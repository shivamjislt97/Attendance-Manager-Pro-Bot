#!/bin/bash
# Student Attendance Manager Bot - run script
# ==================================================================
#  SINGLE-INSTANCE GUARD (bahut important!):
#  Telegram ek bot token par SIRF EK hi polling instance allow karta hai.
#  2+ instances chalne par -> "Conflict: terminated by other getUpdates
#  request" error -> users ke buttons/messages miss ho jaate hain.
#
#  Ye run.sh hamesha SAFE hai (idempotent):
#    * Bot pahle se ACTIVE/running -> kuch NAHI karega (exit 0)
#    * Bot CRASHED/inactive        -> naya instance START karega
#    * 2 log EK SAATH chalayein (race) -> flock sirf 1 ko start karne dega
#
#  Use (multiple terminal se bhi chalao, phir bhi EK hi bot chalega):
#      cd /teamspace/studios/this_studio/attendance_bot && ./run.sh
# ==================================================================
cd "$(dirname "$0")"

# .env se secrets load karo (BOT_TOKEN etc.) — .env gitignored hai, kabhi commit nahi hoti
if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
fi

# Token env var se aa sakta hai: BOT_TOKEN="123456:AAxx..." ./run.sh
# ya config.py mein direct paste karo
if [ -z "$BOT_TOKEN" ]; then
    echo "⚠️  BOT_TOKEN env var set nahi hai - config.py wala use hoga"
fi

# Lock file run.sh ke paas hi rakho (per-bot lock)
LOCK_FILE="$(cd "$(dirname "$0")" && pwd)/run.lock"
exec 9>"$LOCK_FILE"

# ---- 1) MKDIR atomic mutex (overlayfs-safe, primary guard) ----
# Is container ke overlayfs par flock kabhi-kabhi inode-race de deta hai
# (2 alag inode par lock -> dono pass ho jaate hain). 'mkdir' hamesha atomic hai.
RUN_LOCKDIR="$(cd "$(dirname "$0")" && pwd)/run.lockdir"
acquire_run_lock() {
    for _try in 1 2 3; do
        if mkdir "$RUN_LOCKDIR" 2>/dev/null; then
            echo $$ > "$RUN_LOCKDIR/pid"
            return 0
        fi
        # lockdir maujood hai — kya holder zinda hai?
        if [ -f "$RUN_LOCKDIR/pid" ] && kill -0 "$(cat "$RUN_LOCKDIR/pid" 2>/dev/null)" 2>/dev/null; then
            return 1   # koi aur bot zinda hai
        fi
        # stale lockdir (crash/exit) -> hatao aur dobara try
        rm -rf "$RUN_LOCKDIR" 2>/dev/null
        sleep 0.2
    done
    return 1
}
if ! acquire_run_lock; then
    echo "ℹ️  Bot pehle se CHALU hai (run.lockdir active) — kuch nahi kiya."
    echo "    Sirf EK bot active rahega, no conflict. ✅"
    exit 0
fi

# ---- 2) FLOCK: do launcher ek saath challenge par bhi sirf EK hi aage badhega.
#    (secondary guard — mkdir se peekar dono process dismiss hone par bhi safe)
if command -v flock >/dev/null 2>&1; then
    if ! flock -n 9; then
        rm -rf "$RUN_LOCKDIR"
        echo "ℹ️  Bot pehle se CHALU hai (run.lock active) — kuch nahi kiya."
        echo "    Sirf EK bot active rahega, no conflict. ✅"
        exit 0
    fi
fi

# ---- 3) PGREP: koi bot instance zinda hai (final backup check)
if pgrep -f "python.*bot\.py" >/dev/null 2>&1; then
    rm -rf "$RUN_LOCKDIR"
    echo "ℹ️  Bot already RUNNING hai — duplicate launch SKIP. ✅"
    echo "    Sirf EK bot active rahega, no conflict."
    exit 0
fi

echo "▶️  Attendance bot START ho raha hai (single instance)..."
# NOTE: exec => fd 9 (flock) isi python ke paas rehta hai jab tak bot zinda hai.
# Bot crash/exit hote hi flock release aur run.lockdir stale -> dobara start.
exec python3 bot.py
