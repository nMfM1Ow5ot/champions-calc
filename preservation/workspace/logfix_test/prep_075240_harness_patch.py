#!/usr/bin/env python3
"""make_harness.py: 075240 対応の鏡像 (emitLog 挿入) + FUNCS + T124/T125。
使い方: python3 prep_075240_harness_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH).read()
EDITS = []

EDITS.append((
"""'terrainSourcePlausible', 'confirmHeldTerrainReplace',""",
"""'terrainSourcePlausible', 'confirmHeldTerrainReplace', 'fieldLineForAbility',"""))

EDITS.append((
"""    battleLog.append(line)
    // 入場バッチ ('ab' イベント) の記録は本体 emitLog と同一ロジックを再現する""",
"""    // 並びの訂正 (本体 emitLog と同一ロジック)
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
    // 入場バッチ ('ab' イベント) の記録は本体 emitLog と同一ロジックを再現する"""))

EDITS.append((
"""check("T123f occupant faint synthesized", battleLog.contains("|-damage|p1a: Farigiraf|0/100"))""",
"""check("T123f occupant faint synthesized", battleLog.contains("|-damage|p1a: Farigiraf|0/100"))

// T124a: 疑わしい低下の保留が解けた直後の説明できない低下は確定しない
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 1
monStates["p2:Sneasler"] = MonState()
monStates["p2:Sneasler"]?.hpPercent = 100
suspectJump["oppA"] = (toPct: 10, turn: 1)
lastEmittedPct["oppA"] = 100
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 88, hpText: "151/171", force: true)
check("T124a post-suspect drop held", !battleLog.contains { $0.contains("-damage") } && suspectJump["oppA"]?.toPct == 88 && lastEmittedPct["oppA"] == 100)
currentTurn = 2
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 100, hpText: "171/171", force: true)
check("T124a back to full leaves nothing", !battleLog.contains { $0.contains("-damage") } && suspectJump["oppA"] == nil)

// T124b: 分類できた低下 (状態異常の経過) は保留明けでも従来どおり出る
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 1
monStates["p2:Sneasler"] = MonState()
monStates["p2:Sneasler"]?.hpPercent = 100
suspectJump["oppA"] = (toPct: 10, turn: 1)
lastEmittedPct["oppA"] = 100
pendingStatusFrom["p2:Sneasler"] = (code: "psn", at: Date())
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 88, hpText: "151/171", force: true)
check("T124b classified drop emitted", battleLog.contains("|-damage|p2a: Sneasler|151/171|[from] psn"))

// T124c: 保留明けでも小さな低下 (3 以下) は従来どおり出る
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 1
monStates["p2:Sneasler"] = MonState()
monStates["p2:Sneasler"]?.hpPercent = 100
suspectJump["oppA"] = (toPct: 10, turn: 1)
lastEmittedPct["oppA"] = 100
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 98, hpText: "168/171", force: true)
check("T124c small drop emitted", battleLog.contains("|-damage|p2a: Sneasler|168/171"))

// T125a: 急所行は同じ対象の ひんし行より前に置く
resetAll()
emitLog("|-damage|p2a: Charizard|0/160")
emitLog("|faint|p2a: Charizard")
emitLog("|-crit|p2a: Charizard")
let critIdx = battleLog.firstIndex(of: "|-crit|p2a: Charizard")
let faintIdx = battleLog.firstIndex(of: "|faint|p2a: Charizard")
check("T125a crit before faint", critIdx != nil && faintIdx != nil && critIdx! < faintIdx!)

// T125b: 特性行は対応する天候行より前に置く
resetAll()
emitLog("|-weather|Sunny Day")
emitLog("|-ability|p2b: Torkoal|Drought")
let abIdx = battleLog.firstIndex(of: "|-ability|p2b: Torkoal|Drought")
let wIdx = battleLog.firstIndex(of: "|-weather|Sunny Day")
check("T125b ability before weather", abIdx != nil && wIdx != nil && abIdx! < wIdx!)

// T125c: ターンを跨いだ特性行は前のターンの天候行より前に動かさない
resetAll()
emitLog("|-weather|Sunny Day")
emitLog("|turn|2")
emitLog("|-ability|p2b: Torkoal|Drought")
let abIdx2 = battleLog.firstIndex(of: "|-ability|p2b: Torkoal|Drought")
let wIdx2 = battleLog.firstIndex(of: "|-weather|Sunny Day")
check("T125c no reorder across turns", abIdx2 != nil && wIdx2 != nil && wIdx2! < abIdx2!)"""))

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
    print("dry run ok")
