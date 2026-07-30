"""Refresh the weather data behind the spain2026.miker.be live dashboard.

Reads the site list the content deploy leaves at data/sites.json, then writes
data/forecast.json and data/metar.json beside it. Runs on a timer so the page
stays a plain file_server: no CORS problem for aviationweather, no per-visitor
load on Open-Meteo, and the last good data survives an upstream outage.
"""
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
FORECAST_DAYS = 16
TIMEOUT = 90


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


def fetch_forecast(sites):
    """Hourly cloud for every site, quantised to bytes to keep the file small."""
    hours, rows = None, {}
    for i in range(0, len(sites), CHUNK):
        part = sites[i:i + CHUNK]
        q = urllib.parse.urlencode({
            "latitude": ",".join(f"{s['lat']:.4f}" for s in part),
            "longitude": ",".join(f"{s['lon']:.4f}" for s in part),
            "hourly": "cloud_cover,cloud_cover_low,cloud_cover_mid,cloud_cover_high",
            "forecast_days": FORECAST_DAYS,
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
                print(f"  {s['id']}: time axis mismatch, skipped", file=sys.stderr)
                continue
            rows[s["id"]] = {
                k[len("cloud_cover"):].lstrip("_") or "total":
                    [(-1 if v is None else int(v)) for v in h[k]]
                for k in ("cloud_cover", "cloud_cover_low",
                          "cloud_cover_mid", "cloud_cover_high")
            }
        time.sleep(1.0)
    return {"hours": hours, "sites": rows}


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


def main():
    with open(os.path.join(DATA, "sites.json")) as fh:
        cfg = json.load(fh)
    sites, airports = cfg["sites"], cfg["airports"]
    print(f"{len(sites)} sites, {len(airports)} aerodromes")

    started = time.time()
    ok = {"forecast": False, "metar": False}

    try:
        fc = fetch_forecast(sites)
        if fc["hours"]:
            fc["fetched_at"] = int(started)
            n = write_atomic("forecast.json", fc)
            ok["forecast"] = True
            print(f"  forecast.json {n // 1024} kB, {len(fc['sites'])} sites, "
                  f"{len(fc['hours'])} hours")
    except Exception as e:
        print(f"  forecast failed, keeping previous: {e}", file=sys.stderr)

    try:
        mt = fetch_metar([a["icao"] for a in airports])
        if mt:
            n = write_atomic("metar.json", {"fetched_at": int(time.time()),
                                            "stations": mt})
            ok["metar"] = True
            print(f"  metar.json {n // 1024} kB, {len(mt)} stations")
    except Exception as e:
        print(f"  metar failed, keeping previous: {e}", file=sys.stderr)

    write_atomic("updated.json", {
        "fetched_at": int(time.time()),
        "took_s": round(time.time() - started, 1),
        "forecast_ok": ok["forecast"],
        "metar_ok": ok["metar"],
    })
    # A partial refresh still leaves usable data on disk, so only fail the unit
    # when nothing at all came back.
    if not any(ok.values()):
        sys.exit(1)


if __name__ == "__main__":
    main()
