#!/usr/bin/env python3
"""battle_20261122_091721 の reader 側 6 件の対応。
使い方: python3 prep_091721_patch.py [apply]"""
import re
import subprocess
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH).read()
EDITS = []

# E1: lastMoveSigSeq の宣言
EDITS.append((
"""var lastMoveSigAt: [String: Date] = [:]           // "枠|技EN" -> |move| を出した時刻 (OCR ゆれでの二重出力防止)""",
"""var lastMoveSigAt: [String: Date] = [:]           // "枠|技EN" -> |move| を出した時刻 (OCR ゆれでの二重出力防止)
var lastMoveSigSeq: [String: Int] = [:]           // "枠|技EN|tN" -> その技行を出した時点の行動番号 (境界検出の遅れ判定)
var prevBoostFragment: (text: String, speciesEn: String, side: String, at: Date)? = nil   // ランク変化文の断片 (主語+能力名だけ先に届いた文)"""))

# E2: リセット
EDITS.append((
"""    lastMoveSigAt = [:]""",
"""    lastMoveSigAt = [:]
    lastMoveSigSeq = [:]"""))

# E3: 技行の重複抑止にターン境界の遅れを織り込む
EDITS.append((
"""                let sig = slot + "|" + moveEn + "|t" + String(currentTurn)
                if lastMoveSigAt[sig] != nil { return true }
                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                lastMoveSigAt[sig] = Date()
                lastMoveSigAt[slot + "|" + moveEn] = Date()""",
"""                let sig = slot + "|" + moveEn + "|t" + String(currentTurn)
                if lastMoveSigAt[sig] != nil {
                    // 同じ枠の同じ技が同じターン番号ですでに出ている場合でも、
                    // その後に技行が 2 件以上進み 10 秒以上経っていて、その枠が
                    // この区間ですでに技を使っているなら、ターン境界の検出が
                    // 遅れている次ターンの技とみなして通す (ターン行は
                    // emitLog のガードが先に出す)。ログ画面の再読のような
                    // 近接した再処理は従来どおり落とす (実例: 2026-11-22
                    // battle_20261122_091721、こだわりスカーフのニョロトノの
                    // だくりゅう が境界検出より先に届いて重複として落ち、
                    // 被ダメ行だけが前のターンに付いた)
                    let moverLabel = "\\(slot): \\(sp.en)"
                    let advanced = actionSeq - (lastMoveSigSeq[sig] ?? 0) >= 2
                    let waited = Date().timeIntervalSince(lastMoveSigAt[sig]!) >= 10
                    if !(movesSinceTurnLine.contains(moverLabel) && advanced && waited) { return true }
                }
                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                lastMoveSigAt[sig] = Date()
                lastMoveSigAt[slot + "|" + moveEn] = Date()
                lastMoveSigSeq[sig] = actionSeq"""))

# E4: pullBackSwitchBlock (emitLog の直前へ)
EDITS.append((
"""func emitLog(_ line: String) { emitLog(line, applyNow: true) }""",
"""// ターン開始の交代行ブロックを、挿入するターン行の直後へ移す。
// 交代行と、その枠の付随行 (持ち物の判明・フォルム変化・メガ進化・
// 特性) だけを対象にする。ターン行以降・交代行より前に同じ側の
// ひんし行がある交代 (ひんし交代) は対象にしない。表示側は交代の
// 描画行を一緒に移す (実例: 2026-11-22 battle_20261122_091721、
// ゲンガーの交代とメガ進化がターン6の末尾に記録された)
func pullBackSwitchBlock(label: String) -> (proto: [String], display: [String]) {
    guard let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) else { return ([], []) }
    var switchIdx: Int? = nil
    for i in (turnIdx + 1)..<battleLog.count {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|switch|"), f.count >= 3, f[2] == label { switchIdx = i }
    }
    guard let si = switchIdx else { return ([], []) }
    let side = String(label.prefix(2))
    for i in (turnIdx + 1)..<si {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|faint|"), f.count >= 3, f[2].hasPrefix(side) { return ([], []) }
    }
    var idxs = [si]
    if si + 1 < battleLog.count {
        for j in (si + 1)..<battleLog.count {
            let l = battleLog[j]
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, f[2] == label else { continue }
            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
        }
    }
    let pulled = idxs.map { battleLog[$0] }
    for i in idxs.reversed() { battleLog.remove(at: i) }
    // 表示側: 交代の描画 (引き戻し行 + 繰り出し行) と石への反応・
    // メガ進化の描画行を、最後のターン見出しより後ろから集める
    let species = label.split(separator: ":").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    var dispIdxs: [Int] = []
    var dStart = 0
    for (i, l) in displayLog.enumerated() where l.hasPrefix("Turn ") { dStart = i + 1 }
    if !species.isEmpty, dStart < displayLog.count {
        for i in dStart..<displayLog.count {
            let l = displayLog[i]
            if l == "Go! \\(species)!" || l.hasSuffix("sent out \\(species)!") { dispIdxs.append(i) }
            else if l.hasSuffix("is reacting to the Key Stone!") && l.contains(species) { dispIdxs.append(i) }
            else if l.contains("has Mega Evolved into") && l.contains(species) { dispIdxs.append(i) }
        }
        if let first = dispIdxs.first, first > dStart {
            let prev = displayLog[first - 1]
            if prev.hasSuffix("come back!") || prev.contains("withdrew") { dispIdxs.insert(first - 1, at: 0) }
        }
    }
    let pulledDisplay = dispIdxs.map { displayLog[$0] }
    for i in dispIdxs.reversed() { displayLog.remove(at: i) }
    return (pulled, pulledDisplay)
}

func emitLog(_ line: String) { emitLog(line, applyNow: true) }"""))

# E5: ターン行ガードの (c) 判定と交代ブロックの引き戻し
EDITS.append((
"""            var guardN: Int? = nil
            if currentTurn == 0 && !roundEventSeen { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if let mover, currentTurn >= 1, !movesSinceTurnLine.isEmpty,
                    !movesSinceTurnLine.contains(mover),
                    enteredThisSegment.contains(mover.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") { guardN = currentTurn + 1 }
            if let n = guardN {
                if debugMode { print("[reader] ターン行ガードが発火しました: |turn|\\(n) を先に出します (きっかけ: \\(line))") }
                fflush(stdout)
                debugCapture(kind: "turn_guard", key: "turn_guard:\\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild,
                                      "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\\(n)")   // この呼び出しで追跡状態はリセットされる
            }""",
"""            var guardN: Int? = nil
            // (c) の条件 (この区間で交代で入った枠の最初の技) は、交代行
            // ブロックの引き戻し判定にも使うため先に確定させる
            let ruleC = mover.map { mv in
                currentTurn >= 1 && !movesSinceTurnLine.isEmpty && !movesSinceTurnLine.contains(mv)
                    && enteredThisSegment.contains(mv.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            } ?? false
            if currentTurn == 0 && !roundEventSeen { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if ruleC { guardN = currentTurn + 1 }
            if let n = guardN {
                // (c) で発火した場合、原因の交代はターン開始の交代であり、
                // その行ブロックが前のターンの末尾に出ていることがある。
                // ターン行の直後へ移す (実例: 2026-11-22
                // battle_20261122_091721、ゲンガーの交代とメガ進化)
                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                if ruleC, let mover { (pulledProto, pulledDisplay) = pullBackSwitchBlock(label: mover) }
                if debugMode { print("[reader] ターン行ガードが発火しました: |turn|\\(n) を先に出します (きっかけ: \\(line))") }
                fflush(stdout)
                debugCapture(kind: "turn_guard", key: "turn_guard:\\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild,
                                      "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\\(n)")   // この呼び出しで追跡状態はリセットされる
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
            }"""))

# E6: 「ゆけっ」の枠割り当て
EDITS.append((
"""        for (i, e) in found.prefix(2).enumerated() {
            let plateName = i == 0 ? "mineA" : "mineB"
            if monStates["p1:\\(e.en)"] == nil { monStates["p1:\\(e.en)"] = MonState() }
            if lastSlots[plateName]?.speciesEn != e.en {""",
"""        for e in found.prefix(2) {
            if monStates["p1:\\(e.en)"] == nil { monStates["p1:\\(e.en)"] = MonState() }
            // 文が 1 体ずつ届く場合、並び順の決め打ちでは 2 体目が
            // 先発の枠 (mineA) へ重なり、誤った枠の交代行と、プレート
            // 確定時の二重の交代行を生む (実例: 2026-11-22
            // battle_20261122_091721、ブリジュラスが p1a に出て、
            // 先発の交代行が二重になった)。登録済みの種族は飛ばし、
            // 空いている枠の若い方へ割り当てる
            if lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en { continue }
            let plateName = lastSlots["mineA"] == nil ? "mineA" : "mineB"
            if lastSlots[plateName]?.speciesEn != e.en {"""))

# E7: entryEffectPending の開幕拡張
EDITS.append((
"""    return !pendingSwitchSpecies.filter({ $0.key.hasPrefix(otherPrefix) }).isEmpty
        || sideAwaitingReplacement(otherPrefix, otherSide)
}""",
"""    return !pendingSwitchSpecies.filter({ $0.key.hasPrefix(otherPrefix) }).isEmpty
        || sideAwaitingReplacement(otherPrefix, otherSide)
        // 開幕は、相手の先発がプレートに読まれる前に特性の効果文が
        // 届くことがある。その間は入場効果が未確定として扱う
        // (実例: 2026-11-22 battle_20261122_091721、いかくの攻撃低下行が
        //  原因の交代行・特性行より先に出た)
        || (currentTurn <= 1 && (fieldSeen[otherSide]?.count ?? 0) < 2)
}"""))

# E8: healSource の吸収優先と消費済みガード
EDITS.append((
"""    let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
        : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
    if fromPct <= 50 && (12...30).contains(delta) {""",
"""    let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
        : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
    // 自分が直前に使った吸収技による回復は、持ち物の回復より優先して
    // 技へ帰属させる (実例: 2026-11-22 battle_20261122_091721、
    // ドレインキッスの吸収回復が、消費済みの オボンのみ の再発動に化けた)
    let drainMoves: Set<String> = ["Absorb", "Mega Drain", "Giga Drain", "Drain Punch", "Leech Life",
                                   "Horn Leech", "Oblivion Wing", "Parabolic Charge", "Draining Kiss",
                                   "Dream Eater", "Bitter Blade", "Matcha Gotcha", "Strength Sap"]
    let mySlot = slotFor(side: key.hasPrefix("p2") ? "p2" : "p1", speciesEn: speciesEn)
    if lastMoveLabel == "\\(mySlot): \\(speciesEn)", drainMoves.contains(lastMoveName),
       Date().timeIntervalSince(lastMoveMsgAt) < 20 {
        return ("move: \\(lastMoveName)", nil)
    }
    // 消費済みの持ち物は二度と発動しない
    if fromPct <= 50 && (12...30).contains(delta) && !itemLostActive.contains(key) {"""))

# E9: たくわえるの蓄積数文からの技行の補完 (サイコアップの直後へ)
EDITS.append((
"""    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する""",
"""    // たくわえるの蓄積数文: 「<種族>は Nつ たくわえた！」は技が成功
    // した証拠。技告知文を取りこぼした場合は、ここから技行を補う
    // (実例: 2026-11-22 battle_20261122_091721 ターン2、告知文が
    // 断片化して技行が無く、上昇行だけが残った)。既にこの区間で
    // その枠の技行がある場合は消費だけする
    if t.contains("たくわえた") {
        if let e = findAllSpeciesJa(in: t).first {
            let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
            let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
            if inOpp || inMine {
                let mSide = inOpp && !inMine ? "p2" : "p1"
                let mSlot = slotFor(side: mSide, speciesEn: e.en)
                let mLabel = "\\(mSlot): \\(e.en)"
                if !movesSinceTurnLine.contains(mLabel) {
                    lastMoveSigAt["\\(mSlot)|Stockpile|t\\(currentTurn)"] = Date()
                    lastMoveSigAt["\\(mSlot)|Stockpile"] = Date()
                    lastMoveSigSeq["\\(mSlot)|Stockpile|t\\(currentTurn)"] = actionSeq
                    lastMoveLabel = mLabel
                    lastMoveMsgAt = Date()
                    lastMoveName = "Stockpile"
                    emitLog("|move|\\(mLabel)|Stockpile")
                    lastMoveSeq = actionSeq
                    applyMoveField("たくわえる", side: mSide)
                }
            }
        }
        return true
    }
    // ランク変化文の断片 (主語と能力名だけが先に届き、上がった/
    // 下がったが次の読みに分かれた文) を覚えておく。方向の文が主語
    // なしで届いたら、断片と結合して適用する (実例: 2026-11-22
    // battle_20261122_091721 ターン4、たくわえる の「防御特防が」と
    // 「ぐーんと上がった！」が別々の読みに分かれ、上昇行が丸ごと落ちた)
    if !(t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
         || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた")) {
        let statWords = ["攻撃", "防御", "特攻", "特防", "素早さ", "命中率", "回避率",
                         "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ"]
        if statWords.contains(where: { t.contains($0) }) {
            let subs = boostSubjects(in: t)
            if subs.count == 1 {
                let e = subs[0]
                let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
                let fSide = (t.contains("相手の") || t.contains("あいての")) && inOpp ? "p2" : (inOpp && !inMine ? "p2" : "p1")
                prevBoostFragment = (text: t, speciesEn: e.en, side: fSide, at: Date())
            }
        }
    }
    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する"""))

# E11: 断片の結合適用 (ランク変化の分岐チェーンへ)
EDITS.append((
"""        } else if subjects.count == 1, subjects[0].en != sp.en {""",
"""        } else if subjects.isEmpty, let frag = prevBoostFragment,
                  Date().timeIntervalSince(frag.at) < 6 {
            // 主語のない方向の文は、直前に覚えた断片 (主語+能力名) と
            // 結合して適用する
            checkBoostText(text: frag.text + t, side: frag.side, speciesEn: frag.speciesEn,
                           slot: slotFor(side: frag.side, speciesEn: frag.speciesEn))
            prevBoostFragment = nil
        } else if subjects.count == 1, subjects[0].en != sp.en {"""))

# E12: Simple Beam と Electro Shot の吸収文 (まもる成功の直前へ)
EDITS.append((
"""    // まもる成功: 「<対象>は 攻撃から 身を守った！」""",
"""    // シンプルビームの特性変化: 「<種族>は たんじゅんになった！」を
    // 特性の変化として構造化する (実例: 2026-11-22
    // battle_20261122_091721、効果文が未翻訳のまま残り、特性変化の
    // 行が無かった)
    if t.contains("たんじゅんになった") || t.contains("たんじゅんになつた")
        || foldDakuten(t).contains("たんしゆんになった") {
        if let e = findAllSpeciesJa(in: t).first(where: { cand in lastSlots.values.contains { $0.speciesEn == cand.en } }) {
            let bSide = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en ? "p2" : "p1"
            emitLog("|-ability|\\(slotFor(side: bSide, speciesEn: e.en)): \\(e.en)|Simple")
        }
        return true
    }
    // エレクトロショットの吸収文: 「<種族>は 電気を 吸収した！」は
    // 雨天時の即時発射の告知で、技行と特攻上昇行は別の文から出るため、
    // 文は消費だけする (実例: 2026-11-22 battle_20261122_091721、
    // 2 回とも未翻訳として残った)
    if t.contains("電気を吸収した") || t.contains("電気を吸収し") {
        return true
    }
    // まもる成功: 「<対象>は 攻撃から 身を守った！」"""))

# E13: Acupressure の上昇量
EDITS.append((
"""    let mag = (text.contains("ぐーんと") || text.contains("ぐんと") || text.contains("がくっと") || text.contains("がくつと")) ? 2 : 1""",
"""    var mag = (text.contains("ぐーんと") || text.contains("ぐんと") || text.contains("がくっと") || text.contains("がくつと")) ? 2 : 1
    // つぼをつく は必ず 2 段階上がる。上昇量の文の「ぐーんと」が
    // 読み落ちて 1 段階として記録されるのを、技の文脈で正す
    // (実例: 2026-11-22 battle_20261122_091721 ターン6)
    if up && mag == 1 && lastMoveName == "Acupressure" && Date().timeIntervalSince(lastMoveMsgAt) < 20 { mag = 2 }"""))

# E14: completeArchiveHeader の HP 表記の統一
EDITS.append((
"""    var disp = displayLines""",
"""    // 自軍の交代行の HP 表記を実数へ統一する: 開幕の交代行が % 表記
    // (100/100) で出た枠も、後の被ダメ行などで実数の最大値が判明
    // していれば、その表記 (最大値/最大値) に揃える。実数表記の枠と
    // 混在すると、同じ開幕の交代行で表記が割れる (実例: 2026-11-22
    // battle_20261122_091721、ニョロトノは 167/167、ブリジュラスは
    // 100/100 で出た)
    var realMax: [String: Int] = [:]
    for l in proto {
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 5, f[1] == "-damage" || f[1] == "-heal" || f[1] == "switch" else { continue }
        let hpParts = f[4].split(separator: " ")
        guard let first = hpParts.first else { continue }
        let curMax = first.split(separator: "/")
        if curMax.count == 2, let mx = Int(curMax[1]), mx != 100 {
            realMax[f[2]] = max(realMax[f[2]] ?? 0, mx)
        }
    }
    if !realMax.isEmpty {
        proto = proto.map { l in
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, f[1] == "switch", f[4] == "100/100", let mx = realMax[f[2]] else { return l }
            var g = f
            g[4] = "\\(mx)/\\(mx)"
            return g.joined(separator: "|")
        }
    }
    var disp = displayLines"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for i, (old, new) in enumerate(EDITS):
    n = src.count(old)
    print(f"edit {i + 1}: anchor count = {n}")
    if n != 1:
        bad += 1
if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    for old, new in EDITS:
        src = src.replace(old, new, 1)
    stamp = subprocess.run(["date", "+%Y%m%d_%H%M"], env={"TZ": "Asia/Tokyo", "PATH": "/usr/bin:/bin"},
                           capture_output=True, text=True).stdout.strip()
    src, n = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src)
    print(f"build stamp -> {stamp} (replaced {n})")
    open(PATH, "w").write(src)
    print("applied all edits")
else:
    print("dry run ok")
