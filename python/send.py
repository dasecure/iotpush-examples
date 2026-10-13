#!/usr/bin/env python3
"""Send a push to an iotPush topic. Standard library only, Python 3.9+.

Usage:
    IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=... python3 send.py "Backup finished" \
        [--title T] [--priority low|normal|high|urgent] [--tags a,b] [--click URL]

Env:
    IOTPUSH_TOPIC      topic name (required)
    IOTPUSH_TOPIC_KEY  the topic's API key (required for private topics, omit for public ones)
    IOTPUSH_BASE       override the base URL (default https://www.iotpush.com)
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("IOTPUSH_BASE", "https://www.iotpush.com").rstrip("/")


def send(topic, message, title=None, priority=None, tags=None, click_url=None, key=None):
    payload = {"message": message}
    if title:
        payload["title"] = title  # JSON body: non-ASCII titles are fine here
    if priority:
        payload["priority"] = priority
    if tags:
        payload["tags"] = tags
    if click_url:
        payload["click_url"] = click_url
    headers = {"Content-Type": "application/json"}
    if key:
        headers["Authorization"] = "Bearer " + key
    req = urllib.request.Request(
        BASE + "/api/push/" + urllib.parse.quote(topic, safe=""),
        data=json.dumps(payload).encode(),
        headers=headers,
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.load(resp)


def main():
    p = argparse.ArgumentParser(description="Send an iotPush notification")
    p.add_argument("message")
    p.add_argument("-t", "--title")
    p.add_argument("-p", "--priority", choices=["low", "normal", "high", "urgent"])
    p.add_argument("--tags", help="comma separated, e.g. backup,nas")
    p.add_argument("-c", "--click", help="URL opened when the notification is tapped")
    a = p.parse_args()

    topic = os.environ.get("IOTPUSH_TOPIC")
    if not topic:
        sys.exit("set IOTPUSH_TOPIC")
    try:
        result = send(topic, a.message, a.title, a.priority, a.tags, a.click,
                      os.environ.get("IOTPUSH_TOPIC_KEY"))
    except urllib.error.HTTPError as e:
        # 429 = over the Free plan's monthly push limit
        sys.exit("push failed: HTTP %d %s" % (e.code, e.read().decode(errors="replace")))
    print("sent, receipt_id:", result.get("receipt_id"))


if __name__ == "__main__":
    main()
