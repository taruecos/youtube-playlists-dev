#!/usr/bin/env bash
# stream-thunderstorm.sh — 24/7 ambient YouTube livestream supervisor
#
# Continuously loops VIDEO_LOOP_PATH + AUDIO_LOOP_PATH through ffmpeg/NVENC
# to rtmp://a.rtmp.youtube.com/live2/$YT_STREAM_KEY. Designed to survive
# ffmpeg crashes, network blips, and YouTube ingest disconnects.
#
# Required env: YT_STREAM_KEY, VIDEO_LOOP_PATH, AUDIO_LOOP_PATH

set -u
set -o pipefail

# ---------- configuration ----------
LOG_DIR="/var/log/thunderstorm-stream"
LOG_FILE="${LOG_DIR}/stream.log"
RTMP_URL="rtmp://a.rtmp.youtube.com/live2"

# Encoder parameters — 1080p30 CBR 6000k h264_nvenc, AAC 128k 44.1kHz stereo
VIDEO_BITRATE="6000k"
VIDEO_MAXRATE="6000k"
VIDEO_BUFSIZE="12000k"      # 2x bitrate — YouTube ingest tolerates this best
AUDIO_BITRATE="128k"
AUDIO_SAMPLERATE="44100"
TARGET_FPS="30"
GOP_SIZE="60"               # keyframe every 2s @ 30fps (YouTube requirement)
NVENC_PRESET="p5"           # p1=fastest, p7=slowest; p5 = balanced quality
NVENC_TUNE="hq"
RESOLUTION="1920:1080"
PIXEL_FORMAT="yuv420p"

# Backoff
BACKOFF_MIN=5
BACKOFF_MAX=60
BACKOFF_RESET_AFTER=300     # 5 minutes of uptime resets backoff

# ---------- logging ----------
mkdir -p "${LOG_DIR}" 2>/dev/null || true

log() {
    local ts
    ts="$(date '+%Y-%m-%d %H:%M:%S%z')"
    # tee so both systemd journal (stdout) and rotated file get the line
    printf '[%s] %s\n' "${ts}" "$*" | tee -a "${LOG_FILE}" >/dev/null
    printf '[%s] %s\n' "${ts}" "$*"
}

# ---------- env validation ----------
missing=()
[[ -z "${YT_STREAM_KEY:-}"     ]] && missing+=("YT_STREAM_KEY")
[[ -z "${VIDEO_LOOP_PATH:-}"   ]] && missing+=("VIDEO_LOOP_PATH")
[[ -z "${AUDIO_LOOP_PATH:-}"   ]] && missing+=("AUDIO_LOOP_PATH")
if (( ${#missing[@]} > 0 )); then
    log "FATAL: missing required env vars: ${missing[*]}"
    exit 1
fi

if [[ ! -r "${VIDEO_LOOP_PATH}" ]]; then
    log "FATAL: VIDEO_LOOP_PATH not readable: ${VIDEO_LOOP_PATH}"
    exit 1
fi
if [[ ! -r "${AUDIO_LOOP_PATH}" ]]; then
    log "FATAL: AUDIO_LOOP_PATH not readable: ${AUDIO_LOOP_PATH}"
    exit 1
fi

# ---------- signal handling ----------
FFMPEG_PID=0
SHUTTING_DOWN=0

graceful_shutdown() {
    local sig="$1"
    SHUTTING_DOWN=1
    log "received ${sig}, shutting down"
    if (( FFMPEG_PID > 0 )) && kill -0 "${FFMPEG_PID}" 2>/dev/null; then
        log "sending SIGINT to ffmpeg pid ${FFMPEG_PID} for graceful YouTube disconnect"
        kill -SIGINT "${FFMPEG_PID}" 2>/dev/null || true
        # Wait up to 10s for ffmpeg to flush + disconnect cleanly
        for _ in {1..20}; do
            kill -0 "${FFMPEG_PID}" 2>/dev/null || break
            sleep 0.5
        done
        # If still alive, escalate
        if kill -0 "${FFMPEG_PID}" 2>/dev/null; then
            log "ffmpeg ignored SIGINT; sending SIGTERM"
            kill -SIGTERM "${FFMPEG_PID}" 2>/dev/null || true
            sleep 2
            kill -SIGKILL "${FFMPEG_PID}" 2>/dev/null || true
        fi
    fi
    log "exit"
    exit 0
}

trap 'graceful_shutdown SIGTERM' SIGTERM
trap 'graceful_shutdown SIGINT'  SIGINT

# ---------- ffmpeg invocation ----------
# Notes on flags:
#   -re                    realtime input pacing (one frame per wallclock frame)
#   -stream_loop -1        loop input infinitely
#   -fflags +genpts        regenerate pts so loop boundaries don't cause jumps
#   -vsync cfr             constant framerate output (YouTube prefers this)
#   -rc cbr -b:v=maxrate   true CBR for stable ingest bitrate
#   -g / -keyint_min       hard GOP every 60 frames, no scene-cut keyframes
#   -sc_threshold 0        disable scene-change keyframes (CBR-friendly)
#   -bf 2                  2 B-frames; NVENC handles this well
#   -map 0:v -map 1:a      explicit stream selection
#   -shortest NOT used     we want infinite — both inputs loop independently
run_ffmpeg() {
    ffmpeg \
        -hide_banner \
        -loglevel warning \
        -nostats \
        -fflags +genpts \
        -re -stream_loop -1 -i "${VIDEO_LOOP_PATH}" \
        -re -stream_loop -1 -i "${AUDIO_LOOP_PATH}" \
        -map 0:v:0 -map 1:a:0 \
        -vf "scale=${RESOLUTION}:force_original_aspect_ratio=decrease,pad=${RESOLUTION}:(ow-iw)/2:(oh-ih)/2,format=${PIXEL_FORMAT},fps=${TARGET_FPS}" \
        -c:v h264_nvenc \
        -preset "${NVENC_PRESET}" \
        -tune "${NVENC_TUNE}" \
        -profile:v high \
        -rc cbr \
        -b:v "${VIDEO_BITRATE}" \
        -maxrate "${VIDEO_MAXRATE}" \
        -minrate "${VIDEO_BITRATE}" \
        -bufsize "${VIDEO_BUFSIZE}" \
        -g "${GOP_SIZE}" \
        -keyint_min "${GOP_SIZE}" \
        -sc_threshold 0 \
        -bf 2 \
        -b_ref_mode middle \
        -spatial-aq 1 \
        -temporal-aq 1 \
        -rc-lookahead 20 \
        -vsync cfr \
        -c:a aac \
        -b:a "${AUDIO_BITRATE}" \
        -ar "${AUDIO_SAMPLERATE}" \
        -ac 2 \
        -f flv \
        -flvflags no_duration_filesize \
        "${RTMP_URL}/${YT_STREAM_KEY}" \
        >> "${LOG_FILE}" 2>&1 &

    FFMPEG_PID=$!
    log "ffmpeg started pid=${FFMPEG_PID}"
    wait "${FFMPEG_PID}"
    local rc=$?
    FFMPEG_PID=0
    return ${rc}
}

# ---------- supervisor loop ----------
backoff=${BACKOFF_MIN}
log "supervisor starting — video=${VIDEO_LOOP_PATH} audio=${AUDIO_LOOP_PATH}"

while (( SHUTTING_DOWN == 0 )); do
    start_ts=$(date +%s)
    run_ffmpeg
    rc=$?
    end_ts=$(date +%s)
    uptime=$(( end_ts - start_ts ))

    if (( SHUTTING_DOWN == 1 )); then
        break
    fi

    log "ffmpeg exited rc=${rc} after ${uptime}s"

    if (( uptime >= BACKOFF_RESET_AFTER )); then
        log "uptime ${uptime}s >= ${BACKOFF_RESET_AFTER}s, resetting backoff"
        backoff=${BACKOFF_MIN}
    fi

    log "restarting in ${backoff}s"
    # Interruptible sleep so signals reach us promptly
    for (( i = 0; i < backoff; i++ )); do
        (( SHUTTING_DOWN == 1 )) && break
        sleep 1
    done

    # Exponential backoff capped at BACKOFF_MAX
    backoff=$(( backoff * 2 ))
    (( backoff > BACKOFF_MAX )) && backoff=${BACKOFF_MAX}
done

log "supervisor exiting"
