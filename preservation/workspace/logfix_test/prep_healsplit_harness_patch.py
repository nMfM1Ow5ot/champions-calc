#!/usr/bin/env python3
# make_harness.py: T144 for the Sitrus + Grassy Terrain heal split.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T144: オボン + 地形の合算回復の分離 (battle_20261122_201011 T7) =====
resetAll()
currentTurn = 7
logFieldTerrain = "Grassy"
teamEntries["Incineroar"] = nil
lastMoveLabel = "p2a: Garchomp"; lastMoveName = "Rock Slide"; lastMoveMsgAt = Date()
monStates["p1:Incineroar"] = MonState(); monStates["p1:Incineroar"]!.hpPercent = 53
lastEmittedPct["mineB"] = 23
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", toPct: 53, hpText: "108/202", force: true)
check("T144a the berry line is split out", battleLog.contains("|-heal|p1b: Incineroar|96/202|[from] item: Sitrus Berry"))
check("T144b the terrain line follows", battleLog.contains("|-heal|p1b: Incineroar|108/202|[from] Grassy Terrain"))
check("T144c no combined single line", !battleLog.contains("|-heal|p1b: Incineroar|108/202|[from] item: Sitrus Berry"))
// 対照: 地形が無ければ合算の形のまま 1 行
resetAll()
currentTurn = 7
teamEntries["Incineroar"] = nil
lastMoveLabel = "p2a: Garchomp"; lastMoveName = "Rock Slide"; lastMoveMsgAt = Date()
monStates["p1:Incineroar"] = MonState(); monStates["p1:Incineroar"]!.hpPercent = 53
lastEmittedPct["mineB"] = 23
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", toPct: 53, hpText: "108/202", force: true)
check("T144d without terrain it stays one line", battleLog.contains("|-heal|p1b: Incineroar|108/202|[from] item: Sitrus Berry"))
// 対照: 地形があってもオボン単独の量なら分けない
resetAll()
currentTurn = 7
logFieldTerrain = "Grassy"
teamEntries["Incineroar"] = nil
lastMoveLabel = "p2a: Garchomp"; lastMoveName = "Rock Slide"; lastMoveMsgAt = Date()
monStates["p1:Incineroar"] = MonState(); monStates["p1:Incineroar"]!.hpPercent = 48
lastEmittedPct["mineB"] = 23
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", toPct: 48, hpText: "96/202", force: true)
check("T144e a berry-only amount is not split", battleLog.contains("|-heal|p1b: Incineroar|96/202|[from] item: Sitrus Berry") && !battleLog.contains("[from] Grassy Terrain"))
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
print("OK: T144 block")
