#!/usr/bin/env python3
# make_harness.py: critEventMarks prelude global + reset + T141.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# prelude declaration (next to the lastCritAt global)
import re
m = re.search(r"var lastCritAt[^\n]*\n", src)
if not m:
    print("ABORT: prelude lastCritAt not found")
    sys.exit(1)
src = src.replace(m.group(0), m.group(0) + 'var critEventMarks: [String: (turn: Int, atk: String)] = [:]\n', 1)
print("OK: prelude decl")

# resetAll clearing (the reset block lists lastCritAt)
m2 = re.search(r"[^\n]*lastCritAt = \[\:\][^\n]*\n", src)
if not m2:
    print("ABORT: reset lastCritAt not found")
    sys.exit(1)
src = src.replace(m2.group(0), m2.group(0) + "    critEventMarks = [:]\n", 1)
print("OK: reset")

TESTS = r'''
// ===== T141: 急所マーク (battle_20261122_201011 の切り分け) =====
// (a) 急所文の確定が (ターン, 攻撃側) で記録されていれば、6 秒を
// 超えて生成された dmg イベントにも crit が載る
resetAll()
currentTurn = 7
critEventMarks["p1b: Venusaur"] = (turn: 7, atk: "p2a: Garchomp")
lastMoveLabel = "p2a: Garchomp"; lastMoveName = "Rock Slide"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
monStates["p1:Venusaur"] = MonState(); monStates["p1:Venusaur"]!.hpPercent = 44
recordDamageEvent(slot: "p1b", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 89, toPct: 44, hpText: "70/157")
check("T141a late-created event carries the crit", battleEvents.last?.contains("\"crit\":true") == true)
// (b) 対照: 攻撃側が異なるヒットには載らない
resetAll()
currentTurn = 7
critEventMarks["p1b: Venusaur"] = (turn: 7, atk: "p2a: Garchomp")
lastMoveLabel = "p2b: Floette-Eternal"; lastMoveName = "Draining Kiss"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
monStates["p1:Venusaur"] = MonState(); monStates["p1:Venusaur"]!.hpPercent = 44
recordDamageEvent(slot: "p1b", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 89, toPct: 44, hpText: "70/157")
check("T141b a different attacker's hit stays non-crit", battleEvents.last?.contains("\"crit\":false") == true)
'''

lines = src.split("\n")
for i, line in enumerate(lines):
    if 'out(failures == 0 ? "ALL PASS"' in line:
        lines[i:i] = [TESTS]
        break
else:
    print("ABORT: ALL PASS anchor not found")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T141 block")
