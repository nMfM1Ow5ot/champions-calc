import sys
PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(PATH, encoding="utf-8").read()
def rep(old, new, n=1):
    global src
    c = src.count(old)
    if c != n:
        print(f"ABORT count={c}: {old[:70]!r}"); sys.exit(1)
    src = src.replace(old, new)

# 1) prelude globals: candidate tuple type + revert counter
rep("var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]",
    """var battleMaxCandidate: [String: (max: Int, count: Int, firstAt: Date)] = [:]
var battleMaxRevertCount: [String: Int] = [:]""")
# 2) prelude global: protectMoveName
rep("var protectMoveTurn: [String: Int] = [:]",
    """var protectMoveTurn: [String: Int] = [:]
var protectMoveName: [String: String] = [:]""")
# 3) resetAll additions
rep("protectMoveTurn = [:]; effectBySeq = [:];",
    "protectMoveTurn = [:]; protectMoveName = [:]; effectBySeq = [:];")
rep("battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:];",
    "battleMaxOverride = [:]; battleMaxCandidate = [:]; battleMaxRevertCount = [:]; pendingReturnCount = [:];")
# 4) prelude emitLog copy: mirror the Protect/Detect recording in the |move| branch
rep("""    if line.hasPrefix("|move|") {
""",
"""    if line.hasPrefix("|move|") {
        let pmf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if pmf.count >= 4 && (pmf[3] == "Protect" || pmf[3] == "Detect") {
            let pslot = pmf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn; protectMoveName[pslot] = pmf[3] }
        }
""")
# 5) T127b: backdate the candidate so the second sighting is time-spread
rep("""noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)
check("T127b one sighting not adopted", battleMaxOverride["Armarouge"] == nil)
noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)""",
"""noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)
check("T127b one sighting not adopted", battleMaxOverride["Armarouge"] == nil)
battleMaxCandidate["Armarouge"] = (max: 161, count: 1, firstAt: Date(timeIntervalSinceNow: -4))
noteBattleMaxRead(speciesEn: "Armarouge", readMax: 161, registeredMax: 150)""")
# 6) T150 tests before the final summary
rep('''check("T149c phantom candidate never confirms once the real plate returns", !battleLog.contains { $0.hasPrefix("|switch|p1a: Venusaur") })

out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")''',
'''check("T149c phantom candidate never confirms once the real plate returns", !battleLog.contains { $0.hasPrefix("|switch|p1a: Venusaur") })

// T150 (battle_20261123_043809): suspect 解消の ±3 採用、最大 HP のバースト不採用と取消し、漢字「眠」、Detect の activate
// a: 保留値の ±3 以内の読みは次ターンに無音採用される
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 3
monStates["p2:Dragonite"] = MonState()
monStates["p2:Dragonite"]?.hpPercent = 54
suspectJump["oppB"] = (toPct: 6, turn: 3)
lastEmittedPct["oppB"] = 54
currentTurn = 4
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Dragonite", speciesEn: "Dragonite", fromPct: 54, toPct: 5, hpText: "5/100", force: true)
check("T150a near suspect value adopted next turn", monStates["p2:Dragonite"]?.hpPercent == 5 && suspectJump["oppB"] == nil && !battleLog.contains { $0.contains("-damage|p2b: Dragonite") })
// b: 保留値から遠い値は従来どおり再保留される
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 3
monStates["p2:Dragonite"] = MonState()
monStates["p2:Dragonite"]?.hpPercent = 54
suspectJump["oppB"] = (toPct: 6, turn: 3)
lastEmittedPct["oppB"] = 54
currentTurn = 4
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Dragonite", speciesEn: "Dragonite", fromPct: 54, toPct: 40, hpText: "40/100", force: true)
check("T150b far value still re-held", suspectJump["oppB"]?.toPct == 40 && !battleLog.contains { $0.contains("-damage|p2b: Dragonite") })
// c: 最大 HP は短時間のバーストでは採用されず、時間をおいた一致で採用され、登録値の読みが続けば取り消される
resetAll()
teamEntries = ["Sylveon": ["stats": ["hp": 193]]]
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 219, registeredMax: 193)
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 219, registeredMax: 193)
check("T150c burst sightings not adopted", battleMaxOverride["Sylveon"] == nil)
battleMaxCandidate["Sylveon"] = (max: 219, count: 2, firstAt: Date(timeIntervalSinceNow: -4))
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 219, registeredMax: 193)
check("T150c adopted after time spread", battleMaxOverride["Sylveon"] == 219)
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 193, registeredMax: 193)
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 193, registeredMax: 193)
check("T150c two registered reads keep override", battleMaxOverride["Sylveon"] == 219)
noteBattleMaxRead(speciesEn: "Sylveon", readMax: 193, registeredMax: 193)
check("T150c reverted after three registered reads", battleMaxOverride["Sylveon"] == nil && debugCaptureCalls.contains("team_max_reverted"))
// d: 漢字「眠ってしまった」が |-status| になる (両経路)。眠気は対象外
resetAll()
monStates["p2:Primarina"] = MonState()
checkStatusText(text: "相手のアシレーヌは眠ってしまった！", side: "p2", speciesEn: "Primarina", slot: "p2a")
check("T150d kanji sleep becomes status", battleLog.contains("|-status|p2a: Primarina|slp"))
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Primarina", hpPercent: 63)
check("T150d salvage kanji sleep", salvageStatus(in: "相手のアシレーヌは眠ってしまった！") && battleLog.contains("|-status|p2a: Primarina|slp"))
check("T150d yawn text not salvaged as sleep", !salvageStatus(in: "相手のアシレーヌは眠気を誘った！"))
// e: Detect の成功文に activate 行 (move: Detect) が付く
resetAll()
logStarted = true
currentTurn = 6
lastSingleActAt = [:]
lastSlots["mineA"] = SlotState(speciesEn: "Sylveon", hpPercent: 88)
emitLog("|move|p1a: Sylveon|Detect")
_ = translateBattleMessage("ニンフィアは攻撃から身を守った！")
check("T150e detect activate emitted", battleLog.contains("|-activate|p1a: Sylveon|move: Detect"))

out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")''')

open(PATH, "w", encoding="utf-8").write(src)
print("OK")
