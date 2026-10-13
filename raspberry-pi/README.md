# Raspberry Pi: CPU temperature alert

`cpu_temp_alert.py` reads `/sys/class/thermal/thermal_zone0/temp` and sends a
`priority: high` push when the CPU is above a threshold (default 75 °C). A cooldown
(default 30 minutes) stops it from repeating every run. Standard library only.

It checks once and exits, so schedule it.

## Quick test

```bash
IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=... TEMP_THRESHOLD_C=20 python3 cpu_temp_alert.py
```

## Option A: cron (every 5 minutes)

```cron
*/5 * * * * IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=xxxx /usr/bin/python3 /home/pi/cpu_temp_alert.py >/dev/null 2>&1
```

## Option B: systemd timer

Put the key in a root-only env file:

```bash
sudo install -m 600 /dev/null /etc/iotpush.env
sudo tee /etc/iotpush.env >/dev/null <<'EOF'
IOTPUSH_TOPIC=my-topic
IOTPUSH_TOPIC_KEY=replace-with-your-topic-key
TEMP_THRESHOLD_C=75
EOF
sudo install -m 755 cpu_temp_alert.py /usr/local/bin/iotpush-cpu-temp-alert
```

`/etc/systemd/system/iotpush-cpu-temp.service`

```ini
[Unit]
Description=iotPush CPU temperature alert
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
EnvironmentFile=/etc/iotpush.env
Environment=STATE_FILE=/var/lib/iotpush-cpu-temp/last
StateDirectory=iotpush-cpu-temp
ExecStart=/usr/bin/python3 /usr/local/bin/iotpush-cpu-temp-alert
DynamicUser=yes
```

`/etc/systemd/system/iotpush-cpu-temp.timer`

```ini
[Unit]
Description=Check CPU temperature every 5 minutes

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now iotpush-cpu-temp.timer
systemctl list-timers iotpush-cpu-temp.timer
journalctl -u iotpush-cpu-temp.service
```
