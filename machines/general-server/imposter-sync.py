#!/usr/bin/env python3
"""Round sync for imposter.miker.be, a game on several phones.

POST /api/game/<CODE>         <- {"token": "...", "state": {...}}
POST /api/game/<CODE>/skip    <- {"n": round, "who": player index, "vote": true | false}
GET  /api/game/<CODE>         -> {"state": {...}}, so a phone can join with the code
POST /api/game/<CODE>/hello   <- {"who": player index}, every HELLO_SEC seconds from each phone
GET  /api/game/<CODE>/events  -> text/event-stream, one "data:" line with
                                 the state each time it changes, and a
                                 "ping" event every PING_SEC seconds

The main phone sends the state of the game: the round number, the phase,
the votes, the score, and the game settings with the player names (so a
phone can join with only the code). The other phones listen and follow. The state
holds no word and no imposter: each phone calculates those itself from
the game code and the round number.

Any phone can ask to skip a round, and each phone votes on /skip. The
votes go out with the state as "skip": {"id", "n", "by", "yes": [...],
"no": [...]}. The main phone skips when all players agree. A new round from
the main phone clears the votes. A vote needs no token: a wrong vote can
only stop a skip or help one.

Each phone sends a hello with its player index. A player counts as online
for ONLINE_SEC seconds after its last hello. The list goes out as
"online": [...] with the state, and with each ping, so the game leader
sees how many phones are connected. A hello needs no token.

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
POSTS_PER_SEC = 20
PING_SEC = 10

PATH_RE = re.compile(r"^/api/game/([A-Z2-9]{6})(/events|/skip|/hello)?$")
ONLINE_SEC = 35
MAX_PLAYERS = 50

lock = threading.Condition()
rooms = {}  # code -> {"token", "state", "seq", "updated", "posts": [times]}
streams = 0


def online(room, now):
    """The players with a hello in the last ONLINE_SEC seconds."""
    return sorted(w for w, t in room.get("seen", {}).items() if now - t < ONLINE_SEC)


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
        # An error reply can leave the request body unread. Close the
        # connection, or Caddy sends the next request after that body.
        if code >= 400:
            self.close_connection = True
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        if code >= 400:
            self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(data)

    def read_json(self):
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            return None
        try:
            return json.loads(self.rfile.read(length))
        except Exception:
            return None

    def limited(self, room, now):
        room["posts"] = [t for t in room["posts"] if now - t < 1] + [now]
        return len(room["posts"]) > POSTS_PER_SEC

    def do_POST(self):
        m = PATH_RE.match(self.path)
        if not m or m.group(2) == "/events":
            return self.reply(404)
        if m.group(2) == "/skip":
            return self.skip(m.group(1))
        if m.group(2) == "/hello":
            return self.hello(m.group(1))
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
            if self.limited(room, now):
                return self.reply(429)
            # A new round ends a skip vote for an earlier round.
            if room.get("skip") and room["skip"]["n"] != state.get("n"):
                room["skip"] = None
            room["state"] = state
            room["seq"] += 1
            room["updated"] = now
            lock.notify_all()
            seq = room["seq"]
        self.reply(200, {"seq": seq})

    def hello(self, code):
        body = self.read_json()
        try:
            who = int(body["who"])
            assert 0 <= who < MAX_PLAYERS
        except Exception:
            return self.reply(400)
        now = time.time()
        with lock:
            room = rooms.get(code)
            if room is None:
                return self.reply(404)
            if self.limited(room, now):
                return self.reply(429)
            before = online(room, now)
            room.setdefault("seen", {})[who] = now
            # Tell the phones only when a player comes online.
            if online(room, now) != before:
                room["seq"] += 1
                lock.notify_all()
        self.reply(200, {"online": online(room, now)})

    def skip(self, code):
        body = self.read_json()
        try:
            n, who, vote = int(body["n"]), int(body["who"]), bool(body["vote"])
            assert 1 <= n <= 100000 and 0 <= who < MAX_PLAYERS
        except Exception:
            return self.reply(400)
        now = time.time()
        with lock:
            room = rooms.get(code)
            if room is None or room["state"] is None:
                return self.reply(404)
            if room["state"].get("n") != n:
                return self.reply(409)
            if self.limited(room, now):
                return self.reply(429)
            sk = room.get("skip")
            # A yes after a no, or for a new round, starts a new request.
            if not sk or sk["n"] != n or (sk["no"] and vote):
                if not vote:
                    return self.reply(200, {"skip": sk})
                room["skips"] = room.get("skips", 0) + 1
                sk = {"id": room["skips"], "n": n, "by": who, "yes": [], "no": []}
            for key in ("yes", "no"):
                if who in sk[key]:
                    sk[key].remove(who)
            sk["yes" if vote else "no"].append(who)
            room["skip"] = sk
            room["seq"] += 1
            room["updated"] = now
            lock.notify_all()
        self.reply(200, {"skip": sk})

    def do_GET(self):
        m = PATH_RE.match(self.path)
        if not m:
            if SITE_DIR:
                return super().do_GET()
            return self.reply(404)
        if not m.group(2):
            with lock:
                room = rooms.get(m.group(1))
                state = room and room["state"]
            return self.reply(200, {"state": state}) if state else self.reply(404)
        if m.group(2) != "/events":
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
                    if state is not None:
                        state = dict(state, skip=room.get("skip"), online=online(room, time.time()))
                    beat = {"online": online(room, time.time())}
                if seq != sent and state is not None:
                    self.wfile.write(b"data: " + json.dumps(state).encode() + b"\n\n")
                    sent = seq
                else:
                    # A named event, so the phone sees it and knows the stream is alive.
                    self.wfile.write(b"event: ping\ndata: " + json.dumps(beat).encode() + b"\n\n")
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
