#!/usr/bin/env python3
"""serve.py の送信完了表示 (2026-11-21 のユーザー指示) の回帰テスト。

検証すること:
- 1 試合分の一式を送り切ったら「[log] 送信が完了しました」が出る
- 備考待ちの試合が残っている場合は、完了表示ではなく
  「送信できる分は完了しました (備考の入力待ちが N 件あります)」が出る
- 何も送っていないサイクルでは何も出ない
- 試合と無関係なファイル (クラッシュ記録) だけの送信では出ない

実行: python3 tests/test_upload_completion.py (全て PASS で終了コード 0)
"""
import contextlib
import importlib.util
import io
import os
import sys

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
    serve._log_token = lambda: "tok"
    serve._gh_get_file = gh.get_file
    serve._gh_put_file = gh.put_file
    serve._encrypt_log = lambda data: b"enc:" + data
    serve._note_prompt_waiting = False
    serve._log_hold_notice_keys = set()
    serve._log_last_error = ""
    return gh


def write(tmp, name, content=b"x"):
    with open(os.path.join(tmp, name), "wb") as f:
        f.write(content)


def run_upload():
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        serve.upload_logs_once()
    return buf.getvalue()


def test_full_drain(tmp):
    setup_env(tmp)
    write(tmp, "battle_20261121_170000_final.log",
          "Battle started between A and B!\n".encode())
    write(tmp, "battle_20261121_170000_final_protocol.log", b"|start")
    write(tmp, "battle_20261121_170000_debug01.json", b"{}")
    write(tmp, "battle_20261121_170000_note.txt", "メモ".encode())
    out = run_upload()
    check("drain: completion shown", "[log] 送信が完了しました" in out)
    check("drain: no partial message", "送信できる分は完了しました" not in out)
    # 何も送らないサイクルでは出ない
    out2 = run_upload()
    check("drain: silent when nothing sent",
          "送信が完了しました" not in out2 and "送信できる分" not in out2)


def test_partial_with_held(tmp):
    setup_env(tmp)
    write(tmp, "battle_20261121_170000_final.log",
          "Battle started between A and B!\n".encode())
    write(tmp, "battle_20261121_170000_note.txt", "".encode())
    write(tmp, "battle_20261121_180000_final.log",
          "Battle started between A and C!\n".encode())
    out = run_upload()
    check("partial: partial message shown",
          "送信できる分は完了しました" in out and "1 件" in out)
    check("partial: no plain completion", "[log] 送信が完了しました" not in out)
    # この表示自体は備考の空欄処理の契機ではない (2026-11-21 の
    # ユーザー訂正)。備考待ちの試合に備考ファイルは作られない
    check("partial: completion line does not submit notes",
          not os.path.exists(
              os.path.join(tmp, "battle_20261121_180000_note.txt")))


def test_backlog_out_of_scope(tmp):
    # 自動送信 (session_only) では、起動前から残っている備考待ち
    # (滞留分) は件数に数えない (2026-11-21 のユーザー指示: 起動時に
    # 過去分を処理しない。完了表示にも入力待ちとして出さない)。
    # 対象範囲は試合の開始時刻で判定する (ファイル時刻は見ない)
    setup_env(tmp)
    old_start = serve._PROCESS_STARTED_AT
    serve._PROCESS_STARTED_AT = serve._key_started_at("20261121_173000")
    try:
        # 起動後に始まった試合 (備考あり) は送られる
        write(tmp, "battle_20261121_180000_final.log",
              "Battle started between A and C!\n".encode())
        write(tmp, "battle_20261121_180000_note.txt", "".encode())
        # 起動前に始まった試合 (備考待ち) は、ファイルが新しくても
        # 滞留分として件数に数えない
        write(tmp, "battle_20261121_170000_final.log",
              "Battle started between A and B!\n".encode())
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            serve.upload_logs_once(session_only=True)
        out = buf.getvalue()
        check("backlog: plain completion in auto mode",
              "[log] 送信が完了しました" in out)
        check("backlog: no partial message in auto mode",
              "送信できる分は完了しました" not in out)
        check("backlog: held battle untouched",
              serve.list_pending_log_notes() != [])
    finally:
        serve._PROCESS_STARTED_AT = old_start


def test_journal_only(tmp):
    gh = setup_env(tmp)
    write(tmp, "serve_crashes.log", b"crash record")
    out = run_upload()
    check("journal: uploaded",
          any("serve_crashes" in p for p in gh.puts))
    check("journal: no completion message",
          "送信が完了しました" not in out and "送信できる分" not in out)


def main():
    import tempfile
    for fn in (test_full_drain, test_partial_with_held,
               test_backlog_out_of_scope, test_journal_only):
        with tempfile.TemporaryDirectory() as tmp:
            fn(tmp)
    print("FAILURES:", failures if failures else "none")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
