#!/usr/bin/env python3
# serve.py terminal display changes (user instruction via the
# comprehensive chat, 2026-11-22):
# D1: no calc-log receipt display (saving unchanged)
# D2: no sync-deferral start notice (deferral + resume notice unchanged)
# D3: per-battle completion line when a battle's logs are all sent
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

rep("D2 sync hold notice",
    """            elif _battle_in_progress():
                if not sync_deferred:
                    sync_deferred = True
                    print("[sync] 対戦中のため、同期の反映を対戦終了まで保留します", flush=True)
""",
    """            elif _battle_in_progress():
                # 保留の開始表示は出さない (2026-11-22 のユーザー
                # 指示)。保留の動作そのものと、対戦終了時の再開表示
                # は従来どおり
                sync_deferred = True
""")

rep("D1a calc docstring",
    "    推論過程ログと同水準の検証・同型の受け取り表示にする。\n",
    "    推論過程ログと同水準の検証にする (受け取り表示は出さない)。\n")

rep("D1b calc receipt removal",
    """    # 推論過程ログと同じく、起動前に終わった試合分は保存だけして
    # 受け取り表示を出さない (起動時に過去分の処理が走っている
    # ように見せないため)。判定は対象範囲の判定 (試合の開始時刻
    # 基準) で行う
    ended_before_start = not _in_session_scope(_gate_key(battle))
    if not ended_before_start:
        _announce_receipt(("calclog", battle), "ダメ計ログ",
                          name, len(data["entries"]))
    return name
""",
    """    # ダメ計ログの受け取り表示は出さない (2026-11-22 のユーザー
    # 指示)。保存は従来どおり毎回行う
    return name
""")

rep("D3a completion line (final)",
    """            if final_known:
                sent.add(gk)
                changed = True
""",
    """            if final_known:
                sent.add(gk)
                changed = True
                _announce_battle_sent(gk)
""")

rep("D3b completion line (no final)",
    """        elif all(state.get(n) == _file_hash(os.path.join(LOG_DIR, n))
                 for n in gnames):
            sent.add(gk)
            changed = True
""",
    """        elif all(state.get(n) == _file_hash(os.path.join(LOG_DIR, n))
                 for n in gnames):
            sent.add(gk)
            changed = True
            _announce_battle_sent(gk)
""")

rep("D3c announce helper",
    """def _update_sent_battles(state, names, known):
""",
    """def _announce_battle_sent(gk):
    \"\"\"その試合のログ一式がすべて送信完了したことを 1 行で知らせる
    (2026-11-22 のユーザー指示)。送信済みの記録への取り込みが
    完了の判定で、記録された試合につき 1 回だけ出る。対象範囲外の
    試合 (過去分の取り込み) は静かに記録だけする\"\"\"
    if _in_session_scope(gk):
        print(f"[log] battle_{gk} の試合ログをすべて送信しました", flush=True)


def _update_sent_battles(state, names, known):
""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
