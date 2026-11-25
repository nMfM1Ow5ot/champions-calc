#!/usr/bin/env python3
# Harness: add T133a-h for the battle_20261122_171847 fix round.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

anchor = '''check("T132d distinct text emitted", battleLog.contains("|-damage|p1a: Gardevoir|150/167"))
out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
addition = '''check("T132d distinct text emitted", battleLog.contains("|-damage|p1a: Gardevoir|150/167"))
// T133: battle_20261122_171847 修正群
// (a) 兄弟枠ガードは ひんし (0%) には効かない (相手2体の "0/100" は
// 常に一致してしまうため、0% まで保留すると ひんしが丸ごと消える)
resetAll()
var ms133z = MonState(); ms133z.hpPercent = 0; ms133z.hpText = "0/100"
monStates["p2:Charizard"] = ms133z
lastSlots["oppB"] = SlotState(speciesEn: "Charizard", hpPercent: 0)
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T133a sibling guard does not hold a faint", battleLog.contains("|-damage|p2a: Sneasler|0/100"))
// (b) suspect として保留された 0% は、持続しても無音採用せず行を出す
resetAll()
currentTurn = 1
suspectJump["oppB"] = (toPct: 0, turn: 1)
currentTurn = 2
lastMoveLabel = "p1a: Armarouge"
lastMoveName = "Armor Cannon"
lastMoveMsgAt = Date()
lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Kingambit", speciesEn: "Kingambit", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T133b suspect zero falls through to emission", battleLog.contains("|-damage|p2b: Kingambit|0/100") && suspectJump["oppB"] == nil)
// (c) 別種族の登録最大と一致する読みは採用候補に数えない
resetAll()
teamEntries["Indeedee-F"] = ["stats": ["hp": 177]]
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 177, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 177, registeredMax: 157)
check("T133c sibling-max collision not adopted", battleMaxOverride["Sneasler"] == nil)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
check("T133c genuine max adopted after collision blocked", battleMaxOverride["Sneasler"] == 171)
teamEntries["Indeedee-F"] = nil
// (d) ひんし交代はターン冒頭へ引き戻さない
resetAll()
currentTurn = 3
battleLog = ["|turn|3", "|move|p1a: Armarouge|Expanding Force"]
displayLog = ["Turn 3", "Armarouge used Expanding Force!"]
lastSlots["oppB"] = SlotState(speciesEn: "Charizard", hpPercent: 0)
let kbState = SlotState(speciesEn: "Kingambit", hpPercent: 100)
processPlates(["oppB": kbState])
processPlates(["oppB": kbState])
processPlates(["oppB": kbState])
let swIdx133 = battleLog.firstIndex(of: "|switch|p2b: Kingambit|Kingambit|100/100") ?? -1
let mvIdx133 = battleLog.firstIndex(of: "|move|p1a: Armarouge|Expanding Force") ?? -1
check("T133d faint replacement not pulled to turn head", swIdx133 > mvIdx133 && mvIdx133 >= 0)
// (e) ひんし文: プレートが先に monStates を 0 にしていても、被ダメ行が
// 未出なら文側で補う
resetAll()
var ms133g2 = MonState(); ms133g2.hpPercent = 0; ms133g2.hpText = "8/100"; ms133g2.hpMax = 100
monStates["p2:Garchomp"] = ms133g2
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 0)
lastEmittedPct["oppA"] = 8
_ = translateBattleMessage("相手のガブリアスは たおれた！")
check("T133e faint text compensates when plate state already 0", battleLog.contains("|-damage|p2a: Garchomp|0/100") && pendingFaints.contains { $0.slot == "p2a" })
// (f) 最大の断片読みは既知の最大で組み直す
resetAll()
teamEntries["Gardevoir"] = ["stats": ["hp": 145]]
let gvState = SlotState(speciesEn: "Gardevoir", hpPercent: 24, hpCur: 11, hpMax: 45)
processPlates(["mineB": gvState])
processPlates(["mineB": gvState])
processPlates(["mineB": gvState])
check("T133f fragment max rescaled to known max", lastSlots["mineB"]?.hpMax == 145 && lastSlots["mineB"]?.hpCur == 35)
teamEntries["Gardevoir"] = nil
// (g) 主語だけの断片 + 能力名・動詞の断片で ランク変化が適用される
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
var ms133g3 = MonState(); ms133g3.hpPercent = 100; ms133g3.hpText = "100/100"
monStates["p2:Garchomp"] = ms133g3
_ = translateBattleMessage("相手のガブリアスの")
_ = translateBattleMessage("素早さが下かった！")
check("T133g subject-only fragment merges into unboost", battleLog.contains("|-unboost|p2a: Garchomp|spe|1"))
// (h) いのちのたまの反動が残量で切り取られた ひんしにも [from] が付く
resetAll()
revealedItems["Garchomp"] = "いのちのたま"
lastMoveLabel = "p2a: Garchomp"
lastMoveName = "Earthquake"
lastMoveMsgAt = Date()
lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Garchomp", speciesEn: "Garchomp", fromPct: 8, toPct: 0, hpText: "0/100", force: true)
check("T133h capped Life Orb recoil classified", battleLog.contains("|-damage|p2a: Garchomp|0/100|[from] item: Life Orb"))
revealedItems["Garchomp"] = nil
out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
c = src.count(anchor)
if c != 1:
    print(f"ABORT: anchor count = {c}")
    sys.exit(1)
src = src.replace(anchor, addition, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T133a-h added")
