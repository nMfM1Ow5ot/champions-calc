#!/usr/bin/env python3
# Harness updates for Phase 4 (turn side):
# - prelude: lastRoundEventAt global; mirror the turn-0 move-only rule
#   and the lastRoundEventAt update in the emitLog copy
# - driver: T131 (091721 opening-sequence reproduction)
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
    "var sendOutTextSeen: [String: (species: String, at: Date)] = [:]\n",
    "var sendOutTextSeen: [String: (species: String, at: Date)] = [:]\n"
    "var lastRoundEventAt: Date? = nil\n")

rep("copy turn-0 rule",
    "            if currentTurn == 0 && !roundEventSeen { guardN = 1 }\n",
    "            if currentTurn == 0 && mover != nil { guardN = 1 }\n")

rep("copy lastRoundEventAt",
    "            roundEventSeen = true\n",
    "            roundEventSeen = true\n            lastRoundEventAt = Date()\n")

TESTS = r'''
// T131: 開幕区間では入場効果のラウンド行でターン行を出さない (フェーズ4、
// battle_20261122_091721 の +1 の再現: debug02 は いかく の低下行で
// |turn|1 を挿入していた)
resetAll()
currentTurn = 0
battleLog = []
displayLog = []
roundEventSeen = false
movesSinceTurnLine = []
enteredThisSegment = []
emitLog("|-unboost|p1a: Politoed|atk|1")
check("T131a entry unboost makes no turn line", !battleLog.contains { $0.hasPrefix("|turn|") } && currentTurn == 0)
emitLog("|-boost|p2b: Overqwil|def|1")
check("T131b entry boost makes no turn line", !battleLog.contains { $0.hasPrefix("|turn|") } && currentTurn == 0)
emitLog("|move|p2a: Sableye|Fake Out")
check("T131c first move inserts turn 1", battleLog.firstIndex(of: "|turn|1") != nil && (battleLog.firstIndex(of: "|turn|1") ?? 99) < (battleLog.firstIndex(of: "|move|p2a: Sableye|Fake Out") ?? -1) && currentTurn == 1)
check("T131d exactly one turn line", battleLog.filter { $0.hasPrefix("|turn|") }.count == 1)
'''
anchor = 'check("T130b default preserved", announcedSlot(side: "p2", speciesEn: "Dragapult") == "p2a")\n'
rep("driver T131", anchor, anchor + TESTS)

open(HPATH, "w", encoding="utf-8").write(src)
print("ALL HARNESS EDITS APPLIED")
