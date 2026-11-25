#!/usr/bin/env python3
"""battle_20261122_070237 追加依頼 (イベント列の二重化・欠落、amt/急所の食い違い)
への reader.swift パッチ。使い方: python3 prep_070237_patch2.py [apply]"""
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH).read()
EDITS = []

# N1: recordDamageEvent の時刻ガード緩和 (8s -> 20s)
EDITS.append((
"""    guard !lastMoveLabel.isEmpty, actionSeq - lastMoveSeq <= 1,
          Date().timeIntervalSince(lastMoveMsgAt) < 8 else { return }""",
"""    // 時刻の上限は行動の区切り (actionSeq) 側が本筋の帰属ガードで、
    // こちらは暴走防止の緩い上限にとどめる。開幕の演出や範囲技の
    // 解決が長いと 8 秒では正当な証拠まで落ちる (実例: 2026-11-22
    // battle_20261122_070237 ターン1、ユキメノコのふぶきの被ダメ
    // イベントが欠落した)
    guard !lastMoveLabel.isEmpty, actionSeq - lastMoveSeq <= 1,
          Date().timeIntervalSince(lastMoveMsgAt) < 20 else { return }"""))

# N2a: 上書き判定用に「先のイベントが使った基準実数」を保持する変数
EDITS.append((
"""var lastExactHp: [String: [Int]] = [:]            // key -> [現在HP, 最大HP] (自軍の正確な数値の追跡)""",
"""var lastExactHp: [String: [Int]] = [:]            // key -> [現在HP, 最大HP] (自軍の正確な数値の追跡)
var lastDmgEventPrevExact: [String: [Int]] = [:]  // key -> 直近の dmg イベントが使った基準実数 ([] = 基準なし)。再放出の上書き時に amt を元の基準から計算し直すため"""))

# N2b: resetLogState でのリセット
EDITS.append((
"""    lastExactHp = [:]""",
"""    lastExactHp = [:]
    lastDmgEventPrevExact = [:]"""))

# N2c: recordDamageEvent — 上書き判定を amt 計算の前に挟み、末尾で振り替える
EDITS.append((
"""    let prevExact = lastExactHp[key]
    if let exact { lastExactHp[key] = exact }""",
"""    let prevExact = lastExactHp[key]
    if let exact { lastExactHp[key] = exact }
    // 同じ行動・同じ対象・同じ基準 HP からの被ダメが再び放出された
    // 場合は、別イベントとして足さずに先の記録を上書きする。二重の
    // 記録 (推定側での二重処理) を防ぎ、途中値で記録されたイベントを
    // 最終値へ是正するのが目的。連続ヒットは基準 HP が前回の到達値と
    // 一致するため、この条件には当たらず別イベントとして残る
    // (実例: 2026-11-22 battle_20261122_070237、Milotic のイベント
    // 二重化と Farigiraf の amt 食い違い)
    let defLabelForEv = "\\(slot): \\(speciesEn)"
    let supersedeIdx = battleEvents.lastIndex(where: {
        $0.hasPrefix("{\\"k\\":\\"dmg\\"") && $0.contains("\\"turn\\":\\(currentTurn)")
            && $0.contains("\\"atk\\":\\"\\(jsonEscape(lastMoveLabel))\\"")
            && $0.contains("\\"def\\":\\"\\(jsonEscape(defLabelForEv))\\"")
            && $0.contains("\\"move\\":\\"\\(jsonEscape(lastMoveName))\\"")
            && $0.contains("\\"defHp\\":\\(fromPct)")
    })
    var effPrevExact = prevExact
    if supersedeIdx != nil, let stashed = lastDmgEventPrevExact[key] {
        effPrevExact = stashed.isEmpty ? nil : stashed
    }"""))

# N2d: amt 計算は effPrevExact を使う
EDITS.append((
"""    if defSide == "p1", let pe = prevExact, let ce = exact, pe[1] == ce[1], pe[0] > ce[0] {""",
"""    if defSide == "p1", let pe = effPrevExact, let ce = exact, pe[1] == ce[1], pe[0] > ce[0] {"""))

# N2e: 末尾の append を上書き振り替えにする (recordDamageEvent 側。
# 直後に反動イベントのコメントが続くことで recordRecoilEvent 側と区別する)
EDITS.append((
"""    ev += "}"
    battleEvents.append(ev)
}

// 自分自身への反動ダメージのイベント""",
"""    ev += "}"
    if let idx = supersedeIdx {
        battleEvents[idx] = ev
    } else {
        battleEvents.append(ev)
        lastDmgEventPrevExact[key] = prevExact ?? []
    }
}

// 自分自身への反動ダメージのイベント"""))

# N3: 急所文の処理で、記録済み dmg イベントの crit を是正する
EDITS.append((
"""        if !target.isEmpty && Date().timeIntervalSince(lastCritAt[target] ?? .distantPast) > 6 {
            lastCritAt[target] = Date()
            emitLog("|-crit|\\(target)")
        }""",
"""        if !target.isEmpty && Date().timeIntervalSince(lastCritAt[target] ?? .distantPast) > 6 {
            lastCritAt[target] = Date()
            // 急所の告知文は被ダメ行より後に来るため、記録時点では
            // dmg イベントの crit が false のまま残る。対象の直近の
            // イベントを是正する (実例: 2026-11-22
            // battle_20261122_070237 ターン2、プロトコルには急所行が
            // あるのにイベントは crit=false だった)
            if let idx = battleEvents.lastIndex(where: { ev in
                ev.hasPrefix("{\\"k\\":\\"dmg\\"") && ev.contains("\\"def\\":\\"\\(jsonEscape(target))\\"")
                    && !ev.contains("\\"atk\\":\\"\\(jsonEscape(target))\\"") && ev.contains("\\"crit\\":false")
            }) {
                battleEvents[idx] = battleEvents[idx].replacingOccurrences(of: "\\"crit\\":false", with: "\\"crit\\":true")
            }
            emitLog("|-crit|\\(target)")
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
