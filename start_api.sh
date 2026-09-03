#!/bin/bash
# Attendance API Server - start script (BOT se ALAG command!)
# ==================================================================
#  Lightning startup/cron me BOT wali command se ALAG paste karo:
#      cd /teamspace/studios/this_studio/attendance_bot && ./start_api.sh
#  Dono independent hain — ek fail ho to dusra chalta rahega.
#
#  Ye script idempotent/safe hai (run.sh jaisa guard):
#    * API pehle se RUNNING -> kuch NAHI karega (exit 0)
#    * API CRASHED/inactive  -> naya instance start hoga
# ==================================================================
cd "$(dirname "$0")"

# .env se secrets (BOT_TOKEN, GH_PAT, API_PORT)
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

PORT="${API_PORT:-8000}"

# ---- 1) MKDIR atomic mutex (apna lockdir — bot se alag) ----
API_LOCKDIR="$(cd "$(dirname "$0")" && pwd)/api.lockdir"
acquire_api_lock() {
    for _try in 1 2 3; do
        if mkdir "$API_LOCKDIR" 2>/dev/null; then
            echo $$ > "$API_LOCKDIR/pid"
            return 0
        fi
        if [ -f "$API_LOCKDIR/pid" ] && kill -0 "$(cat "$API_LOCKDIR/pid" 2>/dev/null)" 2>/dev/null; then
            return 1   # koi aur API zinda hai
        fi
        rm -rf "$API_LOCKDIR" 2>/dev/null
        sleep 0.2
    done
    return 1
}
if ! acquire_api_lock; then
    echo "ℹ️  API pehle se CHALU hai (api.lockdir active) — kuch nahi kiya. ✅"
    exit 0
fi

# ---- 2) PGREP: sirf API pattern (bot se takkar nahi) ----
if pgrep -f "uvicorn.*api:app" >/dev/null 2>&1; then
    rm -rf "$API_LOCKDIR"
    echo "ℹ️  API already RUNNING hai — duplicate launch SKIP. ✅"
    exit 0
fi

echo "▶️  Attendance API START ho rahi hai (port $PORT, single instance)..."
# NOTE: workers 1 fix hai — SQLite ke liye zaroori.
exec python3 -m uvicorn api:app --host 0.0.0.0 --port "$PORT" --workers 1
