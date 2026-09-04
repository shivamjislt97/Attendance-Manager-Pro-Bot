#!/usr/bin/env python3
"""SQLite database layer - har record chat_id ke saath (design doc ke mutabik)."""
import sqlite3
import threading
from datetime import date, datetime
from zoneinfo import ZoneInfo

import config

_TZ = ZoneInfo(config.TZ)
_LOCK = threading.Lock()


def _now() -> datetime:
    return datetime.now(_TZ)


def _conn() -> sqlite3.Connection:
    conn = sqlite3.connect(config.DB_PATH)
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_db() -> None:
    """Tables banao (agar nahi hain)."""
    with _LOCK, _conn() as c:
        c.executescript(
            """
            CREATE TABLE IF NOT EXISTS students (
                chat_id    TEXT PRIMARY KEY,
                naam       TEXT,
                branch     TEXT,
                roll_no    TEXT,
                year       TEXT,
                unique_id  TEXT UNIQUE,
                registered_at TEXT DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_students_roll
                ON students(roll_no);
            CREATE INDEX IF NOT EXISTS idx_students_branch
                ON students(branch);

            CREATE TABLE IF NOT EXISTS attendance (
                date       TEXT,
                chat_id    TEXT,
                status     TEXT NOT NULL,
                marked_by  TEXT NOT NULL DEFAULT 'self',
                PRIMARY KEY (date, chat_id),
                FOREIGN KEY (chat_id) REFERENCES students(chat_id)
            );
            CREATE INDEX IF NOT EXISTS idx_att_chat
                ON attendance(chat_id);

            CREATE TABLE IF NOT EXISTS holiday_notices (
                date       TEXT PRIMARY KEY,
                notice     BLOB,
                type       TEXT NOT NULL,
                saved_by   TEXT NOT NULL,
                notify_day TEXT,
                announced  INTEGER NOT NULL DEFAULT 0
            );

            CREATE TABLE IF NOT EXISTS broadcast_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                kind       TEXT NOT NULL,
                day        TEXT NOT NULL,
                chat_id    TEXT NOT NULL,
                message_id INTEGER NOT NULL,
                sent_at    TEXT DEFAULT (datetime('now'))
            );
            CREATE INDEX IF NOT EXISTS idx_bcast_day
                ON broadcast_log(kind, day);

            CREATE TABLE IF NOT EXISTS recall_log (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                day        TEXT NOT NULL,
                deleted    INTEGER NOT NULL DEFAULT 0,
                failed     INTEGER NOT NULL DEFAULT 0,
                at         TEXT DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS role_audit (
                id         INTEGER PRIMARY KEY AUTOINCREMENT,
                actor_chat_id  TEXT NOT NULL,
                target_chat_id TEXT NOT NULL,
                action     TEXT NOT NULL,
                at         TEXT DEFAULT (datetime('now'))
            );
            """
        )
        # Migration: purane DB me 'year' column nahi hoga -> add karo
        cols = {r["name"] for r in c.execute("PRAGMA table_info(students)")}
        if "year" not in cols:
            c.execute("ALTER TABLE students ADD COLUMN year TEXT")
        # Migration: scheduled-holiday columns (notify_day/announced)
        hcols = {r["name"] for r in c.execute("PRAGMA table_info(holiday_notices)")}
        if "notify_day" not in hcols:
            c.execute("ALTER TABLE holiday_notices ADD COLUMN notify_day TEXT")
        if "announced" not in hcols:
            c.execute("ALTER TABLE holiday_notices ADD COLUMN announced INTEGER NOT NULL DEFAULT 0")
        # Migration: broadcast batch column (general broadcast recall)
        bcols = {r["name"] for r in c.execute("PRAGMA table_info(broadcast_log)")}
        if "batch" not in bcols:
            c.execute("ALTER TABLE broadcast_log ADD COLUMN batch TEXT")
        # Migration: students.role (admin RBAC, master immutable)
        scols = {r["name"] for r in c.execute("PRAGMA table_info(students)")}
        if "role" not in scols:
            c.execute("ALTER TABLE students ADD COLUMN role TEXT DEFAULT 'student' CHECK(role IN ('student','admin'))")
            c.execute("UPDATE students SET role = 'student' WHERE role IS NULL")
            # Master seed — Sabse Bade Malik hamesha admin
            c.execute("UPDATE students SET role = 'admin' WHERE chat_id = '6267031612'")
        else:
            # Ensure master stays admin even if someone flipped it
            c.execute("UPDATE students SET role = 'admin' WHERE chat_id = '6267031612'")


# ---------------- students ----------------

def get_student(chat_id: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM students WHERE chat_id = ?", (str(chat_id),)
        ).fetchone()


def get_student_by_roll(roll_no: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM students WHERE roll_no = ? ORDER BY chat_id",
            (str(roll_no),),
        ).fetchone()


def get_student_by_unique_id(uid: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM students WHERE unique_id = ?", (uid,)
        ).fetchone()


def get_all_students():
    with _LOCK, _conn() as c:
        return c.execute("SELECT * FROM students").fetchall()


def save_student_field(chat_id: str, field: str, value: str) -> None:
    """chat_id ko PK maan kar field save/update karo (upsert)."""
    assert field in ("naam", "branch", "roll_no", "year"), field
    chat_id = str(chat_id)
    with _LOCK, _conn() as c:
        row = c.execute(
            "SELECT 1 FROM students WHERE chat_id = ?", (chat_id,)
        ).fetchone()
        if row is None:
            c.execute(
                f"INSERT INTO students (chat_id, {field}) VALUES (?, ?)",
                (chat_id, value),
            )
        else:
            c.execute(
                f"UPDATE students SET {field} = ? WHERE chat_id = ?",
                (value, chat_id),
            )


def delete_student(chat_id: str) -> None:
    with _LOCK, _conn() as c:
        c.execute(
            "DELETE FROM attendance WHERE chat_id = ?", (str(chat_id),)
        )
        c.execute("DELETE FROM students WHERE chat_id = ?", (str(chat_id),))


# ---------------- attendance ----------------

def _today_str() -> str:
    return _now().strftime("%d/%m/%Y")


def mark_attendance(
    chat_id: str, status: str, marked_by: str = "self", day: str | None = None
) -> None:
    day = day or _today_str()
    with _LOCK, _conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO attendance (date, chat_id, status, marked_by)"
            " VALUES (?, ?, ?, ?)",
            (day, str(chat_id), status, marked_by),
        )


def get_attendance(chat_id: str, day: str | None = None):
    day = day or _today_str()
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM attendance WHERE chat_id = ? AND date = ?",
            (str(chat_id), day),
        ).fetchone()


def get_attendance_history(chat_id: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT date, status, marked_by FROM attendance WHERE chat_id = ?"
            " ORDER BY date",
            (str(chat_id),),
        ).fetchall()


def get_absent_dates(chat_id: str):
    with _LOCK, _conn() as c:
        return [
            r["date"]
            for r in c.execute(
                "SELECT date FROM attendance WHERE chat_id = ? AND status = ?"
                " ORDER BY date",
                (str(chat_id), "ABSENT"),
            )
        ]


def get_present_dates(chat_id: str):
    with _LOCK, _conn() as c:
        return [
            r["date"]
            for r in c.execute(
                "SELECT date FROM attendance WHERE chat_id = ? AND status = ?"
                " ORDER BY date",
                (str(chat_id), "PRESENT"),
            )
        ]


# ---------------- holidays ----------------

def save_holiday(day: str, notice: bytes | None, ntype: str, saved_by: str) -> None:
    with _LOCK, _conn() as c:
        c.execute(
            "INSERT OR REPLACE INTO holiday_notices (date, notice, type, saved_by)"
            " VALUES (?, ?, ?, ?)",
            (day, notice, ntype, str(saved_by)),
        )


def get_holiday(day: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM holiday_notices WHERE date = ?", (day,)
        ).fetchone()


def set_holiday_schedule(day: str, notify_day: str | None) -> None:
    """Advance-notice schedule set/clear karo (announced reset ke saath)."""
    with _LOCK, _conn() as c:
        c.execute("UPDATE holiday_notices SET notify_day = ?, announced = 0"
                  " WHERE date = ?", (notify_day, day))


def mark_holiday_announced(day: str) -> None:
    with _LOCK, _conn() as c:
        c.execute("UPDATE holiday_notices SET announced = 1 WHERE date = ?",
                  (day,))


def get_due_advance_notices(today: str):
    """Jin holidays ka advance notice aaj jana hai (notify_day=today, unsent)."""
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT * FROM holiday_notices WHERE notify_day = ?"
            " AND announced = 0",
            (today,),
        ).fetchall()


def get_all_holidays():
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT date, type, saved_by, notify_day, announced"
            " FROM holiday_notices ORDER BY date"
        ).fetchall()


def is_holiday(day: str) -> bool:
    return get_holiday(day) is not None


# ---------------- broadcast log + recall audit ----------------

def log_broadcast(kind: str, day: str, chat_id: str, message_id: int,
                  batch: str | None = None) -> None:
    """Broadcast message ID save karo (48h recall window ke liye)."""
    with _LOCK, _conn() as c:
        c.execute(
            "INSERT INTO broadcast_log (kind, day, chat_id, message_id, batch)"
            " VALUES (?, ?, ?, ?, ?)",
            (kind, day, str(chat_id), int(message_id), batch),
        )


def get_broadcast_log(kind: str, day: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT chat_id, message_id FROM broadcast_log"
            " WHERE kind = ? AND day = ? ORDER BY id",
            (kind, day),
        ).fetchall()


def clear_broadcast_log(kind: str, day: str) -> None:
    with _LOCK, _conn() as c:
        c.execute("DELETE FROM broadcast_log WHERE kind = ? AND day = ?",
                  (kind, day))


def get_broadcast_batch(batch: str):
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT chat_id, message_id FROM broadcast_log"
            " WHERE batch = ? ORDER BY id",
            (batch,),
        ).fetchall()


def clear_broadcast_batch(batch: str) -> None:
    with _LOCK, _conn() as c:
        c.execute("DELETE FROM broadcast_log WHERE batch = ?", (batch,))


def list_broadcast_batches(limit: int = 10):
    """Recent general batches: batch, day, count (recall list ke liye)."""
    with _LOCK, _conn() as c:
        return c.execute(
            "SELECT batch, day, COUNT(*) AS n, MAX(sent_at) AS at"
            " FROM broadcast_log WHERE kind = 'general' AND batch IS NOT NULL"
            " GROUP BY batch, day ORDER BY MAX(id) DESC LIMIT ?",
            (limit,),
        ).fetchall()


def log_recall(day: str, deleted: int, failed: int) -> None:
    """Recall attempt audit trail."""
    with _LOCK, _conn() as c:
        c.execute("INSERT INTO recall_log (day, deleted, failed)"
                  " VALUES (?, ?, ?)", (day, deleted, failed))


def get_recall_log(day: str):
    with _LOCK, _conn() as c:
        return c.execute("SELECT * FROM recall_log WHERE day = ?"
                         " ORDER BY id", (day,)).fetchall()


def get_role(chat_id: str) -> str:
    """Role nikalo: master 6267031612 hamesha admin, baki DB se."""
    if str(chat_id) == "6267031612":
        return "admin"
    row = get_student(chat_id)
    if row is None:
        return "student"
    try:
        return row["role"] or "student"
    except Exception:
        return "student"


def is_admin_role(chat_id: str) -> bool:
    return get_role(chat_id) == "admin"


def set_role(target_chat_id: str, role: str, actor_chat_id: str) -> None:
    assert role in ("student", "admin"), role
    target = str(target_chat_id)
    actor = str(actor_chat_id)
    # Master guards — hard block
    if target == "6267031612":
        raise PermissionError("Master admin (6267031612) ko downgrade nahi kar sakte")
    if target == actor and actor == "6267031612":
        raise PermissionError("Master khud ko downgrade nahi kar sakta")
    if role not in ("student", "admin"):
        raise ValueError(role)
    with _LOCK, _conn() as c:
        exists = c.execute("SELECT 1 FROM students WHERE chat_id = ?", (target,)).fetchone()
        if not exists:
            raise LookupError(f"Target chat_id {target} ka student nahi mila")
        c.execute("UPDATE students SET role = ? WHERE chat_id = ?", (role, target))
        c.execute("INSERT INTO role_audit (actor_chat_id, target_chat_id, action) VALUES (?, ?, ?)",
                  (actor, target, f"set:{role}"))


def list_admins():
    with _LOCK, _conn() as c:
        return c.execute("SELECT * FROM students WHERE role = 'admin' OR chat_id = '6267031612' ORDER BY chat_id").fetchall()


def get_role_audit(limit: int = 20):
    with _LOCK, _conn() as c:
        return c.execute("SELECT * FROM role_audit ORDER BY id DESC LIMIT ?", (limit,)).fetchall()
