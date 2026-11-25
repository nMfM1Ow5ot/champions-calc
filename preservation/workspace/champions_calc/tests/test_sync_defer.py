#!/usr/bin/env python3
"""serve.py の「対戦中は同期の反映を保留する」のテスト。

検証すること:
- 対戦中 ( _battle_in_progress() が True ) の周期では run_sync を
  回さない (UI ファイルを差し替えない)
- 対戦が終わった後の周期で run_sync が再開する
- 起動時の同期 (force) は従来どおり走る

実行: python3 tests/test_sync_defer.py (全て PASS で終了コード 0)
"""
import importlib.util
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


class StopLoop(Exception):
    pass


sync_calls = []
serve.run_sync = lambda show, force=False: sync_calls.append((show, force))
serve._maybe_repair_missing_synced_files = lambda: None
serve.upload_logs_once = lambda session_only=True: None
serve.maybe_restart_self = lambda: None
serve._record_crash = lambda where, e: None

battle_script = iter([True, True, False, False, False])
serve._battle_in_progress = lambda: next(battle_script, False)

sleep_calls = {"n": 0}
real_sleep = serve.time.sleep


def fake_sleep(sec):
    sleep_calls["n"] += 1
    if sleep_calls["n"] >= 4:
        raise StopLoop()


serve.time.sleep = fake_sleep
try:
    try:
        serve.sync_loop()
    except StopLoop:
        pass
finally:
    serve.time.sleep = real_sleep

check("起動時の同期 (force) は走る", (True, True) in sync_calls)
periodic = [c for c in sync_calls if c == (False, False)]
check("対戦中は周期同期を回さず、終了後に再開する (周期同期は 1 回だけ)",
      len(periodic) == 1)

print("---")
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
