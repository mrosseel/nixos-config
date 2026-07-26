{ pkgs, ... }:

# Persistence backend for the family trip planner (thailand.miker.be).
# A tiny stdlib-only HTTP service:
#   GET    /api/plan          -> current plan JSON (or null if never saved)
#   PUT    /api/plan          -> overwrite plan (validated, snapshotted, atomic)
#   POST   /api/images        -> store an image body, returns {"url": "/api/images/<id>"}
#   GET    /api/images/<id>   -> serve a stored image
#   DELETE /api/images/<id>   -> drop a stored image
# Access is gated by Caddy basic_auth on the vhost, so no auth logic here.
let
  server = pkgs.writeText "plan-server.py" ''
    import http.server, json, os, shutil, threading, time, uuid

    DATA = os.environ.get('PLAN_FILE', '/var/lib/thailand-planner/plan.json')
    PORT = int(os.environ.get('PORT', '8010'))
    ROOT = os.path.dirname(DATA)
    SNAPDIR = os.path.join(ROOT, 'snapshots')
    IMGDIR = os.path.join(ROOT, 'images')

    # A snapshot at most every 10 minutes of active editing, keeping the last 200.
    SNAP_INTERVAL = 600
    SNAP_KEEP = 200
    MAX_IMAGE = 12 * 1024 * 1024

    EXTS = {
        'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp',
        'image/gif': '.gif', 'image/heic': '.heic', 'image/avif': '.avif',
    }
    TYPES = {v: k for k, v in EXTS.items()}
    lock = threading.Lock()

    def snapshot():
        """Keep a rolling history so a bad write or a stray Reset is recoverable."""
        if not os.path.exists(DATA):
            return
        os.makedirs(SNAPDIR, exist_ok=True)
        snaps = sorted(os.listdir(SNAPDIR))
        if snaps:
            newest = os.path.getmtime(os.path.join(SNAPDIR, snaps[-1]))
            if time.time() - newest < SNAP_INTERVAL:
                return
        name = time.strftime('plan-%Y%m%d-%H%M%S.json', time.gmtime())
        shutil.copy2(DATA, os.path.join(SNAPDIR, name))
        snaps = sorted(os.listdir(SNAPDIR))
        for old in snaps[:-SNAP_KEEP]:
            os.remove(os.path.join(SNAPDIR, old))

    class H(http.server.BaseHTTPRequestHandler):
        def _send(self, code, body, ctype='application/json'):
            raw = body if isinstance(body, bytes) else body.encode()
            self.send_response(code)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

        def _image_path(self):
            name = os.path.basename(self.path[len('/api/images/'):])
            ext = os.path.splitext(name)[1].lower()
            if not name or ext not in TYPES:
                return None, None
            return os.path.join(IMGDIR, name), TYPES[ext]

        def do_GET(self):
            if self.path == '/api/plan':
                try:
                    with open(DATA, 'rb') as f:
                        self._send(200, f.read())
                except FileNotFoundError:
                    self._send(200, 'null')
                return
            if self.path.startswith('/api/images/'):
                path, ctype = self._image_path()
                if not path:
                    self._send(404, '{"error":"not found"}')
                    return
                try:
                    with open(path, 'rb') as f:
                        body = f.read()
                except FileNotFoundError:
                    self._send(404, '{"error":"not found"}')
                    return
                self.send_response(200)
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Cache-Control', 'private, max-age=31536000, immutable')
                self.end_headers()
                self.wfile.write(body)
                return
            self._send(404, '{"error":"not found"}')

        def do_PUT(self):
            if self.path != '/api/plan':
                self._send(404, '{"error":"not found"}')
                return
            n = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(n)
            try:
                plan = json.loads(raw)
            except Exception:
                self._send(400, '{"error":"bad json"}')
                return
            # Refuse writes that would wipe the plan through a truncated payload.
            if not isinstance(plan, dict) or not isinstance(plan.get('columns'), list):
                self._send(400, '{"error":"plan must have a columns list"}')
                return
            with lock:
                snapshot()
                os.makedirs(ROOT, exist_ok=True)
                tmp = DATA + '.tmp'
                with open(tmp, 'wb') as f:
                    f.write(raw)
                    f.flush()
                    os.fsync(f.fileno())
                os.replace(tmp, DATA)
            self._send(200, '{"ok":true}')

        def do_POST(self):
            if self.path != '/api/images':
                self._send(404, '{"error":"not found"}')
                return
            ctype = (self.headers.get('Content-Type') or "").split(';')[0].strip().lower()
            ext = EXTS.get(ctype)
            if not ext:
                self._send(415, '{"error":"unsupported image type"}')
                return
            n = int(self.headers.get('Content-Length', 0))
            if n <= 0 or n > MAX_IMAGE:
                self._send(413, '{"error":"image too large"}')
                return
            body = self.rfile.read(n)
            os.makedirs(IMGDIR, exist_ok=True)
            name = uuid.uuid4().hex + ext
            tmp = os.path.join(IMGDIR, '.' + name)
            with open(tmp, 'wb') as f:
                f.write(body)
            os.replace(tmp, os.path.join(IMGDIR, name))
            self._send(201, json.dumps({'url': '/api/images/' + name}))

        def do_DELETE(self):
            if not self.path.startswith('/api/images/'):
                self._send(404, '{"error":"not found"}')
                return
            path, _ = self._image_path()
            if path:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            self._send(200, '{"ok":true}')

        def log_message(self, *a):
            pass

    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
  '';
in {
  systemd.services.thailand-planner = {
    description = "Thailand trip planner JSON store";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 ${server}";
      Environment = [
        "PLAN_FILE=/var/lib/thailand-planner/plan.json"
        "PORT=8010"
      ];
      DynamicUser = true;
      StateDirectory = "thailand-planner";
      Restart = "on-failure";
      ProtectSystem = "strict";
      ProtectHome = true;
      NoNewPrivileges = true;
    };
  };
}
