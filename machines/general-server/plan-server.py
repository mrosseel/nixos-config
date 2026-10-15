"""Persistence backend for the family trip planner (thailand.miker.be).

Stdlib only, single file, no framework. Access is gated by Caddy on the vhost,
so there is no auth logic here. Caddy lets a holder of the view link reach only
GET /api/view and GET /api/photos/files/<f>. Those two must never return notes,
bookings or TODOs. Caddy marks a request of the view link with the header
X-Thailand-Viewer.

    GET    /api/plan            -> current plan document, or null
    PUT    /api/plan            -> overwrite; needs If-Match: <rev>
    GET    /api/versions        -> commit log of the plan
    GET    /api/versions/<sha>  -> the plan as it was at that commit
    POST   /api/restore         -> {"sha": ...}; restores as a NEW version
    POST   /api/images          -> store an image body, returns {"url": ...}
    GET    /api/images/<id>     -> serve a stored image
    DELETE /api/images/<id>     -> drop a stored image

    GET    /api/photos          -> the trip photos, newest first
    POST   /api/photos/files    -> store a photo file, returns {"file": ...}
    GET    /api/photos/files/<f> -> serve a photo file
    POST   /api/photos          -> add a photo: {full, thumb, day, ...}
    PATCH  /api/photos/<id>     -> change its day or caption
    DELETE /api/photos/<id>     -> drop it and its files

    GET    /api/location        -> the last position of each person
    POST   /api/location        -> {person, name, lat, lon, accuracy, at};
                                   Home Assistant sends it

    GET    /api/view            -> the read-only overview for the family at
                                   home: the legs, their dates and the photos.
                                   No notes, bookings or TODOs. The positions
                                   of the people are in it for the view link
                                   only from the first to the last day of the
                                   trip.

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
from datetime import date, datetime, timedelta, timezone

DATA = os.environ.get('PLAN_FILE', '/var/lib/thailand-planner/plan.json')
PORT = int(os.environ.get('PORT', '8010'))
REMOTE = os.environ.get('PLAN_GIT_REMOTE', '')
ROOT = os.path.dirname(DATA)
IMGDIR = os.path.join(ROOT, 'images')
NAME = os.path.basename(DATA)
PHOTODIR = os.path.join(ROOT, 'photos')
PHOTOS = os.path.join(ROOT, 'photos.json')
# The last position of each person, {person: {...}}. It is not in git: the
# history repo is a copy of the plan, not a log of where the family was.
LOCATION = os.path.join(ROOT, 'location.json')
# The trip is in UTC+7 (Thailand, Laos, Vietnam). The days of the trip are
# dates there. The app uses the same rule.
TRIP_TZ = timezone(timedelta(hours=7))

# One commit per burst of editing rather than per keystroke: the committer wakes
# on a timer and only acts once the plan has been quiet for a moment.
COMMIT_QUIET = 20
COMMIT_POLL = 5
MAX_IMAGE = 12 * 1024 * 1024
# The plan is about 60KB. A body far above that is a fault, not a plan.
MAX_PLAN = 8 * 1024 * 1024

EXTS = {
    'image/jpeg': '.jpg', 'image/png': '.png', 'image/webp': '.webp',
    'image/gif': '.gif', 'image/heic': '.heic', 'image/avif': '.avif',
}
TYPES = {v: k for k, v in EXTS.items()}

lock = threading.Lock()
dirty = threading.Event()
last_change = [0.0]

# The off-site copy is best effort and off the request path, so a broken deploy
# key would otherwise be silent until someone read the journal. The result of
# the last attempt is published for the app to show.
push_state = {'ok': None, 'at': None, 'error': None, 'commitAt': None}

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


# --- photos -----------------------------------------------------------------
#
# Photos are not part of the plan document. Two phones upload at the same time,
# and a photo must not make a plan save fail with a conflict. Each photo has the
# date it belongs to, not a place: the place comes from the plan for that date.

ISO_RE = re.compile(r'^\d{4}-\d{2}-\d{2}$')
FILE_RE = re.compile(r'^[0-9a-f]{32}\.(jpg|png|webp)$')
ID_RE = re.compile(r'^[0-9a-f]{32}$')
MAX_CAPTION = 500


def read_photos():
    try:
        with open(PHOTOS, 'rb') as f:
            photos = json.loads(f.read())
        return photos if isinstance(photos, list) else []
    except (FileNotFoundError, ValueError):
        return []


def write_photos(photos):
    tmp = PHOTOS + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(photos, f, ensure_ascii=False, indent=1)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp, PHOTOS)
    last_change[0] = time.time()
    dirty.set()


def coord(v, limit):
    try:
        v = float(v)
    except (TypeError, ValueError):
        return None
    return round(v, 5) if -limit <= v <= limit else None


def photo_fields(body, photo):
    """Copy the fields a client may set onto photo. Returns an error or None."""
    if 'day' in body:
        if not isinstance(body['day'], str) or not ISO_RE.match(body['day']):
            return 'day must be YYYY-MM-DD'
        photo['day'] = body['day']
    if 'caption' in body:
        photo['caption'] = str(body['caption'] or '')[:MAX_CAPTION]
    return None


def photo_url(name):
    return '/api/photos/files/' + name


def public_photo(p):
    return {
        'id': p['id'], 'day': p['day'], 'caption': p.get('caption', ''),
        'full': photo_url(p['full']), 'thumb': photo_url(p['thumb']),
        'width': p.get('width'), 'height': p.get('height'),
        'takenAt': p.get('takenAt'), 'lat': p.get('lat'), 'lon': p.get('lon'),
    }


PERSON_RE = re.compile(r'^[a-z0-9_.-]{1,64}$')
MAX_NAME = 40


def read_locations():
    try:
        with open(LOCATION, 'rb') as f:
            locs = json.loads(f.read())
        return locs if isinstance(locs, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def people():
    """The last position of each person, by name."""
    return sorted(read_locations().values(), key=lambda p: p['name'].lower())


def location_from(body):
    """The person and the position in a request body, or None. Home Assistant
    sends {person: "person.mike", name: "Mike", lat, lon, accuracy, at}."""
    person = body.get('person')
    if not isinstance(person, str) or not PERSON_RE.match(person):
        return None
    lat, lon = coord(body.get('lat'), 90), coord(body.get('lon'), 180)
    if lat is None or lon is None:
        return None
    acc = coord(body.get('accuracy'), 1e6)
    acc = round(acc) if acc is not None and acc >= 0 else None
    name = str(body.get('name') or '').strip()[:MAX_NAME] or person.split('.')[-1]
    # The time of the fix, if the sender knows it. A time in the future is a
    # wrong clock.
    now = time.time()
    try:
        at = datetime.fromisoformat(str(body.get('at'))).timestamp()
    except ValueError:
        at = now
    at = min(at, now)
    return {'person': person, 'name': name, 'lat': lat, 'lon': lon, 'accuracy': acc,
            'at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(at))}


def write_location(loc):
    """Keep loc if it is newer than the stored position of that person.
    Returns the stored one."""
    with lock:
        locs = read_locations()
        old = locs.get(loc['person'])
        if old and old.get('at', '') > loc['at']:
            return old
        locs[loc['person']] = loc
        tmp = LOCATION + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(locs, f, ensure_ascii=False)
        os.replace(tmp, LOCATION)
    return loc


def sorted_photos():
    return sorted(read_photos(),
                  key=lambda p: (p['day'], p.get('takenAt') or '', p.get('addedAt') or ''),
                  reverse=True)


def overview(viewer):
    """The plan with everything private left out: per leg only the place and
    its dates. Built here and not in the browser, so the private parts never
    reach a phone that holds only the view link.

    The view link sees the position of the phone only during the trip. Before
    and after the trip the phone is at home."""
    plan = read_plan()
    legs = []
    if plan:
        for d, dt in zip(plan['days'], day_dates(plan)):
            place = plain(d.get('place')).strip()
            iso = dt.isoformat()
            if legs and legs[-1]['place'] == place:
                legs[-1]['last'] = iso
                legs[-1]['days'] += 1
            else:
                legs.append({'place': place, 'first': iso, 'last': iso, 'days': 1})
    meta = (plan or {}).get('meta') or {}
    start = legs[0]['first'] if legs else None
    end = legs[-1]['last'] if legs else None
    today = datetime.now(TRIP_TZ).date().isoformat()
    during = bool(legs) and start <= today <= end
    return {
        'title': plain(meta.get('title')) or 'Trip',
        'start': start,
        'end': end,
        'legs': legs,
        'photos': [public_photo(p) for p in sorted_photos()],
        'people': [{k: p[k] for k in ('name', 'lat', 'lon', 'accuracy', 'at')} for p in people()]
        if during or not viewer else [],
    }


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
        f.write('*.tmp\nsnapshots/\nlocation.json\n')
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
        push_state['commitAt'] = time.time()
    except (subprocess.SubprocessError, OSError) as e:
        print(f'commit failed: {e}', flush=True)
        return
    if REMOTE:
        try:
            git('push', '-q', 'origin', 'main')
            push_state.update(ok=True, at=time.time(), error=None)
        except (subprocess.SubprocessError, OSError) as e:
            # Off-site backup is best effort; the local history is still intact
            # and the next successful push carries everything missed. It is not
            # silent, though — the app shows it.
            detail = getattr(e, 'stderr', '') or str(e)
            push_state.update(ok=False, at=time.time(), error=detail.strip()[-300:])
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
        if n > MAX_PLAN:
            raise ValueError('body too large')
        return self.rfile.read(n) if n > 0 else b''

    def _file(self, path, ctype):
        try:
            with open(path, 'rb') as f:
                body = f.read()
        except FileNotFoundError:
            self._json(404, {'error': 'not found'})
            return
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'private, max-age=31536000, immutable')
        self.end_headers()
        self.wfile.write(body)

    def _store(self, folder):
        """Write the request body to a new file in folder. Returns its name, or
        None after an error response."""
        ctype = (self.headers.get('Content-Type') or '').split(';')[0].strip().lower()
        ext = EXTS.get(ctype)
        if not ext:
            self._json(415, {'error': 'unsupported image type'})
            return None
        n = int(self.headers.get('Content-Length', 0))
        if n <= 0 or n > MAX_IMAGE:
            self._json(413, {'error': 'image too large'})
            return None
        body = self.rfile.read(n)
        os.makedirs(folder, exist_ok=True)
        name = uuid.uuid4().hex + ext
        tmp = os.path.join(folder, '.' + name)
        with open(tmp, 'wb') as f:
            f.write(body)
        os.replace(tmp, os.path.join(folder, name))
        last_change[0] = time.time()
        dirty.set()
        return name

    def _image_path(self):
        name = os.path.basename(self.path[len('/api/images/'):])
        ext = os.path.splitext(name)[1].lower()
        if not name or ext not in TYPES:
            return None, None
        return os.path.join(IMGDIR, name), TYPES[ext]

    def do_GET(self):
        if self.path == '/api/plan':
            plan = read_plan()
            # The app polls every ten seconds. The revision is the ETag, so an
            # unchanged plan costs a 304 and not the whole document. Any digits
            # in If-None-Match count: Caddy can add a suffix like "-gzip".
            etag = f'"{plan.get("rev", 0)}"' if plan else None
            seen = re.findall(r'\d+', self.headers.get('If-None-Match') or '')
            if etag and seen and seen[0] == etag.strip('"'):
                self.send_response(304)
                self.send_header('ETag', etag)
                self.send_header('Cache-Control', 'no-cache')
                self.end_headers()
                return
            raw = (json.dumps(plan, ensure_ascii=False) if plan else 'null').encode()
            self.send_response(200)
            self.send_header('Content-Type', 'application/json')
            self.send_header('Content-Length', str(len(raw)))
            self.send_header('Cache-Control', 'no-cache')
            if etag:
                self.send_header('ETag', etag)
            self.end_headers()
            self.wfile.write(raw)
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
        if self.path == '/api/health':
            # "behind" means there is a commit newer than the last successful
            # push — the off-site copy is out of date, whatever the last error.
            stale = (push_state['commitAt'] is not None
                     and (push_state['at'] is None
                          or push_state['at'] < push_state['commitAt'] - 1))
            self._json(200, {
                'remote': bool(REMOTE),
                'push': {
                    'ok': push_state['ok'],
                    'error': push_state['error'],
                    'agoSeconds': (round(time.time() - push_state['at'])
                                   if push_state['at'] else None),
                    'behind': stale,
                },
            })
            return
        if self.path.startswith('/api/images/'):
            path, ctype = self._image_path()
            if path:
                self._file(path, ctype)
            else:
                self._json(404, {'error': 'not found'})
            return
        if self.path == '/api/view':
            self._json(200, overview(bool(self.headers.get('X-Thailand-Viewer'))))
            return
        if self.path == '/api/location':
            self._json(200, people())
            return
        if self.path == '/api/photos':
            self._json(200, {'photos': [public_photo(p) for p in sorted_photos()]})
            return
        if self.path.startswith('/api/photos/files/'):
            name = self.path[len('/api/photos/files/'):]
            if FILE_RE.match(name):
                self._file(os.path.join(PHOTODIR, name), TYPES[os.path.splitext(name)[1]])
            else:
                self._json(404, {'error': 'not found'})
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

        if self.path == '/api/location':
            try:
                body = json.loads(self._body())
                if not isinstance(body, dict):
                    raise ValueError('not an object')
            except ValueError:
                self._json(400, {'error': 'bad json'})
                return
            loc = location_from(body)
            if not loc:
                self._json(400, {'error': 'person, lat and lon are required'})
                return
            self._json(200, write_location(loc))
            return

        if self.path == '/api/photos/files':
            name = self._store(PHOTODIR)
            if name:
                self._json(201, {'file': name})
            return

        if self.path == '/api/photos':
            try:
                body = json.loads(self._body())
                if not isinstance(body, dict):
                    raise ValueError('not an object')
            except ValueError:
                self._json(400, {'error': 'bad json'})
                return
            full, thumb = body.get('full'), body.get('thumb')
            for name in (full, thumb):
                if not (isinstance(name, str) and FILE_RE.match(name)
                        and os.path.isfile(os.path.join(PHOTODIR, name))):
                    self._json(400, {'error': 'full and thumb must be uploaded files'})
                    return
            if 'day' not in body:
                self._json(400, {'error': 'day is required'})
                return
            photo = {'id': uuid.uuid4().hex, 'full': full, 'thumb': thumb,
                     'addedAt': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
            error = photo_fields(body, photo)
            if error:
                self._json(400, {'error': error})
                return
            for key, limit in (('lat', 90), ('lon', 180)):
                photo[key] = coord(body.get(key), limit)
            for key in ('width', 'height'):
                photo[key] = body[key] if isinstance(body.get(key), int) else None
            taken = body.get('takenAt')
            photo['takenAt'] = taken[:19] if isinstance(taken, str) else None
            with lock:
                photos = read_photos()
                photos.append(photo)
                write_photos(photos)
            self._json(201, public_photo(photo))
            return

        if self.path != '/api/images':
            self._json(404, {'error': 'not found'})
            return
        name = self._store(IMGDIR)
        if name:
            self._json(201, {'url': '/api/images/' + name})

    def _photo_id(self):
        pid = self.path[len('/api/photos/'):]
        return pid if self.path.startswith('/api/photos/') and ID_RE.match(pid) else None

    def do_PATCH(self):
        pid = self._photo_id()
        if not pid:
            self._json(404, {'error': 'not found'})
            return
        try:
            body = json.loads(self._body())
            if not isinstance(body, dict):
                raise ValueError('not an object')
        except ValueError:
            self._json(400, {'error': 'bad json'})
            return
        with lock:
            photos = read_photos()
            photo = next((p for p in photos if p['id'] == pid), None)
            if not photo:
                self._json(404, {'error': 'no such photo'})
                return
            error = photo_fields(body, photo)
            if error:
                self._json(400, {'error': error})
                return
            write_photos(photos)
        self._json(200, public_photo(photo))

    def do_DELETE(self):
        pid = self._photo_id()
        if pid:
            with lock:
                photos = read_photos()
                gone = [p for p in photos if p['id'] == pid]
                if gone:
                    write_photos([p for p in photos if p['id'] != pid])
            for p in gone:
                for name in (p['full'], p['thumb']):
                    try:
                        os.remove(os.path.join(PHOTODIR, name))
                    except FileNotFoundError:
                        pass
            self._json(200, {'ok': True})
            return
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
