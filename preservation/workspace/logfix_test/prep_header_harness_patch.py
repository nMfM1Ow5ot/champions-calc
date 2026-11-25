#!/usr/bin/env python3
# Harness update for the header-completion round: FUNCS additions,
# prelude globals, resetAll clears, T163 tests.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count = {n} (expected {count})")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

rep("'confirmedDisplayCount', 'takeDisplayPrintLines', 'flushDisplayPrint',",
    "'confirmedDisplayCount', 'takeDisplayPrintLines', 'flushDisplayPrint', 'completeDisplayHeader', 'refreshHeaderState',",
    "FUNCS")
rep('''var displayPrintedCount = 0''',
    '''var displayPrintedCount = 0
var headerPrintReady = false
var headerLineCount = 0''',
    "prelude globals")
rep('''logFieldWeather = ""; logFieldTerrain = ""; winLogged = false; logStarted = true''',
    '''logFieldWeather = ""; logFieldTerrain = ""; winLogged = false; logStarted = true; headerPrintReady = false; headerLineCount = 0; displayPrintedCount = 0''',
    "resetAll clears")

TESTS = '''// ===== T163 (header completion gating) =====
func headerFixture163() -> [String] {
    return ["you and Opponent joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg M-C", "Rated battle",
            "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
            "Your team:", "Venusaur / Torkoal / Garchomp / Delphox / Farigiraf / Kingambit",
            "Opponent's team:", "Excadrill / Tyranitar / Milotic / Sinistcha", "",
            "Battle started between you and Opponent!", ""]
}
// a: 判明前はヘッダーも後続も印刷されない
resetAll()
displayLog = headerFixture163()
headerLineCount = displayLog.count
trainerOpp = ""
oppTeamSeen = ["Excadrill", "Tyranitar", "Milotic", "Sinistcha"]
previewHandled = false
displayLog.append("Turn 1")
displayLog.append("Go! Venusaur!")
check("T163a nothing prints before identification completes", takeDisplayPrintLines(isFinal: false).isEmpty && displayPrintedCount == 0)
// b: 2条件がそろった時点で完成形に書き直され、印刷範囲に入る
trainerOpp = "くさ"
oppTeamSeen = ["Excadrill", "Tyranitar", "Milotic", "Sinistcha", "Staraptor", "Gholdengo"]
refreshHeaderState()
check("T163b header rewritten in completed form", displayLog[0] == "Ren and くさ joined" && displayLog[8] == "くさ's team:" && displayLog[9] == "Excadrill / Tyranitar / Milotic / Sinistcha / Staraptor / Gholdengo" && displayLog[11] == "Battle started between Ren and くさ!")
check("T163b header released to the printer", headerPrintReady && displayPrintedCount == headerLineCount)
// c: 同定終了時の例外 — そろっている分で完成する
resetAll()
displayLog = headerFixture163()
headerLineCount = displayLog.count
trainerOpp = ""
oppTeamSeen = ["Excadrill", "Tyranitar"]
previewHandled = true
refreshHeaderState()
check("T163c partial header completes at identification end", headerPrintReady && displayLog[9] == "Excadrill / Tyranitar" && displayLog[0] == "Ren and Opponent joined")
// d: 最終フラッシュで全文が一致する
displayLog.append("Turn 1")
let rest163 = takeDisplayPrintLines(isFinal: true)
check("T163d final flush matches the whole log", displayPrintedCount == displayLog.count && rest163.count == 1)

'''
ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT tests anchor: count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, TESTS + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
