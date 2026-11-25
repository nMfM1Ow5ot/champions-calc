#!/usr/bin/env python3
"""serve.py の UI デバッグ送信 (POST /debug_report) のテスト。

検証すること:
- debug_ui_<日時>.json は送信対象になり、備考ゲートの対象外
- POST /debug_report がボディを logs/debug_ui_<日時>.json に保存し 200 を返す
- 不正な JSON / 別パスへの POST は非 2xx を返す (UI が失敗表示にできる)

実行: python3 tests/test_debug_report.py (全て PASS で終了コード 0)
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

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


# --- 送信対象の判定 ---
check("debug_ui_*.json は送信対象",
      serve._is_upload_target("debug_ui_20261121_221500.json"))
check("debug_ui_*.jpg は送信対象でない",
      not serve._is_upload_target("debug_ui_20261121_221500.jpg"))
check("debug_ui は備考待ちの一覧に出ない",
      all("debug_ui" not in str(p)
          for p in serve.list_pending_log_notes()))

# --- 受け口 ---
tmp = tempfile.mkdtemp()
serve.LOG_DIR = tmp
server = serve.http.server.ThreadingHTTPServer(
    ("127.0.0.1", 0), serve.QuietHandler)
port = server.server_address[1]
t = threading.Thread(target=server.serve_forever, daemon=True)
t.start()
try:
    body = json.dumps({"kind": "ui-debug", "version": 1,
                       "uiState": {"note": "テスト"}}).encode()
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request("POST", "/debug_report", body,
                 {"Content-Type": "application/json"})
    resp = conn.getresponse()
    payload = json.loads(resp.read())
    check("POST /debug_report は 200", resp.status == 200)
    saved = payload.get("file", "")
    check("保存名は debug_ui_<日時>.json 形式",
          saved.startswith("debug_ui_") and saved.endswith(".json"))
    path = os.path.join(tmp, saved)
    check("ボディがそのまま保存される",
          os.path.exists(path) and open(path, "rb").read() == body)

    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request("POST", "/debug_report", b"not json",
                 {"Content-Type": "application/json"})
    resp = conn.getresponse()
    resp.read()
    check("不正な JSON は 400", resp.status == 400)

    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
    conn.request("POST", "/other", body,
                 {"Content-Type": "application/json"})
    resp = conn.getresponse()
    resp.read()
    check("別パスへの POST は 404", resp.status == 404)
finally:
    server.shutdown()

print("---")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
