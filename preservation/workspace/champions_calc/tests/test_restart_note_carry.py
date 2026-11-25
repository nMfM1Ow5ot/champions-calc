#!/usr/bin/env python3
"""serve.py の「備考待ち中の自己再起動の保留」と「再起動を挟んだ
備考待ちの引き継ぎ」のテスト (battle_20261122_071457 の件)。

検証すること:
- 備考プロンプトの回答待ち中は maybe_restart_self が再起動しない
- 対象範囲内に備考待ちの試合がある間も再起動しない。ただし保留が
  120 秒を超えたら、引き継ぎを付けて再起動する
- 備考待ちが無ければ従来どおり再起動し、引き継ぎ変数は残らない
- 再起動時の引き継ぎには、対象範囲内の備考待ちのゲートキーだけが入る
- 引き継がれた試合は、起動時刻より前に終わっていても自動プロンプト
  の対象に残る。引き継がれていない旧試合は従来どおり対象外
- プロンプト回答待ち中は sync_loop が同期の反映を回さない

実行: python3 tests/test_restart_note_carry.py (全て PASS で終了コード 0)
"""
import importlib.util
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
SERVE_PATH = os.path.join(HERE, "..", "serve.py")

failures = []


def check(name, cond):
    print(("PASS " if cond else "FAIL ") + name)
    if not cond:
        failures.append(name)


def load_serve(carry=None):
    if carry is None:
        os.environ.pop("CHAMPIONS_NOTE_CARRY", None)
    else:
        os.environ["CHAMPIONS_NOTE_CARRY"] = carry
    name = f"serve_test_{time.time_ns()}"
    spec = importlib.util.spec_from_file_location(name, SERVE_PATH)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


class ExecCapture:
    def __init__(self, mod):
        self.mod = mod
        self.calls = []
        self.real = mod.os.execv

    def __enter__(self):
        self.mod.os.execv = lambda *a: self.calls.append(a)
        return self

    def __exit__(self, *exc):
        self.mod.os.execv = self.real
        return False


def prime_restart(mod):
    mod.self_hash = lambda: "newhash"
    mod.START_HASH = "oldhash"
    mod._restart_note_defer_since = None
    mod._note_prompt_waiting = False


# A: プロンプト回答待ち中は再起動しない
mod = load_serve()
prime_restart(mod)
mod._note_prompt_waiting = True
mod.list_pending_log_notes = lambda: []
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
check("A prompt waiting defers restart", ex.calls == [])

# B: 対象範囲内の備考待ちがある間は再起動せず、120 秒超で引き継ぎ付き再起動
mod = load_serve()
prime_restart(mod)
# 対象範囲は試合の開始時刻で判定されるため、起動時刻は対象試合
# (07:14 開始) より前に置く
mod._PROCESS_STARTED_AT = mod._key_started_at("20261122_070000")
mod.list_pending_log_notes = lambda: [
    {"key": "20261122_071457", "mtime": time.time(),
     "opponent": "Grekraus", "kind": "final"}]
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
    check("B pending note defers restart", ex.calls == [])
    mod._restart_note_defer_since = mod.time.monotonic() - 121
    mod.maybe_restart_self()
    check("B restart proceeds after 120s", len(ex.calls) == 1)
check("B carry env set", os.environ.get("CHAMPIONS_NOTE_CARRY") == "20261122_071457")

# C: 備考待ちが無ければ従来どおり再起動し、引き継ぎは残らない
mod = load_serve()
prime_restart(mod)
mod.list_pending_log_notes = lambda: []
os.environ["CHAMPIONS_NOTE_CARRY"] = "20261122_000000"
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
check("C restart proceeds", len(ex.calls) == 1)
check("C carry env cleared", "CHAMPIONS_NOTE_CARRY" not in os.environ)

# D: 引き継ぎには対象範囲内の備考待ちだけが入る
mod = load_serve()
mod._PROCESS_STARTED_AT = mod._key_started_at("20261122_070000")
mod.list_pending_log_notes = lambda: [
    {"key": "20261122_071457", "mtime": time.time()},
    {"key": "20261121_200000", "mtime": mod._PROCESS_STARTED_AT - 1000}]
mod._set_note_carry()
check("D carry only in-scope keys",
      os.environ.get("CHAMPIONS_NOTE_CARRY") == "20261122_071457")
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)

# E: 引き継がれた試合のスコープ判定 (判定は試合の開始時刻のみ。
# ファイル時刻は見ない — 2026-11-22 の二重送信対策で変更)
mod = load_serve(carry="20261122_071457")
check("E carried old battle in scope",
      mod._in_session_scope("20261122_071457") is True)
check("E non-carried old battle out of scope",
      mod._in_session_scope("20261121_200000") is False)
check("E battle started after process in scope",
      mod._in_session_scope("20990101_000000") is True)
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)

# F: 引き継がれた試合は自動プロンプトの対象に残り、旧試合は対象外
mod = load_serve(carry="20261122_071457")
mod.list_pending_log_notes = lambda: [
    {"key": "20261121_200000", "mtime": 0.0, "opponent": "", "kind": "final"},
    {"key": "20261122_071457", "mtime": 0.0, "opponent": "Grekraus",
     "kind": "final"}]
saved = []
mod.save_log_note = lambda key, note: saved.append(key) or True
mod.prompt_for_pending_notes(input_fn=lambda prompt: "",
                             do_upload=False, session_only=True)
check("F prompt only for carried battle", saved == ["20261122_071457"])
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)


# H: 備考入力済み・未送信の試合がある間は再起動せず、300 秒超で
# 引き継ぎ付きで再起動する (battle_20261122_201011 の再現)
import tempfile
mod = load_serve()
prime_restart(mod)
mod._restart_upload_defer_since = None
mod._PROCESS_STARTED_AT = mod._key_started_at("20261122_200000")
mod.list_pending_log_notes = lambda: []
tmp_h = tempfile.mkdtemp(prefix="restart_upload_")
mod.LOG_DIR = tmp_h
with open(os.path.join(tmp_h, "battle_20261122_201011_final.log"), "w") as f:
    f.write("Battle started\n")
with open(os.path.join(tmp_h, "battle_20261122_201011_note.txt"), "w") as f:
    f.write("")
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)
check("H unsent ready battle detected",
      mod._unsent_ready_battle_keys() == ["20261122_201011"])
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
    check("H unsent battle defers restart", ex.calls == [])
    mod._restart_upload_defer_since = mod.time.monotonic() - 301
    mod.maybe_restart_self()
    check("H restart proceeds after 300s", len(ex.calls) == 1)
check("H carry includes the unsent battle",
      os.environ.get("CHAMPIONS_NOTE_CARRY") == "20261122_201011")
os.environ.pop("CHAMPIONS_NOTE_CARRY", None)

# I: 送信済みの記録に入った試合は送信待ちに数えず、再起動も進む
mod = load_serve()
prime_restart(mod)
mod._restart_upload_defer_since = None
mod._PROCESS_STARTED_AT = mod._key_started_at("20261122_200000")
mod.list_pending_log_notes = lambda: []
mod.LOG_DIR = tmp_h
with open(os.path.join(tmp_h, "sent_battles.json"), "w") as f:
    f.write('["20261122_201011"]')
check("I sent battle not counted as unsent",
      mod._unsent_ready_battle_keys() == [])
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
check("I restart proceeds when nothing unsent", len(ex.calls) == 1)


# G: プロンプト回答待ち中は sync_loop が同期を回さない
class StopLoop(Exception):
    pass


mod = load_serve()
sync_calls = []
restart_calls = []
mod.run_sync = lambda show, force=False: sync_calls.append((show, force))
mod._maybe_repair_missing_synced_files = lambda: None
mod.maybe_restart_self = lambda: restart_calls.append(1)
mod.upload_logs_once = lambda session_only=True: None
mod._record_crash = lambda where, e=None: None
mod._battle_in_progress = lambda: False
mod._note_prompt_waiting = True
sleep_n = {"n": 0}
real_sleep = mod.time.sleep


def fake_sleep(sec):
    sleep_n["n"] += 1
    if sleep_n["n"] >= 3:
        raise StopLoop()


mod.time.sleep = fake_sleep
try:
    try:
        mod.sync_loop()
    except StopLoop:
        pass
finally:
    mod.time.sleep = real_sleep
check("G startup sync ran once", sync_calls == [(True, True)])
check("G no sync while prompt waiting", len(restart_calls) == 1)

print()
if failures:
    print(f"{len(failures)} FAILURES")
    sys.exit(1)
print("ALL PASS")
