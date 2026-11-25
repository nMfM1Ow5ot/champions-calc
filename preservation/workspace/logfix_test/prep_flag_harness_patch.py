#!/usr/bin/env python3
# Harness support for the manual flag mode (T159): prelude globals,
# FUNCS additions, and the T159 tests appended after T158.
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

rep("var winLogged = false",
    "var winLogged = false\nvar inBattle = false\nvar flagManualMode = false\nvar flagStartSeqSeen = 0\nvar flagEndSeqSeen = 0\nvar flagControlAdopted = false",
    "prelude flag globals")

rep("'fieldLineWithAttribution', 'isMoveListText', 'headerDistinctMargin', 'maxReadPlausible',",
    "'fieldLineWithAttribution', 'isMoveListText', 'headerDistinctMargin', 'maxReadPlausible', 'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment',",
    "FUNCS flag functions")

rep('''check("T158 chip line has from", battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm"))''',
    '''check("T158 chip line has from", battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm"))
// T159 (手動フラグモード): 制御の取り込みと自動オンの抑止
// a: 起動後の最初の取り込みは連番を採用するだけで実行しない
resetAll()
flagManualMode = false; flagStartSeqSeen = 0; flagEndSeqSeen = 0; flagControlAdopted = false; logStarted = false; inBattle = false
applyFlagControl(mode: "manual", startSeq: 5, endSeq: 2)
check("T159a adoption only", flagControlAdopted && flagManualMode && !logStarted && flagStartSeqSeen == 5 && flagEndSeqSeen == 2)
// b: 開始要求で開始し、phase が inBattle になる
applyFlagControl(mode: "manual", startSeq: 6, endSeq: 2)
check("T159b manual start", logStarted && inBattle && flagPhase() == "inBattle" && flagModeName() == "manual")
// c: 開始済みへの開始要求は再開始しない (冪等)
let logCount159 = battleLog.count
applyFlagControl(mode: "manual", startSeq: 7, endSeq: 2)
check("T159c duplicate start ignored", battleLog.count == logCount159 && flagStartSeqSeen == 7)
// d: 終了要求でフラグが立ち phase が idle に戻る
applyFlagControl(mode: "manual", startSeq: 7, endSeq: 3)
check("T159d manual end", winLogged && !inBattle && flagPhase() == "idle")
// e: auto モードでは要求を実行しない
resetAll()
flagManualMode = true; flagStartSeqSeen = 0; flagEndSeqSeen = 0; flagControlAdopted = false; logStarted = false; inBattle = false
applyFlagControl(mode: "auto", startSeq: 1, endSeq: 0)
applyFlagControl(mode: "auto", startSeq: 2, endSeq: 0)
check("T159e auto ignores requests", !flagManualMode && !logStarted && flagStartSeqSeen == 2)
// f: 手動モードでは勝敗文でフラグが立たない (行は残る)
resetAll()
flagManualMode = true; winLogged = false
_ = translateBattleMessage("Kiwiとの勝負に勝った！")
check("T159f win line without flag", battleLog.contains("|win|Ren") && !winLogged)
// g: 自動モードでは従来どおりフラグが立つ
resetAll()
flagManualMode = false; winLogged = false
_ = translateBattleMessage("Kiwiとの勝負に勝った！")
check("T159g auto win sets flag", winLogged)
// h: state.json に battlePhase / flagMode が載る
resetAll()
flagManualMode = true
if !speciesDict.contains(where: { $0.en == "Milotic" }) { speciesDict.append(E("ミロカロス", "Milotic")) }
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 66)]
monStates["p2:Milotic"] = MonState(); monStates["p2:Milotic"]?.hpPercent = 66; monStates["p2:Milotic"]?.hpText = "66/100"
writeState()
let stFlag = (try? String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)) ?? ""
check("T159h state carries flag", stFlag.contains("\\"battlePhase\\": \\"inBattle\\"") && stFlag.contains("\\"flagMode\\": \\"manual\\""))''',
    "T159 tests")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
