#!/usr/bin/env python3
# Harness update for the delayed-print round: FUNCS additions,
# prelude global, resetAll clear, T162 tests.
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

rep("'safetyNetDraftDue',",
    "'safetyNetDraftDue', 'confirmedDisplayCount', 'takeDisplayPrintLines', 'flushDisplayPrint',",
    "FUNCS")
rep('''var displayLog: [String] = []''',
    '''var displayLog: [String] = []
var displayPrintedCount = 0''',
    "prelude global")
rep('''displayLog = []''',
    '''displayLog = []; displayPrintedCount = 0''',
    "resetAll clear")

TESTS = '''// ===== T162 (delayed print, plan 2) =====
// a: 確定境界は最後の Turn 見出しの位置。現在の区間は印刷されない
resetAll()
displayLog = ["you and Opponent joined", "Your team:", "Venusaur / Torkoal", "Turn 1", "Go! Venusaur!", "Go! Torkoal!"]
var printed162: [String] = []
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a only the header prints before Turn 2", printed162 == ["you and Opponent joined", "Your team:", "Venusaur / Torkoal"])
displayLog.append("The opposing Excadrill used Protect!")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a current segment stays unprinted", printed162.count == 3)
displayLog.append("Turn 2")
displayLog.append("Go! Kingambit!")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a previous segment prints when the next heading lands", printed162 == Array(displayLog[0..<7]) && printed162.count == 7)
// b: 現在の区間への差し込みは、区間が閉じるまで印刷されず、閉じた後は差し込み位置どおりに出る
let before162 = printed162
displayLog.insert("The opposing Milotic was burned!", at: 8)
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162b insertion in the current segment is not printed early", printed162 == before162)
displayLog.append("Turn 3")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162b inserted line prints in its final position", printed162 == Array(displayLog[0..<printed162.count]) && printed162[8] == "The opposing Milotic was burned!")
// c: pullback の後でも印刷済み接頭辞は崩れない
resetAll()
battleLog = ["|turn|2", "|move|p2a: Excadrill|Protect", "|switch|p2b: Milotic|Milotic|100/100"]
displayLog = ["Turn 1", "Go! Excadrill!", "Turn 2", "The opposing Excadrill used Protect!", "Opponent sent out Milotic!"]
printed162 = takeDisplayPrintLines(isFinal: false)
check("T162c prints up to the current heading", printed162 == ["Turn 1", "Go! Excadrill!"])
let pb162 = pullBackSwitchBlock(label: "p2b: Milotic")
if !pb162.display.isEmpty, let ti = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) {
    displayLog.insert(contentsOf: pb162.display, at: ti + 1)
}
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162c pullback keeps the printed prefix intact", printed162 == Array(displayLog[0..<printed162.count]))
// d: 最終フラッシュで全文が一致する
printed162 += takeDisplayPrintLines(isFinal: true)
check("T162d final flush matches the whole log", printed162 == displayLog && displayPrintedCount == displayLog.count)
// e: 印刷カウンタは後退しない
let cnt162 = displayPrintedCount
_ = takeDisplayPrintLines(isFinal: false)
check("T162e print counter never retreats", displayPrintedCount == cnt162)

'''
ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT tests anchor: count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, TESTS + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
