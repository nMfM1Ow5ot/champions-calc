#!/usr/bin/env python3
"""serve.py の自動送信の対象範囲 (セッション限定) の回帰テスト。

対象の現象 (2026-11-21、ユーザーのターミナル報告): start_all.sh の
起動直後、起動前から残っていた試合のログ一式が自動送信され始めた。
ユーザー指示により、起動前から残っている試合 (滞留分) は自動送信
では扱わず、Mac 側にそのまま残す。手動経路 (session_only=False、
--note の送信など) では従来どおり送れる。

検証すること:
- 自動 (session_only=True): 起動前の試合は、備考が付いていても
  送られない。起動後の試合は送られる
- 手動 (session_only=False): 起動前の試合も送られる

実行: python3 tests/test_upload_session_scope.py (全て PASS で終了コード 0)
"""
import importlib.util
import os
import sys
import time

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


def setup_env(tmp):
    gh = FakeGH()
    serve.LOG_DIR = tmp
    serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
    serve._log_token = lambda: "tok"
    serve._gh_get_file = gh.get_file
    serve._gh_put_file = gh.put_file
    serve._encrypt_log = lambda data: b"enc:" + data
    serve._note_prompt_waiting = False
    return gh


def write(tmp, name, content, mtime):
    path = os.path.join(tmp, name)
    with open(path, "wb") as f:
        f.write(content)
    os.utime(path, (mtime, mtime))


def scenario_late_inference(tmp):
    # 起動前の試合に、起動後になって推論過程ログが遅れて届いても
    # (UI の再送)、その試合は滞留分のまま自動送信されない。試合の
    # 帰属判定はファイル時刻ではなく試合の開始時刻で行うため、
    # ログ自体が新しい時刻で再保存されても対象にはならない
    # (2026-11-22 battle_20261122_071457 の二重送信の再現)
    gh = setup_env(tmp)
    started = serve._key_started_at("20261121_143000")
    serve._PROCESS_STARTED_AT = started
    write(tmp, "battle_20261121_140000_final.log",
          "Battle started between A and B!\n".encode(), started + 30)
    write(tmp, "battle_20261121_140000_note.txt", b"", started - 3600)
    write(tmp, "battle_20261121_140000_inference.json",
          b'{"entries": []}', started + 30)
    serve.upload_logs_once(session_only=True)
    sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
    check("late-inference: pre-start battle stays backlog", sent == set())


def scenario_journal_bundle(tmp):
    # クラッシュ記録は、起動しただけでは送られない。起動後に
    # 終わった試合が送られるサイクルで同梱される
    gh = setup_env(tmp)
    started = serve._key_started_at("20261121_143000")
    serve._PROCESS_STARTED_AT = started
    write(tmp, "serve_crashes.log", b"crash record", started - 3600)
    serve.upload_logs_once(session_only=True)
    check("journal: not sent alone at startup",
          not any("serve_crashes" in p for p in gh.puts))
    write(tmp, "battle_20261121_150000_final.log",
          "Battle started between A and C!\n".encode(), started + 5)
    write(tmp, "battle_20261121_150000_note.txt", b"", started + 5)
    serve.upload_logs_once(session_only=True)
    check("journal: bundled with a session battle",
          any("serve_crashes" in p for p in gh.puts))


def scenario_receipt_display(tmp):
    # 推論過程ログは、起動前に終わった試合でも対戦中の試合でも、
    # 保存はされるが受領の表示は出ない (2026-11-22 のユーザー
    # 指示で受け取り表示そのものを停止)
    import contextlib
    import io
    import json as _json
    setup_env(tmp)
    started = serve._key_started_at("20261121_143000")
    serve._PROCESS_STARTED_AT = started
    write(tmp, "battle_20261121_140000_final.log",
          "Battle started between A and B!\n".encode(), started - 3600)
    body = _json.dumps({"kind": "inference-log", "version": 1,
                        "battle": "20261121_140000",
                        "entries": [{"seq": 1}]}).encode()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        serve._save_inference_log(body)
    check("receipt: saved silently for pre-start battle",
          "受け取りました" not in buf.getvalue()
          and os.path.exists(
              os.path.join(tmp, "battle_20261121_140000",
                           "battle_20261121_140000_inference.json")))
    body2 = _json.dumps({"kind": "inference-log", "version": 1,
                         "battle": "20261121_150000",
                         "entries": [{"seq": 1}]}).encode()
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        serve._save_inference_log(body2)
    check("receipt: not shown for in-progress battle either",
          "受け取りました" not in buf.getvalue())


def main():
    import tempfile
    old_start = serve._PROCESS_STARTED_AT
    try:
        with tempfile.TemporaryDirectory() as tmp:
            gh = setup_env(tmp)
            started = serve._key_started_at("20261121_143000")
            serve._PROCESS_STARTED_AT = started
            # 起動前の試合 (備考あり) と起動後の試合 (備考あり)
            write(tmp, "battle_20261121_140000_final.log",
                  "Battle started between A and B!\n".encode(), started - 3600)
            write(tmp, "battle_20261121_140000_note.txt", b"", started - 3600)
            write(tmp, "battle_20261121_150000_final.log",
                  "Battle started between A and C!\n".encode(), started + 5)
            write(tmp, "battle_20261121_150000_note.txt", b"", started + 5)
            serve.upload_logs_once(session_only=True)
            sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
            check("auto: post-start battle sent",
                  "logs_enc/battle_20261121_150000_final.log.enc" in sent)
            check("auto: pre-start battle NOT sent",
                  not any("140000" in p for p in sent))
            serve.upload_logs_once(session_only=False)
            sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
            check("manual: pre-start battle sent",
                  "logs_enc/battle_20261121_140000_final.log.enc" in sent)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_late_inference(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_journal_bundle(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            scenario_receipt_display(tmp)
    finally:
        serve._PROCESS_STARTED_AT = old_start
    print("FAILURES:", failures if failures else "none")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
