#!/usr/bin/env python3
# Harness support for the battle_20261123_060833 fix round (T152a-e):
# - FUNCS: extract headerDistinctMargin
# - prelude: pendingAbilityReveal global + resetAll clear
# - driver: append T152a-e after T151e
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

rep("'fieldLineWithAttribution', 'isMoveListText',",
    "'fieldLineWithAttribution', 'isMoveListText', 'headerDistinctMargin',",
    "FUNCS")

rep("var critEventMarks: [String: (turn: Int, atk: String)] = [:]",
    "var critEventMarks: [String: (turn: Int, atk: String)] = [:]\nvar pendingAbilityReveal: [String: String] = [:]",
    "prelude global")

rep("    critEventMarks = [:]",
    "    critEventMarks = [:]\n    pendingAbilityReveal = [:]",
    "resetAll clear")

rep('''check("T151e no attribution when set by move", battleLog.contains("|-weather|Rain Dance") && !battleLog.contains("|-weather|Rain Dance|[from]"))''',
    '''check("T151e no attribution when set by move", battleLog.contains("|-weather|Rain Dance") && !battleLog.contains("|-weather|Rain Dance|[from]"))
// T152 (battle_20261123_060833): TR 補完 / ひんし同種族の誤帰属 / Overlord / マージン / 形状判定
// a: 開始文の主語から技行を補い、告知済みなら二重化しない
resetAll()
if !speciesDict.contains(where: { $0.en == "Farigiraf" }) { speciesDict.append(E("リキキリン", "Farigiraf")) }
lastSlots = ["oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100)]
monStates["p2:Farigiraf"] = MonState()
emitLog("|turn|1")
_ = checkFieldText(text: "相手のリキキリンは時空をゆがめた！")
check("T152a trick room move synthesized", battleLog.contains("|move|p2a: Farigiraf|Trick Room") && battleLog.contains("|-fieldstart|move: Trick Room") && battleLog.firstIndex(of: "|move|p2a: Farigiraf|Trick Room")! < battleLog.firstIndex(of: "|-fieldstart|move: Trick Room")!)
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100)]
monStates["p2:Farigiraf"] = MonState()
emitLog("|turn|1")
emitLog("|move|p2a: Farigiraf|Trick Room")
_ = checkFieldText(text: "相手のリキキリンは時空をゆがめた！")
check("T152a no duplicate when announced", battleLog.filter { $0 == "|move|p2a: Farigiraf|Trick Room" }.count == 1)
// b: 倒れた相手の同種族が枠に残っていても、自軍への低下が相手へ付かない
resetAll()
for (ja, en) in [("マフォクシー", "Delphox"), ("コータス", "Torkoal")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37),
             "mineB": SlotState(speciesEn: "Farigiraf", hpPercent: 0),
             "oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100),
             "oppB": SlotState(speciesEn: "Torkoal", hpPercent: 0)]
monStates["p1:Delphox"] = MonState(); monStates["p2:Torkoal"] = MonState()
faintedSpecies = ["p2:Torkoal", "p1:Farigiraf"]
emittedSwitchKeys = ["p1:Delphox", "p2:Farigiraf", "p2:Torkoal"]
teamEntries["Delphox"] = ["item": "Delphoxite"]
lastMoveLabel = "p1a: Delphox"; lastMoveMsgAt = Date()
_ = translateBattleMessage("マフォクシーとコータスのこうげきが下がった！")
check("T152b fainted namesake not used", !battleLog.contains("|-unboost|p2b: Torkoal|atk|1"))
recordSwitchIn(side: "p1", slot: "p1b", speciesEn: "Torkoal")
check("T152b boost lands on mine after switch-in", battleLog.contains("|-unboost|p1b: Torkoal|atk|1"))
// c: そうだいしょうの定型文は交代確定まで保留され、確定時に流れる (語順崩れでも)
resetAll()
if !speciesDict.contains(where: { $0.en == "Kingambit" }) { speciesDict.append(E("ドドゲザン", "Kingambit")) }
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37), "mineB": SlotState(speciesEn: "Torkoal", hpPercent: 100)]
fieldSeen["p1"] = ["Delphox", "Torkoal", "Kingambit"]
_ = translateBattleMessage("ドドゲザンは倒された仲間から力をもらった！")
check("T152c overlord held before switch-in", !battleLog.contains(where: { $0.contains("Supreme Overlord") }) && pendingAbilityReveal["p1:Kingambit"] == "Supreme Overlord")
recordSwitchIn(side: "p1", slot: "p1a", speciesEn: "Kingambit")
check("T152c overlord emitted at switch-in", battleLog.contains("|-ability|p1a: Kingambit|Supreme Overlord"))
resetAll()
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37)]
fieldSeen["p1"] = ["Delphox", "Kingambit"]
_ = translateBattleMessage("ドドゲザンはもらった！仲間から倒された力を")
check("T152c scrambled text also held", pendingAbilityReveal["p1:Kingambit"] == "Supreme Overlord")
// d: マージンは同種族のフォルム差を飛ばして別種族との差を取る
check("T152d forme margin skipped", headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114), ("Garchomp", 0.300)]) != nil && abs(headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114), ("Garchomp", 0.300)])! - 0.200) < 0.0001)
check("T152d distinct margin plain", headerDistinctMargin(ranked: [("Sneasler", 0.050), ("Garchomp", 0.090)]) != nil && abs(headerDistinctMargin(ranked: [("Sneasler", 0.050), ("Garchomp", 0.090)])! - 0.040) < 0.0001)
check("T152d no distinct rival", headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114)]) == nil)
// e: 漢字能力名の化け断片でも形状として消費される
check("T152e garbled stat shape", isBoostShapedText("マフォクシーとコータスの政撃が下がった！"))''',
    "T152 tests")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
