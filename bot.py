#!/usr/bin/env python3
"""
STUDENT ATTENDANCE MANAGER BOT (design doc: ../.lightning_studio/bot design.md)
- Har user CHAT_ID ke saath DB mein
- Roz 8:15 AM IST sawaal, har ghanta reminder, 5 PM cutoff (auto ABSENT)
- Admin (6267031612): respected tone, 3 buttons, holiday notice, record lookup
- 9-button menu sirf registered users ke liye
"""
import asyncio
import io
import logging
import random
import re
import uuid

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, InputFile, Update
from telegram.ext import (
    Application, ApplicationBuilder, CallbackQueryHandler, CommandHandler,
    ContextTypes, ConversationHandler, MessageHandler, filters,
)

import config
import database as db
import stats as stats_mod

logging.basicConfig(
    format="%(asctime)s %(levelname)s %(name)s: %(message)s", level=logging.INFO
)
logging.getLogger("httpx").setLevel(logging.WARNING)
log = logging.getLogger("attendance-bot")

# ---------------- BUTTONS (mood emojis) ----------------
BTN_YES = "😎 HAA KARWANA HAI!"
BTN_NO = "🙅 NHI REHENE DO"
BTN_CS, BTN_IT, BTN_EC, BTN_ME = "🧑‍💻 CS", "💻 IT", "🔌 EC", "⚙️ ME"
BRANCH_MAP = {BTN_CS: "CS", BTN_IT: "IT", BTN_EC: "EC", BTN_ME: "ME"}
BTN_CHANGE_YES, BTN_CHANGE_NO = "✅ HAA", "❌ NHI"
CHANGEABLE = ["naam", "branch", "year", "roll_no"]
BTN_Y1, BTN_Y2, BTN_Y3, BTN_Y4 = (
    "1️⃣ 1st Year", "2️⃣ 2nd Year", "3️⃣ 3rd Year", "4️⃣ 4th Year")
YEAR_MAP = {BTN_Y1: "1st Year", BTN_Y2: "2nd Year",
            BTN_Y3: "3rd Year", BTN_Y4: "4th Year"}
BTN_PRESENT = "😎 PRESENT HU"
BTN_CHHUTTI = "😁 AAJ KI CHHUTTI MAAR LI"
BTN_HOLIDAY = "🏖️ AAJ College ki Chhutti hai"
BTN_NOTICE = "📢 Update College Holiday Notice"
BTN_LOOKUP = "🔍 KISI STUDENT KA RECORD NIKALO"
BTN_MENU = "📋 MENU KHOLO"
CB_MENU_OPEN = "menu:open"
BTN_EXIT = "❌ EXIT"
CB_EXIT = "exit:cancel"

MENU_BUTTONS = [
    "📊 Meri kitni percent attendance hai?",
    "🏫 Mein total kitne din college gaya tha",
    "😴 Meri total kitni chutti hai abhi",
    "🎒 Kitne din college khula tha",
    "🔒 Kitne din band tha",
    "📅 Sirf iss mahine ka record chahiye",
    "🚫 Kon konsi date ko mein absent tha",
    "✅ Kon konsi date ko mein present tha",
    "🗓️ Custom date record chahiye",
]
(BTN_PCT, BTN_GAYA, BTN_CHUTTI_TOTAL, BTN_KHULA, BTN_BAND,
 BTN_MONTH, BTN_ABSENT_D, BTN_PRESENT_D, BTN_CUSTOM) = MENU_BUTTONS

# ---------------- MESSAGES ----------------
MSG_WELCOME = [
    "😕 Are! Tum kaun ho bhai aur mujhse kya kaam hai!",
    "😎 Kya Registration karwana hai apni attendance mujhse manage karwane ke liye?",
]
MSG_BYE = "theek hai baad mein baat karenge BYE mere DOST 👋"
MSG_ASK_NAME = "🧑 Apna naam likh kar bhejo mujhe:"
MSG_ASK_BRANCH = "🏷️ Tumhari kya branch hai? (button dabao):"
MSG_ASK_YEAR = "🎓 Tumhare B.Tech ka kaun sa YEAR hai? (button dabao):"
MSG_ADMIN_ASK_YEAR = "Malik APP 🙏, aap kis YEAR mein hain? (button dabaiye):"
MSG_ASK_ROLL = "🔢 Apna ROLL number bhejo (same naam wale students mein confusion na ho):"
MSG_ASK_CHANGE = "Kya kuch change karna hai?"
MSG_ASK_WHAT_CHANGE = ("Kya change karna hai? Ye bhejo:\n1️⃣ naam\n2️⃣ branch\n3️⃣ year\n4️⃣ roll_no")
MSG_UNIQUE_ID = (
    "🎉 Registration COMPLETE!\n\n"
    "🆔 Tumhari UNIQUE ID: {uid}\n\n"
    "⚠️ Isse sambhal kar rakho ya kahi likh lo — "
    "baad mein kaam aayegi jab apna ATTENDANCE record wapus chahiye hoga!"
)
MSG_ADMIN_ASK_NAME = "Malik APP 🙏, apna shubh-naam likh kar bhejiye:"
MSG_ADMIN_ASK_ROLL = "Malik APP 🙏, apna ROLL number bhejiye:"
MSG_ADMIN_CHANGE = "Malik APP 🙏, kya kuch change karna hai?"
MSG_ADMIN_HOLIDAY_ASK = (
    "Malik APP 🙏, college ki chhutti ka notice bhej dijiye — "
    "image ho ya text, kuch farak nahi padta. 📩"
)
MSG_ADMIN_NOTICE_ASK = (
    "Malik APP 🙏, naya College Holiday Notice bhej dijiye "
    "(image ya text, jo bhi sahi lage) 📩"
)
MSG_ASK_HOLIDAY_DATE = (
    "Malik APP 🙏, chhutti kis date ki hai? 📅\n"
    "👇 AAJ button dabao ya DD/MM/YYYY bhejo (jaise 10/09/2026)."
)
MSG_ASK_HOLIDAY_PROOF = (
    "Malik APP 🙏, {day} ke liye proof bhej dijiye — "
    "image ho ya text, kuch farak nahi padta. 📩"
)
MSG_HOLIDAY_BROADCAST = (
    "🏖️ AAJ TOH CHHUTTI HAI MOZ KARO 🎉\n"
    "📅 Date: {day}"
)
MSG_EXIT_DONE = (
    "❌ Cancel kar diya, bahar aa gaye. ✅\n"
    "Adhura data discard kar diya — kuch save nahi hua.\n"
    "/start se dobara shuru karo. 😊"
)
MSG_EXIT_HINT = "\n\n❌ Bahar nikalne ke liye EXIT dabao ya /cancel bhejo."
MSG_AUTO_ABSENT = (
    "😡🤬🤬 Oye! Tumne ajj ki chhuti maarli mujhe bina batay abhi "
    "🤪😜😓 ruko tum hari absent lagata hu. "
    "Le lagadi abh kiya karoge 😁😁😁\n"
    "📅 Date: {day}"
)
TAREEF = [
    "Wah! Shabash! 🎉 Aaj tum present ho — dedication ka koi jawab nahi! ⭐",
    "Bahut badhiya! 🌟 Attendance time par laga di — keep it up, hero! 💪",
    "Zabardast! 😎 Tumhari punctuality ka koi jawab nahi. Aaj ka din tumhara! 🏆",
]

# ---------------- STATES ----------------
(ASK_NAME, ASK_BRANCH, ASK_ROLL, ASK_CHANGE,
  ASK_WHAT_CHANGE, ASK_HOLIDAY_NOTICE, ASK_YEAR,
  ASK_HOLIDAY_DATE) = range(8)

REG = {}            # chat_id -> registration context
ADMIN_NOTICE_WAIT = set()
LOOKUP_WAIT = set()
HOLIDAY_DATE = {}   # chat_id -> DD/MM/YYYY (Step-1 me chosen, Step-2 proof me use)
HOLIDAY_DATE_WAIT = set()  # chat_id jahan Step-1 date pending hai
BTN_TODAY = "📅 AAJ"
CB_HOL_TODAY = "hol:today"

# ---------------- HELPERS ----------------
def is_admin(update: Update) -> bool:
    return update.effective_chat is not None and (
        update.effective_chat.id == config.ADMIN_CHAT_ID
    )


def today_str() -> str:
    return stats_mod.fmt(stats_mod.today())


def parse_holiday_day(raw_text: str | None) -> str:
    """Admin notice ke first-word me DD/MM/YYYY ho to wahi date, warna aaj.

    Future-date support: '10/09/2026 Kal band rahega' -> '10/09/2026'.
    Galat/expired format -> today_str() fallback (caller validate kare).
    """
    txt = (raw_text or "").strip()
    m = re.match(r"^(\d{2}/\d{2}/\d{4})\b", txt)
    if not m:
        return today_str()
    try:
        stats_mod._parse_ddmmyyyy(m.group(1))
        return m.group(1)
    except Exception:
        return today_str()


def strip_date_prefix(raw_text: str | None) -> str:
    """'10/09/2026 Kal band' -> 'Kal band' (broadcast proof saaf dikhe)."""
    txt = (raw_text or "").strip()
    return re.sub(r"^\d{2}/\d{2}/\d{4}\b\s*", "", txt).strip()


async def broadcast_holiday(day: str, ntype: str, raw: bytes,
                            proof_text: str, context) -> tuple[int, int]:
    """Holiday notice turant SAB registered users ko bhejo (proof ke saath).

    - image: wahi photo + caption 'AAJ TOH CHHUTTI HAI MOZ KARO + date'
    - text: message 'AAJ TOH CHHUTTI HAI MOZ KARO + date + proof text'
    Returns (ok, fail). Kisi ek user par fail ho to bhi continue.
    """
    base = MSG_HOLIDAY_BROADCAST.format(day=day)
    ok, fail = 0, 0
    for stu in db.get_all_students():
        cid = stu["chat_id"]
        try:
            if ntype == "image":
                cap = base + (f"\n📝 {proof_text[:900]}" if proof_text else "")
                await context.bot.send_photo(
                    chat_id=int(cid),
                    photo=InputFile(io.BytesIO(raw), filename="holiday.jpg"),
                    caption=cap,
                )
            else:
                txt = base
                try:
                    txt += "\n📝 Proof: " + raw.decode(errors="replace")[:1500]
                except Exception:
                    pass
                await context.bot.send_message(chat_id=int(cid), text=txt)
            ok += 1
        except Exception as e:
            log.warning("holiday broadcast fail %s: %s", cid, e)
            fail += 1
    return ok, fail


def mark_holiday_attendance(day: str) -> int:
    """Holiday wale din SAB users ki entry HOLIDAY me update karo.

    Reason: 'holiday declared by admin' taaki extra present/absent na gine
    aur record accurate rahe. Returns updated count.
    """
    reason = "admin-holiday: holiday declared by admin"
    n = 0
    for stu in db.get_all_students():
        db.mark_attendance(stu["chat_id"], "HOLIDAY", reason, day)
        n += 1
    return n


def exit_kb_row() -> list:
    """Har inline keyboard ki last-row me EXIT button."""
    return [InlineKeyboardButton(BTN_EXIT, callback_data=CB_EXIT)]


def clear_wait_state(chat_id) -> None:
    """EXIT/cancel par saara adhura state discard karo (kuch save nahi)."""
    REG.pop(chat_id, None)
    ADMIN_NOTICE_WAIT.discard(chat_id)
    LOOKUP_WAIT.discard(chat_id)
    HOLIDAY_DATE.pop(chat_id, None)
    HOLIDAY_DATE_WAIT.discard(chat_id)


def menu_rows() -> list:
    """Design doc section 4: saare 9 menu buttons (1 per row ko banao)."""
    return [[InlineKeyboardButton(b, callback_data="menu:" + str(i))]
            for i, b in enumerate(MENU_BUTTONS)]


def main_menu_kb() -> InlineKeyboardMarkup:
    # 9 menu buttons - 1 per row (Telegram limit: max 8 per row)
    return InlineKeyboardMarkup(menu_rows())


def menu_open_kb() -> InlineKeyboardMarkup:
    """Registered user ka home keyboard:
    - SABSE UPAR 2 attendance buttons: [😎 PRESENT HU] [😁 AAJ KI CHHUTTI MAAR LI]
      -> in par click karne se aaj ki attendance turant lag jaati hai
    - Niche '📋 MENU KHOLO' -> click karne par 9-button menu khulta hai
    """
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(BTN_PRESENT, callback_data="att:PRESENT"),
         InlineKeyboardButton(BTN_CHHUTTI, callback_data="att:CHHUTTI")],
        [InlineKeyboardButton(BTN_MENU, callback_data=CB_MENU_OPEN)],
    ])


def name_for(update: Update) -> str:
    u = update.effective_user
    return (u.first_name if u else None) or "Dost"


def daily_kb() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton(BTN_PRESENT, callback_data="att:PRESENT"),
          InlineKeyboardButton(BTN_CHHUTTI, callback_data="att:CHHUTTI")]]
    )


def admin_daily_kb() -> InlineKeyboardMarkup:
    """
    ADMIN HOME KEYBOARD (design doc ke mutabik):
    - Pehle 6 buttons HAMESHA dikhenge (starting wale, jese hain):
      1) 😎 PRESENT HU
      2) 😁 AAJ KI CHHUTTI MAAR LI
      3) 🏖️ AAJ College ki Chhutti hai
      4) 📢 Update College Holiday Notice
      5) 🔍 KISI STUDENT KA RECORD NIKALO
      6) 📊 Meri kitni percent attendance hai?
    - In 6 ke NICHE ek '📋 MENU KHOLO' button hoga
    - MENU click karne par hi bache hue 8 buttons dikhenge
    """
    return InlineKeyboardMarkup([
        [InlineKeyboardButton(BTN_PRESENT, callback_data="att:PRESENT")],
        [InlineKeyboardButton(BTN_CHHUTTI, callback_data="att:CHHUTTI")],
        [InlineKeyboardButton(BTN_HOLIDAY, callback_data="holiday:ask")],
        [InlineKeyboardButton(BTN_NOTICE, callback_data="holiday:ask")],
        [InlineKeyboardButton(BTN_LOOKUP, callback_data="lookup:ask")],
        [InlineKeyboardButton(MENU_BUTTONS[0], callback_data="menu:0")],
        [InlineKeyboardButton(BTN_MENU, callback_data=CB_MENU_OPEN)],
    ])


def admin_extended_menu_kb() -> InlineKeyboardMarkup:
    """Admin '📋 MENU KHOLO' click karne par -> baaki ke 8 menu buttons (1..8)."""
    return InlineKeyboardMarkup(
        [[InlineKeyboardButton(b, callback_data="menu:" + str(i))]
         for i, b in enumerate(MENU_BUTTONS) if i != 0]
    )


def menu_result_text(chat_id: str, which: str, custom_date=None) -> str:
    s = stats_mod.compute_stats(chat_id)
    if not s:
        return "Pehle registration karwao! 'hi' bhejo. 😊"
    today = stats_mod.today()
    if which == BTN_PCT:
        return stats_mod.stats_message(s, "📊 ATTENDANCE PERCENT")
    if which == BTN_GAYA:
        dates = stats_mod.sort_dates_desc(s["present_dates"] + s["chutti_dates"])
        return (f"🏫 TOTAL COLLEGE GAYE DIN: {len(dates)}\n\n"
                + ("\n".join(f"  • {d}" for d in dates) or "  (koi nahi)"))
    if which == BTN_CHUTTI_TOTAL:
        return (f"😴 TOTAL CHHUTTI (abhi tak): {s['chutti'] + s['absent']}\n\n"
                f"😁 self-declared: {s['chutti']}\n🚫 absent (auto): {s['absent']}")
    if which == BTN_KHULA:
        return (f"🎒 COLLEGE KHULA THA: {s['college_open']} din\n"
                f"(registration se aaj tak, SUNDAY + chhutti chhod kar)")
    if which == BTN_BAND:
        return (f"🔒 COLLEGE BAND THA: {s['college_closed']} din\n"
                f"(saare SUNDAY + admin-declared chhutti)")
    if which == BTN_MONTH:
        sm = stats_mod.compute_stats(chat_id, (today.year, today.month))
        return stats_mod.stats_message(
            sm, f"📅 ISS MAHINE ({stats_mod.MONTHS_HI[today.month-1]} {today.year})")
    if which == BTN_ABSENT_D:
        return ("🚫 ABSENT THA IN DATES PAR:\n\n"
                + ("\n".join(f"  • {d}" for d in s["absent_dates"])
                   or "  🎉 (kabhi absent nahi hua!)")
                + "\n\n(sab DD/MM/YYYY mein — latest date sabse upar)")
    if which == BTN_PRESENT_D:
        return ("✅ PRESENT THA IN DATES PAR:\n\n"
                + ("\n".join(f"  • {d}" for d in s["present_dates"])
                   or "  (abhi koi entry nahi)")
                + "\n\n(sab DD/MM/YYYY mein — latest date sabse upar)")
    return "Samajh nahi aaya, dobara try karo!"


# ---------------- /start + FIRST INTERACTION ----------------
async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if is_admin(update):
        if db.get_student(chat_id):
            await update.effective_message.reply_text(
                f"🙏 Namaste Malik APP! (aaj: {today_str()})",
                reply_markup=admin_daily_kb(),
            )
        else:
            REG[chat_id] = {"is_admin": True}
            await update.effective_message.reply_text(
                f"🙏 Namaste Malik ! {MSG_ADMIN_ASK_NAME}")
            return ASK_NAME
        return ConversationHandler.END

    if db.get_student(chat_id):
        await update.effective_message.reply_text(
            f"😎 {name_for(update)}, aaj college gaye the ya chhutti maar li? "
            f"👇 Niche button dabao (menu bhi niche hai):",
            reply_markup=menu_open_kb(),
        )
        return ConversationHandler.END

    await update.effective_message.reply_text(MSG_WELCOME[0])
    await update.effective_message.reply_text(
        MSG_WELCOME[1],
        reply_markup=InlineKeyboardMarkup(
            [[InlineKeyboardButton(BTN_YES, callback_data="reg:yes"),
              InlineKeyboardButton(BTN_NO, callback_data="reg:no")]]),
    )
    return ConversationHandler.END


# ---------------- /menu (MENU button) ----------------
async def cmd_menu(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Telegram ke MENU button (ya /menu) par click karo -> 9-button menu khulta hai."""
    chat_id = update.effective_chat.id
    if db.get_student(chat_id):
        kb = admin_daily_kb() if is_admin(update) else main_menu_kb()
        await update.effective_message.reply_text(
            "👇 MENU — jo bhi poochna ho, button dabao:",
            reply_markup=kb,
        )
        return ConversationHandler.END
    # Unregistered: pehli baar "hi" wala welcome + registration buttons
    await update.effective_message.reply_text(MSG_WELCOME[0])
    await update.effective_message.reply_text(
        MSG_WELCOME[1],
        reply_markup=InlineKeyboardMarkup(
            [[InlineKeyboardButton(BTN_YES, callback_data="reg:yes"),
              InlineKeyboardButton(BTN_NO, callback_data="reg:no")]]),
    )
    return ConversationHandler.END


async def on_menu_open(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """'📋 MENU KHOLO' button par click -> menu buttons edit kar deta hai.
    - Admin: baaki ke 8 buttons (1..8) — 6 fixed buttons ke andar nahi hain
    - Student: saare 9 menu buttons
    """
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    if db.get_student(chat_id):
        if is_admin(update):
            kb = admin_extended_menu_kb()
            txt = "👇 MENU — baaki ke 8 options (admin):"
        else:
            kb = main_menu_kb()
            txt = "👇 MENU — jo bhi poochna ho, button dabao:"
        await q.edit_message_text(txt, reply_markup=kb)
    else:
        await q.edit_message_text(
            "Pehle registration karwao! 'hi' ya /start bhejo 😊")


async def on_reg_choice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    if q.data == "reg:yes":
        REG[chat_id] = {"is_admin": is_admin(update)}
        await q.edit_message_text(
            MSG_ADMIN_ASK_NAME if is_admin(update) else MSG_ASK_NAME)
        return ASK_NAME
    await q.edit_message_text(MSG_BYE)
    return ConversationHandler.END


# ---------------- REGISTRATION STEPS ----------------
async def reg_name(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if (update.message.text or "").strip().lower() in ("exit", "/cancel"):
        return await on_exit_text(update, context)
    naam = update.message.text.strip()[:50]
    REG.setdefault(chat_id, {})["naam"] = naam
    await update.message.reply_text(
        f"✅ Naam save ho gaya: {naam}\n\n"
        + MSG_ASK_BRANCH + MSG_EXIT_HINT,
        reply_markup=InlineKeyboardMarkup(
            [[InlineKeyboardButton(b, callback_data="branch:" + b)
              for b in BRANCH_MAP],
             exit_kb_row()]),
    )
    return ASK_BRANCH


async def reg_branch(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    REG.setdefault(chat_id, {})["branch"] = BRANCH_MAP.get(
        q.data.split(":", 1)[1], "?")
    ctx = REG[chat_id]
    branch = ctx.get("branch")
    await q.edit_message_text(
        f"✅ Branch save ho gayi: {branch}\n\n"
        + (MSG_ADMIN_ASK_YEAR if ctx.get("is_admin") else MSG_ASK_YEAR)
        + MSG_EXIT_HINT,
        reply_markup=InlineKeyboardMarkup(
            [[InlineKeyboardButton(b, callback_data="year:" + YEAR_MAP[b])
              for b in YEAR_MAP],
             exit_kb_row()]),
    )
    return ASK_YEAR


async def reg_year(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Year button click -> roll number poocho."""
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    REG.setdefault(chat_id, {})["year"] = q.data.split(":", 1)[1]
    year = REG[chat_id]["year"]
    await q.edit_message_text(
        f"✅ Year save ho gaya: {year}\n\n"
        + (MSG_ADMIN_ASK_ROLL if REG.get(chat_id, {}).get("is_admin")
           else MSG_ASK_ROLL)
        + MSG_EXIT_HINT)
    return ASK_ROLL


async def reg_roll(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if (update.message.text or "").strip().lower() in ("exit", "/cancel"):
        return await on_exit_text(update, context)
    roll = update.message.text.strip()[:20]
    REG.setdefault(chat_id, {})["roll_no"] = roll
    ctx = REG[chat_id]
    summary = (f"📝 Tumhara data:\n👤 {ctx.get('naam')}\n🏷️ {ctx.get('branch')}\n"
               f"🎓 {ctx.get('year')}\n🔢 {roll}\n\n")
    msg = MSG_ADMIN_CHANGE if ctx.get("is_admin") else MSG_ASK_CHANGE
    await update.message.reply_text(
        f"✅ Roll number save ho gaya: {roll}\n\n" + summary + msg,
        reply_markup=InlineKeyboardMarkup(
            [[InlineKeyboardButton(BTN_CHANGE_YES, callback_data="chg:yes"),
              InlineKeyboardButton(BTN_CHANGE_NO, callback_data="chg:no")],
             exit_kb_row()]),
    )
    return ASK_CHANGE


async def reg_change(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    ctx = REG.get(chat_id, {})
    if q.data == "chg:yes":
        await q.edit_message_text(
            MSG_ASK_WHAT_CHANGE + MSG_EXIT_HINT,
            reply_markup=InlineKeyboardMarkup([exit_kb_row()]),
        )
        return ASK_WHAT_CHANGE

    # ---- FINAL SAVE (chat_id ke saath - design doc requirement) ----
    db.save_student_field(chat_id, "naam", ctx.get("naam") or name_for(update))
    db.save_student_field(chat_id, "branch", ctx.get("branch") or "-")
    db.save_student_field(chat_id, "year", ctx.get("year") or "-")
    db.save_student_field(chat_id, "roll_no", ctx.get("roll_no") or "-")
    uid = "STU-" + uuid.uuid4().hex[:8].upper()
    with db._LOCK, db._conn() as c:
        c.execute("UPDATE students SET unique_id = ? WHERE chat_id = ?",
                  (uid, str(chat_id)))
    REG.pop(chat_id, None)

    if ctx.get("is_admin"):
        await q.edit_message_text(
            f"✅ Verify: registration save ho gaya!\n"
            f"👤 {ctx.get('naam')} | 🏷️ {ctx.get('branch')} | "
            f"🎓 {ctx.get('year')} | 🔢 {ctx.get('roll_no')}\n"
            f"🎉 Malik APP, aapka registration ho gaya! 🙏\n"
            f"🆔 UNIQUE ID: {uid}\n(Issse sambhal kar rakhiye!)")
        await update.effective_message.reply_text(
            "🙏 Aaj ka kya status hai?", reply_markup=admin_daily_kb())
    else:
        saved = (f"✅ Verify: registration save ho gaya!\n"
                 f"👤 {ctx.get('naam')} | 🏷️ {ctx.get('branch')} | "
                 f"🎓 {ctx.get('year')} | 🔢 {ctx.get('roll_no')}\n\n")
        await q.edit_message_text(saved + MSG_UNIQUE_ID.format(uid=uid))
        await update.effective_message.reply_text(
            "🙏 Aaj college gaye the ya chhutti? 👇 Button dabao "
            "(menu bhi niche hai):",
            reply_markup=menu_open_kb())
    return ConversationHandler.END


async def reg_what_change(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    txt_raw = (update.message.text or "").strip()
    if txt_raw.lower() in ("exit", "/cancel"):
        return await on_exit_text(update, context)
    txt = txt_raw.lower()
    if txt in ("kuch change nahi karna", "no change", "nahi", "no"):
        # Seedha bina change ke save par wapas (ASK_CHANGE)
        ctx = REG.get(chat_id, {})
        msg = MSG_ADMIN_CHANGE if ctx.get("is_admin") else MSG_ASK_CHANGE
        await update.message.reply_text(
            "✅ Theek hai, koi change nahi. " + msg,
            reply_markup=InlineKeyboardMarkup(
                [[InlineKeyboardButton(BTN_CHANGE_YES, callback_data="chg:yes"),
                  InlineKeyboardButton(BTN_CHANGE_NO, callback_data="chg:no")],
                 exit_kb_row()]),
        )
        return ASK_CHANGE
    field = next((f for f in CHANGEABLE if f in txt), None)
    if not field:
        await update.message.reply_text(
            "Ye samajh nahi aaya! 'naam', 'branch', 'year', 'roll_no' likho, "
            "'kuch change nahi karna' likho, ya EXIT dabao.",
            reply_markup=InlineKeyboardMarkup([exit_kb_row()]))
        return ASK_WHAT_CHANGE
    REG.setdefault(chat_id, {})["change_field"] = field
    prompts = {"naam": MSG_ASK_NAME, "branch": MSG_ASK_BRANCH,
               "year": MSG_ASK_YEAR, "roll_no": MSG_ASK_ROLL}
    await update.message.reply_text(
        f"✅ Change field select: {field}. " + prompts[field] + MSG_EXIT_HINT)
    if field == "naam":
        return ASK_NAME
    if field == "roll_no":
        return ASK_ROLL
    if field == "year":
        return ASK_YEAR
    return ASK_BRANCH


# ---------------- EXIT (universal) ----------------
async def on_exit_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Inline EXIT button -> adhura kaam discard karke bahar."""
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    clear_wait_state(chat_id)
    context.user_data.pop("awaiting_custom_date", None)
    try:
        await q.edit_message_text(MSG_EXIT_DONE)
    except Exception:
        await context.bot.send_message(chat_id=int(chat_id), text=MSG_EXIT_DONE)
    return ConversationHandler.END


async def on_exit_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """'exit' text ya /cancel command -> discard karke bahar."""
    chat_id = update.effective_chat.id
    clear_wait_state(chat_id)
    context.user_data.pop("awaiting_custom_date", None)
    await update.message.reply_text(MSG_EXIT_DONE)
    return ConversationHandler.END


async def cmd_cancel(update: Update, context: ContextTypes.DEFAULT_TYPE):
    return await on_exit_text(update, context)

# ---------------- ATTENDANCE CALLBACKS ----------------
async def on_attendance_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    status = q.data.split(":", 1)[1]
    if not db.get_student(chat_id):
        await q.edit_message_text("Pehle registration karwao! 'hi' bhejo 😊")
        return
    day = today_str()
    db.mark_attendance(chat_id, status, "self")
    # Jawab ke baad menu wapas dikha do (taaki user menu tak na scroll kare)
    after_kb = (admin_extended_menu_kb() if is_admin(update)
                else InlineKeyboardMarkup([[
                    InlineKeyboardButton(BTN_MENU, callback_data=CB_MENU_OPEN)]]))
    if status == "PRESENT":
        await q.edit_message_text(
            f"✅ Verify: aaj ({day}) ka PRESENT save ho gaya!\n"
            + random.choice(TAREEF) + "\n\n👇 Aur kuch poochna ho toh MENU kholo:",
            reply_markup=after_kb)
    else:
        hol = db.get_holiday(day)
        extra = ""
        if hol:
            extra = "\n\n🏖️ Waise aaj college band tha! Proof:\n" + (
                f"[{hol['type']}]" if hol["type"] == "image" else hol["notice"].decode(errors="replace")
            )
        await q.edit_message_text(
            f"✅ Verify: aaj ({day}) ki CHHUTTI save ho gayi!\n"
            f"😁 Theek hai dost, aaj ki CHHUTTI maar li! 🎬\n"
            f"Koi baat nahi, kal se phir se milte hain! ⏰{extra}"
            f"\n\n👇 Aur kuch poochna ho toh MENU kholo:",
            reply_markup=after_kb)


# ---------------- MENU CALLBACKS ----------------
async def on_menu_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    idx = int(q.data.split(":", 1)[1])
    which = MENU_BUTTONS[idx]
    if which == BTN_CUSTOM:
        context.user_data["awaiting_custom_date"] = True
        await q.message.reply_text(
            "🗓️ Date bhejo DD/MM/YYYY mein (jaise 02/09/2026):" + MSG_EXIT_HINT,
            reply_markup=InlineKeyboardMarkup([exit_kb_row()]))
        return
    await q.message.reply_text("✅ Verify: tumhara sawal mil gaya!\n" + menu_result_text(chat_id, which))


async def on_custom_date(update: Update, context: ContextTypes.DEFAULT_TYPE):
    txt = (update.message.text or "").strip()
    chat_id = update.effective_chat.id

    # ---- CASE 0 (FIX): conversation ke bahar se aaya holiday/lookup input ----
    # on_holiday_ask/on_lookup_ask ConversationHandler ke bahar registered hain,
    # isliye unka return ASK_HOLIDAY_NOTICE state set nahi karta. Admin ka agli
    # photo/text conversation me nahi jaati — yahan pakdo, warna silently drop
    # ho jaati thi (photo ke liye to koi global handler tha hi nahi).
    if (chat_id in LOOKUP_WAIT or chat_id in ADMIN_NOTICE_WAIT
            or chat_id in HOLIDAY_DATE_WAIT):
        return await holiday_or_lookup_router(update, context)

    # ---- CASE 1: custom date pending hai -> usko process karo ----
    if context.user_data.get("awaiting_custom_date"):
        if txt.lower() in ("exit", "/cancel"):
            return await on_exit_text(update, context)
        if not re.match(r"^\d{2}/\d{2}/\d{4}$", txt):
            await update.message.reply_text(
                "❌ Format galat hai! DD/MM/YYYY bhejo (jaise 02/09/2026):"
                + MSG_EXIT_HINT,
                reply_markup=InlineKeyboardMarkup([exit_kb_row()]))
            return
        context.user_data["awaiting_custom_date"] = False
        row = db.get_attendance(chat_id, txt)
        hol = db.get_holiday(txt)
        parts = [f"✅ Verify: record nikaal diya!\n🗓️ RECORD FOR {txt}:"]
        if hol:
            parts.append("🏖️ Us din COLLEGE BAND tha (chhutti)! 🎉")
        if row:
            emoji = {"PRESENT": "✅", "CHHUTTI": "😁", "ABSENT": "🚫",
                     "HOLIDAY": "🏖️"}.get(row["status"], "")
            parts.append(f"{emoji} Status: {row['status']} (by {row['marked_by']})")
        elif not hol:
            parts.append("❓ Us din koi record nahi mila.")
        await update.message.reply_text("\n".join(parts))
        return

    # ---- CASE 2: REGISTERED user -> design doc section 4 ----
    # MENU (9 buttons) hamesha show — jitni baar bhi user kuch bhi likhe.
    # (Pehle yahan 'ignore' ho jaata tha, isliye "saare buttons show nhi
    # ho rahe the" ka problem tha.)
    if db.get_student(chat_id):
        if is_admin(update):
            kb = admin_daily_kb()
            txt = "🙏 Malik APP, aaj ka kya status hai? 👇 (MENU niche hai)"
        else:
            kb = menu_open_kb()  # upar 2 attendance buttons + MENU KHOLO
            txt = ("😎 Aaj college gaye the ya chhutti maar li? "
                   "👇 Button dabao (menu bhi niche hai):")
        await update.message.reply_text(txt, reply_markup=kb)
        return

    # ---- CASE 3: unregistered + greeting -> design doc section 1 ----
    # Pehli baar "hi" bhejne par intro + [😎 HAA] / [🙅 NHI] buttons.
    if re.match(r"^(hi+|hello+|hey+|hii+|namaste|salaam|namaskar|yo|start)\b",
                txt, re.IGNORECASE):
        await update.message.reply_text(MSG_WELCOME[0])
        await update.message.reply_text(
            MSG_WELCOME[1],
            reply_markup=InlineKeyboardMarkup(
                [[InlineKeyboardButton(BTN_YES, callback_data="reg:yes"),
                  InlineKeyboardButton(BTN_NO, callback_data="reg:no")]]),
        )


# ---------------- HOLIDAY NOTICE (admin) — 2 STEP: pehle DATE, phir PROOF ----------------
async def on_holiday_ask(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    # FIX: dono WAIT sets ek saath active rahe to router confuse hota tha
    # (lookup pehle check hota hai). Dusra clear karo + purani pending date reset.
    LOOKUP_WAIT.discard(update.effective_chat.id)
    ADMIN_NOTICE_WAIT.discard(update.effective_chat.id)
    HOLIDAY_DATE.pop(update.effective_chat.id, None)
    HOLIDAY_DATE_WAIT.add(update.effective_chat.id)
    await q.edit_message_text(
        MSG_ASK_HOLIDAY_DATE + MSG_EXIT_HINT,
        reply_markup=InlineKeyboardMarkup([
            [InlineKeyboardButton(f"{BTN_TODAY} ({today_str()})",
                                  callback_data=CB_HOL_TODAY)],
            exit_kb_row(),
        ]),
    )
    return ASK_HOLIDAY_DATE


def _valid_holiday_date(txt: str | None) -> str | None:
    """DD/MM/YYYY validate karo — koi bhi valid date chalegi (past/today/future)."""
    txt = (txt or "").strip()
    if not re.match(r"^\d{2}/\d{2}/\d{4}$", txt):
        return None
    try:
        stats_mod._parse_ddmmyyyy(txt)
        return txt
    except Exception:
        return None


async def _goto_proof_step(chat_id, day: str, update, context):
    """Date store karke Step-2 (proof) par bhejo."""
    HOLIDAY_DATE[chat_id] = day
    HOLIDAY_DATE_WAIT.discard(chat_id)
    ADMIN_NOTICE_WAIT.add(chat_id)
    await update.message.reply_text(
        f"✅ Date save ho gayi: {day}, ab proof bhejo 📩\n\n"
        + MSG_ASK_HOLIDAY_PROOF.format(day=day) + MSG_EXIT_HINT)
    return ASK_HOLIDAY_NOTICE


async def on_holiday_date_btn(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Step-1 me AAJ button -> aaj ki date store, proof step par jao."""
    q = update.callback_query
    await q.answer()
    chat_id = update.effective_chat.id
    day = today_str()
    HOLIDAY_DATE[chat_id] = day
    HOLIDAY_DATE_WAIT.discard(chat_id)
    ADMIN_NOTICE_WAIT.add(chat_id)
    await q.edit_message_text(
        f"✅ Date save ho gayi: {day}, ab proof bhejo 📩\n\n"
        + MSG_ASK_HOLIDAY_PROOF.format(day=day) + MSG_EXIT_HINT)
    return ASK_HOLIDAY_NOTICE


async def on_holiday_date_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """Step-1 me text date -> validate karke proof step par jao."""
    chat_id = update.effective_chat.id
    txt = (update.message.text or "").strip()
    if txt.lower() in ("exit", "/cancel"):
        return await on_exit_text(update, context)
    if txt.lower() in ("aaj", "today"):
        return await _goto_proof_step(chat_id, today_str(), update, context)
    day = _valid_holiday_date(txt)
    if not day:
        await update.message.reply_text(
            "❌ Format galat hai! DD/MM/YYYY bhejo (jaise 10/09/2026), "
            "AAJ likho, ya AAJ button dabao — ya EXIT dabao.",
            reply_markup=InlineKeyboardMarkup([exit_kb_row()]))
        return ASK_HOLIDAY_DATE
    return await _goto_proof_step(chat_id, day, update, context)


async def on_holiday_notice(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if chat_id not in ADMIN_NOTICE_WAIT:
        return ConversationHandler.END
    if (update.message.text and update.message.text.strip().lower() in ("exit", "/cancel")):
        return await on_exit_text(update, context)
    # 2-STEP: date Step-1 (HOLIDAY_DATE) se aayegi — proof me date prefix nahi chahiye.
    # Purana first-word-date tarika hata diya gaya hai.
    day = HOLIDAY_DATE.get(chat_id) or today_str()
    if update.message.photo:
        try:
            file = await update.message.photo[-1].get_file()
            data = await file.download_as_bytearray()
            raw = bytes(data)
        except Exception as e:
            log.error("holiday photo download fail: %s", e)
            await update.message.reply_text(
                "❌ Photo download nahi ho payi, dobara bhejo ya EXIT dabao.")
            return ConversationHandler.END
        cap = (update.message.caption or "").strip()
        try:
            db.save_holiday(day, raw, "image", chat_id)
        except Exception as e:
            log.error("holiday save fail: %s", e)
            await update.message.reply_text(
                "❌ Notice SAVE nahi ho paya (DB error), dobara try karo.")
            return ConversationHandler.END
        log.info("holiday saved: %s image %d bytes by %s", day, len(raw), chat_id)
        await update.message.reply_text(
            f"✅ Verify: holiday notice SAVE ho gaya! 📸 Date: {day} — {cap[:50]}")
        proof_text = cap
        ntype = "image"
    else:
        text = update.message.text or ""
        proof_text = text.strip()
        raw = (text or "").encode()
        try:
            db.save_holiday(day, raw, "text", chat_id)
        except Exception as e:
            log.error("holiday save fail: %s", e)
            await update.message.reply_text(
                "❌ Notice SAVE nahi ho paya (DB error), dobara try karo.")
            return ConversationHandler.END
        log.info("holiday saved: %s text by %s", day, chat_id)
        await update.message.reply_text(
            f"✅ Verify: holiday notice SAVE ho gaya! 📝 Date: {day} — {proof_text[:50]}")
        ntype = "text"
    # Holiday wale din sabki attendance HOLIDAY me update (bewajah present/absent na gine)
    n_updated = mark_holiday_attendance(day)
    # INSTANT BROADCAST: declare hote hi sabko message + proof
    ok, fail = await broadcast_holiday(day, ntype, raw, proof_text, context)
    ADMIN_NOTICE_WAIT.discard(chat_id)
    HOLIDAY_DATE.pop(chat_id, None)
    await update.message.reply_text(
        f"🏖️ Holiday declare kar diya gaya hai! ✅\n"
        f"📅 Date: {day} | 📎 Proof: {ntype} | 👥 {n_updated} entries HOLIDAY me update\n"
        f"📢 Broadcast ho gaya! ✅ {ok} ko bheja, ❌ {fail} fail.\n"
        "Ye holiday data se hi sabki attendance calculate hogi — "
        "us din kisi ko bewajah chhutti/absent nahi lagegi. 🎯",
        reply_markup=admin_daily_kb())
    return ConversationHandler.END


# ---------------- ADMIN LOOKUP ----------------
async def on_lookup_ask(update: Update, context: ContextTypes.DEFAULT_TYPE):
    q = update.callback_query
    await q.answer()
    # FIX: holiday wait clear taaki router lookup ko sahi pakde
    ADMIN_NOTICE_WAIT.discard(update.effective_chat.id)
    HOLIDAY_DATE.pop(update.effective_chat.id, None)
    HOLIDAY_DATE_WAIT.discard(update.effective_chat.id)
    LOOKUP_WAIT.add(update.effective_chat.id)
    await q.edit_message_text(
        "🔍 Kisse dhundo Malik APP? Roll number ya chat id bhejiye:" + MSG_EXIT_HINT,
        reply_markup=InlineKeyboardMarkup([exit_kb_row()]),
    )
    return ASK_HOLIDAY_NOTICE  # reuse same wait state


async def on_lookup_input(update: Update, context: ContextTypes.DEFAULT_TYPE):
    chat_id = update.effective_chat.id
    if chat_id not in LOOKUP_WAIT:
        return ConversationHandler.END
    if (update.message.text or "").strip().lower() in ("exit", "/cancel"):
        return await on_exit_text(update, context)
    LOOKUP_WAIT.discard(chat_id)
    key = update.message.text.strip()
    stu = db.get_student(key) or db.get_student_by_roll(key)
    if stu is None:
        LOOKUP_WAIT.add(chat_id)
        await update.message.reply_text(
            f"😔 Verify: '{key}' se koi student nahi mila. Dobara try karo ya EXIT dabao:",
            reply_markup=InlineKeyboardMarkup([exit_kb_row()]))
        return ASK_HOLIDAY_NOTICE  # retry
    s = stats_mod.compute_stats(stu["chat_id"])
    if not s:
        await update.message.reply_text("✅ Verify: record compute nahi ho paya. ❌")
        return ConversationHandler.END
    await update.message.reply_text(
        "✅ Verify: student record mil gaya!\n🔍 STUDENT RECORD (Malik APP ke liye)\n\n"
        + stats_mod.stats_message(s),
        reply_markup=admin_daily_kb())
    return ConversationHandler.END


# ---------------- SCHEDULED JOBS ----------------
async def daily_job(context: ContextTypes.DEFAULT_TYPE):
    """8:15 AM IST - sab registered users se poocho (SUNDAY skip, holiday par MOZ KARO)."""
    t = stats_mod.today()
    day = today_str()
    if stats_mod.is_sunday(t):
        log.info("Sunday - daily job skip")
        return
    hol = db.get_holiday(day)
    if hol:
        # Uss din chhutti hai -> attendance sawal ki jagah MOZ KARO + proof
        log.info("Holiday %s - moz-karo broadcast", day)
        try:
            raw = bytes(hol["notice"]) if hol["notice"] else b""
        except Exception:
            raw = b""
        proof = ""
        if hol["type"] != "image":
            try:
                proof = raw.decode(errors="replace")
            except Exception:
                proof = ""
        else:
            proof = ""
        await broadcast_holiday(day, hol["type"], raw, proof, context)
        return
    for stu in db.get_all_students():
        cid = stu["chat_id"]
        if db.get_attendance(cid, day):
            continue  # pehle se marked
        try:
            if cid == str(config.ADMIN_CHAT_ID):
                await context.bot.send_message(
                    int(cid),
                    f"🙏 Malik APP, aaj ({day}) ka kya status hai?",
                    reply_markup=admin_daily_kb())
            else:
                await context.bot.send_message(
                    int(cid),
                    f"⏰ Aaj ({day}) ki attendance KAB lagaoge? "
                    f"Agar nahi lagai toh mein ABSENT laga dunga! 😠",
                    reply_markup=daily_kb())
        except Exception as e:
            log.warning("send fail %s: %s", cid, e)


async def reminder_job(context: ContextTypes.DEFAULT_TYPE):
    """Har ghanta 8:15-17:00 IST ke beech - jinhone nahi lagayi."""
    now = stats_mod.today()
    from datetime import datetime
    dt = datetime.now(stats_mod._TZ)
    if dt.weekday() == 6 or db.is_holiday(today_str()):
        return
    if dt.hour < config.DAILY_QUESTION_HOUR or dt.hour >= config.CUTOFF_HOUR:
        return
    day = today_str()
    for stu in db.get_all_students():
        cid = stu["chat_id"]
        if db.get_attendance(cid, day):
            continue
        try:
            if cid == str(config.ADMIN_CHAT_ID):
                await context.bot.send_message(
                    int(cid), f"🙏 Malik APP, yaad dila rahe hain — aaj ka status?",
                    reply_markup=admin_daily_kb())
            else:
                await context.bot.send_message(
                    int(cid),
                    "⏰ Yaad hai? Attendance abhi tak nahi lagai! "
                    "Button daba do warna ABSENT laga dunga! 😠",
                    reply_markup=daily_kb())
        except Exception as e:
            log.warning("reminder fail %s: %s", cid, e)


async def auto_absent_job(context: ContextTypes.DEFAULT_TYPE):
    """5:00 PM (cutoff) ke baad - jinhone nahi lagayi unhe ABSENT mark karo."""
    from datetime import datetime
    dt = datetime.now(stats_mod._TZ)
    if dt.weekday() == 6 or db.is_holiday(today_str()):
        return
    day = today_str()
    for stu in db.get_all_students():
        cid = stu["chat_id"]
        if db.get_attendance(cid, day):
            continue
        db.mark_attendance(cid, "ABSENT", "bot-auto")
        try:
            await context.bot.send_message(
                int(cid),
                MSG_AUTO_ABSENT.format(day=day))
        except Exception as e:
            log.warning("absent-notify fail %s: %s", cid, e)


# ---------------- MAIN ----------------
async def on_error(update, context):
    log.error("Update error: %s", context.error)


async def post_init(application: Application) -> None:
    """Telegram UI ke '☰ Menu' button mein commands dikhao (native menu button)."""
    try:
        await application.bot.set_my_commands([
            ("start", "Bot start karo / welcome"),
            ("menu", "9-button menu kholo (attendance & details)"),
            ("cancel", "Adhura kaam discard karke bahar niklo"),
        ])
    except Exception as e:
        log.warning("set_my_commands fail: %s", e)


def build_app() -> Application:
    app = ApplicationBuilder().token(config.BOT_TOKEN).post_init(post_init).build()

    reg_conv = ConversationHandler(
        entry_points=[
            CommandHandler("start", cmd_start),
            CallbackQueryHandler(on_reg_choice, pattern="^reg:(yes|no)$"),
        ],
        states={
            ASK_NAME: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, reg_name),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_BRANCH: [
                CallbackQueryHandler(reg_branch, pattern="^branch:"),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_YEAR: [
                CallbackQueryHandler(reg_year, pattern="^year:"),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_ROLL: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, reg_roll),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_CHANGE: [
                CallbackQueryHandler(reg_change, pattern="^chg:(yes|no)$"),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_WHAT_CHANGE: [
                MessageHandler(filters.TEXT & ~filters.COMMAND, reg_what_change),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_HOLIDAY_NOTICE: [
                MessageHandler(
                    (filters.PHOTO | filters.TEXT) & ~filters.COMMAND,
                    holiday_or_lookup_router),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
            ASK_HOLIDAY_DATE: [
                MessageHandler(filters.TEXT & ~filters.COMMAND,
                               holiday_or_lookup_router),
                CallbackQueryHandler(on_holiday_date_btn, pattern="^hol:today$"),
                CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"),
            ],
        },
        fallbacks=[
            CommandHandler("start", cmd_start),
            CommandHandler("cancel", cmd_cancel),
        ],
        allow_reentry=True,
    )
    app.add_handler(reg_conv)

    app.add_handler(CallbackQueryHandler(reg_year, pattern="^year:"))
    app.add_handler(CallbackQueryHandler(on_exit_btn, pattern="^exit:cancel$"))
    app.add_handler(CommandHandler("cancel", cmd_cancel))
    app.add_handler(CommandHandler("menu", cmd_menu))
    app.add_handler(CallbackQueryHandler(on_reg_choice, pattern="^reg:(yes|no)$"))
    app.add_handler(CallbackQueryHandler(on_attendance_btn, pattern="^att:"))
    app.add_handler(CallbackQueryHandler(on_menu_open, pattern="^menu:open$"))
    app.add_handler(CallbackQueryHandler(on_menu_btn, pattern="^menu:[0-9]+$"))
    app.add_handler(CallbackQueryHandler(on_holiday_ask, pattern="^holiday:ask$"))
    app.add_handler(CallbackQueryHandler(on_lookup_ask, pattern="^lookup:ask$"))
    # Date-step AAJ button conversation ke bahar bhi fire hona chahiye
    app.add_handler(CallbackQueryHandler(on_holiday_date_btn, pattern="^hol:today$"))
    # FIX: photo wait-state routing (conversation END hone par bhi save ho)
    app.add_handler(MessageHandler(filters.PHOTO, on_photo_global))
    app.add_handler(MessageHandler(
        filters.TEXT & ~filters.COMMAND, on_custom_date))
    app.add_error_handler(on_error)

    try:
        from telegram.ext import JobQueue
        app.job_queue.run_daily(
            daily_job,
            time=__import__("datetime").time(
                hour=config.DAILY_QUESTION_HOUR,
                minute=config.DAILY_QUESTION_MINUTE,
                tzinfo=stats_mod._TZ),
            name="daily_815")
        app.job_queue.run_repeating(
            reminder_job, interval=3600, first=3600, name="hourly_reminder")
        app.job_queue.run_daily(
            auto_absent_job,
            time=__import__("datetime").time(
                hour=config.CUTOFF_HOUR, minute=config.CUTOFF_MINUTE + 1,
                tzinfo=stats_mod._TZ),
            name="auto_absent_1701")
        log.info("Job queue scheduled: daily 8:15 AM, hourly reminder, 5:01 PM auto-absent (IST)")
    except ImportError:
        log.warning("JobQueue nahi mila - scheduled jobs disabled (pip install 'python-telegram-bot[job-queue]')")

    return app


async def holiday_or_lookup_router(update, context):
    """Holiday 2-step / lookup routing.

    Order: LOOKUP -> date-step (Step-1) -> proof-step (Step-2).
    """
    chat_id = update.effective_chat.id
    if chat_id in LOOKUP_WAIT:
        return await on_lookup_input(update, context)
    if chat_id in HOLIDAY_DATE_WAIT:
        # Step-1 me photo aayi to error — pehle date chahiye
        if update.message and update.message.photo:
            await update.message.reply_text(
                "❌ Pehle date bhejo (DD/MM/YYYY ya AAJ dabao) — uske baad proof 📩")
            return ASK_HOLIDAY_DATE
        return await on_holiday_date_input(update, context)
    if chat_id in ADMIN_NOTICE_WAIT:
        return await on_holiday_notice(update, context)
    return ConversationHandler.END


async def on_photo_global(update: Update, context: ContextTypes.DEFAULT_TYPE):
    """FIX: conversation ke bahar admin photo bhej de to pakdo.

    Pehle photo ke liye koi global handler tha hi nahi — conversation END
    hone par admin ki holiday photo silently gir jaati thi (save hi nahi hoti).
    """
    chat_id = update.effective_chat.id
    if chat_id in LOOKUP_WAIT or chat_id in ADMIN_NOTICE_WAIT or chat_id in HOLIDAY_DATE_WAIT:
        return await holiday_or_lookup_router(update, context)
    # Normal photo (bina wait-state): ignore, taaki unrelated photo par
    # bot bekar me na bole. Sirf log karo.
    log.info("ignored photo from %s (no wait-state)", chat_id)
    return


def main() -> None:
    db.init_db()
    log.info("DB ready: %s", config.DB_PATH)
    app = build_app()
    log.info("Bot polling start ho raha hai...")
    # drop_pending_updates=False => bot restart hone par pending updates (jaise
    # admin ka message) kabhi GIRAYENGE nahi. Earlier 'True' the, jisse agar
    # koi update reh gaya (duplicate instance conflict mein) to silently drop
    # ho jaata tha aur buttons/messages gayab dikhte the.
    app.run_polling(drop_pending_updates=False)


if __name__ == "__main__":
    main()
