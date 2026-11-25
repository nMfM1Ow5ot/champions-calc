#!/usr/bin/env python3
"""serve.py の表示変更 (2026-11-22 のユーザー指示) のテスト。

- 試合のログ一式がすべて送信完了したら、その試合について 1 回だけ
  「[log] battle_<キー> の試合ログをすべて送信しました」を出す
- 過去分 (対象範囲外) の送信済み取り込みでは出さない
- ダメ計ログの受け取り表示は出ない (保存はされる)

実行: python3 tests/test_battle_completion_display.py
"""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
# 自動送信は出荷状態では無効化されている (2026-11-23)。この
# スイートは保持された送信機構そのものを検証するため、明示的
# に有効化してから走らせる
serve._AUTO_UPLOAD_ENABLED = True

JST = timezone(timedelta(hours=9))
STARTED = datetime(2026, 11, 22, 8, 0, 0, tzinfo=JST).timestamp()

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def sha(b):
    return hashlib.sha256(b).hexdigest()


class FakeGH:
    def __init__(self, index_files):
        self.puts = []
        self.index = {"files": [
            {"name": n, "sha256": h, "uploaded_at": "2026-11-22T07:30:00+09:00"}
            for n, h in index_files.items()]}

    def get_file(self, path, token):
        if path == "logs_enc/index.json":
            return json.dumps(self.index).encode(), "index-sha"
        return None, None

    def put_file(self, path, data, token, msg, sha=None):
        self.puts.append(path)
        return "sha-" + path


def setup_env(tmp, index_files):
    gh = FakeGH(index_files)
    serve.LOG_DIR = tmp
    serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
    serve._log_token = lambda: "tok"
    serve._gh_get_file = gh.get_file
    serve._gh_put_file = gh.put_file
    serve._encrypt_log = lambda data: b"enc:" + data
    serve._note_prompt_waiting = False
    serve._PROCESS_STARTED_AT = STARTED
    serve._CARRIED_NOTE_KEYS = set()
    serve._STARTUP_BATTLE_KEY_CACHE = None
    return gh


def write(tmp, name, content):
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(content)


def main():
    tmp = tempfile.mkdtemp(prefix="completion_disp_")
    # 対象範囲内の新しい試合: 送信完了で 1 回だけ表示し、次の周期
    # では再表示しない
    gh = setup_env(tmp, {})
    key = "20261122_083000"
    write(tmp, f"battle_{key}_final.log", "Battle started\n".encode())
    write(tmp, f"battle_{key}_note.txt", b"")
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        serve.upload_logs_once(session_only=True)
    line = f"[log] battle_{key} の試合ログをすべて送信しました"
    check("completion line shown once when the battle is fully sent",
          buf.getvalue().count(line) == 1)
    import re as _re
    check("completion line carries the completion datetime",
          _re.search(_re.escape(line) + r"（\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}）",
                     buf.getvalue()) is not None)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        serve.upload_logs_once(session_only=True)
    check("completion line not repeated on later cycles",
          line not in buf.getvalue())

    # 対象範囲外の旧試合が目録から取り込まれても表示しない
    tmp2 = tempfile.mkdtemp(prefix="completion_disp_old_")
    old_key = "20261121_140000"
    old_files = {
        f"battle_{old_key}_final.log": "Battle started\n".encode(),
        f"battle_{old_key}_note.txt": b"",
    }
    for n, c in old_files.items():
        write(tmp2, n, c)
    with open(os.path.join(tmp2, "uploaded.json"), "w") as f:
        json.dump({n: sha(c) for n, c in old_files.items()}, f)
    setup_env(tmp2, {n: sha(c) for n, c in old_files.items()})
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        # 手動経路 (session_only=False) では対象範囲外の試合も目録
        # 取り込みの対象になる。その場合も表示は出ない
        serve.upload_logs_once(session_only=False)
    check("old battle imported silently (recorded, no line)",
          f"battle_{old_key}" not in buf.getvalue()
          and old_key in serve._load_sent_battles())

    print("---")
    if failures:
        print(f"{len(failures)} FAILURES")
        sys.exit(1)
    print("ALL PASS")


if __name__ == "__main__":
    main()
