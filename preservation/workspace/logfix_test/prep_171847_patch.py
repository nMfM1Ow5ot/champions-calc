#!/usr/bin/env python3
# reader.swift fixes for battle_20261122_171847 (log-analysis request):
# G1 pull-back guard for faint replacements
# G2a sibling-identical hold excludes faints (toPct == 0)
# G2b suspect adoption never silently adopts 0 (falls through to emission)
# G2c faint-text branch: occupant-based compensation, not monStates-gated
# G3 noteBattleMaxRead: reject reads colliding with another species' max
# G4 processPlates: rescale mine reads whose max differs from the known max
# G5a boost fragment retention for subject-only fragments
# G5b Life Orb capped recoil (toPct == 0) classification
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

# ---- G2b: suspect 0 falls through ----
rep("G2b suspect zero fall-through",
    """    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct {
            if currentTurn > sj.turn {""",
    """    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct && sj.toPct == 0 {
            // 0% の持続は状態訂正ではなく ひんし。無音で取り込むと
            // 被ダメ行・ひんし行が丸ごと消えるため、疑いを解いて
            // 通常処理へ落とす (実例: 2026-11-22
            // battle_20261122_171847、アーマーキャノンで倒れた
            // Kingambit が hp_jump_adopted で無音採用された)
            suspectJump[plateName] = nil
        } else if toPct == sj.toPct {
            if currentTurn > sj.turn {""")

# ---- G2c: faint-text branch restructure ----
rep("G2c faint-text branch",
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
            // プレートで 0% を読む前に倒れた場合 (ひんしアニメーションで
            // プレートがすぐ消える等)、被ダメ行もここで補う
            // (実例: 2026-11-20、イエッサンとオオニューラの ひんし に
            //  被ダメ行が付かなかった)
            let pn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            if !pn.isEmpty && (lastEmittedPct[pn] ?? 1) > 0 {
                heldLine[pn] = nil
                let fhp = monStates[key]?.hpMax.map { "0/\\($0)" } ?? "0/100"
                _ = emitDamageLine(plateName: pn, slot: slot, key: key, speciesEn: sp.en,
                                   fromPct: lastEmittedPct[pn] ?? (monStates[key]?.hpPercent ?? 100),
                                   toPct: 0, hpText: fhp, force: true)
            }
            // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
            deferFaint(slot: slot, speciesEn: sp.en)
        }
        return true
    }""",
    """    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
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
        // 占有者の ひんし文は確定情報として扱う。プレートが先に 0%
        // を読んで monStates だけが 0 になっている場合でも、
        // lastEmittedPct が残っていれば被ダメ行はまだ出ていない
        // (プレートの 0% 確定には 2 フレーム必要で、ひんしアニメー
        // ションでプレートが消えると確定しないまま文だけが届く。
        // 実例: 2026-11-22 battle_20261122_171847、Charizard の
        // 被ダメ行・ひんし行が無音で消えた)
        if !faintPn.isEmpty && (lastEmittedPct[faintPn] ?? 1) > 0 {
            heldLine[faintPn] = nil
            let fhp = monStates[key]?.hpMax.map { "0/\\($0)" } ?? "0/100"
            _ = emitDamageLine(plateName: faintPn, slot: slot, key: key, speciesEn: sp.en,
                               fromPct: lastEmittedPct[faintPn] ?? (monStates[key]?.hpPercent ?? 100),
                               toPct: 0, hpText: fhp, force: true)
        }
        // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
        deferFaint(slot: slot, speciesEn: sp.en)
        return true
    }""")

# ---- G3: max collision guard ----
rep("G3 noteBattleMaxRead collision guard",
    """    if let curText = monStates["p1:\\(speciesEn)"]?.hpText,
       let cur = Int(curText.split(separator: "/").first ?? ""), readMax < cur { return }""",
    """    if let curText = monStates["p1:\\(speciesEn)"]?.hpText,
       let cur = Int(curText.split(separator: "/").first ?? ""), readMax < cur { return }
    // 別種族の既知の最大と寸分違わぬ読みは、隣枠の最大の混入の疑い
    // として候補に数えない (実例: 2026-11-22 battle_20261122_171847、
    // Sneasler の最大として同じ自軍の Indeedee-F の最大 177 が
    // 2 回続けて読まれ、そのまま採用されて幻の被ダメ行が出た)
    for (other, entry) in teamEntries where other != speciesEn {
        if let h = (entry["stats"] as? [String: Int])?["hp"], h == readMax { return }
    }
    for (k, st) in monStates where k.hasPrefix("p1:") && k != "p1:\\(speciesEn)" {
        if let h = st.hpMax, h == readMax { return }
    }""")

# ---- G4: processPlates rescale ----
rep("G4 mine max rescale",
    """        let prev = lastSlots[plate.name]
        if prev?.speciesEn != s.speciesEn {""",
    """        // 自軍の読みの最大が既知の最大と食い違う場合 (最大の断片
        // 読み 145 -> 45 等)、割合の方は正しいことが多いため、行の
        // 構築に使う現在値を既知の最大で組み直す。読みの最大その
        // ものの採否は noteBattleMaxRead が別途扱う (実例:
        // 2026-11-22 battle_20261122_171847、サーナイトの被ダメ行が
        // 11/45 になった)
        var s = s
        if side == "p1", let readMax = s.hpMax, s.hpCur != nil,
           let entry = speciesDict.first(where: { $0.en == s.speciesEn }),
           let knownMax = battleKnownMax(speciesEn: s.speciesEn, grp: formeGroup(entry)),
           knownMax > 0, readMax != knownMax {
            s.hpCur = Int((Double(s.hpPercent) / 100.0 * Double(knownMax)).rounded())
            s.hpMax = knownMax
        }
        let prev = lastSlots[plate.name]
        if prev?.speciesEn != s.speciesEn {""")

# ---- G5a: subject-only boost fragment ----
rep("G5a subject-only fragment retention",
    """        let statWords = ["攻撃", "防御", "特攻", "特防", "素早さ", "命中率", "回避率",
                         "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ"]
        if statWords.contains(where: { t.contains($0) }) {""",
    """        let statWords = ["攻撃", "防御", "特攻", "特防", "素早さ", "命中率", "回避率",
                         "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ"]
        // 能力名を含まない主語だけの断片 (「相手のガブリアスの」で
        // 読みが分かれ、能力名と動詞が次の読みに来る形) も覚える。
        // 文の途中で切れた形 (末尾が「の」) に限る (実例: 2026-11-22
        // battle_20261122_171847、がんせきふうじの素早さ低下文が
        // 未翻訳で残った)
        if statWords.contains(where: { t.contains($0) }) || t.hasSuffix("の") {""")

# ---- G5b: Life Orb capped recoil ----
rep("G5b Life Orb capped recoil",
    """                if (9...11).contains(drop), knownItem == nil || knownItem == "いのちのたま" {""",
    """                // 残り HP が少なく反動が上限で切り取られた場合
                // (8% から 0% 等) も、持ち物が判明していれば
                // いのちのたまの反動として分類する (実例: 2026-11-22
                // battle_20261122_171847、ガブリアスの反動ひんし行に
                // [from] が付かなかった)
                if ((9...11).contains(drop) || (toPct == 0 && drop <= 11 && knownItem == "いのちのたま")),
                   knownItem == nil || knownItem == "いのちのたま" {""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
