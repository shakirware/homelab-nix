import json
import os
import re
import shutil
import sys
import urllib.request

APPLY = os.environ.get("PACER_APPLY") == "1"
MOVIES_PER_RUN = int(os.environ.get("PACER_MOVIES_PER_RUN", "3"))
SEASONS_PER_RUN = int(os.environ.get("PACER_SEASONS_PER_RUN", "1"))
STATE_PATH = os.environ.get("PACER_STATE_PATH", "/var/lib/homelab-upgrade-pacer/state.json")
MAX_QUEUE = int(os.environ.get("PACER_MAX_QUEUE", "6"))
MAX_DOWNLOADS_USED = float(os.environ.get("PACER_MAX_DOWNLOADS_USED", "0.6"))
MIN_MEDIA_FREE_TIB = float(os.environ.get("PACER_MIN_MEDIA_FREE_TIB", "4"))
DOWNLOADS_PATH = os.environ.get("PACER_DOWNLOADS_PATH", "/srv/downloads")
MEDIA_PATH = os.environ.get("PACER_MEDIA_PATH", "/srv/media")

APPS = {
    "radarr": {
        "url": os.environ.get("RADARR_URL", "http://127.0.0.1:7878"),
        "source": "2160p Infuse Playback - Movies (Library)",
        "target": "2160p Infuse Playback - Movies",
    },
    "sonarr": {
        "url": os.environ.get("SONARR_URL", "http://127.0.0.1:8989"),
        "source": "2160p Infuse Playback - TV (Library)",
        "target": "2160p Infuse Playback - TV",
    },
}


def api_key(app):
    env = os.environ.get(f"{app.upper()}_API_KEY")
    if env:
        return env
    with open(f"/srv/appdata/{app}/config.xml") as f:
        return re.search(r"<ApiKey>(.*?)</ApiKey>", f.read()).group(1)


def call(app, method, path, body=None):
    cfg = APPS[app]
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f"{cfg['url']}/api/v3/{path}",
        data=data,
        method=method,
        headers={"X-Api-Key": cfg["key"], "Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        raw = r.read()
    return json.loads(raw) if raw else None


def profile_ids(app):
    names = {p["name"]: p["id"] for p in call(app, "GET", "qualityprofile")}
    cfg = APPS[app]
    for k in ("source", "target"):
        if cfg[k] not in names:
            sys.exit(f"{app}: profile not found: {cfg[k]}")
    return names[cfg["source"]], names[cfg["target"]]


def log(msg):
    print(msg, flush=True)


def queue_bytes_left(app):
    downloads, page = {}, 1
    while True:
        r = call(app, "GET", f"queue?page={page}&pageSize=200&includeUnknownMovieItems=true&includeUnknownSeriesItems=true")
        for x in r["records"]:
            downloads[x.get("downloadId") or f"id-{x['id']}"] = int(x.get("sizeleft", 0))
        if page * 200 >= r["totalRecords"]:
            return sum(downloads.values()), len(downloads)
        page += 1


def guards():
    d = shutil.disk_usage(DOWNLOADS_PATH)
    left, queued = 0, 0
    for app in APPS:
        b, n = queue_bytes_left(app)
        left += b
        queued += n
    projected = (d.used + left) / d.total
    if projected > MAX_DOWNLOADS_USED:
        return f"download disk would be {projected:.0%} used after the queue finishes (limit {MAX_DOWNLOADS_USED:.0%})"
    free = shutil.disk_usage(MEDIA_PATH).free / 2**40
    if free < MIN_MEDIA_FREE_TIB:
        return f"media disk {free:.1f} TiB free (floor {MIN_MEDIA_FREE_TIB} TiB)"
    if queued >= MAX_QUEUE:
        return f"{queued} items queued (limit {MAX_QUEUE})"
    return None


def load_state():
    try:
        with open(STATE_PATH) as f:
            return json.load(f)
    except FileNotFoundError:
        return {"seasons": []}


def save_state(state):
    tmp = STATE_PATH + ".tmp"
    with open(tmp, "w") as f:
        json.dump(state, f)
    os.replace(tmp, STATE_PATH)


def movies_to_upgrade(source):
    movies = [m for m in call("radarr", "GET", "movie") if m["qualityProfileId"] == source and m["monitored"] and m.get("hasFile")]
    ids = [m["id"] for m in movies]
    scores = {}
    for i in range(0, len(ids), 40):
        q = "&".join(f"movieId={x}" for x in ids[i:i + 40])
        for f in call("radarr", "GET", f"moviefile?{q}"):
            scores[f["movieId"]] = f.get("customFormatScore", 0)
    movies.sort(key=lambda m: scores.get(m["id"], 0))
    return movies, scores


def series_score(series_id):
    files = call("sonarr", "GET", f"episodefile?seriesId={series_id}")
    return sum(f.get("customFormatScore", 0) for f in files) / max(len(files), 1)


def seasons_with_files(series):
    return [
        x["seasonNumber"] for x in sorted(series.get("seasons", []), key=lambda x: x["seasonNumber"])
        if x.get("monitored") and x.get("statistics", {}).get("episodeFileCount")
    ]


def do_movies(mode):
    src, dst = profile_ids("radarr")
    movies, scores = movies_to_upgrade(src)
    pick = movies[:MOVIES_PER_RUN]
    log(f"[{mode}] radarr: {len(movies)} movies left on the library profile, taking {len(pick)}")
    for m in pick:
        log(f"  movie {m['title']} ({m.get('year')}) score {scores.get(m['id'], 0)}")
    if APPLY and pick:
        ids = [m["id"] for m in pick]
        call("radarr", "PUT", "movie/editor", {"movieIds": ids, "qualityProfileId": dst})
        call("radarr", "POST", "command", {"name": "MoviesSearch", "movieIds": ids})


def do_seasons(mode):
    src, dst = profile_ids("sonarr")
    all_series = {s["id"]: s for s in call("sonarr", "GET", "series")}
    state = load_state()
    pending = [p for p in state["seasons"] if p[0] in all_series and all_series[p[0]]["qualityProfileId"] == dst]
    library = [s for s in all_series.values() if s["qualityProfileId"] == src and s["monitored"] and seasons_with_files(s)]
    picks = []
    scores = None
    while len(picks) < SEASONS_PER_RUN:
        if not pending:
            if not library:
                break
            if scores is None:
                scores = {s["id"]: series_score(s["id"]) for s in library}
                library.sort(key=lambda s: scores[s["id"]])
            nxt = library.pop(0)
            log(f"  series {nxt['title']} avg score {round(scores[nxt['id']])}, moving to the upgrade profile")
            if APPLY:
                call("sonarr", "PUT", "series/editor", {"seriesIds": [nxt["id"]], "qualityProfileId": dst})
            pending = [[nxt["id"], n] for n in seasons_with_files(nxt)]
            if APPLY:
                state["seasons"] = picks + pending
                save_state(state)
            else:
                all_series[nxt["id"]] = dict(nxt, qualityProfileId=dst)
            continue
        picks.append(pending.pop(0))
    log(f"[{mode}] sonarr: {len(library)} series left on the library profile, {len(pending)} seasons pending, searching {len(picks)}")
    for sid, n in picks:
        log(f"  season {all_series[sid]['title']} S{n:02d}")
        if APPLY:
            call("sonarr", "POST", "command", {"name": "SeasonSearch", "seriesId": sid, "seasonNumber": n})
    if APPLY:
        state["seasons"] = pending
        save_state(state)


def run():
    for app in APPS:
        APPS[app]["key"] = api_key(app)
    mode = "apply" if APPLY else "dry run"
    blocked = guards()
    if blocked:
        log(f"[{mode}] skipped: {blocked}")
        return
    do_movies(mode)
    do_seasons(mode)


if __name__ == "__main__":
    run()
