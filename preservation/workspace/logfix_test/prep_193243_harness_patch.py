#!/usr/bin/env python3
# make_harness.py: T139 for the battle_20261122_193243 fixes
# (immune text form; recoil text source + correction guard).
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T139: 193243 fixes (immune text; recoil text source) =====
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 87, hpCur: 161, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 87
fieldSeen["p1"] = ["Garchomp", "Farigiraf"]
_ = translateBattleMessage("ガブリアスにはこうかはないようだ…")
check("T139a immune line from the hiragana trailing-ellipsis form", battleLog.contains("|-immune|p1a: Garchomp"))
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
lastMoveLabel = "p2b: Rillaboom"
lastMoveName = "Wood Hammer"
lastMoveMsgAt = Date(timeIntervalSinceNow: -10)
lastDamageTime["oppB"] = Date(timeIntervalSinceNow: -20)
lastDamageSeq["oppB"] = actionSeq - 1
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 100
lastSlots["oppB"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100, hpCur: 100, hpMax: 100, hpBarPct: nil)
fieldSeen["p2"] = ["Raichu", "Rillaboom"]
emittedSwitchKeys.insert("p2:Rillaboom")
let recoilCtl = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 99, hpText: "99/100", force: true)
check("T139b small drop absorbed silently without a source", recoilCtl && !battleLog.contains("|-damage|p2b: Rillaboom|99/100"))
lastDamageTime["oppB"] = Date(timeIntervalSinceNow: -20)
lastDamageSeq["oppB"] = actionSeq - 1
_ = translateBattleMessage("相手のゴリランダーはウッドハンマーの反動によるダメージを受けた！")
check("T139c recoil text records the pending source", pendingStatusFrom["p2:Rillaboom"]?.code == "move: Wood Hammer")
let recoilEmit = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 99, hpText: "99/100", force: true)
check("T139d recoil drop emitted with its [from]", recoilEmit && battleLog.contains("|-damage|p2b: Rillaboom|99/100|[from] move: Wood Hammer"))
'''

old = """check("T138d unscored falls back to suffix rule", hdrDoneOld.removed.contains("p2:Kommo-o"))"""
if src.count(old) != 1:
    print("ABORT: anchor count", src.count(old))
    sys.exit(1)
src = src.replace(old, old + TESTS, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T139 tests")
