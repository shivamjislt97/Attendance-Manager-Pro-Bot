#!/bin/bash
# Attendance Bot — auto backup (code + DB + SQL dump + holiday proofs) -> GitHub
# Use: ./backup.sh              (nightly bot job + per-event hook + manual)
# Fail-safe: push fail ho to bhi local dump/commit safe rehta hai, next run retry.
cd "$(dirname "$0")"

# Secrets (.env gitignored hai)
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

TS=$(date +%Y%m%d)
mkdir -p backups holiday_proofs

# 1) SQL dump (text history — diff/restore ke liye)
if command -v sqlite3 >/dev/null 2>&1 && [ -f attendance.db ]; then
    sqlite3 attendance.db ".dump" > "backups/attendance_${TS}.sql" 2>/dev/null \
        && echo "✅ dump: backups/attendance_${TS}.sql" \
        || echo "⚠️ dump fail (DB busy?) — aage badho"
else
    echo "⚠️ sqlite3/attendance.db nahi mila — dump skip"
fi

# 2) Stage + commit (gitignore .env/*.bak/logs/locks ko bahar rakhta hai)
git add -A 2>/dev/null
if git diff --cached --quiet 2>/dev/null; then
    echo "ℹ️ koi change nahi — push skip"
    exit 0
fi
STU=$(sqlite3 attendance.db "SELECT count(*) FROM students;" 2>/dev/null || echo "?")
ATT=$(sqlite3 attendance.db "SELECT count(*) FROM attendance;" 2>/dev/null || echo "?")
HOL=$(sqlite3 attendance.db "SELECT count(*) FROM holiday_notices;" 2>/dev/null || echo "?")
git commit -m "auto-backup: ${TS} (students=${STU} attendance=${ATT} holidays=${HOL})" 2>&1 | tail -1

# 3) Push (PAT na ho to local commit rakho + warn)
if [ -z "$GH_PAT" ]; then
    echo "⚠️ GH_PAT nahi hai — commit local raha, push skip (.env me GH_PAT dalo)"
    exit 0
fi
if GIT_ASKPASS="$PWD/git_askpass.sh" GIT_TERMINAL_PROMPT=0 git push origin main 2>&1 | tail -2; then
    echo "✅ backup pushed"
else
    echo "⚠️ push fail — local commit safe hai, agli run me retry"
    exit 1
fi
