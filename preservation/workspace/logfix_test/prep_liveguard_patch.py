#!/usr/bin/env python3
# serve.py + its tests: the missing-file self-repair must only run
# in a live server process. On 2026-11-22 the sync-loop tests ran
# sync_loop with run_sync stubbed but the repair live, and the
# repair overwrote other chats' unpushed edits in the shared dev
# workspace with the published versions (twice, ~19:47 and ~19:52,
# plus a matching incident at ~08:20).
#  - serve.py: _LIVE_SERVER flag, set only in main() before the
#    sync thread starts; _repair_missing_synced_files returns []
#    unless the flag is set.
#  - tests/test_missing_repair.py: opts in explicitly.
#  - tests/test_sync_defer.py / test_restart_note_carry.py: stub
#    the repair alongside run_sync (defense in depth).
import sys

def patch(path, pairs):
    src = open(path, encoding="utf-8").read()
    for name, old, new in pairs:
        c = src.count(old)
        if c != 1:
            print(f"ABORT: {path} {name}: anchor count = {c}")
            sys.exit(1)
        src = src.replace(old, new, 1)
        print(f"OK: {path} {name}")
    open(path, "w", encoding="utf-8").write(src)

BASE = "/home/hatch/workspace/champions_calc/"

patch(BASE + "serve.py", [
    ("flag decl",
     """_SYNC_BASE = os.path.dirname(SELF_PATH)
_last_missing_repair_at = -1e9""",
     """_SYNC_BASE = os.path.dirname(SELF_PATH)
_last_missing_repair_at = -1e9
# 自己修復は、実際にサーバーとして起動したプロセスでのみ動く
# (main() が同期スレッドを始める前に立てる)。テスト等がモジュール
# を読み込んで sync_loop を回しても、共有ワークスペースの未 push
# 変更を公開済みの内容で上書きしないためのガード (2026-11-22 に
# テスト実行中の自己修復が他チャットの未 push 変更を 2 回消した)
_LIVE_SERVER = False"""),
    ("repair guard",
     """def _repair_missing_synced_files():
    \"\"\"公開マニフェストにあってローカルで不足しているファイルを補う。""",
     """def _repair_missing_synced_files():
    \"\"\"公開マニフェストにあってローカルで不足しているファイルを補う。
    実サーバーとして起動したプロセス以外では何もしない。"""),
    ("thread start sets flag",
     """    threading.Thread(target=sync_loop, daemon=True).start()""",
     """    global _LIVE_SERVER
    _LIVE_SERVER = True
    threading.Thread(target=sync_loop, daemon=True).start()"""),
])

# the guard check itself, inserted at the top of the repair body:
src = open(BASE + "serve.py", encoding="utf-8").read()
anchor = '''    実サーバーとして起動したプロセス以外では何もしない。'''
idx = src.index(anchor)
# find the end of the docstring (the closing triple quote after the anchor)
end = src.index('"""', idx + len(anchor)) + 3
src = src[:end] + "\n    if not _LIVE_SERVER:\n        return []" + src[end:]
open(BASE + "serve.py", "w", encoding="utf-8").write(src)
print("OK: guard check inserted")

patch(BASE + "tests/test_missing_repair.py", [
    ("opt in",
     """serve._SYNC_BASE = tmp""",
     """serve._SYNC_BASE = tmp
serve._LIVE_SERVER = True"""),
])

patch(BASE + "tests/test_sync_defer.py", [
    ("stub repair",
     """serve.run_sync = lambda show, force=False: sync_calls.append((show, force))""",
     """serve.run_sync = lambda show, force=False: sync_calls.append((show, force))
serve._maybe_repair_missing_synced_files = lambda: None"""),
])

patch(BASE + "tests/test_restart_note_carry.py", [
    ("stub repair",
     """mod.run_sync = lambda show, force=False: sync_calls.append((show, force))""",
     """mod.run_sync = lambda show, force=False: sync_calls.append((show, force))
mod._maybe_repair_missing_synced_files = lambda: None"""),
])
print("ALL EDITS APPLIED")
