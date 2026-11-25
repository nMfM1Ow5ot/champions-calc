#!/usr/bin/env python3
# reader.swift patch for battle_20261123_090354 (log-analysis request):
#  1. archive header completion also uses the final identified team
#     (identified-but-never-appeared species were dropped when a
#     manual start wrote the header mid-identification)
#  2. Hospitality tea text -> ability line + pending heal source, so
#     the plate rise is adopted as a heal (the missed heal had
#     frozen the baseline and swallowed the following drops)
#  3. burn cue gap: 「負った/負つた」 missing from the status cue
#     lists (burn lines had never been produced); glyph decode
#     stage extended to 2 kana<->kanji confusions
#  4. late turn-start switch: announcement-before-first-move
#     evidence overrides the developed-segment pull-back refusal;
#     residual [from] damage lines are no longer carried by
#     switch pull-backs; status-residual [from] fallback for chips
#  5. manual mode: |win| re-fired on re-reads (winLogged is never
#     set) -> dedicated winLineEmitted latch
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
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

# ---- build stamp ----
rep('let readerBuild = "20261123_0923"', 'let readerBuild = "20261123_0948"', "build")

# ---- 5. win latch: global + reset ----
rep('''var winLogged = false                             // このバトルで勝敗が確定したか''',
    '''var winLogged = false                             // このバトルで勝敗が確定したか
var winLineEmitted = false                        // 勝敗行を既に出したか (手動モードでは winLogged を立てないため、再読での二重生成をこれで抑える)''',
    "5a win latch global")
rep('''    lastEmittedPct = [:]
    winLogged = false''',
    '''    lastEmittedPct = [:]
    winLogged = false
    winLineEmitted = false''',
    "5b win latch reset")

# win-text branch: extend the guard, set the latch on emission
rep('''    if t.range(of: "勝.に", options: .regularExpression) != nil && (t.contains("負けた") || tw.contains("勝つた")) {
        if winLogged { return true }   // 同じ勝敗文の再読では出さない''',
    '''    if t.range(of: "勝.に", options: .regularExpression) != nil && (t.contains("負けた") || tw.contains("勝つた")) {
        if winLogged || winLineEmitted { return true }   // 同じ勝敗文の再読では出さない''',
    "5c win guard")
rep('''        emitPendingFaints()
        if won { emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)") }
        else { emitLog("|win|\\(oppName.isEmpty ? "p2" : oppName)") }''',
    '''        emitPendingFaints()
        if won { emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)") }
        else { emitLog("|win|\\(oppName.isEmpty ? "p2" : oppName)") }
        winLineEmitted = true''',
    "5d win latch set")
# forfeit branch
rep('''    if t.contains("あきらめた") {
        if winLogged { return true }   // 同じ勝敗文の再読では出さない
        let oppGaveUp = t.contains("相手") || t.contains("あいて")
        forfeitName = oppGaveUp ? (trainerOpp.isEmpty ? "Opponent" : trainerOpp) : (trainerMine.isEmpty ? "You" : trainerMine)
        emitPendingFaints()
        emitLog("|win|\\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")''',
    '''    if t.contains("あきらめた") {
        if winLogged || winLineEmitted { return true }   // 同じ勝敗文の再読では出さない
        let oppGaveUp = t.contains("相手") || t.contains("あいて")
        forfeitName = oppGaveUp ? (trainerOpp.isEmpty ? "Opponent" : trainerOpp) : (trainerMine.isEmpty ? "You" : trainerMine)
        emitPendingFaints()
        emitLog("|win|\\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        winLineEmitted = true''',
    "5e forfeit latch")
# idle branch
rep('''    if t.contains("操作がありません") || (t.contains("対戦を終了します") && t.contains("操作")) {
        if winLogged { return true }''',
    '''    if t.contains("操作がありません") || (t.contains("対戦を終了します") && t.contains("操作")) {
        if winLogged || winLineEmitted { return true }''',
    "5f idle guard")
rep('''        if oppIdle && !mineIdle {
            forfeitName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
            emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)")
            if !flagManualMode { winLogged = true }
        } else if mineIdle && !oppIdle {
            forfeitName = trainerMine.isEmpty ? "You" : trainerMine
            emitLog("|win|\\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            if !flagManualMode { winLogged = true }
        }''',
    '''        if oppIdle && !mineIdle {
            forfeitName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
            emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)")
            winLineEmitted = true
            if !flagManualMode { winLogged = true }
        } else if mineIdle && !oppIdle {
            forfeitName = trainerMine.isEmpty ? "You" : trainerMine
            emitLog("|win|\\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            winLineEmitted = true
            if !flagManualMode { winLogged = true }
        }''',
    "5g idle latch set")

# ---- 2. pending heal source: global + reset + healSource ----
rep('''var pendingStatusFrom: [String: (code: String, at: Date)] = [:]  // "p1:Species" -> 状態異常ダメージの帰属''',
    '''var pendingStatusFrom: [String: (code: String, at: Date)] = [:]  // "p1:Species" -> 状態異常ダメージの帰属
var pendingHealFrom: [String: (label: String, at: Date)] = [:]  // "p1:Species" -> 文で判明した回復の発生源 (おちゃかい等)''',
    "2a heal global")
rep('''    pendingStatusFrom = [:]''',
    '''    pendingStatusFrom = [:]
    pendingHealFrom = [:]''',
    "2b heal reset")
rep('''func healSource(plateName: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) -> (label: String, itemJa: String?)? {
    let delta = toPct - fromPct
    guard delta > 0 else { return nil }''',
    '''func healSource(plateName: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) -> (label: String, itemJa: String?)? {
    let delta = toPct - fromPct
    guard delta > 0 else { return nil }
    // 文で判明した回復の発生源 (おちゃかいの回復等) が控えてあれば
    // それを最優先する。回復量は最大の 1/4 前後 (実例: 2026-11-23
    // battle_20261123_090354、ミロカロス 62 -> 85 が発生源なしとして
    // 抑えられ、基準値が止まって後続の低下まで呑んだ)
    if let ph = pendingHealFrom[key], sNow().timeIntervalSince(ph.at) < 10, (20...30).contains(delta) {
        pendingHealFrom[key] = nil
        return (ph.label, nil)
    }''',
    "2c healSource")

# ---- 2. tea branch in translateBattleMessage (before the ゆけっ branch) ----
rep('''    // 繰り出し (自分): 「ゆけっ！ A！ B！」の並び順 = 場の左右 (実機で確認)。''',
    '''    // おちゃかい (ヤバソチャの特性): 「相手のヤバソチャが たてた
    // お茶を <相方>は 飲みほした！」(2 行構成。ボックス結合で語順が
    // 崩れて届くこともある)。特性行を出し、回復の発生源を相方へ
    // 控える (プレートの上昇を |-heal| として採用するため。実例:
    // 2026-11-23 battle_20261123_090354、文が |-message| に落ちて
    // 回復行が出ず、後続の低下まで欠落した)
    if t.contains("お茶") && (t.contains("飲みほした") || t.contains("飲み干した") || t.contains("のみほした")) {
        let named = findAllSpeciesJa(in: t)
        let sinistcha = named.first(where: { $0.en == "Sinistcha" })
            ?? lastSlots.values.first(where: { $0.speciesEn == "Sinistcha" }).map { s in
                speciesDict.first(where: { $0.en == s.speciesEn })
            } ?? nil
        if let sc = sinistcha {
            let side = (lastSlots["oppA"]?.speciesEn == sc.en || lastSlots["oppB"]?.speciesEn == sc.en) ? "p2" : "p1"
            let names = side == "p2" ? ["oppA", "oppB"] : ["mineA", "mineB"]
            let scSlot = names.first(where: { lastSlots[$0]?.speciesEn == sc.en }).map { slotId($0) }
            let allyName = names.first(where: { lastSlots[$0]?.speciesEn != sc.en && lastSlots[$0] != nil })
            if let scSlot, let allyName, let ally = lastSlots[allyName] {
                emitAbilityOnce(slot: scSlot, side: side, speciesEn: sc.en, abilityEn: "Hospitality")
                pendingHealFrom["\\(side):\\(ally.speciesEn)"] = ("ability: Hospitality", sNow())
                return true
            }
        }
    }
    // 繰り出し (自分): 「ゆけっ！ A！ B！」の並び順 = 場の左右 (実機で確認)。''',
    "2d tea branch")

# ---- 3. burn cues ----
rep('''    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた"]
    guard cues.contains(where: { text.contains($0) }) else { return }''',
    '''    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた", "負った", "負つた"]
    guard cues.contains(where: { text.contains($0) }) else { return }''',
    "3a cues checkStatusText")
rep('''    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた"]
    guard cured || (hasCode && cues.contains(where: { t.contains($0) })) else { return false }''',
    '''    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた", "負った", "負つた"]
    guard cured || (hasCode && cues.contains(where: { t.contains($0) })) else { return false }''',
    "3b cues salvageStatus")

# ---- 3. glyph stage: up to 2 confusions ----
rep('''            var hit = false
            outer: for start in 0...(tArr.count - nArr.count) {
                var diffs = 0
                for k in 0..<nArr.count {
                    let a = tArr[start + k], b = nArr[k]
                    if a == b { continue }
                    diffs += 1
                    if diffs > 1 { break }
                    if !((isKana(a) && isKanji(b)) || (isKanji(a) && isKana(b))) { diffs = 2; break }
                }
                if diffs == 1 { hit = true; break outer }
            }''',
    '''            var hit = false
            outer: for start in 0...(tArr.count - nArr.count) {
                var diffs = 0
                for k in 0..<nArr.count {
                    let a = tArr[start + k], b = nArr[k]
                    if a == b { continue }
                    diffs += 1
                    if diffs > 2 { break }
                    if !((isKana(a) && isKanji(b)) || (isKanji(a) && isKana(b))) { diffs = 3; break }
                }
                if diffs == 1 || diffs == 2 { hit = true; break outer }
            }''',
    "3c glyph 2 diffs")
rep('''    // 字形混同 (ミロカロス→三ロカロス のようにカタカナが似た漢字に
    // 化ける) は上の全段で拾えないため、同長で 1 文字だけ食い違い、''',
    '''    // 字形混同 (ミロカロス→三ロカロス のようにカタカナが似た漢字に
    // 化ける) は上の全段で拾えないため、同長で最大 2 文字だけ食い違い、''',
    "3d glyph comment")

# ---- 4. segment timing globals + applyEvent tracking ----
rep('''var lastMoveMsgAt = Date.distantPast''',
    '''var lastMoveMsgAt = Date.distantPast
var segmentFirstMoveAt: Date? = nil   // 現在のターン区間で最初の技行が出た時刻 (交代引き戻しの判定用)
var lastTurnLineAt = Date.distantPast // 直近のターン行が出た時刻''',
    "4a timing globals")

# ---- 1. header completion from the final identified team ----
rep('''func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:], pickByCandidate: [String: String] = [:], slotMargins: [String: Double] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {''',
    '''func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:], pickByCandidate: [String: String] = [:], slotMargins: [String: Double] = [:], finalTeams: [String: [String]] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {''',
    "1a header signature")
rep('''        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)
        proto.insert(contentsOf: missing.map { "|poke|\\(side)|\\($0)" }, at: insertAt)
        added += missing.map { "\\(side):\\($0)" }
    }''',
    '''        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)
        proto.insert(contentsOf: missing.map { "|poke|\\(side)|\\($0)" }, at: insertAt)
        added += missing.map { "\\(side):\\($0)" }
        // 最終同定チームによる補完: 手動開始で同定の途中にヘッダーが
        // 書かれた場合、同定済みでも登場しなかった種族は上の補完
        // (登場した種族が対象) では拾えない (実例: 2026-11-23
        // battle_20261123_090354、Staraptor と Gholdengo が最終
        // ヘッダーから落ちた)。同定結果を正として、宣言が 6 体に
        // 満たない分だけ同定順に補う
        if let fin = finalTeams[side] {
            let have = proto.compactMap { l -> String? in
                l.hasPrefix("|poke|\\(side)|") ? String(l.dropFirst("|poke|\\(side)|".count)) : nil
            }
            var extra: [String] = []
            for sp in fin where have.count + extra.count < 6 {
                if !have.contains(where: { sameSpeciesFamily($0, sp) }) && !extra.contains(where: { sameSpeciesFamily($0, sp) }) {
                    extra.append(sp)
                }
            }
            if !extra.isEmpty {
                var at = insertAt + missing.count
                if at > proto.count { at = proto.count }
                proto.insert(contentsOf: extra.map { "|poke|\\(side)|\\($0)" }, at: at)
                added += extra.map { "\\(side):\\($0)" }
            }
        }
    }''',
    "1b header final-team completion")
rep('''    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines, idScores: headerIdScores, pickByCandidate: headerPickByCandidate, slotMargins: headerSlotMargins)''',
    '''    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines, idScores: headerIdScores, pickByCandidate: headerPickByCandidate, slotMargins: headerSlotMargins, finalTeams: ["p2": oppTeamSeen])''',
    "1c header caller")

# ---- 4a2. applyEvent tracks the segment timing ----
rep('''    if line.hasPrefix("|turn|") {
        if let n = Int(line.dropFirst(6)) { currentTurn = n }
    } else if line.hasPrefix("|-weather|") {''',
    '''    if line.hasPrefix("|turn|") {
        if let n = Int(line.dropFirst(6)) { currentTurn = n }
        lastTurnLineAt = sNow()
        segmentFirstMoveAt = nil
    } else if line.hasPrefix("|-weather|") {''',
    "4a2 turn tracking")
rep('''    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq''',
    '''    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq
        if segmentFirstMoveAt == nil { segmentFirstMoveAt = sNow() }''',
    "4a3 move tracking")

# ---- 4c. announcement evidence overrides the developed-segment refusal ----
rep('''                        if segHasMove && !outActed {
                            let pulled = pullBackSwitchBlock(label: "\\(slot): \\(s.speciesEn)", requireEarlySegment: true)''',
    '''                        if segHasMove && !outActed {
                            // 繰り出し文がこのターンに入ってから最初の
                            // 技より前に見えていた場合は、そのターンの
                            // 開始交代である直接証拠があるため、発達
                            // した区間でも引き戻す (実例: 2026-11-23
                            // battle_20261123_090354 ターン3、コータス
                            // の交代は文ではターン頭、プレート確定は
                            // ターン末尾だった)
                            let sideKey = String(slot.prefix(2))
                            let announceOK = sendOutTextSeen[sideKey].map { ev in
                                ev.species == s.speciesEn && ev.at > lastTurnLineAt
                                    && (segmentFirstMoveAt.map { ev.at < $0 } ?? false)
                            } ?? false
                            let pulled = pullBackSwitchBlock(label: "\\(slot): \\(s.speciesEn)", requireEarlySegment: !announceOK)''',
    "4c announce override")

# ---- 4d. status-residual [from] fallback in emitDamageLine ----
rep('''        if let pf = pendingStatusFrom[key], sNow().timeIntervalSince(pf.at) < 5 {
            fromCode = pf.code
            pendingStatusFrom[key] = nil
        }''',
    '''        if let pf = pendingStatusFrom[key], sNow().timeIntervalSince(pf.at) < 5 {
            fromCode = pf.code
            pendingStatusFrom[key] = nil
        }
        // 予告記録が間に合わなかった場合の受け皿: 状態異常が判明して
        // いて、低下量がその経過ダメージに一致し、荒天の経過と紛れ
        // ず、解決中の技の対象でもない低下は、状態異常の経過として
        // 帰属させる (実例: 2026-11-23 battle_20261123_090354
        // ターン3、ミロカロスのやけどチップ行に [from] brn が
        // 付かなかった)
        if fromCode == nil, let st = monStates[key]?.status, st == "brn" || st == "psn",
           logFieldWeather != "Sand" && logFieldWeather != "Snow",
           lastMoveLabel != "\\(slot): \\(speciesEn)",
           !(damagedBySeq[actionSeq] ?? []).contains("\\(slot): \\(speciesEn)") {
            let drop = effFrom - toPct
            if (st == "brn" && (drop == 6 || drop == 7)) || (st == "psn" && (drop == 12 || drop == 13)) {
                fromCode = st
            }
        }''',
    "4d status fallback")

# ---- 4. residual [from] lines are not carried by switch pull-backs ----
rep('''            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
            // 交代行に付随する補完の被ダメ・回復行 (入場時点の差分) も
            // ブロックの一部として一緒に引き戻す。ただし次の技行より
            // 後ろの同名行はその技の結果なので対象にしない
            else if !passedMove && (l.hasPrefix("|-damage|") || l.hasPrefix("|-heal|")) { idxs.append(j) }''',
    '''            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
            // 交代行に付随する補完の被ダメ・回復行 (入場時点の差分) も
            // ブロックの一部として一緒に引き戻す。ただし次の技行より
            // 後ろの同名行はその技の結果なので対象にしない。
            // 経過ダメージ (天候・状態異常・拘束等) の行はターン終了時
            // の出来事であり、入場差分ではないため一緒に移さない
            // (実例: 2026-11-23 battle_20261123_090354 ターン2、
            // ミロカロスの砂嵐チップ行が交代と一緒にターン頭へ
            // 引き戻された)
            else if !passedMove && (l.hasPrefix("|-damage|") || l.hasPrefix("|-heal|")) {
                let residualFroms = ["sandstorm", "hail", "brn", "psn", "tox", "Leech Seed", "Curse", "Salt Cure",
                                     "Fire Spin", "Sand Tomb", "Whirlpool", "Bind", "Wrap", "Clamp", "Magma Storm",
                                     "Infestation", "Snap Trap", "Thunder Cage", "Nightmare"]
                var isResidual = false
                if let r = l.range(of: "[from] ") {
                    let v = String(l[r.upperBound...]).split(separator: "|").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    isResidual = residualFroms.contains(v)
                }
                if !isResidual { idxs.append(j) }
            }''',
    "4b pullback residual exclusion")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
