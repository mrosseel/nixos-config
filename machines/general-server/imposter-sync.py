#!/usr/bin/env python3
"""Round sync for imposter.miker.be, a game on several phones.

POST /api/game/<CODE>         <- {"token": "...", "state": {...}}
GET  /api/game/<CODE>/events  -> text/event-stream, one "data:" line with
                                 the state each time it changes, and a
                                 "ping" event every PING_SEC seconds

The main phone sends the state of the game: the round number, the phase,
the votes and the score. The other phones listen and follow. The state
holds no word and no imposter: each phone calculates those itself from
the game code and the round number.

The first POST for a code stores its token. Later POSTs must send the
same token, so only the main phone can change the game. Rooms are kept
in memory and are deleted after ROOM_TTL seconds with no change.

Limits:
- A code is 6 characters, A-Z and 2-9. A request body is at most
  MAX_BODY bytes.
- At most MAX_ROOMS rooms and MAX_STREAMS open event streams.
- A room takes at most POSTS_PER_SEC changes a second.
- Listens on localhost only. Caddy fronts it.

With SITE_DIR set, other paths serve the files in that directory. That
is for a local test only, without Caddy.
"""

import hmac
import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, SimpleHTTPRequestHandler, ThreadingHTTPServer

PORT = int(os.environ.get("PORT", "8323"))
SITE_DIR = os.environ.get("SITE_DIR")
MAX_BODY = 4096
MAX_ROOMS = 2000
MAX_STREAMS = 400
ROOM_TTL = 12 * 3600
POSTS_PER_SEC = 10
PING_SEC = 10

PATH_RE = re.compile(r"^/api/game/([A-Z2-9]{6})(/events)?$")

lock = threading.Condition()
rooms = {}  # code -> {"token", "state", "seq", "updated", "posts": [times]}
streams = 0


def cleanup():
    while True:
        time.sleep(600)
        now = time.time()
        with lock:
            for code in [c for c, r in rooms.items() if now - r["updated"] > ROOM_TTL]:
                del rooms[code]


class Handler(SimpleHTTPRequestHandler if SITE_DIR else BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    timeout = 10

    def __init__(self, *args, **kwargs):
        if SITE_DIR:
            kwargs["directory"] = SITE_DIR
        super().__init__(*args, **kwargs)

    def log_message(self, fmt, *args):
        pass

    def reply(self, code, body=None):
        data = json.dumps(body or {}).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_POST(self):
        m = PATH_RE.match(self.path)
        if not m or m.group(2):
            return self.reply(404)
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return self.reply(413)
        try:
            body = json.loads(self.rfile.read(length))
            token = str(body["token"])
            state = body["state"]
            assert isinstance(state, dict) and 8 <= len(token) <= 64
        except Exception:
            return self.reply(400)
        code = m.group(1)
        now = time.time()
        with lock:
            room = rooms.get(code)
            if room is None or room["token"] is None:
                if room is None and len(rooms) >= MAX_ROOMS:
                    return self.reply(503)
                room = rooms[code] = room or {"seq": 0, "state": None, "posts": []}
                room["token"] = token
            elif not hmac.compare_digest(room["token"], token):
                return self.reply(403)
            room["posts"] = [t for t in room["posts"] if now - t < 1] + [now]
            if len(room["posts"]) > POSTS_PER_SEC:
                return self.reply(429)
            room["state"] = state
            room["seq"] += 1
            room["updated"] = now
            lock.notify_all()
            seq = room["seq"]
        self.reply(200, {"seq": seq})

    def do_GET(self):
        m = PATH_RE.match(self.path)
        if not m:
            if SITE_DIR:
                return super().do_GET()
            return self.reply(404)
        if not m.group(2):
            return self.reply(404)
        self.stream(m.group(1))

    def stream(self, code):
        global streams
        with lock:
            if streams >= MAX_STREAMS:
                return self.reply(503)
            if code not in rooms:
                if len(rooms) >= MAX_ROOMS:
                    return self.reply(503)
                # A phone can listen before the main phone sends the first state.
                rooms[code] = {"token": None, "seq": 0, "state": None, "posts": [], "updated": time.time()}
            streams += 1
        self.close_connection = True
        try:
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-store")
            self.send_header("X-Accel-Buffering", "no")
            self.end_headers()
            self.connection.settimeout(PING_SEC + 10)
            sent = 0
            while True:
                with lock:
                    room = rooms.get(code)
                    if room is None:
                        return
                    if room["seq"] == sent:
                        lock.wait(PING_SEC)
                    seq, state = room["seq"], room["state"]
                if seq != sent and state is not None:
                    self.wfile.write(b"data: " + json.dumps(state).encode() + b"\n\n")
                    sent = seq
                else:
                    # A named event, so the phone sees it and knows the stream is alive.
                    self.wfile.write(b"event: ping\ndata: {}\n\n")
                self.wfile.flush()
        except OSError:
            pass
        finally:
            with lock:
                streams -= 1


if __name__ == "__main__":
    threading.Thread(target=cleanup, daemon=True).start()
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    server.daemon_threads = True
    server.serve_forever()
