#!/usr/bin/env python3
"""battle_20261122_070237 修正ラウンドの make_harness.py パッチ (準備済み)。
使い方: python3 prep_070237_harness_patch.py [apply]"""
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH).read()
EDITS = []

# 1. FUNCS に新関数を追加
EDITS.append((
"""'aliveOnFieldCount', 'awaitingReplacement', 'processPlates', 'fingerprintFiles',""",
"""'aliveOnFieldCount', 'awaitingReplacement', 'anyAwaitingReplacement', 'entryEffectPending', 'processPlates', 'fingerprintFiles',"""))

# 2. prelude に slotSwapPending スタブ
EDITS.append((
"""var pendingSwitchSpecies: [String: String] = [:]
var pendingSwitchSince: [String: Date] = [:]""",
"""var pendingSwitchSpecies: [String: String] = [:]
var pendingSwitchSince: [String: Date] = [:]
var slotSwapPending: [String: (a: String, b: String, count: Int)] = [:]"""))

# 3. resetAll に slotSwapPending リセット
EDITS.append((
"""    pendingFaints = []; faintedSlots = [:]; pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]""",
"""    pendingFaints = []; faintedSlots = [:]; pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]
    slotSwapPending = [:]"""))

# 4. speciesDict フィクスチャ (Ninetales-Alola / Milotic / Torkoal)
EDITS.append((
"""E("キュウコン", "Ninetales"), E("ロトム", "Rotom"),""",
"""E("キュウコン", "Ninetales"), E("キュウコン", "Ninetales-Alola"), E("ロトム", "Rotom"),
    E("ミロカロス", "Milotic"), E("コータス", "Torkoal"),"""))

# 5. speciesAbilityMap フィクスチャ
EDITS.append((
"""    "Typhlosion-Hisui": ["Blaze", "Frisk"],
]""",
"""    "Typhlosion-Hisui": ["Blaze", "Frisk"],
    "Ninetales": ["Flash Fire", "Drought"],
    "Ninetales-Alola": ["Snow Cloak", "Snow Warning"],
    "Milotic": ["Marvel Scale", "Competitive", "Cute Charm"],
    "Torkoal": ["White Smoke", "Drought", "Shell Armor"],
    "Staraptor": ["Intimidate", "Reckless"],
    "Farigiraf": ["Cud Chew", "Armor Tail", "Sap Sipper"],
]"""))

# 5b. prelude に lastDmgEventPrevExact スタブ
EDITS.append((
"""var battleEvents: [String] = []""",
"""var battleEvents: [String] = []
var lastDmgEventPrevExact: [String: [Int]] = [:]"""))

# 6. T121 ドライバ (最終出力の直前)
T121 = r'''
// T121a: 両枠が互いの種族を示したら、交代ではなく枠の入れ替わりとして登録を入れ替える
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 2)
lastSlots["mineB"] = SlotState(speciesEn: "Torkoal", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Milotic", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Froslass", hpPercent: 100)
monStates["p1:Sneasler"] = MonState(); monStates["p1:Sneasler"]?.hpPercent = 2
monStates["p1:Torkoal"] = MonState()
emittedSwitchKeys = ["p1:Sneasler", "p1:Torkoal", "p2:Milotic", "p2:Froslass"]
fieldSeen["p1"] = ["Sneasler", "Torkoal"]; fieldSeen["p2"] = ["Milotic", "Froslass"]
let swapHits: [String: SlotState] = ["mineA": SlotState(speciesEn: "Torkoal", hpPercent: 100), "mineB": SlotState(speciesEn: "Sneasler", hpPercent: 2), "oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Froslass", hpPercent: 100)]
processPlates(swapHits)
processPlates(swapHits)
check("T121a swap emits no switch lines", !battleLog.contains { $0.hasPrefix("|switch|p1") })
check("T121a slots swapped", lastSlots["mineA"]?.speciesEn == "Torkoal" && lastSlots["mineB"]?.speciesEn == "Sneasler")
check("T121a swap recorded", debugCaptureCalls.contains("slot_swap"))

// T121b: ひんし文の濁点ゆれ (たおれだ) を faint として消費する
resetAll()
var ms121b = MonState(); ms121b.hpPercent = 30; ms121b.hpMax = 226; ms121b.hpText = "68/226"
monStates["p2:Farigiraf"] = ms121b
lastSlots["oppB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 30)
lastEmittedPct["oppB"] = 30
emittedSwitchKeys = ["p2:Farigiraf"]
let t121b = translateBattleMessage("相手のリキキリンはたおれだ！")
check("T121b garbled faint consumed", t121b)
check("T121b faint damage from text", battleLog.contains("|-damage|p2b: Farigiraf|0/226"))
emitPendingFaints()
check("T121b faint line", battleLog.contains("|faint|p2b: Farigiraf"))
check("T121b no message dup", !battleLog.contains { $0.hasPrefix("|-message|") && $0.contains("たおれだ") })

// T121c: 行動不能文の 動→勤 ゆれを cant として消費する
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 2)
monStates["p1:Sneasler"] = MonState()
emittedSwitchKeys = ["p1:Sneasler"]
let t121c = translateBattleMessage("オオニューラは凍ってしまって勤けない！")
check("T121c garbled cant consumed", t121c)
check("T121c cant line", battleLog.contains("|-cant|p1a: Sneasler|frz"))
check("T121c no message dup", !battleLog.contains { $0.hasPrefix("|-message|") && $0.contains("勤けない") })

// T121d: 0% への低下は HP 補正として握りつぶさない (ひんしとして出す)
resetAll()
var ms121d = MonState(); ms121d.hpPercent = 2; ms121d.hpMax = 155; ms121d.hpText = "3/155"
monStates["p1:Sneasler"] = ms121d
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 2)
lastEmittedPct["mineB"] = 2
lastDamageTime["mineB"] = Date(timeIntervalSinceNow: -30)
lastMoveMsgAt = Date(timeIntervalSinceNow: -30)
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Sneasler", speciesEn: "Sneasler", fromPct: 2, toPct: 0, hpText: "0/155", force: true)
check("T121d zero drop emitted as damage", battleLog.contains("|-damage|p1b: Sneasler|0/155"))
resetAll()
monStates["p1:Sneasler"] = ms121d
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 2)
lastEmittedPct["mineB"] = 2
lastDamageTime["mineB"] = Date(timeIntervalSinceNow: -30)
lastMoveMsgAt = Date(timeIntervalSinceNow: -30)
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Sneasler", speciesEn: "Sneasler", fromPct: 2, toPct: 1, hpText: "1/155", force: true)
check("T121d nonzero small correction stays silent", !battleLog.contains { $0.hasPrefix("|-damage|p1b") })

// T121e: オボンのみ回復の途中値は確定せず、最終値で 1 行にする
resetAll()
var ms121e = MonState(); ms121e.hpPercent = 55; ms121e.hpMax = 226; ms121e.hpText = "125/226"
monStates["p1:Farigiraf"] = ms121e
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 55)
lastEmittedPct["mineB"] = 30
let held121e = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Farigiraf", speciesEn: "Farigiraf", fromPct: 30, toPct: 50, hpText: "114/226", force: true)
check("T121e mid-animation sitrus held", !held121e && !battleLog.contains { $0.hasPrefix("|-heal|") } && lastEmittedPct["mineB"] == 30)
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Farigiraf", speciesEn: "Farigiraf", fromPct: 30, toPct: 55, hpText: "125/226", force: true)
check("T121e final sitrus emitted", battleLog.contains("|-heal|p1b: Farigiraf|125/226|[from] item: Sitrus Berry"))

// T121f: 場の誰のフォルムでも説明できない天候は、別フォルムの特性として訂正・帰属する
resetAll()
currentTurn = 4
lastSlots["oppA"] = SlotState(speciesEn: "Milotic", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Torkoal", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Staraptor", hpPercent: 100)
monStates["p2:Ninetales"] = MonState()
emittedSwitchKeys = ["p2:Milotic", "p2:Ninetales", "p1:Torkoal", "p1:Staraptor"]
battleLog = ["|switch|p2b: Ninetales|Ninetales|100/100"]
lastSwitchIn["p2:Ninetales"] = ("p2b", Date())
switchInTurn["p2:Ninetales"] = 4
logFieldWeather = "Snow"; fieldWeatherSetAt = Date(); fieldWeatherSetTurn = 4; fieldSetByMoveTurn = -1
attributeFieldAbilities()
check("T121f forme corrected", lastSlots["oppB"]?.speciesEn == "Ninetales-Alola")
check("T121f ability attributed", battleLog.contains("|-ability|p2b: Ninetales-Alola|Snow Warning"))
check("T121f switch line rewritten", battleLog.contains("|switch|p2b: Ninetales-Alola|Ninetales-Alola|100/100"))

// T121g: ひんし交代の要員待ちの間は天候開始を保留し、後任の登録後に流す
resetAll()
logFieldWeather = "Sun"
lastSlots["oppA"] = SlotState(speciesEn: "Milotic", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Torkoal", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 2)
faintedSlots["p2b"] = "Froslass"
fieldSeen["p2"] = ["Milotic", "Froslass"]
fieldSeen["p1"] = ["Torkoal", "Sneasler"]
setWeather("Snow", "Snow", via: "あいて相手のキュウコンのゆきふらし")
check("T121g weather held while awaiting", logFieldWeather == "Sun" && heldWeatherStart != nil)
lastSlots["oppB"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
fieldSeen["p2"] = ["Milotic", "Froslass", "Ninetales"]
processPlates(["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Ninetales", hpPercent: 100), "mineA": SlotState(speciesEn: "Torkoal", hpPercent: 100), "mineB": SlotState(speciesEn: "Sneasler", hpPercent: 2)])
check("T121g weather flushed after replacement", logFieldWeather == "Snow")

// T121h: 入場効果の保留は要員待ちでも効き、後続の変化も一緒に保留される
resetAll()
currentTurn = 4
lastSlots["oppA"] = SlotState(speciesEn: "Milotic", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Torkoal", hpPercent: 100)
monStates["p2:Milotic"] = MonState()
emittedSwitchKeys = ["p2:Milotic", "p1:Torkoal"]
faintedSlots["p1b"] = "Sneasler"
fieldSeen["p1"] = ["Sneasler", "Torkoal", "Staraptor"]
fieldSeen["p2"] = ["Milotic", "Froslass", "Ninetales", "Incineroar"]
lastMoveMsgAt = Date(timeIntervalSinceNow: -10); lastMoveName = "Eruption"
applyBoost(key: "p2:Milotic", slot: "p2a", speciesEn: "Milotic", stat: "atk", delta: -1)
check("T121h atk drop held", !battleLog.contains { $0.hasPrefix("|-unboost|p2a: Milotic") } && heldEntryBoosts.count == 1)
applyBoost(key: "p2:Milotic", slot: "p2a", speciesEn: "Milotic", stat: "spa", delta: 2)
check("T121h follow-up boost held together", !battleLog.contains { $0.hasPrefix("|-boost|p2a: Milotic") } && heldEntryBoosts.count == 2)
lastSlots["mineB"] = SlotState(speciesEn: "Staraptor", hpPercent: 100)
emittedSwitchKeys.insert("p1:Staraptor")
processPlates(["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "mineA": SlotState(speciesEn: "Torkoal", hpPercent: 100), "mineB": SlotState(speciesEn: "Staraptor", hpPercent: 100)])
check("T121h boosts flushed after entry", battleLog.contains("|-unboost|p2a: Milotic|atk|1") && battleLog.contains("|-boost|p2a: Milotic|spa|2"))

// T122a: 遅い解決でも dmg イベントを落とさない (時刻ガードの緩和)
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 1
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p1:Sneasler"] = MonState()
lastEmittedPct["mineA"] = 100
lastMoveLabel = "p2b: Froslass"; lastMoveName = "Blizzard"; lastMoveMsgAt = Date(timeIntervalSinceNow: -12); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 41, hpText: "64/155", force: true)
let ev122a = battleEvents.last { $0.contains("\"k\":\"dmg\"") } ?? ""
check("T122a slow event recorded", ev122a.contains("\"atk\":\"p2b: Froslass\"") && ev122a.contains("\"pct\":59"))

// T122b: 同じ基準からの再放出は上書きされ、二重化しない (最終値が残る)
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 2
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 50)
var ms122 = MonState(); ms122.hpPercent = 50; ms122.hpMax = 226; ms122.hpText = "114/226"
monStates["p1:Farigiraf"] = ms122
lastEmittedPct["mineB"] = 50
lastMoveLabel = "p2b: Froslass"; lastMoveName = "Blizzard"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Farigiraf", speciesEn: "Farigiraf", fromPct: 50, toPct: 20, hpText: "45/226", force: true)
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Farigiraf", speciesEn: "Farigiraf", fromPct: 50, toPct: 0, hpText: "0/226", force: true)
let evs122 = battleEvents.filter { $0.contains("\"k\":\"dmg\"") && $0.contains("Farigiraf") }
check("T122b re-emission supersedes", evs122.count == 1 && (evs122.first ?? "").contains("\"pct\":50"))

// T122c: 急所文が後から来たら、記録済みイベントの crit を是正する
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 2
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 100)
var ms122c = MonState(); ms122c.hpPercent = 100; ms122c.hpMax = 226; ms122c.hpText = "226/226"
monStates["p1:Farigiraf"] = ms122c
lastEmittedPct["mineB"] = 100
lastMoveLabel = "p2b: Froslass"; lastMoveName = "Blizzard"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Farigiraf", speciesEn: "Farigiraf", fromPct: 100, toPct: 50, hpText: "113/226", force: true)
let t122c = translateBattleMessage("急所に当たった！")
check("T122c crit text consumed", t122c)
let ev122c = battleEvents.last { $0.contains("\"k\":\"dmg\"") } ?? ""
check("T122c crit patched", ev122c.contains("\"crit\":true"))

out(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")'''
EDITS.append((
"""out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")""",
T121))

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
