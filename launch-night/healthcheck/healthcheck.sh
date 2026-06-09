#!/usr/bin/env bash
# thunderstorm-healthcheck: monitor 24/7 YouTube ambient livestream
# Runs every 5 minutes via systemd timer. Silent on success, alerts on failure.

set -euo pipefail
IFS=$'\n\t'

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
SERVICE_NAME="${SERVICE_NAME:-thunderstorm-stream.service}"
LOG_DIR="${LOG_DIR:-/var/log/thunderstorm-healthcheck}"
LOG_FILE="${LOG_FILE:-${LOG_DIR}/check.log}"
STREAM_LOG="${STREAM_LOG:-/var/log/thunderstorm-stream/stream.log}"
STATE_DIR="${STATE_DIR:-/var/lib/thunderstorm-healthcheck}"
RESTART_COUNTER="${STATE_DIR}/restart-count"
ENV_FILE="${ENV_FILE:-/etc/thunderstorm-healthcheck.env}"

# Load env file if present (no-op if running with pre-set env, e.g. systemd)
if [[ -r "$ENV_FILE" ]]; then
    # shellcheck disable=SC1090
    set -a; source "$ENV_FILE"; set +a
fi

# -----------------------------------------------------------------------------
# Logging helpers
# -----------------------------------------------------------------------------
mkdir -p "$LOG_DIR" "$STATE_DIR" 2>/dev/null || true

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

log() {
    local level="$1"; shift
    local line="[$(ts)] [$level] $*"
    echo "$line" | tee -a "$LOG_FILE" >&2
}

trap 'log ERROR "healthcheck crashed at line $LINENO (exit=$?)"' ERR

# -----------------------------------------------------------------------------
# Env validation
# -----------------------------------------------------------------------------
require_env() {
    local missing=()
    for var in TELEGRAM_BOT_TOKEN TELEGRAM_CHAT_ID YT_API_KEY YT_CHANNEL_ID; do
        if [[ -z "${!var:-}" ]]; then
            missing+=("$var")
        fi
    done
    if (( ${#missing[@]} > 0 )); then
        log FATAL "missing required env vars: ${missing[*]}"
        exit 2
    fi
}

# -----------------------------------------------------------------------------
# Telegram
# -----------------------------------------------------------------------------
telegram_send() {
    local text="$1"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    local resp
    resp=$(curl -sS --max-time 15 -X POST "$url" \
        --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
        --data-urlencode "text=${text}" \
        --data-urlencode "parse_mode=HTML" \
        --data-urlencode "disable_web_page_preview=true" \
        2>&1) || {
            log ERROR "telegram curl failed: $resp"
            return 1
        }
    if ! echo "$resp" | jq -e '.ok == true' >/dev/null 2>&1; then
        log ERROR "telegram API rejected message: $resp"
        return 1
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Checks (return 0 = OK, non-zero = FAIL, echo reason on stdout)
# -----------------------------------------------------------------------------
check_systemd() {
    local status
    status=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || true)
    if [[ "$status" != "active" ]]; then
        echo "systemd: ${SERVICE_NAME} is '${status:-unknown}' (expected active)"
        return 1
    fi
    return 0
}

check_ffmpeg() {
    if ! pgrep -f "ffmpeg.*rtmp://a.rtmp.youtube.com" >/dev/null 2>&1; then
        echo "ffmpeg: no process matching rtmp://a.rtmp.youtube.com"
        return 1
    fi
    return 0
}

check_youtube_api() {
    local url="https://www.googleapis.com/youtube/v3/search"
    url+="?part=snippet&channelId=${YT_CHANNEL_ID}&eventType=live&type=video&key=${YT_API_KEY}"
    local resp
    resp=$(curl -sS --max-time 20 "$url" 2>&1) || {
        echo "youtube_api: curl failed: $resp"
        return 1
    }
    # Detect API error envelope (quota exceeded, bad key, etc.)
    if echo "$resp" | jq -e '.error' >/dev/null 2>&1; then
        local err
        err=$(echo "$resp" | jq -r '.error.message // "unknown error"')
        echo "youtube_api: API error: $err"
        return 1
    fi
    local count
    count=$(echo "$resp" | jq -r '.items | length' 2>/dev/null || echo 0)
    if [[ "$count" -eq 0 ]]; then
        echo "youtube_api: no live items returned for channel ${YT_CHANNEL_ID}"
        return 1
    fi
    return 0
}

# Optional bandwidth check — best-effort, never fatal
check_bandwidth() {
    if [[ ! -r "$STREAM_LOG" ]]; then
        log INFO "bandwidth: stream log $STREAM_LOG not readable, skipping"
        return 0
    fi
    # Grab last bitrate= line in the last 5 minutes worth of log (rough heuristic: last 500 lines)
    local last_bitrate
    last_bitrate=$(tail -n 500 "$STREAM_LOG" 2>/dev/null | grep -oE 'bitrate=[ ]*[0-9.]+kbits/s' | tail -n 1 || true)
    if [[ -n "$last_bitrate" ]]; then
        log INFO "bandwidth: last reported $last_bitrate"
    else
        log INFO "bandwidth: no bitrate found in recent log"
    fi
    return 0
}

# -----------------------------------------------------------------------------
# Restart + recovery
# -----------------------------------------------------------------------------
increment_restart_count() {
    local current=0
    [[ -f "$RESTART_COUNTER" ]] && current=$(cat "$RESTART_COUNTER" 2>/dev/null || echo 0)
    echo $((current + 1)) > "$RESTART_COUNTER"
}

restart_service() {
    log WARN "attempting restart of ${SERVICE_NAME}"
    if systemctl restart "$SERVICE_NAME" 2>&1 | tee -a "$LOG_FILE" >&2; then
        increment_restart_count
        log INFO "restart command issued, sleeping 30s for service to settle"
        sleep 30
        return 0
    else
        log ERROR "systemctl restart failed"
        return 1
    fi
}

tail_stream_log() {
    if [[ -r "$STREAM_LOG" ]]; then
        tail -n 10 "$STREAM_LOG" 2>/dev/null | sed 's/[<>&]//g' || echo "(stream log unreadable)"
    else
        echo "(stream log $STREAM_LOG not found)"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    require_env

    local now; now=$(ts)
    local failures=()

    # Manual test path: simulate a failure without touching the service
    if [[ "${FORCE_FAIL:-0}" == "1" ]]; then
        log WARN "FORCE_FAIL=1 — simulating failure path (no restart will occur)"
        local snippet; snippet=$(tail_stream_log)
        local msg
        msg=$(printf '%s\n%s\n\n<b>Failed checks:</b>\n- %s\n\n<b>Restart:</b> skipped (FORCE_FAIL)\n\n<b>Last log lines:</b>\n<pre>%s</pre>' \
            "<b>[TEST] Stream healthcheck failure</b>" \
            "<i>$now</i>" \
            "forced failure injection" \
            "$snippet")
        telegram_send "$msg" || log ERROR "failed to send test alert"
        log INFO "FORCE_FAIL test alert dispatched"
        exit 0
    fi

    # Pass 1
    local reason
    if ! reason=$(check_systemd); then failures+=("$reason"); fi
    if ! reason=$(check_ffmpeg); then failures+=("$reason"); fi
    if ! reason=$(check_youtube_api); then failures+=("$reason"); fi
    check_bandwidth

    if (( ${#failures[@]} == 0 )); then
        log INFO "OK"
        exit 0
    fi

    # FAILURE path
    local initial_failures="${failures[*]}"
    log ERROR "initial failures: ${initial_failures}"

    local restart_result="ok"
    if ! restart_service; then
        restart_result="failed"
    fi

    # Pass 2 — skip YouTube API (takes 1-2 min to re-register)
    failures=()
    if ! reason=$(check_systemd); then failures+=("$reason"); fi
    if ! reason=$(check_ffmpeg); then failures+=("$reason"); fi

    local recovery_ts; recovery_ts=$(ts)

    if (( ${#failures[@]} == 0 )); then
        log INFO "recovered after restart at $recovery_ts"
        local msg
        msg=$(printf '%s\n<i>%s</i>\n\nInitial failures:\n<pre>%s</pre>' \
            "<b>Stream recovered after auto-restart</b>" \
            "$recovery_ts" \
            "$initial_failures")
        telegram_send "$msg" || log ERROR "failed to send recovery alert"
        exit 0
    fi

    # Still failing — escalate
    log ERROR "still failing after restart: ${failures[*]}"
    local snippet; snippet=$(tail_stream_log)
    local msg
    msg=$(printf '%s\n<i>%s</i>\n\n<b>Failed checks (post-restart):</b>\n%s\n\n<b>Restart attempt:</b> %s\n\n<b>Last 10 stream log lines:</b>\n<pre>%s</pre>' \
        "<b>Stream DOWN — manual intervention needed</b>" \
        "$recovery_ts" \
        "$(printf -- '- %s\n' "${failures[@]}")" \
        "$restart_result" \
        "$snippet")
    telegram_send "$msg" || log ERROR "failed to send failure alert"
    exit 1
}

main "$@"
