#!/usr/bin/env python3
# Harness updates for the battle_20261122_160927 fix round:
# - prelude: barVetoHold global + resetAll clears it
# - driver: T132a-d (max adoption gates, bar veto, sourceless hold)
import sys

HPATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(HPATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

rep("prelude global",
    "var lastRoundEventAt: Date? = nil\n",
    "var lastRoundEventAt: Date? = nil\nvar barVetoHold: [String: (pct: Int, turn: Int)] = [:]\n")

rep("resetAll clears barVetoHold",
    "battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]\n",
    "battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]; barVetoHold = [:]\n")

TESTS = r'''
// T132: battle_20261122_160927 の修正群
// (a) 最大 HP の採用ゲート: 正当な採用は従来どおり、融合読みは候補に
//     ならず、採用は 1 回限り
resetAll()
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
check("T132a legit adoption still works", battleMaxOverride["Sneasler"] == 171)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 271, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 271, registeredMax: 157)
check("T132a adoption is once-only", battleMaxOverride["Sneasler"] == 171)
resetAll()
noteBattleMaxRead(speciesEn: "Indeedee-F", readMax: 371, registeredMax: 177)
noteBattleMaxRead(speciesEn: "Indeedee-F", readMax: 371, registeredMax: 177)
check("T132b fused max never adopted", battleMaxOverride["Indeedee-F"] == nil && battleMaxCandidate["Indeedee-F"] == nil)
// (b) バー拒否: 数字だけが大きく下がり、バーが確定値を維持する場合は
//     行を出さない。次ターンも続けば状態訂正として静かに取り込む
resetAll()
var ms132 = MonState(); ms132.hpPercent = 100; ms132.hpText = "171/171"
monStates["p1:Sneasler"] = ms132
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
lastEmittedPct["mineA"] = 100
let barState132 = SlotState(speciesEn: "Sneasler", hpPercent: 63, hpCur: 108, hpMax: 171, hpBarPct: 98)
processPlates(["mineA": barState132])
pendingDamageSince["mineA"] = Date(timeIntervalSinceNow: -3)
processPlates(["mineA": barState132])
processPlates(["mineA": barState132])
check("T132c bar veto blocks phantom drop", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") } && barVetoHold["mineA"]?.pct == 63)
currentTurn = 2
processPlates(["mineA": barState132])
pendingDamageSince["mineA"] = Date(timeIntervalSinceNow: -3)
processPlates(["mineA": barState132])
processPlates(["mineA": barState132])
check("T132c persistent value adopted silently next turn", lastEmittedPct["mineA"] == 63 && !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") })
// (c) 出所の無い低下の保留: 直近に他の技が無い大きな低下は行を出さず、
//     直近の相手の技がある場合は従来どおり出す
resetAll()
lastMoveLabel = "p2b: Milotic"; lastMoveName = "Coil"
lastMoveMsgAt = Date(timeIntervalSinceNow: -30)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 90, hpText: "150/167")
check("T132d sourceless drop held", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Gardevoir") } && suspectJump["mineA"]?.toPct == 90)
resetAll()
lastMoveLabel = "p2a: Raichu"; lastMoveName = "Thunderbolt"
lastMoveMsgAt = Date()
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 90, hpText: "150/167")
check("T132d recent opposing move explains drop", battleLog.contains("|-damage|p1a: Gardevoir|150/167"))
'''
anchor = 'check("T131d exactly one turn line", battleLog.filter { $0.hasPrefix("|turn|") }.count == 1)\n'
rep("driver T132", anchor, anchor + TESTS)

open(HPATH, "w", encoding="utf-8").write(src)
print("ALL HARNESS EDITS APPLIED")
