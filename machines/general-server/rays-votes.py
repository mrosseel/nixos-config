#!/usr/bin/env python3
"""Thumbs up/down counter for rays.miker.be.

GET  /api/votes          -> {"<key>": {"up": n, "down": n}, ...}
POST /api/vote           <- {"key": "...", "v": 1 | -1}
                         -> {"key": ..., "up": n, "down": n}

Every vote is appended to a JSONL log with a timestamp, so the totals
can be rebuilt and the history read. No auth: the site is one person's
notebook for now. Listens on localhost only; Caddy fronts it.

Limits:
- Only known keys are accepted. A key is a feature name without the
  "(candidate N)" suffix, the same rule as voteKey() in the site. The
  allow-list comes from the deployed events.features.json and
  img/manifest.json, and is read again when their mtime changes.
- Token buckets limit the votes per client IP per key, per client IP,
  and for the whole server.
- The log stops at MAX_LOG_BYTES. Past that, votes get 507.
- A request body is at most 4096 bytes. A socket read or write waits at
  most 10 s. At most MAX_CONNS requests run at the same time.
"""

import json
import os
import re
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from ipaddress import ip_address, ip_network
from pathlib import Path

PORT = int(os.environ.get("PORT", "8322"))
LOG = Path(os.environ.get("VOTES_LOG", "/var/lib/rays-votes/votes.jsonl"))
SITE = Path(os.environ.get("SITE_DIR", "/var/www/rays.miker.be"))
MAX_LOG_BYTES = int(os.environ.get("MAX_LOG_BYTES", str(50 * 1024 * 1024)))
MAX_BODY = 4096
MAX_CONNS = 32
KEY_RE = re.compile(r"^[\w .'()/+?-]{1,120}$")
CANDIDATE_RE = re.compile(r"\s*\(candidate \d+\)\s*$")

# Token buckets: (capacity, refill per second). Each client bucket is
# full again 60 s after its last use.
PER_IP_KEY = (3, 3 / 60)     # 3 votes per minute per IP per key
PER_IP = (30, 30 / 60)       # 30 votes per minute per IP
GLOBAL = (20, 5.0)           # 5 votes per second for the whole server
REFILL_S = 60
MAX_BUCKETS = 20000

lock = threading.Lock()
totals = {}


def vote_key(desc):
    """The site's voteKey(): first comma field, no "(candidate N)"."""
    return CANDIDATE_RE.sub("", str(desc).split(",")[0]).strip()


class AllowList:
    """Known vote keys, read again when a source file changes."""

    def __init__(self, site):
        self.files = [site / "events.features.json", site / "img" / "manifest.json"]
        self.stamp = None
        self.keys = frozenset()
        self.lock = threading.Lock()

    def _stamp(self):
        out = []
        for f in self.files:
            try:
                st = f.stat()
                out.append((st.st_mtime_ns, st.st_size))
            except OSError:
                out.append(None)
        return tuple(out)

    def _read(self):
        keys = set()
        try:
            feats = json.loads(self.files[0].read_text())
            keys.update(vote_key(f["desc"]) for f in feats if "desc" in f)
        except (OSError, ValueError, TypeError):
            pass
        try:
            man = json.loads(self.files[1].read_text())
            keys.update(vote_key(m["name"]) for m in man.values() if m.get("name"))
        except (OSError, ValueError, TypeError, AttributeError):
            pass
        return frozenset(k for k in keys if KEY_RE.match(k))

    def get(self):
        with self.lock:
            stamp = self._stamp()
            if stamp != self.stamp:
                self.keys = self._read()
                self.stamp = stamp
            return self.keys


allowed = AllowList(SITE)


class Buckets:
    """Token buckets by name."""

    def __init__(self):
        self.b = {}
        self.lock = threading.Lock()

    def _level(self, name, cap, rate, now):
        tokens, last = self.b.get(name, (cap, now))
        return min(cap, tokens + (now - last) * rate)

    def allow(self, ip, key):
        now = time.monotonic()
        with self.lock:
            if len(self.b) > MAX_BUCKETS:
                self._prune(now)
                if len(self.b) > MAX_BUCKETS:
                    return False
            names = [(("g",), GLOBAL), (("ip", ip), PER_IP),
                     (("ipk", ip, key), PER_IP_KEY)]
            # Check all three before a token is taken from any of them,
            # so a refused vote costs nothing.
            levels = [self._level(n, c, r, now) for n, (c, r) in names]
            if min(levels) < 1:
                return False
            for (n, _), level in zip(names, levels):
                self.b[n] = (level - 1, now)
            return True

    def _prune(self, now):
        # A client bucket unused for REFILL_S is full, the same as no bucket.
        old = [n for n, (_, last) in self.b.items()
               if n[0] != "g" and now - last >= REFILL_S]
        for n in old:
            del self.b[n]


buckets = Buckets()


def stored_ip(ip):
    """The address written to the log.

    For privacy the log keeps only the network, not the full address:
    /24 for IPv4 and /48 for IPv6. The full address stays in memory only,
    in the rate-limit table.
    """
    try:
        a = ip_address(ip)
    except ValueError:
        return "?"
    prefix = 24 if a.version == 4 else 48
    return str(ip_network(f"{a}/{prefix}", strict=False))


def load():
    if not LOG.exists():
        return
    with LOG.open() as fp:
        for line in fp:
            try:
                r = json.loads(line)
                key, v = r["key"], int(r["v"])
            except (ValueError, KeyError, TypeError):
                continue
            if isinstance(key, str) and KEY_RE.match(key):
                bump(key, v)


def bump(key, v):
    t = totals.setdefault(key, {"up": 0, "down": 0})
    t["up" if v > 0 else "down"] += 1
    return t


class H(BaseHTTPRequestHandler):
    server_version = "rays-votes/1"
    # StreamRequestHandler sets this as the socket timeout. A client that
    # sends nothing for 10 s is dropped.
    timeout = 10

    def _send(self, code, obj, extra=()):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Length", str(len(body)))
        for k, val in extra:
            self.send_header(k, val)
        self.end_headers()
        self.wfile.write(body)

    def client_ip(self):
        """The real client address.

        The service listens on 127.0.0.1, so the peer is the local Caddy.
        Caddy puts the client address it sees as the last X-Forwarded-For
        entry. Entries to its left come from the client and are not trusted.
        """
        peer = self.client_address[0]
        if not ip_address(peer).is_loopback:
            return peer
        xff = self.headers.get_all("X-Forwarded-For") or []
        parts = [p.strip() for h in xff for p in h.split(",") if p.strip()]
        if not parts:
            return peer
        try:
            return str(ip_address(parts[-1]))
        except ValueError:
            return peer

    def do_GET(self):
        if self.path.split("?")[0] != "/api/votes":
            return self._send(404, {"error": "not found"})
        keys = allowed.get()
        with lock:
            out = {k: dict(t) for k, t in totals.items() if k in keys}
        self._send(200, out)

    def do_POST(self):
        if self.path != "/api/vote":
            return self._send(404, {"error": "not found"})
        self.close_connection = True
        try:
            n = int(self.headers.get("Content-Length", ""))
        except ValueError:
            return self._send(411, {"error": "length required"})
        if n < 0:
            return self._send(400, {"error": "bad length"})
        if n > MAX_BODY:
            return self._send(413, {"error": "too large"})
        try:
            raw = self.rfile.read(n)
        except TimeoutError:
            return
        if len(raw) != n:
            return self._send(400, {"error": "short body"})
        try:
            r = json.loads(raw)
            key, v = r["key"], int(r["v"])
        except (ValueError, KeyError, TypeError):
            return self._send(400, {"error": "bad request"})
        if (v not in (1, -1) or not isinstance(key, str)
                or not KEY_RE.match(key)):
            return self._send(400, {"error": "bad vote"})
        if key not in allowed.get():
            return self._send(400, {"error": "unknown key"})
        ip = self.client_ip()
        if not buckets.allow(ip, key):
            return self._send(429, {"error": "too many votes"},
                              [("Retry-After", "60")])
        rec = {"t": int(time.time()), "key": key, "v": v, "ip": stored_ip(ip)}
        line = json.dumps(rec) + "\n"
        t = None
        with lock:
            try:
                size = LOG.stat().st_size
            except OSError:
                size = 0
            if size + len(line) <= MAX_LOG_BYTES:
                LOG.parent.mkdir(parents=True, exist_ok=True)
                with LOG.open("a") as fp:
                    fp.write(line)
                t = dict(bump(key, v))
        if t is None:
            return self._send(507, {"error": "vote log full"})
        self._send(200, {"key": key, **t})

    def log_message(self, *a):
        pass


class Server(ThreadingHTTPServer):
    """A threading server that runs at most MAX_CONNS requests at once.

    A connection past the limit is closed at once, not queued.
    """

    daemon_threads = True

    def __init__(self, *a, **kw):
        self.slots = threading.BoundedSemaphore(MAX_CONNS)
        super().__init__(*a, **kw)

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


if __name__ == "__main__":
    load()
    Server(("127.0.0.1", PORT), H).serve_forever()
