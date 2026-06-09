# Thunderstorm YouTube Livestream Healthcheck

Monitors a 24/7 ambient YouTube livestream running as `thunderstorm-stream.service` inside WSL2. Checks systemd, the ffmpeg process, and the YouTube Data API every 5 minutes. On failure: logs, auto-restarts, retries, and alerts via Telegram. Once per day at 09:00 UTC posts a digest.

## Files

| File | Destination |
| --- | --- |
| `healthcheck.sh` | `/usr/local/bin/thunderstorm-healthcheck.sh` (chmod 0755) |
| `daily-digest.sh` | `/usr/local/bin/thunderstorm-daily-digest.sh` (chmod 0755) |
| `thunderstorm-healthcheck.service` | `/etc/systemd/system/thunderstorm-healthcheck.service` |
| `thunderstorm-healthcheck.timer` | `/etc/systemd/system/thunderstorm-healthcheck.timer` |
| env file (you create) | `/etc/thunderstorm-healthcheck.env` (chmod 0640, root:root) |

Working directories are created on first run:

- `/var/log/thunderstorm-healthcheck/check.log` — append-only check log
- `/var/lib/thunderstorm-healthcheck/restart-count` — rolling restart counter, reset each daily digest

## Env file format — `/etc/thunderstorm-healthcheck.env`

```
TELEGRAM_BOT_TOKEN=123456:AAA...
TELEGRAM_CHAT_ID=-1001234567890
YT_API_KEY=AIzaSy...
YT_CHANNEL_ID=UCxxxxxxxxxxxxxxxxxxxxxx
# optional overrides
# SERVICE_NAME=thunderstorm-stream.service
# STREAM_LOG=/var/log/thunderstorm-stream/stream.log
```

Lock it down:

```bash
sudo install -o root -g root -m 0640 thunderstorm-healthcheck.env /etc/thunderstorm-healthcheck.env
```

## Install

```bash
# 1. Place the scripts
sudo install -o root -g root -m 0755 healthcheck.sh    /usr/local/bin/thunderstorm-healthcheck.sh
sudo install -o root -g root -m 0755 daily-digest.sh   /usr/local/bin/thunderstorm-daily-digest.sh

# 2. Place the systemd units
sudo install -o root -g root -m 0644 thunderstorm-healthcheck.service /etc/systemd/system/
sudo install -o root -g root -m 0644 thunderstorm-healthcheck.timer   /etc/systemd/system/

# 3. Prep log + state dirs
sudo mkdir -p /var/log/thunderstorm-healthcheck /var/lib/thunderstorm-healthcheck
sudo chmod 0755 /var/log/thunderstorm-healthcheck /var/lib/thunderstorm-healthcheck

# 4. Enable + start the timer (5-min healthcheck)
sudo systemctl daemon-reload
sudo systemctl enable --now thunderstorm-healthcheck.timer

# 5. Verify
systemctl list-timers thunderstorm-healthcheck.timer
journalctl -u thunderstorm-healthcheck.service -f
```

## Daily digest timer

A second timer fires `daily-digest.sh` at 09:00 UTC. Use a calendar timer (no service file needed beyond a tiny wrapper):

```bash
sudo tee /etc/systemd/system/thunderstorm-daily-digest.service >/dev/null <<'UNIT'
[Unit]
Description=Thunderstorm livestream daily digest (Telegram)
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/thunderstorm-healthcheck.env
ExecStart=/usr/local/bin/thunderstorm-daily-digest.sh
UNIT

sudo tee /etc/systemd/system/thunderstorm-daily-digest.timer >/dev/null <<'UNIT'
[Unit]
Description=Run thunderstorm daily digest at 09:00 UTC

[Timer]
OnCalendar=*-*-* 09:00:00 UTC
Persistent=true
Unit=thunderstorm-daily-digest.service

[Install]
WantedBy=timers.target
UNIT

sudo systemctl daemon-reload
sudo systemctl enable --now thunderstorm-daily-digest.timer
```

## Manual testing

Run the healthcheck once, as if invoked by the timer:

```bash
sudo systemctl start thunderstorm-healthcheck.service
journalctl -u thunderstorm-healthcheck.service -n 50 --no-pager
sudo tail -n 20 /var/log/thunderstorm-healthcheck/check.log
```

Force the alert path without killing the stream — uses `FORCE_FAIL=1` and exits before restart logic:

```bash
sudo FORCE_FAIL=1 /usr/local/bin/thunderstorm-healthcheck.sh
```

You should see a Telegram message prefixed `[TEST] Stream healthcheck failure` within a few seconds. If you don't, check:

1. `sudo tail /var/log/thunderstorm-healthcheck/check.log` for `telegram` errors
2. Env file is readable and has all 4 vars
3. Bot is actually in the chat / has permission to post

Fire the digest manually:

```bash
sudo systemctl start thunderstorm-daily-digest.service
```

## WSL2 notes

- This repo prefers a systemd timer over cron because cron in WSL2 dies when the distro shuts down and doesn't catch up on resume. `Persistent=true` plus `OnBootSec` means the timer catches missed runs after Windows sleeps or restarts.
- Make sure `systemd` is enabled in WSL2 (`/etc/wsl.conf` → `[boot]\nsystemd=true`). Without it, none of the units will fire.
- The healthcheck script bounds its YouTube API call to 20s and Telegram calls to 15s so it can never block the next 5-min tick.

## Exit codes

| Code | Meaning |
| --- | --- |
| 0 | All checks OK, or recovered after restart, or FORCE_FAIL test path |
| 1 | Still failing after auto-restart — alert was sent |
| 2 | Misconfiguration (missing env vars) |

`SuccessExitStatus=0 1` in the service unit keeps escalated failures (exit 1) from polluting `systemctl --failed` since the script already alerted Tariq via Telegram.
