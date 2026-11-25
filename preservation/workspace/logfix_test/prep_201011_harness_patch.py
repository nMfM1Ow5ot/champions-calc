#!/usr/bin/env python3
# make_harness.py: T140 block for the battle_20261122_201011 fixes,
# plus two probes (T140f Heat Wave announcement, T140g Calm Mind
# boosts) reproducing the reported losses with the exact texts.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T140: battle_20261122_201011 =====
// (a) ひんし記録済みでも、その種族の未発行の KO 被ダメ行は出す
resetAll()
currentTurn = 5
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 0
lastEmittedPct["oppA"] = 100
faintedSpecies.insert("p2:Rillaboom")
lastMoveLabel = "p1a: Charizard"; lastMoveName = "Heat Wave"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T140a owed KO line survives the post-faint guard", battleLog.contains("|-damage|p2a: Rillaboom|0/100"))
// (b) 対照: ひんし後の古い読み (0 でない被ダメ) は従来どおり抑制
resetAll()
currentTurn = 5
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 0
lastEmittedPct["oppA"] = 0
faintedSpecies.insert("p2:Rillaboom")
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 50, toPct: 36, hpText: "36/100", force: true)
check("T140b stale post-faint read still suppressed", !battleLog.contains { $0.contains("Rillaboom") && $0.contains("36/100") })
// (c) 持ち物消費済みの個体に たべのこし は帰属しない
resetAll()
currentTurn = 8
logFieldTerrain = ""
itemLostActive.insert("p1:Incineroar")
check("T140c no Leftovers guess for a consumed item", healSource(plateName: "mineA", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 29, toPct: 35) == nil)
itemLostActive.remove("p1:Incineroar")
check("T140c2 Leftovers guess intact otherwise", healSource(plateName: "mineA", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 29, toPct: 35)?.label == "item: Leftovers")
// (d) 交代直後のミス文: このターンの交代記録があれば通す
resetAll()
currentTurn = 4
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 46)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 100)
switchInTurn["p2:Rillaboom"] = 4
lastMoveLabel = "p1a: Charizard"; lastMoveName = "Heat Wave"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のゴリランダーには当たらなかった！")
check("T140d miss accepted with this-turn switch record", battleLog.contains("|-miss|p1a: Charizard|p2a: Rillaboom"))
// (e) すてゼリフの低下は、文中の相手マーカーで相手側へ帰属する
resetAll()
currentTurn = 1
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 100)
emittedSwitchKeys.insert("p2:Incineroar"); emittedSwitchKeys.insert("p1:Incineroar")
lastMoveLabel = "p1b: Incineroar"; lastMoveName = "Parting Shot"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のガオガエンのこうげきが下がった！")
check("T140e Parting Shot drop goes to the opponent", battleLog.contains("|-unboost|p2a: Incineroar|atk|1") && !battleLog.contains { $0.contains("unboost|p1b: Incineroar") })
// (f) 探針: T5 ねっぷう告知 (正確な文と近似した場の状態)
resetAll()
currentTurn = 5
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Venusaur", hpPercent: 78)
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 67)
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Fake Out"; lastMoveMsgAt = Date()
_ = translateBattleMessage("リザードンのねっぷう！")
check("T140f PROBE heat wave announcement at T5", battleLog.contains("|move|p1a: Charizard|Heat Wave"))
// (g) 探針: めいそう の上昇行 (T2 適用後に T3 で同じ文が来る場合)
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 46)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 61)
monStates["p2:Floette-Eternal"] = MonState(); monStates["p2:Floette-Eternal"]!.hpPercent = 61
emittedSwitchKeys.insert("p2:Floette-Eternal")
_ = translateBattleMessage("あいて相手のフラエッテのとくこうとくぼう特攻特防が上がった！")
let t140gAfterT2 = battleLog.filter { $0.contains("boost|p2b: Floette-Eternal") }.count
currentTurn = 3
_ = translateBattleMessage("相手のフラエッテのめいそう！")
_ = translateBattleMessage("相手のフラエッテのとくにう特攻特防が上がった！")
_ = translateBattleMessage("あいて相手のフラエッテのとくこうとくぼう特攻特防が上がった！")
let t140gAfterT3 = battleLog.filter { $0.contains("boost|p2b: Floette-Eternal") }.count
check("T140g PROBE calm mind boosts land on both turns", t140gAfterT2 == 2 && t140gAfterT3 == 4)
'''

lines = src.split("\n")
for i, line in enumerate(lines):
    if 'out(failures == 0 ? "ALL PASS"' in line:
        lines[i:i] = [TESTS]
        break
else:
    print("ABORT: ALL PASS anchor not found")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write("\n".join(lines))
print("OK: T140 block")
