#!/usr/bin/env python3
# reader.swift: hold the display log's "Turn N" block until the
# turn's first substantive event renders (user instruction via the
# comprehensive chat 2026-11-22: the turn display appeared before
# the turn had begun, e.g. an empty Turn 10 on a command-phase
# forfeit in battle_20261122_201011).
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# 1. the pending global, next to renderHold
rep("decl",
    """var renderHold: [String] = []                     // フィールド開始行の保留 (特性行が直後に来たら順序を入れ替える)""",
    """var renderHold: [String] = []                     // フィールド開始行の保留 (特性行が直後に来たら順序を入れ替える)
var pendingTurnDisplay: [String] = []             // 表示ログの Turn 行ブロックの保留 (そのターンの最初の出来事が表示されるまで出さない)""")

# 2. clear it in resetLogState (unique context)
rep("reset",
    """    renderHold = []
    renderPendingBlank = false""",
    """    renderHold = []
    pendingTurnDisplay = []
    renderPendingBlank = false""")

# 3. the hold/flush logic, right before the display reorder section
rep("hold",
    """    // 表示ログの並び訂正 (プロトコル側の挿入と対): 急所の表示は""",
    """    // ターン表示 (Turn N のブロック) は、そのターンが始まった
    // ことを示す最初の出来事 (特性・持ち物・交代・技など、表示行を
    // 伴うもの) が来るまで出さない。ターン行だけが先行して表示
    // されると、始まっていないターンの見出しが残る (実例:
    // 2026-11-22 battle_20261122_201011、コマンド選択中の投了で
    // 中身の無い Turn 10 が表示された)。勝敗行が来たら保留は
    // 破棄する (そのターンは始まらなかった)
    if kind == "turn" {
        pendingTurnDisplay = out
        out = []
    } else if kind == "win" || kind == "tie" {
        pendingTurnDisplay = []
    } else if !out.isEmpty && !pendingTurnDisplay.isEmpty {
        out = pendingTurnDisplay + out
        pendingTurnDisplay = []
    }
    // 表示ログの並び訂正 (プロトコル側の挿入と対): 急所の表示は""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
