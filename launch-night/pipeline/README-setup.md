# Thunderstorm 24/7 YouTube Livestream — Setup

Target host: Windows 11 tower with NVIDIA GPU + CUDA 12.9, running WSL2 Ubuntu.
Pipeline: `ffmpeg` (NVENC h264) loops one video + one audio file forever and
pushes to `rtmp://a.rtmp.youtube.com/live2/<STREAM_KEY>`.

---

## 1. Enable systemd inside WSL2

WSL2 does not run systemd by default. Edit (create if missing) `/etc/wsl.conf`
**inside the WSL2 distro**:

```ini
[boot]
systemd=true

[network]
generateResolvConf=true
```

Then from **Windows PowerShell** (not WSL):

```powershell
wsl --shutdown
```

Re-open the WSL2 terminal. Verify:

```bash
ps -p 1 -o comm=     # should print "systemd"
systemctl --version  # should not error
```

---

## 2. Install ffmpeg with NVENC support

```bash
sudo apt update
sudo apt install -y ffmpeg
ffmpeg -encoders 2>/dev/null | grep -i nvenc
# expect: V....D h264_nvenc           NVIDIA NVENC H.264 encoder
```

If `h264_nvenc` is missing, the distro ffmpeg was built without NVENC. Either:
- Install a newer ffmpeg via the official static build, or
- Build ffmpeg from source against the NVIDIA codec headers.

Sanity-check the GPU is visible inside WSL2:

```bash
nvidia-smi   # should list the GPU. WSL2 + CUDA 12.9 is supported out of the box.
```

---

## 3. Lay down the files

```bash
sudo mkdir -p /home/atlas/youtube-stream/assets
sudo mkdir -p /var/log/thunderstorm-stream
sudo chown -R atlas:atlas /home/atlas/youtube-stream /var/log/thunderstorm-stream

# Copy the deliverables (assumed already on disk at /tmp/youtube-stream-pipeline/)
sudo install -m 0755 -o atlas -g atlas \
    /tmp/youtube-stream-pipeline/stream-thunderstorm.sh \
    /home/atlas/youtube-stream/stream-thunderstorm.sh

sudo install -m 0644 \
    /tmp/youtube-stream-pipeline/thunderstorm-stream.service \
    /etc/systemd/system/thunderstorm-stream.service

sudo install -m 0644 \
    /tmp/youtube-stream-pipeline/logrotate.conf \
    /etc/logrotate.d/thunderstorm-stream
```

Drop your assets in place:

```bash
cp /path/to/thunderstorm-loop.mp4  /home/atlas/youtube-stream/assets/
cp /path/to/thunderstorm-audio.mp3 /home/atlas/youtube-stream/assets/
```

---

## 4. Create the env file with the real stream key

```bash
sudo cp /tmp/youtube-stream-pipeline/thunderstorm-stream.env.example \
        /etc/thunderstorm-stream.env
sudoedit /etc/thunderstorm-stream.env       # paste real YT_STREAM_KEY
sudo chown root:root /etc/thunderstorm-stream.env
sudo chmod 600       /etc/thunderstorm-stream.env
```

Get the stream key from <https://studio.youtube.com/> → Create → Go live →
Stream → Stream key (under "Stream settings"). Use a *persistent* key so the
URL doesn't change between sessions.

---

## 5. Enable + start the service

```bash
sudo systemctl daemon-reload
sudo systemctl enable thunderstorm-stream.service
sudo systemctl start  thunderstorm-stream.service
sudo systemctl status thunderstorm-stream.service
```

---

## 6. View logs

```bash
# Live tail of supervisor + ffmpeg output
tail -F /var/log/thunderstorm-stream/stream.log

# systemd-level events (start/stop/restart)
tail -F /var/log/thunderstorm-stream/systemd.log

# Journal (last hour)
journalctl -u thunderstorm-stream.service --since "1 hour ago"
```

YouTube's Live Control Room dashboard will show "Receiving data" within
~15 seconds of `ffmpeg` starting. If it doesn't, check:
1. Stream key is correct and the channel is in "Stream" mode.
2. Outbound TCP 1935 (RTMP) is not blocked by Windows Firewall.
3. The bitrate isn't being throttled (check Windows Resource Monitor).

---

## 7. Survive a Windows reboot

WSL2 distros don't auto-start with Windows. Two options:

### Option A — Task Scheduler (recommended)

1. Open **Task Scheduler** → **Create Task**.
2. **General** tab:
   - Name: `WSL Thunderstorm Stream`
   - "Run whether user is logged on or not"
   - "Run with highest privileges"
3. **Triggers** tab → New:
   - "At startup"
   - Delay task for: 1 minute (gives the network stack time to come up)
4. **Actions** tab → New:
   - Program/script: `C:\Windows\System32\wsl.exe`
   - Arguments: `-d Ubuntu -u atlas -- /bin/bash -lc "sudo systemctl start thunderstorm-stream.service"`
   - (Replace `Ubuntu` with the output of `wsl -l -q` if your distro is named differently.)
5. **Conditions** tab → uncheck "Start only on AC power" (desktop has no battery, but be safe).
6. **Settings** tab → check "If the task fails, restart every 1 minute, attempt 3 times".

For `sudo systemctl start` to work non-interactively, allow passwordless start
of just this unit:

```bash
sudo visudo -f /etc/sudoers.d/thunderstorm-stream
# Add:
atlas ALL=(root) NOPASSWD: /usr/bin/systemctl start thunderstorm-stream.service, /usr/bin/systemctl stop thunderstorm-stream.service, /usr/bin/systemctl restart thunderstorm-stream.service
```

### Option B — Run as the WSL distro's default boot command

In `/etc/wsl.conf`:

```ini
[boot]
systemd=true
command="systemctl start thunderstorm-stream.service"
```

This still requires *something* to launch the WSL2 distro on Windows boot.
Pair it with a minimal Task Scheduler entry that just runs `wsl -d Ubuntu -- true`
at startup (forces the distro to boot, then `command=` fires).

### After Windows Update reboots

Windows Update reboots are unavoidable. Both Option A and Option B handle them
transparently — within 1-2 minutes of Windows finishing boot, WSL2 starts,
systemd starts, the unit starts, and YouTube sees the stream resume. Expect
a ~3-5 minute gap on YouTube's side; viewers see "Live stream offline" briefly
then auto-reconnect.

---

## 8. Operational notes

- **Log rotation** runs daily via logrotate (`/etc/logrotate.d/thunderstorm-stream`).
  14 days of compressed history, `copytruncate` so ffmpeg's open fd survives.
- **Stop the stream**: `sudo systemctl stop thunderstorm-stream.service`
  Sends SIGTERM; the script forwards SIGINT to ffmpeg, which flushes and
  disconnects from YouTube cleanly (no "stream crashed" notice in Studio).
- **Swap the assets without downtime**: replace the files in
  `/home/atlas/youtube-stream/assets/`, then `sudo systemctl restart
  thunderstorm-stream.service`. There will be a ~10s gap on YouTube; the
  ingest stays alive for ~30s so viewers usually don't disconnect.
- **Health check from outside**: YouTube Studio → Stream Health.
  Green = good. Yellow = bitrate fluctuating (check upload bandwidth).
  Red = ingest dropped (the supervisor will reconnect automatically; check
  `stream.log` for the cause).
