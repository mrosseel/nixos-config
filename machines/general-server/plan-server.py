"""Persistence backend for the family trip planner (thailand.miker.be).

Stdlib only, single file, no framework. Access is gated by Caddy basic_auth on
the vhost, so there is no auth logic here.

    GET    /api/plan            -> current plan document, or null
    PUT    /api/plan            -> overwrite; needs If-Match: <rev>
    GET    /api/versions        -> commit log of the plan
    GET    /api/versions/<sha>  -> the plan as it was at that commit
    POST   /api/restore         -> {"sha": ...}; restores as a NEW version
    POST   /api/images          -> store an image body, returns {"url": ...}
    GET    /api/images/<id>     -> serve a stored image
    DELETE /api/images/<id>     -> drop a stored image

Two people edit this plan at the same time. Every write therefore carries the
revision it was based on, and a stale write is refused rather than silently
overwriting the other person's edit.

The state directory is a git repository. Every burst of editing lands as one
commit and is pushed to a private remote, which is both the version history the
UI browses and the only off-site copy of the trip.
"""

import http.server
import json
import re
import os
import subprocess
import threading
import time
import uuid
from datetime import date, timedelta

DATA = os.environ.get('PLAN_FILE', '/var/lib/thailand-planner/plan.json')
PORT = int(os.environ.get('PORT', '8010'))
REMOTE = os.environ.get('PLAN_GIT_REMOTE', '')
ROOT = os.path.dirname(DATA)
IMGDIR = os.path.join(ROOT, 'images')
NAME = os.path.basename(DATA)

# One commit per burst of editing rather than per keystroke: the committer wakes
# on a timer and only acts once the plan has been quiet for a moment.
COMMIT_QUIET = 20
COMMIT_POLL = 5
MAX_IMAGE = 12 * 1024 * 1024

EXTS = {
    'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp',
    'image/gif': '.gif', 'image/heic': '.heic', 'image/avif': '.avif',
}
TYPES = {v: k for k, v in EXTS.items()}

lock = threading.Lock()
dirty = threading.Event()
last_change = [0.0]

GIT = ['git', '-c', 'user.name=thailand-planner',
       '-c', 'user.email=planner@miker.be', '-C', ROOT]


def git(*args, check=True):
    return subprocess.run(GIT + list(args), capture_output=True, text=True,
                          check=check, timeout=120)


# --- the plan document ------------------------------------------------------

def read_plan():
    try:
        with open(DATA, 'rb') as f:
            return json.loads(f.read())
    except (FileNotFoundError, ValueError):
        return None


def valid(plan):
    """Reject anything that would replace the trip with a truncated payload."""
    return (isinstance(plan, dict)
            and plan.get('v') == 2
            and isinstance(plan.get('days'), list)
            and len(plan['days']) > 0)


def write_plan(plan, rev):
    plan['rev'] = rev
    plan['savedAt'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    os.makedirs(ROOT, exist_ok=True)
    tmp = DATA + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(plan, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, DATA)
    with open(os.path.join(ROOT, 'PLAN.md'), 'w') as f:
        f.write(to_markdown(plan))
    last_change[0] = time.time()
    dirty.set()
    return plan


# --- readable rendering -----------------------------------------------------
#
# The git remote doubles as the off-site backup, so it carries a rendered
# PLAN.md next to the JSON: if this service is gone, the whole trip is still
# readable in a browser on the repo page with nothing installed.

DOW = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec']


def day_dates(plan):
    """Dates are positional: day N is the start date plus N days."""
    try:
        y, m, d = (int(x) for x in plan.get('start', '2026-10-21').split('-'))
        start = date(y, m, d)
    except ValueError:
        start = date(2026, 10, 21)
    return [start + timedelta(days=i) for i in range(len(plan['days']))]


TAG_RE = re.compile(r'<[^>]+>')
BREAK_RE = re.compile(r'</(p|div|li|ul|ol|h3|h4|blockquote)>|<br\s*/?>', re.I)


def plain(v):
    """Notes are rich text in the app; the rendered plan is words only."""
    if not v:
        return ''
    s = BREAK_RE.sub('\n', str(v))
    s = TAG_RE.sub('', s)
    for a, b in (('&amp;', '&'), ('&lt;', '<'), ('&gt;', '>'), ('&nbsp;', ' '), ('&quot;', '"')):
        s = s.replace(a, b)
    return s.strip()


def cell(v):
    return plain(v).replace('|', r'\|').replace('\n', ' ')


def short_url(url):
    """Booking links are hundreds of characters of tracking parameters, which
    makes the rendered table unreadable. Link the text, keep the target."""
    try:
        rest = url.split('://', 1)[1]
        host, _, path = rest.partition('/')
        tail = [p for p in path.split('?')[0].split('/') if p]
        label = host[4:] if host.startswith('www.') else host
        return f"[{label}{'/' + tail[-1] if tail else ''}]({url})"
    except IndexError:
        return url


def node_line(n):
    data = n.get('data') or {}
    url = data.get('url') or data.get('bookingUrl')
    bits = [b for b in (
        data.get('name') or n.get('title'),
        data.get('price'),
        f"check-in {data['checkIn']}" if data.get('checkIn') else None,
        f"check-out {data['checkOut']}" if data.get('checkOut') else None,
        f"cancel before {data['cancelBefore']}" if data.get('cancelBefore') else None,
        f"booked by {data['bookedBy']}" if data.get('bookedBy') else None,
        short_url(url) if url else None,
    ) if b]
    return ' · '.join(str(b) for b in bits)


def to_markdown(plan):
    meta = plan.get('meta') or {}
    days = plan['days']
    dates = day_dates(plan)
    out = [f"# {meta.get('title', 'Trip')}", '']
    if meta.get('subtitle'):
        out += [meta['subtitle'], '']
    out += [f"{len(days)} days · generated {plan.get('savedAt', '')} by "
            'thailand.miker.be — do not edit here, edit the site.', '',
            '## Itinerary', '',
            '| Date | Day | Place | What | Weather | Attached |',
            '| --- | --- | --- | --- | --- | --- |']
    for d, dt in zip(days, dates):
        nodes = d.get('nodes') or []
        out.append('| {} | {} | {} | {} | {} | {} |'.format(
            f'{dt.day:02d} {MONTHS[dt.month - 1]}',
            DOW[dt.weekday()],
            cell(d.get('place')),
            ('★ ' if d.get('special') else '') + cell(d.get('notes')),
            cell(d.get('weather')),
            cell('; '.join(node_line(n) for n in nodes)),
        ))

    booked = [(d, dt, n) for d, dt in zip(days, dates) for n in (d.get('nodes') or [])
              if n.get('type') in ('hotel', 'transport')]
    if booked:
        out += ['', '## Bookings', '']
        for d, dt, n in booked:
            status = n.get('status') or 'idea'
            out.append(f"- **{dt.day:02d} {MONTHS[dt.month - 1]}** "
                       f"({d.get('place') or '—'}) — [{status}] {node_line(n)}")

    notes = plan.get('notes') or []
    if notes:
        out += ['', '## Planning notes', '']
        out += [f'- {plain(n)}' for n in notes]
    return '\n'.join(out) + '\n'


# --- version history --------------------------------------------------------

def ensure_repo():
    os.makedirs(ROOT, exist_ok=True)
    if not os.path.isdir(os.path.join(ROOT, '.git')):
        git('init', '-q', '-b', 'main')
    with open(os.path.join(ROOT, '.gitignore'), 'w') as f:
        # Attachments are tracked: they are trip data too. Only scratch is not.
        f.write('*.tmp\nsnapshots/\n')
    if REMOTE:
        git('remote', 'remove', 'origin', check=False)
        git('remote', 'add', 'origin', REMOTE, check=False)


def commit_and_push():
    try:
        git('add', '-A')
        if not git('status', '--porcelain').stdout.strip():
            return
        plan = read_plan()
        rev = plan.get('rev', '?') if plan else '?'
        git('commit', '-q', '-m', f'plan: rev {rev}')
    except (subprocess.SubprocessError, OSError) as e:
        print(f'commit failed: {e}', flush=True)
        return
    if REMOTE:
        try:
            git('push', '-q', 'origin', 'main')
        except (subprocess.SubprocessError, OSError) as e:
            # Off-site backup is best effort; the local history is still intact
            # and the next successful push carries everything missed.
            print(f'push failed: {e}', flush=True)


def committer():
    while True:
        time.sleep(COMMIT_POLL)
        if dirty.is_set() and time.time() - last_change[0] >= COMMIT_QUIET:
            dirty.clear()
            with lock:
                commit_and_push()


def versions(limit=200):
    try:
        log = git('log', f'-{limit}', '--format=%H%x1f%aI%x1f%s', '--', NAME).stdout
    except (subprocess.SubprocessError, OSError):
        return []
    out = []
    for line in log.strip().splitlines():
        sha, at, subject = line.split('\x1f')
        out.append({'sha': sha, 'shortSha': sha[:8], 'at': at, 'summary': subject})
    return out


def plan_at(sha):
    if not sha.isalnum():
        return None
    try:
        raw = git('show', f'{sha}:{NAME}').stdout
        return json.loads(raw)
    except (subprocess.SubprocessError, OSError, ValueError):
        return None


# --- HTTP -------------------------------------------------------------------

class H(http.server.BaseHTTPRequestHandler):
    def _send(self, code, body, ctype='application/json'):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _body(self):
        n = int(self.headers.get('Content-Length', 0))
        return self.rfile.read(n) if n > 0 else b''

    def _image_path(self):
        name = os.path.basename(self.path[len('/api/images/'):])
        ext = os.path.splitext(name)[1].lower()
        if not name or ext not in TYPES:
            return None, None
        return os.path.join(IMGDIR, name), TYPES[ext]

    def do_GET(self):
        if self.path == '/api/plan':
            plan = read_plan()
            self._send(200, json.dumps(plan, ensure_ascii=False) if plan else 'null')
            return
        if self.path.startswith('/api/versions/'):
            plan = plan_at(self.path[len('/api/versions/'):])
            if plan is None:
                self._json(404, {'error': 'no such version'})
            else:
                self._json(200, plan)
            return
        if self.path == '/api/versions':
            self._json(200, {'versions': versions()})
            return
        if self.path.startswith('/api/images/'):
            path, ctype = self._image_path()
            body = None
            if path:
                try:
                    with open(path, 'rb') as f:
                        body = f.read()
                except FileNotFoundError:
                    body = None
            if body is None:
                self._json(404, {'error': 'not found'})
                return
            self.send_response(200)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(body)))
            self.send_header('Cache-Control', 'private, max-age=31536000, immutable')
            self.end_headers()
            self.wfile.write(body)
            return
        self._json(404, {'error': 'not found'})

    def do_PUT(self):
        if self.path != '/api/plan':
            self._json(404, {'error': 'not found'})
            return
        try:
            plan = json.loads(self._body())
        except ValueError:
            self._json(400, {'error': 'bad json'})
            return
        if not valid(plan):
            self._json(400, {'error': 'plan must be v2 with a non-empty days list'})
            return
        with lock:
            current = read_plan()
            cur_rev = (current or {}).get('rev', 0)
            try:
                sent = int(self.headers.get('If-Match', cur_rev))
            except ValueError:
                sent = -1
            # A write based on an older revision would erase whatever the other
            # traveller saved in between, so hand it back their copy instead.
            if current is not None and sent != cur_rev:
                self._json(409, {'error': 'stale', 'rev': cur_rev, 'current': current})
                return
            saved = write_plan(plan, cur_rev + 1)
        self._json(200, {'ok': True, 'rev': saved['rev'], 'savedAt': saved['savedAt']})

    def do_POST(self):
        if self.path == '/api/restore':
            try:
                sha = json.loads(self._body()).get('sha', '')
            except ValueError:
                self._json(400, {'error': 'bad json'})
                return
            old = plan_at(sha)
            if not valid(old):
                self._json(404, {'error': 'no such version'})
                return
            with lock:
                cur_rev = (read_plan() or {}).get('rev', 0)
                # Restoring moves history forward rather than rewriting it, so
                # a restore is itself undoable.
                saved = write_plan(old, cur_rev + 1)
            self._json(200, {'ok': True, 'rev': saved['rev']})
            return

        if self.path != '/api/images':
            self._json(404, {'error': 'not found'})
            return
        ctype = (self.headers.get('Content-Type') or '').split(';')[0].strip().lower()
        ext = EXTS.get(ctype)
        if not ext:
            self._json(415, {'error': 'unsupported image type'})
            return
        n = int(self.headers.get('Content-Length', 0))
        if n <= 0 or n > MAX_IMAGE:
            self._json(413, {'error': 'image too large'})
            return
        body = self.rfile.read(n)
        os.makedirs(IMGDIR, exist_ok=True)
        name = uuid.uuid4().hex + ext
        tmp = os.path.join(IMGDIR, '.' + name)
        with open(tmp, 'wb') as f:
            f.write(body)
        os.replace(tmp, os.path.join(IMGDIR, name))
        last_change[0] = time.time()
        dirty.set()
        self._json(201, {'url': '/api/images/' + name})

    def do_DELETE(self):
        if not self.path.startswith('/api/images/'):
            self._json(404, {'error': 'not found'})
            return
        path, _ = self._image_path()
        if path:
            try:
                os.remove(path)
                last_change[0] = time.time()
                dirty.set()
            except FileNotFoundError:
                pass
        self._json(200, {'ok': True})

    def log_message(self, *a):
        pass


if __name__ == '__main__':
    ensure_repo()
    threading.Thread(target=committer, daemon=True).start()
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
