#!/usr/bin/env python3
# battle_20261122_231107 fix round (plan: FIX_231107_PLAN.md).
# Item 1 (high): replacementBusy switch confirmation — defer instead of drop.
# Item 2 (mid): miss guard accepts sendOutTextSeen evidence.
# Item 3 (mid): completeArchiveHeader removal selection — runner-up evidence
#   + within-slot margin, replacing cross-slot raw-score order.
# Item 5 (low): recordTurnEvidence HP from monStates.
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count {n} != {count}")
        sys.exit(1)
    src = src.replace(old, new, count)
    print("OK", tag)

# ---------- Item 5: recordTurnEvidence HP ----------
rep('''        if let s = lastSlots[name] {
            slots[name] = ["species": s.speciesEn, "hp": s.hpPercent] as [String: Any]''',
    '''        if let s = lastSlots[name] {
            // HP は枠の読みではなく追跡値 (monStates) を正とする。
            // 枠の読みが古いと前の占有者の HP が証拠に残る
            // (実例: 2026-11-22 battle_20261122_231107、turn_decided の
            // oppB に Pelipper の 35 が残り、追跡値は 90 だった)
            let side = name.hasPrefix("mine") ? "p1" : "p2"
            let hp = monStates["\\(side):\\(s.speciesEn)"]?.hpPercent ?? s.hpPercent
            slots[name] = ["species": s.speciesEn, "hp": hp] as [String: Any]''',
    "item5 turn evidence hp")

# ---------- Item 2: miss guard text evidence ----------
rep('''                || switchInTurn["\\(side):\\(sp.en)"] == currentTurn''',
    '''                || switchInTurn["\\(side):\\(sp.en)"] == currentTurn
                // 繰り出し文の証拠も、プレート経路とは独立に入場を
                // 裏付ける (実例: 2026-11-22 battle_20261122_231107、
                // 交代確定が要員選択のガードで落ち、候補も未形成の
                // 間に来たミス文には文証拠だけが残っていた)
                || (sendOutTextSeen[side].map { $0.species == sp.en && sNow().timeIntervalSince($0.at) < 20 } ?? false)''',
    "item2 miss text evidence")

# ---------- Item 1: defer instead of drop ----------
rep('''                let pendingSwitchAge = pendingSwitchSince[plate.name].map { sNow().timeIntervalSince($0) } ?? 0
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
                pendingSwitchCandidates[plate.name] = nil
                if sendOutTextSeen[side]?.species == s.speciesEn { sendOutTextSeen[side] = nil }''',
    '''                let pendingSwitchAge = pendingSwitchSince[plate.name].map { sNow().timeIntervalSince($0) } ?? 0''',
    "item1a move clearing")

rep('''                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                    && pendingSwitchAge < 20
                if !replacementBusy {''',
    '''                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                    && pendingSwitchAge < 20
                if replacementBusy {
                    // 破棄ではなく保留にする: 候補の蓄積を消すと、要員
                    // 選択が終わった後に確定する道まで断たれる (実例:
                    // 2026-11-22 battle_20261122_231107、ターン2頭の
                    // Charizard→Venusaur の確定試行が Farigiraf の
                    // ひんし後の選択中に届いて破棄され、交代行が
                    // ターン末尾へ遅れた)。静定時計を現在へ戻して
                    // 先送りすれば、選択画面の幻の候補は画面が消えた
                    // 後に新たな静定を得られず期限で落ち、本物の交代
                    // だけが場の読みで静定し直して確定する
                    if var cand = pendingSwitchCandidates[plate.name]?[s.speciesEn] {
                        cand.firstSeen = sNow()
                        cand.count = 1
                        pendingSwitchCandidates[plate.name]?[s.speciesEn] = cand
                    }
                    pendingSwitchSince[plate.name] = sNow()
                    pendingSwitchCount[plate.name] = 1
                } else {
                    pendingSwitchSpecies[plate.name] = nil
                    pendingSwitchCount[plate.name] = nil
                    pendingSwitchSince[plate.name] = nil
                    pendingSwitchCandidates[plate.name] = nil
                    if sendOutTextSeen[side]?.species == s.speciesEn { sendOutTextSeen[side] = nil }
                }
                if !replacementBusy {''',
    "item1b defer on busy")

# ---------- Item 3: header snapshots ----------
rep('''var headerIdScores: [String: Double] = [:]   // "p2:種族" -> 見せ合い同定のベストスコア (開始時点の控え。ヘッダー補完の削除候補の優先順位に使う)''',
    '''var headerIdScores: [String: Double] = [:]   // "p2:種族" -> 見せ合い同定のベストスコア (開始時点の控え。ヘッダー補完の削除候補の優先順位に使う)
var headerPickByCandidate: [String: String] = [:]   // "p2:候補種族" -> その種族が次点だった枠の pick (開始時点の控え。ヘッダー補完で誤同定の枠を外す証拠)
var headerSlotMargins: [String: Double] = [:]   // "p2:pick種族" -> その枠での次点とのスコア差 (開始時点の控え)''',
    "item3a globals")

rep('''    headerIdScores = [:]
    for slotVotes in previewEvidenceVotes {
        for entry in slotVotes {
            if let sp = entry["species"] as? String, let best = entry["best"] as? Double {
                let k = "p2:\\(sp)"
                headerIdScores[k] = max(headerIdScores[k] ?? -1, best)
            }
        }
    }''',
    '''    headerIdScores = [:]
    headerPickByCandidate = [:]
    headerSlotMargins = [:]
    for slotVotes in previewEvidenceVotes {
        for entry in slotVotes {
            if let sp = entry["species"] as? String, let best = entry["best"] as? Double {
                let k = "p2:\\(sp)"
                headerIdScores[k] = max(headerIdScores[k] ?? -1, best)
            }
        }
        // 枠内の順位関係も控える: pick (最良) と次点の対応は、後の
        // ヘッダー補正で「どの枠が誤同定だったか」を決める証拠になる
        let ranked = slotVotes.compactMap { e -> (String, Double)? in
            guard let sp = e["species"] as? String, let best = e["best"] as? Double else { return nil }
            return (sp, best)
        }.sorted { $0.1 < $1.1 }
        if let pick = ranked.first {
            if let runner = ranked.dropFirst().first {
                headerSlotMargins["p2:\\(pick.0)"] = runner.1 - pick.1
            }
            for cand in ranked.dropFirst() {
                let k = "p2:\\(cand.0)"
                if let prev = headerPickByCandidate[k], prev != pick.0 {
                    headerPickByCandidate[k] = nil   // 複数枠の次点で pick が割れる場合は証拠にしない
                } else {
                    headerPickByCandidate[k] = pick.0
                }
            }
        }
    }''',
    "item3b snapshot build")

# resetLogState clearing for the new globals (next to headerIdScores clear)
rep('''    headerOppTeam = []
    headerIdScores = [:]''',
    '''    headerOppTeam = []
    headerIdScores = [:]
    headerPickByCandidate = [:]
    headerSlotMargins = [:]''',
    "item3c reset clear")

# completeArchiveHeader signature + call site
rep('''func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {''',
    '''func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:], pickByCandidate: [String: String] = [:], slotMargins: [String: Double] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {''',
    "item3d signature")
rep('''    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines, idScores: headerIdScores)''',
    '''    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines, idScores: headerIdScores, pickByCandidate: headerPickByCandidate, slotMargins: headerSlotMargins)''',
    "item3e call site")

# removal selection rewrite
rep('''            if removeCount > 0 {
                // 削除候補は同定スコアの低い順に選ぶ (スコアが無い
                // 種族は最後尾扱い、同点は宣言の後ろのものから)。
                // 位置だけで末尾から落とすと、正しく同定された
                // 種族が誤同定より先に落ちる (実例: 2026-11-22
                // battle_20261122_185505、Kommo-o (スコア 0.332) が
                // 落ち、0.126 の Slowking-Galar が残った)
                let removing = Array(unused.enumerated().sorted { a, b in
                    let sa = idScores["\\(side):\\(a.element)"] ?? .infinity
                    let sb = idScores["\\(side):\\(b.element)"] ?? .infinity
                    if sa != sb { return sa < sb }
                    return a.offset > b.offset
                }.prefix(removeCount).map { $0.element })''',
    '''            if removeCount > 0 {
                // 削除候補の選定: (1) 実登場した未宣言種族が次点だった
                // 枠の pick を最優先で落とす (その枠の同定が誤りだった
                // 直接証拠)。(2) 残りは枠内の優位差 (次点とのスコア差)
                // が小さい順 (辛勝の枠ほど誤同定の疑いが強い)。
                // 生スコア順は採らない: スコアは枠ごとの距離であり、
                // 枠をまたいだ比較は意味を持たない (実例: 2026-11-22
                // battle_20261122_231107、正しい Sneasler (-0.190) が
                // 落ち、誤同定の Barbaracle (0.45) が残った。185505
                // では逆の数値関係で生スコア順が偶然機能していた)
                var pool = unused
                var picked: [String] = []
                for m in missing {
                    if let pick = pickByCandidate["\\(side):\\(m)"],
                       pool.contains(pick), !picked.contains(pick) {
                        picked.append(pick)
                        pool.removeAll { $0 == pick }
                    }
                    if picked.count >= removeCount { break }
                }
                if picked.count < removeCount {
                    let rest = Array(pool.enumerated().sorted { a, b in
                        let ma = slotMargins["\\(side):\\(a.element)"] ?? .infinity
                        let mb = slotMargins["\\(side):\\(b.element)"] ?? .infinity
                        if ma != mb { return ma < mb }
                        return a.offset > b.offset
                    }.prefix(removeCount - picked.count).map { $0.element })
                    picked += rest
                }
                let removing = picked''',
    "item3f removal selection")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL PATCHES APPLIED, size", len(orig), "->", len(src))
