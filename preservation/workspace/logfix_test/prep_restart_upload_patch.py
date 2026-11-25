#!/usr/bin/env python3
# serve.py: the self-restart deferral must also cover the window
# between the note being entered and the battle's upload completing
# (battle_20261122_201011: the note timed out empty, the restart
# fired seconds later, and the restarted process treated the battle
# as out of session scope, so it was never sent automatically).
#  - new _unsent_ready_battle_keys(): in-scope battles whose note
#    gate is satisfied but which are not yet in the sent record.
#  - maybe_restart_self defers while any exist (300s bound), and
#  - _set_note_carry also carries those keys across the restart so
#    the battle stays in scope even if the restart does happen.
import sys

PATH = "/home/hatch/workspace/champions_calc/serve.py"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ---- 1. second defer clock ----
rep("clock decl",
    """START_HASH = self_hash()


_restart_note_defer_since = None""",
    """START_HASH = self_hash()


_restart_note_defer_since = None
_restart_upload_defer_since = None""")

# ---- 2. maybe_restart_self: upload-wait deferral ----
rep("restart body",
    """    global _restart_note_defer_since
    current = self_hash()
    if current is None or START_HASH is None or current == START_HASH:
        _restart_note_defer_since = None
        return
    if _note_blocking():
        now = time.monotonic()
        if _restart_note_defer_since is None:
            _restart_note_defer_since = now
            if not _note_prompt_waiting:
                # プロンプト表示中にこの表示を出すと割り込み出力に
                # なって入力を無効化するため、表示中は出さない
                print("[sync] 備考の入力待ちがあるため、serve.py の再起動を保留します", flush=True)
        if now - _restart_note_defer_since < 120:
            return
    _restart_note_defer_since = None
    _set_note_carry()""",
    """    global _restart_note_defer_since, _restart_upload_defer_since
    current = self_hash()
    if current is None or START_HASH is None or current == START_HASH:
        _restart_note_defer_since = None
        _restart_upload_defer_since = None
        return
    now = time.monotonic()
    if _note_blocking():
        if _restart_note_defer_since is None:
            _restart_note_defer_since = now
            if not _note_prompt_waiting:
                # プロンプト表示中にこの表示を出すと割り込み出力に
                # なって入力を無効化するため、表示中は出さない
                print("[sync] 備考の入力待ちがあるため、serve.py の再起動を保留します", flush=True)
        if now - _restart_note_defer_since < 120:
            return
    if _unsent_ready_battle_keys():
        # 備考は入力済みだが送信がまだ終わっていない試合がある間も
        # 再起動しない。送信は約 30 秒ごとの周期で行われるため、
        # 通常は 1〜2 周期で解消する。送信が失敗し続ける場合も
        # 300 秒で、引き継ぎ付きで再起動する (引き継ぎ先でも
        # 対象範囲に残り、自動送信が続く)
        if _restart_upload_defer_since is None:
            _restart_upload_defer_since = now
            if not _note_prompt_waiting:
                print("[sync] 試合ログの送信待ちがあるため、serve.py の再起動を保留します", flush=True)
        if now - _restart_upload_defer_since < 300:
            return
    _restart_note_defer_since = None
    _restart_upload_defer_since = None
    _set_note_carry()""")

# ---- 3. the unsent-ready helper, right after _note_blocking ----
rep("helper",
    """def _set_note_carry():
    \"\"\"再起動の直前に、対象範囲内の備考待ちを引き継ぎ用に控える。\"\"\"
    try:
        keys = sorted({p["key"] for p in list_pending_log_notes()
                       if _in_session_scope(p["key"])})
    except Exception:
        keys = []""",
    """def _unsent_ready_battle_keys():
    \"\"\"送信待ち (備考ゲートは解消済みだが未送信) の対象範囲内の試合。

    備考が入力された直後は _note_blocking が False に戻るため、その
    ままでは送信の周期 (約 30 秒ごと) より先に自己再起動が割り込み、
    再起動後のプロセスではその試合が対象範囲外になって自動送信
    されなくなる (実例: 2026-11-22 battle_20261122_201011、備考の
    30 秒無入力確定の直後に再起動が入り、ログが通常ルートで
    送られなかった)。送信完了までの間は再起動を保留し、やむを得ず
    再起動する場合も引き継ぎの対象にする。\"\"\"
    try:
        if not os.path.isdir(LOG_DIR):
            return []
        groups = {}
        for name in sorted(os.listdir(LOG_DIR)):
            if not _is_upload_target(name):
                continue
            bk = _battle_key(name)
            if bk is None:
                continue
            groups.setdefault(_gate_key(bk), []).append(name)
        sent = _load_sent_battles()
        ready = []
        for gk, names in groups.items():
            if gk in sent or not _in_session_scope(gk):
                continue
            if _note_gate_applies(gk):
                noted = _note_exists(gk) or any(
                    _note_exists(_battle_key(n) or "") for n in names)
                if not noted:
                    continue   # 備考待ちは _note_blocking 側の担当
            ready.append(gk)
        return sorted(ready)
    except Exception:
        return []


def _set_note_carry():
    \"\"\"再起動の直前に、対象範囲内の備考待ちと送信待ちを引き継ぎ用に控える。\"\"\"
    try:
        keys = sorted({p["key"] for p in list_pending_log_notes()
                       if _in_session_scope(p["key"])}
                      | set(_unsent_ready_battle_keys()))
    except Exception:
        keys = []""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
