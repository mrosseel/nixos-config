"""Persistence backend for the family trip planner (thailand.miker.be).

Stdlib only, single file, no framework. Access is gated by Caddy on the vhost,
so there is no auth logic here. Caddy lets a holder of the view link reach only
GET /api/view and GET /api/photos/files/<f>. Those two must never return notes,
bookings or TODOs. Caddy marks a request of the view link with the header
X-Thailand-Viewer. The view link can also reach /api/push/*, GET
/api/reactions and POST /api/reactions/<id> and /api/comments/<id>.

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
    PUT    /api/photos/order    -> {day, ids}: the order of the photos of a day
    DELETE /api/photos/<id>     -> drop it and its files

    GET    /api/location        -> the last position of each person
    POST   /api/location        -> {person, name, lat, lon, accuracy, at};
                                   Home Assistant sends it
    GET    /api/track           -> the route the people travelled, from
                                   PEOPLE_FROM: a list of lines of [lat, lon]

    GET    /api/stories         -> the story of each day, {day: text}
    PUT    /api/stories/<day>   -> {text}; an empty text removes it

    GET    /api/push/key        -> the public VAPID key for the browser
    POST   /api/push/subscribe  -> {subscription}; a phone asks for a
                                   notification when there are new photos
                                   or a new story
    DELETE /api/push/subscribe  -> {endpoint}; the phone stops them

    GET    /api/view            -> the read-only overview for the family at
                                   home: the legs, their dates, the photos and
                                   the stories. No notes, bookings or TODOs.
                                   The positions and the route of the people
                                   are in it for the view link only from
                                   PEOPLE_FROM to PEOPLE_UNTIL.

Two people edit this plan at the same time. Every write therefore carries the
revision it was based on, and a stale write is refused rather than silently
overwriting the other person's edit.

The state directory is a git repository. Every burst of editing lands as one
commit and is pushed to a private remote, which is both the version history the
UI browses and the only off-site copy of the trip.
"""

import base64
import http.server
import json
import math
import re
import os
import subprocess
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from datetime import date, datetime, timedelta, timezone

# Web push to the phones of the family at home. Without the package, as in
# the local sandbox, the site works and sends no notifications.
try:
    from cryptography.hazmat.primitives import serialization
    from pywebpush import webpush, WebPushException
except ImportError:
    webpush = None

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
# The route of each person, {person: [[lat, lon, time], ...]}. Not in git
# either, for the same reason.
TRACK = os.path.join(ROOT, 'track.json')
# The story of each day, {day: text}. This is trip content, so it is in git.
STORIES = os.path.join(ROOT, 'stories.json')
# The trip is in UTC+7 (Thailand, Laos, Vietnam). The days of the trip are
# dates there. The app uses the same rule.
TRIP_TZ = timezone(timedelta(hours=7))
# The first and the last day on which the view link sees where the people
# are. Without them, the first and the last day of the trip.
PEOPLE_FROM = os.environ.get('PEOPLE_FROM') or None
PEOPLE_UNTIL = os.environ.get('PEOPLE_UNTIL') or None
# A position goes into the route when it is this far from the last point of
# that person. Closer points add nothing at the zoom of the map.
TRACK_STEP_M = 500
# A position less accurate than this does not go into the route.
TRACK_MAX_ACC = 1000
# The route that the map gets is simplified: no point leaves the real route by
# more than this, in degrees (about 200 m).
TRACK_TOLERANCE = 0.002
MAX_STORY = 5000
# The push subscriptions of the family at home, {endpoint: subscription}. Not
# in git: a subscription is the key of one phone.
PUSH = os.path.join(ROOT, 'push.json')
# The private VAPID key, a PEM file. Without it there are no notifications.
VAPID_KEY = os.environ.get('VAPID_PRIVATE_KEY') or ''
VAPID_SUB = 'mailto:planner@miker.be'
# One notification for a burst of photos and stories. It goes out after this
# many seconds without a new one.
PUSH_QUIET = 180
PUSH_POLL = 10
MAX_SUBS = 200

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
        # Only entries of a person. An older version of this file held one
        # position without a person.
        return ({k: v for k, v in locs.items() if isinstance(v, dict) and 'name' in v}
                if isinstance(locs, dict) else {})
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
        add_to_track(loc)
    return loc


def distance_m(a, b):
    """The distance in metres between two (lat, lon)."""
    la1, lo1, la2, lo2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    h = (math.sin((la2 - la1) / 2) ** 2
         + math.cos(la1) * math.cos(la2) * math.sin((lo2 - lo1) / 2) ** 2)
    return 2 * 6371000 * math.asin(math.sqrt(h))


def read_track():
    try:
        with open(TRACK, 'rb') as f:
            track = json.loads(f.read())
        return track if isinstance(track, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def add_to_track(loc):
    """Add loc to the route of its person if it is far enough from the last
    point. The caller holds the lock."""
    if loc['accuracy'] is not None and loc['accuracy'] > TRACK_MAX_ACC:
        return
    track = read_track()
    points = track.setdefault(loc['person'], [])
    at = int(datetime.fromisoformat(loc['at']).timestamp())
    if points and (points[-1][2] >= at
                   or distance_m(points[-1], (loc['lat'], loc['lon'])) < TRACK_STEP_M):
        return
    points.append([loc['lat'], loc['lon'], at])
    tmp = TRACK + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(track, f)
    os.replace(tmp, TRACK)


def simplify(points, tol):
    """Douglas-Peucker on [(lat, lon), ...]: keep only the points that the
    shape of the line needs."""
    if len(points) < 3:
        return points
    keep = [False] * len(points)
    keep[0] = keep[-1] = True
    stack = [(0, len(points) - 1)]
    while stack:
        a, b = stack.pop()
        (y1, x1), (y2, x2) = points[a], points[b]
        dy, dx = y2 - y1, x2 - x1
        norm = math.hypot(dx, dy)
        far, index = 0.0, None
        for i in range(a + 1, b):
            y, x = points[i]
            d = (abs(dy * (x - x1) - dx * (y - y1)) / norm if norm
                 else math.hypot(x - x1, y - y1))
            if d > far:
                far, index = d, i
        if index is not None and far > tol:
            keep[index] = True
            stack += [(a, index), (index, b)]
    return [p for p, k in zip(points, keep) if k]


track_cache = {}


def route(first):
    """The route of each person from the day first (UTC+7), simplified, as a
    list of lines of [lat, lon]."""
    try:
        stamp = os.stat(TRACK).st_mtime_ns
    except FileNotFoundError:
        return []
    key = (stamp, first)
    if key not in track_cache:
        since = (datetime.fromisoformat(first).replace(tzinfo=TRIP_TZ).timestamp()
                 if first else 0)
        lines = []
        for points in read_track().values():
            line = [(p[0], p[1]) for p in points if p[2] >= since]
            if len(line) > 1:
                lines.append([list(p) for p in simplify(line, TRACK_TOLERANCE)])
        track_cache.clear()
        track_cache[key] = lines
    return track_cache[key]


def read_stories():
    try:
        with open(STORIES, 'rb') as f:
            stories = json.loads(f.read())
        return stories if isinstance(stories, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def write_stories(stories):
    tmp = STORIES + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(stories, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, STORIES)
    last_change[0] = time.time()
    dirty.set()


# --- photos from Google Photos ----------------------------------------------
# The travellers pick photos in the Google Photos picker, in the browser. The
# browser cannot download the picked bytes itself: the download needs the
# OAuth token in a header, and the Google host does not allow that from
# another site. So the browser sends the URL and its short-lived token here,
# and this service fetches the bytes. Only Google photo hosts are fetched.
FETCH_HOSTS = ('.googleusercontent.com', 'photospicker.googleapis.com')
MAX_FETCH = 80 * 1024 * 1024


def fetch_host_ok(url):
    try:
        u = urllib.parse.urlsplit(url)
    except ValueError:
        return False
    host = (u.hostname or '').lower()
    return u.scheme == 'https' and any(
        host == h.lstrip('.') or host.endswith(h) for h in FETCH_HOSTS)


# --- reactions and comments --------------------------------------------------
# The family at home reacts to a photo with an emoji, or writes a comment.
# Each reaction and comment carries the name the sender typed once on their
# phone. The file holds, per photo id, the count of each emoji, the names
# behind each emoji, and the comments. Nobody logs in: a phone remembers its
# own reactions and its name itself. Reactions from before the names have a
# count but no name. Each address may send a limited number of comments and
# reactions per hour.
REACTIONS = os.path.join(ROOT, 'reactions.json')
EMOJIS = ('❤️', '😂', '😮', '👍', '🙏')
MAX_COMMENT = 500
MAX_COMMENT_NAME = 40
MAX_COMMENTS_PER_PHOTO = 200
RATE_WINDOW = 3600
RATE_COMMENTS = 10
RATE_REACTIONS = 60
rate = {}  # (address, kind) -> the times of its requests this hour


def read_reactions():
    try:
        with open(REACTIONS, 'rb') as f:
            data = json.loads(f.read())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def write_reactions(data):
    tmp = REACTIONS + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
    os.replace(tmp, REACTIONS)
    last_change[0] = time.time()
    dirty.set()


def reactions_of(data, pid):
    entry = data.setdefault(pid, {})
    entry.setdefault('emoji', {})
    entry.setdefault('who', {})
    entry.setdefault('comments', [])
    return entry


def under_limit(address, kind, limit):
    """True when the address is under its limit for this kind this hour. A
    request that passes counts. The caller holds the lock."""
    now = time.time()
    key = (address, kind)
    times = [t for t in rate.get(key, []) if now - t < RATE_WINDOW]
    if len(times) >= limit:
        rate[key] = times
        return False
    times.append(now)
    rate[key] = times
    if len(rate) > 5000:
        for k in [k for k, v in rate.items() if not v or now - v[-1] >= RATE_WINDOW]:
            del rate[k]
    return True


def one_line(text, limit):
    """The text without control characters, at most limit characters."""
    text = ''.join(c for c in text if c == '\n' or c >= ' ')
    return text.strip()[:limit]


# How the family reaches a leg, from the transport items on its first day. The
# first match wins, so a day with a taxi and a flight is a flight. The app has
# the same table in src/transport.js.
TRANSPORT = [
    ('flight', re.compile(r'vlucht|flight|vliegtuig|plane', re.I)),
    ('train', re.compile(r'trein|train', re.I)),
    ('boat', re.compile(r'boot|boat|ferry|slowboat|cruise', re.I)),
    ('bus', re.compile(r'bus|minivan|limo', re.I)),
    ('car', re.compile(r'taxi|auto|grab|chauffeur|driver|transfer|\bcar\b', re.I)),
]


def transport_of(day):
    """The way of travel of the transport items of a day, or None. Only the
    kind goes to the view link, not the details."""
    text = ' '.join(
        '%s %s' % (plain(n.get('title')), plain((n.get('data') or {}).get('mode')))
        for n in day.get('nodes') or [] if n.get('type') == 'transport')
    return next((mode for mode, rx in TRANSPORT if rx.search(text)), None)


def sorted_photos():
    """Newest day first. Within a day: the photos the travellers arranged by
    hand, in that order, then the others newest first. Each sort is stable,
    so the later sorts keep the order of the earlier ones."""
    newest = sorted(read_photos(),
                    key=lambda p: (p.get('takenAt') or '', p.get('addedAt') or ''), reverse=True)
    arranged = sorted(newest, key=lambda p: (p.get('order') is None, p.get('order') or 0))
    return sorted(arranged, key=lambda p: p['day'], reverse=True)


def overview(viewer):
    """The plan with everything private left out: per leg only the place and
    its dates. Built here and not in the browser, so the private parts never
    reach a phone that holds only the view link.

    The view link sees the positions and the route of the people only from
    PEOPLE_FROM to PEOPLE_UNTIL. Before and after that the family is at
    home."""
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
                legs.append({'place': place, 'first': iso, 'last': iso, 'days': 1,
                             'by': transport_of(d)})
    meta = (plan or {}).get('meta') or {}
    start = legs[0]['first'] if legs else None
    end = legs[-1]['last'] if legs else None
    first = PEOPLE_FROM or start
    last = PEOPLE_UNTIL or end
    today = datetime.now(TRIP_TZ).date().isoformat()
    shown = bool(first and last) and first <= today <= last
    return {
        'title': plain(meta.get('title')) or 'Trip',
        'start': start,
        'end': end,
        'legs': legs,
        'photos': [public_photo(p) for p in sorted_photos()],
        'people': [{k: p[k] for k in ('name', 'lat', 'lon', 'accuracy', 'at')} for p in people()]
        if shown or not viewer else [],
        'peopleFrom': first,
        'peopleUntil': last,
        'track': route(first) if shown or not viewer else [],
        'stories': read_stories(),
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
        f.write('*.tmp\nsnapshots/\nlocation.json\ntrack.json\npush.json\n')
    if REMOTE:
        git('remote', 'remove', 'origin', check=False)
        git('remote', 'add', 'origin', REMOTE, check=False)


def commit():
    """Commit what changed. Returns True when there is a new commit. The
    caller holds the lock, so no write lands between add and commit."""
    try:
        git('add', '-A')
        if not git('status', '--porcelain').stdout.strip():
            return False
        plan = read_plan()
        rev = plan.get('rev', '?') if plan else '?'
        git('commit', '-q', '-m', f'plan: rev {rev}')
        push_state['commitAt'] = time.time()
        return True
    except (subprocess.SubprocessError, OSError) as e:
        print(f'commit failed: {e}', flush=True)
        return False


def push():
    """Push to the off-site copy. Not under the lock: a push waits up to
    two minutes when GitHub is slow, and a save must not wait with it."""
    if not REMOTE:
        return
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
                committed = commit()
            if committed:
                push()


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


# --- notifications ----------------------------------------------------------
#
# A phone of the family at home subscribes once. Each new photo and each new
# story counts, and after a quiet moment one notification goes to every
# phone: "3 nieuwe foto's en een nieuw verhaal uit Luang Prabang".

def read_subs():
    try:
        with open(PUSH, 'rb') as f:
            subs = json.loads(f.read())
        return subs if isinstance(subs, dict) else {}
    except (FileNotFoundError, ValueError):
        return {}


def write_subs(subs):
    tmp = PUSH + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(subs, f)
    os.replace(tmp, PUSH)


def subscription_from(body):
    """The push subscription in a request body, as the browser gives it, or
    None."""
    sub = body.get('subscription')
    if not isinstance(sub, dict):
        return None
    endpoint, keys = sub.get('endpoint'), sub.get('keys')
    if not (isinstance(endpoint, str) and endpoint.startswith('https://')
            and len(endpoint) < 2048):
        return None
    if not (isinstance(keys, dict) and isinstance(keys.get('p256dh'), str)
            and isinstance(keys.get('auth'), str)):
        return None
    return {'endpoint': endpoint,
            'keys': {'p256dh': keys['p256dh'][:200], 'auth': keys['auth'][:100]}}


push_on = bool(webpush and VAPID_KEY)
vapid_public = [None]


def vapid_public_key():
    """The public VAPID key as the browser wants it: the raw point,
    base64url without padding. None when push is off."""
    if not push_on:
        return None
    if vapid_public[0] is None:
        with open(VAPID_KEY, 'rb') as f:
            key = serialization.load_pem_private_key(f.read(), password=None)
        raw = key.public_key().public_bytes(serialization.Encoding.X962,
                                            serialization.PublicFormat.UncompressedPoint)
        vapid_public[0] = base64.urlsafe_b64encode(raw).rstrip(b'=').decode()
    return vapid_public[0]


# The photos and stories the phones were not told about yet: photos per day,
# the days with a new story, and the time of the last one.
pending = {'photos': {}, 'stories': set(), 'at': 0.0}


def note(kind, day):
    """Count a new photo or story for the next notification. The caller
    holds the lock."""
    if kind == 'photo':
        pending['photos'][day] = pending['photos'].get(day, 0) + 1
    else:
        pending['stories'].add(day)
    pending['at'] = time.time()


def place_of(day):
    plan = read_plan()
    for d, dt in zip(plan['days'], day_dates(plan)) if plan else ():
        if dt.isoformat() == day:
            return plain(d.get('place')).strip()
    return ''


def notification():
    """One message for all pending changes, or None. A change on a day the
    view link cannot see yet, from a preview of a later day, is not in it."""
    today = datetime.now(TRIP_TZ).date().isoformat()
    photos = sum(n for d, n in pending['photos'].items() if d <= today)
    stories = [d for d in pending['stories'] if d <= today]
    days = sorted({d for d in pending['photos'] if d <= today} | set(stories))
    if not days:
        return None
    parts = []
    if photos:
        parts.append('1 nieuwe foto' if photos == 1 else f"{photos} nieuwe foto's")
    if stories:
        parts.append('een nieuw verhaal' if len(stories) == 1 else f'{len(stories)} nieuwe verhalen')
    place = place_of(days[-1])
    meta = (read_plan() or {}).get('meta') or {}
    return {'title': plain(meta.get('title')) or 'Reis',
            'body': ' en '.join(parts) + (f' uit {place}' if place else ''),
            'url': '/view.html'}


def send_push(msg):
    """Send msg to every phone. A phone that is gone (404, 410) is removed.
    Not under the lock: a slow push must not block a save."""
    data = json.dumps(msg, ensure_ascii=False)
    gone = []
    for endpoint, sub in read_subs().items():
        try:
            webpush(subscription_info=sub, data=data, vapid_private_key=VAPID_KEY,
                    vapid_claims={'sub': VAPID_SUB}, ttl=24 * 3600, timeout=20)
        except WebPushException as e:
            status = getattr(e.response, 'status_code', None)
            if status in (404, 410):
                gone.append(endpoint)
            else:
                print(f'push failed for a phone: {e}', flush=True)
        except Exception as e:  # noqa: BLE001 - a network fault must not stop the thread
            print(f'push failed for a phone: {e}', flush=True)
    if gone:
        with lock:
            subs = read_subs()
            for endpoint in gone:
                subs.pop(endpoint, None)
            write_subs(subs)
        print(f'{len(gone)} phone(s) unsubscribed', flush=True)


def notifier():
    while True:
        time.sleep(PUSH_POLL)
        with lock:
            if not pending['at'] or time.time() - pending['at'] < PUSH_QUIET:
                continue
            msg = notification()
            pending['photos'].clear()
            pending['stories'].clear()
            pending['at'] = 0.0
        if msg and push_on:
            send_push(msg)


# --- HTTP -------------------------------------------------------------------

class H(http.server.BaseHTTPRequestHandler):
    # A client that stops in the middle of a request holds a thread. After
    # this many seconds of silence the thread closes the connection.
    timeout = 60

    def _send(self, code, body, ctype='application/json'):
        raw = body if isinstance(body, bytes) else body.encode()
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def _json(self, code, obj):
        self._send(code, json.dumps(obj, ensure_ascii=False))

    def _length(self):
        """The Content-Length header as a number. A missing or a bad header
        counts as zero."""
        try:
            return int(self.headers.get('Content-Length') or 0)
        except ValueError:
            return 0

    def _body(self):
        n = self._length()
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
        n = self._length()
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
        if self.path == '/api/track':
            self._json(200, overview(False)['track'])
            return
        if self.path == '/api/stories':
            self._json(200, read_stories())
            return
        if self.path == '/api/push/key':
            self._json(200, {'key': vapid_public_key()})
            return
        if self.path == '/api/photos':
            self._json(200, {'photos': [public_photo(p) for p in sorted_photos()]})
            return
        if self.path == '/api/reactions':
            self._json(200, {'photos': read_reactions()})
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
        if self.path == '/api/photos/order':
            self._order_photos()
            return
        if self.path.startswith('/api/stories/'):
            day = self.path[len('/api/stories/'):]
            if not ISO_RE.match(day):
                self._json(404, {'error': 'not found'})
                return
            try:
                body = json.loads(self._body())
                if not isinstance(body, dict):
                    raise ValueError('not an object')
            except ValueError:
                self._json(400, {'error': 'bad json'})
                return
            text = str(body.get('text') or '').strip()[:MAX_STORY]
            with lock:
                stories = read_stories()
                if text and text != stories.get(day):
                    note('story', day)
                if text:
                    stories[day] = text
                else:
                    stories.pop(day, None)
                write_stories(stories)
            self._json(200, {'day': day, 'text': text})
            return
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

        if self.path == '/api/push/subscribe':
            try:
                body = json.loads(self._body())
                if not isinstance(body, dict):
                    raise ValueError('not an object')
            except ValueError:
                self._json(400, {'error': 'bad json'})
                return
            sub = subscription_from(body)
            if not sub:
                self._json(400, {'error': 'a push subscription is required'})
                return
            with lock:
                subs = read_subs()
                if sub['endpoint'] not in subs and len(subs) >= MAX_SUBS:
                    self._json(429, {'error': 'too many phones'})
                    return
                subs[sub['endpoint']] = sub
                write_subs(subs)
            self._json(201, {'ok': True, 'push': push_on})
            return

        if self.path == '/api/photos/files':
            name = self._store(PHOTODIR)
            if name:
                self._json(201, {'file': name})
            return

        if self.path == '/api/photos/fetch':
            self._fetch_photo()
            return

        if self.path.startswith('/api/reactions/') or self.path.startswith('/api/comments/'):
            self._react()
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
                note('photo', photo['day'])
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

    def _address(self):
        """The address of the client. Caddy appends it to X-Forwarded-For, so
        the last entry is the one to trust."""
        forwarded = self.headers.get('X-Forwarded-For', '')
        return forwarded.split(',')[-1].strip() or self.client_address[0]

    def _order_photos(self):
        """PUT /api/photos/order {day, ids}: the ids of every photo of that day,
        in the order the travellers want. A photo added to the day later comes
        after them."""
        try:
            body = json.loads(self._body())
            if not isinstance(body, dict):
                raise ValueError('not an object')
        except ValueError:
            self._json(400, {'error': 'bad json'})
            return
        day, ids = body.get('day'), body.get('ids')
        if not (isinstance(day, str) and ISO_RE.match(day) and isinstance(ids, list)
                and all(isinstance(i, str) for i in ids)):
            self._json(400, {'error': 'day and ids are required'})
            return
        with lock:
            photos = read_photos()
            of_day = {p['id'] for p in photos if p['day'] == day}
            if set(ids) != of_day or len(ids) != len(of_day):
                self._json(409, {'error': 'ids must be every photo of that day, once'})
                return
            rank = {pid: i for i, pid in enumerate(ids)}
            for p in photos:
                if p['id'] in rank:
                    p['order'] = rank[p['id']]
            write_photos(photos)
        self._json(200, {'photos': [public_photo(p) for p in sorted_photos()]})

    def _fetch_photo(self):
        """POST /api/photos/fetch {url, token}: the bytes of one picked Google
        photo, for the planner only. Caddy keeps the viewer out."""
        try:
            body = json.loads(self._body())
            if not isinstance(body, dict):
                raise ValueError('not an object')
        except ValueError:
            self._json(400, {'error': 'bad json'})
            return
        url, token = body.get('url'), body.get('token')
        if not (isinstance(url, str) and isinstance(token, str) and token and fetch_host_ok(url)):
            self._json(400, {'error': 'url must be a Google photo URL, token is required'})
            return
        req = urllib.request.Request(url, headers={
            'Authorization': 'Bearer ' + token, 'User-Agent': 'thailand-planner'})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                ctype = r.headers.get('Content-Type', 'application/octet-stream')
                data = r.read(MAX_FETCH + 1)
        except urllib.error.HTTPError as e:
            self._json(502, {'error': f'Google answered {e.code}'})
            return
        except (urllib.error.URLError, OSError, ValueError):
            self._json(502, {'error': 'Google not reachable'})
            return
        if len(data) > MAX_FETCH:
            self._json(413, {'error': 'photo too large'})
            return
        if not ctype.startswith('image/'):
            self._json(502, {'error': 'not an image'})
            return
        self.send_response(200)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def _react(self):
        """POST /api/reactions/<id> {emoji, name, remove} and
        POST /api/comments/<id> {name, text}, from the family at home."""
        kind, _, pid = self.path[len('/api/'):].partition('/')
        if not ID_RE.match(pid):
            self._json(404, {'error': 'not found'})
            return
        try:
            body = json.loads(self._body())
            if not isinstance(body, dict):
                raise ValueError('not an object')
        except ValueError:
            self._json(400, {'error': 'bad json'})
            return
        name = one_line(body.get('name') if isinstance(body.get('name'), str) else '', MAX_COMMENT_NAME)
        if not name:
            self._json(400, {'error': 'name is required'})
            return
        if kind == 'reactions':
            emoji = body.get('emoji')
            if emoji not in EMOJIS:
                self._json(400, {'error': 'unknown emoji'})
                return
            comment = None
        else:
            text = one_line(body.get('text') if isinstance(body.get('text'), str) else '', MAX_COMMENT)
            if not text:
                self._json(400, {'error': 'text is required'})
                return
            comment = {'id': uuid.uuid4().hex, 'name': name,
                       'text': text, 'at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())}
        with lock:
            if not any(p['id'] == pid for p in read_photos()):
                self._json(404, {'error': 'no such photo'})
                return
            limit = RATE_REACTIONS if comment is None else RATE_COMMENTS
            if not under_limit(self._address(), kind, limit):
                self._json(429, {'error': 'too many this hour'})
                return
            data = read_reactions()
            entry = reactions_of(data, pid)
            if comment is None:
                # One reaction per name and emoji. A removal without a
                # matching name takes one from the count: a reaction given
                # before the names.
                names = entry['who'].setdefault(emoji, [])
                n = entry['emoji'].get(emoji, 0)
                if body.get('remove'):
                    if name in names:
                        names.remove(name)
                    n -= 1
                elif name not in names:
                    names.append(name)
                    n += 1
                entry['emoji'][emoji] = max(0, n)
                if not entry['emoji'][emoji]:
                    del entry['emoji'][emoji]
                if not names:
                    del entry['who'][emoji]
            else:
                if len(entry['comments']) >= MAX_COMMENTS_PER_PHOTO:
                    self._json(429, {'error': 'too many comments on this photo'})
                    return
                entry['comments'].append(comment)
            write_reactions(data)
        self._json(201 if comment else 200, comment or {'emoji': entry['emoji'], 'who': entry['who']})

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
        if self.path == '/api/push/subscribe':
            try:
                endpoint = json.loads(self._body()).get('endpoint')
            except (ValueError, AttributeError):
                endpoint = None
            with lock:
                subs = read_subs()
                if subs.pop(endpoint, None) is not None:
                    write_subs(subs)
            self._json(200, {'ok': True})
            return
        if self.path.startswith('/api/comments/'):
            # Only the travellers get here: Caddy stops a DELETE from the
            # view link.
            pid, _, cid = self.path[len('/api/comments/'):].partition('/')
            if not (ID_RE.match(pid) and ID_RE.match(cid)):
                self._json(404, {'error': 'not found'})
                return
            with lock:
                data = read_reactions()
                entry = reactions_of(data, pid)
                kept = [c for c in entry['comments'] if c['id'] != cid]
                if len(kept) != len(entry['comments']):
                    entry['comments'] = kept
                    write_reactions(data)
            self._json(200, {'ok': True})
            return
        pid = self._photo_id()
        if pid:
            with lock:
                photos = read_photos()
                gone = [p for p in photos if p['id'] == pid]
                if gone:
                    write_photos([p for p in photos if p['id'] != pid])
                    data = read_reactions()
                    if data.pop(pid, None) is not None:
                        write_reactions(data)
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
    if not push_on:
        print('push notifications off: no pywebpush or no VAPID_PRIVATE_KEY', flush=True)
    threading.Thread(target=committer, daemon=True).start()
    threading.Thread(target=notifier, daemon=True).start()
    http.server.ThreadingHTTPServer(('127.0.0.1', PORT), H).serve_forever()
