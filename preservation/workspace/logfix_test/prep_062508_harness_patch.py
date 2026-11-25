#!/usr/bin/env python3
# Harness support for the battle_20261123_062508 fix round (T153-T158):
# - prelude: suspectJump gains hpText; lastMoveBySlot / lastMissKey globals
# - resetAll: clear the new globals
# - driver: append T153-T158 after T152e
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print(f"ABORT {tag}: anchor count = {n}")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

rep("var suspectJump: [String: (toPct: Int, turn: Int)] = [:]",
    "var suspectJump: [String: (toPct: Int, turn: Int, hpText: String)] = [:]",
    "prelude suspectJump type")

rep("var critEventMarks: [String: (turn: Int, atk: String)] = [:]",
    "var critEventMarks: [String: (turn: Int, atk: String)] = [:]\nvar lastMoveBySlot: [String: (move: String, turn: Int)] = [:]\nvar lastMissKey = \"\"",
    "prelude globals")

rep('    lastMoveLabel = ""; lastMoveName = ""; lastMoveMsgAt = Date.distantPast; lastMoveSeq = -1',
    '    lastMoveLabel = ""; lastMoveName = ""; lastMoveMsgAt = Date.distantPast; lastMoveSeq = -1; lastMissKey = ""; lastMoveBySlot = [:]',
    "resetAll clears")

rep('''check("T152e garbled stat shape", isBoostShapedText("マフォクシーとコータスの政撃が下がった！"))''',
    '''check("T152e garbled stat shape", isBoostShapedText("マフォクシーとコータスの政撃が下がった！"))
// T153 (battle_20261123_062508): 保留した低下が更なる低下で裏づけられたら行として出す
// a: sibling 保留 → 分類済みチップで 2 行に分かれる
resetAll()
for (ja, en) in [("ミロカロス", "Milotic"), ("バンギラス", "Tyranitar")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Tyranitar"]?.hpText = "86/100"
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 100, toPct: 86, hpText: "86/100", force: true)
check("T153a held by sibling", battleLog.filter { $0.contains("|-damage|") }.isEmpty && suspectJump["oppA"]?.toPct == 86)
pendingStatusFrom["p2:Milotic"] = ("sandstorm", Date())
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 100, toPct: 80, hpText: "80/100", force: true)
check("T153a held segment emitted first", battleLog.contains("|-damage|p2a: Milotic|86/100") && battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm") && battleLog.firstIndex(of: "|-damage|p2a: Milotic|86/100")! < battleLog.firstIndex(of: "|-damage|p2a: Milotic|80/100|[from] sandstorm"))
// b: sibling 保留 → 未分類の更なる低下でも 2 行出て、再保留されない
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Milotic"]?.hpText = "85/100"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 85, hpText: "85/100", force: true)
check("T153b held by sibling", suspectJump["oppB"]?.toPct == 85)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 7, hpText: "7/100", force: true)
check("T153b both lines emitted", battleLog.contains("|-damage|p2b: Tyranitar|85/100") && battleLog.contains("|-damage|p2b: Tyranitar|7/100") && suspectJump["oppB"] == nil)
// c: 保留 → ひんしでも保留分が先に出る
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Milotic"]?.hpText = "85/100"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 85, hpText: "85/100", force: true)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T153c held then faint", battleLog.contains("|-damage|p2b: Tyranitar|85/100") && battleLog.contains("|-damage|p2b: Tyranitar|0/100"))
// T154: あり得ない最大値の読みは状態に採用しない (幽霊行の防止)
resetAll()
if !speciesDict.contains(where: { $0.en == "Kingambit" }) { speciesDict.append(E("ドドゲザン", "Kingambit")) }
teamEntries["Kingambit"] = ["item": "Life Orb", "stats": ["hp": 177]]
lastSlots = ["mineA": SlotState(speciesEn: "Kingambit", hpPercent: 100, hpCur: 177, hpMax: 177)]
monStates["p1:Kingambit"] = MonState(); monStates["p1:Kingambit"]?.hpPercent = 100; monStates["p1:Kingambit"]?.hpText = "177/177"; monStates["p1:Kingambit"]?.hpMax = 177
emittedSwitchKeys.insert("p1:Kingambit")
emitLog("|turn|5")
processPlates(["mineA": SlotState(speciesEn: "Kingambit", hpPercent: 64, hpCur: 177, hpMax: 277)])
check("T154 implausible max dropped", lastSlots["mineA"]?.hpPercent == 100 && (monStates["p1:Kingambit"]?.hpText ?? "") == "177/177" && !battleLog.contains(where: { $0.contains("|-damage|") }))
// T155: ひんし文経路の分母は登録最大で統一される
resetAll()
if !speciesDict.contains(where: { $0.en == "Torkoal" }) { speciesDict.append(E("コータス", "Torkoal")) }
teamEntries["Torkoal"] = ["item": "Charcoal", "stats": ["hp": 177]]
lastSlots = ["mineB": SlotState(speciesEn: "Torkoal", hpPercent: 24, hpCur: 43, hpMax: 177)]
monStates["p1:Torkoal"] = MonState(); monStates["p1:Torkoal"]?.hpPercent = 24; monStates["p1:Torkoal"]?.hpText = "43/177"
lastEmittedPct["mineB"] = 24
emittedSwitchKeys.insert("p1:Torkoal")
_ = translateBattleMessage("コータスは たおれた！")
check("T155 faint denominator", battleLog.contains("|-damage|p1b: Torkoal|0/177"))
// T156: 同じ行動の外れ文は 1 行だけ
resetAll()
for (ja, en) in [("フシギバナ", "Venusaur"), ("バンギラス", "Tyranitar")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
moveNameOrig[normalize("リーフストーム")] = "リーフストーム"; moveJa2En["リーフストーム"] = "Leaf Storm"
lastSlots = ["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p1:Venusaur", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|1")
emitLog("|move|p1a: Venusaur|Leaf Storm")
lastMoveLabel = "p1a: Venusaur"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のバンギラスには当たらなかった！")
_ = translateBattleMessage("相手のバンギラスには当たらなかった！")
check("T156 miss not duplicated", battleLog.filter { $0.hasPrefix("|-miss|") }.count == 1)
// T157: 反動行の処理が次の技より遅れても [from] が付く
resetAll()
for (ja, en) in [("ムクホーク", "Staraptor"), ("ミロカロス", "Milotic"), ("フシギバナ", "Venusaur"), ("コータス", "Torkoal")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
moveNameOrig[normalize("ブレイブバード")] = "ブレイブバード"; moveJa2En["ブレイブバード"] = "Brave Bird"
moveNameOrig[normalize("ねっとう")] = "ねっとう"; moveJa2En["ねっとう"] = "Scald"
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Staraptor", hpPercent: 100),
             "mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100), "mineB": SlotState(speciesEn: "Torkoal", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Staraptor", "p1:Venusaur", "p1:Torkoal"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|4")
emitLog("|move|p2b: Staraptor|Brave Bird")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 100, toPct: 20, hpText: "20/100", force: true)
emitLog("|move|p2a: Milotic|Scald")
lastMoveLabel = "p2a: Milotic"; lastMoveMsgAt = Date()
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Staraptor", speciesEn: "Staraptor", fromPct: 100, toPct: 75, hpText: "75/100", force: true)
check("T157 late recoil classified", battleLog.contains("|-damage|p2b: Staraptor|75/100|[from] move: Brave Bird") && battleEvents.contains(where: { $0.contains("recoil") }))
// T158: 砂あらじの化け文でも天候チップとして消費され [from] が付く
resetAll()
if !speciesDict.contains(where: { $0.en == "Milotic" }) { speciesDict.append(E("ミロカロス", "Milotic")) }
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 86)]
monStates["p2:Milotic"] = MonState(); monStates["p2:Milotic"]?.hpPercent = 86; monStates["p2:Milotic"]?.hpText = "86/100"
emittedSwitchKeys.insert("p2:Milotic")
_ = translateBattleMessage("砂あらじが相手のミロカロスを襲う！")
check("T158 garbled sandstorm consumed", (pendingStatusFrom["p2:Milotic"]?.code ?? "") == "sandstorm" && !battleLog.contains(where: { $0.hasPrefix("|-message|") }))
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 86, toPct: 80, hpText: "80/100", force: true)
check("T158 chip line has from", battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm"))''',
    "T153-T158 tests")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
