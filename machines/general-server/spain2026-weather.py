"""Refresh the weather data behind the spain2026.miker.be live dashboard.

Reads the site list the content deploy leaves at data/sites.json, then writes
data/forecast.json and data/metar.json beside it. Runs on a timer so the page
stays a plain file_server: no CORS problem for aviationweather, no per-visitor
load on Open-Meteo, and the last good data survives an upstream outage.
"""
import datetime
import json
import os
import sys
import time
import urllib.parse
import urllib.request

WEB = os.environ.get("SPAIN2026_WEB", "/var/www/spain2026.miker.be")
DATA = os.path.join(WEB, "data")
UA = "spain2026.miker.be weather refresh (mike.rosseel@gmail.com)"
CHUNK = 25            # Open-Meteo multi-location batch
TIMEOUT = 90

# Open-Meteo's free tier bills a request as
# (variables / 10) x (days / 14) x locations against 10 000 units a day, so the
# horizon is not free. Asking only as far as the day after the eclipse means the
# per-run cost falls every day, and that is what pays for the cadence below
# rising as the eclipse gets close: on the day itself a run costs a seventh of
# what it costs two weeks out.
ECLIPSE_DAY = datetime.date(2026, 8, 12)
HORIZON_END = ECLIPSE_DAY + datetime.timedelta(days=1)

# Days to the eclipse -> seconds between refreshes. The timer fires at the
# shortest of these and the script decides whether the run is due, so the
# schedule lives here rather than in a unit file.
CADENCE = ((3, 5 * 60), (7, 10 * 60), (10 ** 4, 20 * 60))
IDLE = 6 * 3600       # once the eclipse is past there is nothing to forecast
# A refused or broken fetch must not be retried at eclipse-day speed.
RETRY_AFTER_FAIL = 30 * 60


def today():
    return datetime.datetime.now(datetime.timezone.utc).date()


def forecast_days(day=None):
    """Horizon in whole days, out to the day after the eclipse."""
    return max(1, min(16, (HORIZON_END - (day or today())).days + 1))


def interval(day=None):
    """How often a refresh should happen, in seconds."""
    left = (ECLIPSE_DAY - (day or today())).days
    if left < 0:
        return IDLE
    return next(s for t, s in CADENCE if left <= t)


def grid_max_age(day=None):
    """The raster is the expensive half of a run, so it lags the site forecast."""
    return max(15 * 60, min(60 * 60, 6 * interval(day)))


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.load(r)


def write_atomic(name, payload):
    """Never leave a half-written file where the page can read it."""
    path = os.path.join(DATA, name)
    tmp = path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(payload, fh, separators=(",", ":"))
    os.replace(tmp, path)
    return os.path.getsize(path)


def fetch_grid(grid, hours, days):
    """Hourly opaque cloud on a coarse lat/lon grid, for the map raster.

    Only the worse of the low and mid layers is kept: that is what decides
    whether a 5-10 degree sun is visible, and one byte per cell per hour keeps
    the file small enough to ship to every visitor.
    """
    pts = grid["points"]
    ncell = len(pts)
    out = [None] * ncell
    for i in range(0, ncell, CHUNK):
        part = pts[i:i + CHUNK]
        q = urllib.parse.urlencode({
            "latitude": ",".join(f"{p[0]:.3f}" for p in part),
            "longitude": ",".join(f"{p[1]:.3f}" for p in part),
            "hourly": "cloud_cover_low,cloud_cover_mid",
            "forecast_days": days,
            "timezone": "UTC",
        })
        res = get("https://api.open-meteo.com/v1/forecast?" + q)
        res = res if isinstance(res, list) else [res]
        for k, d in enumerate(res):
            h = d.get("hourly") or {}
            if h.get("time") != hours:
                continue
            lo, mid = h["cloud_cover_low"], h["cloud_cover_mid"]
            out[i + k] = [
                -1 if (lo[j] is None or mid[j] is None) else max(lo[j], mid[j])
                for j in range(len(hours))
            ]
        time.sleep(1.0)
    filled = sum(1 for c in out if c)
    blank = [-1] * len(hours)
    return {"cols": len(grid["lons"]), "rows": len(grid["lats"]),
            "lons": grid["lons"], "lats": grid["lats"],
            "cells": [c if c else blank for c in out],
            "filled": filled, "n": ncell}


def fetch_forecast(sites, days, key="id"):
    """Hourly cloud for every point, quantised to bytes to keep the file small."""
    hours, rows = None, {}
    for i in range(0, len(sites), CHUNK):
        part = sites[i:i + CHUNK]
        q = urllib.parse.urlencode({
            "latitude": ",".join(f"{s['lat']:.4f}" for s in part),
            "longitude": ",".join(f"{s['lon']:.4f}" for s in part),
            "hourly": "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high",
            "forecast_days": days,
            "timezone": "UTC",
        })
        res = get("https://api.open-meteo.com/v1/forecast?" + q)
        res = res if isinstance(res, list) else [res]
        for s, d in zip(part, res):
            h = d["hourly"]
            if hours is None:
                hours = h["time"]
            elif h["time"] != hours:
                # different grid cell, different run window: skip rather than
                # silently misalign this site against the shared time axis
                print(f"  {s[key]}: time axis mismatch, skipped", file=sys.stderr)
                continue
            rows[s[key]] = {
                k[len("cloud_cover"):].lstrip("_") or "total":
                    [(-1 if v is None else int(v)) for v in h[k]]
                for k in ("cloud_cover", "cloud_cover_low",
                          "cloud_cover_mid", "cloud_cover_high")
            }
        time.sleep(1.0)
    return {"hours": hours, "sites": rows}


# Mid-totality, the instant a TAF would have to cover to be worth anything here.
TOTALITY_EPOCH = 1786559400        # 2026-08-12T18:30:00Z, mid-totality


# Cloud cover ranked by how much of the sun it takes away.
COVER_RANK = {"SKC": 0, "CLR": 0, "NSC": 0, "NCD": 0, "CAVOK": 0,
              "FEW": 1, "SCT": 2, "BKN": 3, "OVC": 4, "VV": 5, "OVX": 5}


def taf_hourly(t):
    """Flatten a TAF's change groups into one value per hour.

    A TAF is a base forecast plus FM/BECMG amendments and TEMPO/PROB variations.
    The prevailing state is the last non-temporary group covering the hour; the
    temporary groups are kept separately rather than averaged in, because
    "BKN for 40 minutes in every hour" is a different thing to fly, or watch an
    eclipse, under.
    """
    a, b = t.get("validTimeFrom"), t.get("validTimeTo")
    if not a or not b:
        return None
    a, b = int(a) // 3600 * 3600, int(b)
    hours, prev, base, tempo = [], [], [], []
    for ts in range(a, b, 3600):
        best = None, None, None      # (start, rank, base)
        temp = None
        for f in (t.get("fcsts") or []):
            fa, fb = f.get("timeFrom"), f.get("timeTo")
            if not fa or not fb or not (fa <= ts < fb):
                continue
            cl = f.get("clouds") or []
            rank, cbase = 0, None
            for c in cl:
                r = COVER_RANK.get(c.get("cover"), 0)
                if r >= rank:
                    rank, cbase = r, c.get("base")
            kind = (f.get("fcstChange") or "").upper()
            if kind.startswith("TEMPO") or kind.startswith("PROB"):
                temp = rank if temp is None else max(temp, rank)
            elif best[0] is None or fa >= best[0]:
                best = fa, rank, cbase
        hours.append(ts)
        prev.append(-1 if best[1] is None else best[1])
        base.append(best[2] if best[2] is not None else -1)
        tempo.append(-1 if temp is None else temp)
    return {"hours": hours, "cover": prev, "base": base, "tempo": tempo}


def fetch_taf(icaos):
    """Aerodrome forecasts.

    A TAF is a human-checked forecast of cloud base and amount, but it only runs
    24-30 hours ahead, so it cannot say anything about eclipse evening until
    11 August. Until then this records how far each one reaches; after that the
    period covering totality is the best worded guidance available.
    """
    out = {}
    try:
        data = get("https://aviationweather.gov/api/data/taf"
                   f"?ids={','.join(icaos)}&format=json")
    except Exception as e:
        print(f"  taf fetch failed: {e}", file=sys.stderr)
        return out
    for t in data:
        icao = t.get("icaoId")
        if not icao:
            continue
        covering = None
        for f in (t.get("fcsts") or []):
            a, b = f.get("timeFrom"), f.get("timeTo")
            if a and b and a <= TOTALITY_EPOCH < b:
                cl = [(c.get("cover"), c.get("base")) for c in (f.get("clouds") or [])]
                worst = "CLR"
                for cover, _ in cl:
                    if cover in ("BKN", "OVC", "VV"):
                        worst = "BKN/OVC"
                        break
                    if cover == "SCT":
                        worst = "SCT"
                covering = {"from": a, "to": b, "clouds": cl, "state": worst,
                            "wx": f.get("wxString")}
                break
        prev = out.get(icao)
        rec = {"issued": t.get("issueTime"), "from": t.get("validTimeFrom"),
               "to": t.get("validTimeTo"), "raw": t.get("rawTAF"),
               "totality": covering, "hourly": taf_hourly(t)}
        # keep the newest issue per station
        if not prev or (rec["issued"] or "") > (prev["issued"] or ""):
            out[icao] = rec
    return out


def fetch_metar(icaos):
    out = {}
    ids = ",".join(icaos)
    try:
        data = get("https://aviationweather.gov/api/data/metar"
                   f"?ids={ids}&format=json")
    except Exception as e:
        print(f"  metar fetch failed: {e}", file=sys.stderr)
        return out
    for m in data:
        clouds = [(c.get("cover"), c.get("base")) for c in (m.get("clouds") or [])]
        worst = "CLR"
        for cover, _ in clouds:
            if cover in ("BKN", "OVC", "VV"):
                worst = "BKN/OVC"
                break
            if cover == "SCT":
                worst = "SCT"
        out[m["icaoId"]] = {
            "obs": m.get("obsTime"),
            "raw": m.get("rawOb"),
            "temp": m.get("temp"),
            "clouds": clouds,
            "state": worst,
            "visib": m.get("visib"),
        }
    return out


def forecast_due(now):
    """Whether a forecast fetch is due, given the cadence for today.

    The timer fires at the fastest rate the schedule ever needs and this decides
    whether the run does anything, so changing the ramp does not mean touching a
    unit file. A failed fetch backs off rather than retrying at eclipse-day
    speed: a provider refusing us is not a reason to ask it 288 times a day.
    """
    try:
        with open(os.path.join(DATA, "updated.json")) as fh:
            last = json.load(fh)
    except (OSError, ValueError):
        return True, "no previous run"
    age = now - last.get("fetched_at", 0)
    if not last.get("forecast_ok"):
        if age < RETRY_AFTER_FAIL:
            return False, f"last fetch failed {age / 60:.0f} min ago, backing off"
        return True, "retrying after a failed fetch"
    want = interval()
    if age < want - 30:      # allow for timer jitter
        return False, f"last fetch {age / 60:.0f} min ago, cadence {want // 60} min"
    return True, f"cadence {want // 60} min"


def main():
    with open(os.path.join(DATA, "sites.json")) as fh:
        cfg = json.load(fh)
    sites, airports = cfg["sites"], cfg["airports"]

    started = time.time()
    days = forecast_days()
    left = (ECLIPSE_DAY - today()).days
    due, why = forecast_due(started)
    print(f"{len(sites)} sites, {len(airports)} aerodromes · {left} days to the "
          f"eclipse · horizon {days} d · {why}")
    if not due:
        return

    ok = {"forecast": False, "grid": False, "metar": False}

    try:
        fc = fetch_forecast(sites, days)
        if fc["hours"]:
            fc["fetched_at"] = int(started)
            # the aerodromes get the same treatment, for the hover charts
            try:
                fc["airports"] = fetch_forecast(airports, days, key="icao")["sites"]
            except Exception as e:
                print(f"  airport forecast failed: {e}", file=sys.stderr)
                fc["airports"] = {}
            n = write_atomic("forecast.json", fc)
            ok["forecast"] = True
            print(f"  forecast.json {n // 1024} kB, {len(fc['sites'])} sites, "
                  f"{len(fc.get('airports', {}))} aerodromes, {len(fc['hours'])} hours")
    except Exception as e:
        print(f"  forecast failed, keeping previous: {e}", file=sys.stderr)

    grid_path = os.path.join(DATA, "grid.json")
    grid_fresh = (os.path.exists(grid_path)
                  and time.time() - os.path.getmtime(grid_path) < grid_max_age())
    if grid_fresh:
        print("  grid still fresh, skipping")
    if ok["forecast"] and cfg.get("grid") and not grid_fresh:
        try:
            gr = fetch_grid(cfg["grid"], fc["hours"], days)
            gr["fetched_at"] = int(time.time())
            n = write_atomic("grid.json", gr)
            ok["grid"] = True
            print(f"  grid.json {n // 1024} kB, {gr['filled']}/{gr['n']} cells")
        except Exception as e:
            print(f"  grid failed, keeping previous: {e}", file=sys.stderr)

    try:
        icaos = [a["icao"] for a in airports]
        mt = fetch_metar(icaos)
        tf = fetch_taf(icaos)
        if mt or tf:
            n = write_atomic("metar.json", {"fetched_at": int(time.time()),
                                            "stations": mt, "taf": tf,
                                            "totality_epoch": TOTALITY_EPOCH})
            ok["metar"] = True
            cov = sum(1 for v in tf.values() if v.get("totality"))
            print(f"  metar.json {n // 1024} kB, {len(mt)} obs, {len(tf)} TAFs "
                  f"({cov} reaching totality)")
    except Exception as e:
        print(f"  metar/taf failed, keeping previous: {e}", file=sys.stderr)

    write_atomic("updated.json", {
        "fetched_at": int(time.time()),
        "took_s": round(time.time() - started, 1),
        "forecast_ok": ok["forecast"],
        "horizon_days": days,
        "next_in_s": interval(),
        "grid_ok": ok["grid"] or grid_fresh,
        "metar_ok": ok["metar"],
    })
    # A partial refresh still leaves usable data on disk, so only fail the unit
    # when nothing at all came back.
    if not any(ok.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
