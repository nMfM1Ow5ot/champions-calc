#!/usr/bin/env python3
"""battle_20261122_070237 修正ラウンドの reader.swift パッチ (準備済み)。
画像認識チャットの claim 解除後に適用する。各編集はアンカー文字列が
ちょうど 1 回だけ現れることを確認してから置換する。
使い方: python3 prep_070237_patch.py [apply]
引数なしではドライラン (アンカーの一致数だけを表示)。"""
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH).read()

EDITS = []

# --- A. slotSwapPending グローバル ---
EDITS.append((
"""var pendingSwitchCount: [String: Int] = [:]       // 同じ種族が連続で見えた回数""",
"""var pendingSwitchCount: [String: Int] = [:]       // 同じ種族が連続で見えた回数
var slotSwapPending: [String: (a: String, b: String, count: Int)] = [:]  // 側 -> 枠入れ替わり候補 (2 回連続で確定)"""))

# --- B. 枠入れ替わり検出 (プレートループの直前) ---
EDITS.append((
"""    for plate in plates {
        guard let s = hits[plate.name] else { continue }""",
"""    // 枠の入れ替わり: 両枠が互いの登録種族を同時に示し、HP もそれぞれの
    // 登録値と一致する場合は、2 件の交代ではなく表示位置の入れ替わり
    // として登録を入れ替える (交代行は出さない)。ひんし交代の後任が
    // 想定と逆の枠に表示される場合に起きる。2 回続けて観測されたら確定
    // する (実例: 2026-11-22 battle_20261122_070237、コータスが左枠・
    //  オオニューラが右枠に表示され、幻の交代行と両枠ともオオニューラ
    //  という状態破損が起きた)
    for (a, b) in [("mineA", "mineB"), ("oppA", "oppB")] {
        let sideKey = a.hasPrefix("mine") ? "mine" : "opp"
        guard let pa = lastSlots[a], let pb = lastSlots[b],
              let ha = hits[a], let hb = hits[b],
              pa.speciesEn != pb.speciesEn,
              ha.speciesEn == pb.speciesEn, hb.speciesEn == pa.speciesEn,
              faintedSlots[slotId(a)] == nil, faintedSlots[slotId(b)] == nil,
              abs(ha.hpPercent - pb.hpPercent) <= 3, abs(hb.hpPercent - pa.hpPercent) <= 3
        else { slotSwapPending[sideKey] = nil; continue }
        if slotSwapPending[sideKey]?.a == ha.speciesEn {
            slotSwapPending[sideKey]?.count += 1
        } else {
            slotSwapPending[sideKey] = (a: ha.speciesEn, b: hb.speciesEn, count: 1)
        }
        guard (slotSwapPending[sideKey]?.count ?? 0) >= 2 else { continue }
        slotSwapPending[sideKey] = nil
        lastSlots[a] = ha
        lastSlots[b] = hb
        let ea = lastEmittedPct[a]; lastEmittedPct[a] = lastEmittedPct[b]; lastEmittedPct[b] = ea
        let fa = firstEntryPlateHP[a]; firstEntryPlateHP[a] = firstEntryPlateHP[b]; firstEntryPlateHP[b] = fa
        for p in [a, b] {
            pendingDamagePct[p] = nil; pendingDamageCount[p] = nil; pendingDamageSince[p] = nil
            pendingSwitchSpecies[p] = nil; pendingSwitchCount[p] = nil; pendingSwitchSince[p] = nil
            heldLine[p] = nil; suspectJump[p] = nil
        }
        debugCapture(kind: "slot_swap", key: "slot_swap:\\(sideKey):\\(currentTurn)", rawText: "",
                     detail: ["side": sideKey, "a": "\\(a)=\\(ha.speciesEn)", "b": "\\(b)=\\(hb.speciesEn)", "turn": currentTurn])
        print("[reader] 枠の表示位置の入れ替わりを検出し、登録を入れ替えました: \\(a)=\\(ha.speciesEn) / \\(b)=\\(hb.speciesEn)")
        fflush(stdout)
    }
    for plate in plates {
        guard let s = hits[plate.name] else { continue }"""))

# --- C. anyAwaitingReplacement ヘルパ (awaitingReplacement の直後) ---
EDITS.append((
"""    return seen.contains { !onField.contains($0) && (monStates["\\(side):\\($0)"]?.hpPercent ?? 0) > 0 }
}""",
"""    return seen.contains { !onField.contains($0) && (monStates["\\(side):\\($0)"]?.hpPercent ?? 0) > 0 }
}

// どちらかの側が、ひんし交代の要員待ち (場が 1 体で後任が未登録) か
func anyAwaitingReplacement() -> Bool {
    awaitingReplacement("mine", "p1") || awaitingReplacement("opp", "p2")
}

// key (変化を受ける側) の反対側で、入場効果の原因になる交代が
// 未確定 (プレート確定待ち、またはひんし交代の要員待ち) か
func entryEffectPending(key: String) -> Bool {
    let otherPrefix = key.hasPrefix("p1") ? "opp" : "mine"
    let otherSide = key.hasPrefix("p1") ? "p2" : "p1"
    return !pendingSwitchSpecies.filter({ $0.key.hasPrefix(otherPrefix) }).isEmpty
        || awaitingReplacement(otherPrefix, otherSide)
}"""))

# --- D1. setWeather の保留条件 ---
EDITS.append((
"""    if !stale && !text.isEmpty && !fieldHoldBypass && !pendingSwitchSpecies.isEmpty {
        if heldWeatherStart?.ui != ui {""",
"""    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {
        if heldWeatherStart?.ui != ui {"""))

# --- D2. setTerrain の保留条件 ---
EDITS.append((
"""    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)
    if !stale && !text.isEmpty && !fieldHoldBypass && !pendingSwitchSpecies.isEmpty {""",
"""    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {"""))

# --- E. フィールド保留のフラッシュ条件 ---
EDITS.append((
"""    if heldWeatherStart != nil || heldTerrainStart != nil {
        let ready = pendingSwitchSpecies.isEmpty
            || Date().timeIntervalSince((heldWeatherStart?.at ?? heldTerrainStart?.at) ?? .distantPast) > 6.0""",
"""    if heldWeatherStart != nil || heldTerrainStart != nil {
        // 要員待ちが続く間は上限を延ばす (要員選択は 6 秒を超えることが
        // 普通にある。要員が登録されれば即座に流れる)
        let awaitingNow = anyAwaitingReplacement()
        let heldAge = Date().timeIntervalSince((heldWeatherStart?.at ?? heldTerrainStart?.at) ?? .distantPast)
        let ready = (pendingSwitchSpecies.isEmpty && !awaitingNow) || heldAge > (awaitingNow ? 20.0 : 6.0)"""))

# --- F. applyBoost の入場効果保留 (条件拡張 + 同一個体の後続変化) ---
EDITS.append((
"""    } else if stat == "atk" && delta < 0 && Date().timeIntervalSince(lastMoveMsgAt) > 3
                && !pendingSwitchSpecies.filter({ $0.key.hasPrefix(key.hasPrefix("p1") ? "opp" : "mine") }).isEmpty {""",
"""    } else if stat == "atk" && delta < 0 && Date().timeIntervalSince(lastMoveMsgAt) > 3
                && entryEffectPending(key: key) {"""))
EDITS.append((
"""        heldEntryBoosts.append((key: key, line: line, at: Date()))
    } else {
        emitLog(line, applyNow: false)
    }""",
"""        heldEntryBoosts.append((key: key, line: line, at: Date()))
    } else if heldEntryBoosts.contains(where: { $0.key == key }) && Date().timeIntervalSince(lastMoveMsgAt) > 3 {
        // 入場効果として保留中の個体の後続の変化 (いかくを受けた
        // かちき の特攻上昇など) も、原因の交代行が出るまで一緒に
        // 保留する (片方だけ先に出ると順序が崩れる。実例: 2026-11-22
        // battle_20261122_070237、ミロカロスの攻撃低下と特攻上昇が
        // キュウコンとムクホークの交代行より前に並んだ)
        heldEntryBoosts.append((key: key, line: line, at: Date()))
    } else {
        emitLog(line, applyNow: false)
    }"""))

# --- G. heldEntryBoosts の末尾フラッシュ条件 ---
EDITS.append((
"""    if !heldEntryBoosts.isEmpty && pendingSwitchSpecies.isEmpty { flushHeldEntryBoosts() }""",
"""    if !heldEntryBoosts.isEmpty && pendingSwitchSpecies.isEmpty && !anyAwaitingReplacement() { flushHeldEntryBoosts() }"""))

# --- H. flushHeldBoostsTimeout の上限 ---
EDITS.append((
"""func flushHeldBoostsTimeout() {
    if heldEntryBoosts.contains(where: { Date().timeIntervalSince($0.at) > 6 }) { flushHeldEntryBoosts() }""",
"""func flushHeldBoostsTimeout() {
    let cap: TimeInterval = anyAwaitingReplacement() ? 20 : 6
    if heldEntryBoosts.contains(where: { Date().timeIntervalSince($0.at) > cap }) { flushHeldEntryBoosts() }"""))

# --- I. ひんし文の濁点ゆれ (3 か所) ---
EDITS.append((
"""    if t.contains("たおれた") || t.contains("効果は") || t.contains("回復") { return false }""",
"""    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") || t.contains("効果は") || t.contains("回復") { return false }"""))
EDITS.append((
"""    if (t.hasSuffix("！") || t.hasSuffix("!")) && !t.contains("たおれた") {""",
"""    if (t.hasSuffix("！") || t.hasSuffix("!")) && !t.contains("たおれた") && !foldDakuten(t).contains("たおれた") {"""))
EDITS.append((
"""    // ひんし (プレート側で既に 0% になっている場合も文は消費する。
    // 消費しないと |-message| に化けて同じ文が残り続ける)
    if t.contains("たおれた") {""",
"""    // ひんし (プレート側で既に 0% になっている場合も文は消費する。
    // 消費しないと |-message| に化けて同じ文が残り続ける)。
    // 末尾の濁点ゆれ (たおれだ) も拾う (実例: 2026-11-22
    // battle_20261122_070237、ひんし文が faint 行と併記で残った)
    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {"""))

# --- J. 行動不能文の 動→勤 ゆれ ---
EDITS.append((
"""    let cantCode = (t.contains("しびれて") && t.contains("動けない")) ? "par"
        : (t.contains("凍って") && t.contains("動けない")) ? "frz\"""",
"""    // 「動けない」の 動 が 勤 に崩れる OCR ゆれも拾う (実例: 2026-11-22
    // battle_20261122_070237、「凍ってしまって勤けない！」が行動不能行と
    // 併記で日本語のまま残った)
    let cantVerb = t.contains("動けない") || t.contains("勤けない")
    let cantCode = (t.contains("しびれて") && cantVerb) ? "par"
        : (t.contains("凍って") && cantVerb) ? "frz\""""))

# --- K. HP 補正の 0% 除外 ---
EDITS.append((
"""        if effFrom - toPct <= 3, let lt = prevDamageAt, Date().timeIntervalSince(lt) >= 10,""",
"""        if toPct != 0, effFrom - toPct <= 3, let lt = prevDamageAt, Date().timeIntervalSince(lt) >= 10,"""))

# --- L. オボンのみ回復の途中値保留 ---
EDITS.append((
"""        let src = healSource(plateName: plateName, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        // 発生源を特定できず、回復技・ねがいごとの遅延回復・吸収特性""",
"""        let src = healSource(plateName: plateName, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        // オボンのみと分類できた回復が本来の +25% に大きく届かず、かつ
        // プレートの最新読みがさらに上を示している場合は、回復
        // アニメーションの途中値とみて確定せずに戻す (基準値は戻し、
        // 後続の読みが最終値で再駆動する。実例: 2026-11-22
        // battle_20261122_070237、+20% で確定し、残り +5% が出所不明の
        // 回復として二重に残った)
        if src?.label == "item: Sitrus Berry", effFrom <= 50, toPct - effFrom <= 21,
           (lastSlots[plateName]?.hpPercent ?? toPct) > toPct {
            lastEmittedPct[plateName] = effFrom
            return false
        }
        // 発生源を特定できず、回復技・ねがいごとの遅延回復・吸収特性"""))

# --- M. attributeFieldAbilities 第 3 パス (別フォルムからの訂正と帰属) ---
EDITS.append((
"""            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: forme, abilityEn: ab)
        }
    }
}""",
"""            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: forme, abilityEn: ab)
        }
    }
    // 別フォルム側のフィールド特性: 現在の天候・地形が、場の誰の現在の
    // フォルムでも説明できず、交代で入った相手の同種族の別フォルム
    // (リージョンフォルム等) の特性でだけ説明できる場合は、フォルムの
    // 登録自体が誤りとみて訂正した上で帰属する (プレート同定は同名
    // フォルムを区別できず、見せ合い側でも通常種として登録される
    // ことがある。実例: 2026-11-22 battle_20261122_070237、キュウコン
    // (アローラ) が通常種で登録され、ゆきふらし が帰属しなかった)
    for (key, sw) in Array(lastSwitchIn) {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        guard side == "p2" else { continue }
        for ab in [weatherAb[logFieldWeather], terrainAb[logFieldTerrain]].compactMap({ $0 }) {
            // 場の誰かの現在のフォルムで説明できるなら、その個体が原因
            if lastSlots.values.contains(where: { (speciesAbilityMap[$0.speciesEn] ?? []).contains(ab) }) { continue }
            // 自分の現在のフォルムで持てるなら通常の帰属が担当する
            if (speciesAbilityMap[en] ?? []).contains(ab) { continue }
            guard let entry = speciesDict.first(where: { $0.en == en }) else { continue }
            let cands = formeGroup(entry).filter { $0.en != en && (speciesAbilityMap[$0.en] ?? []).contains(ab) }
            guard cands.count == 1, let newEn = cands.first?.en else { continue }
            var matched = false
            if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            let inTurn = switchInTurn[key].map { max($0, 1) }
            if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
            if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
            guard matched else { continue }
            correctFormeByAbility(side: side, slot: sw.slot, speciesEn: en, abilityEn: ab)
            fieldAbilityDone["\\(side):\\(newEn)"] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: newEn, abilityEn: ab)
        }
    }
}"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for i, (old, new) in enumerate(EDITS):
    n = src.count(old)
    print(f"edit {i + 1}: anchor count = {n}")
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
