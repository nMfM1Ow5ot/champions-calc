#!/usr/bin/env python3
# Harness update for the battle-end state write round: FUNCS
# addition and T165 tests (flag series, after T164).
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

rep("'writeManualStartResetState',",
    "'writeManualStartResetState', 'writeBattleEndState',",
    "FUNCS")

TESTS = '''// ===== T165 (battle end state.json write, flag series) =====
// a: 終了要求の取り込み後に state.json が書き出され、phase は idle
resetAll()
clearState164()
battleLog = ["|turn|1", "|move|p1a: Blastoise|Surf"]
battleArchived = false
battleArchiveId = "20261123_111415"
lastSlots["mineA"] = SlotState(speciesEn: "Blastoise", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 100)
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 0
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
if let obj = stateJson164() {
    check("T165a end writes state with idle phase", winLogged && (obj["battlePhase"] as? String) == "idle" && (obj["flagMode"] as? String) == "manual")
} else {
    check("T165a end writes state with idle phase", false)
}
// b: 場の情報が無い場合も、リセット形で phase が書き出される
resetAll()
clearState164()
battleLog = ["|turn|1"]
battleArchived = false
battleArchiveId = "20261123_111415"
lastSlots = [:]
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 0
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
if let obj = stateJson164() {
    check("T165b end writes the reset shape when the field is empty", (obj["battlePhase"] as? String) == "idle" && (obj["oppReset"] as? Bool) == true)
} else {
    check("T165b end writes the reset shape when the field is empty", false)
}
// c: 終了要求が増えていない場合は書き出されない
resetAll()
clearState164()
battleLog = ["|turn|1"]
battleArchived = false
lastSlots["mineA"] = SlotState(speciesEn: "Blastoise", hpPercent: 100)
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 1
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
check("T165c no end request, no write", stateJson164() == nil && !winLogged)

'''
ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT tests anchor: count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, TESTS + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
