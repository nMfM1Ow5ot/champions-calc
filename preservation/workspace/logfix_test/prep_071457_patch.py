#!/usr/bin/env python3
"""battle_20261122_071457 の reader 側修正 6 件。
使い方: python3 prep_071457_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH).read()
EDITS = []

# 0. ビルドスタンプ
import re
m = re.search(r'let readerBuild = "\d{8}_\d{4}"', src)
print("current build stamp:", m.group(0) if m else None)
EDITS.append((m.group(0), 'let readerBuild = "20261122_0801"'))

# 1. トリックルーム開始文の濁点崩れ (ゆかめた) を拾う
EDITS.append((
"""    // トリックルーム (地形・天候とは別枠のフィールド効果)
    if text.contains("時空") && (text.contains("ゆがめ") || text.contains("歪め")) {""",
"""    // トリックルーム (地形・天候とは別枠のフィールド効果)。開始文の
    // 濁点崩れ (ゆがめた -> ゆかめた) も拾う (実例: 2026-11-22
    // battle_20261122_071457、開始行が出ず告知文が未翻訳で残った)
    if text.contains("時空") && (foldDakuten(text).contains("ゆかめ") || text.contains("歪め")) {"""))

# 2. completeMega: 場にいない種族のメガを、別種族の占有枠へ付けない
EDITS.append((
"""    // megaSpecies への反映は |detailschange| 行の applyEvent が行う
    let slot = slotFor(side: side, speciesEn: baseEn)
    emitLog("|detailschange|\\(slot): \\(baseEn)|\\(megaEn)")""",
"""    // megaSpecies への反映は |detailschange| 行の applyEvent が行う
    let slot = slotFor(side: side, speciesEn: baseEn)
    // 場に居ることが確認できていない種族のメガを、別種族が占有して
    // いる枠へ付けることはしない。slotFor は場に無い種族に対して
    // 既定枠 (a 枠) を返すため、そのまま出すと無関係な枠の種族として
    // detailschange が出て、その枠の状態まで巻き込む (実例:
    // 2026-11-22 battle_20261122_071457、交代が未確定だった
    // ムクホークのメガがオオニューラの枠 p1a に付いた)。保留は
    // 維持し、交代の確定後の再試行 (synthesizeMegaIfPending) で
    // 正しい枠に出す
    let megaPlate = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
    if let occ = lastSlots[megaPlate], !sameSpeciesFamily(occ.speciesEn, baseEn) {
        return
    }
    emitLog("|detailschange|\\(slot): \\(baseEn)|\\(megaEn)")"""))

# 3. recordSwitchIn の いかく遡及: seq 一致の要求を外し、時刻窓だけにする
EDITS.append((
"""        let hasDrop = recentAtkDrops.contains { $0.key.hasPrefix("\\(other):") && $0.value.seq == actionSeq && now.timeIntervalSince($0.value.at) < 12 }""",
"""        // seq 一致まで要求すると、確定の遅れの間に他の文が処理された
        // 時点で恒常的に外れ、特性行が丸ごと落ちる (実例: 2026-11-22
        // battle_20261122_071457、特性行が 1 行も出なかった)。攻撃
        // 低下の記録が直近 20 秒以内にあれば帰属の根拠として十分
        let hasDrop = recentAtkDrops.contains { $0.key.hasPrefix("\\(other):") && now.timeIntervalSince($0.value.at) < 20 }"""))

# 4. completeArchiveHeader: 6 体を超える場合は未登場の宣言種族と入れ替える
EDITS.append((
"""func completeArchiveHeader(protocolLines: [String], displayLines: [String]) -> (protocolLines: [String], displayLines: [String], added: [String]) {
    var proto = protocolLines
    var added: [String] = []""",
"""func completeArchiveHeader(protocolLines: [String], displayLines: [String]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {
    var proto = protocolLines
    var added: [String] = []
    var removed: [String] = []"""))
EDITS.append((
"""        let missing = appeared.filter { a in !declared.contains { sameSpeciesFamily($0, a) } }
        if missing.isEmpty { continue }
        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)""",
"""        let missing = appeared.filter { a in !declared.contains { sameSpeciesFamily($0, a) } }
        if missing.isEmpty { continue }
        // 補完で 6 体を超える場合は、実際には登場しなかった宣言側の
        // 種族 (見せ合い同定の誤り) と入れ替える。チームが 7 体に
        // なるヘッダーはあり得ない (実例: 2026-11-22
        // battle_20261122_071457、誤同定の枠が残ったまま実登場した
        // サーフゴーが 7 体目に追記された)
        if declared.count + missing.count > 6 {
            let unused = declared.filter { d in !appeared.contains { sameSpeciesFamily($0, d) } }
            let removeCount = min(unused.count, declared.count + missing.count - 6)
            if removeCount > 0 {
                let removing = Array(unused.suffix(removeCount))
                let removeSet = Set(removing)
                proto = proto.filter { line in
                    guard line.hasPrefix("|poke|\\(side)|") else { return true }
                    return !removeSet.contains(String(line.dropFirst("|poke|\\(side)|".count)))
                }
                removed += removing.map { "\\(side):\\($0)" }
                lastPokeIdx = nil
                for (i, l) in proto.enumerated() {
                    if l.hasPrefix("|poke|\\(side)|") { lastPokeIdx = i }
                    if l == "|start" { break }
                }
            }
        }
        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)"""))
EDITS.append((
"""            let existing = disp[namesIdx].isEmpty ? [] : disp[namesIdx].components(separatedBy: " / ")
            let extra = sideAdded.filter { a in !existing.contains { sameSpeciesFamily($0, a) } }
            if !extra.isEmpty { disp[namesIdx] = (existing + extra).joined(separator: " / ") }""",
"""            let existing = disp[namesIdx].isEmpty ? [] : disp[namesIdx].components(separatedBy: " / ")
            let sideRemoved = removed.filter { $0.hasPrefix("\\(side):") }.map { String($0.dropFirst(3)) }
            let kept = existing.filter { e in !sideRemoved.contains { sameSpeciesFamily($0, e) } }
            let extra = sideAdded.filter { a in !kept.contains { sameSpeciesFamily($0, a) } }
            if !extra.isEmpty || kept.count != existing.count { disp[namesIdx] = (kept + extra).joined(separator: " / ") }"""))
EDITS.append((
"""    return (proto, disp, added)
}""",
"""    return (proto, disp, added, removed)
}"""))

# 5. 外れ行: 対象の枠と種族が場の記録と矛盾する場合は出さない
EDITS.append((
"""    if t.contains("当たらなかった") {
        if !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 8 {
            emitLog("|-miss|\\(lastMoveLabel)|\\(slot): \\(sp.en)")
        }
        return true
    }""",
"""    if t.contains("当たらなかった") {
        if !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 8 {
            // 外れの対象 (枠と種族) が場の記録と矛盾する場合は行を
            // 出さない (実例: 2026-11-22 battle_20261122_071457、
            // 場に出ていないガオガエンが p2a の外れ対象になった)。
            // 交代直後でプレート未確定の間は、交代記録の枠と一致
            // すれば通す
            let missPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            let missTracked = lastSlots[missPn]?.speciesEn
            let missConsistent = (missTracked.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[missPn] == sp.en
                || lastSwitchIn["\\(side):\\(sp.en)"]?.slot == slot
            if missConsistent {
                emitLog("|-miss|\\(lastMoveLabel)|\\(slot): \\(sp.en)")
            } else {
                debugCapture(kind: "move_guard", key: "miss_target:\\(slot):\\(sp.en):\\(currentTurn)", rawText: t,
                             detail: ["reason": "miss_target_inconsistent", "slot": slot, "species": sp.en, "tracked": missTracked ?? "", "turn": currentTurn])
            }
        }
        return true
    }"""))

# 6. ひんし文: 場の占有として記録されていない種族では被ダメ行を合成しない
EDITS.append((
"""    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        if (monStates[key]?.hpPercent ?? 0) > 0 {
            // プレートで 0% を読む前に倒れた場合 (ひんしアニメーションで""",
"""    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        if (monStates[key]?.hpPercent ?? 0) > 0 {
            // 場の占有として記録されていない種族の ひんし文では、
            // 被ダメ行の合成も ひんし行も出さない。未登録のまま倒れた
            // 個体の文や枠解決の誤りで、無関係な枠の HP 基準
            // (lastEmittedPct) を 0 に潰し、後続の正しいプレート読み
            // まで棄却する事故になるため (実例: 2026-11-22
            // battle_20261122_071457、コータスの ひんし文が p1a に
            // 解決され、リキキリンの正しい 65% 読みが棄却された)。
            // 文自体は消費する
            let faintPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            let faintOccupant = lastSlots[faintPn]?.speciesEn
            let faintIsOccupant = (faintOccupant.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[faintPn] == sp.en
            if !faintIsOccupant {
                debugCapture(kind: "faint_guard", key: "faint_guard:untracked:\\(slot):\\(sp.en)", rawText: t,
                             detail: ["reason": "faint_text_untracked", "slot": slot, "species": sp.en, "occupant": faintOccupant ?? "", "turn": currentTurn])
                return true
            }
            // プレートで 0% を読む前に倒れた場合 (ひんしアニメーションで"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for i, (old, new) in enumerate(EDITS):
    n = src.count(old)
    print(f"edit {i}: anchor count = {n}")
    if n != 1:
        bad += 1
        continue
    if apply:
        src = src.replace(old, new, 1)
if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    open(PATH, "w").write(src)
    print("applied all", len(EDITS), "edits")
else:
    print("dry run ok:", len(EDITS), "edits ready")
