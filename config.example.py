#!/usr/bin/env python3
"""Config TEMPLATE - ise copy karke apne secrets kabhi commit mat karo.

Setup:
  1. cp config.example.py config.py  (config.py pehle se hai to sirf .env banao)
  2. .env file me likho:  BOT_TOKEN="123456789:AAxxxxxxxxxxxxxxxxx"
     (token @BotFather se lo, kabhi git me mat bhejo)
"""
import os

# Token sirf env se (.env file ya exported env var)
BOT_TOKEN = os.environ.get("BOT_TOKEN", "")
if not BOT_TOKEN:
    raise RuntimeError(
        "BOT_TOKEN missing! .env me BOT_TOKEN=... rakho ya env var set karo."
    )

# Admin chat id (Malik APP)
ADMIN_CHAT_ID = 6267031612

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
