#!/usr/bin/env python3
# Harness support for the safety-net suspension (T160): prelude
# globals, a FUNCS addition, and the T160 tests after T159.
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

rep("var battleArchived = false",
    "var battleArchived = false\nvar emptyBattleFrames = 0\nvar lastArchiveSnapshotCount = -1\nvar lastLogEventAt = Date.distantPast\nvar safetyNetDraftEnabled = false",
    "prelude safety-net globals")

rep("'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment',",
    "'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment', 'safetyNetDraftDue',",
    "FUNCS safetyNetDraftDue")

rep('''check("T159h state carries flag", stFlag.contains("\\"battlePhase\\": \\"inBattle\\"") && stFlag.contains("\\"flagMode\\": \\"manual\\""))''',
    '''check("T159h state carries flag", stFlag.contains("\\"battlePhase\\": \\"inBattle\\"") && stFlag.contains("\\"flagMode\\": \\"manual\\""))
// T160 (安全網の下書き保存の無効化): 条件が揃ってもスイッチが
// 切れていれば due にならない。スイッチを入れれば従来どおり
resetAll()
battleLog = ["|gametype|doubles", "|start"]
battleArchived = false; winLogged = false
emptyBattleFrames = 31
lastLogEventAt = Date().addingTimeInterval(-100)
lastArchiveSnapshotCount = -1
safetyNetDraftEnabled = false
check("T160a suspended stays not due", !safetyNetDraftDue())
safetyNetDraftEnabled = true
check("T160b enabled becomes due", safetyNetDraftDue())
winLogged = true
check("T160c win settled stays not due", !safetyNetDraftDue())
winLogged = false; emptyBattleFrames = 10
check("T160d frames short stays not due", !safetyNetDraftDue())
safetyNetDraftEnabled = false''',
    "T160 tests")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
