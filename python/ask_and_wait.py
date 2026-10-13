#!/usr/bin/env python3
"""Ask an Approve/Reject question on your phone and block until it is answered.
Standard library only, Python 3.9+.

Usage:
    IOTPUSH_API_KEY=iop_live_... python3 ask_and_wait.py "Deploy v2.4 to production?" [--title T] [--timeout 300]

Env:
    IOTPUSH_API_KEY  ACCOUNT API key (iop_live_...) with scopes questions:ask + questions:read,
                     created at https://www.iotpush.com/dashboard/settings -> API keys.
                     A per-topic key will not work here.
    IOTPUSH_TOPIC    optional topic name (optional if the account has one)
    IOTPUSH_BASE     override the base URL (default https://www.iotpush.com)

Exit codes: 0 approved (the ONLY "go ahead"), 1 rejected,
            2 no decision (expired / cancelled / interrupted), 3 error (e.g. HTTP 402 = approvals used up).
"""
import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

BASE = os.environ.get("IOTPUSH_BASE", "https://www.iotpush.com").rstrip("/")


def api(method, path, key, body=None):
    headers = {"Authorization": "Bearer " + key}
    data = None
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    req = urllib.request.Request(BASE + path, data=data, headers=headers, method=method)
    with urllib.request.urlopen(req, timeout=70) as resp:  # wait calls hold up to 55 s
        return json.load(resp)


def ask_and_wait(key, question, title=None, topic=None, timeout_s=300):
    """Returns the final question JSON. status is answered, expired or cancelled."""
    body = {"question": question, "kind": "confirm", "timeout_s": timeout_s}
    if title:
        body["title"] = title
    if topic:
        body["topic"] = topic
    qid = api("POST", "/api/v1/questions", key, body)["question_id"]
    qpath = "/api/v1/questions/" + urllib.parse.quote(qid, safe="")
    print("asked %s, waiting for an answer..." % qid, file=sys.stderr)

    deadline = time.monotonic() + timeout_s + 60  # safety net; the server expires it first
    try:
        while True:
            q = api("GET", qpath + "/wait?timeout=30", key)
            if q.get("status") != "pending":
                return q
            if time.monotonic() > deadline:
                api("POST", qpath + "/cancel", key)
                return {"status": "cancelled", "answer": None}
    except KeyboardInterrupt:
        try:
            api("POST", qpath + "/cancel", key)
        except Exception:
            pass
        return {"status": "cancelled", "answer": None}


def main():
    p = argparse.ArgumentParser(description="Ask an iotPush approval question and wait")
    p.add_argument("question")
    p.add_argument("-t", "--title")
    p.add_argument("-s", "--timeout", type=int, default=300, help="10-86400 seconds")
    a = p.parse_args()

    key = os.environ.get("IOTPUSH_API_KEY")
    if not key:
        sys.exit("set IOTPUSH_API_KEY (account key, iop_live_...)")
    try:
        q = ask_and_wait(key, a.question, a.title, os.environ.get("IOTPUSH_TOPIC"), a.timeout)
    except urllib.error.HTTPError as e:
        print("request failed: HTTP %d %s" % (e.code, e.read().decode(errors="replace")), file=sys.stderr)
        sys.exit(3)

    answer = q.get("answer") or {}
    if q.get("status") == "answered" and answer.get("action_id") == "approve":
        print("approved by", answer.get("answered_by"), file=sys.stderr)
        sys.exit(0)
    if q.get("status") == "answered":
        print("rejected", file=sys.stderr)
        sys.exit(1)
    # expired / cancelled: nobody decided. Never treat this as approval.
    print("no decision (%s): not proceeding" % q.get("status"), file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    main()
