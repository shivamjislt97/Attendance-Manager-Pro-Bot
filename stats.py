#!/usr/bin/env python3
"""Attendance calculations - sab kuch DD/MM/YYYY (IST) ke hisaab se."""
from datetime import date, timedelta
from zoneinfo import ZoneInfo

import config

_TZ = ZoneInfo(config.TZ)

MONTHS_HI = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun",
    "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
]


def today() -> date:
    from datetime import datetime
    return datetime.now(_TZ).date()


def _parse_ddmmyyyy(s: str) -> date:
    d, m, y = s.split("/")
    return date(int(y), int(m), int(d))


def sort_dates_desc(dstrs: list[str]) -> list[str]:
    """DD/MM/YYYY strings ko NEWEST-FIRST (sabse nayi date sabse upar) sort karo.

    NOTE: plain `sorted()` ya SQL `ORDER BY date` STRING-sort hai jo DD/MM/YYYY
    par galat order deta hai ('01/09/2026' string mein '31/08/2026' se CHHOTA
    hai, par date mein BADA hai). Isliye hamesha real date parse karke sort.
    """
    def _key(s: str) -> date:
        try:
            return _parse_ddmmyyyy(s)
        except Exception:
            return date.min

    return sorted(dstrs, key=_key, reverse=True)


def fmt(d: date) -> str:
    return d.strftime("%d/%m/%Y")


def _registered_date(student_row) -> date | None:
    """students.registered_at (sqlite 'YYYY-MM-DD HH:MM:SS') se date nikaalo."""
    if student_row is None:
        return None
    raw = student_row["registered_at"]
    if not raw:
        return None
    y, m, d = raw.split("-")[:3]
    return date(int(y), int(m), int(d.split(" ")[0]))


def is_sunday(d: date) -> bool:
    return d.weekday() == 6


def college_open_dates(student_row, upto: date | None = None) -> list[date]:
    """
    Registration date se aaj (ya upto) tak ke saare 'college khula' din:
    SUNDAY chhod kar aur holiday_notices mein saved chhutti chhod kar.
    """
    import database as db

    reg = _registered_date(student_row)
    if reg is None:
        return []
    end = upto or today()
    holidays = {r["date"] for r in db.get_all_holidays()}
    out = []
    d = reg
    while d <= end:
        if not is_sunday(d) and fmt(d) not in holidays:
            out.append(d)
        d += timedelta(days=1)
    return out


def college_closed_dates(student_row, upto: date | None = None) -> list[date]:
    """Registration se aaj tak: saare SUNDAY + saved holidays."""
    import database as db

    reg = _registered_date(student_row)
    if reg is None:
        return []
    end = upto or today()
    holidays = {r["date"] for r in db.get_all_holidays()}
    out = []
    d = reg
    while d <= end:
        if is_sunday(d) or fmt(d) in holidays:
            out.append(d)
        d += timedelta(days=1)
    return out


def compute_stats(chat_id: str, month: tuple[int, int] | None = None) -> dict:
    """
    Ek student ke saare numbers.
    month=(yyyy, mm) doge toh sirf us mahine ka record.
    """
    import database as db

    stu = db.get_student(chat_id)
    if stu is None:
        return {}

    open_days = college_open_dates(stu)
    if month:
        yyyy, mm = month
        open_days = [d for d in open_days if d.year == yyyy and d.month == mm]

    open_set = {fmt(d) for d in open_days}

    history = db.get_attendance_history(chat_id)
    present, chutti, absent = [], [], []
    for row in history:
        dstr = row["date"]
        if dstr not in open_set:
            continue  # band din ki entry count nahi hogi
        if month:
            d = _parse_ddmmyyyy(dstr)
            if not (d.year == month[0] and d.month == month[1]):
                continue
        status = row["status"]
        if status == "PRESENT":
            present.append(dstr)
        elif status == "CHHUTTI":
            chutti.append(dstr)
        elif status == "ABSENT":
            absent.append(dstr)

    # Date lists hamesha NEWEST-FIRST (latest date sabse upar) —
    # DD/MM/YYYY par string-sort galat order deta tha (01/09 upar, 31/08 niche).
    present = sort_dates_desc(present)
    chutti = sort_dates_desc(chutti)
    absent = sort_dates_desc(absent)

    worked = len(open_days)
    marked = len(present) + len(chutti) + len(absent)
    percent = (len(present) / worked * 100) if worked else 0.0

    return {
        "naam": stu["naam"] or "-",
        "branch": stu["branch"] or "-",
        "year": stu["year"] or "-",
        "roll_no": stu["roll_no"] or "-",
        "unique_id": stu["unique_id"] or "-",
        "college_open": worked,
        "college_closed": len(college_closed_dates(stu)),
        "present": len(present),
        "chutti": len(chutti),
        "absent": len(absent),
        "percent": round(percent, 1),
        "present_dates": present,
        "absent_dates": absent,
        "chutti_dates": chutti,
        "month": month,
    }


def stats_message(s: dict, title: str = "📊 ATTENDANCE REPORT") -> str:
    lines = [
        f"{title}",
        f"👤 {s['naam']}  |  {s['branch']}  |  {s['year']}  |  Roll: {s['roll_no']}",
        "",
        f"🎒 College khule din : {s['college_open']}",
        f"🔒 College band din  : {s['college_closed']}",
        f"✅ Present           : {s['present']}",
        f"😁 Chutti (self)     : {s['chutti']}",
        f"🚫 Absent            : {s['absent']}",
        f"📊 Attendance        : {s['percent']}%",
    ]
    if s["month"]:
        yyyy, mm = s["month"]
        lines.insert(1, f"🗓️ Mahina: {MONTHS_HI[mm - 1]} {yyyy}")
    return "\n".join(lines)