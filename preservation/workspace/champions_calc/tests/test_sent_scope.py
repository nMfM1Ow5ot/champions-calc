#!/usr/bin/env python3
"""serve.py の二重送信対策 (送信済みの永続記録 + 開始時刻基準の対象判定)。

対象の事故 (2026-11-22、ユーザーのターミナル報告): start_all.sh を
再実行した直後、試合が始まっていないのに、前回までに通常経路で
到着済みの battle_20261122_071457 のファイルが再び送信された。
経過: 起動時に salvage ログが再保存され (ファイル時刻が新しく
なった)、残っていた UI が同試合のダメ計ログを再送し (内容が変化
した)、対象範囲の判定がファイル時刻基準だったため「起動後に
終わった試合」に化けて、ダメ計ログ・推論過程ログ・クラッシュ
記録が二重送信された。

対策の検証:
- 送信済みの試合は、ファイルの再到着・salvage の再保存・再起動が
  あっても、自動・手動を問わず二度と送信されない (送信済みの
  永続記録 sent_battles.json と、リポジトリ目録からの取り込み)
- 自動送信の対象判定はファイル時刻ではなく試合の開始時刻で行う
  (起動前に終わった試合は、起動後にファイルが届いても対象外)
- serve_crashes.log は、正当に送信対象の試合が無い周期には
  単独で送られない
- 手動経路 (--note 相当、session_only=False) では、未送信の
  滞留分は従来どおり送れる

実行: python3 tests/test_sent_scope.py (全て PASS で終了コード 0)
"""
import hashlib
import importlib.util
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


def battle_puts(gh):
    return {p for p in gh.puts if p.startswith("logs_enc/battle_")}


def scenario_incident(tmp):
    # 事故の再現: 071457 は前回までに通常経路で到着済み (目録と
    # ローカルの送信済み記録に全ファイルがある)。再起動後に
    # salvage が再保存され、UI がダメ計ログを再送 (内容が変化) し、
    # クラッシュ記録も変化した。それでも何も送信されない
    key = "20261122_071457"
    files = {
        f"battle_{key}_final.log": "Battle started\n".encode(),
        f"battle_{key}_final_protocol.log": b"|start\n",
        f"battle_{key}_salvage_final.log": "Battle started\n".encode(),
        f"battle_{key}_note.txt": b"",
        f"battle_{key}_calclog.json": b'{"entries": [1]}',
        f"battle_{key}_inference.json": b'{"entries": [1]}',
        "serve_crashes.log": b"crash v1",
    }
    for n, c in files.items():
        write(tmp, n, c)
    state = {n: sha(c) for n, c in files.items()}
    with open(os.path.join(tmp, "uploaded.json"), "w") as f:
        json.dump(state, f)
    gh = setup_env(tmp, {n: sha(c) for n, c in files.items()})
    # 起動後の到着: salvage の再保存 (同じ内容・新しい時刻) と、
    # ダメ計ログの再送 (蓄積が増えた = 内容が変化)、クラッシュ追記
    write(tmp, f"battle_{key}_salvage_final.log", files[f"battle_{key}_salvage_final.log"])
    write(tmp, f"battle_{key}_calclog.json", b'{"entries": [1, 2, 3]}')
    write(tmp, "serve_crashes.log", b"crash v1\ncrash v2")
    serve.upload_logs_once(session_only=True)
    check("incident: nothing sent automatically", battle_puts(gh) == set()
          and not any("serve_crashes" in p for p in gh.puts))
    check("incident: battle recorded as sent",
          "20261122_071457" in serve._load_sent_battles())
    gh.puts.clear()
    serve.upload_logs_once(session_only=False)
    check("incident: nothing sent manually either", battle_puts(gh) == set())


def scenario_new_battle(tmp):
    # 起動後に始まった試合は従来どおり送られ、送信後は記録され、
    # 後からのファイル変化でも再送されない
    gh = setup_env(tmp, {})
    key = "20261122_083000"
    write(tmp, f"battle_{key}_final.log", "Battle started\n".encode())
    write(tmp, f"battle_{key}_note.txt", b"")
    serve.upload_logs_once(session_only=True)
    check("new battle: sent", battle_puts(gh) != set())
    check("new battle: recorded as sent",
          key in serve._load_sent_battles())
    gh.puts.clear()
    write(tmp, f"battle_{key}_calclog.json", b'{"entries": [1, 2]}')
    serve.upload_logs_once(session_only=True)
    check("new battle: late file not re-sent", battle_puts(gh) == set())


def scenario_manual_backlog(tmp):
    # 未送信の滞留分は自動では送られず、手動では送れる (従来どおり)。
    # 送られた後は手動でも再送されない
    gh = setup_env(tmp, {})
    key = "20261121_200000"
    write(tmp, f"battle_{key}_final.log", "Battle started\n".encode())
    write(tmp, f"battle_{key}_note.txt", b"")
    serve.upload_logs_once(session_only=True)
    check("backlog: not sent automatically", battle_puts(gh) == set())
    serve.upload_logs_once(session_only=False)
    check("backlog: sent manually", battle_puts(gh) != set())
    check("backlog: recorded as sent", key in serve._load_sent_battles())
    gh.puts.clear()
    write(tmp, f"battle_{key}_inference.json", b'{"entries": [9]}')
    serve.upload_logs_once(session_only=False)
    check("backlog: changed file not re-sent manually",
          battle_puts(gh) == set())


def scenario_interrupted_only(tmp):
    # 確定ログの無い試合 (中断のみ) も、全部送られたら記録され、
    # 後からの変化では再送されない
    gh = setup_env(tmp, {})
    key = "20261122_084500"
    write(tmp, f"battle_{key}_interrupted.log", "Battle started\n".encode())
    write(tmp, f"battle_{key}_note.txt", b"")
    serve.upload_logs_once(session_only=True)
    check("interrupted: sent", battle_puts(gh) != set())
    check("interrupted: recorded as sent",
          key in serve._load_sent_battles())
    gh.puts.clear()
    write(tmp, f"battle_{key}_debug01.json", b"{}")
    serve.upload_logs_once(session_only=True)
    check("interrupted: late debug not re-sent", battle_puts(gh) == set())


def main():
    old = (serve._PROCESS_STARTED_AT, serve._CARRIED_NOTE_KEYS,
           serve._STARTUP_BATTLE_KEY_CACHE)
    try:
        with tempfile.TemporaryDirectory() as tmp:
            scenario_incident(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_new_battle(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_manual_backlog(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_interrupted_only(tmp)
    finally:
        (serve._PROCESS_STARTED_AT, serve._CARRIED_NOTE_KEYS,
         serve._STARTUP_BATTLE_KEY_CACHE) = old
    print("FAILURES:", failures if failures else "none")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
