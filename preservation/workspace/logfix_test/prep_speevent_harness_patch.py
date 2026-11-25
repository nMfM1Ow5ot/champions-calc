#!/usr/bin/env python3
# make_harness.py: T135 tests for the spe (pre-move KO) events.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T135: spe events (speed evidence for pre-move KOs) =====
// (a) acceptance scene (battle_20261122_181745 T1): Steel Beam KOs
// Gardevoir before it moves -> spe event fast=Archaludon slow=Gardevoir
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\\"k\\":\\"mv\\",\\"turn\\":1,\\"label\\":\\"p2a: Archaludon\\",\\"move\\":\\"Steel Beam\\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135a spe event for pre-move KO", battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") && $0.contains("\\"fast\\":\\"p2a: Archaludon\\"") && $0.contains("\\"slow\\":\\"p1a: Gardevoir\\"") && $0.contains("\\"move\\":\\"Steel Beam\\"") })
// (b) the defender already moved this turn -> no spe event
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p1a: Gardevoir|Moonblast", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\\"k\\":\\"mv\\",\\"turn\\":1,\\"label\\":\\"p1a: Gardevoir\\",\\"move\\":\\"Moonblast\\"}",
                "{\\"k\\":\\"mv\\",\\"turn\\":1,\\"label\\":\\"p2a: Archaludon\\",\\"move\\":\\"Steel Beam\\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135b no spe when defender moved", !battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") })
// (c) the defender switched in this turn -> no spe event
resetAll()
currentTurn = 2
battleLog = ["|turn|2", "|switch|p1a: Gardevoir|Gardevoir|145/145", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\\"k\\":\\"mv\\",\\"turn\\":2,\\"label\\":\\"p2a: Archaludon\\",\\"move\\":\\"Steel Beam\\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135c no spe when defender entered this turn", !battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") })
// (d) no KO (or not a direct move) -> no spe event
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\\"k\\":\\"mv\\",\\"turn\\":1,\\"label\\":\\"p2a: Archaludon\\",\\"move\\":\\"Steel Beam\\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 10, hpText: "14/145", directMove: true)
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: false)
check("T135d no spe without a direct-move KO", !battleEvents.contains { $0.contains("\\"k\\":\\"spe\\"") })
'''

old = """check("T134g no full-hp damage line", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Gardevoir") })"""
if src.count(old) != 1:
    print("ABORT: anchor count", src.count(old))
    sys.exit(1)
src = src.replace(old, old + TESTS, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T135 tests")
