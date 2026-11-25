#!/usr/bin/env python3
# Item 4b: weather/terrain [from] attribution when the ability line
# arrives after the field-start line (emitLog hook + helper).
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count {n} != {count}")
        sys.exit(1)
    src = src.replace(old, new, count)
    print("OK", tag)

# helper, right after fieldLineForAbility's closing (anchor on the
# fieldRenderForAbility signature that follows it)
rep('''func fieldRenderForAbility(_ ability: String) -> String? {''',
    '''// 特性行がフィールドの開始行より遅れて出た場合に、開始行へ
// [from] の帰属を付け直す (プロトコル行のみ。表示行には出ない)。
// 対象は同じターン区間にある帰属なしの開始行だけで、その区間に
// 同じ天候・地形を呼ぶ技行が先行する場合は技由来とみて付けない
// (実例: 2026-11-22 battle_20261122_231107、あめふらしの特性行が
// 雨の開始行より後ろに出て、帰属が付かなかった)
func annotateFieldLineFromAbility(_ abilityLine: String) {
    let f = abilityLine.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, f[1] == "-ability" else { return }
    let label = f[2]
    let ability = f[3]
    guard let fieldLine = fieldLineForAbility(ability) else { return }
    let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) ?? -1
    guard turnIdx + 1 <= battleLog.count else { return }
    let seg = Array(battleLog[(turnIdx + 1)...])
    guard let rel = seg.lastIndex(of: fieldLine) else { return }
    let rawName: String
    if fieldLine.hasPrefix("|-fieldstart|move: ") {
        rawName = String(fieldLine.dropFirst("|-fieldstart|move: ".count))
    } else {
        rawName = String(fieldLine.dropFirst("|-weather|".count))
    }
    let moveName = rawName == "Snow" ? "Snowscape" : rawName
    if seg[..<rel].contains(where: { $0.hasPrefix("|move|") && $0.hasSuffix("|\\(moveName)") }) { return }
    if let swIdx = seg.lastIndex(where: { $0.hasPrefix("|switch|\\(label)|") || $0.hasPrefix("|drag|\\(label)|") }), swIdx > rel { return }
    battleLog[turnIdx + 1 + rel] = "\\(fieldLine)|[from] ability: \\(ability)|[of] \\(label)"
}

func fieldRenderForAbility(_ ability: String) -> String? {''',
    "item4b helper")

# hook in emitLog, right after the ability-plausibility guard
rep('''    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        if debugMode { print("[reader] あり得ない特性行を記録しませんでした: \\(line)") }
        fflush(stdout)
        debugCapture(kind: "ability_guard", key: "ability_guard:\\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }''',
    '''    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        if debugMode { print("[reader] あり得ない特性行を記録しませんでした: \\(line)") }
        fflush(stdout)
        debugCapture(kind: "ability_guard", key: "ability_guard:\\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    if line.hasPrefix("|-ability|") { annotateFieldLineFromAbility(line) }''',
    "item4b emitLog hook")

open(PATH, "w", encoding="utf-8").write(src)
print("APPLIED")
