#!/usr/bin/env python3
"""Config for Student Attendance Manager Bot."""
import os

# ============ TOKEN ============
# Token kabhi is file me mat likho (git history me leak ho jayega).
# .env file me BOT_TOKEN=... rakho (gitignored) ya env var set karo.
# Naya token @BotFather se lo.
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
if not BOT_TOKEN:
    raise RuntimeError(
        "BOT_TOKEN missing! .env me BOT_TOKEN=... rakho ya env var set karo. "
        "Template: config.example.py dekho."
    )

# Admin chat id (Malik APP) — legacy single-admin compat
ADMIN_CHAT_ID = 6267031612
# Sabse Bade Malik — master admin, only 1, never downgradable, cannot be created
MASTER_ADMIN_ID = 6267031612

# Timezone: bot ka saara schedule IST (Asia/Kolkata) mein
TZ = "Asia/Kolkata"

# Daily attendance poochne ka time (IST)
DAILY_QUESTION_HOUR = 8
DAILY_QUESTION_MINUTE = 15

# Agar user kuch nahi dabata toh har ghante reminder
REMINDER_INTERVAL_HOURS = 1

# Is time ke baad kuch nahi poochenge (us din ke liye)
CUTOFF_HOUR = 17      # 5:00 PM IST
CUTOFF_MINUTE = 0

# Auto-absent after cutoff
AUTO_ABSENT = True

# Database file
DB_PATH = os.environ.get(
    "BOT_DB_PATH",
    os.path.join(os.path.dirname(os.path.abspath(__file__)), "attendance.db"),
)

# Logs
LOG_FILE = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "logs", "bot.log"
)