#!/usr/bin/env python3
# make_harness.py: T138 for evidence-based header completion removal.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

TESTS = r'''
// ===== T138: header completion removes lowest-scored unused species =====
let hdrProto = ["|gametype|doubles",
                "|poke|p2|Absol", "|poke|p2|Delphox", "|poke|p2|Slowking-Galar", "|poke|p2|Arcanine", "|poke|p2|Sneasler", "|poke|p2|Kommo-o",
                "|start",
                "|switch|p2b: Absol|Absol|100/100",
                "|switch|p2a: Indeedee-F|Indeedee-F|100/100",
                "|switch|p2b: Armarouge|Armarouge|100/100",
                "|switch|p2a: Sneasler|Sneasler|100/100"]
let hdrScores: [String: Double] = ["p2:Delphox": 0.309, "p2:Slowking-Galar": 0.126, "p2:Arcanine": 0.146, "p2:Kommo-o": 0.332]
let hdrDone = completeArchiveHeader(protocolLines: hdrProto, displayLines: [], idScores: hdrScores)
check("T138a Kommo-o kept by score", hdrDone.protocolLines.contains("|poke|p2|Kommo-o"))
check("T138b lowest scores removed", hdrDone.removed.contains("p2:Slowking-Galar") && hdrDone.removed.contains("p2:Arcanine") && !hdrDone.removed.contains("p2:Kommo-o"))
check("T138c appeared species added", hdrDone.added.contains("p2:Indeedee-F") && hdrDone.added.contains("p2:Armarouge"))
let hdrDoneOld = completeArchiveHeader(protocolLines: hdrProto, displayLines: [])
check("T138d unscored falls back to suffix rule", hdrDoneOld.removed.contains("p2:Kommo-o"))
'''

old = """check("T137c in-battle intake when empty", battleMineTeam.compactMap { $0?.species }.count == 6)"""
if src.count(old) != 1:
    print("ABORT: anchor count", src.count(old))
    sys.exit(1)
src = src.replace(old, old + TESTS, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: T138 tests")
