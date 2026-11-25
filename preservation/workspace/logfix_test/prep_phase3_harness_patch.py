#!/usr/bin/env python3
# Harness updates for Phase 3 steps 2+3:
# - FUNCS: announcedSlot
# - prelude: sendOutTextSeen global + resetAll; mirror the split
#   handling in the hand-written emitLog copy's turn-guard block
# - driver: T126b expectations -> split shape (verified golden truth);
#   new T130a/b (text evidence fast-confirm, announcedSlot)
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

rep("FUNCS announcedSlot",
    "'syncMineProvisional', 'mineTeamJSON', 'noteMineMove', 'mergeMineDetailFromCapture', 'mineProvisionalSpecies',",
    "'syncMineProvisional', 'mineTeamJSON', 'noteMineMove', 'mergeMineDetailFromCapture', 'mineProvisionalSpecies', 'announcedSlot',")

rep("prelude global",
    "var pivotReturnAt: [String: Date] = [:]\n",
    "var pivotReturnAt: [String: Date] = [:]\n"
    "var sendOutTextSeen: [String: (species: String, at: Date)] = [:]\n")

rep("resetAll",
    "    pendingSwitchCandidates = [:]\n",
    "    pendingSwitchCandidates = [:]\n    sendOutTextSeen = [:]\n")

rep("emitLog copy guard",
    """                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                if ruleC, let mover { (pulledProto, pulledDisplay) = pullBackSwitchBlock(label: mover) }
""",
    """                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                var pulledProtoHead: [String] = []
                var pulledDisplayHead: [String] = []
                if ruleC, let mover {
                    let pb = pullBackSwitchBlock(label: mover, splitMega: true)
                    pulledProto = pb.proto
                    pulledDisplay = pb.display
                    pulledProtoHead = pb.protoHead
                    pulledDisplayHead = pb.displayHead
                }
                let oldTurnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") })
                let oldTurnIdxD = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") })
""")

rep("emitLog copy insertion",
    """                emitLog("|turn|\\(n)")
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
""",
    """                emitLog("|turn|\\(n)")
                if !pulledProtoHead.isEmpty, let ti = oldTurnIdx {
                    battleLog.insert(contentsOf: pulledProtoHead, at: ti + 1)
                }
                if !pulledDisplayHead.isEmpty, let ti = oldTurnIdxD {
                    displayLog.insert(contentsOf: pulledDisplayHead, at: ti + 1)
                }
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
""")

# ---------------------------------------------------------------- T126b: verified-truth shape
rep("T126b protocol checks",
    'check("T126b switch block pulled after turn line", t7Pos >= 0 && swPos == t7Pos + 1 && megaPos > swPos && mvPos > megaPos)\n',
    'let t6Pos = battleLog.firstIndex(of: "|turn|6") ?? -1\n'
    'check("T126b switch pulled to old turn head", t6Pos >= 0 && swPos == t6Pos + 1)\n'
    'check("T126b mega block in new turn", t7Pos >= 0 && megaPos > t7Pos && mvPos > megaPos)\n')

rep("T126b display check",
    'check("T126b display block moved too", dHeal >= 0 && dBack == dHeal + 1 && dGo == dBack + 1 && dMega > dGo)\n',
    'check("T126b display split too", dBack >= 0 && dGo == dBack + 1 && dHeal == dGo + 1 && dMega > dHeal)\n')

# ---------------------------------------------------------------- driver T130
TESTS = r'''
// T130: 文証拠と候補優先の帰属 (フェーズ3)
// a: 繰り出し文の証拠があれば、交代は 1 回のプレート読みで確定する
resetAll()
currentTurn = 3
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 80)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p2:Floette"] = MonState(); monStates["p2:Floette"]?.hpPercent = 80
fieldSeen["p2"] = ["Floette"]
emittedSwitchKeys = ["p2:Floette", "p1:Gardevoir", "p1:Armarouge"]
sendOutTextSeen["p2"] = (species: "Gholdengo", at: Date())
processPlates(["oppB": SlotState(speciesEn: "Gholdengo", hpPercent: 100)])
check("T130a text evidence fast-confirms", battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })
check("T130a evidence consumed", sendOutTextSeen["p2"] == nil)

// b: 告知の帰属枠は、場にいない種族でも交代候補の枠を既定枠より優先する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Rillaboom", hpPercent: 90)
pendingSwitchCandidates["oppB"] = ["Gholdengo": (count: 1, firstSeen: Date(), lastSeen: Date())]
check("T130b candidate slot preferred", announcedSlot(side: "p2", speciesEn: "Gholdengo") == "p2b")
check("T130b on-field slot exact", announcedSlot(side: "p2", speciesEn: "Floette") == "p2a")
check("T130b default preserved", announcedSlot(side: "p2", speciesEn: "Dragapult") == "p2a")
'''
anchor = 'check("T129b no switch emitted", !battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })\n'
rep("driver T130", anchor, anchor + TESTS)

open(HPATH, "w", encoding="utf-8").write(src)
print("ALL HARNESS EDITS APPLIED")
