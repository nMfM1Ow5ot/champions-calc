#!/usr/bin/env python3
"""serve.py の送信グルーピング (salvage 変種と元の試合の統合、および
ログの無い試合のデバッグ一式) の回帰テスト。

対象の取りこぼし (2026-11-21 の監査で検出):
1. salvage で救済された試合は、ログが <元ID>_salvage のキーに、
   デバッグ一式 (preview_id を含む) が元の試合 ID のキーに分かれ、
   一式だけのグループはログが無いため備考待ちにならず、備考ゲートに
   残り続けて永遠に届かなかった。
2. reader の異常終了で salvage も効かなかった試合は、デバッグ一式
   だけが残り、同じく備考待ちにならなかった。

検証すること:
- salvage 変種と元の試合が 1 つの備考待ちとして束ねられる
- 備考が入るまでは一式すべてが保留され、入れば一式すべてが送られる
- salvage 変種のキーで保存された備考でも一式が解放される
- ログの無い一式は、最後のファイルから 10 分経てば備考待ちになり、
  新しいうちは (対戦中とみなして) ならない

実行: python3 tests/test_upload_grouping.py (全て PASS で終了コード 0)
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
# 備考ゲートと terminal 表示限定は出荷状態では無効化されている
# (2026-11-23)。このスイートは保持されたゲート機構そのものの
# 挙動を検証するため、明示的に有効化してから走らせる
serve._NOTE_GATE_ENABLED = True
serve._LIMIT_TERMINAL_OUTPUT = False

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
    serve._log_token = lambda: "token"
    serve._gh_get_file = gh.get_file
    serve._gh_put_file = gh.put_file
    serve._encrypt_log = lambda data: b"enc:" + data
    serve._note_prompt_waiting = False
    return gh


def write(tmp, name, content=b"x"):
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(content)


def test_salvage_grouping(tmp):
    gh = setup_env(tmp)
    write(tmp, "battle_20261121_140000_debug01.json", b"{}")
    write(tmp, "battle_20261121_140000_debug01.jpg", b"jpg")
    write(tmp, "battle_20261121_140000_salvage_interrupted.log",
          "Battle started between A and B!\n".encode())
    write(tmp, "battle_20261121_140000_salvage_interrupted_protocol.log",
          b"|start")
    pending = serve.list_pending_log_notes()
    check("salvage: one pending entry", len(pending) == 1)
    if pending:
        check("salvage: grouped under base key",
              pending[0]["key"] == "20261121_140000")
        check("salvage: all files in group", len(pending[0]["files"]) == 4)
        check("salvage: opponent parsed", pending[0]["opponent"] == "B")
    # 備考が無い間は一式すべて保留される
    serve._upload_logs_once_locked()
    battle_puts = [p for p in gh.puts if "battle_" in p]
    check("salvage: nothing sent before note", battle_puts == [])
    # 備考が入れば一式すべて送られる
    check("salvage: note saved",
          serve.save_log_note("20261121_140000", "メモ") is True)
    serve._upload_logs_once_locked()
    sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
    expected = {"logs_enc/battle_20261121_140000_debug01.json.enc",
                "logs_enc/battle_20261121_140000_debug01.jpg.enc",
                "logs_enc/battle_20261121_140000_salvage_interrupted.log.enc",
                "logs_enc/battle_20261121_140000_salvage_interrupted_protocol.log.enc"}
    check("salvage: all files sent after note", expected <= sent)


def test_note_under_salvage_key_releases(tmp):
    setup_env(tmp)
    write(tmp, "battle_20261121_140000_debug01.json", b"{}")
    write(tmp, "battle_20261121_140000_salvage_interrupted.log",
          "Battle started between A and B!\n".encode())
    check("salvage-note: note saved under salvage key",
          serve.save_log_note("20261121_140000_salvage", "") is True)
    check("salvage-note: no longer pending",
          serve.list_pending_log_notes() == [])
    gh = FakeGH()
    serve._gh_put_file = gh.put_file
    serve._upload_logs_once_locked()
    sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
    check("salvage-note: bundle released", len(sent) == 2)


def test_bundle_only_stale(tmp):
    setup_env(tmp)
    write(tmp, "battle_20261121_150000_debug01.json", b"{}")
    # 新しいうちは備考待ちにならない (対戦中の試合の一式)
    check("orphan: fresh bundle not pending",
          serve.list_pending_log_notes() == [])
    # 10 分経てば備考待ちになる
    old = time.time() - 700
    os.utime(os.path.join(tmp, "battle_20261121_150000_debug01.json"),
             (old, old))
    pending = serve.list_pending_log_notes()
    check("orphan: stale bundle pending", len(pending) == 1
          and pending[0]["key"] == "20261121_150000")


def test_final_supersedes_draft(tmp):
    # 安全網の下書き (interrupted) と確定版 (final) が両方ある試合では、
    # 下書きは送らない (実例: 2026-11-21 battle_20261121_234913、
    # ヘッダーのみの下書きが「対戦本体が記録されていない試合」に見えた)
    gh = setup_env(tmp)
    write(tmp, "battle_20261121_234913_interrupted.log",
          "Battle started between A and B!\n".encode())
    write(tmp, "battle_20261121_234913_interrupted_protocol.log", b"|start")
    write(tmp, "battle_20261121_234913_final.log",
          "Battle started between A and B!\nTurn 1\n".encode())
    write(tmp, "battle_20261121_234913_final_protocol.log",
          b"|start\n|turn|1")
    check("draft: note saved",
          serve.save_log_note("20261121_234913", "") is True)
    serve._upload_logs_once_locked()
    sent = {p for p in gh.puts if p.startswith("logs_enc/battle_")}
    check("draft: final sent",
          "logs_enc/battle_20261121_234913_final.log.enc" in sent
          and "logs_enc/battle_20261121_234913_final_protocol.log.enc" in sent)
    check("draft: interrupted not sent",
          not any("_interrupted" in p for p in sent))


def main():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        test_salvage_grouping(d)
    with tempfile.TemporaryDirectory() as d:
        test_note_under_salvage_key_releases(d)
    with tempfile.TemporaryDirectory() as d:
        test_bundle_only_stale(d)
    with tempfile.TemporaryDirectory() as d:
        test_final_supersedes_draft(d)
    if failures:
        print(f"{len(failures)} FAILURES")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
