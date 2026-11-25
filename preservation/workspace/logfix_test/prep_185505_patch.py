#!/usr/bin/env python3
# reader.swift fixes for battle_20261122_185505 (build 20261122_1825):
# H1 (high 1): move announcements lost when the delivered text has
#   trailing junk after the "!" (recording overlay) or a "・" before
#   the move name, and the in-text fallback scan required the mover
#   to be a current plate occupant.
# H2 (high 3): HP lines (heals/damage) for a species already
#   recorded fainted were re-emitted from stale plate reads.
# H3 (high 2): the switch pull-back fired into an already developed
#   turn segment (turn-line lag), dragging the switch and the
#   following events into the previous turn.
import re
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

# ---- H1: announcement branch head + bang-cut locals ----
rep("H1 head",
    """    if (t.hasSuffix("！") || t.hasSuffix("!")) && !t.contains("たおれた") && !foldDakuten(t).contains("たおれた") {""",
    """    if let bangIdx = t.firstIndex(where: { $0 == "！" || $0 == "!" }),
       !String(t[...bangIdx]).contains("たおれた"), !foldDakuten(String(t[...bangIdx])).contains("たおれた") {
        // 告知文は最初の「！」までで切って扱う。文の後ろに録画表示
        // などの別要素の文字が続いた delivery では、末尾チェックが
        // 外れて技行が丸ごと落ちた (実例: 2026-11-22
        // battle_20261122_185505、「ムービー収録 リザードンの
        // ねっぷう！ 0 KB」で Charizard の Heat Wave が欠落)
        let at = String(t[...bangIdx])
        let ant = normalize(at)""")

# ---- H1: within the announcement branch, nt -> ant ----
start_marker = "    // 技の使用: 「(相手の) <種族>の <技>！」"
end_marker = "applyMoveField(mvJa, side: side)"
si = src.index(start_marker)
ei = src.index(end_marker, si)
# extend to the end of the "return true" line after the end marker
ri = src.index("return true", ei)
line_end = src.index("\n", ri)
block = src[si:line_end]
new_block, n = re.subn(r"\bnt\b", "ant", block)
if n < 5:
    print(f"ABORT: H1 nt->ant replacements = {n}")
    sys.exit(1)
src = src[:si] + new_block + src[line_end:]
print(f"OK: H1 branch nt->ant ({n} replacements)")

# ---- H1: candidate trim also strips a leading/trailing "・" ----
rep("H1 cand trim",
    """            let c = cand.trimmingCharacters(in: CharacterSet(charactersIn: "！!"))""",
    """            let c = cand.trimmingCharacters(in: CharacterSet(charactersIn: "！!・"))""")

# ---- H1: fallback scan also accepts species that entered this battle ----
rep("H1 onField widening",
    """            let onField = lastSlots.values.contains { $0.speciesEn == sp.en }
                || formeGroup(sp).contains { g in lastSlots.values.contains { $0.speciesEn == g.en } }""",
    """            let onField = lastSlots.values.contains { $0.speciesEn == sp.en }
                || formeGroup(sp).contains { g in lastSlots.values.contains { $0.speciesEn == g.en } }
                || (fieldSeen[side]?.contains { sameSpeciesFamily($0, sp.en) } ?? false)""")

# ---- H2: suppress HP lines for already-fainted species ----
rep("H2 post-faint suppression",
    """        if sj.toPct < effFrom, sj.toPct != 0 { clearedDropSuspect = true }
        suspectJump[plateName] = nil
    }
    if toPct < effFrom {""",
    """        if sj.toPct < effFrom, sj.toPct != 0 { clearedDropSuspect = true }
        suspectJump[plateName] = nil
    }
    // ひんし行が出た種族への HP 変動行は出さない。ひんし後に同じ
    // 枠へ残った古い読みが、回復や被ダメとして再演される事故の
    // 防止 (交代で戻れば faintedSpecies から外れるため、正規の
    // 再登場には影響しない。実例: 2026-11-22
    // battle_20261122_185505、ひんし済みの Garchomp に 36/185 の
    // 幻回復が 2 回と、2 回目のひんし行が出た)
    if faintedSpecies.contains(key) {
        debugCapture(kind: "faint_guard", key: "post_faint_line:\\(key)", rawText: "",
                     detail: ["reason": "post_faint_suppressed", "slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "turn": currentTurn])
        return true
    }
    if toPct < effFrom {""")

# ---- H2: revival paths also retract the fainted-species mark ----
rep("H2 revival A retracts",
    """                        faintedSlots.removeValue(forKey: slot)
                        faintReviveCount[plate.name] = nil""",
    """                        faintedSlots.removeValue(forKey: slot)
                        faintedSpecies.remove(key)
                        faintReviveCount[plate.name] = nil""")
rep("H2 revival B retracts",
    """               Date().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                lastEmittedPct[plate.name] = s.hpPercent
                debugCapture(kind: "faint_guard", key: "faint_revived:\\(slot):\\(s.speciesEn)", rawText: "",
                             detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
            }""",
    """               Date().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                lastEmittedPct[plate.name] = s.hpPercent
                faintedSpecies.remove(key)
                debugCapture(kind: "faint_guard", key: "faint_revived:\\(slot):\\(s.speciesEn)", rawText: "",
                             detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
            }""")

# ---- H3: developed-segment guard for the confirm-path pull-back ----
rep("H3 signature",
    """func pullBackSwitchBlock(label: String, splitMega: Bool = false) -> (proto: [String], display: [String], protoHead: [String], displayHead: [String]) {
    guard let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) else { return ([], [], [], []) }""",
    """func pullBackSwitchBlock(label: String, splitMega: Bool = false, requireEarlySegment: Bool = false) -> (proto: [String], display: [String], protoHead: [String], displayHead: [String]) {
    guard let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) else { return ([], [], [], []) }
    if requireEarlySegment {
        // 確定経路からの引き戻しは、そのターンの序盤の区間にだけ
        // 適用する。ひんし行がある、または技行が 3 件以上ある
        // 発達した区間では、ターン行の検出遅れで前ターンの区間と
        // 混ざっている可能性が高く、引き戻すと交代とその後の
        // 出来事まで前ターン側へ連れていかれる (実例: 2026-11-22
        // battle_20261122_185505、実ターン 3 の Sylveon の交代と
        // 被ダメがターン 2 冒頭へ引き戻された)
        var segMoves = 0, segFaints = 0
        for l in battleLog[(turnIdx + 1)...] {
            if l.hasPrefix("|move|") { segMoves += 1 }
            if l.hasPrefix("|faint|") { segFaints += 1 }
        }
        if segFaints >= 1 || segMoves >= 3 { return ([], [], [], []) }
    }""")
rep("H3 confirm caller",
    """                            let pulled = pullBackSwitchBlock(label: "\\(slot): \\(s.speciesEn)")""",
    """                            let pulled = pullBackSwitchBlock(label: "\\(slot): \\(s.speciesEn)", requireEarlySegment: true)""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
