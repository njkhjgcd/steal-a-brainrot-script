#!/usr/bin/env python3
"""
Steal a Brainrot - Auto Finder backend (stdlib only, no dependencies).

How it works:
- Every player running the finder script scans their own Roblox server.
- When they see a good brainrot, the script reports it here:
    GET /report?placeId=..&jobId=..&name=..&rarity=..&income=..&price=..
- Every other player's script polls:
    GET /list   -> JSON of live finds (max 180 seconds old)
- Clicking Join in the script teleports the player to that jobId.

Listings live in memory only and expire after TTL seconds, so a
restart clears everything (no stale/fake finds survive).
"""
import json
import time
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
import os

PORT = int(os.environ.get("FINDER_PORT", "8765"))
TTL = 180  # seconds a find stays listed
MAX_LISTINGS = 200

_lock = threading.Lock()
_listings = {}  # key (jobId, name.lower()) -> dict


def cleanup(now):
    dead = [k for k, v in _listings.items() if now - v["ts"] > TTL]
    for k in dead:
        del _listings[k]


def add_listing(data):
    now = time.time()
    name = str(data.get("name", "")).strip()[:60]
    job_id = str(data.get("jobId", "")).strip()[:80]
    place_id = str(data.get("placeId", "")).strip()[:20]
    if not name or not job_id or not place_id:
        return False
    try:
        income = float(data.get("income", 0) or 0)
    except (TypeError, ValueError):
        income = 0
    try:
        price = float(data.get("price", 0) or 0)
    except (TypeError, ValueError):
        price = 0
    rarity = str(data.get("rarity", "")).strip()[:30]
    reporter = str(data.get("by", "")).strip()[:30]
    with _lock:
        cleanup(now)
        _listings[(job_id, name.lower())] = {
            "name": name,
            "jobId": job_id,
            "placeId": place_id,
            "rarity": rarity,
            "income": income,
            "price": price,
            "by": reporter,
            "ts": now,
        }
        # keep only the newest MAX_LISTINGS
        if len(_listings) > MAX_LISTINGS:
            oldest = sorted(_listings.items(), key=lambda kv: kv[1]["ts"])[: len(_listings) - MAX_LISTINGS]
            for k, _ in oldest:
                del _listings[k]
    return True


def get_listings(place_id=None):
    now = time.time()
    with _lock:
        cleanup(now)
        out = []
        for v in _listings.values():
            if place_id and v["placeId"] != str(place_id):
                continue
            item = dict(v)
            item["age"] = int(now - v["ts"])
            out.append(item)
    out.sort(key=lambda x: x["income"], reverse=True)
    return out


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def _json(self, obj, code=200):
        body = json.dumps(obj).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        if u.path == "/health":
            self._json({"ok": True, "listings": len(get_listings()), "ttl": TTL})
        elif u.path == "/report":
            ok = add_listing(q)
            self._json({"ok": ok}, 200 if ok else 400)
        elif u.path == "/list":
            self._json({"ok": True, "finds": get_listings(q.get("placeId"))})
        elif u.path == "/":
            finds = get_listings()
            rows = "".join(
                f"<tr><td>{f['name']}</td><td>{f['rarity']}</td>"
                f"<td>${f['income']:,.0f}/s</td><td>{f['age']}s ago</td></tr>"
                for f in finds
            ) or "<tr><td colspan='4'>No live finds right now</td></tr>"
            html = (
                "<!doctype html><meta charset='utf-8'>"
                "<title>Brainrot Auto Finder - live finds</title>"
                "<body style='font-family:sans-serif;background:#14141c;color:#eee'>"
                "<h2>🧠 Steal a Brainrot — Auto Finder (live)</h2>"
                f"<p>{len(finds)} find(s), each listed for {TTL}s after it was seen.</p>"
                "<table border='1' cellpadding='6' style='border-collapse:collapse'>"
                "<tr><th>Brainrot</th><th>Rarity</th><th>Income</th><th>Seen</th></tr>"
                + rows + "</table></body>"
            ).encode("utf-8")
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(html)))
            self.end_headers()
            self.wfile.write(html)
        else:
            self._json({"ok": False, "error": "not found"}, 404)

    def do_POST(self):
        u = urlparse(self.path)
        if u.path == "/report":
            try:
                length = int(self.headers.get("Content-Length", 0) or 0)
                raw = self.rfile.read(length) if length else b"{}"
                data = json.loads(raw.decode("utf-8") or "{}")
            except Exception:
                data = {}
            ok = add_listing(data)
            self._json({"ok": ok}, 200 if ok else 400)
        else:
            self._json({"ok": False, "error": "not found"}, 404)


if __name__ == "__main__":
    server = ThreadingHTTPServer(("127.0.0.1", PORT), Handler)
    print(f"finder backend on 127.0.0.1:{PORT}", flush=True)
    server.serve_forever()
