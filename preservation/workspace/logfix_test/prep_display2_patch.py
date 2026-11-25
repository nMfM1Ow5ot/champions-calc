#!/usr/bin/env python3
# serve.py: also suppress the inference-log receipt display and the
# sync resume notice (user's direct instruction, 2026-11-22).
# Collection/sending behavior is unchanged.
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

rep("sync resume notice",
    """            elif _battle_in_progress():
                # 保留の開始表示は出さない (2026-11-22 のユーザー
                # 指示)。保留の動作そのものと、対戦終了時の再開表示
                # は従来どおり
                sync_deferred = True
            else:
                if sync_deferred:
                    sync_deferred = False
                    print("[sync] 対戦が終了したため、同期を再開します", flush=True)
""",
    """            elif _battle_in_progress():
                # 保留の開始表示は出さない (2026-11-22 のユーザー
                # 指示)。保留の動作そのものは従来どおり
                sync_deferred = True
            else:
                if sync_deferred:
                    # 再開表示も出さない (2026-11-22 のユーザー指示)
                    sync_deferred = False
""")

rep("receipt helper removal",
    """_receipt_printed = set()


def _announce_receipt(tag, label, name, count):
    \"\"\"受け取り表示は、同じ試合・同じ種類につきプロセス内で 1 回
    だけ出す。UI は蓄積全件を数秒おきに再送するため、毎回出すと
    対戦中のターミナルに送信が行われているかのような表示が並ぶ
    (2026-11-22 のユーザー指摘)。保存そのものは毎回行う\"\"\"
    if tag in _receipt_printed:
        return
    _receipt_printed.add(tag)
    print(f"[log] {label}を受け取りました: {name} ({count} 件)", flush=True)


""",
    """""")

rep("inference receipt removal",
    """    # 起動前に終わった試合の推論過程ログが、UI の再送で起動時に
    # 届くことがある。保存はするが、起動時に過去分の処理が走って
    # いるように見える表示は出さない (2026-11-21 のユーザー指示)。
    # 判定は対象範囲の判定 (試合の開始時刻基準) で行う
    ended_before_start = not _in_session_scope(_gate_key(battle))
    if not ended_before_start:
        _announce_receipt(("inference", battle), "推論過程ログ",
                          name, len(data["entries"]))
    return name
""",
    """    # 推論過程ログの受け取り表示は出さない (2026-11-22 のユーザー
    # 指示)。保存は従来どおり毎回行う
    return name
""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
