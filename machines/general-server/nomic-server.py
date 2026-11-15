"""Game store for nomic.miker.be.

Each game is one JSON file in GAME_DIR. The game id is a long random string
that the browser makes. The link is the access: anyone with the link can read
and change the game, as with a shared document.

Each game has a revision number. A write must name the revision it is based
on. If another device wrote first, the write fails with 409 and the current
game, and the browser applies its own changes again on top of it.

Endpoints:

  GET /api/games/<id>              200 {"rev": n, "game": {...}}, or 404
  GET /api/games/<id>?since=<n>    204 when the revision is still n
  PUT /api/games/<id>              body {"baseRev": n, "game": {...}}
                                   200 {"rev": n + 1}, or 409 {"rev", "game"}
"""

import json
import os
import re
import threading
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

GAME_DIR = os.environ.get("GAME_DIR", "/var/lib/nomic/games")
PORT = int(os.environ.get("PORT", "8020"))
MAX_BODY = 2 * 1024 * 1024
MAX_GAMES = 5000

ID_RE = re.compile(r"^[A-Za-z0-9_-]{16,64}$")
PATH_RE = re.compile(r"^/api/games/([^/]+)$")

# One lock for all writes. Writes are small and rare, so this is sufficient.
lock = threading.Lock()


def game_path(game_id):
    return os.path.join(GAME_DIR, f"{game_id}.json")


def read_game(game_id):
    try:
        with open(game_path(game_id), encoding="utf-8") as f:
            return json.load(f)
    except FileNotFoundError:
        return None


def write_game(game_id, record):
    path = game_path(game_id)
    tmp = f"{path}.tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(record, f, separators=(",", ":"))
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, path)


def game_count():
    return sum(1 for n in os.listdir(GAME_DIR) if n.endswith(".json"))


class Handler(BaseHTTPRequestHandler):
    server_version = "nomic"

    def log_message(self, fmt, *args):
        # systemd adds the time. Keep one short line for each request.
        print(f"{self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)

    def send_json(self, status, body=None):
        data = b"" if body is None else json.dumps(body, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        if body is not None:
            self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def game_id(self):
        m = PATH_RE.match(urlparse(self.path).path)
        if not m or not ID_RE.match(m.group(1)):
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "no such game"})
            return None
        return m.group(1)

    def do_GET(self):
        game_id = self.game_id()
        if not game_id:
            return
        record = read_game(game_id)
        if record is None:
            self.send_json(HTTPStatus.NOT_FOUND, {"error": "no such game"})
            return
        since = parse_qs(urlparse(self.path).query).get("since", [None])[0]
        if since is not None and since == str(record["rev"]):
            self.send_json(HTTPStatus.NO_CONTENT)
            return
        self.send_json(HTTPStatus.OK, record)

    def do_PUT(self):
        game_id = self.game_id()
        if not game_id:
            return
        length = int(self.headers.get("Content-Length") or 0)
        if length <= 0 or length > MAX_BODY:
            self.send_json(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, {"error": "body too large or empty"})
            return
        try:
            body = json.loads(self.rfile.read(length))
            base = int(body["baseRev"])
            game = body["game"]
            if not isinstance(game, dict) or not isinstance(game.get("rules"), list):
                raise ValueError("not a game")
        except (ValueError, KeyError, TypeError):
            self.send_json(HTTPStatus.BAD_REQUEST, {"error": "expected {baseRev, game}"})
            return

        with lock:
            record = read_game(game_id)
            current = record["rev"] if record else 0
            if base != current:
                self.send_json(HTTPStatus.CONFLICT, record or {"rev": 0, "game": None})
                return
            if record is None and game_count() >= MAX_GAMES:
                self.send_json(HTTPStatus.INSUFFICIENT_STORAGE, {"error": "the store is full"})
                return
            record = {"rev": current + 1, "game": game}
            write_game(game_id, record)
        self.send_json(HTTPStatus.OK, {"rev": record["rev"]})


def main():
    os.makedirs(GAME_DIR, exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"nomic: serving {GAME_DIR} on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
