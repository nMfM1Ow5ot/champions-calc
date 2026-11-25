#!/usr/bin/env python3
# tests/test_restart_note_carry.py: scenarios H/I for the
# upload-wait restart deferral (battle_20261122_201011).
import sys

PATH = "/home/hatch/workspace/champions_calc/tests/test_restart_note_carry.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
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
    f.write('{"20261122_201011": "2026-11-22T20:12:00+09:00"}')
check("I sent battle not counted as unsent",
      mod._unsent_ready_battle_keys() == [])
with ExecCapture(mod) as ex:
    mod.maybe_restart_self()
check("I restart proceeds when nothing unsent", len(ex.calls) == 1)
'''

anchor = """# G: プロンプト回答待ち中は sync_loop が同期を回さない"""
if src.count(anchor) != 1:
    print("ABORT: anchor count", src.count(anchor))
    sys.exit(1)
src = src.replace(anchor, TESTS.strip() + "\n\n\n" + anchor, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: H/I scenarios")
