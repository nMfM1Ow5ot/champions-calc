#!/usr/bin/env python3
# make_harness.py: fixture entry for Floette-Eternal + T142
# (ability guard accepts the Fairy Aura line with corrected data).
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

_anchor = """speciesAbilityMap["Indeedee-F"] = ["Synchronize", "Psychic Surge"]"""
_i = src.rfind(_anchor)
if _i < 0:
    print("ABORT: fixture anchor not found")
    sys.exit(1)
src = src[:_i] + _anchor + """
speciesAbilityMap["Floette-Eternal"] = ["Fairy Aura"]
speciesAbilityMap["Floette"] = ["Flower Veil", "Symbiosis"]""" + src[_i + len(_anchor):]
print("OK: fixture")

TESTS = r'''
// ===== T142: Floette-Eternal の Fairy Aura (battle_20261122_201011) =====
check("T142a Fairy Aura line is plausible for Floette-Eternal", abilityLinePlausible("|-ability|p2b: Floette-Eternal|Fairy Aura"))
resetAll()
currentTurn = 1
emitLog("|-ability|p2b: Floette-Eternal|Fairy Aura")
check("T142b the aura line reaches the log", battleLog.contains("|-ability|p2b: Floette-Eternal|Fairy Aura"))
'''

lines = src.split("\n")
for i, line in enumerate(lines):
    if 'out(failures == 0 ? "ALL PASS"' in line:
        lines[i:i] = [TESTS]
        break
else:
    print("ABORT: ALL PASS anchor not found")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T142 block")
