#!/usr/bin/env python3
"""Local stand-in for the iotPush API, used by tests/run.sh. Standard library only.

Binds 127.0.0.1 on a free port and prints the port as its first line.
Every request is appended as one JSON line to $MOCK_LOG.

MOCK_MODE decides how a question ends (the first /wait call always returns pending):
    approve (default) | reject | expired
"""
import json
import os
import re
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

MODE = os.environ.get("MOCK_MODE", "approve")
LOG = os.environ.get("MOCK_LOG", "mock_requests.jsonl")
lock = threading.Lock()
wait_calls = {}


def question(qid, status, answer=None):
    return {"question_id": qid, "status": status, "kind": "confirm",
            "expires_at": "2030-01-01T00:00:00Z", "answer": answer}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def _record(self, body):
        try:
            parsed = json.loads(body) if body else None
        except ValueError:
            parsed = None
        url = urlsplit(self.path)
        entry = {
            "method": self.command,
            "path": url.path,
            "query": {k: v[0] for k, v in parse_qs(url.query).items()},
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "body": body,
            "json": parsed,
        }
        with lock, open(LOG, "a") as f:
            f.write(json.dumps(entry) + "\n")
        return url

    def _send(self, code, obj):
        data = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _handle(self):
        length = int(self.headers.get("Content-Length") or 0)
        body = self.rfile.read(length).decode("utf-8") if length else ""
        url = self._record(body)
        path, m = url.path, self.command

        if m == "POST" and re.fullmatch(r"/api/push/[^/]+", path):
            return self._send(200, {"ok": True, "receipt_id": "r_test"})
        if m == "POST" and path == "/api/1/messages.json":
            return self._send(200, {"status": 1, "request": "mock"})

        if path.startswith("/api/v1/"):
            if not self.headers.get("Authorization", "").startswith("Bearer iop_live_"):
                return self._send(401, {"error": "account API key required"})
            if m == "POST" and path == "/api/v1/questions":
                with lock:
                    wait_calls["q_test"] = 0
                return self._send(201, question("q_test", "pending"))
            wm = re.fullmatch(r"/api/v1/questions/([^/]+)/wait", path)
            if m == "GET" and wm:
                qid = wm.group(1)
                with lock:
                    wait_calls[qid] = wait_calls.get(qid, 0) + 1
                    n = wait_calls[qid]
                if n == 1:
                    return self._send(200, question(qid, "pending"))
                if MODE == "expired":
                    return self._send(200, question(qid, "expired"))
                action = "reject" if MODE == "reject" else "approve"
                return self._send(200, question(qid, "answered", {
                    "action_id": action, "label": action.title(), "text": None,
                    "answered_by": "tester@example.com", "answered_at": "2030-01-01T00:00:00Z"}))
            cm = re.fullmatch(r"/api/v1/questions/([^/]+)/cancel", path)
            if m == "POST" and cm:
                return self._send(200, question(cm.group(1), "cancelled"))

        return self._send(404, {"error": "not found"})

    do_GET = do_POST = _handle


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    print(server.server_address[1], flush=True)
    server.serve_forever()
