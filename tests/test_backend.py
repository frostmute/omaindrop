"""Backend tests against a fake Raindrop API.

Run:  python3 -m unittest discover -s tests -v
Spins up a local HTTP server that speaks enough of Raindrop's REST v1 and
runs bin/omaindrop-backend as a subprocess against it, the same way the bar does.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKEND = os.path.join(ROOT, "bin", "omaindrop-backend")
TOKEN = "test-token-123"


def item(i, title, link, coll=-1, tags=None):
    return {"_id": i, "title": title, "link": link, "domain": urlparse(link).netloc, "excerpt": "",
            "tags": tags or [], "type": "link", "created": "2026-11-0%dT10:00:00Z" % (i % 9 + 1),
            "collection": {"$id": coll}, "highlights": [{"text": "x"}] if i == 2 else []}


class FakeRaindrop:
    def __init__(self):
        self.reset()

    def reset(self):
        self.items = {
            1: item(1, "Quickshell docs", "https://quickshell.org/docs", -1, ["omarchy", "qml"]),
            2: item(2, "Godot 4.7 notes", "https://godotengine.org/article/x", 101, ["godot"]),
            3: item(3, "Hyprland wiki", "https://wiki.hyprland.org", -1, ["hyprland"]),
        }
        self.next_id = 100
        self.requests = []
        self.fail_with = None  # (status, headers)

    def collections(self):
        return [{"_id": 101, "title": "Gamedev", "count": 1, "sort": 0},
                {"_id": 102, "title": "Linux", "count": 0, "sort": 1}]

    def children(self):
        return [{"_id": 201, "title": "Shaders", "count": 0, "parent": {"$id": 101}}]


FAKE = FakeRaindrop()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, status, payload, headers=None):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n else b""

    def _route(self, method):
        raw = self._body()
        u = urlparse(self.path)
        q = {k: v[0] for k, v in parse_qs(u.query).items()}
        path = u.path.replace("/rest/v1", "", 1)
        FAKE.requests.append({"method": method, "path": path, "query": q, "body": raw,
                              "auth": self.headers.get("Authorization"),
                              "ctype": self.headers.get("Content-Type", "")})
        if FAKE.fail_with:
            status, headers = FAKE.fail_with
            return self._send(status, {"result": False, "errorMessage": "nope"}, headers)
        if self.headers.get("Authorization") != "Bearer " + TOKEN:
            return self._send(401, {"result": False, "errorMessage": "Unauthorized"})

        if method == "GET" and path == "/user/stats":
            unsorted = sum(1 for i in FAKE.items.values() if i["collection"]["$id"] == -1)
            return self._send(200, {"result": True, "items": [
                {"_id": 0, "count": len(FAKE.items)}, {"_id": -1, "count": unsorted}, {"_id": -99, "count": 4}]})
        if method == "GET" and path == "/user":
            return self._send(200, {"result": True, "user": {"fullName": "Frost", "pro": True}})
        if method == "GET" and path.startswith("/raindrops/"):
            cid = int(path.rsplit("/", 1)[1])
            rows = [i for i in FAKE.items.values() if cid == 0 or i["collection"]["$id"] == cid]
            s = q.get("search", "").lower()
            if s:
                rows = [i for i in rows if s in i["title"].lower() or s in " ".join(i["tags"])]
            rows.sort(key=lambda i: i["created"], reverse=True)
            per = int(q.get("perpage", 25))
            return self._send(200, {"result": True, "items": rows[:per], "count": len(rows)})
        if method == "GET" and path == "/collections":
            return self._send(200, {"result": True, "items": FAKE.collections()})
        if method == "GET" and path == "/collections/childrens":
            return self._send(200, {"result": True, "items": FAKE.children()})
        if method == "GET" and path.startswith("/tags"):
            counts = {}
            for i in FAKE.items.values():
                for t in i["tags"]:
                    counts[t] = counts.get(t, 0) + 1
            counts["omarchy"] = counts.get("omarchy", 0) + 5
            return self._send(200, {"result": True, "items": [{"_id": k, "count": v} for k, v in counts.items()]})
        if method == "POST" and path == "/raindrop":
            data = json.loads(raw)
            FAKE.next_id += 1
            it = item(FAKE.next_id, data.get("title") or "Parsed title", data["link"], data["collection"]["$id"], data.get("tags"))
            FAKE.items[it["_id"]] = it
            return self._send(200, {"result": True, "item": it})
        if method == "PUT" and path == "/raindrop/file":
            FAKE.next_id += 1
            it = item(FAKE.next_id, "upload.png", "https://up.raindrop.io/x.png", -1)
            it["type"] = "image"
            FAKE.items[it["_id"]] = it
            return self._send(200, {"result": True, "item": it})
        if method in ("PUT", "GET", "DELETE") and path.startswith("/raindrop/"):
            rid = int(path.rsplit("/", 1)[1])
            if rid not in FAKE.items:
                return self._send(404, {"result": False, "errorMessage": "Not found"})
            if method == "GET":
                return self._send(200, {"result": True, "item": FAKE.items[rid]})
            if method == "DELETE":
                FAKE.items[rid]["collection"] = {"$id": -99}
                return self._send(200, {"result": True})
            data = json.loads(raw)
            it = FAKE.items[rid]
            if "collection" in data:
                it["collection"] = data["collection"]
            if "tags" in data:
                it["tags"] = data["tags"]
            if "title" in data:
                it["title"] = data["title"]
            return self._send(200, {"result": True, "item": it})
        return self._send(404, {"result": False, "errorMessage": "no route " + path})

    def do_GET(self):
        self._route("GET")

    def do_POST(self):
        self._route("POST")

    def do_PUT(self):
        self._route("PUT")

    def do_DELETE(self):
        self._route("DELETE")


class BackendTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        cls.port = cls.server.server_address[1]
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def setUp(self):
        FAKE.reset()
        self.home = tempfile.mkdtemp(prefix="omaindrop-test-")
        self.bin = os.path.join(self.home, "bin")
        os.makedirs(self.bin)
        os.makedirs(os.path.join(self.home, ".config", "raindrop"))
        with open(os.path.join(self.home, ".config", "raindrop", "token"), "w") as fh:
            fh.write(TOKEN + "\n")

    def tearDown(self):
        shutil.rmtree(self.home, ignore_errors=True)

    def env(self, **extra):
        e = {"HOME": self.home, "PATH": self.bin + os.pathsep + "/usr/bin:/bin",
             "OMAINDROP_API_BASE": "http://127.0.0.1:%d/rest/v1" % self.port, "OMAINDROP_TIMEOUT": "5"}
        e.update(extra)
        return e

    def run_backend(self, *args, input_text=None, **env):
        res = subprocess.run([sys.executable, BACKEND] + list(args), capture_output=True, text=True,
                             input=input_text, timeout=30, env=self.env(**env))
        self.assertEqual(res.stdout.count("\n"), 1, "exactly one JSON line: %r %r" % (res.stdout, res.stderr))
        data = json.loads(res.stdout)
        self.assertEqual(res.returncode, 0 if data.get("ok") else 1)
        return data

    def fake_bin(self, name, script):
        path = os.path.join(self.bin, name)
        with open(path, "w") as fh:
            fh.write("#!/bin/sh\n" + script + "\n")
        os.chmod(path, 0o755)
        return path

    # --- reads

    def test_count(self):
        d = self.run_backend("count")
        self.assertTrue(d["ok"])
        self.assertEqual(d["counts"], {"all": 3, "unsorted": 2, "trash": 4})
        self.assertFalse(d["stale"])
        self.assertEqual(FAKE.requests[-1]["auth"], "Bearer " + TOKEN)

    def test_count_falls_back_to_cache_when_offline(self):
        self.run_backend("count")
        d = self.run_backend("count", OMAINDROP_API_BASE="http://127.0.0.1:9/rest/v1")
        self.assertTrue(d["ok"])
        self.assertTrue(d["stale"])
        self.assertEqual(d["counts"]["unsorted"], 2)

    def test_offline_without_cache_is_an_error(self):
        d = self.run_backend("count", OMAINDROP_API_BASE="http://127.0.0.1:9/rest/v1")
        self.assertFalse(d["ok"])
        self.assertEqual(d["code"], "offline")

    def test_recent_defaults_to_unsorted(self):
        d = self.run_backend("recent", "--limit", "10")
        self.assertTrue(d["ok"])
        self.assertEqual(d["collection"], -1)
        self.assertEqual([i["id"] for i in d["items"]], [3, 1])
        self.assertEqual(FAKE.requests[-1]["path"], "/raindrops/-1")
        self.assertEqual(FAKE.requests[-1]["query"]["sort"], "-created")
        first = d["items"][1]
        self.assertEqual(first["domain"], "quickshell.org")
        self.assertEqual(first["tags"], ["omarchy", "qml"])

    def test_recent_limit_is_clamped_to_api_max(self):
        self.run_backend("recent", "--collection", "0", "--limit", "500")
        self.assertEqual(FAKE.requests[-1]["query"]["perpage"], "50")

    def test_search(self):
        d = self.run_backend("search", "godot")
        self.assertTrue(d["ok"])
        self.assertEqual(d["total"], 1)
        self.assertEqual(d["items"][0]["highlights"], 1)
        self.assertEqual(FAKE.requests[-1]["path"], "/raindrops/0")
        self.assertEqual(FAKE.requests[-1]["query"]["search"], "godot")

    def test_search_requires_query(self):
        d = self.run_backend("search", " ")
        self.assertFalse(d["ok"])
        self.assertEqual(d["code"], "bad_input")

    def test_collections_nested_with_system_entries(self):
        d = self.run_backend("collections")
        self.assertTrue(d["ok"])
        self.assertEqual([c["id"] for c in d["system"]], [-1, 0])
        self.assertEqual(d["system"][0]["count"], 2)
        self.assertEqual([(c["id"], c["depth"]) for c in d["collections"]], [(101, 0), (201, 1), (102, 0)])
        self.assertEqual(d["collections"][1]["path"], "Gamedev / Shaders")

    def test_tags_sorted_by_use(self):
        d = self.run_backend("tags", "--limit", "2")
        self.assertEqual([t["name"] for t in d["tags"]], ["omarchy", "godot"])

    # --- writes

    def test_save_explicit_url(self):
        d = self.run_backend("save", "https://example.com/a", "--collection", "101", "--tags", "omarchy, #qml,omarchy")
        self.assertTrue(d["ok"])
        body = json.loads(FAKE.requests[-1]["body"])
        self.assertEqual(body["link"], "https://example.com/a")
        self.assertEqual(body["collection"], {"$id": 101})
        self.assertEqual(body["tags"], ["omarchy", "qml"])
        self.assertEqual(body["pleaseParse"], {})
        self.assertEqual(d["item"]["collectionId"], 101)

    def test_save_bare_domain_gets_https(self):
        self.run_backend("save", "raindrop.io")
        self.assertEqual(json.loads(FAKE.requests[-1]["body"])["link"], "https://raindrop.io")

    def test_save_defaults_to_clipboard_and_unsorted(self):
        self.fake_bin("wl-paste", "printf 'https://clip.example/x some trailing words'")
        d = self.run_backend("save")
        self.assertTrue(d["ok"])
        body = json.loads(FAKE.requests[-1]["body"])
        self.assertEqual(body["link"], "https://clip.example/x")
        self.assertEqual(body["collection"], {"$id": -1})

    def test_save_uses_configured_default_collection(self):
        os.makedirs(os.path.join(self.home, ".config", "omaindrop"))
        with open(os.path.join(self.home, ".config", "omaindrop", "config.json"), "w") as fh:
            json.dump({"defaultCollection": 102}, fh)
        self.run_backend("save", "https://example.com")
        self.assertEqual(json.loads(FAKE.requests[-1]["body"])["collection"], {"$id": 102})

    def test_save_rejects_non_links(self):
        for bad in ("not a link", "javascript:alert(1)", "file:///etc/passwd"):
            d = self.run_backend("save", bad)
            self.assertFalse(d["ok"], bad)
            self.assertEqual(d["code"], "bad_input")
        self.assertFalse([r for r in FAKE.requests if r["method"] == "POST"])

    def test_clipboard_command(self):
        self.fake_bin("wl-paste", "printf 'https://a.example'")
        d = self.run_backend("clipboard")
        self.assertEqual(d["url"], "https://a.example")
        self.fake_bin("wl-paste", "printf 'hello'")
        self.assertEqual(self.run_backend("clipboard")["url"], "")

    def test_screenshot_from_file_uploads_multipart_then_tags(self):
        png = os.path.join(self.home, "shot.png")
        with open(png, "wb") as fh:
            fh.write(b"\x89PNG\r\n\x1a\nfake")
        d = self.run_backend("screenshot", "--file", png, "--tags", "shots", "--title", "Bar mockup", "--collection", "101")
        self.assertTrue(d["ok"], d)
        upload = [r for r in FAKE.requests if r["path"] == "/raindrop/file"][0]
        self.assertTrue(upload["ctype"].startswith("multipart/form-data; boundary="))
        self.assertIn(b'name="collectionId"\r\n\r\n101', upload["body"])
        self.assertIn(b'filename="shot.png"', upload["body"])
        self.assertIn(b"Content-Type: image/png", upload["body"])
        patch = json.loads(FAKE.requests[-1]["body"])
        self.assertEqual(patch, {"tags": ["shots"], "title": "Bar mockup"})
        self.assertTrue(os.path.exists(png), "never delete a file the user handed us")

    def test_screenshot_capture_uses_grim_and_slurp(self):
        self.fake_bin("slurp", "echo '10,10 200x100'")
        self.fake_bin("grim", 'for last; do :; done; printf "\\211PNG" > "$last"')
        d = self.run_backend("screenshot")
        self.assertTrue(d["ok"], d)
        self.assertTrue([r for r in FAKE.requests if r["path"] == "/raindrop/file"])

    def test_screenshot_cancelled(self):
        self.fake_bin("slurp", "exit 1")
        self.fake_bin("grim", "exit 0")
        d = self.run_backend("screenshot")
        self.assertFalse(d["ok"])
        self.assertEqual(d["code"], "cancelled")

    def test_move_tag_delete(self):
        self.assertTrue(self.run_backend("move", "1", "102")["ok"])
        self.assertEqual(FAKE.items[1]["collection"], {"$id": 102})
        self.assertTrue(self.run_backend("tag", "1", "new", "--append")["ok"])
        self.assertEqual(FAKE.items[1]["tags"], ["omarchy", "qml", "new"])
        self.assertTrue(self.run_backend("delete", "3")["ok"])
        self.assertEqual(FAKE.items[3]["collection"], {"$id": -99})
        d = self.run_backend("delete", "999")
        self.assertEqual(d["code"], "not_found")

    # --- errors and auth

    def test_no_token(self):
        os.remove(os.path.join(self.home, ".config", "raindrop", "token"))
        d = self.run_backend("count")
        self.assertFalse(d["ok"])
        self.assertEqual(d["code"], "no_token")
        self.assertFalse(FAKE.requests)

    def test_bad_token(self):
        d = self.run_backend("count", RAINDROP_TOKEN="wrong")
        self.assertEqual(d["code"], "unauthorized")

    def test_rate_limited_reports_retry(self):
        import time
        FAKE.fail_with = (429, {"X-RateLimit-Reset": str(int(time.time()) + 30)})
        d = self.run_backend("recent")
        self.assertEqual(d["code"], "rate_limited")
        self.assertTrue(20 <= d["retryAfter"] <= 31)

    def test_unknown_command_and_bad_args(self):
        self.assertEqual(self.run_backend("frobnicate")["code"], "bad_input")
        self.assertEqual(self.run_backend("move", "abc")["code"], "bad_input")
        self.assertEqual(self.run_backend()["code"], "bad_input")

    def test_token_precedence(self):
        os.makedirs(os.path.join(self.home, ".config", "omaindrop"))
        with open(os.path.join(self.home, ".config", "omaindrop", "config.json"), "w") as fh:
            json.dump({"token": "from-config"}, fh)
        d = self.run_backend("status")
        self.assertEqual(d["tokenSource"], "config")
        d = self.run_backend("status", RAINDROP_TOKEN="from-env")
        self.assertEqual(d["tokenSource"], "env:RAINDROP_TOKEN")

    def test_set_token_verifies_and_writes_private_file(self):
        os.remove(os.path.join(self.home, ".config", "raindrop", "token"))
        self.assertEqual(self.run_backend("set-token", input_text="wrong\n")["code"], "unauthorized")
        d = self.run_backend("set-token", input_text=TOKEN + "\n")
        self.assertTrue(d["ok"])
        path = os.path.join(self.home, ".config", "raindrop", "token")
        self.assertEqual(oct(os.stat(path).st_mode & 0o777), "0o600")
        self.assertTrue(self.run_backend("status", "--check")["user"]["pro"])

    def test_set_token_does_not_reuse_readable_temporary_file(self):
        path = os.path.join(self.home, ".config", "raindrop", "token")
        with open(path + ".tmp", "w") as fh:
            fh.write("existing data")
        os.chmod(path + ".tmp", 0o644)
        result = subprocess.run([sys.executable, BACKEND, "set-token", "--no-check"],
                                input=TOKEN + "\n", capture_output=True, text=True, env=self.env())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(os.stat(path).st_mode & 0o777, 0o600)
        with open(path + ".tmp") as fh:
            self.assertEqual(fh.read(), "existing data")

    # --- make it rain

    def make_vault(self, name, advanced_uri=False, token=None, enabled=True):
        vault = os.path.join(self.home, "vaults", name)
        plug = os.path.join(vault, ".obsidian", "plugins")
        os.makedirs(os.path.join(plug, "make-it-rain"))
        with open(os.path.join(plug, "make-it-rain", "manifest.json"), "w") as fh:
            json.dump({"id": "make-it-rain", "version": "2.1.5"}, fh)
        if token:
            with open(os.path.join(plug, "make-it-rain", "data.json"), "w") as fh:
                json.dump({"apiToken": token}, fh)
        if advanced_uri:
            os.makedirs(os.path.join(plug, "obsidian-advanced-uri"))
            with open(os.path.join(plug, "obsidian-advanced-uri", "manifest.json"), "w") as fh:
                json.dump({"id": "obsidian-advanced-uri"}, fh)
        with open(os.path.join(vault, ".obsidian", "community-plugins.json"), "w") as fh:
            json.dump(["make-it-rain"] if enabled else [], fh)
        cfg_dir = os.path.join(self.home, ".config", "obsidian")
        os.makedirs(cfg_dir, exist_ok=True)
        cfg = os.path.join(cfg_dir, "obsidian.json")
        data = {"vaults": {}}
        if os.path.exists(cfg):
            with open(cfg) as fh:
                data = json.load(fh)
        data["vaults"][name] = {"path": vault, "ts": 1, "open": name == "Brain"}
        with open(cfg, "w") as fh:
            json.dump(data, fh)
        return vault

    def test_vault_hidden_without_make_it_rain(self):
        d = self.run_backend("vault")
        self.assertFalse(d["available"])
        self.assertEqual(self.run_backend("pull")["code"], "not_available")

    def test_pull_with_advanced_uri_fires_command(self):
        self.make_vault("Notes")
        self.make_vault("Brain", advanced_uri=True)
        d = self.run_backend("vault")
        self.assertTrue(d["available"])
        self.assertEqual(d["vault"]["name"], "Brain")  # the open vault wins
        d = self.run_backend("pull", "--dry-run")
        self.assertEqual(d["mode"], "command")
        self.assertEqual(d["uri"], "obsidian://adv-uri?vault=Brain&commandid=make-it-rain%3Afetch-raindrops")

    def test_pull_without_advanced_uri_opens_vault(self):
        self.make_vault("My Vault")
        log = os.path.join(self.home, "opened")
        self.fake_bin("xdg-open", 'echo "$1" > %s' % log)
        d = self.run_backend("pull")
        self.assertTrue(d["ok"])
        self.assertEqual(d["mode"], "open-vault")
        self.assertEqual(d["uri"], "obsidian://open?vault=My%20Vault")
        import time
        for _ in range(50):
            if os.path.exists(log):
                break
            time.sleep(0.05)
        with open(log) as fh:
            self.assertEqual(fh.read().strip(), "obsidian://open?vault=My%20Vault")

    def test_token_from_make_it_rain(self):
        os.remove(os.path.join(self.home, ".config", "raindrop", "token"))
        self.make_vault("Brain", token=TOKEN)
        d = self.run_backend("count")
        self.assertTrue(d["ok"])
        self.assertEqual(self.run_backend("status")["tokenSource"], "make-it-rain:Brain")

    def test_copy(self):
        log = os.path.join(self.home, "copied")
        self.fake_bin("wl-copy", "cat > %s" % log)
        self.assertTrue(self.run_backend("copy", "https://x.example")["ok"])
        with open(log) as fh:
            self.assertEqual(fh.read(), "https://x.example")

    def test_open_refuses_non_web(self):
        self.assertEqual(self.run_backend("open", "file:///etc/passwd")["code"], "bad_input")


if __name__ == "__main__":
    unittest.main()
