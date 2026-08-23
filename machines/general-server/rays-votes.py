#!/usr/bin/env python3
"""Thumbs up/down counter for rays.miker.be.

GET  /api/votes          -> {"<key>": {"up": n, "down": n}, ...}
POST /api/vote           <- {"key": "...", "v": 1 | -1}
                         -> {"key": ..., "up": n, "down": n}

Every vote is appended to a JSONL log with a timestamp, so the totals
can be rebuilt and the history read. No auth: the site is one person's
notebook for now. Listens on localhost only; Caddy fronts it.
"""

import json
import os
import re
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Lock

PORT = int(os.environ.get("PORT", "8322"))
LOG = Path(os.environ.get("VOTES_LOG", "/var/lib/rays-votes/votes.jsonl"))
KEY_RE = re.compile(r"^[A-Za-z0-9 .'()/+_-]{1,120}$")
lock = Lock()
totals = {}


def load():
    if not LOG.exists():
        return
    with LOG.open() as fp:
        for line in fp:
            try:
                r = json.loads(line)
            except ValueError:
                continue
            bump(r["key"], r["v"])


def bump(key, v):
    t = totals.setdefault(key, {"up": 0, "down": 0})
    t["up" if v > 0 else "down"] += 1
    return t


class H(BaseHTTPRequestHandler):
    server_version = "rays-votes/1"

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?")[0] != "/api/votes":
            return self._send(404, {"error": "not found"})
        with lock:
            self._send(200, totals)

    def do_POST(self):
        if self.path != "/api/vote":
            return self._send(404, {"error": "not found"})
        try:
            n = int(self.headers.get("Content-Length", "0"))
            r = json.loads(self.rfile.read(min(n, 4096)))
            key, v = str(r["key"]), int(r["v"])
        except (ValueError, KeyError, TypeError):
            return self._send(400, {"error": "bad request"})
        if v not in (1, -1) or not KEY_RE.match(key):
            return self._send(400, {"error": "bad vote"})
        rec = {"t": int(time.time()), "key": key, "v": v,
               "ip": self.client_address[0]}
        with lock:
            LOG.parent.mkdir(parents=True, exist_ok=True)
            with LOG.open("a") as fp:
                fp.write(json.dumps(rec) + "\n")
            t = bump(key, v)
            self._send(200, {"key": key, **t})

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    load()
    ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
