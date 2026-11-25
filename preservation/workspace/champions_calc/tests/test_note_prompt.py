#!/usr/bin/env python3
"""備考プロンプト (serve.py) の回帰テスト。

対象の事故: 2026-11-21 battle_20261121_145658。対戦中にターミナルへ
打たれた「a」がカーネルの入力バッファに残り、試合終了直後の備考
プロンプトがそれを取り込んで、備考「a」で勝手に送信された。

検証すること:
1. プロンプト表示前にバッファへ残っていた行 (タイプアヘッド) は
   消費されず、表示後に入力された行が採用される (pty で実機構を検証)
2. 表示から不自然に早く返った行は 1 回だけ破棄され、聞き直される
3. EOF では例外になり、備考ファイルは作られない
4. 通常経路では入力した備考がそのまま保存される

実行: python3 tests/test_note_prompt.py (全て PASS で終了コード 0)
"""
import importlib.util
import io
import os
import pty
import sys
import threading
import time

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


class FakeIn:
    """readline が即座にキューを返す疑似ストリーム (端末ではない)。"""

    def __init__(self, lines):
        self.lines = list(lines)

    def readline(self):
        return self.lines.pop(0) if self.lines else ""


def test_typeahead_pty():
    master, slave = pty.openpty()
    in_stream = os.fdopen(slave, "r")
    out_stream = io.StringIO()
    # 対戦中に打たれた想定のタイプアヘッドを先にバッファへ入れる
    os.write(master, b"a\n")
    time.sleep(0.1)  # バッファへ届くのを待つ

    def writer():
        time.sleep(0.7)  # プロンプト表示後にユーザーが打った想定
        os.write(master, "real note\n".encode())

    result = {}

    def run():
        result["value"] = serve._prompt_input(in_stream, out_stream, "備考: ")

    t = threading.Thread(target=run, daemon=True)
    w = threading.Thread(target=writer, daemon=True)
    t.start()
    w.start()
    t.join(timeout=10)
    check("typeahead: prompt returns", "value" in result)
    check("typeahead: buffered line not consumed",
          result.get("value") == "real note")
    in_stream.close()
    os.close(master)


def test_fast_line_reasked():
    fake = FakeIn(["fast\n", "second\n"])
    out = io.StringIO()
    value = serve._prompt_input(fake, out, "備考: ")
    check("fast line: discarded once and re-asked", value == "second")
    check("fast line: both lines consumed", fake.lines == [])


def test_eof_no_note(tmp_path):
    fake = FakeIn([])
    try:
        serve._prompt_input(fake, io.StringIO(), "備考: ")
        check("eof: raises EOFError", False)
    except EOFError:
        check("eof: raises EOFError", True)

    # EOF のときに備考ファイルが作られないこと (呼び出し側まで通して確認)
    old_log_dir = serve.LOG_DIR
    old_list = serve.list_pending_log_notes
    serve.LOG_DIR = tmp_path
    serve.list_pending_log_notes = lambda: [
        {"key": "20261121_120000", "opponent": "Test", "kind": "final"}]
    try:
        def raising_input(prompt):
            raise EOFError("closed")

        try:
            serve.prompt_for_pending_notes(input_fn=raising_input,
                                           do_upload=False)
            check("eof: propagates from prompt_for_pending_notes", False)
        except EOFError:
            check("eof: propagates from prompt_for_pending_notes", True)
        check("eof: no note file created",
              not os.path.exists(
                  os.path.join(tmp_path, "battle_20261121_120000",
                  "battle_20261121_120000_note.txt")))
    finally:
        serve.LOG_DIR = old_log_dir
        serve.list_pending_log_notes = old_list


def test_normal_save(tmp_path):
    old_log_dir = serve.LOG_DIR
    old_list = serve.list_pending_log_notes
    serve.LOG_DIR = tmp_path
    serve.list_pending_log_notes = lambda: [
        {"key": "20261121_120000", "opponent": "Test", "kind": "final"}]
    try:
        count = serve.prompt_for_pending_notes(
            input_fn=lambda prompt: "テスト備考", do_upload=False)
        path = os.path.join(tmp_path, "battle_20261121_120000",
                  "battle_20261121_120000_note.txt")
        check("normal: one note saved", count == 1 and os.path.exists(path))
        with open(path, encoding="utf-8") as f:
            check("normal: content matches", f.read() == "テスト備考")
    finally:
        serve.LOG_DIR = old_log_dir
        serve.list_pending_log_notes = old_list


def test_timeout_no_input():
    old = serve._NOTE_PROMPT_TIMEOUT_SEC
    serve._NOTE_PROMPT_TIMEOUT_SEC = 1.5
    master, slave = pty.openpty()
    in_stream = os.fdopen(slave, "r")
    try:
        started = time.monotonic()
        value = serve._prompt_input(in_stream, io.StringIO(), "備考: ")
        elapsed = time.monotonic() - started
        check("timeout: returns empty string", value == "")
        check("timeout: waited about the limit", 1.4 <= elapsed < 5)
    finally:
        serve._NOTE_PROMPT_TIMEOUT_SEC = old
        in_stream.close()
        os.close(master)


def test_timeout_input_in_time():
    old = serve._NOTE_PROMPT_TIMEOUT_SEC
    serve._NOTE_PROMPT_TIMEOUT_SEC = 5.0
    master, slave = pty.openpty()
    in_stream = os.fdopen(slave, "r")

    def writer():
        time.sleep(0.8)
        os.write(master, "間に合った\n".encode())

    w = threading.Thread(target=writer, daemon=True)
    try:
        w.start()
        value = serve._prompt_input(in_stream, io.StringIO(), "備考: ")
        check("timeout: input in time is used", value == "間に合った")
    finally:
        serve._NOTE_PROMPT_TIMEOUT_SEC = old
        in_stream.close()
        os.close(master)


def test_timeout_empty_note_saved(tmp_path):
    old_timeout = serve._NOTE_PROMPT_TIMEOUT_SEC
    old_log_dir = serve.LOG_DIR
    old_list = serve.list_pending_log_notes
    serve._NOTE_PROMPT_TIMEOUT_SEC = 1.5
    serve.LOG_DIR = tmp_path
    serve.list_pending_log_notes = lambda: [
        {"key": "20261121_120000", "opponent": "Test", "kind": "final"}]
    master, slave = pty.openpty()
    in_stream = os.fdopen(slave, "r")
    try:
        count = serve.prompt_for_pending_notes(
            input_fn=lambda prompt: serve._prompt_input(
                in_stream, io.StringIO(), prompt),
            do_upload=False)
        path = os.path.join(tmp_path, "battle_20261121_120000",
                  "battle_20261121_120000_note.txt")
        check("timeout: empty note saved as submitted", count == 1
              and os.path.exists(path))
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                check("timeout: note content is empty", f.read() == "")
    finally:
        serve._NOTE_PROMPT_TIMEOUT_SEC = old_timeout
        serve.LOG_DIR = old_log_dir
        serve.list_pending_log_notes = old_list
        in_stream.close()
        os.close(master)


def test_interrupt_detector_unit():
    real = io.StringIO()
    proxy = serve._InterruptDetectStdout(real)
    serve._prompt_interrupted = False
    serve._prompt_owner_thread = None
    proxy.write("[log] 何か\n")
    check("interrupt unit: no owner, no flag",
          serve._prompt_interrupted is False)
    serve._prompt_owner_thread = -999  # 別スレッドが表示中という想定
    proxy.write("[log] 送信しました\n")
    check("interrupt unit: other-thread output sets the flag",
          serve._prompt_interrupted is True)
    serve._prompt_interrupted = False
    proxy.write("   \n")
    check("interrupt unit: whitespace only does not set the flag",
          serve._prompt_interrupted is False)
    serve._prompt_owner_thread = threading.get_ident()
    proxy.write("[log] 自分の出力\n")
    check("interrupt unit: owner output does not set the flag",
          serve._prompt_interrupted is False)
    serve._prompt_owner_thread = None
    check("interrupt unit: writes pass through",
          "送信しました" in real.getvalue())


def test_interrupt_voids_input():
    master, slave = pty.openpty()
    in_stream = os.fdopen(slave, "r")
    out_stream = io.StringIO()
    proxy = serve._InterruptDetectStdout(io.StringIO())
    result = {}

    def run():
        result["value"] = serve._prompt_input(in_stream, out_stream, "備考: ")

    def interrupter():
        time.sleep(0.6)  # プロンプト表示後に別処理の出力が割り込む
        proxy.write("[log] 試合ログを送信しました: x\n")
        time.sleep(0.3)  # その後ユーザーが Enter した想定
        os.write(master, "打ちかけた備考\n".encode())

    t = threading.Thread(target=run, daemon=True)
    w = threading.Thread(target=interrupter, daemon=True)
    t.start()
    w.start()
    t.join(timeout=10)
    check("interrupt: prompt returns", "value" in result)
    check("interrupt: input is voided to empty",
          result.get("value") == "")
    in_stream.close()
    os.close(master)


def main():
    import tempfile
    test_typeahead_pty()
    test_fast_line_reasked()
    test_interrupt_detector_unit()
    test_interrupt_voids_input()
    test_timeout_no_input()
    test_timeout_input_in_time()
    with tempfile.TemporaryDirectory() as d:
        test_timeout_empty_note_saved(d)
    with tempfile.TemporaryDirectory() as d:
        test_eof_no_note(d)
    with tempfile.TemporaryDirectory() as d:
        test_normal_save(d)
    if failures:
        print(f"{len(failures)} FAILURES")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
