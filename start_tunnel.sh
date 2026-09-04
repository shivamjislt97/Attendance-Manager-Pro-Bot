#!/bin/bash
# Cloudflare Tunnel - start script (BOT/API se ALAG command!)
# ==================================================================
#  Lightning on_start.sh se linked hai — studio restart par auto-start.
#  Manual: cd /teamspace/studios/this_studio/attendance_bot && ./start_tunnel.sh
#
#  Ye script idempotent/safe hai:
#    * Tunnel pehle se RUNNING -> kuch NAHI karega (exit 0)
#    * Tunnel CRASHED/inactive  -> watchdog loop me wapas layega
#    * Binary /tmp me nahi (reboot wipe) -> dobara download karega
#  Bot/API se alag lock+log: ek fail ho to doosre chalte rahenge.
# ==================================================================
cd "$(dirname "$0")"

BIN="/tmp/cloudflared"
URL_FILE="$(cd "$(dirname "$0")" && pwd)/logs/current_tunnel.txt"
TUN_LOCKDIR="$(cd "$(dirname "$0")" && pwd)/tunnel.lockdir"
mkdir -p logs

# ---- 0) Binary lao (agar nahi hai) ----
if [ ! -x "$BIN" ]; then
    echo "⬇️  cloudflared download ho raha hai..."
    if ! curl -sL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o "$BIN"; then
        echo "❌ download fail — net check karo." >&2
        exit 1
    fi
    chmod +x "$BIN"
fi

# ---- 1) MKDIR atomic mutex (apna lockdir — bot/api se alag) ----
acquire_tunnel_lock() {
    for _try in 1 2 3; do
        if mkdir "$TUN_LOCKDIR" 2>/dev/null; then
            echo $$ > "$TUN_LOCKDIR/pid"
            return 0
        fi
        if [ -f "$TUN_LOCKDIR/pid" ] && kill -0 "$(cat "$TUN_LOCKDIR/pid" 2>/dev/null)" 2>/dev/null; then
            return 1   # koi aur tunnel-guard zinda hai
        fi
        rm -rf "$TUN_LOCKDIR" 2>/dev/null
        sleep 0.2
    done
    return 1
}
if ! acquire_tunnel_lock; then
    echo "ℹ️  Tunnel-guard pehle se CHALU hai — kuch nahi kiya. ✅"
    exit 0
fi
cleanup_lock() { rm -rf "$TUN_LOCKDIR"; }
trap cleanup_lock EXIT INT TERM

# ---- 2) PGREP: tunnel zinda hai to bas URL refresh karke niklo ----
# NOTE: poori ancestor-chain exclude karo - supervisor/tool shells ki
# cmdline me pattern hota hai (self-match false-SKIP bug fix).
_ancestor_pids() {
    local _skip=" $$" _a="$PPID"
    while [ -n "$_a" ] && [ "$_a" != "0" ] && [ "$_a" != "1" ]; do
        _skip="$_skip $_a"
        _a=$(ps -o ppid= -p "$_a" 2>/dev/null | tr -d ' ')
    done
    echo "$_skip"
}
alive_pgrep() {
    local _pat="$1" _p _skip
    _skip="$(_ancestor_pids) "
    for _p in $(pgrep -f "$_pat" 2>/dev/null); do
        case "$_skip" in
            *" $_p "*) ;;
            *) echo "$_p"; return 0 ;;
        esac
    done
    return 1
}
if alive_pgrep "cloudflared tun[n]el --url" >/dev/null 2>&1; then
    rm -rf "$TUN_LOCKDIR"
    echo "ℹ️  Tunnel already RUNNING hai — duplicate launch SKIP. ✅"
    exit 0
fi

# ---- 3) Watchdog loop (tunnel kabhi down na rahe) ----
echo "▶️  Tunnel-guard START (URL file: logs/current_tunnel.txt)..."
while true; do
    rm -f /tmp/tunnel_boot.log
    "$BIN" tunnel --url http://localhost:8000 > /tmp/tunnel_boot.log 2>&1 &
    TUN_PID=$!
    # URL aane tak wait (max 60s), persistent file + log me likho
    URL=""
    for _w in $(seq 1 60); do
        sleep 1
        URL=$(grep -a -o "https://[a-z0-9-]*\.trycloudflare\.com" /tmp/tunnel_boot.log 2>/dev/null | head -1)
        [ -n "$URL" ] && break
        kill -0 "$TUN_PID" 2>/dev/null || break
    done
    if [ -n "$URL" ]; then
        echo "$URL" > "$URL_FILE"
        echo "[$(date '+%F %T')] tunnel UP: $URL (pid $TUN_PID)"
    else
        echo "[$(date '+%F %T')] tunnel URL nahi mila — 10s me retry..." >&2
        kill "$TUN_PID" 2>/dev/null
        sleep 10
        continue
    fi
    wait "$TUN_PID"
    echo "[$(date '+%F %T')] tunnel gira (exit $?) — 5s me restart..."
    sleep 5
done
