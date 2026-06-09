#!/usr/bin/env bash
# daily-digest: post a 24h summary to Telegram from healthcheck logs.
# Runs once per day at 09:00 UTC via its own systemd timer (see README).

set -euo pipefail
IFS=$'\n\t'

LOG_FILE="${LOG_FILE:-/var/log/thunderstorm-healthcheck/check.log}"
STATE_DIR="${STATE_DIR:-/var/lib/thunderstorm-healthcheck}"
RESTART_COUNTER="${STATE_DIR}/restart-count"
ENV_FILE="${ENV_FILE:-/etc/thunderstorm-healthcheck.env}"

if [[ -r "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
fi

for var in TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID; do
    if [[ -z "${!var:-}" ]]; then
        echo "missing env $var" >&2
        exit 2
    fi
done

if [[ ! -r "$LOG_FILE" ]]; then
    echo "log $LOG_FILE not readable, skipping digest" >&2
    exit 0
fi

# Window = last 24h. Healthcheck runs every 5min → ideally 288 runs/day.
EXPECTED_RUNS=288
since=$(date -u -d "24 hours ago" +%s)

# Pull only log lines in window. Timestamps look like [2026-06-09T09:00:00Z]
awk_filter='
BEGIN { since='"$since"' }
match($0, /\[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z)\]/, m) {
    cmd = "date -u -d \"" m[1] "\" +%s"
    cmd | getline epoch
    close(cmd)
    if (epoch >= since) print $0
}
'

window=$(awk "$awk_filter" "$LOG_FILE" || true)

ok_runs=$(echo "$window" | grep -c '\[INFO\] OK' || true)
fail_runs=$(echo "$window" | grep -c '\[ERROR\] initial failures' || true)
restarts=$(echo "$window" | grep -c 'attempting restart' || true)
recoveries=$(echo "$window" | grep -c 'recovered after restart' || true)
escalations=$(echo "$window" | grep -c 'still failing after restart' || true)
total_runs=$(( ok_runs + fail_runs ))
if (( total_runs == 0 )); then total_runs=$EXPECTED_RUNS; fi

# Uptime % = OK runs / total runs. Cap at 100.
if (( total_runs > 0 )); then
    uptime_pct=$(awk -v ok="$ok_runs" -v tot="$total_runs" 'BEGIN { printf "%.1f", (ok/tot)*100 }')
else
    uptime_pct="n/a"
fi

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

msg=$(printf '%s\n<i>%s</i>\n\n<b>Uptime:</b> %s%% (%d/%d checks OK)\n<b>Restarts:</b> %d\n<b>Recoveries:</b> %d\n<b>Escalations:</b> %d' \
    "<b>Daily stream health summary</b>" \
    "$now" \
    "$uptime_pct" \
    "$ok_runs" \
    "$total_runs" \
    "$restarts" \
    "$recoveries" \
    "$escalations")

curl -sS --max-time 15 \
    -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=${msg}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "disable_web_page_preview=true" \
    >/dev/null

# Reset the rolling restart counter after the digest goes out
echo 0 > "$RESTART_COUNTER" 2>/dev/null || true
