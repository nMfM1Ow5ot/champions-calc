#!/usr/bin/env python3
"""battle_20261122_091721 対応のハーネス側パッチ (make_harness.py)。
使い方: python3 prep_091721_harness_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH).read()
EDITS = []

# H1: FUNCS に pullBackSwitchBlock を追加
EDITS.append((
"""    'healSource', 'boostLine', 'translateLogEntry', 'validatedSide', 'regexGroups',""",
"""    'healSource', 'boostLine', 'translateLogEntry', 'validatedSide', 'regexGroups', 'pullBackSwitchBlock',"""))

# H2: 新規グローバルのスタブ
EDITS.append((
"""var lastMoveSigAt: [String: Date] = [:]""",
"""var lastMoveSigAt: [String: Date] = [:]
var lastMoveSigSeq: [String: Int] = [:]
var prevBoostFragment: (text: String, speciesEn: String, side: String, at: Date)? = nil"""))

# H3: resetAll でのリセット
EDITS.append((
"""    lastMoveSigAt = [:]; lastSingleActAt = [:]; lastSideCondAt = [:]; lastCritAt = [:]""",
"""    lastMoveSigAt = [:]; lastMoveSigSeq = [:]; prevBoostFragment = nil; lastSingleActAt = [:]; lastSideCondAt = [:]; lastCritAt = [:]"""))

# H4: 種族フィクスチャの追加
EDITS.append((
"""    E("ブリジュラス", "Archaludon"),""",
"""    E("ブリジュラス", "Archaludon"),
    E("ニョロトノ", "Politoed"), E("ハリーマン", "Overqwil"), E("ピクシー", "Clefable"),"""))

# H5: 技フィクスチャの追加
EDITS.append((
"""for (ja, en) in [("じしん", "Earthquake"), ("まもる", "Protect"), ("アーマーキャノン", "Armor Cannon"), ("ハイパーボイス", "Hyper Voice"), ("シャドーボール", "Shadow Ball"), ("てだすけ", "Helping Hand"), ("サイコキネシス", "Psychic"), ("はかいこうせん", "Hyper Beam")] {""",
"""for (ja, en) in [("じしん", "Earthquake"), ("まもる", "Protect"), ("アーマーキャノン", "Armor Cannon"), ("ハイパーボイス", "Hyper Voice"), ("シャドーボール", "Shadow Ball"), ("てだすけ", "Helping Hand"), ("サイコキネシス", "Psychic"), ("はかいこうせん", "Hyper Beam"), ("だくりゅう", "Muddy Water"), ("たくわえる", "Stockpile"), ("ドレインキッス", "Draining Kiss"), ("つぼをつく", "Acupressure")] {"""))

# H6: emitLog 写しのターン行ガードへ (c) 判定と引き戻しを写す
EDITS.append((
"""            var guardN: Int? = nil
            if currentTurn == 0 && !roundEventSeen { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if let mover, currentTurn >= 1, !movesSinceTurnLine.isEmpty,
                    !movesSinceTurnLine.contains(mover),
                    enteredThisSegment.contains(mover.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "") { guardN = currentTurn + 1 }
            if let n = guardN {
                debugCapture(kind: "turn_guard", key: "turn_guard:\\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild, "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\\(n)")
            }""",
"""            var guardN: Int? = nil
            let ruleC = mover.map { mv in
                currentTurn >= 1 && !movesSinceTurnLine.isEmpty && !movesSinceTurnLine.contains(mv)
                    && enteredThisSegment.contains(mv.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            } ?? false
            if currentTurn == 0 && !roundEventSeen { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if ruleC { guardN = currentTurn + 1 }
            if let n = guardN {
                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                if ruleC, let mover { (pulledProto, pulledDisplay) = pullBackSwitchBlock(label: mover) }
                debugCapture(kind: "turn_guard", key: "turn_guard:\\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild, "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\\(n)")
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
            }"""))

# H7: T126 テスト群
EDITS.append((
"""out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")""",
"""// T126: battle_20261122_091721 の対応 (境界の帰属・二重発動・断片結合ほか)
// a: 同じ枠の同じ技が境界検出の遅れで重複として落ちないこと
resetAll()
logStarted = true
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Politoed", hpPercent: 100)
_ = translateBattleMessage("ニョロトノの だくりゅう！")
check("T126a first move emitted", battleLog.filter { $0 == "|move|p1a: Politoed|Muddy Water" }.count == 1)
_ = translateBattleMessage("ニョロトノの だくりゅう！")
check("T126a immediate re-read still deduped", battleLog.filter { $0 == "|move|p1a: Politoed|Muddy Water" }.count == 1)
emitLog("|move|p1b: Archaludon|Electro Shot")
emitLog("|move|p2b: Overqwil|Stockpile")
lastMoveSigAt["p1a|Muddy Water|t4"] = Date().addingTimeInterval(-30)
lastMoveSigAt["p1a|Muddy Water"] = Date().addingTimeInterval(-30)
_ = translateBattleMessage("ニョロトノの だくりゅう！")
let mwIdxs = battleLog.enumerated().filter { $0.element == "|move|p1a: Politoed|Muddy Water" }.map { $0.offset }
check("T126a boundary move emitted", mwIdxs.count == 2)
check("T126a turn line inserted before it", mwIdxs.count == 2 && battleLog[mwIdxs[1] - 1] == "|turn|5")
// b: ターン開始の交代ブロックが挿入ターン行の直後へ移ること
resetAll()
logStarted = true
currentTurn = 6
battleLog = ["|turn|6",
             "|move|p1b: Archaludon|Electro Shot",
             "|switch|p1a: Gengar|Gengar|137/137",
             "|-item|p2b: Overqwil|Leftovers",
             "|-item|p1a: Gengar|Gengarite",
             "|detailschange|p1a: Gengar|Gengar-Mega",
             "|-mega|p1a: Gengar|Gengar|Gengarite"]
displayLog = ["Turn 6",
              "Politoed, come back!",
              "Go! Gengar!",
              "The opposing Overqwil restored a little HP!",
              "Gengar's Gengarite is reacting to the Key Stone!",
              "Gengar has Mega Evolved into Mega Gengar!"]
enteredThisSegment = ["p1a"]
movesSinceTurnLine = ["p1b: Archaludon"]
emitLog("|move|p1a: Gengar|Sludge Bomb")
let t7Pos = battleLog.firstIndex(of: "|turn|7") ?? -1
let swPos = battleLog.firstIndex(of: "|switch|p1a: Gengar|Gengar|137/137") ?? -1
let megaPos = battleLog.firstIndex(of: "|-mega|p1a: Gengar|Gengar|Gengarite") ?? -1
let loPos = battleLog.firstIndex(of: "|-item|p2b: Overqwil|Leftovers") ?? -1
let mvPos = battleLog.firstIndex(of: "|move|p1a: Gengar|Sludge Bomb") ?? -1
check("T126b switch block pulled after turn line", t7Pos >= 0 && swPos == t7Pos + 1 && megaPos > swPos && mvPos > megaPos)
check("T126b unrelated line stays in old turn", loPos >= 0 && loPos < t7Pos)
let dT7 = displayLog.firstIndex(of: "Turn 7") ?? -1
let dGo = displayLog.firstIndex(of: "Go! Gengar!") ?? -1
let dHeal = displayLog.firstIndex(of: "The opposing Overqwil restored a little HP!") ?? -1
check("T126b display block moved too", dT7 >= 0 && dGo > dT7 && dHeal >= 0 && dHeal < dT7)
// c: 消費済みの オボンのみ は healSource で再発動と分類されないこと
resetAll()
monStates["p2:Clefable"] = MonState()
revealedItems["Clefable"] = "オボンのみ"
check("T126c known sitrus classified", healSource(plateName: "oppA", key: "p2:Clefable", speciesEn: "Clefable", fromPct: 45, toPct: 67)?.label == "item: Sitrus Berry")
itemLostActive.insert("p2:Clefable")
check("T126c consumed sitrus not classified", healSource(plateName: "oppA", key: "p2:Clefable", speciesEn: "Clefable", fromPct: 45, toPct: 67) == nil)
// d: 自分の吸収技の回復は技へ帰属すること
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Clefable", hpPercent: 45)
lastMoveLabel = "p2a: Clefable"
lastMoveName = "Draining Kiss"
lastMoveMsgAt = Date()
check("T126d drain heal attributed to the move", healSource(plateName: "oppA", key: "p2:Clefable", speciesEn: "Clefable", fromPct: 45, toPct: 67)?.label == "move: Draining Kiss")
// e: たくわえるの蓄積数文から技行が補われること
resetAll()
logStarted = true
currentTurn = 2
lastSlots["oppB"] = SlotState(speciesEn: "Overqwil", hpPercent: 65)
_ = translateBattleMessage("相手の ハリーマンは 1つ たくわえた！")
check("T126e stockpile move synthesized", battleLog.contains("|move|p2b: Overqwil|Stockpile"))
_ = translateBattleMessage("相手の ハリーマンは 1つ たくわえた！")
check("T126e not synthesized twice", battleLog.filter { $0 == "|move|p2b: Overqwil|Stockpile" }.count == 1)
// f: ランク変化文の断片が方向の文と結合して適用されること
resetAll()
logStarted = true
currentTurn = 4
lastSlots["oppB"] = SlotState(speciesEn: "Overqwil", hpPercent: 40)
monStates["p2:Overqwil"] = MonState()
_ = translateBattleMessage("相手の ハリーマンの 防御特防が")
_ = translateBattleMessage("ぐーんと上がった！")
check("T126f combined boost applied def", battleLog.contains("|-boost|p2b: Overqwil|def|2"))
check("T126f combined boost applied spd", battleLog.contains("|-boost|p2b: Overqwil|spd|2"))
// g: シンプルビームの特性変化行
resetAll()
logStarted = true
currentTurn = 3
lastSlots["oppB"] = SlotState(speciesEn: "Overqwil", hpPercent: 65)
check("T126g simple beam consumed", translateBattleMessage("相手の ハリーマンは たんじゅんになった！"))
check("T126g ability line emitted", battleLog.contains("|-ability|p2b: Overqwil|Simple"))
// h: エレクトロショットの吸収文は消費だけされること
resetAll()
logStarted = true
currentTurn = 3
check("T126h electro shot charge text consumed", translateBattleMessage("ブリジュラスは 電気を 吸収した！"))
check("T126h no message line left", !battleLog.contains { $0.hasPrefix("|-message|") })
// i: つぼをつく の上昇は文の読みが 1 段階でも 2 段階になること
resetAll()
logStarted = true
currentTurn = 6
lastSlots["oppA"] = SlotState(speciesEn: "Clefable", hpPercent: 45)
monStates["p2:Clefable"] = MonState()
lastMoveName = "Acupressure"
lastMoveMsgAt = Date()
checkBoostText(text: "相手の ピクシーの 防御が 上がった！", side: "p2", speciesEn: "Clefable", slot: "p2a")
check("T126i acupressure forced to +2", battleLog.contains("|-boost|p2a: Clefable|def|2"))
// j: 「ゆけっ」が 1 体ずつ届いても枠が重ならないこと
resetAll()
logStarted = true
_ = translateBattleMessage("ゆけっ！ ニョロトノ！")
_ = translateBattleMessage("ゆけっ！ ブリジュラス！")
check("T126j first lead at p1a", battleLog.contains { $0.hasPrefix("|switch|p1a: Politoed|") })
check("T126j second lead at p1b", battleLog.contains { $0.hasPrefix("|switch|p1b: Archaludon|") })
check("T126j no duplicate switch lines", battleLog.filter { $0.hasPrefix("|switch|p1") }.count == 2)
// k: アーカイブ時の HP 表記の統一
let hdr = completeArchiveHeader(protocolLines: [
    "|poke|p1|Politoed", "|poke|p1|Archaludon", "|start",
    "|switch|p1a: Politoed|Politoed|167/167",
    "|switch|p1b: Archaludon|Archaludon|100/100",
    "|-damage|p1b: Archaludon|161/167",
], displayLines: [])
check("T126k switch hp notation unified", hdr.protocolLines.contains("|switch|p1b: Archaludon|Archaludon|167/167"))
out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")"""))

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
    open(PATH, "w").write(src)
    print("applied all edits")
else:
    print("dry run ok")
