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
import sqlite3
from datetime import date, timedelta
from typing import Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.middleware.cors import CORSMiddleware
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
if os.path.isdir(_WEB_DIR):
    app.mount("/app", StaticFiles(directory=_WEB_DIR, html=True), name="app")


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
        c.commit()
    finally:
        c.close()


# ---------------- auth ----------------
class LoginIn(BaseModel):
    unique_id: str
    roll_no: str


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
    uid = body.unique_id.strip()
    stu = None
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.row_factory = sqlite3.Row
        stu = c.execute("SELECT * FROM students WHERE unique_id = ?",
                        (uid,)).fetchone()
    finally:
        c.close()
    if stu is None or str(stu["roll_no"]) != body.roll_no.strip():
        raise HTTPException(status_code=401, detail="UNIQUE ID ya roll galat")
    token = secrets.token_urlsafe(32)
    c = sqlite3.connect(config.DB_PATH, timeout=30)
    try:
        c.execute("INSERT OR REPLACE INTO api_tokens (token, chat_id)"
                  " VALUES (?, ?)", (token, stu["chat_id"]))
        c.commit()
    finally:
        c.close()
    return {"token": token, "naam": stu["naam"], "branch": stu["branch"],
            "year": stu["year"],
            "is_admin": stu["chat_id"] == str(config.ADMIN_CHAT_ID)}


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
def holiday_proof(date: str, chat_id: str = Depends(_get_chat)):
    import re
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", date):
        raise HTTPException(status_code=400, detail="DD/MM/YYYY bhejo")
    hol = db.get_holiday(date)
    if hol is None:
        raise HTTPException(status_code=404, detail="Us date par holiday nahi")
    raw = bytes(hol["notice"]) if hol["notice"] else b""
    if hol["type"] == "image":
        return Response(content=raw, media_type="image/jpeg")
    return {"date": date, "proof": raw.decode(errors="replace")}


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
    stu = db.get_student(key.strip()) or db.get_student_by_roll(key.strip())
    if stu is None:
        raise HTTPException(status_code=404, detail="Student nahi mila")
    s = stats_mod.compute_stats(stu["chat_id"])
    return {"student": dict(stu), "stats": s}


@app.post("/admin/holiday")
async def admin_holiday(date: str = Form(...), proof_text: str = Form(""),
                        proof: Optional[UploadFile] = File(None),
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
    db.save_holiday(date, raw, ntype, config.ADMIN_CHAT_ID)
    import bot as bot_mod
    bot_mod.export_holiday_proof_file(date, ntype, raw)
    n_upd = bot_mod.mark_holiday_attendance(date)
    # Telegram broadcast (direct Bot API — polling se conflict nahi hota)
    ok, fail = 0, 0
    try:
        from telegram import Bot
        from types import SimpleNamespace
        b = Bot(token=config.BOT_TOKEN)
        ok, fail = await bot_mod.broadcast_holiday(
            date, ntype, raw, ptext, SimpleNamespace(bot=b))
    except Exception as e:
        import logging
        logging.getLogger("attendance-api").warning("broadcast fail: %s", e)
    try:
        bot_mod.queue_backup_push("holiday-app")
    except Exception:
        pass
    return {"ok": True, "date": date, "type": ntype,
            "updated": n_upd, "broadcast_ok": ok, "broadcast_fail": fail}
