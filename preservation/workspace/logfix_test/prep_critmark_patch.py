#!/usr/bin/env python3
# reader.swift: crit marks for damage events (battle_20261122_201011
# triage). recordDamageEvent already checks lastCritAt with a 6s
# window, but a staged HP adoption can create the hit's final dmg
# event more than 6s after the crit text, and the post-hoc patch of
# the earlier event cannot reach a copy the consumer already took.
# Add a (turn, attacker) scoped crit mark set when the crit text is
# confirmed; event creation consults it as well.
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

# 1. the registry, next to lastCritAt
rep("decl",
    """var lastCritAt: [String: Date] = [:]               // 枠 -> 最後に |-crit| を出した時刻""",
    """var lastCritAt: [String: Date] = [:]               // 枠 -> 最後に |-crit| を出した時刻
var critEventMarks: [String: (turn: Int, atk: String)] = [:]  // 対象ラベル -> 急所が確定した (ターン, 攻撃側ラベル)。dmg イベント生成時の crit 判定に使う (生成が急所文から 6 秒以上遅れても、そのヒットの最終イベントに急所を載せるため)""")

# 2. set the mark in the crit branch
rep("mark",
    """            lastCritAt[target] = Date()""",
    """            lastCritAt[target] = Date()
            critEventMarks[target] = (turn: currentTurn, atk: lastMoveLabel)""")

# 3. consult the mark at event creation
rep("consult",
    """    let crit = lastCritAt["\\(slot): \\(speciesEn)"].map { Date().timeIntervalSince($0) < 6 } ?? false""",
    """    let crit = (lastCritAt["\\(slot): \\(speciesEn)"].map { Date().timeIntervalSince($0) < 6 } ?? false)
        || (critEventMarks["\\(slot): \\(speciesEn)"].map { $0.turn == currentTurn && $0.atk == lastMoveLabel } ?? false)""")

# 4. clear in resetLogState (next to the lastCritAt clear, if present;
#    otherwise next to the faintedSpecies clear)
import re
m = re.search(r"lastCritAt = \[\:\][^\n]*\n", src)
if m:
    src = src.replace(m.group(0), m.group(0) + "    critEventMarks = [:]\n", 1)
    print("OK: reset (near lastCritAt)")
else:
    rep("reset (fallback)",
        """    faintedSpecies = []; heldEntryBoosts = []""",
        """    faintedSpecies = []; heldEntryBoosts = []
    critEventMarks = [:]""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
