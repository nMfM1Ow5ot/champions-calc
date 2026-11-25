#!/usr/bin/env python3
# Phase 3 steps 2+3:
# - Step 2: text evidence (send-out texts fast-confirm switches) and
#   candidate-aware announcement slots (announcedSlot).
# - Step 3: pullBackSwitchBlock splitMega — the switch part goes to the
#   previous turn's head, the mega sequence stays with the new turn
#   (verified truth: battle_20261122_091721 switch T5 head, mega T6 head).
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ================================================================ step 2
rep("S2a sendOutTextSeen global",
    "var pivotReturnAt: [String: Date] = [:]",
    "var pivotReturnAt: [String: Date] = [:]\n"
    "var sendOutTextSeen: [String: (species: String, at: Date)] = [:]  // side -> 繰り出し文で観測した入場種族 (フェーズ3: 文証拠)")

rep("S2b reset",
    "    heldTerrainReplace = nil; pivotReturnAt = [:]\n",
    "    heldTerrainReplace = nil; pivotReturnAt = [:]; sendOutTextSeen = [:]\n")

rep("S2c yuke hook",
    "        if lastSlots[\"mineA\"] != nil && lastSlots[\"mineB\"] != nil { return true }\n",
    """        if lastSlots["mineA"] != nil && lastSlots["mineB"] != nil {
            // 途中交代の繰り出し文は、プレート確定を早める文証拠として
            // 残す (フェーズ3)。枠そのものはプレート読みが決める
            if let e = findSpeciesJa(in: t) {
                let inOppOnly = oppTeamSeen.contains(e.en) && teamEntries[e.en] == nil
                    && !battleMineTeam.contains(where: { $0?.species == e.en })
                let evSide = inOppOnly ? "p2" : "p1"
                let onFieldNow = evSide == "p1"
                    ? (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en)
                    : (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en)
                if !onFieldNow { sendOutTextSeen[evSide] = (species: e.en, at: Date()) }
            }
            return true
        }
""")

rep("S2d confirmReads",
    "            let confirmReads = (pivotReturnAt[side].map { Date().timeIntervalSince($0) < 20 } ?? false) ? 1 : 2\n",
    """            // 交代技の戻り消費、または繰り出し文の文証拠がある場合は、
            // 後任を 1 回の読みで確定する
            let pivotFast = pivotReturnAt[side].map { Date().timeIntervalSince($0) < 20 } ?? false
            let textFast = sendOutTextSeen[side].map { $0.species == s.speciesEn && Date().timeIntervalSince($0.at) < 20 } ?? false
            let confirmReads = (pivotFast || textFast) ? 1 : 2
""")

rep("S2e consume text evidence",
    "                pendingSwitchCandidates[plate.name] = nil\n",
    "                pendingSwitchCandidates[plate.name] = nil\n"
    "                if sendOutTextSeen[side]?.species == s.speciesEn { sendOutTextSeen[side] = nil }\n")

rep("S2f announcedSlot helper",
    "func slotFor(side: String, speciesEn: String) -> String {",
    """// 告知文の帰属枠: 場にいればその枠。いない場合は、交代候補として
// 読まれている枠を既定枠 (a 枠) より優先する (フェーズ3: 候補を保持し、
// 既定枠への無言の帰属を避ける)
func announcedSlot(side: String, speciesEn: String) -> String {
    for (name, s) in lastSlots where (name.hasPrefix("mine") ? "p1" : "p2") == side && s.speciesEn == speciesEn {
        return slotId(name)
    }
    let plates = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
    let candPlates = plates.filter { pendingSwitchCandidates[$0]?[speciesEn] != nil }
    if candPlates.count == 1 { return slotId(candPlates[0]) }
    return slotFor(side: side, speciesEn: speciesEn)
}

func slotFor(side: String, speciesEn: String) -> String {""")

rep("S2g announcement slot",
    "    let slot = slotFor(side: side, speciesEn: sp.en)\n    let key = \"\\(side):\\(sp.en)\"\n    if monStates[key] == nil { monStates[key] = MonState() }\n    // ゴツゴツメット: 接触技で攻撃した側が受ける反動ダメージの予告。\n",
    "    let slot = announcedSlot(side: side, speciesEn: sp.en)\n    let key = \"\\(side):\\(sp.en)\"\n    if monStates[key] == nil { monStates[key] = MonState() }\n    // ゴツゴツメット: 接触技で攻撃した側が受ける反動ダメージの予告。\n")

# ================================================================ step 3
rep("S3a pullBack signature",
    "func pullBackSwitchBlock(label: String) -> (proto: [String], display: [String]) {",
    "func pullBackSwitchBlock(label: String, splitMega: Bool = false) -> (proto: [String], display: [String], protoHead: [String], displayHead: [String]) {")

rep("S3b pullBack partition",
    """    let pulled = idxs.map { battleLog[$0] }
    for i in idxs.reversed() { battleLog.remove(at: i) }
""",
    """    // メガ進化は、交代で入場したそのターンには起こらない (交代が
    // そのターンの行動を消費する)。検証済みの実像
    // (battle_20261122_091721: 交代はターン5頭、メガ行はターン6頭)
    // に合わせ、splitMega の場合はメガ一式 (石の持ち物行・
    // detailschange・-mega) を分離して返す。呼び手 (ターン行ガード)
    // が、交代側を前のターンの頭へ、メガ側を新しいターンの頭へ置く
    var headIdxs: [Int] = []
    var restIdxs = idxs
    if splitMega, let k = idxs.firstIndex(where: { battleLog[$0].hasPrefix("|detailschange|") || battleLog[$0].hasPrefix("|-mega|") }) {
        var start = k
        if k > 0, battleLog[idxs[k - 1]].hasPrefix("|-item|") { start = k - 1 }
        headIdxs = Array(idxs[..<start])
        restIdxs = Array(idxs[start...])
    }
    let pulled = restIdxs.map { battleLog[$0] }
    let pulledHead = headIdxs.map { battleLog[$0] }
    for i in idxs.reversed() { battleLog.remove(at: i) }
""")

rep("S3c pullBack display partition",
    """    let pulledDisplay = dispIdxs.map { displayLog[$0] }
    for i in dispIdxs.reversed() { displayLog.remove(at: i) }
    return (pulled, pulledDisplay)
""",
    """    var dispHeadIdxs: [Int] = []
    var dispRestIdxs = dispIdxs
    if !headIdxs.isEmpty {
        // 表示側も同じ分割にする: 石への反応とメガ進化の描画は新しい
        // ターン側、それ以外 (引き戻し・繰り出し・補完の被ダメ描画) は
        // 前のターン側
        dispRestIdxs = dispIdxs.filter { displayLog[$0].hasSuffix("is reacting to the Key Stone!") || displayLog[$0].contains("has Mega Evolved into") }
        dispHeadIdxs = dispIdxs.filter { !dispRestIdxs.contains($0) }
    }
    let pulledDisplay = dispRestIdxs.map { displayLog[$0] }
    let pulledDisplayHead = dispHeadIdxs.map { displayLog[$0] }
    for i in dispIdxs.reversed() { displayLog.remove(at: i) }
    return (pulled, pulledDisplay, pulledHead, pulledDisplayHead)
""")

rep("S3d guard caller",
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

rep("S3e guard insertion",
    """                emitLog("|turn|\\(n)")   // この呼び出しで追跡状態はリセットされる
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
""",
    """                emitLog("|turn|\\(n)")   // この呼び出しで追跡状態はリセットされる
                // 分離した交代側は、前のターンの頭 (直前のターン行の
                // 直後) へ戻す
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

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
