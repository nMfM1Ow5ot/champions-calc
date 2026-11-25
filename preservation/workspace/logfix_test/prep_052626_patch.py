#!/usr/bin/env python3
# battle_20261123_052626 fix round: 5 edits to reader.swift.
# Usage: python3 prep_052626_patch.py [path-to-reader.swift]
# Aborts without writing if any anchor does not match exactly once.
import sys, datetime

PATH = sys.argv[1] if len(sys.argv) > 1 else "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print(f"ABORT {tag}: anchor count = {n}")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

# --- E1a: isMoveListText (pure function, before watchBattleMessage) ---
rep(
    "func watchBattleMessage(image: CGImage, platesVisible: Bool) {",
    """// コマンド選択中の技リスト表示が帯の連結文に混ざると、プレート名と
// 技名が同居して告知と誤認される (実例: 2026-11-23
// battle_20261123_052626、リキキリンのプレート名と技リストの
// てだすけ から幽霊の技行が生まれ、ターンまで 1 つ挿入された)。
// 実文は技名を 1 種しか含まないため、2 種以上の技名を含む文は
// 技リスト表示とみなす。文中の種族名の部分文字列になる技名
// (カイリキー中の かいりき) は技名の出現と数えない
func isMoveListText(_ text: String) -> Bool {
    let nt = normalize(text)
    var found = Set<String>()
    for (norm, _) in moveNameOrig {
        if norm.isEmpty || norm.count < 2 { continue }
        guard nt.contains(norm) else { continue }
        var speciesPart = false
        for sp in speciesDict where nt.contains(normalize(sp.ja)) {
            if normalize(sp.ja).contains(norm) { speciesPart = true; break }
        }
        if !speciesPart { found.insert(norm) }
    }
    return found.count >= 2
}

func watchBattleMessage(image: CGImage, platesVisible: Bool) {""",
    "E1a isMoveListText")

# --- E1b: watcher hook ---
rep(
    """    if text.contains("どうする") || text.contains("選んでください") || text.contains("選ばれました") { lastMsgNorm = norm; lastMsgAt = now; return }""",
    """    if text.contains("どうする") || text.contains("選んでください") || text.contains("選ばれました") { lastMsgNorm = norm; lastMsgAt = now; return }
    // 技リスト表示 (コマンド選択中) はイベントではない
    if isMoveListText(text) { lastMsgNorm = norm; lastMsgAt = now; return }""",
    "E1b watcher hook")

# --- E2: win text garble tolerance ---
rep(
    """    // 勝敗: 「<相手>との 勝負に 負けた！/勝った！」
    // (実機ログでは「勝った」が「勝つた」と OCR 崩れしていたため、
    //  小さい「っ」を通常の「つ」に寄せた形でも判定する)
    let tw = t.replacingOccurrences(of: "っ", with: "つ").replacingOccurrences(of: "ッ", with: "ツ")
    if t.contains("勝負に") && (t.contains("負けた") || tw.contains("勝つた")) {""",
    """    // 勝敗: 「<相手>との 勝負に 負けた！/勝った！」
    // (実機ログでは「勝った」が「勝つた」と OCR 崩れしていたため、
    //  小さい「っ」を通常の「つ」に寄せた形でも判定する)
    // 「勝負」の負が別字に崩れる読み (勝質に 等) でも判定できるよう、
    // 勝+任意の1字+に の形で見る (実例: 2026-11-23
    // battle_20261123_052626、帯の読みが「勝質に勝った！」となり
    // 勝敗が確定せず、完結した試合が interrupted で届いた)
    let tw = t.replacingOccurrences(of: "っ", with: "つ").replacingOccurrences(of: "ッ", with: "ツ")
    if t.range(of: "勝.に", options: .regularExpression) != nil && (t.contains("負けた") || tw.contains("勝つた")) {""",
    "E2 win garble")

# --- E3: checkBoostText two-pass + Stamina attribution ---
rep(
    """        applied.insert(code)
        applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: code, delta: up ? mag : -mag)
    }
}""",
    """        applied.insert(code)
        matched.append((code, up ? mag : -mag))
    }
    // じきゅうりょく の帰属: 特性バナーは画面上部の表示で帯の文には
    // 入らず、帯に届くのは上昇文だけのため、被弾発動の特性行は
    // 今まで出なかった (実例: 2026-11-23 battle_20261123_052626、
    // ブリジュラスの防御上昇に特性行が付かなかった)。「相手の技で
    // 被ダメした直後の 防御 +1 の上昇」で、特性が未判明かつその種族が
    // 持ち得る場合だけ、上昇の適用前に特性行を出す
    if up && mag == 1 && matched.contains(where: { $0.0 == "def" })
        && (damagedBySeq[actionSeq] ?? []).contains("\\(slot): \\(speciesEn)")
        && !lastMoveLabel.isEmpty && !lastMoveLabel.hasPrefix(side)
        && monStates[key]?.ability == nil
        && (speciesAbilityMap[speciesEn]?.contains("Stamina") ?? false) {
        emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Stamina")
    }
    for m in matched {
        applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: m.0, delta: m.1)
    }
}""",
    "E3 stamina apply")
rep(
    """    var applied = Set<String>()
    let foldedText = foldDakuten(text)""",
    """    var matched: [(String, Int)] = []
    var applied = Set<String>()
    let foldedText = foldDakuten(text)""",
    "E3 matched decl")

# --- E4: |-block| before |-activate| ---
rep(
    """        if protectMoveTurn[slot] == currentTurn {
            emitLog("|-activate|\\(slot): \\(sp.en)|move: \\(protectMoveName[slot] ?? "Protect")")
        }""",
    """        if protectMoveTurn[slot] == currentTurn {
            // 防がれた側の block 行も対で出す (今まで reader は
            // |-block| を一切生成しておらず、技が防がれた記録が
            // activate 行だけだった。実例: 2026-11-23
            // battle_20261123_052626、だいちのちからへの block 行欠落)
            emitLog("|-block|\\(slot): \\(sp.en)|move: \\(protectMoveName[slot] ?? "Protect")")
            emitLog("|-activate|\\(slot): \\(sp.en)|move: \\(protectMoveName[slot] ?? "Protect")")
        }""",
    "E4 block line")

# --- E5a: fieldLineWithAttribution (before fieldRenderForAbility) ---
rep(
    "func fieldRenderForAbility(_ ability: String) -> String? {",
    """// 開始行への [from] 帰属 (特性行が先行する配置): 付け直し
// (annotateFieldLineFromAbility) は開始行が先の配置だけを扱うため、
// 特性行が既に区間にある状態で裸の開始行が出たら、出力時点で
// 帰属を付けた形にする (実例: 2026-11-23 battle_20261123_052626
// ターン1、あまごいの特性行が先行し、間に交代行とダメージ行が
// 挟まって開始行が遅れた)。技による開始 (区間内に同名の技行) が
// ある場合は付けない (付け直し側と同じガード)
func fieldLineWithAttribution(_ line: String) -> String {
    let bareLines = ["Drought", "Drizzle", "Sand Stream", "Snow Warning",
                     "Electric Surge", "Grassy Surge", "Misty Surge", "Psychic Surge"]
        .compactMap { fieldLineForAbility($0) }
    guard bareLines.contains(line) else { return line }
    let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) ?? -1
    guard turnIdx + 1 <= battleLog.count else { return line }
    let seg = Array(battleLog[(turnIdx + 1)...])
    let rawName: String
    if line.hasPrefix("|-fieldstart|move: ") {
        rawName = String(line.dropFirst("|-fieldstart|move: ".count))
    } else {
        rawName = String(line.dropFirst("|-weather|".count))
    }
    let moveName = rawName == "Snow" ? "Snowscape" : rawName
    if seg.contains(where: { $0.hasPrefix("|move|") && $0.hasSuffix("|\\(moveName)") }) { return line }
    for l in seg where l.hasPrefix("|-ability|") {
        let af = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if af.count >= 4, fieldLineForAbility(af[3]) == line {
            return "\\(line)|[from] ability: \\(af[3])|[of] \\(af[2])"
        }
    }
    return line
}

func fieldRenderForAbility(_ ability: String) -> String? {""",
    "E5a fieldLineWithAttribution")

# --- E5b: emitLog applies the attribution at its head ---
rep(
    "    if winLogged { startBattleLog() }",
    """    if winLogged { startBattleLog() }
    // フィールド開始行は、特性行が先行する配置では出力時点で
    // [from] 帰属を付けた形にする (fieldLineWithAttribution)
    let line = fieldLineWithAttribution(line)""",
    "E5b emitLog head")

# --- E6: build stamp ---
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
import re
src2, n = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src)
if n != 1:
    print(f"ABORT E6 stamp: count = {n}")
    sys.exit(1)
src = src2
print(f"OK E6 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
