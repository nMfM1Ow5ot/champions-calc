#!/usr/bin/env python3
# make_harness.py: T143 for the standalone crit event.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T143: 独立 crit イベント (battle_20261122_201011、候補 (i)) =====
resetAll()
currentTurn = 7
lastSlots["mineB"] = SlotState(speciesEn: "Venusaur", hpPercent: 44)
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
lastMoveLabel = "p2a: Garchomp"; lastMoveName = "Rock Slide"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
monStates["p1:Venusaur"] = MonState(); monStates["p1:Venusaur"]!.hpPercent = 44
recordDamageEvent(slot: "p1b", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 89, toPct: 44, hpText: "70/157")
check("T143a the dmg event starts non-crit", battleEvents.last?.contains("\"crit\":false") == true)
_ = translateBattleMessage("フシギバナの急所に当たった！")
check("T143b a standalone crit event is appended", battleEvents.last?.contains("\"k\":\"crit\"") == true && battleEvents.last?.contains("\"atk\":\"p2a: Garchomp\"") == true && battleEvents.last?.contains("\"def\":\"p1b: Venusaur\"") == true && battleEvents.last?.contains("\"move\":\"Rock Slide\"") == true)
check("T143c the earlier event is still patched in place", battleEvents.first?.contains("\"crit\":true") == true)
check("T143d the crit line is logged", battleLog.contains("|-crit|p1b: Venusaur"))
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
print("OK: T143 block")
