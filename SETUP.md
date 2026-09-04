# Attendance Manager Pro Bot — Setup & Restore (new machine / recovery)

> Daily + per-event backup GitHub private repo me jata hai:
> code + `attendance.db` + `backups/attendance_YYYYMMDD.sql` + `holiday_proofs/`.

## 1. Fresh setup (5 min)

```bash
git clone https://github.com/shivamjislt97/Attendance-Manager-Pro-Bot.git
cd Attendance-Manager-Pro-Bot
python3 -m pip install -r requirements.txt

# Secrets — .env banao (ye file KABHI commit mat karo):
cat > .env << 'EOF'
BOT_TOKEN="123456789:AAxxxxxxxxxxxxxxxxx"
GH_PAT="github_pat_xxxxxxxxxxxxxxxxxxxx"
API_PORT="8000"
EOF
chmod 600 .env
./run.sh        # Telegram bot
./start_api.sh  # HTTP API :8000 (Android/web app ke liye)
```

## 1b. Autostart (Lightning studio restart par sab wapas)

Teeno services **alag-alag, independent** start hoti hain (ek fail ho to baaki chalte hain):

| Service | Command | Lock | Log |
|---|---|---|---|
| Bot | `./run.sh` | `run.lockdir/` | `logs/bot_run.log` |
| API | `./start_api.sh` | `api.lockdir/` | `logs/api.log` |
| Tunnel | `./start_tunnel.sh` | `tunnel.lockdir/` | `logs/tunnel.log` |

Studio ke `.lightning_studio/on_start.sh` me teeno hooked hain (bot section pehle se tha; API + tunnel guard add hue) — restart par sab auto-start, kuch haath se nahi karna. Fresh phone link hamesha `logs/current_tunnel.txt` me milti hai (tunnel har restart par nayi URL deta hai).

Tunnel na chahiye to `on_start.sh` ka section-4 hata do (bot/API unaffected).

- `BOT_TOKEN` → @BotFather se (bot ka token).
- `GH_PAT` → GitHub → Settings → Developer settings → Personal access tokens:
  classic token with **`repo`** scope (ya fine-grained: repo select karke
  **Contents: Read and write**). Sirf backup-push ke liye chahiye.

## 2. Data recovery (studio delete ho jaye to)

```bash
git clone <repo> && cd <repo>
# attendance.db repo me hi hai — kuch aur copy nahi chahiye.
# Extra text copy: backups/attendance_YYYYMMDD.sql
# Holiday photos: holiday_proofs/  (DB ke bahar bhi safe)
```

SQL dump se restore (agar `.db` corrupt ho):

```bash
sqlite3 attendance.db < backups/attendance_YYYYMMDD.sql
```

## 3. Backup kaise chalta hai

| Trigger | Kaise |
|---|---|
| Roz 2 AM IST | Bot ka scheduler job (`backup_job`) → `backup.sh` |
| Har change par | Registration / attendance / holiday save ke baad background push (5 min debounce, fail-safe — bot reply block nahi hota) |
| Manual | `./backup.sh` |

- Push fail ho to commit local rehta hai, agli run me chala jata hai.
- Holiday photo har save par `holiday_proofs/DD-MM-YYYY.jpg` (ya `.txt`) me bhi export hoti hai — GitHub par khul kar dikhegi.
- Token kabhi repo me nahi jata (`.env` gitignored). PAT leak ho to GitHub se revoke karke `.env` me naya dalo.

## 4. Rollback (kuch toote to)

```bash
git log --oneline          # stable commit dhoondo
git checkout baseline-working-system   # ya koi commit hash
./run.sh
```
