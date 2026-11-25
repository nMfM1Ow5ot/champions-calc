#!/usr/bin/env python3
# make_harness.py: prelude globals for the revival counters + the
# reset mirror + T134 tests for the battle_20261122_181745 round.
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

rep("prelude globals",
    """var barVetoHold: [String: (pct: Int, turn: Int)] = [:]""",
    """var barVetoHold: [String: (pct: Int, turn: Int)] = [:]
var faintReviveCount: [String: Int] = [:]
var faintReviveSince: [String: Date] = [:]""")

rep("reset mirror",
    """    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]; barVetoHold = [:]""",
    """    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]; barVetoHold = [:]; faintReviveCount = [:]; faintReviveSince = [:]""")

TESTS = r'''
// ===== T134: battle_20261122_181745 round =====
// T134a: the 0% branch vetoes a zero read when the bar shows 42%
resetAll()
currentTurn = 2
battleLog = ["|turn|2"]
registerMon(side: "p1", speciesEn: "Sneasler", hp: 61)
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 61, hpCur: 104, hpMax: 171, hpBarPct: 61)
lastEmittedPct["mineA"] = 61
monStates["p1:Sneasler"]?.hpPercent = 61
for _ in 0..<3 {
    processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 0, hpCur: 0, hpMax: 171, hpBarPct: 42)])
}
check("T134a bar 42 vetoes phantom faint", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") } && !battleLog.contains("|faint|p1a: Sneasler") && debugCaptureCalls.contains("hp_disagree"))
// T134b: Steel Beam recoil is classified, not held as unclassified
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
registerMon(side: "p2", speciesEn: "Archaludon", hp: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Archaludon", hpPercent: 100, hpCur: nil, hpMax: nil, hpBarPct: nil)
lastEmittedPct["oppA"] = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Archaludon", speciesEn: "Archaludon", fromPct: 100, toPct: 79, hpText: "79/100", force: true)
check("T134b Steel Beam recoil classified", battleLog.contains("|-damage|p2a: Archaludon|79/100|[from] move: Steel Beam") && suspectJump["oppA"] == nil)
// T134c: the faint subject comes from the name+wa grammar, not the
// first dictionary match in a contaminated text
resetAll()
currentTurn = 2
battleLog = ["|turn|2"]
registerMon(side: "p2", speciesEn: "Archaludon", hp: 49)
lastSlots["oppA"] = SlotState(speciesEn: "Archaludon", hpPercent: 49, hpCur: nil, hpMax: nil, hpBarPct: nil)
lastEmittedPct["oppA"] = 49
emittedSwitchKeys.insert("p2:Archaludon")
_ = translateBattleMessage("相手のブリジュラスは オオニューラ 69/171 たおれた！")
check("T134c faint grammar subject", battleLog.contains("|-damage|p2a: Archaludon|0/100") && pendingFaints.contains { $0.slot == "p2a" && $0.speciesEn == "Archaludon" })
// T134d: a poisoned zero baseline is rebased when the occupant reads alive
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
registerMon(side: "p1", speciesEn: "Sneasler", hp: 40)
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 40, hpCur: 69, hpMax: 171, hpBarPct: 40)
lastEmittedPct["mineA"] = 0
lastDamageTime["mineA"] = Date(timeIntervalSinceNow: -30)
monStates["p1:Sneasler"]?.hpPercent = 40
processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 40, hpCur: 69, hpMax: 171, hpBarPct: 40)])
check("T134d zero baseline rebased on alive read", lastEmittedPct["mineA"] == 40)
// T134e: the archive header unifies a full-HP switch line to the
// adopted real max
let proto134 = ["|poke|p1|Sneasler", "|start",
                "|switch|p1a: Sneasler|Sneasler|157/157",
                "|-damage|p1a: Sneasler|120/171"]
let comp134 = completeArchiveHeader(protocolLines: proto134, displayLines: [])
check("T134e switch max unified to adopted max", comp134.protocolLines.contains("|switch|p1a: Sneasler|Sneasler|171/171"))
// T134f: Perish Song count/announcement texts are consumed
resetAll()
battleLog = []
let perish1 = translateBattleMessage("オオニューラの減びのカウントが3になった！")
let perish2 = translateBattleMessage("ほろびのうたを 聴いたポケモンは3ターン後に滅びてしまう！")
check("T134f perish texts consumed", perish1 && perish2 && battleLog.isEmpty)
// T134g: no damage line at full HP
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
registerMon(side: "p1", speciesEn: "Gardevoir", hp: 100)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 100, hpText: "145/145", force: true)
check("T134g no full-hp damage line", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Gardevoir") })
'''

rep("T134 tests",
    """check("T133h capped Life Orb recoil classified", battleLog.contains("|-damage|p2a: Garchomp|0/100|[from] item: Life Orb"))""",
    """check("T133h capped Life Orb recoil classified", battleLog.contains("|-damage|p2a: Garchomp|0/100|[from] item: Life Orb"))""" + TESTS)

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
