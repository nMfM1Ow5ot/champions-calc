#!/usr/bin/env python3
# Harness update for the 090354 round: prelude globals for the new
# reader globals, resetAll clears, probes replaced by T161 tests.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count = {n} (expected {count})")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

# prelude globals
rep('''var winLogged = false''',
    '''var winLogged = false
var winLineEmitted = false''',
    "prelude winLineEmitted")
rep('''var pendingStatusFrom: [String: (code: String, at: Date)] = [:]''',
    '''var pendingStatusFrom: [String: (code: String, at: Date)] = [:]
var pendingHealFrom: [String: (label: String, at: Date)] = [:]
var segmentFirstMoveAt: Date? = nil
var lastTurnLineAt = Date.distantPast''',
    "prelude heal/segment globals")

# resetAll clears (append to the winLogged clear line inside resetAll)
rep('''    logFieldWeather = ""; logFieldTerrain = ""; winLogged = false; logStarted = true''',
    '''    logFieldWeather = ""; logFieldTerrain = ""; winLogged = false; logStarted = true
    winLineEmitted = false; pendingHealFrom = [:]; segmentFirstMoveAt = nil; lastTurnLineAt = Date.distantPast''',
    "resetAll clears")

# drop the probes: cut from the PROBE header to END PROBE-C marker
start = src.find('// ===== PROBE 090354 (observation only) =====')
end_marker = '// ===== END PROBE-C =====\n'
end = src.find(end_marker)
if start < 0 or end < 0:
    print("ABORT: probe block not found", start, end)
    sys.exit(1)
src = src[:start] + src[end + len(end_marker):]
print("OK probes removed")

TESTS = '''// ===== T161 (battle_20261123_090354) =====
speciesDict.append(E("バンギラス", "Tyranitar"))
speciesDict.append(E("メガバンギラス", "Tyranitar-Mega"))
speciesDict.append(E("ヤバソチャ", "Sinistcha"))
speciesDict.append(E("ドドゲザン", "Kingambit"))
speciesAbilityMap["Tyranitar"] = ["Sand Stream"]
speciesAbilityMap["Tyranitar-Mega"] = ["Sand Stream"]
speciesAbilityMap["Sinistcha"] = ["Hospitality"]
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
speciesAbilityMap["Torkoal"] = ["Drought", "White Smoke", "Shell Armor"]
// a: やけど文の手がかり (負った) が無く、きれいな文でも状態行が出なかった
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 1)
lastSlots["oppB"] = SlotState(speciesEn: "Tyranitar", hpPercent: 89)
monStates["p2:Tyranitar"] = MonState()
_ = translateBattleMessage("相手のバンギラスはやけどを負った！")
check("T161a clean burn text produces status", battleLog.contains("|-status|p2b: Tyranitar|brn") && monStates["p2:Tyranitar"]?.status == "brn")
// b: 崩れたバンギラス (メバンギラス) でも状態行が出る
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 1)
lastSlots["oppB"] = SlotState(speciesEn: "Tyranitar", hpPercent: 89)
monStates["p2:Tyranitar"] = MonState()
if !translateBattleMessage("相手のメバンギラスはやけどを負った！") { _ = salvageFromText("相手のメバンギラスはやけどを負った！") }
check("T161b garbled Tyranitar burn produces status", battleLog.contains("|-status|p2b: Tyranitar|brn"))
// c: 三口カロス (字形混同 2 文字) でも状態行が出る
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Milotic", hpPercent: 68)
monStates["p2:Milotic"] = MonState()
if !translateBattleMessage("相手の三口カロスはやけどを負った！") { _ = salvageFromText("相手の三口カロスはやけどを負った！") }
check("T161c two-glyph Milotic burn produces status", battleLog.contains("|-status|p2b: Milotic|brn"))
// d: ヤバソチャの語順崩れ文でも状態行が出る
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 17)
monStates["p2:Sinistcha"] = MonState()
if !translateBattleMessage("ヤバソチャは相手の負つた！やけどを") { _ = salvageFromText("ヤバソチャは相手の負つた！やけどを") }
check("T161d scrambled Sinistcha burn produces status", battleLog.contains("|-status|p2a: Sinistcha|brn"))
// e: お茶文 (結合崩れ) で特性行が出て、回復の発生源が相方へ控えられる
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Milotic", hpPercent: 62)
monStates["p2:Sinistcha"] = MonState()
monStates["p2:Milotic"] = MonState()
_ = translateBattleMessage("たてた相手のヤバソチャがたてたお茶をミロカロスは飲みほした！")
check("T161e tea text emits ability", battleLog.contains("|-ability|p2a: Sinistcha|Hospitality"))
check("T161e tea heal source recorded", pendingHealFrom["p2:Milotic"]?.label == "ability: Hospitality")
let hs161 = healSource(plateName: "oppB", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 62, toPct: 85)
check("T161e plate rise adopts Hospitality heal", hs161?.label == "ability: Hospitality")
// e2: きれいな語順のお茶文でも同じ
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sinistcha", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Milotic", hpPercent: 62)
monStates["p2:Sinistcha"] = MonState()
monStates["p2:Milotic"] = MonState()
_ = translateBattleMessage("相手のヤバソチャがたてたお茶をミロカロスは飲みほした！")
check("T161e2 clean tea text emits ability", battleLog.contains("|-ability|p2a: Sinistcha|Hospitality") && pendingHealFrom["p2:Milotic"]?.label == "ability: Hospitality")
// f: 手動モードで勝敗文を 2 回読んでも勝敗行は 1 件だけ
resetAll()
flagManualMode = true
_ = translateBattleMessage("くさとの勝負に勝った！")
_ = translateBattleMessage("くさとの勝負に勝った！")
check("T161f manual win text twice gives one win", battleLog.filter { $0.hasPrefix("|win|") }.count == 1 && !winLogged)
resetAll()
flagManualMode = true
trainerOpp = "くさ"
_ = translateBattleMessage("相手のくさは勝負をあきらめた！")
_ = translateBattleMessage("相手のくさは勝負をあきらめた！")
check("T161f manual forfeit twice gives one win", battleLog.filter { $0.hasPrefix("|win|") }.count == 1 && !winLogged)
flagManualMode = false
// g: 最終同定チームによるヘッダー補完 (未登場の同定済み種族)
let proto161 = ["|gametype|doubles", "|poke|p1|Venusaur", "|poke|p2|Excadrill", "|poke|p2|Tyranitar", "|poke|p2|Milotic", "|poke|p2|Sinistcha", "|start",
                "|switch|p2a: Excadrill|Excadrill|100/100", "|switch|p2b: Tyranitar|Tyranitar|100/100", "|turn|1"]
let comp161 = completeArchiveHeader(protocolLines: proto161, displayLines: [], finalTeams: ["p2": ["Excadrill", "Tyranitar", "Milotic", "Sinistcha", "Staraptor", "Gholdengo"]])
let pokes161 = comp161.protocolLines.filter { $0.hasPrefix("|poke|p2|") }
check("T161g header completed to six", pokes161.count == 6 && pokes161.contains("|poke|p2|Staraptor") && pokes161.contains("|poke|p2|Gholdengo"))
let comp161b = completeArchiveHeader(protocolLines: proto161, displayLines: [], finalTeams: ["p2": ["Excadrill", "Tyranitar", "Milotic", "Sinistcha", "Staraptor", "Gholdengo", "Zoroark"]])
check("T161g header never exceeds six", comp161b.protocolLines.filter { $0.hasPrefix("|poke|p2|") }.count == 6)
// h: 引き戻しは経過ダメージ行を一緒に移さない
resetAll()
battleLog = ["|turn|2", "|move|p2a: Excadrill|Protect", "|move|p1b: Delphox|Protect",
             "|switch|p2b: Milotic|Milotic|100/100", "|-damage|p2b: Milotic|94/100|[from] sandstorm"]
let pb161 = pullBackSwitchBlock(label: "p2b: Milotic")
check("T161h pullback takes the switch", pb161.proto.contains("|switch|p2b: Milotic|Milotic|100/100"))
check("T161h residual chip stays at the tail", !pb161.proto.contains(where: { $0.contains("sandstorm") }) && battleLog.contains("|-damage|p2b: Milotic|94/100|[from] sandstorm"))
// i: 状態異常の経過 [from] の受け皿 (予告記録が無い場合)
resetAll()
monStates["p2:Milotic"] = MonState()
monStates["p2:Milotic"]?.status = "brn"
monStates["p2:Milotic"]?.hpPercent = 68
logFieldWeather = "Sun"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 68, toPct: 62, hpText: "62/100")
check("T161i burn chip attributed from status", battleLog.contains("|-damage|p2b: Milotic|62/100|[from] brn"))
resetAll()
monStates["p2:Milotic"] = MonState()
monStates["p2:Milotic"]?.status = "brn"
monStates["p2:Milotic"]?.hpPercent = 68
logFieldWeather = "Sand"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 68, toPct: 62, hpText: "62/100")
check("T161i no status attribution in sand", !battleLog.contains("|-damage|p2b: Milotic|62/100|[from] brn"))
logFieldWeather = ""
// j: 繰り出し文のタイミング証拠 (ターン行の後・最初の技より前)
resetAll()
emitLog("|turn|3")
sendOutTextSeen["p1"] = (species: "Torkoal", at: sNow())
emitLog("|move|p2a: Excadrill|Protect")
let ann161 = sendOutTextSeen["p1"].map { ev in ev.species == "Torkoal" && ev.at > lastTurnLineAt && (segmentFirstMoveAt.map { ev.at < $0 } ?? false) } ?? false
check("T161j announcement before first move qualifies", ann161)
resetAll()
emitLog("|turn|3")
emitLog("|move|p2a: Excadrill|Protect")
sendOutTextSeen["p1"] = (species: "Torkoal", at: sNow())
let ann161b = sendOutTextSeen["p1"].map { ev in ev.species == "Torkoal" && ev.at > lastTurnLineAt && (segmentFirstMoveAt.map { ev.at < $0 } ?? false) } ?? false
check("T161j announcement after first move does not qualify", !ann161b)

'''
ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT tests anchor: count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, TESTS + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
