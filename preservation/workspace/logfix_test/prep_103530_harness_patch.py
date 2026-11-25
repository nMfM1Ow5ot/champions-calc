#!/usr/bin/env python3
# Harness updates for the battle_20261122_103530 fix round:
# - FUNCS: extract the new reader helpers
# - prelude: declare the new globals; mirror the emitLog damage-insertion
#   branch (extracted from the patched reader.swift, backslashes doubled
#   because the prelude is a non-raw Python string)
# - resetAll: clear the new globals
# - driver: add T127a-m tests
import sys

HPATH = "/home/hatch/workspace/logfix_test/make_harness.py"
RPATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(HPATH, encoding="utf-8").read()
reader = open(RPATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ---------------------------------------------------------------- FUNCS
rep("FUNCS additions",
    "'regexGroups', 'pullBackSwitchBlock',",
    "'regexGroups', 'pullBackSwitchBlock', 'minePlateAdmitted', 'noteBattleMaxRead', 'battleKnownMax', 'fieldSourceOnField', 'megaLabelSpecies',")

# ---------------------------------------------------------------- prelude globals
rep("prelude globals",
    "var pendingDamageSince: [String: Date] = [:]\n",
    "var pendingDamageSince: [String: Date] = [:]\n"
    "var pendingReturnCount: [String: Int] = [:]\n"
    "var battleAdmittedSpecies: Set<String> = []\n"
    "var offTeamPlateStreak: [String: Int] = [:]\n"
    "var battleMaxOverride: [String: Int] = [:]\n"
    "var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]\n")

# ---------------------------------------------------------------- resetAll
rep("resetAll additions",
    "    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false\n",
    "    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false\n"
    "    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]\n")

# ---------------------------------------------------------------- prelude emitLog: decl
rep("prelude emitLog decl",
    "    // 並びの訂正 (本体 emitLog と同一ロジック)\n    var insertAt: Int? = nil\n",
    "    // 並びの訂正 (本体 emitLog と同一ロジック)\n    var insertAt: Int? = nil\n    var dmgReorderMoveLabel: String? = nil\n")

# ---------------------------------------------------------------- prelude emitLog: damage branch (extracted from reader)
rlines = reader.split("\n")
j = next(i for i, l in enumerate(rlines) if "if let insertAt { battleLog.insert(line, at: insertAt)" in l)
start = None
for i in range(j - 1, -1, -1):
    if rlines[i].strip() == '} else if line.hasPrefix("|-damage|") {':
        start = i
        break
if start is None:
    print("ABORT: reader damage branch not found")
    sys.exit(1)
branch = "\n".join(rlines[start:j])
branch_doubled = branch.replace("\\", "\\\\")
lines = src.split("\n")
hits = [i for i, l in enumerate(lines) if l == "    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }"]
if len(hits) != 1:
    print(f"ABORT: prelude insertAt line count = {len(hits)}")
    sys.exit(1)
i = hits[0]
if lines[i - 1] != "    }":
    print(f"ABORT: prelude line before insertAt is not the chain close: {lines[i-1]!r}")
    sys.exit(1)
lines[i - 1] = branch_doubled
src = "\n".join(lines)
print("OK: prelude emitLog damage branch")

# ---------------------------------------------------------------- driver tests
TESTS = r'''
// T127: battle_20261122_103530 の対応 (登録ずれ耐性・引き戻し・幻ひんし ほか)
// a: 登録外種族の試合内受け入れ (3 回の観測で採用し、証拠を残す)
resetAll()
teamEntries = ["Gardevoir": ["stats": ["hp": 145]], "Armarouge": ["stats": ["hp": 161]]]
check("T127a off-team 1st sighting rejected", !minePlateAdmitted(plateKey: "mineB", entry: E("イエッサン", "Indeedee-F")))
check("T127a off-team 2nd sighting rejected", !minePlateAdmitted(plateKey: "mineB", entry: E("イエッサン", "Indeedee-F")))
check("T127a off-team 3rd sighting admitted", minePlateAdmitted(plateKey: "mineB", entry: E("イエッサン", "Indeedee-F")))
check("T127a forme group admitted together", minePlateAdmitted(plateKey: "mineA", entry: E("イエッサン", "Indeedee")))
check("T127a evidence recorded", debugCaptureCalls.contains("off_team_plate"))
check("T127a in-team immediate", minePlateAdmitted(plateKey: "mineA", entry: E("サーナイト", "Gardevoir")))

// b: 最大 HP の読み優先 (2 回の一致観測で採用)
resetAll()
teamEntries = ["Armarouge": ["stats": ["hp": 150]]]
noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)
check("T127b one sighting not adopted", battleMaxOverride["Armarouge"] == nil)
noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)
check("T127b two sightings adopted", battleMaxOverride["Armarouge"] == 161)
check("T127b evidence recorded", debugCaptureCalls.contains("team_max_mismatch"))
check("T127b known max prefers override", battleKnownMax(speciesEn: "Armarouge", grp: formeGroup(E("グレンアルマ", "Armarouge"))) == 161)

// c: メガの側判定 (ファミリー照合と登録所在)
resetAll()
if !speciesDict.contains(where: { $0.en == "Floette-Eternal" }) { speciesDict.append(E("フラエッテ", "Floette-Eternal")) }
lastSlots["oppA"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 75)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
check("T127c mega side by family", megaTextSide("フラエッテのフロエッタイトとキーストーンが反応した！", baseEn: "Floette") == "p2")
resetAll()
oppTeamSeen = ["Floette"]
check("T127c mega side by registration", megaTextSide("フラエッテのフロエッタイトとキーストーンが反応した！", baseEn: "Floette") == "p2")

// d: メガ完了行のラベルを場の実表記に寄せる
resetAll()
if !speciesDict.contains(where: { $0.en == "Floette-Eternal" }) { speciesDict.append(E("フラエッテ", "Floette-Eternal")) }
if !speciesDict.contains(where: { $0.en == "Floette-Mega" }) { speciesDict.append(E("メガフラエッテ", "Floette-Mega")) }
itemDict[normalize("フロエッタイト")] = "フロエッタイト"; itemJa2En["フロエッタイト"] = "Floettite"
lastSlots["oppA"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 75)
monStates["p2:Floette-Eternal"] = MonState()
pendingMegaSpecies["p2"] = "Floette"
pendingMegaStone["p2"] = "フロエッタイト"
let ml127 = megaLabelSpecies(side: "p2", speciesEn: "Floette")
check("T127d label species anchored", ml127.slot == "p2a" && ml127.speciesEn == "Floette-Eternal")
completeMega(side: "p2", baseEn: "Floette", megaEn: "Floette-Mega")
check("T127d detailschange uses field forme", battleLog.contains("|detailschange|p2a: Floette-Eternal|Floette-Mega"))
check("T127d mega line label anchored", battleLog.contains("|-mega|p2a: Floette-Eternal|Floette|Floettite"))
check("T127d mega state on field entry", monStates["p2:Floette-Eternal"]?.megaSpecies == "Floette-Mega")

// e: てだすけ の遅れ告知は出さない (区間に他の技行がある場合)
resetAll()
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 50)
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 61)
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Gholdengo", hpPercent: 100)
fieldSeen["p1"] = ["Gardevoir", "Indeedee-F"]; fieldSeen["p2"] = ["Floette", "Gholdengo"]
battleLog = ["|turn|4", "|move|p2a: Floette|Draining Kiss"]
movesSinceTurnLine = ["p2a: Floette"]
actionSeq = 5
let t127e = translateBattleMessage("味方のイエッサンのてだすけ！")
check("T127e late HH consumed", t127e)
check("T127e late HH suppressed", !battleLog.contains { $0.hasPrefix("|move|") && $0.contains("Helping Hand") })
check("T127e priority guard recorded", debugCaptureCalls.contains("move_guard"))
battleLog = ["|turn|4"]
movesSinceTurnLine = []
_ = translateBattleMessage("味方のイエッサンのてだすけ！")
check("T127e first HH emitted", battleLog.contains("|move|p1b: Indeedee-F|Helping Hand"))

// f: 対象なしの外れ文は消費し、未解決の相手枠が 1 つなら外れ行を出す
resetAll()
currentTurn = 6
lastSlots["mineA"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 45)
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Gholdengo", hpPercent: 90)
lastMoveLabel = "p2b: Gholdengo"
lastMoveName = "Make It Rain"
lastMoveMsgAt = Date()
actionSeq = 9
damagedBySeq[9] = ["p1b: Sneasler"]
let t127f = translateBattleMessage("当たらなかった！")
check("T127f bare miss consumed", t127f)
check("T127f miss emitted for unresolved target", battleLog.contains("|-miss|p2b: Gholdengo|p1a: Armarouge"))

// g: 被ダメ行は技の自己ランク変化行より前に戻る
resetAll()
currentTurn = 2
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 100)
battleLog = ["|turn|2"]
displayLog = ["Turn 2"]
lastMoveLabel = "p1b: Armarouge"
lastMoveName = "Armor Cannon"
lastMoveMsgAt = Date()
emitLog("|move|p1b: Armarouge|Armor Cannon")
emitLog("|-unboost|p1b: Armarouge|def|1")
emitLog("|-unboost|p1b: Armarouge|spd|1")
emitLog("|-damage|p2a: Floette|41/100")
let gDmg = battleLog.firstIndex(of: "|-damage|p2a: Floette|41/100") ?? -1
let gBoost = battleLog.firstIndex(of: "|-unboost|p1b: Armarouge|def|1") ?? -1
check("T127g damage before self drops", gDmg >= 0 && gBoost >= 0 && gDmg < gBoost)

// h: まもる を使った枠の 0% 読みは幻ひんしとして捨てる
resetAll()
currentTurn = 6
lastSlots["oppA"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Gholdengo", hpPercent: 90)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 50)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p2:Floette-Eternal"] = MonState(); monStates["p2:Floette-Eternal"]?.hpPercent = 75; monStates["p2:Floette-Eternal"]?.hpText = "75/100"
lastEmittedPct["oppA"] = 75
emittedSwitchKeys = ["p2:Floette-Eternal", "p2:Gholdengo", "p1:Gardevoir", "p1:Armarouge"]
fieldSeen["p1"] = ["Gardevoir", "Armarouge"]; fieldSeen["p2"] = ["Floette-Eternal", "Gholdengo"]
protectMoveTurn["p2a"] = 6
lastMoveLabel = "p1b: Armarouge"
lastMoveMsgAt = Date()
let faintHits: [String: SlotState] = ["oppA": SlotState(speciesEn: "Floette-Eternal", hpPercent: 0), "oppB": SlotState(speciesEn: "Gholdengo", hpPercent: 90), "mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50), "mineB": SlotState(speciesEn: "Armarouge", hpPercent: 100)]
processPlates(faintHits)
processPlates(faintHits)
check("T127h protected zero read discarded", !battleLog.contains { $0.hasPrefix("|-damage|p2a: Floette-Eternal|0") })
check("T127h faint guard recorded", debugCaptureCalls.contains("faint_guard"))
protectMoveTurn["p2a"] = nil
processPlates(faintHits)
pendingDamageSince["oppA"] = Date(timeIntervalSinceNow: -1)
processPlates(faintHits)
check("T127h unprotected zero confirms", battleLog.contains { $0.hasPrefix("|-damage|p2a: Floette-Eternal|0") })

// i: 保留中の被ダメは基準値への 1 回の戻り読みでは消えない
resetAll()
currentTurn = 3
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]?.hpPercent = 100; monStates["p1:Gardevoir"]?.hpText = "145/145"
lastEmittedPct["mineA"] = 100
teamEntries = ["Gardevoir": ["stats": ["hp": 145]]]
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50, hpCur: 73, hpMax: 145)])
check("T127i pending set", pendingDamagePct["mineA"] == 50)
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)])
check("T127i pending survives one return", pendingDamagePct["mineA"] == 50)
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50, hpCur: 73, hpMax: 145)])
check("T127i pending intact after re-read", pendingDamagePct["mineA"] == 50)
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)])
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)])
check("T127i pending cleared after two returns", pendingDamagePct["mineA"] == nil)

// j: ターン開始時の任意交代の確定が遅れたら、ターン行の直後へ引き戻す
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p1a: Gardevoir|Hyper Voice"]
lastSlots["oppA"] = SlotState(speciesEn: "Gholdengo", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p2:Gholdengo"] = MonState(); monStates["p2:Gholdengo"]?.hpPercent = 100
oppTeamSeen = ["Gholdengo", "Floette", "Rillaboom"]
let swHits: [String: SlotState] = ["oppA": SlotState(speciesEn: "Rillaboom", hpPercent: 100), "oppB": SlotState(speciesEn: "Floette", hpPercent: 75), "mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 100), "mineB": SlotState(speciesEn: "Armarouge", hpPercent: 100)]
processPlates(swHits)
processPlates(swHits)
let jSw = battleLog.firstIndex(of: "|switch|p2a: Rillaboom|Rillaboom|100/100") ?? -1
let jMv = battleLog.firstIndex(of: "|move|p1a: Gardevoir|Hyper Voice") ?? -1
check("T127j switch pulled to turn head", jSw == 1 && jMv > jSw)
check("T127j pullback recorded", debugCaptureCalls.contains("turn_guard"))

// k: ターン0 で出所が場にいない地形開始は保留し、出所の登場後に流す
resetAll()
currentTurn = 0
lastSlots["oppA"] = SlotState(speciesEn: "Gholdengo", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
setTerrain("Grassy", via: "ゴリランダーのグラスフィールド！")
check("T127k sourceless turn0 terrain held", logFieldTerrain.isEmpty && heldTerrainStart != nil)
check("T127k no fieldstart line yet", !battleLog.contains { $0.hasPrefix("|-fieldstart|") })
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
processPlates(["oppA": SlotState(speciesEn: "Rillaboom", hpPercent: 100), "oppB": SlotState(speciesEn: "Floette", hpPercent: 100), "mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 100), "mineB": SlotState(speciesEn: "Armarouge", hpPercent: 100)])
check("T127k terrain flushed after source", logFieldTerrain == "Grassy")

// l: 反動の途中値は 3 秒以内・5 ポイントまでなら直前の被ダメ行に吸収する
resetAll()
currentTurn = 6
monStates["p2:Gholdengo"] = MonState(); monStates["p2:Gholdengo"]?.hpPercent = 94; monStates["p2:Gholdengo"]?.hpText = "94/100"
lastSlots["oppB"] = SlotState(speciesEn: "Gholdengo", hpPercent: 94)
lastEmittedPct["oppB"] = 94
lastDamageSeq["oppB"] = actionSeq
lastDamageTurn["oppB"] = 6
lastDamageDir["oppB"] = -1
lastDamageTime["oppB"] = Date()
let lBefore = battleLog.count
let lAbsorbed = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Gholdengo", speciesEn: "Gholdengo", fromPct: 94, toPct: 90, hpText: "90/100", force: true)
check("T127l 4pt tail within 3s absorbed", lAbsorbed && battleLog.count == lBefore && lastEmittedPct["oppB"] == 90)
lastDamageTime["oppB"] = Date()
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Gholdengo", speciesEn: "Gholdengo", fromPct: 90, toPct: 84, hpText: "84/100", force: true)
check("T127l 6pt tail not absorbed", battleLog.count > lBefore)

// m: 要員待ちガードは、確定試行が 20 秒を超えた交代には適用しない
resetAll()
currentTurn = 5
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 0)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]?.hpPercent = 0
monStates["p1:Armarouge"] = MonState()
faintedSlots["p1a"] = "Gardevoir"
fieldSeen["p1"] = ["Gardevoir", "Armarouge"]
emittedSwitchKeys = ["p1:Gardevoir", "p1:Armarouge"]
let mHits: [String: SlotState] = ["mineB": SlotState(speciesEn: "Sneasler", hpPercent: 100)]
processPlates(mHits)
processPlates(mHits)
check("T127m fresh pending still guarded", !battleLog.contains { $0.hasPrefix("|switch|p1b: Sneasler") })
check("T127m guard drop recorded", debugCaptureCalls.contains("switch_guard_drop"))
resetAll()
currentTurn = 5
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 0)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]?.hpPercent = 0
monStates["p1:Armarouge"] = MonState()
faintedSlots["p1a"] = "Gardevoir"
fieldSeen["p1"] = ["Gardevoir", "Armarouge"]
emittedSwitchKeys = ["p1:Gardevoir", "p1:Armarouge"]
processPlates(mHits)
pendingSwitchSince["mineB"] = Date(timeIntervalSinceNow: -25)
processPlates(mHits)
check("T127m stale pending passes valve", battleLog.contains { $0.hasPrefix("|switch|p1b: Sneasler") })
'''

anchor = 'check("T126k switch hp notation unified", hdr.protocolLines.contains("|switch|p1b: Archaludon|Archaludon|167/167"))\n'
rep("driver T127 tests", anchor, anchor + TESTS)

open(HPATH, "w", encoding="utf-8").write(src)
print("ALL HARNESS EDITS APPLIED")
