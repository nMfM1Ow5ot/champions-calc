#!/usr/bin/env python3
"""serve.py の自動処理の対象範囲 (セッション限定) の回帰テスト。

対象の現象:
1. (2026-11-21、ユーザーのスクリーンショット報告) start_all.sh を
   起動するたびに、前回のセッション以前に終わった古い試合の備考
   プロンプトが起動直後に出続けていた → 自動プロンプトは起動後の
   試合だけを聞く。
2. (2026-11-21、ユーザーのターミナル報告) 起動時に、起動前から
   残っていた備考待ちの試合が空欄備考で自動解消され、そのまま
   送信まで始まった → 起動前から残っている試合 (滞留分) は、備考
   の解消も送信も自動では行わず、Mac 側にそのまま残す。扱うのは
   手動の --note 経路だけとする (rev 20261121_2324 の自動解消は
   この仕様で置き換え)。

検証すること:
- 自動 (session_only=True): 起動前の試合は聞かれず、備考ファイルも
  作られず、備考待ちのまま残る。起動後の試合は従来どおり聞かれる
- 手動 (session_only=False、--note 相当) は従来どおり全件聞く

実行: python3 tests/test_prompt_session.py (全て PASS で終了コード 0)
"""
import contextlib
import importlib.util
import io
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "serve", os.path.join(HERE, "..", "serve.py"))
serve = importlib.util.module_from_spec(spec)
spec.loader.exec_module(serve)
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


def write_battle(tmp, key, mtime):
    for suffix in ("_final.log", "_final_protocol.log"):
        path = os.path.join(tmp, f"battle_{key}{suffix}")
        with open(path, "w", encoding="utf-8") as f:
            f.write("Battle started between A and B!\n" if "protocol" not in suffix
                    else "|start\n")
        os.utime(path, (mtime, mtime))


def setup(tmp):
    serve.LOG_DIR = tmp
    serve.LOG_STATE_PATH = os.path.join(tmp, "uploaded.json")
    # 対象範囲は試合の開始時刻で判定されるため、プロセス起動時刻は
    # 2 試合の開始時刻の間 (14:30) に置く
    started = serve._key_started_at("20261121_143000")
    serve._PROCESS_STARTED_AT = started
    write_battle(tmp, "20261121_140000", started - 3600)  # 起動前に開始
    write_battle(tmp, "20261121_150000", started + 5)     # 起動後に開始
    return started


def test_session(tmp):
    setup(tmp)
    prompts = []

    def input_fn(prompt):
        prompts.append(prompt)
        return "新しい方の備考"

    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        n = serve.prompt_for_pending_notes(
            input_fn=input_fn, do_upload=False, session_only=True)
    check("session: only post-start battle prompted", len(prompts) == 1)
    check("session: only post-start battle submitted", n == 1)
    old_note = os.path.join(tmp, "battle_20261121_140000_note.txt")
    check("session: pre-start battle gets NO note file",
          not os.path.exists(old_note))
    check("session: no auto-submit notice",
          "空欄の備考で送信します" not in buf.getvalue())
    new_note = os.path.join(tmp, "battle_20261121_150000",
                            "battle_20261121_150000_note.txt")
    check("session: post-start note is the typed one",
          os.path.exists(new_note)
          and open(new_note, encoding="utf-8").read() == "新しい方の備考")
    pending_keys = [p["key"] for p in serve.list_pending_log_notes()]
    check("session: pre-start battle stays pending (left on the Mac)",
          pending_keys == ["20261121_140000"])


def test_manual(tmp):
    setup(tmp)
    prompts = []

    def input_fn(prompt):
        prompts.append(prompt)
        return ""

    n = serve.prompt_for_pending_notes(
        input_fn=input_fn, do_upload=False, session_only=False)
    check("manual: all battles prompted", len(prompts) == 2 and n == 2)


def main():
    import tempfile
    old_dir, old_state = serve.LOG_DIR, serve.LOG_STATE_PATH
    try:
        with tempfile.TemporaryDirectory() as tmp:
            test_session(tmp)
        with tempfile.TemporaryDirectory() as tmp:
            test_manual(tmp)
    finally:
        serve.LOG_DIR = old_dir
        serve.LOG_STATE_PATH = old_state
    if failures:
        print(f"{len(failures)} FAILURES")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
