#!/usr/bin/env python3
# Harness updates for the mineTeam provisional-list implementation:
# - FUNCS: extract the new functions
# - prelude: struct + globals; mirror the startBattleLog header precedence
# - resetAll: clear the new globals
# - driver: T128a-h tests
import sys

HPATH = "/home/hatch/workspace/logfix_test/make_harness.py"
src = open(HPATH, encoding="utf-8").read()

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
    "'minePlateAdmitted', 'noteBattleMaxRead', 'battleKnownMax', 'fieldSourceOnField', 'megaLabelSpecies',",
    "'minePlateAdmitted', 'noteBattleMaxRead', 'battleKnownMax', 'fieldSourceOnField', 'megaLabelSpecies', 'syncMineProvisional', 'mineTeamJSON', 'noteMineMove', 'mergeMineDetailFromCapture', 'mineProvisionalSpecies',")

# ---------------------------------------------------------------- prelude globals
rep("prelude globals",
    "var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]\n",
    """var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]
struct MineProvisionalEntry {
    var species: String
    var source: String = "preview"
    var ability: String? = nil
    var item: String? = nil
    var moves: [String] = []
    var hpMax: Int? = nil
    var onField: Bool = false
}
var battleMineTeam: [MineProvisionalEntry?] = []
var headerMineTeam: [String] = []
var minePreviewSeenCopy: [String?] = []
var minePreviewAppliedCopy: [String?] = []
var minePreviewUpdatedAt: Date? = nil
var lastBattleStartedAt: Date? = nil
var minePreviewTeam: [String?] = []
var minePreviewDetails: [[String: Any]] = []
""")

# ---------------------------------------------------------------- resetAll
rep("resetAll additions",
    "    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]\n",
    "    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; pendingReturnCount = [:]\n"
    "    battleMineTeam = []; headerMineTeam = []; minePreviewSeenCopy = []; minePreviewAppliedCopy = []; minePreviewUpdatedAt = nil; lastBattleStartedAt = nil; minePreviewTeam = []; minePreviewDetails = []\n")

# ---------------------------------------------------------------- startBattleLog copy mirror
rep("startBattleLog copy",
    "    emitLog(\"|gametype|doubles\")\n    for sp in teamOrder { emitLog(\"|poke|p1|\\(sp)\") }\n",
    "    emitLog(\"|gametype|doubles\")\n"
    "    syncMineProvisional()\n"
    "    let mineHeaderSpecies = mineProvisionalSpecies()\n"
    "    if !mineHeaderSpecies.isEmpty {\n"
    "        for sp in mineHeaderSpecies { emitLog(\"|poke|p1|\\(sp)\") }\n"
    "        headerMineTeam = mineHeaderSpecies\n"
    "    } else {\n"
    "        for sp in teamOrder { emitLog(\"|poke|p1|\\(sp)\") }\n"
    "        headerMineTeam = teamOrder\n"
    "    }\n")

# ---------------------------------------------------------------- driver tests
TESTS = r'''
// T128: 自チーム暫定リスト (mineTeam) の保持・優先・露出
// a: 選出同定があれば、ヘッダーは登録ではなく暫定リストで書く
resetAll()
teamOrder = ["Gengar", "Incineroar", "Politoed", "Archaludon", "Gardevoir", "Armarouge"]
teamEntries = [:]
minePreviewTeam = ["Gardevoir", nil, "Indeedee-F", "Sneasler", "Armarouge", "Whimsicott"]
minePreviewDetails = []
startBattleLog()
check("T128a header uses provisional", battleLog.contains("|poke|p1|Indeedee-F") && battleLog.contains("|poke|p1|Sneasler"))
check("T128a header excludes foreign registration", !battleLog.contains("|poke|p1|Gengar"))
check("T128a headerMineTeam recorded", headerMineTeam == ["Gardevoir", "Indeedee-F", "Sneasler", "Armarouge", "Whimsicott"])

// b: 前の試合の同定結果 (古い更新時刻) は使わない
resetAll()
teamOrder = ["Gengar", "Armarouge"]
minePreviewTeam = ["Indeedee-F", "Sneasler"]
minePreviewSeenCopy = ["Indeedee-F", "Sneasler"]
minePreviewUpdatedAt = Date(timeIntervalSinceNow: -3600)
lastBattleStartedAt = Date()
syncMineProvisional()
check("T128b stale preview not applied", battleMineTeam.isEmpty)
startBattleLog()
check("T128b header falls back to registration", battleLog.contains("|poke|p1|Gengar") && headerMineTeam == ["Gengar", "Armarouge"])

// c: state.json に mineTeam が載り、場の確認が onField に反映される
resetAll()
minePreviewTeam = ["Gardevoir", "Indeedee-F"]
minePreviewDetails = []
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Gholdengo", hpPercent: 100)
fieldSeen["p1"] = ["Gardevoir"]
writeState()
let sj128 = (try? String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)) ?? ""
check("T128c mineTeam in state", sj128.contains("\"mineTeam\""))
check("T128c mineTeam species", sj128.contains("\"species\": \"Gardevoir\"") && sj128.contains("\"species\": \"Indeedee-F\""))
check("T128c onField marked", sj128.contains("\"onField\": true"))

// d: 暫定リストの種族は初見でもプレートを受け入れる
resetAll()
teamEntries = ["Gengar": ["stats": ["hp": 100]]]
battleMineTeam = [MineProvisionalEntry(species: "Sneasler")]
check("T128d provisional species admitted", minePlateAdmitted(plateKey: "mineB", entry: E("オオニューラ", "Sneasler")))

// e: 最大 HP は暫定リストの実数値が登録に優先し、試合内上書きがさらに優先する
resetAll()
teamEntries = ["Gardevoir": ["stats": ["hp": 999]]]
battleMineTeam = [MineProvisionalEntry(species: "Gardevoir", hpMax: 145)]
check("T128e provisional max beats registration", battleKnownMax(speciesEn: "Gardevoir", grp: formeGroup(E("サーナイト", "Gardevoir"))) == 145)
battleMaxOverride["Gardevoir"] = 150
check("T128e battle override beats provisional", battleKnownMax(speciesEn: "Gardevoir", grp: formeGroup(E("サーナイト", "Gardevoir"))) == 150)

// f: 自軍の技行だけが暫定リストの技に積み上がる
resetAll()
battleMineTeam = [MineProvisionalEntry(species: "Gardevoir")]
noteMineMove(label: "p1a: Gardevoir", move: "Hyper Voice")
check("T128f mine move learned", battleMineTeam[0]?.moves.contains("Hyper Voice") == true)
noteMineMove(label: "p2a: Gholdengo", move: "Shadow Ball")
check("T128f opp move ignored", battleMineTeam[0]?.moves.count == 1)

// g: チーム撮影の判明項目が暫定リストへ反映される
resetAll()
battleMineTeam = [MineProvisionalEntry(species: "Indeedee-F")]
teamEntries = ["Indeedee-F": ["ability": "Psychic Surge", "item": "Rocky Helmet", "stats": ["hp": 155]]]
mergeMineDetailFromCapture()
check("T128g detail merged", battleMineTeam[0]?.ability == "Psychic Surge" && battleMineTeam[0]?.item == "Rocky Helmet" && battleMineTeam[0]?.hpMax == 155)
check("T128g source marked detail", battleMineTeam[0]?.source.contains("detail") == true)

// h: 選出同定の詳細 (持ち物) が暫定リストへ引き継がれる
resetAll()
minePreviewTeam = ["Gardevoir"]
minePreviewDetails = [["species": "Gardevoir", "item": "Gardevoirite"]]
syncMineProvisional()
check("T128h preview item inherited", battleMineTeam[0]?.item == "Gardevoirite")
'''

anchor = 'check("T127m stale pending passes valve", battleLog.contains { $0.hasPrefix("|switch|p1b: Sneasler") })\n'
rep("driver T128 tests", anchor, anchor + TESTS)

open(HPATH, "w", encoding="utf-8").write(src)
print("ALL HARNESS EDITS APPLIED")
