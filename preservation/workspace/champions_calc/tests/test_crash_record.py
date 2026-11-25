#!/usr/bin/env python3
"""serve.py の異常記録 (クラッシュジャーナル) の回帰テスト。

対象の事故: 2026-11-21 battle_20261121_150535 の後、備考入力中に
ターミナルが異常終了し、Mac 側の送信処理が止まったが、当時の版では
記録が何も残らず原因を特定できなかった。

検証すること:
1. _record_crash がトレースバック・発生箇所・当時の状態を
   logs/serve_crashes.log へ追記する
2. ジャーナルが上限を超えたら古い分が間引かれる
3. プロンプトの読み取りで EOF 以外の入出力エラー (EIO) が起きても、
   ループが例外を外へ漏らさず、記録を残し、送信停止フラグが
   残らない
4. ジャーナルが通常の送信対象に含まれ、備考ゲートの対象外である

実行: python3 tests/test_crash_record.py (全て PASS で終了コード 0)
"""
import importlib.util
import io
import os
import sys

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


class TimeShim:
    """serve.time の sleep だけを無効化する差し替え。"""

    @staticmethod
    def sleep(_sec):
        pass

    monotonic = staticmethod(__import__("time").monotonic)


class EioIn:
    """readline が EIO を投げる疑似ストリーム (端末消失の再現)。"""

    def readline(self):
        raise OSError(5, "Input/output error")


def test_record_crash(tmp):
    old = serve.LOG_DIR
    serve.LOG_DIR = tmp
    try:
        serve._note_prompt_waiting = True
        serve._note_prompt_current_key = "20261121_120000"
        try:
            raise ValueError("boom")
        except ValueError as e:
            serve._record_crash("test_where", e)
        path = os.path.join(tmp, "serve_crashes.log")
        check("record: file created", os.path.exists(path))
        with open(path, encoding="utf-8") as f:
            text = f.read()
        check("record: where recorded", "where=test_where" in text)
        check("record: state recorded",
              "prompt_waiting=True" in text
              and "prompt_key=20261121_120000" in text)
        check("record: traceback recorded",
              "ValueError: boom" in text and "Traceback" in text)
        # 2 件目は追記される
        serve._record_crash("second")
        with open(path, encoding="utf-8") as f:
            text = f.read()
        check("record: appended", "where=second" in text
              and "where=test_where" in text)
    finally:
        serve.LOG_DIR = old
        serve._note_prompt_waiting = False
        serve._note_prompt_current_key = None


def test_trim(tmp):
    old_dir, old_max = serve.LOG_DIR, serve._CRASH_LOG_MAX
    serve.LOG_DIR = tmp
    serve._CRASH_LOG_MAX = 2000
    try:
        for i in range(30):
            try:
                raise RuntimeError(f"crash {i} " + "x" * 100)
            except RuntimeError as e:
                serve._record_crash(f"w{i}", e)
        path = os.path.join(tmp, "serve_crashes.log")
        size = os.path.getsize(path)
        check("trim: size bounded", size <= 2000)
        with open(path, encoding="utf-8") as f:
            text = f.read()
        check("trim: marker present", "間引かれました" in text)
        check("trim: latest kept", "where=w29" in text)
    finally:
        serve.LOG_DIR = old_dir
        serve._CRASH_LOG_MAX = old_max


def test_prompt_loop_survives_eio(tmp):
    old_dir = serve.LOG_DIR
    old_time = serve.time
    old_list = serve.list_pending_log_notes
    old_progress = serve._battle_in_progress
    old_open = serve._open_prompt_io
    serve.LOG_DIR = tmp
    serve.time = TimeShim
    # 試合キーはプロセス起動より後の日付にする (自動プロンプトの
    # 対象範囲は試合の開始時刻で判定されるため。対象外だと読み取り
    # 自体が起きず、ループが終了条件に到達しない)
    serve.list_pending_log_notes = lambda: [
        {"key": "20990101_120000", "opponent": "Test", "kind": "final",
         "mtime": 4102444800.0}]
    serve._battle_in_progress = lambda: False
    serve._open_prompt_io = lambda: (None, None, "")
    try:
        # 例外が外へ漏れず、ループが (開き直しを諦めて) 正常に返ること
        serve._note_prompt_loop(EioIn(), io.StringIO())
        check("eio: loop returned without raising", True)
        path = os.path.join(tmp, "serve_crashes.log")
        check("eio: crash recorded", os.path.exists(path))
        if os.path.exists(path):
            with open(path, encoding="utf-8") as f:
                text = f.read()
            check("eio: OSError in journal",
                  "OSError" in text and "where=note_prompt_loop" in text)
        check("eio: prompt waiting flag cleared",
              serve._note_prompt_waiting is False)
        check("eio: prompt key cleared",
              serve._note_prompt_current_key is None)
    finally:
        serve.LOG_DIR = old_dir
        serve.time = old_time
        serve.list_pending_log_notes = old_list
        serve._battle_in_progress = old_progress
        serve._open_prompt_io = old_open


def test_upload_inclusion():
    check("upload: crash journal is a target",
          serve._is_upload_target("serve_crashes.log") is True)
    check("upload: crash journal has no battle key (gate-exempt)",
          serve._battle_key("serve_crashes.log") is None)
    check("upload: battle logs still targets",
          serve._is_upload_target("battle_20261121_120000_final.log") is True)


def main():
    import tempfile
    with tempfile.TemporaryDirectory() as d:
        test_record_crash(d)
    with tempfile.TemporaryDirectory() as d:
        test_trim(d)
    with tempfile.TemporaryDirectory() as d:
        test_prompt_loop_survives_eio(d)
    test_upload_inclusion()
    if failures:
        print(f"{len(failures)} FAILURES")
        return 1
    print("ALL PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
