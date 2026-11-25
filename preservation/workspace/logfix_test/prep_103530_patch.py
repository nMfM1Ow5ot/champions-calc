#!/usr/bin/env python3
# battle_20261122_103530 fix round: reader.swift patches.
# Each edit is an exact-anchor replacement; the script aborts unless every
# anchor occurs exactly once.
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

EDITS = []

def edit(name, old, new):
    EDITS.append((name, old, new))

# ---------------------------------------------------------------- P1 globals
edit("P1 globals",
r"""var pendingDamageSince: [String: Date] = [:]       // プレート名 -> その HP% が最初に現れた時刻 (段階アニメーションの途中値と区別する)""",
r"""var pendingDamageSince: [String: Date] = [:]       // プレート名 -> その HP% が最初に現れた時刻 (段階アニメーションの途中値と区別する)
var pendingReturnCount: [String: Int] = [:]        // プレート名 -> 保留中の被ダメ値が基準値へ戻った読みの回数 (1 回の誤読で保留を消さない)
var battleAdmittedSpecies: Set<String> = []        // この試合で「登録外だが繰り返し読めた」ため受け入れた自軍種族 (フォルム群単位)
var offTeamPlateStreak: [String: Int] = [:]        // "枠|種族" -> 登録外種族の連続観測回数
var battleMaxOverride: [String: Int] = [:]         // 種族 -> この試合で採用する最大 HP (登録値と読みが恒常的に食い違う場合)
var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数""")

# ---------------------------------------------------------------- P2 helpers
edit("P2 helpers",
r"""func parsePlate(image: CGImage, plate: Plate) -> SlotState? {""",
r"""// 自軍プレートの登録チーム照合。登録に無い種族は原則として誤読として
// 捨てるが、同じ枠で 3 回続けて読めた場合は登録側の取り違え (別チーム
// 画面の取り込み等で登録が実編成とずれた) とみて、この試合に限り
// フォルム群ごと受け入れる。受け入れた事実は証拠として残す
// (実例: 2026-11-22 battle_20261122_103530、登録が別チームのまま対戦が
//  始まり、イエッサン・オオニューラの交代と被ダメが丸ごと落ちた)
func minePlateAdmitted(plateKey: String, entry: SpeciesEntry) -> Bool {
    if teamEntries.isEmpty { return true }
    let grp = formeGroup(entry)
    if grp.contains(where: { teamEntries[$0.en] != nil }) { return true }
    if grp.contains(where: { battleAdmittedSpecies.contains($0.en) }) { return true }
    let k = "\(plateKey)|\(entry.en)"
    let n = (offTeamPlateStreak[k] ?? 0) + 1
    offTeamPlateStreak[k] = n
    if n >= 3 {
        for m in grp { battleAdmittedSpecies.insert(m.en) }
        debugCapture(kind: "off_team_plate", key: "off_team_plate:\(entry.en)", rawText: "",
                     detail: ["species": entry.en, "plate": plateKey, "sightings": n, "turn": currentTurn, "readerBuild": readerBuild])
        return true
    }
    return false
}

// 自軍プレートの最大 HP の既知値: この試合で読み側を採用した値があれば
// それを最優先し、次にチーム登録の実数値、最後に対戦中の記録を使う
func battleKnownMax(speciesEn: String, grp: [SpeciesEntry]) -> Int? {
    if let o = battleMaxOverride[speciesEn] { return o }
    for m in grp {
        if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { return h }
    }
    return monStates["p1:\(speciesEn)"]?.hpMax
}

// 読みの最大値が登録と食い違う場合の試合内採用管理。同じ読みの最大値を
// 2 回続けて観測したら、その試合では読み側を正として以後の照合に使う
// (1 回だけの読み違いや隣枠の HP の混入で登録値を上書きしないため)
func noteBattleMaxRead(speciesEn: String, readMax: Int, registeredMax: Int?) {
    if battleMaxOverride[speciesEn] == readMax { return }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }
    if battleMaxCandidate[speciesEn]?.max == readMax {
        let n = (battleMaxCandidate[speciesEn]?.count ?? 1) + 1
        if n >= 2 {
            battleMaxOverride[speciesEn] = readMax
            battleMaxCandidate[speciesEn] = nil
            debugCapture(kind: "team_max_mismatch", key: "team_max_mismatch:\(speciesEn)", rawText: "",
                         detail: ["species": speciesEn, "registeredMax": registeredMax ?? -1, "readMax": readMax, "turn": currentTurn, "readerBuild": readerBuild])
        } else {
            battleMaxCandidate[speciesEn] = (max: readMax, count: n)
        }
    } else {
        battleMaxCandidate[speciesEn] = (max: readMax, count: 1)
    }
}

// フィールド開始の出所 (サージ特性・天候特性) を持つ個体が場にいるか。
// メガフォルムの特性は別エントリにあるため科単位でも見る
func fieldSourceOnField(_ ui: String) -> Bool {
    let ability: String?
    switch ui {
    case "Psychic": ability = "Psychic Surge"
    case "Electric": ability = "Electric Surge"
    case "Grassy": ability = "Grassy Surge"
    case "Misty": ability = "Misty Surge"
    case "Sun": ability = "Drought"
    case "Rain": ability = "Drizzle"
    case "Sand": ability = "Sand Stream"
    case "Snow": ability = "Snow Warning"
    default: ability = nil
    }
    guard let ab = ability else { return true }
    for s in lastSlots.values {
        if (speciesAbilityMap[s.speciesEn] ?? []).contains(ab) { return true }
        for (other, pool) in speciesAbilityMap where pool.contains(ab) && sameSpeciesFamily(other, s.speciesEn) { return true }
    }
    return false
}

func parsePlate(image: CGImage, plate: Plate) -> SlotState? {""")

# ---------------------------------------------------------------- P3 parsePlate filter
edit("P3 parsePlate filter",
r"""    // 自軍の固定領域読み: 登録チーム (フォルム違い含む) に無い種族は誤読として捨てる
    if plate.isMine && !teamEntries.isEmpty
        && !formeGroup(raw).contains(where: { teamEntries[$0.en] != nil }) { return nil }""",
r"""    // 自軍の固定領域読み: 登録チーム (フォルム違い含む) に無い種族は
    // 誤読として捨てる (登録側の取り違えへの耐性は minePlateAdmitted が担う)
    if plate.isMine && !minePlateAdmitted(plateKey: plate.name, entry: raw) { return nil }""")

# ---------------------------------------------------------------- P4 parsePlate HP
edit("P4 parsePlate HP",
r"""        var knownMax: Int? = nil
        for m in formeGroup(sp) {
            if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { knownMax = h; break }
        }
        if knownMax == nil { knownMax = monStates["p1:\(sp.en)"]?.hpMax }
        for t in texts + [joined] {
            if let r = parseMineHPText(t, knownMax: knownMax) {
                if let km = knownMax, let mx = r.max, mx != km { continue }
                hp = r.pct; hpCur = r.cur; hpMax = r.max
                break
            }
        }""",
r"""        let knownMax = battleKnownMax(speciesEn: sp.en, grp: formeGroup(sp))
        for t in texts + [joined] {
            if let r = parseMineHPText(t, knownMax: knownMax) {
                if let km = knownMax, let mx = r.max, mx != km { continue }
                hp = r.pct; hpCur = r.cur; hpMax = r.max
                break
            }
        }
        if hp == nil {
            // 登録の最大値と合う読みが無い場合は、最大値を問わない読みで
            // 拾い直す。読みの最大値が登録と恒常的に食い違う場合は、
            // この試合では読み側を採用する (登録側の取り違え対策。
            // 実例: 2026-11-22 battle_20261122_103530、別ビルドの
            // グレンアルマ登録により 161/161 の読みが全て弾かれた)
            for t in texts + [joined] {
                if let r = parseMineHPText(t, knownMax: nil) {
                    hp = r.pct; hpCur = r.cur; hpMax = r.max
                    if let mx = r.max { noteBattleMaxRead(speciesEn: sp.en, readMax: mx, registeredMax: knownMax) }
                    break
                }
            }
        }""")

# ---------------------------------------------------------------- P5 pullBack collect set
edit("P5 pullBack collect",
r"""    var idxs = [si]
    if si + 1 < battleLog.count {
        for j in (si + 1)..<battleLog.count {
            let l = battleLog[j]
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, f[2] == label else { continue }
            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
        }
    }""",
r"""    var idxs = [si]
    if si + 1 < battleLog.count {
        var passedMove = false
        for j in (si + 1)..<battleLog.count {
            let l = battleLog[j]
            if l.hasPrefix("|move|") { passedMove = true }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, f[2] == label else { continue }
            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
            // 交代行に付随する補完の被ダメ・回復行 (入場時点の差分) も
            // ブロックの一部として一緒に引き戻す。ただし次の技行より
            // 後ろの同名行はその技の結果なので対象にしない
            else if !passedMove && (l.hasPrefix("|-damage|") || l.hasPrefix("|-heal|")) { idxs.append(j) }
        }
    }""")

edit("P5b pullBack display",
r"""        for i in dStart..<displayLog.count {
            let l = displayLog[i]
            if l == "Go! \(species)!" || l.hasSuffix("sent out \(species)!") { dispIdxs.append(i) }
            else if l.hasSuffix("is reacting to the Key Stone!") && l.contains(species) { dispIdxs.append(i) }
            else if l.contains("has Mega Evolved into") && l.contains(species) { dispIdxs.append(i) }
        }""",
r"""        var dispPassedMove = false
        for i in dStart..<displayLog.count {
            let l = displayLog[i]
            if l.contains(" used ") { dispPassedMove = true }
            if l == "Go! \(species)!" || l.hasSuffix("sent out \(species)!") { dispIdxs.append(i) }
            else if l.hasSuffix("is reacting to the Key Stone!") && l.contains(species) { dispIdxs.append(i) }
            else if l.contains("has Mega Evolved into") && l.contains(species) { dispIdxs.append(i) }
            else if !dispPassedMove && l.contains("\(species) lost") && l.hasSuffix("of its health!)") { dispIdxs.append(i) }
        }""")

# ---------------------------------------------------------------- P6 emitLog damage insertion
edit("P6a insertAt decl",
r"""    var insertAt: Int? = nil
    if line.hasPrefix("|-crit|") {""",
r"""    var insertAt: Int? = nil
    var dmgReorderMoveLabel: String? = nil
    if line.hasPrefix("|-crit|") {""")

edit("P6b damage branch",
r"""        }
    }
    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }""",
r"""        }
    } else if line.hasPrefix("|-damage|") {
        // 技の自己ランク低下 (アーマーキャノンの防御低下等) は文の翻訳で
        // 即時に出る一方、被ダメ行はプレート確定まで保留されるため、
        // 順序が逆転することがある。直前の技行の直後に、その使用者自身の
        // ランク変化行 (と同技の他の被ダメ行) だけが並んでいる場合は、
        // 被ダメ行をランク変化より前に戻す (実例: 2026-11-22
        // battle_20261122_103530 ターン2、アーマーキャノンの防御低下行が
        // 被ダメ行より前に置かれた)
        let df = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if df.count >= 3 {
            let dmgLabel = df[2]
            var i = battleLog.count - 1
            var firstBoostIdx: Int? = nil
            var boostLabels: [String] = []
            while i >= 0 && battleLog.count - i <= 12 {
                let bl = battleLog[i]
                let bf = bl.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                if (bl.hasPrefix("|-boost|") || bl.hasPrefix("|-unboost|")), bf.count >= 3 {
                    firstBoostIdx = i
                    boostLabels.append(bf[2])
                    i -= 1
                    continue
                }
                if bl.hasPrefix("|-damage|") || bl.hasPrefix("|-heal|") { i -= 1; continue }
                if bl.hasPrefix("|move|"), bf.count >= 4, let fb = firstBoostIdx,
                   bf[2] != dmgLabel, bf[2] == lastMoveLabel, bf[3] == lastMoveName,
                   boostLabels.allSatisfy({ $0 == bf[2] }) {
                    insertAt = fb
                    dmgReorderMoveLabel = bf[2]
                }
                break
            }
        }
    }
    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }""")

edit("P6c display mirror",
r"""            if af.count >= 4, let anchor = fieldRenderForAbility(af[3]) {
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        }
    }""",
r"""            if af.count >= 4, let anchor = fieldRenderForAbility(af[3]) {
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        } else if line.hasPrefix("|-damage|"), let ml = dmgReorderMoveLabel, let ss = parseSlotSpecies(ml) {
            // プロトコル側で技の自己ランク変化より前に戻した被ダメ行の
            // 表示も、使用者のランク変化表示の並びの前に割り込ませる
            let anchorPrefix = "[\(renderPrefix(ss.side))\(ss.speciesEn)'s "
            var i = displayLog.count - 1
            var runStart: Int? = nil
            while i >= 0 && displayLog.count - i <= 60 {
                let dl = displayLog[i]
                if dl.hasPrefix(anchorPrefix) && (dl.hasSuffix("rose!") || dl.hasSuffix("fell!")) { runStart = i; i -= 1; continue }
                break
            }
            if let rs = runStart { displayInsertAt = rs }
        }
    }""")

# ---------------------------------------------------------------- P7 reset clears
edit("P7 reset clears",
r"""    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false""",
r"""    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false
    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]""")

# ---------------------------------------------------------------- P8 tail absorption
edit("P8 tail absorption",
r"""    // 段階アニメーションの尾: 同じ行動・同じターンで、直前の出力行と
    // 同じ向き・わずかな差 (3% 以下) の続きは、行を出さず値だけ取り込む
    // (実例: 2026-11-20、グラススライドの被弾が 79% と 2% に割れた)
    if toPct != 0, let lp = lastEmittedPct[plateName],
       lastDamageSeq[plateName] == actionSeq, lastDamageTurn[plateName] == currentTurn,
       lastDamageDir[plateName] == dir, toPct != lp, abs(toPct - lp) <= 3 {""",
r"""    // 段階アニメーションの尾: 同じ行動・同じターンで、直前の出力行と
    // 同じ向き・わずかな差 (3% 以下) の続きは、行を出さず値だけ取り込む
    // (実例: 2026-11-20、グラススライドの被弾が 79% と 2% に割れた)。
    // 直前の行から 3 秒以内なら 5 ポイントまで広げる (反動ダメージの
    // 途中値が先行行として出て、確定値が第 2 行に割れた実例: 2026-11-22
    // battle_20261122_103530、いのちのたま の反動が 94% と 90% に割れた)
    if toPct != 0, let lp = lastEmittedPct[plateName],
       lastDamageSeq[plateName] == actionSeq, lastDamageTurn[plateName] == currentTurn,
       lastDamageDir[plateName] == dir, toPct != lp,
       abs(toPct - lp) <= 3 || (abs(toPct - lp) <= 5 && (lastDamageTime[plateName].map { Date().timeIntervalSince($0) <= 3 } ?? false)) {""")

# ---------------------------------------------------------------- P9 processPlates hpMax
edit("P9 hpMax adopt",
r"""        // 登録チームの実数値がある種族は、プレート読みの最大値で上書きしない
        // (誤読した最大値が knownMax として固定され、正しい読みまで弾く事故を防ぐ)
        if let m = s.hpMax, (teamEntries[s.speciesEn]?["stats"] as? [String: Int])?["hp"] == nil {
            monStates[key]?.hpMax = m
        }""",
r"""        // 登録チームの実数値がある種族は、プレート読みの最大値で上書きしない
        // (誤読した最大値が knownMax として固定され、正しい読みまで弾く事故を防ぐ)。
        // ただし、この試合で読み側の最大値を採用済みの種族は読みに従う
        if let m = s.hpMax, (teamEntries[s.speciesEn]?["stats"] as? [String: Int])?["hp"] == nil
            || battleMaxOverride[s.speciesEn] == m {
            monStates[key]?.hpMax = m
        }""")

# ---------------------------------------------------------------- P10 pending age + valve
edit("P10a pending age",
r"""                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
                // 交代要員を選んでいる間は、控え一覧画面のバーが場のプレートと""",
r"""                let pendingSwitchAge = pendingSwitchSince[plate.name].map { Date().timeIntervalSince($0) } ?? 0
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
                // 交代要員を選んでいる間は、控え一覧画面のバーが場のプレートと""")

edit("P10b replacementBusy valve",
r"""                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)""",
r"""                // 確定試行が 20 秒以上続いている交代は、要員選択画面の
                // 映り込みではあり得ない (選択は交代の確定で終わる) ため、
                // 要員待ちの破棄対象から外す。後任の交代が記録されないまま
                // 要員待ちが居座り、別枠の本物の交代まで巻き込んで落とし
                // 続けた実例: 2026-11-22 battle_20261122_103530、
                // オオニューラの交代が登録で弾かれ続け、グレンアルマの
                // 再登場が全てこのガードで破棄された
                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                    && pendingSwitchAge < 20""")

# ---------------------------------------------------------------- P11 pull-back call
edit("P11 pullback call",
r"""                    lastSlots[plate.name] = adoptFull
                        ? SlotState(speciesEn: s.speciesEn, hpPercent: 100, hpCur: s.hpMax, hpMax: s.hpMax) : s""",
r"""                    lastSlots[plate.name] = adoptFull
                        ? SlotState(speciesEn: s.speciesEn, hpPercent: 100, hpCur: s.hpMax, hpMax: s.hpMax) : s
                    // ターン開始時の任意交代が、演出の遮蔽で確定が遅れて
                    // 技行より後ろに出た場合は、ターン行の直後へ引き戻す。
                    // 交代した側がこの区間でまだ何もしていない (出す側の
                    // 技行・被ダメ行・ひんし行が区間に無い) 場合に限る
                    // ため、とんぼがえし等の交代技や だっしゅつボタン の
                    // 交代は対象にならない (実例: 2026-11-22
                    // battle_20261122_103530、ゴリランダーのターン1の
                    // 交代が ハイパーボイス より後ろに置かれた)
                    if currentTurn >= 1, let prevSp = prev?.speciesEn,
                       let turnIdx0 = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                        let outLabel = "\(slot): \(prevSp)"
                        let seg = battleLog[(turnIdx0 + 1)...]
                        let segHasMove = seg.contains { $0.hasPrefix("|move|") }
                        let outActed = seg.contains { l in
                            guard l.hasPrefix("|move|") || l.hasPrefix("|-damage|") || l.hasPrefix("|faint|") else { return false }
                            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                            return f.count >= 3 && f[2] == outLabel
                        }
                        if segHasMove && !outActed {
                            let pulled = pullBackSwitchBlock(label: "\(slot): \(s.speciesEn)")
                            if !pulled.proto.isEmpty {
                                if let ti = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                                    battleLog.insert(contentsOf: pulled.proto, at: ti + 1)
                                }
                                if !pulled.display.isEmpty {
                                    var dTurn = -1
                                    for (i, l) in displayLog.enumerated() where l.hasPrefix("Turn ") { dTurn = i }
                                    if dTurn >= 0 { displayLog.insert(contentsOf: pulled.display, at: dTurn + 1) }
                                }
                                debugCapture(kind: "turn_guard", key: "turn_guard_pullback:\(slot):\(s.speciesEn):\(currentTurn)", rawText: "",
                                             detail: ["action": "switch_pulled_to_turn_head", "slot": slot, "species": s.speciesEn, "turn": currentTurn, "readerBuild": readerBuild])
                            }
                        }
                    }""")

# ---------------------------------------------------------------- P12 anti-clear
edit("P12a anti-clear",
r"""            if s.hpPercent == emitted {
                pendingDamagePct[plate.name] = nil
                pendingDamageCount[plate.name] = nil
            } else if s.hpPercent == 0 {""",
r"""            if s.hpPercent == emitted {
                // 保留中の被ダメ値がある間は、基準値と一致する読みが
                // 1 回あっただけでは保留を消さない (アニメーション中の
                // 一過性の戻り読みで本物の被ダメが消えた疑い: 2026-11-22
                // battle_20261122_103530、ドレインキッスを受けた
                // サーナイトの 145→73 が行にならなかった)。2 回続けて
                // 基準値に戻ったら、保留側が誤読だったとして消す
                if pendingDamagePct[plate.name] != nil {
                    let rc = (pendingReturnCount[plate.name] ?? 0) + 1
                    if rc >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {
                        pendingReturnCount[plate.name] = rc
                    }
                } else {
                    pendingDamagePct[plate.name] = nil
                    pendingDamageCount[plate.name] = nil
                }
            } else if s.hpPercent == 0 {""")

edit("P12b pending branch rc clear",
r"""            } else if pendingDamagePct[plate.name] == s.hpPercent {
                // 同じ値が 3 回続き、かつ現れてから 2.0 秒経った = アニメーションが""",
r"""            } else if pendingDamagePct[plate.name] == s.hpPercent {
                pendingReturnCount[plate.name] = nil
                // 同じ値が 3 回続き、かつ現れてから 2.0 秒経った = アニメーションが""")

edit("P12c emit success rc clear",
r"""                    if emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                      fromPct: emitted, toPct: s.hpPercent, hpText: monStates[key]!.hpText) {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                    } else {""",
r"""                    if emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                      fromPct: emitted, toPct: s.hpPercent, hpText: monStates[key]!.hpText) {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {""")

edit("P12d new value rc clear",
r'''            } else {
                pendingDamagePct[plate.name] = s.hpPercent
                pendingDamageCount[plate.name] = 1
                pendingDamageSince[plate.name] = Date()
                lastPendingLabel = "\(slot): \(s.speciesEn)"''',
r'''            } else {
                pendingDamagePct[plate.name] = s.hpPercent
                pendingDamageCount[plate.name] = 1
                pendingDamageSince[plate.name] = Date()
                pendingReturnCount[plate.name] = nil
                lastPendingLabel = "\(slot): \(s.speciesEn)"''')

# ---------------------------------------------------------------- P13 protected faint
edit("P13 protected faint",
r"""                if pendingDamagePct[plate.name] == 0 {
                    let n = (pendingDamageCount[plate.name] ?? 1) + 1
                    if n >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                       fromPct: emitted, toPct: 0, hpText: monStates[key]!.hpText)
                    } else {
                        pendingDamageCount[plate.name] = n
                    }
                } else {""",
r"""                if pendingDamagePct[plate.name] == 0 {
                    let n = (pendingDamageCount[plate.name] ?? 1) + 1
                    if n >= 2 && protectMoveTurn[slot] == currentTurn {
                        // このターン まもる を使った枠は、そのターンの攻撃
                        // では倒れない。0% の読みは演出中の誤読として
                        // 捨てる (実例: 2026-11-22 battle_20261122_103530、
                        // まもるで防いだフラエッテに幻のひんしが出て、
                        // 次ターンの本物のひんしが重複として消えた)。
                        // 天候・状態異常等の残りダメージで倒れた場合は、
                        // ひんし文の経路が別途ひんし行を補う
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                        debugCapture(kind: "faint_guard", key: "faint_guard_protected:\(slot):\(currentTurn)", rawText: "",
                                     detail: ["reason": "protected_zero_read", "slot": slot, "species": s.speciesEn, "turn": currentTurn, "readerBuild": readerBuild])
                    } else if n >= 2 && Date().timeIntervalSince(pendingDamageSince[plate.name] ?? .distantPast) >= 0.8 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                        emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                       fromPct: emitted, toPct: 0, hpText: monStates[key]!.hpText)
                    } else {
                        pendingDamageCount[plate.name] = n
                    }
                } else {""")

# ---------------------------------------------------------------- P14 flush readiness
edit("P14 flush readiness",
r"""        let ready = (pendingSwitchSpecies.isEmpty && !awaitingNow) || heldAge > (awaitingNow ? 20.0 : 6.0)
        if ready {""",
r"""        var ready = (pendingSwitchSpecies.isEmpty && !awaitingNow) || heldAge > (awaitingNow ? 20.0 : 6.0)
        // ターン0 で出所 (サージ・天候特性) が場に確認できない開始は、
        // 出所の交代が確定するまで流さない (上限の強制排出は従来どおり。
        // 実例: 2026-11-22 battle_20261122_103530、ゴリランダーの交代が
        // 確定する前に グラスフィールド の開始行だけが対戦開始直後に出た)
        if ready && currentTurn == 0 && heldAge <= 20.0 {
            if let h = heldWeatherStart, !fieldSourceOnField(h.ui) { ready = false }
            if let h = heldTerrainStart, !fieldSourceOnField(h.ui) { ready = false }
        }
        if ready {""")

# ---------------------------------------------------------------- P15 setWeather hold
edit("P15 setWeather hold",
r"""    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {
        if heldWeatherStart?.ui != ui {
            heldWeatherStart = (ui: ui, logName: logName, text: text, at: Date())
        }
        return
    }""",
r"""    // ターン0 で出所の特性を持つ個体が場にいない開始も保留する
    // (交代の確定前に開始文だけが先行するケース。setTerrain と同じ)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()
        || (currentTurn == 0 && logFieldWeather.isEmpty && !fieldSourceOnField(ui))) {
        if heldWeatherStart?.ui != ui {
            heldWeatherStart = (ui: ui, logName: logName, text: text, at: Date())
        }
        return
    }""")

# ---------------------------------------------------------------- P16 setTerrain hold
edit("P16 setTerrain hold",
r"""    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {
        if heldTerrainStart?.ui != ui {
            heldTerrainStart = (ui: ui, text: text, at: Date())
        }
        return
    }""",
r"""    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)。
    // あわせて、ターン0 で出所の特性を持つ個体が場にいない開始も
    // 保留する (交代の確定前に開始文だけが先行し、出所なしで対戦開始
    // 直後に置かれた実例: 2026-11-22 battle_20261122_103530、
    // ゴリランダーの グラスフィールド)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()
        || (currentTurn == 0 && logFieldTerrain.isEmpty && !fieldSourceOnField(ui))) {
        if heldTerrainStart?.ui != ui {
            heldTerrainStart = (ui: ui, text: text, at: Date())
        }
        return
    }""")

# ---------------------------------------------------------------- P17 completeMega labels
edit("P17 completeMega labels",
r'''    emitLog("|detailschange|\(slot): \(baseEn)|\(megaEn)")
    var megaLine = "|-mega|\(slot): \(baseEn)|\(baseEn)"''',
r'''    // 行のラベルは場の実表記 (フォルム名) に寄せる。ベース名のまま
    // だと交代行 (Floette-Eternal) と表記が揺れ、状態のキーも場の
    // エントリとずれる (実例: 2026-11-22 battle_20261122_103530)
    let labelSp = (lastSlots[megaPlate]?.speciesEn).flatMap { sameSpeciesFamily($0, baseEn) ? $0 : nil } ?? baseEn
    emitLog("|detailschange|\(slot): \(labelSp)|\(megaEn)")
    var megaLine = "|-mega|\(slot): \(labelSp)|\(baseEn)"''')

# ---------------------------------------------------------------- P18 megaTextSide + helper
edit("P18a megaLabelSpecies helper",
r"""func megaTextSide(_ t: String, baseEn: String) -> String {""",
r"""// メガ関連行のラベル: 枠の実占有種族が同ファミリーならその表記
// (フォルム名) を使い、枠とラベル種族の組を返す
func megaLabelSpecies(side: String, speciesEn: String) -> (slot: String, speciesEn: String) {
    let slot = slotFor(side: side, speciesEn: speciesEn)
    let pn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
    if let occ = lastSlots[pn]?.speciesEn, sameSpeciesFamily(occ, speciesEn) { return (slot, occ) }
    return (slot, speciesEn)
}

func megaTextSide(_ t: String, baseEn: String) -> String {""")

edit("P18b megaTextSide",
r"""    let pend = ["p1", "p2"].filter { pendingMegaSpecies[$0] == baseEn }
    if pend.count == 1 { return pend[0] }
    let inMine = lastSlots["mineA"]?.speciesEn == baseEn || lastSlots["mineB"]?.speciesEn == baseEn
    let inOpp = lastSlots["oppA"]?.speciesEn == baseEn || lastSlots["oppB"]?.speciesEn == baseEn
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    return "p1"
}""",
r"""    let pend = ["p1", "p2"].filter { pendingMegaSpecies[$0] == baseEn }
    if pend.count == 1 { return pend[0] }
    // 場の照合はファミリー単位で行う (場の表記がフォルム名
    // (Floette-Eternal) で文側がベース名 (Floette) の場合に、完全一致
    // では決まらない。実例: 2026-11-22 battle_20261122_103530、
    // フラエッテのメガストーンが自軍のグレンアルマに誤帰属した)
    let inMine = ["mineA", "mineB"].contains { (lastSlots[$0]?.speciesEn).map { sameSpeciesFamily($0, baseEn) } ?? false }
    let inOpp = ["oppA", "oppB"].contains { (lastSlots[$0]?.speciesEn).map { sameSpeciesFamily($0, baseEn) } ?? false }
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    // 場で決まらない場合も、登録の所在が片側だけならそちらを正とする
    // (無条件の自軍帰属はしない)
    let teamMine = teamEntries.keys.contains { sameSpeciesFamily($0, baseEn) }
    let teamOpp = oppTeamSeen.contains { sameSpeciesFamily($0, baseEn) }
    if teamMine != teamOpp { return teamMine ? "p1" : "p2" }
    return "p1"
}""")

# ---------------------------------------------------------------- P19 emitItemOnce anchoring
edit("P19a item anchor 1",
r"""                emitItemOnce(slot: slotFor(side: side, speciesEn: sp.en), side: side, speciesEn: sp.en, itemJa: itJa)
                pendingMegaStone[side] = itJa""",
r"""                let ml1 = megaLabelSpecies(side: side, speciesEn: sp.en)
                emitItemOnce(slot: ml1.slot, side: side, speciesEn: ml1.speciesEn, itemJa: itJa)
                pendingMegaStone[side] = itJa""")

edit("P19b item anchor 2",
r"""                    emitItemOnce(slot: slotFor(side: useSide, speciesEn: useSp.en), side: useSide, speciesEn: useSp.en, itemJa: itJa)
                    pendingMegaStone[useSide] = itJa""",
r"""                    let ml2 = megaLabelSpecies(side: useSide, speciesEn: useSp.en)
                    emitItemOnce(slot: ml2.slot, side: useSide, speciesEn: ml2.speciesEn, itemJa: itJa)
                    pendingMegaStone[useSide] = itJa""")

# ---------------------------------------------------------------- P20 bare miss
edit("P20 bare miss",
r"""    if t.contains("つよさの表示") { return true }""",
r"""    if t.contains("つよさの表示") { return true }
    // 外れの文が対象種族なしで届いた場合 (文の末尾だけが読めた断片):
    // 直近の技が解決中の間は未翻訳として残さず消費する。被ダメの記録が
    // 無く、まもる も使っておらず、ひんしにもなっていない相手枠が
    // 1 つだけなら、その枠への外れとして記録する (実例: 2026-11-22
    // battle_20261122_103530、「当たらなかった！」だけが未翻訳で残った)
    if t.contains("当たらなかった") && findSpeciesJa(in: t) == nil
        && !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
        let moverSide = lastMoveLabel.hasPrefix("p1") ? "p1" : "p2"
        let targetPlates = moverSide == "p1" ? ["oppA", "oppB"] : ["mineA", "mineB"]
        var unresolved: [(slot: String, speciesEn: String)] = []
        for pn in targetPlates {
            guard let occ = lastSlots[pn] else { continue }
            let sl = slotId(pn)
            let label = "\(sl): \(occ.speciesEn)"
            if (damagedBySeq[actionSeq] ?? []).contains(label) { continue }
            if protectMoveTurn[sl] == currentTurn { continue }
            if faintedSlots[sl] != nil { continue }
            unresolved.append((slot: sl, speciesEn: occ.speciesEn))
        }
        if unresolved.count == 1 {
            emitLog("|-miss|\(lastMoveLabel)|\(unresolved[0].slot): \(unresolved[0].speciesEn)")
        } else {
            debugCapture(kind: "move_guard", key: "miss_bare:\(currentTurn):\(actionSeq)", rawText: t,
                         detail: ["reason": "bare_miss_consumed", "mover": lastMoveLabel, "candidates": unresolved.count, "turn": currentTurn])
        }
        return true
    }""")

# ---------------------------------------------------------------- P21 Helping Hand guard
edit("P21 HH guard",
r"""                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                lastMoveSigAt[sig] = Date()""",
r"""                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                // てだすけ (優先度 +5) の告知が、区間に他の技行が既に
                // ある状態で届くことは実戦ではあり得ない (コマンド画面の
                // 技表示や過去文の再読が告知として処理されたもの。
                // 実例: 2026-11-22 battle_20261122_103530 ターン4、
                // 場にいないはずのイエッサンの てだすけ が出た)
                if moveEn == "Helping Hand" {
                    var segHasOtherMove = false
                    if let ti = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                        for l in battleLog[(ti + 1)...] where l.hasPrefix("|move|") {
                            let mf = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                            if mf.count >= 4 && mf[3] != "Helping Hand" { segHasOtherMove = true; break }
                        }
                    }
                    if segHasOtherMove {
                        debugCapture(kind: "move_guard", key: "move_guard_priority:\(slot):\(currentTurn)", rawText: t,
                                     detail: ["reason": "priority_late", "move": moveEn, "slot": slot, "species": sp.en, "turn": currentTurn])
                        return true
                    }
                }
                lastMoveSigAt[sig] = Date()""")

# ---------------------------------------------------------------- P22 pick filter + knownMax
edit("P22a pick filter",
r"""            // 自軍プレートの種族は登録チーム (フォルム違い含む) のいずれかで
            // なければならない (演出中の誤読で無関係な種族が紛れ込むのを防ぐ)
            if mine && !teamEntries.isEmpty && !grp.contains(where: { teamEntries[$0.en] != nil }) { continue }""",
r"""            // 自軍プレートの種族は登録チーム (フォルム違い含む) のいずれかで
            // なければならない (演出中の誤読で無関係な種族が紛れ込むのを防ぐ。
            // 登録側の取り違えへの耐性は minePlateAdmitted が担う)
            if mine && !minePlateAdmitted(plateKey: "locate", entry: c.entry) { continue }""")

edit("P22b pick knownMax",
r"""            // 最大HP の既知値: チーム登録の実数値を最優先し (プレート誤読で
            // 固定されることがない)、無ければ対戦中の記録を使う
            var knownMax: Int? = nil
            if mine {
                for m in grp {
                    if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { knownMax = h; break }
                }
                if knownMax == nil { knownMax = monStates["p1:\\(en)"]?.hpMax }
            }
            guard let hp = hpNear(c.box, mine: mine, claimed: &claimed, knownMax: knownMax) else { continue }""",
r"""            // 最大HP の既知値: この試合で読み側を採用した値があればそれを、
            // 無ければチーム登録の実数値を最優先し (プレート誤読で固定
            // されることがない)、最後に対戦中の記録を使う
            var knownMax: Int? = nil
            if mine { knownMax = battleKnownMax(speciesEn: en, grp: grp) }
            var hp = hpNear(c.box, mine: mine, claimed: &claimed, knownMax: knownMax)
            if hp == nil, mine, let km = knownMax {
                // 登録の最大値と合う読みが無い場合は最大値を問わず拾い直し、
                // 読みの最大値を試合内の採用候補として記録する (登録側の
                // 取り違え対策。隣枠の HP を拾う危険があるため、採用の
                // 確定は 2 回の一致観測を要する)
                if let relaxed = hpNear(c.box, mine: mine, claimed: &claimed, knownMax: nil) {
                    hp = relaxed
                    if let mx = relaxed.max { noteBattleMaxRead(speciesEn: en, readMax: mx, registeredMax: km) }
                }
            }
            guard let hp else { continue }""")

# ---------------------------------------------------------------- P23 build stamp
edit("P23 build stamp",
r"""let readerBuild = "20261122_1105""",
r"""let readerBuild = "20261122_1121""")

for name, old, new in EDITS:
    cnt = src.count(old)
    if cnt != 1:
        print(f"ABORT: {name}: anchor count = {cnt}")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
