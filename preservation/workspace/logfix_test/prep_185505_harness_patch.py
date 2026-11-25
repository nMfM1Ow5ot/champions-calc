#!/usr/bin/env python3
# make_harness.py: T136 tests for the battle_20261122_185505 fixes.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T136: 185505 fixes (announcement bang-cut, post-faint lines, pull-back guard) =====
moveNameOrig[normalize("ねっぷう")] = "ねっぷう"; moveJa2En["ねっぷう"] = "Heat Wave"
// (a) announcement with trailing junk after the bang (recording overlay)
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100, hpCur: 185, hpMax: 185, hpBarPct: nil)
lastSlots["mineB"] = SlotState(speciesEn: "Garchomp", hpPercent: 89, hpCur: 165, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 100
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
fieldSeen["p1"] = ["Charizard", "Garchomp"]
emittedSwitchKeys.insert("p1:Charizard"); emittedSwitchKeys.insert("p1:Garchomp")
_ = translateBattleMessage("ムービー収録 リザードンの ねっぷう！ 0 KB")
check("T136a announcement survives trailing junk", battleLog.contains("|move|p1a: Charizard|Heat Wave"))
// (b) announcement with a "・" before the move name
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100, hpCur: 185, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 100
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
fieldSeen["p1"] = ["Charizard", "Garchomp"]
emittedSwitchKeys.insert("p1:Charizard"); emittedSwitchKeys.insert("p1:Garchomp")
_ = translateBattleMessage("リザードンの ・ねっぷう！")
check("T136b announcement survives nakaguro", battleLog.contains("|move|p1a: Charizard|Heat Wave"))
// (c) no HP lines for a species already recorded fainted
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
faintedSpecies.insert("p1:Garchomp")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Garchomp", speciesEn: "Garchomp", fromPct: 0, toPct: 19, hpText: "36/185", force: true)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Garchomp", speciesEn: "Garchomp", fromPct: 19, toPct: 0, hpText: "0/185", force: true)
check("T136c post-faint HP lines suppressed", !battleLog.contains { $0.hasPrefix("|-heal|p1a: Garchomp") || $0.hasPrefix("|-damage|p1a: Garchomp") })
// (d) pull-back skipped in a developed segment, allowed in an early one
resetAll()
currentTurn = 3
battleLog = ["|turn|2", "|move|p2a: Indeedee-F|Helping Hand", "|move|p1a: Charizard|Weather Ball", "|-damage|p2a: Indeedee-F|0/100", "|faint|p2a: Indeedee-F", "|move|p2b: Armarouge|Expanding Force", "|switch|p1b: Sylveon|Sylveon|193/193"]
let pbDev = pullBackSwitchBlock(label: "p1b: Sylveon", requireEarlySegment: true)
check("T136d pull-back skipped in developed segment", pbDev.proto.isEmpty && battleLog.last == "|switch|p1b: Sylveon|Sylveon|193/193")
battleLog = ["|turn|2", "|move|p2a: Indeedee-F|Helping Hand", "|switch|p1b: Sylveon|Sylveon|193/193"]
let pbEarly = pullBackSwitchBlock(label: "p1b: Sylveon", requireEarlySegment: true)
check("T136e pull-back still fires in early segment", !pbEarly.proto.isEmpty)
'''

old = """check("T135d no spe without a direct-move KO", !battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") })"""
if src.count(old) != 1:
    print("ABORT: anchor count", src.count(old))
    sys.exit(1)
src = src.replace(old, old + TESTS, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T136 tests")
