#!/usr/bin/env python3
"""serve.py の _battle_in_progress() の実物テスト (2026-11-23)。

検証すること:
- state.json が新しく battle キーがあり、確定ログ (_final 系) が
  まだ無ければ対戦中 (True)
- _interrupted の下書き (表示・プロトコルとも) があっても対戦中
  のまま (battle_20261123_043809 の途中送信の再発防止)
- _final.log / _final_protocol.log があれば対戦中でない (False)
- デバッグ同梱だけでは対戦中を外さない
- state.json が古い / battle キーが無ければ対戦中でない

実行: python3 tests/test_battle_in_progress.py (全て PASS で終了コード 0)
"""
import importlib.util
import json
import os
import sys
import tempfile
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


KEY = "20261123_043809"
tmp = tempfile.mkdtemp()
log_dir = os.path.join(tmp, "logs")
os.makedirs(log_dir)
state_path = os.path.join(tmp, "state.json")
serve.LOG_DIR = log_dir
serve.STATE_JSON_PATH = state_path


def set_state(battle=KEY, age_sec=0):
    with open(state_path, "w", encoding="utf-8") as f:
        json.dump({"battle": battle}, f)
    t = time.time() - age_sec
    os.utime(state_path, (t, t))


def add_file(name):
    with open(os.path.join(log_dir, name), "w", encoding="utf-8") as f:
        f.write("x")


def clear_files():
    for n in os.listdir(log_dir):
        os.remove(os.path.join(log_dir, n))


# ログが何も無ければ対戦中
clear_files(); set_state()
check("no logs -> in progress", serve._battle_in_progress() is True)

# interrupted の下書き (表示+プロトコル) があっても対戦中
add_file(f"battle_{KEY}_interrupted.log")
add_file(f"battle_{KEY}_interrupted_protocol.log")
check("interrupted draft only -> still in progress",
      serve._battle_in_progress() is True)

# デバッグ同梱・観測ファイルが増えても対戦中のまま
add_file(f"battle_{KEY}_debug01.jpg")
add_file(f"battle_{KEY}_debug01.json")
add_file(f"battle_{KEY}_obs.jsonl")
add_file(f"battle_{KEY}_note.txt")
check("debug/obs/note do not end progress",
      serve._battle_in_progress() is True)

# 確定ログがあれば対戦中でない
add_file(f"battle_{KEY}_final.log")
check("final log -> not in progress", serve._battle_in_progress() is False)

# プロトコルの確定版だけでも対戦中でない
clear_files(); set_state()
add_file(f"battle_{KEY}_interrupted.log")
add_file(f"battle_{KEY}_final_protocol.log")
check("final protocol only -> not in progress",
      serve._battle_in_progress() is False)

# 別の試合の確定ログでは外れない
clear_files(); set_state()
add_file("battle_20261123_030000_final.log")
check("other battle's final -> still in progress",
      serve._battle_in_progress() is True)

# state.json が古ければ対戦中でない (reader が動いていない)
clear_files(); set_state(age_sec=120)
check("stale state.json -> not in progress",
      serve._battle_in_progress() is False)

# battle キーが無ければ対戦中でない
set_state(battle=None)
check("no battle key -> not in progress",
      serve._battle_in_progress() is False)

print("FAILURES:", failures if failures else "none")
sys.exit(1 if failures else 0)
