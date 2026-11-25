#!/usr/bin/env python3
"""serve.py の「対戦中は自動送信を保留する」と「受け取り表示は
1 試合 1 回だけ」のテスト (2026-11-22 のユーザー指示)。

検証すること:
- 対戦中 ( _battle_in_progress() が True ) は、備考済みの前の試合の
  ファイルでも自動送信 (session_only=True) しない
- 対戦終了後は同じ対象が送信される
- 手動経路 (session_only=False) は対戦中でも従来どおり送る
- ダメ計ログ・推論過程ログの受け取り表示は、同じ試合への再送では
  2 回目以降出ない (保存は毎回される)

実行: python3 tests/test_upload_battle_defer.py (全て PASS で終了コード 0)
"""
import importlib.util
import io
import json
import os
import sys
import tempfile
from contextlib import redirect_stdout

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 自動送信は出荷状態では無効化されている (2026-11-23)。この
# スイートは保持された送信機構そのものを検証するため、明示的
# に有効化してから走らせる
serve._AUTO_UPLOAD_ENABLED = True

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


class FakeGH:
    def __init__(self):
        self.puts = []

    def get_file(self, path, token):
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        return "sha-" + path


tmp = tempfile.mkdtemp()
gh = FakeGH()
serve.LOG_DIR = tmp
serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
serve._log_token = lambda: "token"
serve._gh_get_file = gh.get_file
serve._gh_put_file = gh.put_file
serve._encrypt_log = lambda data: b"enc:" + data
serve._note_prompt_waiting = False
# 対象範囲は試合の開始時刻で判定されるため、プロセス起動時刻は
# 対象の試合 (07:02 開始) より前に置く
serve._PROCESS_STARTED_AT = serve._key_started_at("20261122_070000")
serve._STARTUP_BATTLE_KEY_CACHE = None

# 備考済みの前の試合 (ゲート開始後のキーなので備考があれば送れる)
KEY = "20261122_070237"
for name in (f"battle_{KEY}_final.log", f"battle_{KEY}_note.txt",
             f"battle_{KEY}_calclog.json"):
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(b"x")

in_battle = {"v": True}
serve._battle_in_progress = lambda: in_battle["v"]

serve.upload_logs_once(session_only=True)
check("対戦中は自動送信しない", gh.puts == [])

in_battle["v"] = False
serve.upload_logs_once(session_only=True)
check("対戦終了後は送信される", len(gh.puts) > 0)

# 手動経路は対戦中でも送る (別の未送信ファイルを用意する)
KEY2 = "20261122_071500"
for name in (f"battle_{KEY2}_final.log", f"battle_{KEY2}_note.txt"):
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(b"x")
gh.puts.clear()
in_battle["v"] = True
serve.upload_logs_once(session_only=False)
check("手動経路は対戦中でも送信する", len(gh.puts) > 0)

# 受け取り表示は出ない (保存は毎回行われる)
body = json.dumps({"kind": "calc-log", "version": 1,
                   "battle": "20261122_071457",
                   "entries": [{"n": 1}]}).encode()
buf = io.StringIO()
with redirect_stdout(buf):
    serve._save_calc_log(body)
    serve._save_calc_log(body)
out = buf.getvalue()
check("ダメ計ログの受け取り表示は出ない (2026-11-22 のユーザー指示)",
      out.count("ダメ計ログを受け取りました") == 0)
saved = os.path.join(tmp, "battle_20261122_071457",
                     "battle_20261122_071457_calclog.json")
check("ダメ計ログの保存はされている", os.path.exists(saved))

body = json.dumps({"kind": "inference-log", "version": 1,
                   "battle": "20261122_071457",
                   "entries": [{"n": 1}]}).encode()
buf = io.StringIO()
with redirect_stdout(buf):
    serve._save_inference_log(body)
    serve._save_inference_log(body)
out = buf.getvalue()
check("推論過程ログの受け取り表示も出ない (2026-11-22 のユーザー指示)",
      out.count("推論過程ログを受け取りました") == 0)

print("---")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
