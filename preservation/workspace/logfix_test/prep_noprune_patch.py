#!/usr/bin/env python3
# serve.py: remove the automatic debug-bundle pruning feature
# (user instruction via the comprehensive chat: the user deletes
# old debug bundles manually; files must simply remain).
import re
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

# 1. Header comment describing the retention rule
rep("header comment",
    """# デバッグ同梱は保持ルールで掃除する: 送信から 30 日超、または総数
# _DEBUG_KEEP_MAX 件超の古いものから目録と実体を削除する
# (ログ本体は削除対象にしない)。
""",
    """# デバッグ同梱の自動削除はしない (2026-11-22 のユーザー指示:
# 古いデバッグ情報の削除はユーザーが手動で行う)。
""")

# 2. The prune-date global
rep("global decl",
    """_log_prune_done_date = None
""",
    "")

# 3. The constant + the whole prune function
start = src.index("# デバッグ同梱の総数保持上限")
end_marker = "_upload_battle_deferred = False"
end = src.index(end_marker)
removed_block = src[start:end]
if "_prune_debug_entries" not in removed_block or "_DEBUG_KEEP_MAX" not in removed_block:
    print("ABORT: prune block sanity")
    sys.exit(1)
src = src[:start] + src[end:]
print("OK: prune function removed")

# 4. global statement in the upload cycle
rep("global stmt",
    """    global _log_notice_shown, _log_last_error, _log_prune_done_date""",
    """    global _log_notice_shown, _log_last_error""")

# 5. prune_due computation + early-return condition
rep("prune_due",
    """    # デバッグ同梱の掃除は 1 日 1 回まで (送信が無い日でもその回だけ目録を見る)
    prune_due = _log_prune_done_date != datetime.now(JST).date()
    # 前回までのサイクルでファイル自体は送れたのに目録への反映が
    # 失敗した分は、未送信分として扱い、目録の修復だけを行う
    index_pending = [n for n in _load_index_pending() if n in names]
    if not pending and not prune_due and not index_pending:
        return""",
    """    # 前回までのサイクルでファイル自体は送れたのに目録への反映が
    # 失敗した分は、未送信分として扱い、目録の修復だけを行う
    index_pending = [n for n in _load_index_pending() if n in names]
    if not pending and not index_pending:
        return""")

# 6. The prune call inside the cycle
rep("prune call",
    """        if prune_due or changed_index:
            if _prune_debug_entries(index, token):
                changed_index = True
            _log_prune_done_date = datetime.now(JST).date()
        if changed_index:""",
    """        if changed_index:""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
