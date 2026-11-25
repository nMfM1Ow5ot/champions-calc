#!/usr/bin/env python3
# make_harness.py: T137 for the mineProvisional wipe guard.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T137: provisional list is not wiped by an empty preview reset =====
resetAll()
minePreviewTeam = ["Charizard", "Venusaur", "Garchomp", "Incineroar", "Sylveon", "Farigiraf"]
minePreviewDetails = []
syncMineProvisional()
check("T137a provisional applied", battleMineTeam.compactMap { $0?.species }.count == 6)
minePreviewTeam = []
syncMineProvisional()
check("T137b empty reset does not wipe", battleMineTeam.compactMap { $0?.species }.count == 6)
// in-battle first intake still works when the list is empty
battleMineTeam = []
minePreviewTeam = ["Charizard", "Venusaur", "Garchomp", "Incineroar", "Sylveon", "Farigiraf"]
syncMineProvisional()
check("T137c in-battle intake when empty", battleMineTeam.compactMap { $0?.species }.count == 6)
'''

old = """check("T136e pull-back still fires in early segment", !pbEarly.proto.isEmpty)"""
if src.count(old) != 1:
    print("ABORT: anchor count", src.count(old))
    sys.exit(1)
src = src.replace(old, old + TESTS, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T137 tests")
