#!/usr/bin/env python3
"""serve.py のプリセット共有 (POST /presets) のテスト。

検証すること:
- 正しいストア JSON は 200 {"ok": true} を返し、ローカルの
  presets.json に保存され、GitHub へ PUT される (既存ファイルが
  あれば sha 付き)
- 不正な JSON / mine・opps が配列でない場合は 400、1MB 超は 413
- トークンが無い場合は 500 (ok: false) で、ローカル保存だけ行われる
- PUT が 409 (デバッグ用ページ側と競合) の場合は sha を取り直して
  1 回だけ再試行する
- presets.json はログ送信対象ではない (同期・備考ゲートの対象外)

実行: python3 tests/test_presets.py (全て PASS で終了コード 0)
"""
import http.client
import importlib.util
import json
import os
import sys
import tempfile
import threading
import urllib.error

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


check("presets.json はログ送信対象でない",
      not serve._is_upload_target("presets.json"))

# --- GitHub 側のモック ---
tmp = tempfile.mkdtemp()
serve.PRESETS_PATH = os.path.join(tmp, "presets.json")
gh = {"sha": None, "puts": [], "conflict_once": False}


def fake_get_file(path, token):
    assert path == "presets.json"
    if gh["sha"] is None:
        return None, None
    return b"{}", gh["sha"]


def fake_put_file(path, content, token, message, sha=None):
    if gh["conflict_once"]:
        gh["conflict_once"] = False
        gh["sha"] = "sha-from-pages"
        raise urllib.error.HTTPError(
            "https://api.github.com", 409, "conflict", {}, None)
    gh["puts"].append({"path": path, "content": content, "sha": sha})
    gh["sha"] = "sha-next"
    return {}


serve._log_token = lambda: "test-token"
serve._gh_get_file = fake_get_file
serve._gh_put_file = fake_put_file

server = serve.http.server.ThreadingHTTPServer(
    ("127.0.0.1", 0), serve.QuietHandler)
port = server.server_address[1]
t = threading.Thread(target=server.serve_forever, daemon=True)
t.start()


def post(path, body):
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request("POST", path, body=body,
                 headers={"Content-Type": "application/json"})
    r = conn.getresponse()
    data = r.read()
    conn.close()
    return r.status, data


STORE = json.dumps({"v": 1, "updatedAt": "2026-11-22T00:00:00Z",
                    "mine": [{"name": "A"}], "opps": []}).encode()

# 1. 初回保存: sha なしで作成される
status, data = post("/presets", STORE)
check("初回 POST は 200", status == 200)
check("初回 POST は ok:true", json.loads(data) == {"ok": True})
check("ローカルに保存された",
      open(serve.PRESETS_PATH, "rb").read() == STORE)
check("PUT は sha なし (新規作成)",
      len(gh["puts"]) == 1 and gh["puts"][0]["sha"] is None
      and gh["puts"][0]["content"] == STORE)

# 2. 2 回目: 既存 sha を付けて更新される
status, _ = post("/presets", STORE)
check("2 回目の POST は 200", status == 200)
check("PUT に既存 sha が付く",
      len(gh["puts"]) == 2 and gh["puts"][1]["sha"] == "sha-next")

# 3. 検証エラー
status, data = post("/presets", b"{not json")
check("不正な JSON は 400", status == 400 and not json.loads(data)["ok"])
status, _ = post("/presets", json.dumps({"mine": {}, "opps": []}).encode())
check("mine が配列でないと 400", status == 400)
status, _ = post("/presets", json.dumps({"mine": []}).encode())
check("opps が無いと 400", status == 400)
status, _ = post("/presets", b"x" * (1024 * 1024 + 1))
check("1MB 超は 413", status == 413)
check("検証エラーでは PUT されない", len(gh["puts"]) == 2)

# 4. トークンが無い場合: 500 だがローカル保存はされる
serve._log_token = lambda: ""
status, data = post("/presets", STORE)
check("トークンなしは 500 で ok:false",
      status == 500 and not json.loads(data)["ok"])
check("トークンなしでもローカル保存はされる",
      open(serve.PRESETS_PATH, "rb").read() == STORE)
serve._log_token = lambda: "test-token"

# 5. 409 競合: sha を取り直して再試行し 200
gh["conflict_once"] = True
before = len(gh["puts"])
status, _ = post("/presets", STORE)
check("409 競合でも再試行して 200", status == 200)
check("再試行は新しい sha で行われる",
      len(gh["puts"]) == before + 1
      and gh["puts"][-1]["sha"] == "sha-from-pages")

# 6. 別パスは従来どおり 404
status, _ = post("/presets2", STORE)
check("別パスへの POST は 404", status == 404)

server.shutdown()
print("ALL PASS" if not failures else f"{len(failures)} FAILURES")
sys.exit(0 if not failures else 1)
