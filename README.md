# 🤖 Student Attendance Manager Bot

Telegram attendance bot (design doc: `../.lightning_studio/bot design.md` ke mutabik).

## Files
| File | Kaam |
|---|---|
| `config.py` | Token, admin chat id, timings (8:15 AM, 5 PM cutoff, IST) |
| `database.py` | SQLite — students/attendance/holiday_notices (chat_id PK) |
| `stats.py` | Attendance %, khule/band din, DD/MM/YYYY calculations |
| `bot.py` | Main bot — registration, menu, admin, scheduled jobs |
| `run.sh` | Start script |
| `logs/bot.log` | Runtime logs |

## ⚠️ TOKEN (zaroori!)
Token kabhi `config.py` me mat likho (git me leak ho jayega).
`.env` file me rakho (gitignored — `run.sh` khud load karta hai):

```bash
cd /teamspace/studios/this_studio/attendance_bot
echo 'BOT_TOKEN="123456789:AAxxx..."' > .env
./run.sh
```

## Chalana
```bash
cd /teamspace/studios/this_studio/attendance_bot && ./run.sh
```

### ⚠️ SINGLE-INSTANCE (conflict se bachne ke liye — zaroori!)
Telegram ek bot token par **SIRF EK hi instance** allow karta hai. 2+ instances
par `Conflict: terminated by other getUpdates request` error aata hai aur users
ke buttons/messages miss ho jaate hain.

`run.sh` ab **idempotent/safe** hai:
- Bot **pehle se RUNNING** hai → kuch **nahi** karega (exit 0), duplicate start **block**
- Bot **crashed/inactive** hai → hi naya instance start hoga
- 2 log **ek saath** `./run.sh` chalayein → `run.lock` (flock) sirf **1** ko start karne dega
- Multiple terminal se bhi chalao — phir bhi **ek time par ek hi bot**

Lock files:
- `attendance_bot/run.lock` → bot ka lock (jab tak bot zinda, lock held)
- `.lightning_studio/logs/keep_bot_alive.lock` → watchdog ka lock (sirf 1 watchdog)

Watchdog (`keep_bot_alive.sh`): har 30 sec check → bot crash par auto-restart.

## Features (tested ✅)
- Pehli baar "hi"/start → funny intro → [😎 HAA KARWANA HAI!] / [🙅 NHI REHENE DO]
- Registration: naam → branch [🧑‍💻 CS][💻 IT][🔌 EC][⚙️ ME] → roll → change loop → **UNIQUE ID**
- **Har record CHAT_ID ke saath DB mein** + roll_no indexed → admin kisi ka bhi record nikaal sakta hai
- Roz **8:15 AM IST** attendance sawaal (SUNDAY + holiday skip)
- Jawab na do toh **har ghanta reminder till 5 PM**, phir **auto-ABSENT**
- Present → tareef message 😎 | Chhutti → masti message 😁
- **9-button menu** (sirf registered users): % attendance, college gaye din, chutti,
  khule/band din, iss mahine, absent/present dates, custom date (DD/MM/YYYY)
  - Pehle **📋 MENU KHOLO** button dabao (ya **/menu**, ya Telegram ka **☰ Menu**)
  - Us par click karne ke baad hi saare 9 buttons khulte hain
- **Menu button flow**: registered user ko welcome/start/text par
  "📋 MENU KHOLO" dikhta hai → click → 9-button menu (design doc section 4).
  Telegram UI mein bhi native ☰ **Menu** button set hai (`/start`, `/menu`).
- **Admin (6267031612)**: respected "Malik APP" tone aur **saare buttons** — 14 total:
  [😎 PRESENT HU] [😁 CHHUTTI] [🏖️ College ki Chhutti]
  [📢 Update College Holiday Notice] [🔍 Record nikal lo] + poora 9-button menu

## Scheduled Jobs (IST)
| Job | Time | Kaam |
|---|---|---|
| `daily_815` | 08:15 | Sab se attendance poochna |
| `hourly_reminder` | har ghanta (8-5) | Jinhone nahi lagayi unhe yaad dilana |
| `auto_absent_1701` | 17:01 | Bache ko ABSENT mark + notify |
