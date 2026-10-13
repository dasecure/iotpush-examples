#!/usr/bin/env python3
"""Push a high-priority iotPush alert when the Raspberry Pi CPU runs hot.
Standard library only, Python 3.9+. Run it from cron or a systemd timer (see README.md).

Env:
    IOTPUSH_TOPIC        topic name (required)
    IOTPUSH_TOPIC_KEY    the topic's API key (private topics; omit for public ones)
    TEMP_THRESHOLD_C     alert above this temperature, default 75
    COOLDOWN_S           minimum seconds between alerts, default 1800
    STATE_FILE           where the last alert time is kept, default /tmp/iotpush_cpu_temp_alert.last
    THERMAL_FILE         default /sys/class/thermal/thermal_zone0/temp
    IOTPUSH_BASE         override the base URL (default https://www.iotpush.com)
"""
import json
import os
import socket
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("IOTPUSH_BASE", "https://www.iotpush.com").rstrip("/")
THERMAL_FILE = os.environ.get("THERMAL_FILE", "/sys/class/thermal/thermal_zone0/temp")
THRESHOLD_C = float(os.environ.get("TEMP_THRESHOLD_C", "75"))
COOLDOWN_S = int(os.environ.get("COOLDOWN_S", "1800"))
STATE_FILE = os.environ.get("STATE_FILE", "/tmp/iotpush_cpu_temp_alert.last")


def read_temp_c():
    with open(THERMAL_FILE) as f:
        return int(f.read().strip()) / 1000.0  # the kernel reports millidegrees


def in_cooldown():
    try:
        with open(STATE_FILE) as f:
            return time.time() - float(f.read().strip()) < COOLDOWN_S
    except (OSError, ValueError):
        return False


def push(topic, key, message, title):
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    body = {"message": message, "title": title, "priority": "high", "tags": "raspberry-pi,temperature"}
    req = urllib.request.Request(
        BASE + "/api/push/" + urllib.parse.quote(topic, safe=""),
        data=json.dumps(body).encode(), headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main():
    topic = os.environ.get("IOTPUSH_TOPIC")
    if not topic:
        sys.exit("set IOTPUSH_TOPIC")
    temp = read_temp_c()
    if temp <= THRESHOLD_C:
        print("CPU %.1f C, below %.1f C: ok" % (temp, THRESHOLD_C))
        return
    if in_cooldown():
        print("CPU %.1f C, above threshold but in cooldown: not sending" % temp)
        return
    host = socket.gethostname()
    try:
        result = push(topic, os.environ.get("IOTPUSH_TOPIC_KEY"),
                      "CPU at %.1f C on %s (threshold %.1f C)" % (temp, host, THRESHOLD_C),
                      "%s is running hot" % host)
    except urllib.error.HTTPError as e:
        sys.exit("push failed: HTTP %d %s" % (e.code, e.read().decode(errors="replace")))
    with open(STATE_FILE, "w") as f:
        f.write(str(time.time()))
    print("CPU %.1f C: alert sent, receipt_id %s" % (temp, result.get("receipt_id")))


if __name__ == "__main__":
    main()
