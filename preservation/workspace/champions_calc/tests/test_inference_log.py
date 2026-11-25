#!/usr/bin/env python3
"""serve.py の推論過程ログ (POST /inference_log) のテスト。

検証すること:
- battle_<キー>_inference.json は送信対象になり、その試合のキーに
  束ねられる (備考ゲートの対象: 備考ファイルが無ければ備考待ちに
  なり、あれば待ちにならない)
- POST /inference_log がボディを battle_<キー>_inference.json に
  保存し 200 を返す (再送は上書き)
- 不正な試合キー / entries なし / 不正な JSON / 別パスは非 2xx

実行: python3 tests/test_inference_log.py (全て PASS で終了コード 0)
"""
import http.client
import importlib.util
import json
import os
import sys
import tempfile
import threading

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 備考ゲートは出荷状態では無効化されている (2026-11-23)。この
# スイートは備考待ちを含む従来の送信経路を検証するため、明示的
# に有効化してから走らせる
serve._NOTE_GATE_ENABLED = True

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


KEY = "20261121_224409"
NAME = f"battle_{KEY}_inference.json"

# --- 送信対象とキーの束ね ---
check("inference.json は送信対象", serve._is_upload_target(NAME))
check("試合キーに束ねられる", serve._battle_key(NAME) == KEY)
check("salvage キーにも束ねられる",
      serve._battle_key(f"battle_{KEY}_salvage_inference.json")
      == f"{KEY}_salvage")
check("関係ない json は送信対象でない",
      not serve._is_upload_target("battle_20261121_224409_notes.json"))

# --- 備考ゲート (その試合の一式として扱われる) ---
tmp = tempfile.mkdtemp()
serve.LOG_DIR = tmp
with open(os.path.join(tmp, f"battle_{KEY}_final.log"), "w") as f:
    f.write("Turn 1\n")
with open(os.path.join(tmp, NAME), "w") as f:
    f.write("{}")
state_path = os.path.join(tmp, "uploaded.json")
with open(state_path, "w") as f:
    json.dump({}, f)
old_state_file = getattr(serve, "_UPLOAD_STATE_FILE", None)
serve._UPLOAD_STATE_FILE = state_path
try:
    pending = serve.list_pending_log_notes()
    check("備考が無ければ備考待ちに含まれる",
          any(p["key"] == KEY for p in pending))
    with open(os.path.join(tmp, f"battle_{KEY}_note.txt"), "w") as f:
        f.write("")
    pending = serve.list_pending_log_notes()
    check("備考があれば備考待ちに含まれない",
          all(p["key"] != KEY for p in pending))
finally:
    if old_state_file is not None:
        serve._UPLOAD_STATE_FILE = old_state_file

# --- 受け口 ---
server = serve.http.server.ThreadingHTTPServer(
    ("127.0.0.1", 0), serve.QuietHandler)
port = server.server_address[1]
t = threading.Thread(target=server.serve_forever, daemon=True)
t.start()
try:
    def post(path, body):
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request("POST", path, body,
                     {"Content-Type": "application/json"})
        resp = conn.getresponse()
        data = resp.read()
        return resp.status, data

    body = json.dumps({"kind": "inference-log", "version": 1,
                       "battle": KEY,
                       "entries": [{"seq": 1}, {"seq": 2}]}).encode()
    status, data = post("/inference_log", body)
    payload = json.loads(data)
    check("POST /inference_log は 200", status == 200)
    check("保存名は battle_<キー>_inference.json",
          payload.get("file") == NAME)
    path = os.path.join(tmp, f"battle_{KEY}", NAME)
    check("ボディがそのまま保存される",
          os.path.exists(path) and open(path, "rb").read() == body)

    body2 = json.dumps({"kind": "inference-log", "version": 1,
                        "battle": KEY,
                        "entries": [{"seq": 1}]}).encode()
    status, _ = post("/inference_log", body2)
    check("再送は 200 で上書きされる",
          status == 200 and open(path, "rb").read() == body2)

    status, _ = post("/inference_log",
                     json.dumps({"battle": "../etc",
                                 "entries": []}).encode())
    check("不正な試合キーは 400", status == 400)

    status, _ = post("/inference_log",
                     json.dumps({"battle": KEY}).encode())
    check("entries が無ければ 400", status == 400)

    status, _ = post("/inference_log", b"not json")
    check("不正な JSON は 400", status == 400)

    status, _ = post("/other", body)
    check("別パスへの POST は 404", status == 404)
finally:
    server.shutdown()

print("---")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
