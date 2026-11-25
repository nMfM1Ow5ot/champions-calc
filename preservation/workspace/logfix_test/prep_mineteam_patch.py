#!/usr/bin/env python3
# 自チーム暫定リスト (mineTeam) のバックエンド実装:
# - 暫定リストの保持 (battleMineTeam) と同定結果の取り込み (syncMineProvisional)
# - state.json への露出 (writeState の mineTeam)
# - 登録より優先: ヘッダー |poke|p1 / プレート受け入れ / 最大 HP 参照
# - 更新経路: 場の観測 (sync 内)、技行 (noteMineMove)、チーム撮影 (mergeMineDetailFromCapture)
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ---------------------------------------------------------------- P1: globals + core functions
rep("P1 provisional core",
    "var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数\n",
    """var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数

// MARK: - 自チーム暫定リスト (当該試合)
// 見せ合いで同定された自チームの種族を当該試合の正とし、場の観測・
// チーム撮影 (ようすをみる画面相当) ・技の判明で随時更新する。登録
// チーム (teamEntries / teamOrder) と矛盾する場合はこちらを優先する
// (ユーザーの明示指示 2026-11-22、総合チャット経由)。同定そのものは
// 画像認識側の担当で、結果は minePreviewTeam / minePreviewDetails で
// 受け取る。state.json へは mineTeam として出す (UI 側は種族構成が
// 矛盾すれば暫定リストでパネルを組み直す)
struct MineProvisionalEntry {
    var species: String
    var source: String = "preview"   // 判明経路 (preview / field / detail を "+" で併記)
    var ability: String? = nil
    var item: String? = nil
    var moves: [String] = []
    var hpMax: Int? = nil
    var onField: Bool = false
}
var battleMineTeam: [MineProvisionalEntry?] = []  // 選出画面の枠順 (未同定は nil)
var headerMineTeam: [String] = []                  // ヘッダーに書いた自軍の種族
var minePreviewSeenCopy: [String?] = []            // 変化検出用の控え
var minePreviewAppliedCopy: [String?] = []         // 暫定リストへ反映済みの控え
var minePreviewUpdatedAt: Date? = nil              // 同定結果が最後に変わった時刻
var lastBattleStartedAt: Date? = nil               // 直近の試合開始時刻

func mineProvisionalSpecies() -> [String] {
    battleMineTeam.compactMap { $0?.species }
}

// 画像認識側の同定結果を取り込み、場の観測で裏付ける。writeState と
// startBattleLog から呼ぶ (冪等)
func syncMineProvisional() {
    if minePreviewTeam != minePreviewSeenCopy {
        minePreviewSeenCopy = minePreviewTeam
        if minePreviewTeam.contains(where: { $0 != nil }) { minePreviewUpdatedAt = Date() }
    }
    // 鮮度: 同定の更新が直近の試合開始より 120 秒以上前なら、前の
    // 試合の同定結果なので使わない
    let fresh = minePreviewUpdatedAt.map {
        $0.timeIntervalSince(lastBattleStartedAt ?? .distantPast) > -120
    } ?? false
    if fresh && minePreviewTeam != minePreviewAppliedCopy {
        minePreviewAppliedCopy = minePreviewTeam
        battleMineTeam = minePreviewTeam.enumerated().map { (i, sp) -> MineProvisionalEntry? in
            guard let sp else { return nil }
            var e = MineProvisionalEntry(species: sp)
            // 選出画面で読めた持ち物は同定の詳細から引き継ぐ
            if minePreviewDetails.indices.contains(i),
               let it = minePreviewDetails[i]["item"] as? String, !it.isEmpty {
                e.item = it
            }
            return e
        }
    }
    // 場の観測で裏付ける (登場済みの印と最大 HP)
    for i in battleMineTeam.indices {
        guard var e = battleMineTeam[i] else { continue }
        if !e.onField, fieldSeen["p1"]?.contains(where: { sameSpeciesFamily($0, e.species) }) == true {
            e.onField = true
            if !e.source.contains("field") { e.source += "+field" }
        }
        if e.hpMax == nil, let m = monStates["p1:\\(e.species)"]?.hpMax, m > 0 {
            e.hpMax = m
        }
        battleMineTeam[i] = e
    }
}

// state.json の mineTeam 断片 (対戦形)。同定済みの種族だけを枠順に
// 詰めて出す (未同定の枠は要素を出さない。UI 側は「無い = 居ない」
// とは解釈せず、6体そろうまでは既存パネルを残す)
func mineTeamJSON() -> String {
    var parts: [String] = []
    for case let e? in battleMineTeam {
        var s = "{\\"species\\": \\"\\(jsonEscape(e.species))\\", \\"source\\": \\"\\(jsonEscape(e.source))\\""
        if let a = e.ability { s += ", \\"ability\\": \\"\\(jsonEscape(a))\\"" }
        if let it = e.item { s += ", \\"item\\": \\"\\(jsonEscape(it))\\"" }
        if !e.moves.isEmpty {
            s += ", \\"moves\\": [\\(e.moves.map { "\\"\\(jsonEscape($0))\\"" }.joined(separator: ", "))]"
        }
        if let m = e.hpMax { s += ", \\"hpMax\\": \\(m)" }
        if e.onField { s += ", \\"onField\\": true" }
        parts.append(s + "}")
    }
    return parts.isEmpty ? "" : ", \\"mineTeam\\": [\\(parts.joined(separator: ", "))]"
}

// 自軍の技行から暫定リストへ技を積み上げる (技の判明で更新)
func noteMineMove(label: String, move: String) {
    guard label.hasPrefix("p1") else { return }
    let sp = label.split(separator: ":").last.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    guard !sp.isEmpty else { return }
    for i in battleMineTeam.indices {
        guard var e = battleMineTeam[i], sameSpeciesFamily(e.species, sp) else { continue }
        if !e.moves.contains(move) && e.moves.count < 4 {
            e.moves.append(move)
            battleMineTeam[i] = e
        }
        return
    }
}

// チーム撮影で得た情報 (ようすをみる画面相当の観測) を、種族が一致
// する暫定リストの要素へ反映する。種族の同一性は暫定リストが正で、
// ここでは判明項目を埋めるだけ
func mergeMineDetailFromCapture() {
    guard !battleMineTeam.isEmpty else { return }
    for i in battleMineTeam.indices {
        guard var e = battleMineTeam[i] else { continue }
        guard let key = teamEntries.keys.first(where: { sameSpeciesFamily($0, e.species) }),
              let ent = teamEntries[key] else { continue }
        var changed = false
        if let ab = ent["ability"] as? String, !ab.isEmpty, e.ability == nil { e.ability = ab; changed = true }
        if let it = ent["item"] as? String, !it.isEmpty, e.item == nil { e.item = it; changed = true }
        if let mv = ent["moves"] as? [String], !mv.isEmpty, e.moves.isEmpty { e.moves = Array(mv.prefix(4)); changed = true }
        if let st = ent["stats"] as? [String: Int], let hp = st["hp"], hp > 0, e.hpMax == nil { e.hpMax = hp; changed = true }
        if changed {
            if !e.source.contains("detail") { e.source += "+detail" }
            battleMineTeam[i] = e
        }
    }
}
""")

# ---------------------------------------------------------------- P2: schema keys doc
rep("P2 stateMineTeamKeys",
    "let stateRevealedKeys: Set<String> = [\"moves\", \"item\", \"ability\"]\n",
    "let stateRevealedKeys: Set<String> = [\"moves\", \"item\", \"ability\"]\n"
    "let stateMineTeamKeys: Set<String> = [\"species\", \"source\", \"ability\", \"item\", \"moves\", \"hpMax\", \"onField\"]  // mineTeam の要素キー\n")

# ---------------------------------------------------------------- P3: writeState sync
rep("P3 writeState sync",
    "    // state.json はバトルログ由来の状態 (monStates) から生成する\n",
    "    // state.json はバトルログ由来の状態 (monStates) から生成する\n"
    "    syncMineProvisional()\n")

# ---------------------------------------------------------------- P4: writeState mineTeam fragment
rep("P4a mineTeamJson decl",
    "    let team = oppTeamSeen.isEmpty ? \"\" : \", \\\"oppTeam\\\": [\\(oppTeamSeen.map { \"\\\"\\(jsonEscape($0))\\\"\" }.joined(separator: \", \"))]\"\n",
    "    let team = oppTeamSeen.isEmpty ? \"\" : \", \\\"oppTeam\\\": [\\(oppTeamSeen.map { \"\\\"\\(jsonEscape($0))\\\"\" }.joined(separator: \", \"))]\"\n"
    "    let mineTeamJson = mineTeamJSON()\n")
rep("P4b json assembly",
    "\\(team)\\(revJson)\\(trainer)",
    "\\(team)\\(mineTeamJson)\\(revJson)\\(trainer)")

# ---------------------------------------------------------------- P5: startBattleLog
rep("P5a battle start stamp",
    "func startBattleLog() {\n    // 前の試合が未保存のまま新しい試合が始まる場合は、先に前試合を残す\n",
    "func startBattleLog() {\n    lastBattleStartedAt = Date()\n    // 前の試合が未保存のまま新しい試合が始まる場合は、先に前試合を残す\n")
rep("P5b header precedence",
    "    emitLog(\"|gametype|doubles\")\n    for sp in teamOrder { emitLog(\"|poke|p1|\\(sp)\") }\n",
    """    emitLog("|gametype|doubles")
    // 自軍ヘッダーは当該試合の暫定リスト (見せ合い同定) を登録より
    // 優先する。暫定リストが無い試合では従来どおり登録順で出す
    syncMineProvisional()
    let mineHeaderSpecies = mineProvisionalSpecies()
    if !mineHeaderSpecies.isEmpty {
        for sp in mineHeaderSpecies { emitLog("|poke|p1|\\(sp)") }
        headerMineTeam = mineHeaderSpecies
    } else {
        for sp in teamOrder { emitLog("|poke|p1|\\(sp)") }
        headerMineTeam = teamOrder
    }
""")

# ---------------------------------------------------------------- P6: emitLog mv hook
rep("P6 mv hook",
    "            battleEvents.append(\"{\\\"k\\\":\\\"mv\\\",\\\"turn\\\":\\(currentTurn),\\\"label\\\":\\\"\\(jsonEscape(f[2]))\\\",\\\"move\\\":\\\"\\(jsonEscape(f[3]))\\\"}\")\n        }\n    }\n",
    "            battleEvents.append(\"{\\\"k\\\":\\\"mv\\\",\\\"turn\\\":\\(currentTurn),\\\"label\\\":\\\"\\(jsonEscape(f[2]))\\\",\\\"move\\\":\\\"\\(jsonEscape(f[3]))\\\"}\")\n        }\n"
    "        if f.count >= 4 { noteMineMove(label: f[2], move: f[3]) }\n    }\n")

# ---------------------------------------------------------------- P7: admission precedence
rep("P7 admission",
    "func minePlateAdmitted(plateKey: String, entry: SpeciesEntry) -> Bool {\n",
    "func minePlateAdmitted(plateKey: String, entry: SpeciesEntry) -> Bool {\n"
    "    // 当該試合の暫定リストにある種族は、登録より優先して受け入れる\n"
    "    for case let e? in battleMineTeam where sameSpeciesFamily(e.species, entry.en) { return true }\n")

# ---------------------------------------------------------------- P8: known max precedence
rep("P8 known max",
    "func battleKnownMax(speciesEn: String, grp: [SpeciesEntry]) -> Int? {\n    if let o = battleMaxOverride[speciesEn] { return o }\n",
    "func battleKnownMax(speciesEn: String, grp: [SpeciesEntry]) -> Int? {\n"
    "    if let o = battleMaxOverride[speciesEn] { return o }\n"
    "    // 暫定リストで実数値が判明している種族はそれを使う (登録より優先)\n"
    "    for case let e? in battleMineTeam where e.species == speciesEn {\n"
    "        if let m = e.hpMax { return m }\n"
    "    }\n")

# ---------------------------------------------------------------- P9: capture merge hook
rep("P9 capture merge",
    "    if updated > 0 || pruned { writeTeamFile() }\n",
    "    if updated > 0 || pruned { writeTeamFile() }\n"
    "    if updated > 0 { mergeMineDetailFromCapture() }\n")

# ---------------------------------------------------------------- P10: build stamp
rep("P10 build stamp",
    "let readerBuild = \"20261122_1202\"",
    "let readerBuild = \"20261122_1159\"")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
