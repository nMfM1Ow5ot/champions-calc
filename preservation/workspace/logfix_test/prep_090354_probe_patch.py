#!/usr/bin/env python3
# Probe (observation only): current behavior for the 090354 texts.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()
orig = src

ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
PROBE = '''// ===== PROBE 090354 (observation only) =====
speciesDict.append(E("バンギラス", "Tyranitar"))
speciesDict.append(E("メガバンギラス", "Tyranitar-Mega"))
speciesDict.append(E("ヤバソチャ", "Sinistcha"))
speciesDict.append(E("ドドゲザン", "Kingambit"))
speciesAbilityMap["Tyranitar"] = ["Sand Stream"]
speciesAbilityMap["Tyranitar-Mega"] = ["Sand Stream"]
speciesAbilityMap["Sinistcha"] = ["Hospitality"]
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
speciesAbilityMap["Torkoal"] = ["Drought", "White Smoke", "Shell Armor"]
// P1: garbled Tyranitar burn text (mega on field)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 1)
lastSlots["oppB"] = SlotState(speciesEn: "Tyranitar-Mega", hpPercent: 89)
monStates["p2:Tyranitar-Mega"] = MonState()
let p1a = translateBattleMessage("相手のメバンギラスはやけどを負った！")
let p1b = p1a ? true : salvageFromText("相手のメバンギラスはやけどを負った！")
print("PROBE1 translate=\\(p1a) salvage=\\(p1b) log=\\(battleLog)")
// P2: garbled Milotic burn text
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Milotic", hpPercent: 68)
monStates["p2:Milotic"] = MonState()
let p2a = translateBattleMessage("相手の三口カロスはやけどを負った！")
let p2b = p2a ? true : salvageFromText("相手の三口カロスはやけどを負った！")
print("PROBE2 translate=\\(p2a) salvage=\\(p2b) log=\\(battleLog)")
// P3: Sinistcha burn fragment
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 17)
monStates["p2:Sinistcha"] = MonState()
let p3a = translateBattleMessage("ヤバソチャは負った！")
let p3b = p3a ? true : salvageFromText("ヤバソチャは負った！")
print("PROBE3 translate=\\(p3a) salvage=\\(p3b) log=\\(battleLog)")
// P3b: Sinistcha burn fuller garble (obs f507 word order)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 17)
monStates["p2:Sinistcha"] = MonState()
let p3c = translateBattleMessage("ヤバソチャは相手の負つた！やけどを")
let p3d = p3c ? true : salvageFromText("ヤバソチャは相手の負つた！やけどを")
print("PROBE3b translate=\\(p3c) salvage=\\(p3d) log=\\(battleLog)")
// P4: Hospitality tea text (garbled join)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Milotic", hpPercent: 62)
monStates["p2:Sinistcha"] = MonState()
monStates["p2:Milotic"] = MonState()
let p4a = translateBattleMessage("たてた相手のヤバソチャがたてたお茶をミロカロスは飲みほした！")
let p4b = p4a ? true : salvageFromText("たてた相手のヤバソチャがたてたお茶をミロカロスは飲みほした！")
print("PROBE4 translate=\\(p4a) salvage=\\(p4b) log=\\(battleLog)")
// P5: win text twice in manual mode
resetAll()
flagManualMode = true
let p5a = translateBattleMessage("くさとの勝負に勝った！")
let p5b = translateBattleMessage("くさとの勝負に勝った！")
print("PROBE5 manual win x2: \\(p5a) \\(p5b) wins=\\(battleLog.filter { $0.hasPrefix("|win|") }.count) log=\\(battleLog)")
flagManualMode = false
// P5b: forfeit text twice in manual mode
resetAll()
flagManualMode = true
trainerOpp = "くさ"
let p5c = translateBattleMessage("相手のくさは勝負をあきらめた！")
let p5d = translateBattleMessage("相手のくさは勝負をあきらめた！")
print("PROBE5b manual forfeit x2: \\(p5c) \\(p5d) wins=\\(battleLog.filter { $0.hasPrefix("|win|") }.count)")
flagManualMode = false
// ===== END PROBE =====

'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT: anchor count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, PROBE + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
