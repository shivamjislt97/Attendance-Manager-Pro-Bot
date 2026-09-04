#!/usr/bin/env python3
"""Attendance Bot — HTTP API (Android app ke liye).

Usi attendance.db par chalta hai jis par Telegram bot chalta hai.
Bot untouched rehta hai — dono same database.py / stats.py reuse karte hain.

Run (alag command, bot se independent):
    ./start_api.sh        (port 8000, logs/api.log)

Auth: POST /login {unique_id, roll_no} -> X-Token header har request par.
"""
import io
import os
import secrets
import hashlib
import sqlite3
import time
from datetime import date, timedelta
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

import config
import database as db
import stats as stats_mod

HERE = os.path.dirname(os.path.abspath(__file__))
API_PORT = int(os.environ.get("API_PORT", "8000"))

app = FastAPI(title="Attendance API", version="1.0")

# Web UI (phone/browser) kahin se bhi khule — CORS open + /app par static
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)
_WEB_DIR = os.path.join(HERE, "web")


class _CachedStatic(StaticFiles):
    """Versioned assets immutable-cache karo (?v= wali), HTML fresh rakho."""

    async def get_response(self, path, scope):
        resp = await super().get_response(path, scope)
        if path.endswith((".js", ".css", ".woff2")):
            resp.headers["Cache-Control"] = "public, max-age=31536000, immutable"
        else:
            resp.headers["Cache-Control"] = "no-cache"
        return resp


if os.path.isdir(_WEB_DIR):
    app.mount("/app", _CachedStatic(directory=_WEB_DIR, html=True), name="app")


app.add_middleware(GZipMiddleware, minimum_size=500)


# ---------------- startup: WAL + tokens table ----------------
@app.on_event("startup")
def _startup() -> None:
    db.init_db()
    # WAL mode: bot (polling) + API saath me DB use karein, lock-error na aaye
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.execute("PRAGMA journal_mode=WAL;")
        c.execute("PRAGMA busy_timeout=10000;")
        c.execute(
            """CREATE TABLE IF NOT EXISTS api_tokens (
                   token      TEXT PRIMARY KEY,
                   chat_id    TEXT NOT NULL,
                   created_at TEXT DEFAULT (datetime('now'))
               )"""
        )
        c.execute(
            """CREATE TABLE IF NOT EXISTS admin_auth (
                   chat_id    TEXT PRIMARY KEY,
                   pwd_hash   TEXT NOT NULL,
                   updated_at TEXT DEFAULT (datetime('now'))
               )"""
        )
        c.execute(
            """CREATE TABLE IF NOT EXISTS admin_reset (
                   chat_id    TEXT PRIMARY KEY,
                   code_hash  TEXT NOT NULL,
                   expires_at INTEGER NOT NULL,
                   tries      INTEGER NOT NULL DEFAULT 0,
                   created_at INTEGER NOT NULL
               )"""
        )
        c.commit()
    finally:
        c.close()


# ---------------- auth ----------------
class LoginIn(BaseModel):
    unique_id: Optional[str] = None
    roll_no: Optional[str] = None
    password: Optional[str] = None


def _pwd_hash(pw: str, salt: Optional[bytes] = None) -> str:
    """PBKDF2 hash (stdlib) -> 'salt_hex$hash_hex'. Plaintext kabhi store nahi."""
    salt = salt or secrets.token_bytes(16)
    h = hashlib.pbkdf2_hmac("sha256", pw.encode(), salt, 200_000)
    return salt.hex() + "$" + h.hex()


def _pwd_verify(pw: str, stored: str) -> bool:
    try:
        salt_hex, _ = stored.split("$", 1)
        return secrets.compare_digest(_pwd_hash(pw, bytes.fromhex(salt_hex)),
                                      stored)
    except Exception:
        return False


def _admin_row():
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        return c.execute("SELECT * FROM admin_auth WHERE chat_id = ?",
                         (str(config.ADMIN_CHAT_ID),)).fetchone()
    finally:
        c.close()


def _resolve_admin_identity(unique_id: str, roll_no: str):
    """Admin UID/roll verify karo (password ke bina pehchan)."""
    uid, roll = (unique_id or "").strip(), (roll_no or "").strip()
    if not uid and not roll:
        raise HTTPException(status_code=400,
                            detail="UNIQUE ID ya roll number — koi ek do")
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        if uid:
            stu = c.execute("SELECT * FROM students WHERE unique_id = ?",
                            (uid,)).fetchone()
            if stu is None:
                raise HTTPException(status_code=401, detail="UNIQUE ID galat")
        else:
            stu = c.execute("SELECT * FROM students WHERE roll_no = ?"
                            " ORDER BY chat_id", (roll,)).fetchone()
            if stu is None:
                raise HTTPException(status_code=401, detail="Roll galat")
    finally:
        c.close()
    if stu["chat_id"] != str(config.ADMIN_CHAT_ID):
        raise HTTPException(status_code=403, detail="Sirf admin ke liye")
    if roll and str(stu["roll_no"]) != roll:
        raise HTTPException(status_code=401, detail="Roll number match nahi hua")
    return stu


def _get_chat(x_token: Optional[str] = Header(default=None)) -> str:
    if not x_token:
        raise HTTPException(status_code=401, detail="X-Token header missing")
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        row = c.execute("SELECT chat_id FROM api_tokens WHERE token = ?",
                        (x_token,)).fetchone()
    finally:
        c.close()
    if row is None:
        raise HTTPException(status_code=401, detail="Invalid token")
    return row["chat_id"]


def _require_admin(chat_id: str = Depends(_get_chat)) -> str:
    if chat_id != str(config.ADMIN_CHAT_ID):
        raise HTTPException(status_code=403, detail="Admin only")
    return chat_id


@app.get("/health")
def health():
    return {"status": "ok"}


@app.post("/login")
def login(body: LoginIn):
    """Login UNIQUE ID se, Roll number se, ya dono se (koi ek chalega)."""
    uid = (body.unique_id or "").strip()
    roll = (body.roll_no or "").strip()
    if not uid and not roll:
        raise HTTPException(status_code=400,
                            detail="UNIQUE ID ya roll number — koi ek do")
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        if uid:
            stu = c.execute("SELECT * FROM students WHERE unique_id = ?",
                            (uid,)).fetchone()
            if stu is None:
                raise HTTPException(status_code=401, detail="UNIQUE ID galat")
            if roll and str(stu["roll_no"]) != roll:
                raise HTTPException(status_code=401,
                                    detail="Roll number match nahi hua")
        else:
            rows = c.execute("SELECT * FROM students WHERE roll_no = ?"
                             " ORDER BY chat_id", (roll,)).fetchall()
            if not rows:
                raise HTTPException(status_code=401, detail="Roll galat")
            if len(rows) > 1:
                raise HTTPException(status_code=409, detail="Is roll par kai student hain — UNIQUE ID se login karo")
            stu = rows[0]
    finally:
        c.close()
    is_admin = stu["chat_id"] == str(config.ADMIN_CHAT_ID)
    if is_admin:
        # Admin login me password MANDATORY hai (token isse pehle banta hi nahi)
        auth = _admin_row()
        if auth is None:
            raise HTTPException(status_code=401, detail={
                "code": "password_not_set",
                "message": "Pehli baar hai — pehle admin password set karo"})
        if not body.password or not _pwd_verify(body.password, auth["pwd_hash"]):
            raise HTTPException(status_code=401, detail={
                "code": "password_required", "message": "Admin password galat"})
    token = secrets.token_urlsafe(32)
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.execute("INSERT OR REPLACE INTO api_tokens (token, chat_id)"
                  " VALUES (?, ?)", (token, stu["chat_id"]))
        c.commit()
    finally:
        c.close()
    return {"token": token, "naam": stu["naam"], "branch": stu["branch"],
            "year": stu["year"], "is_admin": is_admin}


class SetPwIn(BaseModel):
    unique_id: Optional[str] = None
    roll_no: Optional[str] = None
    password: str


class ForgotIn(BaseModel):
    unique_id: Optional[str] = None
    roll_no: Optional[str] = None


class ResetPwIn(BaseModel):
    unique_id: Optional[str] = None
    roll_no: Optional[str] = None
    code: str
    new_password: str


def _check_pw_policy(pw: str) -> None:
    if not (4 <= len(pw) <= 40):
        raise HTTPException(status_code=400,
                            detail="Password 4-40 characters ka ho")


@app.post("/admin/set-password")
def set_password(body: SetPwIn, x_token: Optional[str] = Header(default=None)):
    """Pehli baar (bina password ke, UID/roll pehchan par) ya logged-in admin
    X-Token se password set/badlo."""
    _check_pw_policy(body.password or "")
    auth = _admin_row()
    if auth is None:
        # First-time: admin UID/roll se pehchan (password abhi hai hi nahi)
        _resolve_admin_identity(body.unique_id or "", body.roll_no or "")
    else:
        # Badalna hai to logged-in admin token chahiye
        if not x_token:
            raise HTTPException(status_code=401, detail={
                "code": "password_required",
                "message": "Pehle admin login karo"})
        if _get_chat(x_token) != str(config.ADMIN_CHAT_ID):
            raise HTTPException(status_code=403, detail="Sirf admin ke liye")
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.execute("INSERT OR REPLACE INTO admin_auth (chat_id, pwd_hash,"
                  " updated_at) VALUES (?, ?, datetime('now'))",
                  (str(config.ADMIN_CHAT_ID), _pwd_hash(body.password)))
        c.commit()
    finally:
        c.close()
    return {"ok": True}


RESET_COOLDOWN = 300   # dobara code 5 min baad
RESET_TTL = 600        # code 10 min valid
RESET_MAX_TRIES = 5


@app.post("/admin/forgot-password")
async def forgot_password(body: ForgotIn):
    """Reset code Telegram admin chat par bhejo (UID/roll pehchan ke baad)."""
    _resolve_admin_identity(body.unique_id or "", body.roll_no or "")
    now = int(time.time())
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        old = c.execute("SELECT * FROM admin_reset WHERE chat_id = ?",
                        (str(config.ADMIN_CHAT_ID),)).fetchone()
        if old and now - old["created_at"] < RESET_COOLDOWN:
            raise HTTPException(status_code=429, detail={
                "code": "cooldown",
                "message": "Code abhi bheja tha — 5 min baad try karo"})
        code = f"{secrets.randbelow(900000) + 100000}"
        c.execute("INSERT OR REPLACE INTO admin_reset"
                  " (chat_id, code_hash, expires_at, tries, created_at)"
                  " VALUES (?, ?, ?, 0, ?)",
                  (str(config.ADMIN_CHAT_ID),
                   hashlib.sha256(code.encode()).hexdigest(),
                   now + RESET_TTL, now))
        c.commit()
    finally:
        c.close()
    try:
        from telegram import Bot
        await Bot(token=config.BOT_TOKEN).send_message(
            chat_id=int(config.ADMIN_CHAT_ID),
            text=f"🔑 Password reset code: {code}\n⏰ 10 min valid hai.")
    except Exception:
        raise HTTPException(status_code=502, detail={
            "code": "send_fail",
            "message": "Telegram par code nahi gaya, dobara try karo"})
    return {"ok": True}


@app.post("/admin/reset-password")
def reset_password(body: ResetPwIn):
    """Telegram code verify karke naya password set karo."""
    _resolve_admin_identity(body.unique_id or "", body.roll_no or "")
    _check_pw_policy(body.new_password or "")
    now = int(time.time())
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        row = c.execute("SELECT * FROM admin_reset WHERE chat_id = ?",
                        (str(config.ADMIN_CHAT_ID),)).fetchone()
        if row is None:
            raise HTTPException(status_code=400, detail={
                "code": "no_code", "message": "Pehle reset code mangwao"})
        if row["tries"] >= RESET_MAX_TRIES or now > row["expires_at"]:
            c.execute("DELETE FROM admin_reset WHERE chat_id = ?",
                      (str(config.ADMIN_CHAT_ID),))
            c.commit()
            raise HTTPException(status_code=401, detail={
                "code": "expired", "message": "Code expire — naya mangwao"})
        if not secrets.compare_digest(
                hashlib.sha256((body.code or '').strip().encode()).hexdigest(),
                row["code_hash"]):
            c.execute("UPDATE admin_reset SET tries = tries + 1"
                      " WHERE chat_id = ?", (str(config.ADMIN_CHAT_ID),))
            c.commit()
            raise HTTPException(status_code=401, detail={
                "code": "wrong_code", "message": "Code galat hai"})
        c.execute("INSERT OR REPLACE INTO admin_auth (chat_id, pwd_hash,"
                  " updated_at) VALUES (?, ?, datetime('now'))",
                  (str(config.ADMIN_CHAT_ID), _pwd_hash(body.new_password)))
        c.execute("DELETE FROM admin_reset WHERE chat_id = ?",
                  (str(config.ADMIN_CHAT_ID),))
        c.commit()
    finally:
        c.close()
    return {"ok": True}


class RegisterIn(BaseModel):
    naam: str
    branch: str
    year: str
    roll_no: str


@app.post("/register")
def register(body: RegisterIn):
    """App se naya registration (bot wali validation). Chat_id = app:UUID."""
    import uuid as _uuid
    naam = (body.naam or "").strip()[:50]
    branch = (body.branch or "").strip().upper()
    year = (body.year or "").strip()
    roll = (body.roll_no or "").strip()[:20]
    if not naam:
        raise HTTPException(status_code=400, detail="Naam likho")
    if branch not in ("CS", "IT", "EC", "ME"):
        raise HTTPException(status_code=400, detail="Branch CS/IT/EC/ME ho")
    if year not in ("1st Year", "2nd Year", "3rd Year", "4th Year"):
        raise HTTPException(status_code=400, detail="Year 1st-4th Year ho")
    if not roll:
        raise HTTPException(status_code=400, detail="Roll number likho")
    chat_id = "app:" + _uuid.uuid4().hex[:12]
    uid = "STU-" + _uuid.uuid4().hex[:8].upper()
    db.save_student_field(chat_id, "naam", naam)
    db.save_student_field(chat_id, "branch", branch)
    db.save_student_field(chat_id, "year", year)
    db.save_student_field(chat_id, "roll_no", roll)
    with db._LOCK, db._conn() as c:
        c.execute("UPDATE students SET unique_id = ? WHERE chat_id = ?",
                  (uid, chat_id))
    # Admin alert (best-effort, direct Telegram — fail-safe)
    try:
        import bot as bot_mod
        from telegram import Bot
        from types import SimpleNamespace
        import asyncio as _aio

        async def _alert():
            await bot_mod.notify_admin_new_registration(
                {"naam": naam, "branch": branch, "year": year,
                 "roll_no": roll, "unique_id": uid, "chat_id": chat_id},
                SimpleNamespace(bot=Bot(token=config.BOT_TOKEN)))
        _aio.run(_alert())
    except Exception as e:
        import logging
        logging.getLogger("attendance-api").warning("reg-alert fail: %s", e)
    try:
        import bot as bot_mod
        bot_mod.queue_backup_push("registration-app")
    except Exception:
        pass
    return {"ok": True, "unique_id": uid, "naam": naam, "branch": branch,
            "year": year, "roll_no": roll}


# ---------------- calendar + stats (bot logic reuse) ----------------
def _month_cells(chat_id: str, year: int, month: int) -> dict:
    """Har date -> marker: present/chutti/absent/holiday/sunday/future/none."""
    stu = db.get_student(chat_id)
    if stu is None:
        raise HTTPException(status_code=404, detail="Student nahi mila")
    today = stats_mod.today()
    first = date(year, month, 1)
    last = (date(year + 1, 1, 1) - timedelta(days=1)
            if month == 12 else date(year, month + 1, 1) - timedelta(days=1))
    open_set = {stats_mod.fmt(d)
                for d in stats_mod.college_open_dates(stu, upto=last)}
    out: dict[str, dict] = {}
    d = first
    while d <= last:
        ds = stats_mod.fmt(d)
        hol = db.get_holiday(ds)
        row = db.get_attendance(chat_id, ds)
        if d > today:
            marker = "future"
        elif hol is not None or stats_mod.is_sunday(d):
            marker = "holiday"
        elif ds not in open_set:
            marker = "closed"
        elif row is None:
            marker = "none"
        else:
            marker = {"PRESENT": "present", "CHHUTTI": "chutti",
                      "ABSENT": "absent", "HOLIDAY": "holiday"}.get(
                          row["status"], "none")
        out[ds] = {"marker": marker,
                   "status": row["status"] if row else None}
        d += timedelta(days=1)
    return out


@app.get("/calendar")
def calendar(year: int, month: int, chat_id: str = Depends(_get_chat)):
    if not (1 <= month <= 12 and 2000 <= year <= 2100):
        raise HTTPException(status_code=400, detail="year/month galat")
    return {"days": _month_cells(chat_id, year, month)}


@app.get("/stats")
def stats(year: Optional[int] = None, month: Optional[int] = None,
          chat_id: str = Depends(_get_chat)):
    m = (year, month) if (year and month) else None
    s = stats_mod.compute_stats(chat_id, m)
    if not s:
        raise HTTPException(status_code=404, detail="Stats nahi mila")
    return s


# ---------------- attendance mark (bot wale rules) ----------------
class AttIn(BaseModel):
    status: str  # PRESENT | CHHUTTI


@app.post("/attendance")
def mark_att(body: AttIn, chat_id: str = Depends(_get_chat)):
    st = body.status.strip().upper()
    if st not in ("PRESENT", "CHHUTTI"):
        raise HTTPException(status_code=400, detail="status PRESENT/CHHUTTI ho")
    day = stats_mod.fmt(stats_mod.today())
    t = stats_mod.today()
    if stats_mod.is_sunday(t) or db.is_holiday(day):
        raise HTTPException(status_code=409, detail="Aaj college band hai")
    if db.get_attendance(chat_id, day):
        raise HTTPException(status_code=409, detail="Aaj ki attendance lag chuki")
    db.mark_attendance(chat_id, st, "app")
    try:
        import bot as bot_mod
        bot_mod.queue_backup_push("attendance-app")
    except Exception:
        pass
    return {"ok": True, "date": day, "status": st}


@app.get("/record")
def record(date: str, chat_id: str = Depends(_get_chat)):
    import re
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", date):
        raise HTTPException(status_code=400, detail="DD/MM/YYYY bhejo")
    row = db.get_attendance(chat_id, date)
    hol = db.get_holiday(date)
    return {"date": date,
            "status": row["status"] if row else None,
            "marked_by": row["marked_by"] if row else None,
            "holiday": hol is not None,
            "has_proof": hol is not None}


@app.get("/holiday-proof")
def holiday_proof(date: str, thumb: int = 0,
                  chat_id: str = Depends(_get_chat)):
    import re
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", date):
        raise HTTPException(status_code=400, detail="DD/MM/YYYY bhejo")
    hol = db.get_holiday(date)
    if hol is None:
        raise HTTPException(status_code=404, detail="Us date par holiday nahi")
    raw = bytes(hol["notice"]) if hol["notice"] else b""
    if hol["type"] == "image":
        if thumb:
            try:
                from PIL import Image
                im = Image.open(io.BytesIO(raw))
                im.thumbnail((800, 800))
                buf = io.BytesIO()
                im.convert("RGB").save(buf, "JPEG", quality=70)
                return Response(content=buf.getvalue(), media_type="image/jpeg")
            except Exception:
                pass
        return Response(content=raw, media_type="image/jpeg")
    return {"date": date, "proof": raw.decode(errors="replace")}


@app.get("/notices")
def notices(chat_id: str = Depends(_get_chat)):
    """Home window: latest 5 holiday notices + meri latest 5 activity."""
    import re

    def _key(d: str):
        try:
            return stats_mod._parse_ddmmyyyy(d)
        except Exception:
            return date.min

    hols = sorted(db.get_all_holidays(), key=lambda r: _key(r["date"]),
                  reverse=True)[:5]
    notices_out = []
    for h in hols:
        try:
            sched = bool(h["notify_day"]) and not h["announced"]
        except Exception:
            sched = False
        notices_out.append({
            "date": h["date"], "type": h["type"], "has_proof": True,
            "tag": ("📅 notice " + h["notify_day"] + " ko aayega"
                    if sched else "🏖️ chhutti thi"),
        })
    rows = sorted(db.get_attendance_history(chat_id),
                  key=lambda r: _key(r["date"]), reverse=True)[:5]
    emo = {"PRESENT": "✅", "CHHUTTI": "😁", "ABSENT": "🚫", "HOLIDAY": "🏖️"}
    activity = [{"date": r["date"], "status": r["status"],
                 "marked_by": r["marked_by"],
                 "emoji": emo.get(r["status"], "")} for r in rows]
    return {"notices": notices_out, "activity": activity}


# ---------------- chat (bot jaisa — 9 menu + custom date) ----------------
class ChatIn(BaseModel):
    text: str


@app.post("/chat")
def chat(body: ChatIn, chat_id: str = Depends(_get_chat)):
    import bot as bot_mod
    import re
    txt = (body.text or "").strip()
    m = re.match(r"^(\d{2}/\d{2}/\d{4})$", txt)
    if m:
        row = db.get_attendance(chat_id, txt)
        hol = db.get_holiday(txt)
        parts = [f"RECORD FOR {txt}:"]
        if hol:
            parts.append("Us din COLLEGE BAND tha!")
        if row:
            parts.append(f"Status: {row['status']} (by {row['marked_by']})")
        elif not hol:
            parts.append("Us din koi record nahi mila.")
        return {"reply": "\n".join(parts), "has_proof": hol is not None,
                "proof_date": txt if hol else None}
    for i, b in enumerate(bot_mod.MENU_BUTTONS[:8]):
        if txt == str(i) or txt.lower() in b.lower():
            import contextlib
            with contextlib.suppress(Exception):
                return {"reply": bot_mod.menu_result_text(chat_id, b)}
    return {"reply": "0-7 me se number bhejo (attendance %, gaya din, chhutti, "
                     "khula/band din, mahina, absent/present dates) ya "
                     "DD/MM/YYYY date bhejo.",
            "options": bot_mod.MENU_BUTTONS[:8]}


# ---------------- admin ----------------
@app.get("/admin/count")
def admin_count(_admin: str = Depends(_require_admin)):
    rows = db.get_all_students()
    by_branch: dict[str, int] = {}
    by_year: dict[str, int] = {}
    matrix: dict[str, dict[str, int]] = {}
    for r in rows:
        b, y = r["branch"] or "-", r["year"] or "-"
        by_branch[b] = by_branch.get(b, 0) + 1
        by_year[y] = by_year.get(y, 0) + 1
        matrix.setdefault(b, {}).update(
            {y: matrix.setdefault(b, {}).get(y, 0) + 1})
    return {"total": len(rows), "by_branch": by_branch,
            "by_year": by_year, "matrix": matrix}


@app.get("/admin/lookup")
def admin_lookup(key: str, _admin: str = Depends(_require_admin)):
    stu = (db.get_student(key.strip())
           or db.get_student_by_roll(key.strip())
           or db.get_student_by_unique_id(key.strip()))
    if stu is None:
        raise HTTPException(status_code=404, detail="Student nahi mila")
    s = stats_mod.compute_stats(stu["chat_id"])
    return {"student": dict(stu), "stats": s}


@app.post("/admin/holiday")
async def admin_holiday(date: str = Form(...), proof_text: str = Form(""),
                        proof: Optional[UploadFile] = File(None),
                        dry_run: bool = False,
                        _admin: str = Depends(_require_admin)):
    import re
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", date):
        raise HTTPException(status_code=400, detail="DD/MM/YYYY bhejo")
    try:
        stats_mod._parse_ddmmyyyy(date)
    except Exception:
        raise HTTPException(status_code=400, detail="Date galat hai")
    if proof is not None:
        raw = await proof.read()
        ntype = "image"
        ptext = proof_text.strip()
    else:
        raw = proof_text.strip().encode() or date.encode()
        ntype = "text"
        ptext = proof_text.strip()
    import bot as bot_mod
    future = bot_mod._cmp_day(date, stats_mod.fmt(stats_mod.today())) > 0
    preview = bot_mod.holiday_user_text(date, ntype, ptext, raw,
                                        advance=future)
    if dry_run:
        # ZERO side-effect: no save/export/HOLIDAY-mark/broadcast/backup
        return {"ok": True, "dry_run": True, "date": date, "type": ntype,
                "preview": preview,
                "scheduled_for": bot_mod.day_before(date) if future else None}
    db.save_holiday(date, raw, ntype, config.ADMIN_CHAT_ID)
    bot_mod.export_holiday_proof_file(date, ntype, raw)
    n_upd = bot_mod.mark_holiday_attendance(date)
    if future:
        # AUTO RULE: future date -> schedule, NO instant broadcast.
        # Marking/export/backup abhi (accuracy intact).
        nday = bot_mod.day_before(date)
        db.set_holiday_schedule(date, nday)
        try:
            bot_mod.queue_backup_push("holiday-app")
        except Exception:
            pass
        return {"ok": True, "date": date, "type": ntype,
                "updated": n_upd, "broadcast_ok": 0, "broadcast_fail": 0,
                "scheduled_for": nday,
                "preview": preview}
    # Telegram broadcast (direct Bot API — polling se conflict nahi hota)
    ok, fail = 0, 0
    try:
        from telegram import Bot
        from types import SimpleNamespace
        b = Bot(token=config.BOT_TOKEN)
        ok, fail = await bot_mod.broadcast_holiday(
            date, ntype, raw, ptext, SimpleNamespace(bot=b))
        import logging as _lg
        _lg.getLogger("attendance-api").info(
            "holiday declare %s type=%s updated=%d broadcast_ok=%d fail=%d",
            date, ntype, n_upd, ok, fail)
    except Exception as e:
        import logging
        logging.getLogger("attendance-api").warning("broadcast fail: %s", e)
    try:
        bot_mod.queue_backup_push("holiday-app")
    except Exception:
        pass
    return {"ok": True, "date": date, "type": ntype,
            "updated": n_upd, "broadcast_ok": ok, "broadcast_fail": fail}


class RecallIn(BaseModel):
    date: str
    batch: Optional[str] = None


def _recall_report(deleted: int, failed: int):
    if (deleted, failed) == (-1, -1):
        raise HTTPException(status_code=429, detail={
            "code": "cooldown", "message": "60 sec rukkar dobara try karo"})
    if (deleted, failed) == (-2, -2):
        raise HTTPException(status_code=403, detail={
            "code": "exhausted", "message": "Attempts khatam (max 3)"})
    return deleted, failed


@app.post("/admin/recall")
async def admin_recall(body: RecallIn,
                       _admin: str = Depends(_require_admin)):
    """Holiday (date) ya general (batch) broadcast recall — admin-only."""
    import bot as bot_mod
    from telegram import Bot
    b = Bot(token=config.BOT_TOKEN)
    if body.batch:
        if not __import__("re").match(r"^g\d{14}$", body.batch.strip()):
            raise HTTPException(status_code=400, detail="Batch id galat")
        deleted, failed = await bot_mod.recall_broadcast_batch(
            body.batch.strip(), b)
        _recall_report(deleted, failed)
        return {"ok": True, "batch": body.batch.strip(),
                "deleted": deleted, "failed": failed}
    import re
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", (body.date or "").strip()):
        raise HTTPException(status_code=400, detail="DD/MM/YYYY bhejo")
    deleted, failed = await bot_mod.recall_holiday_broadcast(
        body.date.strip(), b)
    if (deleted, failed) == (-3, -3):
        return {"ok": True, "date": body.date.strip(),
                "schedule_cancelled": True, "deleted": 0, "failed": 0}
    _recall_report(deleted, failed)
    return {"ok": True, "date": body.date.strip(),
            "deleted": deleted, "failed": failed}


@app.get("/admin/broadcasts")
def admin_broadcasts(_admin: str = Depends(_require_admin)):
    """Recent general batches (recall list ke liye)."""
    rows = db.list_broadcast_batches(10)
    return {"batches": [
        {"batch": r["batch"], "day": r["day"], "count": r["n"],
         "at": r["at"]} for r in rows]}


@app.post("/admin/broadcast")
async def admin_broadcast(message: str = Form(""),
                          branch: str = Form(""),
                          year: str = Form(""),
                          photo: Optional[UploadFile] = File(None),
                          dry_run: bool = False,
                          _admin: str = Depends(_require_admin)):
    """General broadcast (filtered, admin-only). Text required, photo optional."""
    import bot as bot_mod
    text = (message or "").strip()
    if not text:
        raise HTTPException(status_code=400, detail="Message likho")
    if len(text) > 1500:
        raise HTTPException(status_code=400, detail="Message 1500 chars max")
    branch = (branch or "").strip().upper()
    year = (year or "").strip()
    if branch and branch not in ("CS", "IT", "EC", "ME"):
        raise HTTPException(status_code=400, detail="Branch CS/IT/EC/ME ya khaali")
    if year and year not in ("1st Year", "2nd Year", "3rd Year", "4th Year"):
        raise HTTPException(status_code=400, detail="Year 1st-4th ya khaali")
    rows = [r for r in db.get_all_students()
            if (not branch or (r["branch"] or "-") == branch)
            and (not year or (r["year"] or "-") == year)]
    full = "📢 " + text
    if dry_run:
        return {"ok": True, "dry_run": True, "recipients": len(rows),
                "to": [r["naam"] for r in rows],
                "preview": full + (" [+photo]" if photo is not None else "")}
    import time as _time
    batch = "g" + _time.strftime("%Y%m%d%H%M%S", _time.gmtime())
    raw = await photo.read() if photo is not None else None
    if raw is not None and len(raw) > 5 * 1024 * 1024:
        raise HTTPException(status_code=400, detail="Photo 5MB max")
    from telegram import Bot
    ok, fail = await bot_mod.broadcast_custom(
        full, raw, rows, Bot(token=config.BOT_TOKEN), batch)
    import logging as _lg
    _lg.getLogger("attendance-api").info(
        "general broadcast %s to=%d ok=%d fail=%d", batch, len(rows), ok, fail)
    try:
        bot_mod.queue_backup_push("broadcast-app")
    except Exception:
        pass
    return {"ok": True, "batch": batch, "recipients": len(rows),
            "sent": ok, "failed": fail}
