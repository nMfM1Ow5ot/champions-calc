#!/usr/bin/env python3
"""reader.swift: battle_20261122_075240 の2件 + ターミナル表示の変更。
1. 疑わしい低下の保留が解けた直後の、説明できない低下を確定させない
2. 急所行/特性行の並び訂正 (プロトコル + 表示ログ)
3. 診断表示 ([reader]/[field]/[debug]/ログ画面診断) を --debug 時のみに
使い方: python3 prep_075240_patch.py [apply]"""
import re
import subprocess
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH).read()
EDITS = []

# R1: フィールド行の対応表 (emitLog の前へ)
EDITS.append((
"""func emitLog(_ line: String) { emitLog(line, applyNow: true) }""",
"""// 天候・地形を呼ぶ特性と、対応するフィールド行 (プロトコル表記と
// 表示表記) の対応。特性行の生成がフィールド行より遅れた場合の
// 並び訂正に使う (emitLog / 描画部)
func fieldLineForAbility(_ ability: String) -> String? {
    switch ability {
    case "Drought": return "|-weather|Sunny Day"
    case "Drizzle": return "|-weather|Rain Dance"
    case "Sand Stream": return "|-weather|Sandstorm"
    case "Snow Warning": return "|-weather|Snow"
    case "Electric Surge": return "|-fieldstart|move: Electric Terrain"
    case "Grassy Surge": return "|-fieldstart|move: Grassy Terrain"
    case "Misty Surge": return "|-fieldstart|move: Misty Terrain"
    case "Psychic Surge": return "|-fieldstart|move: Psychic Terrain"
    default: return nil
    }
}

func fieldRenderForAbility(_ ability: String) -> String? {
    switch ability {
    case "Drought": return "The sunlight turned harsh!"
    case "Drizzle": return "It started to rain!"
    case "Sand Stream": return "A sandstorm kicked up!"
    case "Snow Warning": return "It started to snow!"
    case "Electric Surge": return "An electric current ran across the battlefield!"
    case "Grassy Surge": return "Grass grew to cover the battlefield!"
    case "Misty Surge": return "Mist swirled around the battlefield!"
    case "Psychic Surge": return "The battlefield got weird!"
    default: return nil
    }
}

func emitLog(_ line: String) { emitLog(line, applyNow: true) }"""))

# R2: プロトコル (battleLog) への挿入
EDITS.append((
"""    battleLog.append(line)
    // 推定エンジン用イベント (技の使用順)""",
"""    // 並びの訂正: 急所行は同じ対象の ひんし行より前に、天候・地形を
    // 呼ぶ特性行は対応するフィールド行より前に置く。ゲーム内の発生
    // 順はその順だが、プレート確定や帰属が遅れると行の生成が前後
    // する (実例: 2026-11-22 battle_20261122_075240、急所行が
    // ひんし行の後ろに、天候行が ひでり の特性行より前に出た)。
    // 表示ログ側の並びは描画部で対処する
    var insertAt: Int? = nil
    if line.hasPrefix("|-crit|") {
        let cf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if cf.count >= 3 {
            let label = cf[2]
            var i = battleLog.count - 1
            while i >= 0 && battleLog.count - i <= 40 {
                let bl = battleLog[i]
                if bl.hasPrefix("|turn|") || bl.hasPrefix("|move|") || bl.hasPrefix("|switch|") { break }
                if bl == "|faint|\\(label)" { insertAt = i; break }
                i -= 1
            }
        }
    } else if line.hasPrefix("|-ability|") {
        let af = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if af.count >= 4, let fieldLine = fieldLineForAbility(af[3]) {
            let label = af[2]
            var i = battleLog.count - 1
            while i >= 0 && battleLog.count - i <= 40 {
                let bl = battleLog[i]
                if bl == fieldLine { insertAt = i; break }
                if bl.hasPrefix("|turn|") { break }
                if bl.hasPrefix("|switch|") && bl.contains("|\\(label)|") { break }
                i -= 1
            }
        }
    }
    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }
    // 推定エンジン用イベント (技の使用順)"""))

# R3: 表示ログ (displayLog) への挿入
EDITS.append((
"""    for l in out {
        displayLog.append(l)
        print(l)
    }
    fflush(stdout)""",
"""    // 表示ログの並び訂正 (プロトコル側の挿入と対): 急所の表示は
    // 同じ対象の ひんし表示より前に、天候・地形特性の表示は対応する
    // フィールド表示より前に割り込ませる。表示ログは逐次構築のため、
    // 既に積まれた行の前へ挿入する必要がある。ターミナルへのライブ
    // 出力は発生順のまま (過去の表示は遡れないため)
    var displayInsertAt: Int? = nil
    if out.count == 1 {
        if line.hasPrefix("|-crit|") {
            let cf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if cf.count >= 3 {
                let (_, side, species) = renderLabelParts(cf[2])
                let anchor = "\\(renderPrefix(side))\\(species) fainted!"
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        } else if line.hasPrefix("|-ability|") {
            let af = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if af.count >= 4, let anchor = fieldRenderForAbility(af[3]) {
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        }
    }
    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
        print(out[0])
    } else {
        for l in out {
            displayLog.append(l)
            print(l)
        }
    }
    fflush(stdout)"""))

# R4: 疑わしさ解消の控え (基準値の疑わしさの直後)
EDITS.append((
"""    let baselineWasSuspect = suspectJump[plateName].map { $0.toPct == effFrom } ?? false""",
"""    let baselineWasSuspect = suspectJump[plateName].map { $0.toPct == effFrom } ?? false
    // この呼び出しで「低下の疑わしさ」が解けたかどうか (下の解消で
    // suspectJump は消えるため、ここで控える)
    var clearedDropSuspect = false"""))

# R5: 解消時に低下の疑わしさだったことを控える
EDITS.append((
"""        }
        suspectJump[plateName] = nil
    }
    if toPct < effFrom {""",
"""        }
        if sj.toPct < effFrom { clearedDropSuspect = true }
        suspectJump[plateName] = nil
    }
    if toPct < effFrom {"""))

# R6: 疑わしさ解消直後の説明できない低下は確定させない
EDITS.append((
"""        if let fromCode { line += "|[from] \\(fromCode)" }
        emitLog(line)""",
"""        // 疑わしい低下を保留した直後に、別の値への説明できない低下が
        // 来た場合は、その値も誤読の連鎖とみて確定させない。保留に
        // なったプレートは読みが安定しておらず、値が変わっただけで
        // 疑いが解けたとは言えない (実例: 2026-11-22
        // battle_20261122_075240、Sneasler に 100% -> 10% の誤読が
        // 保留された後、88% の読みがターン終了時の確定として幻の
        // ダメージ行になった)。持続すれば次ターンに状態訂正として
        // 取り込まれ (冒頭の解消規則)、実値に戻れば何も残らない。
        // 分類できた低下 (状態異常の経過等) は従来どおり出す
        if fromCode == nil, clearedDropSuspect, effFrom - toPct > 3 {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "post_suspect_unexplained"])
            return true
        }
        if let fromCode { line += "|[from] \\(fromCode)" }
        emitLog(line)"""))

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

# R7: 診断表示を --debug 時のみに (ターミナルは人間可読ログの
# ライブ出力が主体。診断の構造化記録は debug 一式に残る)
pat = re.compile(r'^(\s*)print\("\[(?:reader|field|debug)\]|^(\s*)print\("ログ画面診断', re.M)
hits = []

def wrap(m):
    hits.append(m.group(0))
    indent = m.group(1) or m.group(2)
    return indent + "if debugMode { " + m.group(0)[len(indent):]

if apply:
    src2 = pat.sub(wrap, src)
    # 各行の末尾に } を足す: 対象行は print(...) で完結する単独行
    lines = src2.split("\n")
    count = 0
    for j, ln in enumerate(lines):
        if "if debugMode { print(" in ln and ("[reader]" in ln or "[field]" in ln
                                              or "[debug]" in ln or "ログ画面診断" in ln):
            lines[j] = ln + " }"
            count += 1
    print(f"gating: wrapped {count} diagnostic prints")
    if count < 20:
        print("gating count too low — aborting")
        sys.exit(1)
    src = "\n".join(lines)
else:
    print("gating: would wrap", len(pat.findall(src)), "prints (dry run)")

if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    # R8: ビルド番号の更新
    stamp = subprocess.run(["date", "+%Y%m%d_%H%M"], env={"TZ": "Asia/Tokyo", "PATH": "/usr/bin:/bin"},
                           capture_output=True, text=True).stdout.strip()
    src, n = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src)
    print(f"build stamp -> {stamp} (replaced {n})")
    open(PATH, "w").write(src)
    print("applied all edits")
else:
    print("dry run ok")
