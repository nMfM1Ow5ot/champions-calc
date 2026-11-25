#!/usr/bin/env python3
# Harness updates for the battle_20261122_231107 fix round:
# - FUNCS: annotateFieldLineFromAbility
# - prelude emitLog copy: mirror the [from] annotation hook
# - T138: removal rule is now margin-based (update the fixture)
# - T146 header (231107 numbers), T147 miss text evidence,
#   T148 field [from] annotation, T149 switch defer (processPlates)
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()

def rep(old, new, tag, count=1):
    global src
    n = src.count(old)
    if n != count:
        print(f"ABORT {tag}: anchor count {n} != {count}")
        sys.exit(1)
    src = src.replace(old, new, count)
    print("OK", tag)

rep("'terrainSourcePlausible', 'confirmHeldTerrainReplace', 'fieldLineForAbility',",
    "'terrainSourcePlausible', 'confirmHeldTerrainReplace', 'fieldLineForAbility', 'annotateFieldLineFromAbility',",
    "FUNCS add annotate")

rep('''    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        debugCapture(kind: "ability_guard", key: "ability_guard:\\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }''',
    '''    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        debugCapture(kind: "ability_guard", key: "ability_guard:\\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    if line.hasPrefix("|-ability|") { annotateFieldLineFromAbility(line) }''',
    "prelude emitLog hook")

# T138 fixture: scores -> margins (same intent: Slowking/Arcanine are the
# shaky slots, Kommo-o's win was decisive)
rep('''// ===== T138: header completion removes lowest-scored unused species =====''',
    '''// ===== T138: header completion removes smallest-margin unused species =====''',
    "T138 title")
rep('''let hdrScores: [String: Double] = ["p2:Delphox": 0.309, "p2:Slowking-Galar": 0.126, "p2:Arcanine": 0.146, "p2:Kommo-o": 0.332]
let hdrDone = completeArchiveHeader(protocolLines: hdrProto, displayLines: [], idScores: hdrScores)
check("T138a Kommo-o kept by score", hdrDone.protocolLines.contains("|poke|p2|Kommo-o"))
check("T138b lowest scores removed", hdrDone.removed.contains("p2:Slowking-Galar") && hdrDone.removed.contains("p2:Arcanine") && !hdrDone.removed.contains("p2:Kommo-o"))''',
    '''let hdrMargins: [String: Double] = ["p2:Delphox": 0.90, "p2:Slowking-Galar": 0.05, "p2:Arcanine": 0.08, "p2:Kommo-o": 0.40]
let hdrDone = completeArchiveHeader(protocolLines: hdrProto, displayLines: [], slotMargins: hdrMargins)
check("T138a Kommo-o kept by margin", hdrDone.protocolLines.contains("|poke|p2|Kommo-o"))
check("T138b smallest margins removed", hdrDone.removed.contains("p2:Slowking-Galar") && hdrDone.removed.contains("p2:Arcanine") && !hdrDone.removed.contains("p2:Kommo-o"))''',
    "T138 margins")

anchor = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
if src.count(anchor) != 1:
    print("ABORT tail anchor", src.count(anchor)); sys.exit(1)

tests = '''// T146 (battle_20261122_231107): ヘッダー補正の置換先は誤同定の枠。
// Barbaracle (pick 0.45) の次点が実登場の Basculegion-F (0.591)、
// Sneasler (-0.19) の次点は 0.707 で大差。正しい Sneasler を残し
// Barbaracle を落とすこと
let hdr2Proto = ["|gametype|doubles",
                 "|poke|p2|Golisopod", "|poke|p2|Raichu", "|poke|p2|Pelipper", "|poke|p2|Barbaracle", "|poke|p2|Archaludon", "|poke|p2|Sneasler",
                 "|start",
                 "|switch|p2a: Pelipper|Pelipper|100/100",
                 "|switch|p2b: Basculegion-F|Basculegion-F|100/100",
                 "|switch|p2a: Archaludon|Archaludon|100/100"]
let hdr2Pick: [String: String] = ["p2:Basculegion-F": "Barbaracle"]
let hdr2Margins: [String: Double] = ["p2:Barbaracle": 0.141, "p2:Sneasler": 0.897, "p2:Golisopod": 0.03, "p2:Raichu": 0.302]
let hdr2Done = completeArchiveHeader(protocolLines: hdr2Proto, displayLines: [], pickByCandidate: hdr2Pick, slotMargins: hdr2Margins)
check("T146a runner-up evidence removes the misidentified pick", hdr2Done.removed.contains("p2:Barbaracle") && !hdr2Done.removed.contains("p2:Sneasler"))
check("T146b appeared species added, correct species kept", hdr2Done.added.contains("p2:Basculegion-F") && hdr2Done.protocolLines.contains("|poke|p2|Sneasler"))
let hdr2MarginOnly = completeArchiveHeader(protocolLines: hdr2Proto, displayLines: [], slotMargins: hdr2Margins)
check("T146c margin-only also removes Barbaracle", hdr2MarginOnly.removed.contains("p2:Barbaracle"))

// T147 (battle_20261122_231107): 交代記録も候補も無いミス文を、
// 繰り出し文の証拠 (sendOutTextSeen) が救うこと
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 100)
monStates["p1:Charizard"] = MonState(hpPercent: 100, hpText: "153/153")
monStates["p1:Venusaur"] = MonState(hpPercent: 100, hpText: "157/157")
lastMoveLabel = "p2b: Basculegion-F"
lastMoveName = "Muddy Water"
lastMoveMsgAt = Date()
_ = translateBattleMessage("フシギバナには当たらなかった！")
check("T147a miss suppressed without any evidence", !battleLog.contains { $0.contains("-miss") })
battleLog = []
sendOutTextSeen["p1"] = (species: "Venusaur", at: Date())
_ = translateBattleMessage("フシギバナには当たらなかった！")
check("T147b send-out text evidence admits the miss line", battleLog.contains("|-miss|p2b: Basculegion-F|p1a: Venusaur"))

// T148 (battle_20261122_231107): 特性行が遅れた場合に天候の開始行へ
// [from] の帰属が付くこと。技由来の開始行には付かないこと
resetAll()
battleLog = ["|turn|1", "|switch|p2a: Pelipper|Pelipper|100/100", "|-weather|Rain Dance"]
emitLog("|-ability|p2a: Pelipper|Drizzle")
check("T148a weather line annotated from ability", battleLog.contains("|-weather|Rain Dance|[from] ability: Drizzle|[of] p2a: Pelipper"))
resetAll()
battleLog = ["|turn|1", "|move|p1a: Indeedee-F|Rain Dance", "|-weather|Rain Dance", "|switch|p2a: Pelipper|Pelipper|100/100"]
emitLog("|-ability|p2a: Pelipper|Drizzle")
check("T148b move-sourced weather not annotated", battleLog.contains("|-weather|Rain Dance") && !battleLog.contains { $0.contains("[from] ability: Drizzle") })

// T149 (battle_20261122_231107): 要員選択中の交代確定は破棄でなく
// 保留になり、選択終了後に確定すること。幻の候補は実プレートが
// 戻れば確定しないこと
resetAll()
currentTurn = 2
teamEntries["Venusaur"] = ["ability": "", "item": ""]
teamEntries["Charizard"] = ["ability": "", "item": ""]
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 0)
lastEmittedPct["mineA"] = 100
lastEmittedPct["mineB"] = 0
monStates["p1:Charizard"] = MonState(hpPercent: 100, hpText: "153/153")
monStates["p1:Farigiraf"] = MonState(hpPercent: 0, hpText: "0/226")
monStates["p1:Venusaur"] = MonState(hpPercent: 100, hpText: "157/157")
fieldSeen["p1"] = ["Charizard", "Farigiraf"]
faintedSlots["p1b"] = "Farigiraf"
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
check("T149a busy confirmation deferred, not dropped", !battleLog.contains { $0.hasPrefix("|switch|p1a: Venusaur") } && pendingSwitchCandidates["mineA"]?["Venusaur"] != nil && debugCaptureCalls.contains("switch_guard_drop"))
faintedSlots = [:]
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
check("T149b deferred switch confirms after selection ends", battleLog.contains { $0.hasPrefix("|switch|p1a: Venusaur") })
resetAll()
currentTurn = 2
teamEntries["Venusaur"] = ["ability": "", "item": ""]
teamEntries["Charizard"] = ["ability": "", "item": ""]
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 0)
lastEmittedPct["mineA"] = 100
lastEmittedPct["mineB"] = 0
monStates["p1:Charizard"] = MonState(hpPercent: 100, hpText: "153/153")
monStates["p1:Farigiraf"] = MonState(hpPercent: 0, hpText: "0/226")
monStates["p1:Venusaur"] = MonState(hpPercent: 100, hpText: "157/157")
fieldSeen["p1"] = ["Charizard", "Farigiraf"]
faintedSlots["p1b"] = "Farigiraf"
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
processPlates(["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100)])
faintedSlots = [:]
processPlates(["mineA": SlotState(speciesEn: "Charizard", hpPercent: 100)])
processPlates(["mineA": SlotState(speciesEn: "Charizard", hpPercent: 100)])
check("T149c phantom candidate never confirms once the real plate returns", !battleLog.contains { $0.hasPrefix("|switch|p1a: Venusaur") })

'''
src = src.replace(anchor, tests + anchor, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("HARNESS PATCHED")
