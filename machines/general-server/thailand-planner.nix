{ pkgs, ... }:

# Persistence backend for the family trip planner (thailand.miker.be).
# A tiny stdlib-only HTTP service storing the whole plan as one JSON file:
#   GET  /api/plan  -> current plan JSON (or null if never saved)
#   PUT  /api/plan  -> overwrite plan (validated as JSON, written atomically)
# Access is gated by Caddy basic_auth on the vhost, so no auth logic here.
let
  server = pkgs.writeText "plan-server.py" ''
    import http.server, json, os

    DATA = os.environ.get('PLAN_FILE', '/var/lib/thailand-planner/plan.json')
    PORT = int(os.environ.get('PORT', '8010'))

    class H(http.server.BaseHTTPRequestHandler):
        def _send(self, code, body):
            self.send_response(code)
            self.send_header('Content-Type', 'application/json')
            self.end_headers()
            self.wfile.write(body.encode())

        def do_GET(self):
            if self.path == '/api/plan':
                try:
                    with open(DATA) as f:
                        self._send(200, f.read())
                except FileNotFoundError:
                    self._send(200, 'null')
            else:
                self._send(404, '{"error":"not found"}')

        def do_PUT(self):
            if self.path != '/api/plan':
                self._send(404, '{"error":"not found"}')
                return
            n = int(self.headers.get('Content-Length', 0))
            raw = self.rfile.read(n).decode()
            try:
                json.loads(raw)
            except Exception:
                self._send(400, '{"error":"bad json"}')
                return
            os.makedirs(os.path.dirname(DATA), exist_ok=True)
            tmp = DATA + '.tmp'
            with open(tmp, 'w') as f:
                f.write(raw)
            os.replace(tmp, DATA)
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
