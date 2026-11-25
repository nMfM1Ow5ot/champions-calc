
import Foundation

func out(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
var failures = 0
func check(_ name: String, _ cond: Bool) {
    if cond { out("PASS \(name)") } else { failures += 1; out("FAIL \(name)") }
}

struct SpeciesEntry { let ja: String; let en: String; let id: String; let norm: String }
struct SlotState { var speciesEn: String; var hpPercent: Int; var hpCur: Int? = nil; var hpMax: Int? = nil; var hpBarPct: Int? = nil }
struct MonState {
    var hpPercent: Int = 100
    var hpText: String = "100/100"
    var hpMax: Int? = nil
    var status: String = ""   // Showdown コード (brn/par/psn/tox/slp/frz)、なしは ""
    var boosts: [String: Int] = [:]   // ランク変化 (atk/def/spa/spd/spe/acc/eva)
    var megaSpecies: String = ""   // メガシンカ済みならその種族EN (キーはベース種族のまま)
}

var speciesDict: [SpeciesEntry] = []
var monStates: [String: MonState] = [:]
var revealedMoves: [String: [String]] = [:]
var revealedItems: [String: String] = [:]
var revealedAbilities: [String: String] = [:]
var lastSlots: [String: SlotState] = [:]
var oppTeamSeen: [String] = []
var previewTeamWritten = false
var renderFainted: Set<String> = []
var renderLastPct: [String: Int] = [:]
var renderBerryAt: [String: (item: String, at: Date)] = [:]
var renderPokeP1: [String] = []
var renderPokeP2: [String] = []
var renderSlotSpecies: [String: String] = [:]
var renderWeatherProto = ""
var renderHold: [String] = []
var renderPendingBlank = false
var renderMovesSeen = false
var renderFaintPending = false
func regulationDisplay() -> String { "M-C" }
var teamOrder: [String] = []
var teamEntries: [String: [String: Any]] = [:]
var speciesAbilityMap: [String: [String]] = [:]
var abilityDict: [String: String] = [:]
var itemDict: [String: String] = [:]
var moveNameOrig: [String: String] = [:]
var abilityJa2En: [String: String] = [:]
var itemJa2En: [String: String] = [:]
var moveJa2En: [String: String] = [:]

var battleLog: [String] = []
var actionSeq = 0
var currentTurn = 0
var logStarted = false
var winLogged = false
var winLineEmitted = false
var inBattle = false
var flagManualMode = false
var previewHandled = false
var flagStartSeqSeen = 0
var flagEndSeqSeen = 0
var flagControlAdopted = false
var battleArchived = false
var emptyBattleFrames = 0
var lastArchiveSnapshotCount = -1
var lastLogEventAt = Date.distantPast
var interruptedSaveEnabled = false
var oppUnconfirmed: Set<String> = []
var displayLog: [String] = []
var displayPrintedCount = 0
var headerPrintReady = false
var headerLineCount = 0
var movesSinceTurnLine: Set<String> = []
var enteredThisSegment: Set<String> = []
var roundEventSeen = false
var suppressNextDetectorTurn = false
var defaultAttribCount: [String: Int] = [:]
let readerBuild = "harness"
var trainerMine = "Ren"
var trainerOpp = ""
var oppRank = ""
var oppRating = ""
var headerOppTeam: [String] = []
var headerMismatchFired: Set<String> = []
var forfeitName: String? = nil
var lastMsgNorm = ""
var preStartEvents: [(Date, String)] = []
let readerStartedAt = Date()
var lastMsgAt = Date.distantPast
var pendingMegaStone: [String: String] = [:]
var pendingMegaSpecies: [String: String] = [:]
var emittedSwitchKeys: Set<String> = []
struct Plate { let name: String; let x0, y0, x1, y1: Double; let isMine: Bool }
let plates: [Plate] = [
    Plate(name: "oppA", x0: 0, y0: 0, x1: 1, y1: 1, isMine: false),
    Plate(name: "oppB", x0: 0, y0: 0, x1: 1, y1: 1, isMine: false),
    Plate(name: "mineA", x0: 0, y0: 0, x1: 1, y1: 1, isMine: true),
    Plate(name: "mineB", x0: 0, y0: 0, x1: 1, y1: 1, isMine: true),
]
var pendingDamagePct: [String: Int] = [:]
var pendingDamageSince: [String: Date] = [:]
var pendingReturnCount: [String: Int] = [:]
var pendingSwitchCandidates: [String: [String: (count: Int, firstSeen: Date, lastSeen: Date)]] = [:]
var battleAdmittedSpecies: Set<String> = []
var offTeamPlateStreak: [String: Int] = [:]
var battleMaxOverride: [String: Int] = [:]
var battleMaxCandidate: [String: (max: Int, count: Int, firstAt: Date)] = [:]
var battleMaxRevertCount: [String: Int] = [:]
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
var minePreviewEvidence: [[String: Any]] = []
var previewEvidenceTeam: [String?] = []
var pendingDamageCount: [String: Int] = [:]
var heldLine: [String: (toPct: Int, dir: Int, seq: Int, turn: Int, hpText: String)] = [:]
var lastDamageSeq: [String: Int] = [:]
var lastDamageTurn: [String: Int] = [:]
var lastDamageDir: [String: Int] = [:]
var lastDamageTime: [String: Date] = [:]
var suspectJump: [String: (toPct: Int, turn: Int, hpText: String)] = [:]
var firstEntryPlateHP: [String: String] = [:]
var sitrusWatch: [String: Int] = [:]
var lastMoveEmitSeq = -1
var lastSwitchEmitSeq = -1
var fieldSetByMoveTurn = -1
var switchInTurn: [String: Int] = [:]
var heldWeatherStart: (ui: String, logName: String, text: String, at: Date)? = nil
var heldTerrainStart: (ui: String, text: String, at: Date)? = nil
var heldTerrainReplace: (ui: String, text: String, at: Date)? = nil
var pivotReturnAt: [String: Date] = [:]
var sendOutTextSeen: [String: (species: String, at: Date)] = [:]
var lastRoundEventAt: Date? = nil
var barVetoHold: [String: (pct: Int, turn: Int)] = [:]
var faintReviveCount: [String: Int] = [:]
var faintReviveSince: [String: Date] = [:]
var fieldHoldBypass = false
var wishSetTurn: [String: Int] = [:]
var pendingFaints: [(slot: String, speciesEn: String, at: Date)] = []
var faintedSlots: [String: String] = [:]
var pendingSwitchSpecies: [String: String] = [:]
var pendingSwitchSince: [String: Date] = [:]
var slotSwapPending: [String: (a: String, b: String, count: Int)] = [:]
var stateSnapRecords: [[String: Any]] = []
var stateSnapLeadIn: [[String: Any]] = []
var stateSnapKey = ""
var stateSnapLastShape = ""
var stateSnapLastEvents = -1
var stateSnapFirstBattlePending = true
var stateSnapFlushCount = 0
func flushStateSnapshots() { stateSnapFlushCount += 1 }   // ファイル書き出しは検証対象外のためスタブ (呼び出しだけ数える)
// reader.swift の natureTable の手書きコピー (25 性格の補正先/元。多行の
// リテラルのため extract_const では取り込めない)
let natureTable: [(up: Int?, down: Int?)] = [
    (nil, nil), (1, 2), (1, 5), (1, 3), (1, 4),
    (2, 1), (nil, nil), (2, 5), (2, 3), (2, 4),
    (5, 1), (5, 2), (nil, nil), (5, 3), (5, 4),
    (3, 1), (3, 2), (3, 5), (nil, nil), (3, 4),
    (4, 1), (4, 2), (4, 5), (4, 3), (nil, nil),
]
var grassyHealTurn: [String: Int] = [:]
var pendingSwitchCount: [String: Int] = [:]
var heldBoostLines: [String: [(stat: String, delta: Int, at: Date)]] = [:]
var faintedSpecies: Set<String> = []
var heldEntryBoosts: [(key: String, line: String, at: Date)] = []
var logTrickRoom = false
var debugMode = false
var pendingUnburden: Set<String> = []
var battleArchiveId = ""
var subActive: Set<String> = []
var boostTouchedStats: Set<String> = []
let outURL = URL(fileURLWithPath: "/tmp/harness_state.json")
var lastWritten = ""
var fieldWeatherSetTurn = 0
var fieldTerrainSetTurn = 0
var prevFieldWeather = ""
var prevFieldWeatherSetTurn = 0
var prevFieldTerrain = ""
var prevFieldTerrainSetTurn = 0
let recoilMoves: Set<String> = ["Double-Edge", "Take Down", "Submission", "Volt Tackle", "Flare Blitz", "Brave Bird", "Wood Hammer", "Head Smash", "Wild Charge", "Head Charge", "Struggle", "Wave Crash", "Steel Beam", "Mind Blown", "Chloroblast"]
var fieldTrickRoomSetTurn = 0
var sideCondSetTurns: [String: [String: Int]] = [:]
var unburdenActive: Set<String> = []
var boostPathAt: [String: (at: Date, salvage: Bool)] = [:]
var battleEvents: [String] = []
var lastDmgEventPrevExact: [String: [Int]] = [:]
var lastExactHp: [String: [Int]] = [:]
var entryBatchId = 0
var entryBatchOpen = false
var entryBatchMembers: Set<String> = []
var entryBatchAbBuffer: [(label: String, ability: String)] = []
var eventSlotSpecies: [String: String] = [:]
var itemLostActive: Set<String> = []
var recentAtkDrops: [String: (at: Date, seq: Int)] = [:]
var lastSwitchIn: [String: (slot: String, at: Date)] = [:]
var fieldSeen: [String: Set<String>] = ["p1": [], "p2": []]
var intimidateDone: [String: Date] = [:]
var fieldAbilityDone: [String: Date] = [:]
var lastBoostApply: [String: (seq: Int, turn: Int, at: Date)] = [:]
var lastEffectAt: [String: Date] = [:]
var protectMoveTurn: [String: Int] = [:]
var protectMoveName: [String: String] = [:]
var effectBySeq: [Int: [String: String]] = [:]
var damagedBySeq: [Int: Set<String>] = [:]
var lastAbilityEmit: [String: Date] = [:]
var lastItemEmit: [String: Date] = [:]
var lastMoveSigAt: [String: Date] = [:]
var lastMoveSigSeq: [String: Int] = [:]
var prevBoostFragment: (text: String, speciesEn: String, side: String, at: Date)? = nil
var lastSingleActAt: [String: Date] = [:]
var lastSideCondAt: [String: Date] = [:]
var lastCritAt: [String: Date] = [:]
var critEventMarks: [String: (turn: Int, atk: String)] = [:]
var lastMoveBySlot: [String: (move: String, turn: Int)] = [:]
var lastMissKey = ""
var pendingAbilityReveal: [String: String] = [:]
var frameAt = Date()
func sNow() -> Date { Date() }
var skippedShotsThisBattle = 0
func flushPendingSkipObs() {}
var lastDamageAt = Date.distantPast
var lastDamageLabel = ""
var lastPendingLabel = ""
var lastMoveLabel = ""
var lastMoveName = ""
var lastMoveMsgAt = Date.distantPast
var lastMoveSeq = -1
var pendingStatusFrom: [String: (code: String, at: Date)] = [:]
var pendingHealFrom: [String: (label: String, at: Date)] = [:]
var segmentFirstMoveAt: Date? = nil
var lastTurnLineAt = Date.distantPast
var pendingHazard: (side: String, hazard: String, seq: Int)? = nil
var pendingRemoval: (side: String, seq: Int)? = nil
var battleHazards: [String: [String: Int]] = [:]
var lastEmittedPct: [String: Int] = [:]
var logFieldWeather = ""
var logFieldTerrain = ""
var fieldWeatherSetAt = Date.distantPast
var fieldTerrainSetAt = Date.distantPast

let protocolLogURL = URL(fileURLWithPath: "/tmp/harness_protocol.log")
let battleLogURL = URL(fileURLWithPath: "/tmp/harness_battle.log")

// emitLog スタブ: 本体の actionSeq 進行と |switch| フックだけを再現する
func emitLog(_ line: String) { emitLog(line, applyNow: true) }
func emitLog(_ line: String, applyNow: Bool) {
    // 本体と同一: 勝敗確定後の新規行は次試合のものとして先に開始する
    if winLogged { startBattleLog() }
    let line = fieldLineWithAttribution(line)
    // 本体と同一: あり得ない特性行・技行のガードと、技行前のひんし行フラッシュ
    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        debugCapture(kind: "ability_guard", key: "ability_guard:\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    if line.hasPrefix("|move|") {
        let pmf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if pmf.count >= 4 && (pmf[3] == "Protect" || pmf[3] == "Detect") {
            let pslot = pmf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn; protectMoveName[pslot] = pmf[3] }
        }
        emitPendingFaints()
        if moveLineHardImplausible(line) {
            debugCapture(kind: "move_guard", key: "move_guard:\(line)", rawText: "",
                         detail: ["line": line, "turn": currentTurn])
            return
        }
        if moveLineOffField(line) {
            debugCapture(kind: "move_guard", key: "move_guard:\(line)", rawText: "",
                         detail: ["line": line, "turn": currentTurn, "mode": "off_field_evidence"])
        }
    }
    if line.hasPrefix("|-item|"), itemLineImplausible(line) {
        debugCapture(kind: "item_guard", key: "item_guard:\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    // 本体と同一: ターン行の構造ガード
    if logStarted && !winLogged {
        if line.hasPrefix("|turn|") {
            movesSinceTurnLine = []
            roundEventSeen = false
            enteredThisSegment = []
        } else if line.hasPrefix("|switch|") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 3 {
                enteredThisSegment.insert(f[2].split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            }
        } else if isRoundEventLine(line) {
            let mover: String? = line.hasPrefix("|move|")
                ? line.split(separator: "|", omittingEmptySubsequences: false).map(String.init).dropFirst(2).first?.trimmingCharacters(in: .whitespaces)
                : nil
            var guardN: Int? = nil
            let ruleC = mover.map { mv in
                currentTurn >= 1 && !movesSinceTurnLine.isEmpty && !movesSinceTurnLine.contains(mv)
                    && enteredThisSegment.contains(mv.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            } ?? false
            if currentTurn == 0 && mover != nil { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if ruleC { guardN = currentTurn + 1 }
            if let n = guardN {
                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                var pulledProtoHead: [String] = []
                var pulledDisplayHead: [String] = []
                if ruleC, let mover {
                    let pb = pullBackSwitchBlock(label: mover, splitMega: true)
                    pulledProto = pb.proto
                    pulledDisplay = pb.display
                    pulledProtoHead = pb.protoHead
                    pulledDisplayHead = pb.displayHead
                }
                let oldTurnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") })
                let oldTurnIdxD = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") })
                debugCapture(kind: "turn_guard", key: "turn_guard:\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild, "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\(n)")
                if !pulledProtoHead.isEmpty, let ti = oldTurnIdx {
                    battleLog.insert(contentsOf: pulledProtoHead, at: ti + 1)
                }
                if !pulledDisplayHead.isEmpty, let ti = oldTurnIdxD {
                    displayLog.insert(contentsOf: pulledDisplayHead, at: ti + 1)
                }
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
            }
            roundEventSeen = true
            lastRoundEventAt = Date()
            if let mover { movesSinceTurnLine.insert(mover) }
        }
    }
    if applyNow {
        if line.hasPrefix("|move|") || line.hasPrefix("|turn|") { actionSeq += 1 }
        applyEvent(line)
    }
    if line.hasPrefix("|switch|") {
        let sf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if sf.count >= 4 {
            let sside = sf[2].hasPrefix("p2") ? "p2" : "p1"
            emittedSwitchKeys.insert("\(sside):\(sf[3].trimmingCharacters(in: .whitespaces))")
        }
    }
    // ひんし直前の端数 HP 表記の書き換え (本体 emitLog と同一ロジック)
    if line.hasPrefix("|faint|") {
        let ff = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if ff.count >= 3 {
            let label = ff[2]
            for i in battleLog.indices.reversed() {
                let bl = battleLog[i]
                if bl.hasPrefix("|switch|") && bl.contains("|\(label)|") { break }
                if bl.hasPrefix("|-damage|\(label)|") {
                    let parts = bl.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    if parts.count >= 4 {
                        let hp = parts[3].split(separator: "/")
                        if hp.count == 2, let cur = Int(hp[0].trimmingCharacters(in: .whitespaces)),
                           let maxHp = Int(hp[1].trimmingCharacters(in: .whitespaces)),
                           cur > 0, maxHp > 0, Int((Double(cur) / Double(maxHp) * 100).rounded()) == 0 {
                            battleLog[i] = "|-damage|\(label)|0/\(maxHp)" + (parts.count >= 5 ? "|\(parts[4])" : "")
                        }
                    }
                    break
                }
            }
        }
    }
    // 並びの訂正 (本体 emitLog と同一ロジック)
    var insertAt: Int? = nil
    var dmgReorderMoveLabel: String? = nil
    if line.hasPrefix("|-crit|") {
        let cf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if cf.count >= 3 {
            let label = cf[2]
            var i = battleLog.count - 1
            while i >= 0 && battleLog.count - i <= 40 {
                let bl = battleLog[i]
                if bl.hasPrefix("|turn|") || bl.hasPrefix("|move|") || bl.hasPrefix("|switch|") { break }
                if bl == "|faint|\(label)" { insertAt = i; break }
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
                if bl.hasPrefix("|switch|") && bl.contains("|\(label)|") { break }
                i -= 1
            }
        }
    } else if line.hasPrefix("|-damage|") {
        // 技の自己ランク低下 (アーマーキャノンの防御低下等) は文の翻訳で
        // 即時に出る一方、被ダメ行はプレート確定まで保留されるため、
        // 順序が逆転することがある。直前の技行の直後に、その使用者自身の
        // ランク変化行 (と同技の他の被ダメ行) だけが並んでいる場合は、
        // 被ダメ行をランク変化より前に戻す (実例: 2026-11-22
        // battle_20261122_103530 ターン2、アーマーキャノンの防御低下行が
        // 被ダメ行より前に置かれた)
        let df = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if df.count >= 3 {
            let dmgLabel = df[2]
            var i = battleLog.count - 1
            var firstBoostIdx: Int? = nil
            var boostLabels: [String] = []
            while i >= 0 && battleLog.count - i <= 12 {
                let bl = battleLog[i]
                let bf = bl.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                if (bl.hasPrefix("|-boost|") || bl.hasPrefix("|-unboost|")), bf.count >= 3 {
                    firstBoostIdx = i
                    boostLabels.append(bf[2])
                    i -= 1
                    continue
                }
                if bl.hasPrefix("|-damage|") || bl.hasPrefix("|-heal|") { i -= 1; continue }
                if bl.hasPrefix("|move|"), bf.count >= 4, let fb = firstBoostIdx,
                   bf[2] != dmgLabel, bf[2] == lastMoveLabel, bf[3] == lastMoveName,
                   boostLabels.allSatisfy({ $0 == bf[2] }) {
                    insertAt = fb
                    dmgReorderMoveLabel = bf[2]
                }
                break
            }
        }
    }
    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }
    // 入場バッチ ('ab' イベント) の記録は本体 emitLog と同一ロジックを再現する
    if line.hasPrefix("|switch|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3 {
            if !entryBatchOpen { entryBatchId += 1; entryBatchMembers = []; entryBatchAbBuffer = []; entryBatchOpen = true }
            entryBatchMembers.insert(f[2])
        }
    } else if line.hasPrefix("|-ability|") {
        if entryBatchOpen {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 4 { entryBatchAbBuffer.append((label: f[2], ability: f[3])) }
        }
    }
    if (line.hasPrefix("|turn|") || line.hasPrefix("|move|")) && entryBatchOpen {
        for ab in entryBatchAbBuffer where entryBatchMembers.contains(ab.label) {
            if battleEvents.count < 600 {
                battleEvents.append("{\"k\":\"ab\",\"turn\":\(currentTurn),\"label\":\"\(jsonEscape(ab.label))\",\"ability\":\"\(jsonEscape(ab.ability))\",\"batch\":\(entryBatchId)}")
            }
        }
        entryBatchOpen = false
        entryBatchMembers = []
        entryBatchAbBuffer = []
    }
    // 設置・解除の保留確定 (本体 emitLog 末尾と同一ロジックを再現する)
    if line.hasPrefix("|turn|") { pendingHazard = nil; pendingRemoval = nil }
    if line.hasPrefix("|-damage|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3 {
            let dmgSide = f[2].hasPrefix("p1") ? "p1" : "p2"
            if let ph = pendingHazard, dmgSide == ph.side {
                pendingHazard = nil
                emitHazard(ph.side, ph.hazard, start: true)
            }
            if let pr = pendingRemoval, dmgSide != pr.side {
                pendingRemoval = nil
                clearSideHazards(pr.side)
            }
        }
    }
    // 本体と同一: 特性判明によるフォルム訂正 (相手側のみ)
    if line.hasPrefix("|-ability|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4 {
            let lp = f[2].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if lp.count == 2 && lp[0].hasPrefix("p2") {
                correctFormeByAbility(side: "p2", slot: lp[0], speciesEn: lp[1],
                                      abilityEn: f[3].trimmingCharacters(in: .whitespaces))
            }
        }
    }
    if line.hasPrefix("|-ability|") { annotateFieldLineFromAbility(line) }
}
func updateOppTeam() {}   // 相手チームの蓄積は検証対象外のためスタブ
func startBattleLog() {
    // 本体の開始処理の最小再現: 前試合のログを閉じ、ヘッダーから新しい
    // ログを始める (状態のリセットは各テストの resetAll が担う)
    winLogged = false
    battleLog = []
    emitLog("|gametype|doubles")
    syncMineProvisional()
    let mineHeaderSpecies = mineProvisionalSpecies()
    if !mineHeaderSpecies.isEmpty {
        for sp in mineHeaderSpecies { emitLog("|poke|p1|\(sp)") }
        headerMineTeam = mineHeaderSpecies
    } else {
        for sp in teamOrder { emitLog("|poke|p1|\(sp)") }
        headerMineTeam = teamOrder
    }
    for sp in oppTeamSeen { emitLog("|poke|p2|\(sp)") }
    headerOppTeam = oppTeamSeen
    emitLog("|start")
    logStarted = true
}
func archiveCurrentBattle(final: Bool) {}   // ログアーカイブは検証対象外のためスタブ
var debugCaptureCalls: [String] = []
func debugCapture(kind: String, key: String, rawText: String, detail: [String: Any]) { debugCaptureCalls.append(kind) }   // デバッグ撮影は検証対象外のためスタブ (判定ロジック debugShouldCapture は T84 で検証)。発火した種別だけ記録する
func recordObservation(pass: String, region: [Double], boxes: [(text: String, x0: Double, y0: Double, x1: Double, y1: Double, conf: Double)]) {}   // 生観測の記録は検証対象外のためスタブ (フェーズ5 の recordDecode が呼ぶ)

let stateTopKeys: Set<String> = ["mine", "opps", "oppTeam", "oppRevealed", "oppTrainer", "events", "field", "sideConditions", "hazards", "oppReset", "oppPreview", "battle", "minePreview", "mineTeam", "battlePhase", "flagMode"]
let stateMonKeys: Set<String> = ["species", "curHPPercent", "status", "unburden", "itemLost", "mega", "megaSpecies", "boosts", "revealed"]
let stateBoostKeys: [String] = ["atk", "def", "spa", "spd", "spe", "acc", "eva"]  // boosts は常時この7能力をそろえて出す
let stateRevealedKeys: Set<String> = ["moves", "item", "ability"]
let stateFieldKeys: Set<String> = ["terrain", "weather", "terrainTurnsLeft", "weatherTurnsLeft", "trickRoomTurnsLeft"]
let sideCondDurations: [String: Int] = ["Reflect": 5, "Light Screen": 5, "Aurora Veil": 5, "Tailwind": 4, "Mist": 5, "Safeguard": 5, "Wide Guard": 1]
let fieldDurations = 5  // 天気・フィールド・トリックルームの基本継続ターン (岩・粘土等の延長は画面から知りえないため数えない)
let weatherUiByLogName: [String: String] = ["Rain Dance": "Rain", "Sunny Day": "Sun", "Sandstorm": "Sand", "Snow": "Snow"]
let hazardCaps: [String: Int] = ["Stealth Rock": 1, "Spikes": 3, "Toxic Spikes": 2, "Sticky Web": 1]

func normalize(_ s: String) -> String {
    // ひらがな→カタカナ, 全角英数字→半角, 空白・中点・記号を除去
    // (OCR は「１０まんボルト」「ＤＤラリアット」のように全角で返すことがある)
    var out = ""
    for ch in s {
        if ch == " " || ch == "　" || ch == "・" { continue }
        if let v = ch.unicodeScalars.first,
           (0xFF10...0xFF19).contains(v.value) || (0xFF21...0xFF3A).contains(v.value) || (0xFF41...0xFF5A).contains(v.value),
           let half = UnicodeScalar(v.value - 0xFEE0) {
            out.append(Character(half))
        } else if let v = ch.unicodeScalars.first, (0x3041...0x3096).contains(v.value),
           let kata = UnicodeScalar(v.value + 0x60) {
            out.append(Character(kata))
        } else if ch.isLetter || ch.isNumber {
            out.append(ch)
        }
    }
    return out
}

func foldDakuten(_ s: String) -> String {
    let map: [Character: Character] = ["ガ": "カ", "ギ": "キ", "グ": "ク", "ゲ": "ケ", "ゴ": "コ",
        "ザ": "サ", "ジ": "シ", "ズ": "ス", "ゼ": "セ", "ゾ": "ソ",
        "ダ": "タ", "ヂ": "チ", "ヅ": "ツ", "デ": "テ", "ド": "ト",
        "バ": "ハ", "ビ": "ヒ", "ブ": "フ", "ベ": "ヘ", "ボ": "ホ",
        "パ": "ハ", "ピ": "ヒ", "プ": "フ", "ペ": "ヘ", "ポ": "ホ",
        "が": "か", "ぎ": "き", "ぐ": "く", "げ": "け", "ご": "こ",
        "ざ": "さ", "じ": "し", "ず": "す", "ぜ": "せ", "ぞ": "そ",
        "だ": "た", "ぢ": "ち", "づ": "つ", "で": "て", "ど": "と",
        "ば": "は", "び": "ひ", "ぶ": "ふ", "べ": "へ", "ぼ": "ほ",
        "ぱ": "は", "ぴ": "ひ", "ぷ": "ふ", "ぺ": "へ", "ぽ": "ほ"]
    return String(s.map { map[$0] ?? $0 })
}

func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = [Int](0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

func findSpeciesJa(in text: String) -> SpeciesEntry? {
    let t = normalize(text)
    var best: SpeciesEntry? = nil
    for e in speciesDict where !e.ja.isEmpty {
        if t.contains(normalize(e.ja)) && (best == nil || e.ja.count > best!.ja.count) { best = e }
    }
    // 「メガ」が「メカ」に崩れると基本フォルムに落ちて状態の記録先キーが
    // ずれるため、メカ→メガに直した文でも照合する (検証 R1 #83 で検出)
    let exactBest = best
    if t.contains("メカ") {
        let t2 = t.replacingOccurrences(of: "メカ", with: "メガ")
        for e in speciesDict where !e.ja.isEmpty {
            if t2.contains(normalize(e.ja)) && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
        if exactBest == nil, let b = best { recordDecode(stage: "meka", raw: text, resolved: b.en) }
    }
    // 濁点ゆれで名前が崩れた場合 (サーナイト→ザーナイト、ドラパルト→
    // ドラパルド等) は、両辺の濁点を畳んだ形でも照合する。通常照合で
    // 何も見つからなかった場合だけ使う (検証 R2 で検出)
    if best == nil {
        let ft = foldDakuten(t)
        for e in speciesDict where !e.ja.isEmpty {
            if ft.contains(foldDakuten(normalize(e.ja))) && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
        if let b = best { recordDecode(stage: "fold", raw: text, resolved: b.en) }
    }
    // さらに「ー」落ちまで重なった場合 (サーナイト→ザナイト) は、長音も
    // 落として照合する。カラカラ/ガラガラ のような衝突があるため、場か
    // チームで裏付けが取れた候補だけを採る (検証 R2 で検出)。
    // ッ→ツも畳む (イエッサン→イエツザン の二重ゆれ対策、検証 hard R7)。
    // この変換 (畳み+ッ→ツ+長音落ち) の衝突は全件フォルム違いのみで
    // あることを辞書全件で確認済み
    if best == nil {
        let tsuFold: (String) -> String = { $0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ") }
        let ft = tsuFold(foldDakuten(t)).replacingOccurrences(of: "ー", with: "")
        for e in speciesDict where !e.ja.isEmpty {
            let nk = tsuFold(foldDakuten(normalize(e.ja))).replacingOccurrences(of: "ー", with: "")
            guard ft.contains(nk) else { continue }
            let anch = fieldAnchoredSpecies(e)
            let backed = lastSlots.values.contains { $0.speciesEn == anch.en }
                || teamEntries[anch.en] != nil || oppTeamSeen.contains(anch.en)
            if backed && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
        if let b = best { recordDecode(stage: "tsu", raw: text, resolved: b.en) }
    }
    // 字形混同 (ミロカロス→三ロカロス のようにカタカナが似た漢字に
    // 化ける) は上の全段で拾えないため、同長で最大 2 文字だけ食い違い、
    // その位置がカタカナと漢字の混同である場合に限る照合を最終段と
    // して置く (復号段の第6段: glyph)。カタカナ同士の置換まで広げる
    // と、緩い照合でしか解けない崩れ名で場の登録まで進んでしまう
    // (ハーネス T89c の否定条件)。tsu 段と同じく、場かチームで
    // 裏付けが取れた候補だけを採る
    if best == nil {
        let tArr = Array(t)
        func isKana(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { (0x30A0...0x30FF).contains($0.value) || (0x3040...0x309F).contains($0.value) }
        }
        func isKanji(_ c: Character) -> Bool {
            c.unicodeScalars.allSatisfy { (0x4E00...0x9FFF).contains($0.value) }
        }
        for e in speciesDict where !e.ja.isEmpty {
            let nArr = Array(normalize(e.ja))
            if nArr.count < 4 || tArr.count < nArr.count { continue }
            var hit = false
            outer: for start in 0...(tArr.count - nArr.count) {
                var diffs = 0
                for k in 0..<nArr.count {
                    let a = tArr[start + k], b = nArr[k]
                    if a == b { continue }
                    diffs += 1
                    if diffs > 2 { break }
                    if !((isKana(a) && isKanji(b)) || (isKanji(a) && isKana(b))) { diffs = 3; break }
                }
                if diffs == 1 || diffs == 2 { hit = true; break outer }
            }
            guard hit else { continue }
            let anch = fieldAnchoredSpecies(e)
            let backed = lastSlots.values.contains { $0.speciesEn == anch.en }
                || teamEntries[anch.en] != nil || oppTeamSeen.contains(anch.en)
            if backed && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
        if let b = best { recordDecode(stage: "glyph", raw: text, resolved: b.en) }
    }
    return best
}

func findAllSpeciesJa(in text: String) -> [SpeciesEntry] {
    let t = normalize(text)
    func scan(_ s: String, _ normOf: (SpeciesEntry) -> String) -> [SpeciesEntry] {
        var covered: [Range<String.Index>] = []
        var found: [(Range<String.Index>, SpeciesEntry)] = []
        for e in speciesDict.filter({ !$0.ja.isEmpty }).sorted(by: { $0.ja.count > $1.ja.count }) {
            let nj = normOf(e)
            var start = s.startIndex
            while start < s.endIndex, let r = s.range(of: nj, range: start..<s.endIndex) {
                if !covered.contains(where: { $0.lowerBound < r.upperBound && r.lowerBound < $0.upperBound }) {
                    found.append((r, e))
                    covered.append(r)
                }
                start = r.upperBound
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { $0.1 }
    }
    let exact = scan(t) { normalize($0.ja) }
    if !exact.isEmpty { return exact }
    // 濁点ゆれで全滅した場合だけ、両辺を畳んだ形で再照合する (検証 R2)。
    // foldDakuten は 1 文字→1 文字の置換なので範囲の位置は変わらない
    return scan(foldDakuten(t)) { foldDakuten(normalize($0.ja)) }
}

func findSpeciesJaLoose(in text: String) -> (entry: SpeciesEntry, moveStart: Int)? {
    let chars = Array(normalize(text))
    if chars.count < 3 { return nil }
    let particles: Set<Character> = ["ノ", "ハ", "ニ", "ガ", "ヲ"]
    var textBigrams = Set<String>()
    var textChars = Set<Character>()
    for i in 0..<chars.count {
        textChars.insert(chars[i])
        if i + 1 < chars.count { textBigrams.insert(String([chars[i], chars[i + 1]])) }
    }
    var best: (entry: SpeciesEntry, dist: Int, len: Int, moveStart: Int)? = nil
    for e in speciesDict where !e.ja.isEmpty {
        let ja = Array(normalize(e.ja))
        let L = ja.count
        if L < 3 || L > chars.count { continue }
        if L >= 4 {
            var shares = false
            for i in 0..<(L - 1) where textBigrams.contains(String([ja[i], ja[i + 1]])) { shares = true; break }
            if !shares { continue }
        } else if ja.filter({ textChars.contains($0) }).count < 2 { continue }
        let maxDist = L <= 5 ? 1 : 2
        for start in 0..<chars.count {
            for wlen in [L - 1, L, L + 1] where wlen >= 2 && start + wlen <= chars.count {
                let after = start + wlen
                if after < chars.count && !particles.contains(chars[after]) { continue }
                let d = editDistance(Array(chars[start..<(start + wlen)]), ja)
                if d <= maxDist && (best == nil || d < best!.dist || (d == best!.dist && L > best!.len)) {
                    best = (e, d, L, after + 1)
                }
            }
        }
    }
    guard let b = best else { return nil }
    return (b.entry, b.moveStart)
}

func moveNameLoose(_ cand: String) -> String? {
    guard cand.count >= 3 else { return nil }
    let maxDist = cand.count <= 5 ? 1 : 2
    let ca = Array(cand)
    var bestKey: String? = nil
    var bestDist = Int.max
    var tie = false
    for key in moveNameOrig.keys {
        if abs(key.count - cand.count) > maxDist { continue }
        let d = levenshtein(Array(key), ca)
        if d > maxDist { continue }
        if d < bestDist { bestDist = d; bestKey = key; tie = false }
        else if d == bestDist { tie = true }
    }
    if let bk = bestKey, !tie { return moveNameOrig[bk] }
    // 第2パス: 濁点を畳んだ形同士の編集距離 (シザグロス→シザークロスのように
    // 長音落ち+濁点ゆれが重なると素の距離では届かない。検証 hard R7 #24)。
    // 技名は畳んでも全件衝突しないことを辞書で確認済み。同点は従来通り棄却
    let fc = Array(foldDakuten(cand))
    var fBestKey: String? = nil
    var fBestDist = Int.max
    var fTie = false
    for key in moveNameOrig.keys {
        let fk = foldDakuten(key)
        if abs(fk.count - fc.count) > maxDist { continue }
        let d = levenshtein(Array(fk), fc)
        if d > maxDist { continue }
        if d < fBestDist { fBestDist = d; fBestKey = key; fTie = false }
        else if d == fBestDist { fTie = true }
    }
    if let bk = fBestKey, !fTie { return moveNameOrig[bk] }
    // 第3パス: 長音も落として畳んだ形で照合する (ワンダルム→ワンダールーム
    // のような長音2連落ち対策。検証 最終監査 seed31 #54)。この変換でも
    // 技名は全件衝突しないことを辞書で確認済み。距離は 1 までに絞る
    let stripLong: (String) -> String = { $0.replacingOccurrences(of: "ー", with: "") }
    let dc = Array(stripLong(foldDakuten(cand)))
    var dBestKey: String? = nil
    var dBestDist = Int.max
    var dTie = false
    for key in moveNameOrig.keys {
        let dk = stripLong(foldDakuten(key))
        if abs(dk.count - dc.count) > 1 { continue }
        let d = levenshtein(Array(dk), dc)
        if d > 1 { continue }
        if d < dBestDist { dBestDist = d; dBestKey = key; dTie = false }
        else if d == dBestDist { dTie = true }
    }
    guard let bk = dBestKey, !dTie else { return nil }
    return moveNameOrig[bk]
}

func findInDict(in text: String, _ dict: [String: String]) -> String? {
    let t = normalize(text)
    var best: String? = nil
    for (norm, orig) in dict {
        if !norm.isEmpty && t.contains(norm) && (best == nil || orig.count > best!.count) { best = orig }
    }
    return best
}

func looseText(_ s: String) -> String {
    let small: [Character: Character] = ["ャ": "ヤ", "ュ": "ユ", "ョ": "ヨ", "ッ": "ツ",
                                          "ァ": "ア", "ィ": "イ", "ゥ": "ウ", "ェ": "エ", "ォ": "オ",
                                          "ヮ": "ワ", "ヵ": "カ", "ヶ": "ケ"]
    let nfd = normalize(s).decomposedStringWithCanonicalMapping
    var stripped = ""
    for sc in nfd.unicodeScalars {
        if sc.value == 0x3099 || sc.value == 0x309A { continue }
        stripped.append(Character(sc))
    }
    let recomposed = stripped.precomposedStringWithCanonicalMapping
    return String(recomposed.map { small[$0] ?? $0 })
}

func parseMineHPText(_ text: String, knownMax: Int?) -> (pct: Int, cur: Int, max: Int?)? {
    func pct(_ c: Int, _ m: Int) -> Int { max(0, min(100, Int((Double(c) / Double(m) * 100).rounded()))) }
    // 1) スラッシュ形式 (全角含む)。最大が小さいものは選出画面の「0/4」等の誤認
    //    防止のため除外するが、ヌケニンの 1/1 だけは例外として通す
    let slashed = text.replacingOccurrences(of: "／", with: "/")
    if let r = slashed.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
        let parts = slashed[r].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? -1 }
        if parts.count == 2 && (parts[1] >= 10 || parts[1] == 1) && parts[0] <= parts[1] {
            return (pct(parts[0], parts[1]), parts[0], parts[1])
        }
    }
    if text.contains(":") || text.contains("：") { return nil }  // 時刻・タイマー表示は HP ではない
    if text.contains("Lv") || text.contains("レベル") { return nil }  // レベル表記 (50) を現在値と誤認しない
    // 2) 数字が連結して読まれた場合: スラッシュ消失 (連結) と
    //    スラッシュの数字化 (1文字置換) の両方で、桁数のバランスする
    //    分割 (現在値/最大値) を探し、現在値が最大の候補を採る
    let digits = asciiDigits(text).filter { $0.isNumber && $0.isASCII }
    let rest = asciiDigits(text).filter { !($0.isNumber && $0.isASCII) && !$0.isWhitespace }
    if rest.isEmpty && (4...7).contains(digits.count) {
        let arr = Array(digits)
        var bestSplit: (Int, Int)? = nil
        func consider(_ c: Int, _ m: Int) {
            guard m >= 30 && m <= 500 && c <= m else { return }
            if bestSplit == nil || c > bestSplit!.0 { bestSplit = (c, m) }
        }
        for i in 1..<arr.count where abs(i - (arr.count - i)) <= 1 {
            if let c = Int(String(arr[..<i])), let m = Int(String(arr[i...])) { consider(c, m) }
        }
        for i in 1..<(arr.count - 1) where abs(i - (arr.count - 1 - i)) <= 1 {
            if let c = Int(String(arr[..<i])), let m = Int(String(arr[(i + 1)...])) { consider(c, m) }
        }
        if let (c, m) = bestSplit { return (pct(c, m), c, m) }
    }
    // 3) 区切りが空白・記号で読まれた数字ペア ("137 137", "137-137")
    let groups = numberGroups(text)
    if groups.count == 2 && groups[1] >= 30 && groups[0] >= 10 && groups[0] <= groups[1] && !text.contains("%") {
        return (pct(groups[0], groups[1]), groups[0], groups[1])
    }
    // 3b) スラッシュが最大値の先頭桁と融合して 1 文字に化けた場合
    // (例: "150m71" — "/1" が "m" になった読み)。ペアの後半が現在値
    // より小さい場合だけ、最大値の先頭桁を補って解釈する。既知の
    // 最大値と一致する補完を採り、既知値が無ければ成り立つ最小の
    // 補完を採る (実例: 2026-11-22 battle_20261122_071457、
    // ムクホークの 150/171 が読めず 65 秒間ヒットしなかった)
    if groups.count == 2 && groups[0] >= 10 && groups[1] >= 10 && groups[0] > groups[1] && !text.contains("%") {
        var place = 1
        for _ in 0..<String(groups[1]).count { place *= 10 }
        for p in 1...4 {
            let m = p * place + groups[1]
            if m >= groups[0] && m <= 500 && (knownMax == nil || m == knownMax) {
                return (pct(groups[0], m), groups[0], m)
            }
        }
    }
    // 4) 現在値だけ読めた場合: 判明済みの最大HP から割合を復元する
    // (1 桁の数字はカウントダウン等の UI 要素であることが多く、現在値とはみなさない。
    //  スラッシュ形式で読めた場合 (パターン 1) は 1 桁でも正規の読みとして通る)
    if groups.count == 1, let km = knownMax, km > 0, groups[0] >= 10 && groups[0] <= km {
        return (pct(groups[0], km), groups[0], km)
    }
    return nil
}

func asciiDigits(_ s: String) -> String {
    var out = ""
    for ch in s {
        if let v = ch.unicodeScalars.first, (0xFF10...0xFF19).contains(v.value),
           let a = UnicodeScalar(v.value - 0xFEE0) {
            out.append(Character(a))
        } else {
            out.append(ch)
        }
    }
    return out
}

func numberGroups(_ s: String) -> [Int] {
    var out: [Int] = []
    var cur = ""
    for ch in asciiDigits(s) {
        if ch.isNumber { cur.append(ch) }
        else if !cur.isEmpty { if let v = Int(cur) { out.append(v) }; cur = "" }
    }
    if !cur.isEmpty, let v = Int(cur) { out.append(v) }
    return out
}

func recordDecode(stage: String, raw: String, resolved: String) {
    recordObservation(pass: "decode", region: [0, 0, 0, 0],
                      boxes: [(text: stage + "|" + raw + "|" + resolved,
                               x0: 0, y0: 0, x1: 0, y1: 0, conf: 1.0)])
}

func slotId(_ plateName: String) -> String {
    switch plateName {
    case "mineA": return "p1a"
    case "mineB": return "p1b"
    case "oppA": return "p2a"
    case "oppB": return "p2b"
    default: return plateName
    }
}

func slotFor(side: String, speciesEn: String) -> String {
    for (name, s) in lastSlots where (name.hasPrefix("mine") ? "p1" : "p2") == side && s.speciesEn == speciesEn {
        return slotId(name)
    }
    return side + "a"
}

func formeGroup(_ e: SpeciesEntry) -> [SpeciesEntry] {
    func disp(_ ja: String) -> String {
        var s = ja
        while let r = s.range(of: "（[^）]*）", options: .regularExpression) { s.removeSubrange(r) }
        while let r = s.range(of: "\\([^)]*\\)", options: .regularExpression) { s.removeSubrange(r) }
        return normalize(s)
    }
    let d = disp(e.ja)
    let g = speciesDict.filter { disp($0.ja) == d }
    return g.isEmpty ? [e] : g
}

func anchoredSpecies(_ e: SpeciesEntry, mine: Bool) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count <= 1 { return e }
    let registered = mine ? grp.filter { teamEntries[$0.en] != nil } : grp.filter { oppTeamSeen.contains($0.en) }
    return registered.count == 1 ? registered[0] : e
}

func fieldAnchoredSpecies(_ e: SpeciesEntry) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count <= 1 { return e }
    for key in ["mineA", "mineB", "oppA", "oppB"] {
        if let s = lastSlots[key], let m = grp.first(where: { $0.en == s.speciesEn }) { return m }
    }
    let m = anchoredSpecies(e, mine: true)
    if m.en != e.en { return m }
    return anchoredSpecies(e, mine: false)
}

func anchoredSpeciesForText(_ e: SpeciesEntry, text: String) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count > 1 {
        let oppFirst = text.contains("相手の") || text.contains("あいての")
        let order = oppFirst ? ["oppA", "oppB", "mineA", "mineB"] : ["mineA", "mineB", "oppA", "oppB"]
        for key in order {
            if let s = lastSlots[key], let m = grp.first(where: { $0.en == s.speciesEn }) { return m }
        }
    }
    return fieldAnchoredSpecies(e)
}

func isRoundEventLine(_ line: String) -> Bool {
    for p in ["|move|", "|-damage|", "|-heal|", "|faint|", "|-status|", "|-boost|", "|-unboost|",
              "|-activate|", "|-start|", "|-end|", "|-item|", "|-enditem|", "|-sidestart|", "|-sideend|",
              "|detailschange|", "|-mega|", "|-crit|", "|-fail|"] {
        if line.hasPrefix(p) { return true }
    }
    return false
}

func healExplained(key: String, slot: String, speciesEn: String, fromPct: Int, toPct: Int,
                   knownItem: String?, abilityJa: String?) -> Bool {
    let delta = toPct - fromPct
    let selfHeal: Set<String> = ["Recover", "Soft-Boiled", "Milk Drink", "Slack Off", "Heal Order",
                                 "Roost", "Synthesis", "Morning Sun", "Moonlight", "Shore Up", "Rest",
                                 "Wish", "Strength Sap", "Life Dew", "Lunar Blessing", "Jungle Healing",
                                 "Absorb", "Mega Drain", "Giga Drain", "Drain Punch", "Leech Life",
                                 "Horn Leech", "Oblivion Wing", "Parabolic Charge", "Draining Kiss",
                                 "Dream Eater", "Bitter Blade", "Matcha Gotcha"]
    let allyHeal: Set<String> = ["Life Dew", "Heal Pulse", "Floral Healing", "Pollen Puff",
                                 "Lunar Blessing", "Jungle Healing"]
    let label = "\(slot): \(speciesEn)"
    if lastMoveLabel == label && selfHeal.contains(lastMoveName) { return true }
    if allyHeal.contains(lastMoveName) && lastMoveLabel != label
        && lastMoveLabel.hasPrefix(String(slot.prefix(2))) { return true }
    if knownItem == "たべのこし" || knownItem == "くろいヘドロ" { return true }
    let figyBerries: Set<String> = ["フィラのみ", "ウイのみ", "マゴのみ", "バンジのみ", "イアのみ"]
    if fromPct <= 34 && (30...36).contains(delta)
        && (knownItem == nil || figyBerries.contains(knownItem ?? "")) { return true }
    if abilityJa == "あめうけざら" && logFieldWeather == "Rain" { return true }
    if abilityJa == "アイスボディ" && logFieldWeather == "Snow" { return true }
    if abilityJa == "どくしゅ" {
        let st = monStates[key]?.status ?? ""
        if st == "psn" || st == "tox" { return true }
    }
    // ねがいごと: 使った次のターンの終わりに、使用側の場のポケモンが
    // 50% 回復する。受け手は使用者とは限らない (交代先の枠が受ける)
    // ため、直前の技ではなく使用ターンと側で判定する
    if (40...55).contains(delta), let wt = wishSetTurn[key.hasPrefix("p2") ? "p2" : "p1"],
       wt == currentTurn - 1 { return true }
    // 吸収特性: 相手の技を受けて回復する (みずをすいこむ等は 25%)。
    // 直前の技が相手側のもので、増分が吸収量と一致する場合のみ
    let absorb: Set<String> = ["みずをすいこむ", "ちくでん", "どしょく", "かんそうはだ"]
    if let abilityJa, absorb.contains(abilityJa), (20...30).contains(delta),
       !lastMoveLabel.isEmpty, !lastMoveLabel.hasPrefix(key.hasPrefix("p2") ? "p2" : "p1") { return true }
    // かんそうはだは雨のターン終了時にも 1/8 回復する
    if abilityJa == "かんそうはだ" && logFieldWeather == "Rain" && (9...16).contains(delta) { return true }
    return false
}

func debugStateExcerpt() -> [String: Any] {
    var slots: [String: Any] = [:]
    // HP はプレートの最新観測値ではなく、ログに確定した値を優先する。
    // 観測値には却下された誤読 (満タンの跳ね等) が混ざっており、その
    // まま写すと記録の state がログと食い違う (実例: 2026-11-21
    // battle_20261121_145658 の hp_jump_rejected 記録)
    for (k, s) in lastSlots { slots[k] = ["species": s.speciesEn, "hpPct": lastEmittedPct[k] ?? s.hpPercent] }
    return ["turn": currentTurn, "weather": logFieldWeather, "terrain": logFieldTerrain, "slots": slots]
}

func checkHeaderMismatch(slot: String, speciesEn: String) {
    guard headerOppTeam.count == 6 else { return }
    guard !headerMismatchFired.contains(speciesEn) else { return }
    let entry = speciesDict.first(where: { $0.en == speciesEn })
    let inHeader = headerOppTeam.contains { h in
        h == speciesEn || (entry != nil && formeGroup(entry!).contains { $0.en == h })
    }
    guard !inHeader else { return }
    headerMismatchFired.insert(speciesEn)
    if debugMode { print("[reader] ヘッダーと異なる相手種族がプレートで確定しました: \(speciesEn) (ヘッダー: \(headerOppTeam.joined(separator: ", ")))") }
    fflush(stdout)
    debugCapture(kind: "header_mismatch", key: "header_mismatch:\(speciesEn)", rawText: "",
                 detail: ["species": speciesEn, "header": headerOppTeam,
                          "slot": slot, "turn": currentTurn,
                          "readerBuild": readerBuild])
}

func boostSubjects(in t: String) -> [SpeciesEntry] {
    let found = findAllSpeciesJa(in: t).map { fieldAnchoredSpecies($0) }
    if found.count <= 1 { return found }
    // 最初の能力名より前が主語の領域
    let statWords = ["こうげき", "攻撃", "ぼうぎょ", "防御", "とくこう", "特攻", "とくぼう", "特防",
                     "すばやさ", "素早さ", "めいちゅう", "命中率", "かいひ", "回避率",
                     "コウゲキ", "ボウギョ", "トクコウ", "トクボウ", "スバヤサ", "メイチュウ", "カイヒ"]
    var cut = t.endIndex
    for w in statWords {
        if let r = t.range(of: w), r.lowerBound < cut { cut = r.lowerBound }
    }
    let region = normalize(String(t[..<cut]))
    let foldedRegion = foldDakuten(region)
    let inRegion = found.filter {
        region.contains(normalize($0.ja)) || foldedRegion.contains(foldDakuten(normalize($0.ja)))
    }
    // 複合主語 (「Aと Bの」) のときだけ、領域内の全員を対象にする。
    // 正規化で「と」は「ト」になるため両形を見る。種族名の一部
    // (ドラパルトの「ト」等) と誤認しないよう、2 つの名前の間に
    // 助詞がある場合だけ複合とみなす
    if inRegion.count >= 2 {
        var compound = false
        for i in 0..<(inRegion.count - 1) {
            let a = normalize(inRegion[i].ja), b = normalize(inRegion[i + 1].ja)
            guard let ra = region.range(of: a),
                  let rb = region.range(of: b, range: ra.upperBound..<region.endIndex) else { continue }
            let between = region[ra.upperBound..<rb.lowerBound]
            if between.contains("と") || between.contains("ト") { compound = true }
        }
        if compound { return inRegion }
    }
    // 単独主語: 主語領域に現れる最後の種族だけが文法上の主語
    if let last = inRegion.last { return [last] }
    return found
}

func emitAbilityOnce(slot: String, side: String, speciesEn: String, abilityEn: String) {
    let k = "\(side):\(speciesEn):\(abilityEn)"
    if let at = lastAbilityEmit[k], sNow().timeIntervalSince(at) < 10 { return }
    lastAbilityEmit[k] = sNow()
    emitLog("|-ability|\(slot): \(speciesEn)|\(abilityEn)")
}

func emitItemOnce(slot: String, side: String, speciesEn: String, itemJa: String) {
    let k = "\(side):\(speciesEn):\(itemJa)"
    if let at = lastItemEmit[k], sNow().timeIntervalSince(at) < 25 { return }
    lastItemEmit[k] = sNow()
    emitLog("|-item|\(slot): \(speciesEn)|\(itemJa2En[itemJa] ?? itemJa)")
}

func correctFormeByAbility(side: String, slot: String, speciesEn: String, abilityEn: String) {
    guard side == "p2" else { return }
    // 現在のフォルムでも持ち得る特性なら訂正しない
    if (speciesAbilityMap[speciesEn] ?? []).contains(abilityEn) { return }
    guard let entry = speciesDict.first(where: { $0.en == speciesEn }) else { return }
    let cands = formeGroup(entry).filter { $0.en != speciesEn && (speciesAbilityMap[$0.en] ?? []).contains(abilityEn) }
    guard cands.count == 1, let newEn = cands.first?.en else { return }
    for name in ["oppA", "oppB"] where lastSlots[name]?.speciesEn == speciesEn {
        lastSlots[name]?.speciesEn = newEn
    }
    let oldKey = "\(side):\(speciesEn)", newKey = "\(side):\(newEn)"
    if let st = monStates[oldKey] {
        if monStates[newKey] == nil { monStates[newKey] = st }
        monStates[oldKey] = nil
    }
    oppTeamSeen = oppTeamSeen.map { $0 == speciesEn ? newEn : $0 }
    if oppUnconfirmed.contains(speciesEn) { oppUnconfirmed.remove(speciesEn); oppUnconfirmed.insert(newEn) }
    if fieldSeen[side]?.contains(speciesEn) == true { fieldSeen[side]?.remove(speciesEn); fieldSeen[side]?.insert(newEn) }
    if let sw = lastSwitchIn[oldKey] { lastSwitchIn[newKey] = sw; lastSwitchIn[oldKey] = nil }
    if let ab = revealedAbilities[speciesEn] { revealedAbilities[newEn] = ab; revealedAbilities[speciesEn] = nil }
    if emittedSwitchKeys.contains("\(side):\(speciesEn)") {
        emittedSwitchKeys.remove("\(side):\(speciesEn)")
        emittedSwitchKeys.insert("\(side):\(newEn)")
    }
    renderSlotSpecies[slot] = newEn
    for i in battleLog.indices {
        let f = battleLog[i].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3 else { continue }
        if battleLog[i].hasPrefix("|poke|p2|") && f[3] == speciesEn {
            var nf = f; nf[3] = newEn
            battleLog[i] = nf.joined(separator: "|")
        } else if f[2] == "\(slot): \(speciesEn)" {
            var nf = f; nf[2] = "\(slot): \(newEn)"
            if battleLog[i].hasPrefix("|switch|") && nf.count >= 4 { nf[3] = newEn }
            battleLog[i] = nf.joined(separator: "|")
        }
    }
    for i in displayLog.indices {
        if displayLog[i].contains("opposing \(speciesEn)") || displayLog[i].contains("sent out \(speciesEn)") || displayLog[i].contains("withdrew \(speciesEn)") {
            displayLog[i] = displayLog[i].replacingOccurrences(of: speciesEn, with: newEn)
        }
    }
    try? (battleLog.joined(separator: "\n") + "\n").write(to: protocolLogURL, atomically: true, encoding: .utf8)
    try? (displayLog.joined(separator: "\n") + "\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
    if debugMode { print("[reader] 特性 \(abilityEn) の判明によりフォルムを訂正しました: \(speciesEn) -> \(newEn)") }
    fflush(stdout)
}

func attributeIntimidate(targetSide: String) {
    let other = targetSide == "p1" ? "p2" : "p1"
    let now = sNow()
    for (key, sw) in lastSwitchIn where key.hasPrefix("\(other):") {
        if intimidateDone[key] == sw.at { continue }
        guard now.timeIntervalSince(sw.at) < 8 else { continue }
        guard lastMoveMsgAt < sw.at else { continue }   // 繰り出し後に技が使われていたら、その技の効果とみなす
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let en = String(parts[1])
        guard let pool = speciesAbilityMap[en], pool.contains("Intimidate") else { continue }
        intimidateDone[key] = sw.at
        emitAbilityOnce(slot: sw.slot, side: other, speciesEn: en, abilityEn: "Intimidate")  // 判明登録は applyEvent が行う
    }
}

func attributeFieldAbilities() {
    let weatherAb: [String: String] = ["Sun": "Drought", "Rain": "Drizzle", "Sand": "Sand Stream", "Snow": "Snow Warning"]
    let terrainAb: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    let allField: Set<String> = Set(weatherAb.values).union(terrainAb.values)
    let now = sNow()
    for (key, sw) in lastSwitchIn {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        guard let pool = speciesAbilityMap[en] else { continue }
        let fieldOnes = pool.filter { allField.contains($0) }
        guard fieldOnes.count == 1, let ab = fieldOnes.first else { continue }
        var matched = false
        // 窓は 30 秒: フィールド文 (即時) とプレート確定 (2 フレーム+演出の
        // バックログ) の間隔が 12 秒を超えることがある (実例: 2026-11-20、
        // イエッサンのサイコメイカー括弧行が落ちた)
        if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        // ターン一致: 交代の確定が大きく遅れると 30 秒の窓を超える
        // (実例: 2026-11-21 battle_20261121_230402、イエッサン♀の
        // 確定が地形開始から約 41 秒遅れ、サイコメイカーが付かなかった)。
        // フィールドを張ったのと同じターンに入った交代は、その入場が
        // 原因とみなす。ただし、そのフィールドが技で張られたターン
        // は除く (技の使用者が原因のため)
        let inTurn = switchInTurn[key].map { max($0, 1) }   // trackFieldEvent の eff (max(currentTurn, 1)) に合わせる
        if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
        if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
        // 開始直後の上書き: 先発は最初のターン行より前に場に出ており、
        // その入場で張った天候・地形が、相手の先発の特性で即座に
        // 上書きされることがある (実例: 2026-11-21 battle_20261121_233243、
        // ゴリランダーのグラスフィールドがサイコフィールドに上書き
        // され、グラスメイカーが付かなかった)。先発 (ターン 0 で記録)
        // に限り、上書きされた側に対しても帰属する
        if switchInTurn[key] == 0 {
            if weatherAb[prevFieldWeather] == ab && fieldSetByMoveTurn != prevFieldWeatherSetTurn { matched = true }
            if terrainAb[prevFieldTerrain] == ab && fieldSetByMoveTurn != prevFieldTerrainSetTurn { matched = true }
        }
        if matched {
            fieldAbilityDone[key] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: en, abilityEn: ab)
        }
    }
    // メガフォルム側のフィールド特性: ベース種族のプールには含まれない
    // (リザードンの ひでり は メガリザードンY 側)。完了済み・保留中の
    // メガフォルムの特性で現在の天候・地形と一致するものがあれば、
    // その特性行をメガフォルム名で出す (完了が保留中なら先に補う)
    for (key, sw) in lastSwitchIn {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        let forme = monStates[key]?.megaSpecies ?? pendingMegaForme(side: side, baseEn: en)
        guard let forme, forme != en, let mpool = speciesAbilityMap[forme] else { continue }
        let mfield = mpool.filter { allField.contains($0) }
        guard mfield.count == 1, let ab = mfield.first else { continue }
        var matched = false
        if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        let inTurn = switchInTurn[key].map { max($0, 1) }
        if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
        if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
        if switchInTurn[key] == 0 {
            if weatherAb[prevFieldWeather] == ab && fieldSetByMoveTurn != prevFieldWeatherSetTurn { matched = true }
            if terrainAb[prevFieldTerrain] == ab && fieldSetByMoveTurn != prevFieldTerrainSetTurn { matched = true }
        }
        if matched {
            fieldAbilityDone[key] = sw.at
            if pendingMegaSpecies[side] == en { completeMega(side: side, baseEn: en, megaEn: forme) }
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: forme, abilityEn: ab)
        }
    }
    // 別フォルム側のフィールド特性: 現在の天候・地形が、場の誰の現在の
    // フォルムでも説明できず、交代で入った相手の同種族の別フォルム
    // (リージョンフォルム等) の特性でだけ説明できる場合は、フォルムの
    // 登録自体が誤りとみて訂正した上で帰属する (プレート同定は同名
    // フォルムを区別できず、見せ合い側でも通常種として登録される
    // ことがある。実例: 2026-11-22 battle_20261122_070237、キュウコン
    // (アローラ) が通常種で登録され、ゆきふらし が帰属しなかった)
    for (key, sw) in Array(lastSwitchIn) {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        guard side == "p2" else { continue }
        for ab in [weatherAb[logFieldWeather], terrainAb[logFieldTerrain]].compactMap({ $0 }) {
            // 場の誰かの現在のフォルムで説明できるなら、その個体が原因
            if lastSlots.values.contains(where: { (speciesAbilityMap[$0.speciesEn] ?? []).contains(ab) }) { continue }
            // 自分の現在のフォルムで持てるなら通常の帰属が担当する
            if (speciesAbilityMap[en] ?? []).contains(ab) { continue }
            guard let entry = speciesDict.first(where: { $0.en == en }) else { continue }
            let cands = formeGroup(entry).filter { $0.en != en && (speciesAbilityMap[$0.en] ?? []).contains(ab) }
            guard cands.count == 1, let newEn = cands.first?.en else { continue }
            var matched = false
            if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            let inTurn = switchInTurn[key].map { max($0, 1) }
            if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
            if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
            guard matched else { continue }
            correctFormeByAbility(side: side, slot: sw.slot, speciesEn: en, abilityEn: ab)
            fieldAbilityDone["\(side):\(newEn)"] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: newEn, abilityEn: ab)
        }
    }
}

func setWeather(_ ui: String, _ logName: String, via text: String = "", stale: Bool = false) {
    if logFieldWeather == ui { return }
    // ログ画面経由の古い開始文は、実況で追えている現行の天候を上書きしない
    // (地形側と同じ再適用の穴。現行が空のときの復旧は従来どおり行う)
    if stale && !logFieldWeather.isEmpty {
        if debugMode { print("[field] ログ画面の古い天候文を採用しませんでした: \(ui) (現在: \(logFieldWeather))") }
        debugCapture(kind: "weather_change", key: "weather_change_blocked:\(ui)", rawText: text,
                     detail: ["from": logFieldWeather, "to": ui, "turn": currentTurn, "blocked": true])
        return
    }
    // 交代の確定 (プレート 2 フレーム) がまだの間に開始文だけが先に
    // 届くと、開始行が交代行より前に出てしまう (実例: 2026-11-21
    // battle_20261121_230402、ペリッパーの あめふらし の雨開始行が
    // 繰り出し行より前に出た)。交代確定待ちがある間は開始文を保留し、
    // プレート処理の末尾で流す (最大 2.5 秒で強制的に流す)
    // ターン0 で出所の特性を持つ個体が場にいない開始も保留する
    // (交代の確定前に開始文だけが先行するケース。setTerrain と同じ)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()
        || (currentTurn == 0 && !lastSlots.isEmpty && logFieldWeather.isEmpty && !fieldSourceOnField(ui))) {
        if heldWeatherStart?.ui != ui {
            heldWeatherStart = (ui: ui, logName: logName, text: text, at: sNow())
        }
        return
    }
    let prev = logFieldWeather
    fieldWeatherSetAt = sNow()
    // この天候が保留中のメガのフィールド特性によるものなら、
    // 天候行より先にメガ完了を補う (順序の保持)
    let weatherAbility: [String: String] = ["Sun": "Drought", "Rain": "Drizzle", "Sand": "Sand Stream", "Snow": "Snow Warning"]
    if let ab = weatherAbility[ui] { completePendingMegaForField(ability: ab) }
    emitLog("|-weather|\(logName)")  // 状態への反映は applyEvent が行う
    attributeFieldAbilities()
    // 天候の変化は根拠テキストごと残す (変化の経路を後から特定できるように)
    if !text.isEmpty {
        debugCapture(kind: "weather_change", key: "weather_change:\(currentTurn):\(ui)", rawText: text,
                     detail: ["from": prev, "to": ui, "turn": currentTurn])
    }
}

func clearWeather(stale: Bool = false) {
    if logFieldWeather.isEmpty { return }
    if stale {
        if debugMode { print("[field] ログ画面の古い天候終了文で現行の天候を消しませんでした: \(logFieldWeather)") }
        return
    }
    emitLog("|-weather|none")
}

func setTerrain(_ ui: String, via text: String = "", stale: Bool = false) {
    if logFieldTerrain == ui { return }
    // ログ画面経由の古い開始文は、実況で追えている現行の地形を上書きしない
    // (実例: 2026-11-21 battle_20261121_161334、対戦開始時のサイコフィールドの
    //  文がターン2終了時に再適用され、グラスフィールド下でサイコシードの
    //  消費まで補完された。現行が空のときの復旧は従来どおり行う)
    if stale && !logFieldTerrain.isEmpty {
        if debugMode { print("[field] ログ画面の古い地形文を採用しませんでした: \(ui) (現在: \(logFieldTerrain))") }
        debugCapture(kind: "terrain_change", key: "terrain_change_blocked:\(ui)", rawText: text,
                     detail: ["from": logFieldTerrain, "to": ui, "turn": currentTurn, "blocked": true])
        return
    }
    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)。
    // あわせて、ターン0 で出所の特性を持つ個体が場にいない開始も
    // 保留する (交代の確定前に開始文だけが先行し、出所なしで対戦開始
    // 直後に置かれた実例: 2026-11-22 battle_20261122_103530、
    // ゴリランダーの グラスフィールド)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()
        || (currentTurn == 0 && !lastSlots.isEmpty && logFieldTerrain.isEmpty && !fieldSourceOnField(ui))) {
        if heldTerrainStart?.ui != ui {
            heldTerrainStart = (ui: ui, text: text, at: sNow())
        }
        return
    }
    // 別の地形が張られている状態への上書きは、出所 (サージ特性の
    // 交代・地形技) が直近に確認できる場合だけ即時に採用する。
    // 出所の無い上書きは開始文の再読や古いフレームの再処理の疑いが
    // 強いため短時間保留し、出所が付けば採用し、付かなければ
    // 破棄する (実例: 2026-11-22 battle_20261122_054802、開始時の
    // サイコフィールド文がターン3に再処理され、張られたばかりの
    // グラスフィールドを上書きした)
    if !logFieldTerrain.isEmpty && !stale && !text.isEmpty && !fieldHoldBypass && !terrainSourcePlausible(ui) {
        if heldTerrainReplace?.ui != ui {
            heldTerrainReplace = (ui: ui, text: text, at: sNow())
        }
        return
    }
    let prev = logFieldTerrain
    fieldTerrainSetAt = sNow()
    let terrainAbility: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    if let ab = terrainAbility[ui] { completePendingMegaForField(ability: ab) }
    emitLog("|-fieldstart|move: \(ui) Terrain")  // 状態への反映は applyEvent が行う
    attributeFieldAbilities()
    retroSeedCheck(terrain: ui)
    // 地形の変化は根拠テキストごと残す (変化の経路を後から特定できるように)
    if !text.isEmpty {
        debugCapture(kind: "terrain_change", key: "terrain_change:\(currentTurn):\(ui)", rawText: text,
                     detail: ["from": prev, "to": ui, "turn": currentTurn])
    }
}

func clearTerrain(stale: Bool = false) {
    if logFieldTerrain.isEmpty { return }
    if stale {
        if debugMode { print("[field] ログ画面の古い地形終了文で現行の地形を消しませんでした: \(logFieldTerrain)") }
        return
    }
    let old = logFieldTerrain
    emitLog("|-fieldend|move: \(old) Terrain")  // 状態への反映は applyEvent が行う
}

func retroSeedCheck(terrain: String) {
    let seedFor: [String: (item: String, stat: String)] = ["Psychic": ("サイコシード", "spd"), "Misty": ("ミストシード", "spd"), "Electric": ("エレキシード", "def"), "Grassy": ("グラスシード", "def")]
    guard let sd = seedFor[terrain] else { return }
    for (plateName, s) in lastSlots {
        let side = plateName.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        if itemLostActive.contains(key) { continue }
        if monStates[key] == nil { monStates[key] = MonState() }
        if (monStates[key]?.hpPercent ?? 100) <= 0 { continue }
        let knownItem = side == "p1" ? (teamEntries[s.speciesEn]?["item"] as? String) : revealedItems[s.speciesEn]
        guard knownItem == sd.item else { continue }
        let slot = slotId(plateName)
        // シードの上昇分も取りこぼしている場合だけ補う。その能力に既に
        // 記録済みの変化がある場合は、内訳を分解できないため重ねない
        // (上昇だけはサルベージ経由で入れる。直後に本物の上昇文が届いた
        //  場合は経路をまたぐ二重適用防止が 25 秒間はじく)
        if !boostTouchedStats.contains("\(key)|\(sd.stat)") {
            applyBoost(key: key, slot: slot, speciesEn: s.speciesEn, stat: sd.stat, delta: 1, viaSalvage: true)
        }
        noteItemLost(slot: slot, side: side, speciesEn: s.speciesEn)
    }
}

func applyMoveField(_ mvJa: String, side: String) {
    // 技で天候・地形を張る場合は、その旨をターンで記録する (交代に
    // よる特性帰属のターン一致判定で、技が原因の開始を交代のせいに
    // しないため)
    if ["あめごい", "にほんばれ", "すなあらし", "ゆきげしき", "さむいギャグ",
        "エレキフィールド", "グラスフィールド", "ミストフィールド", "サイコフィールド"].contains(mvJa) {
        fieldSetByMoveTurn = currentTurn
    }
    // 前の技で確定しなかった設置・解除の保留は、次の技の時点で失効させる
    if let ph = pendingHazard, ph.seq < actionSeq { pendingHazard = nil }
    if let pr = pendingRemoval, pr.seq < actionSeq { pendingRemoval = nil }
    let foe = side == "p1" ? "p2" : "p1"
    switch mvJa {
    case "あめごい": setWeather("Rain", "Rain Dance")
    case "にほんばれ": setWeather("Sun", "Sunny Day")
    case "すなあらし": setWeather("Sand", "Sandstorm")
    case "ゆきげしき", "さむいギャグ": setWeather("Snow", "Snow")
    case "エレキフィールド": setTerrain("Electric")
    case "グラスフィールド": setTerrain("Grassy")
    case "ミストフィールド": setTerrain("Misty")
    case "サイコフィールド": setTerrain("Psychic")
    case "ワイドガード": emitLog("|-sidestart|\(side)|move: Wide Guard")
    // 設置物 (Showdown のサイドコンディションとして扱う)
    case "ステルスロック": emitHazard(foe, "Stealth Rock", start: true)
    case "まきびし": emitHazard(foe, "Spikes", start: true)
    case "どくびし": emitHazard(foe, "Toxic Spikes", start: true)
    case "がんせきアックス":
        // 追加効果の設置は当たった場合のみ。確定は emitLog 側の
        // ダメージ行フックと設置文の救済に任せ、ここでは保留だけ置く
        pendingHazard = (foe, "Stealth Rock", actionSeq)
    case "ねがいごと":
        // 回復は次のターンの終わりに使用側の枠へ届く。発生源の説明
        // (healExplained) が参照するため、使用ターンだけを記録する
        wishSetTurn[side] = currentTurn
    case "こうそくスピン", "キラースピン":
        pendingRemoval = (side, actionSeq)
    case "おかたづけ": clearSideHazards(side)
    case "きりばらい":
        // きりばらいは両側の設置物とフィールドを消す (第9世代仕様)
        clearSideHazards("p1"); clearSideHazards("p2")
        if !logFieldTerrain.isEmpty { emitLog("|-fieldend|move: \(logFieldTerrain) Terrain") }
    case "コートチェンジ":
        let mineHz = battleHazards["p1"] ?? [:], oppHz = battleHazards["p2"] ?? [:]
        clearSideHazards("p1"); clearSideHazards("p2")
        for (name, layers) in oppHz { for _ in 0..<layers { emitHazard("p1", name, start: true) } }
        for (name, layers) in mineHz { for _ in 0..<layers { emitHazard("p2", name, start: true) } }
    default: break
    }
}

func applyAbilityField(_ abJa: String) {
    switch abJa {
    case "あめふらし": setWeather("Rain", "Rain Dance")
    case "ひでり": setWeather("Sun", "Sunny Day")
    case "すなあらし": setWeather("Sand", "Sandstorm")
    case "ゆきふらし": setWeather("Snow", "Snow")
    case "エレキメイカー", "ハドロンエンジン": setTerrain("Electric")
    case "グラスメイカー": setTerrain("Grassy")
    case "ミストメイカー": setTerrain("Misty")
    case "サイコメイカー": setTerrain("Psychic")
    default: break
    }
}

func emitHazard(_ side: String, _ hazard: String, start: Bool) {
    lastSideCondAt["\(side):\(hazard):\(start ? "start" : "end")"] = sNow()
    emitLog("|-\(start ? "sidestart" : "sideend")|\(side)|move: \(hazard)")
}

func clearSideHazards(_ side: String) {
    guard let hz = battleHazards[side] else { return }
    for name in hz.keys.sorted() { emitHazard(side, name, start: false) }
}

func checkFieldText(text: String, fromLogScreen: Bool = false) -> Bool {
    // フィールドの終了文 (実機の文面は漢字混じり。OCR 崩れにも耐えるよう緩く照合する)
    if (text.contains("不思議") || text.contains("フィールド")) && (text.contains("なくな") || text.contains("消え") || text.contains("きえ") || text.contains("きれ")) { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("霧が") && text.contains("はれた") { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("電気が") && (text.contains("消えた") || text.contains("消え去った")) { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("草が") && (text.contains("なくな") || text.contains("消え") || text.contains("きえ")) { clearTerrain(stale: fromLogScreen); return true }
    // トリックルーム (地形・天候とは別枠のフィールド効果)。開始文の
    // 濁点崩れ (ゆがめた -> ゆかめた) も拾う (実例: 2026-11-22
    // battle_20261122_071457、開始行が出ず告知文が未翻訳で残った)
    if text.contains("時空") && (foldDakuten(text).contains("ゆかめ") || text.contains("歪め")) {
        if !logTrickRoom {
            // 告知行が落ちている場合、開始文の主語から技行を補う
            // (実例: 2026-11-23 battle_20261123_060833、告知文は obs に
            // クリーンに残っていたが技行だけが無く、開始行だけが残った。
            // 開始文は使用者が確定している証拠なので、現在の区間に同じ
            // 技行が無い場合に限り開始行の直前へ補う。告知が後から届いても
            // emitLog の同ラウンド再使用ガードが二重化を防ぐ)
            if !fromLogScreen, let tsp = findSpeciesJa(in: text) {
                let tside = (text.contains("相手の") || text.contains("あいての")) ? "p2" : "p1"
                let tslot = slotFor(side: tside, speciesEn: tsp.en)
                let tpn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][tslot] ?? ""
                let tocc = lastSlots[tpn]?.speciesEn
                if let tocc, sameSpeciesFamily(tocc, tsp.en) {
                    let tlabel = "\(tslot): \(tsp.en)"
                    let segStart = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) ?? -1
                    if !battleLog[(segStart + 1)...].contains("|move|\(tlabel)|Trick Room") {
                        emitLog("|move|\(tlabel)|Trick Room")
                    }
                }
            }
            emitLog("|-fieldstart|move: Trick Room")
        }
        return true
    }
    if (text.contains("ゆがみ") || text.contains("時空")) && (text.contains("戻った") || text.contains("もどった")) {
        // 継続ターンの管理側が先に終了行を出していた場合 (logTrickRoom
        // が既に落ちている) も、文自体は消費する (実例: 2026-11-21
        // battle_20261121_233243、|-fieldend| の直後に同じ文が
        // |-message| として残り、二重に表示された)
        if logTrickRoom { emitLog("|-fieldend|move: Trick Room") }
        return true
    }
    // フィールドの開始文 (特性サージ系は種族名・特性名が出ず、この文だけが出る。
    // 「足下が不思議な感じになった」はサイコフィールド専用の文。
    // 「感じになった」はこの文にしか出ないため、足下・不思議が OCR 崩れ
    // しても拾う (実例: 2026-11-20「下か不態議な感じになった！」の漏れ)。
    // ただし「感じ+なった」だけでは広すぎるため、地形文らしい断片
    // (不思議/議/足下/下が/下か) の併存を必須にする)
    if text.contains("感じ") && text.contains("なった") && (text.contains("不思議") || text.contains("議") || text.contains("足下") || text.contains("下が") || text.contains("下か")) { setTerrain("Psychic", via: text, stale: fromLogScreen); return true }
    if text.contains("足下が") && text.contains("不思議な感じに") { setTerrain("Psychic", via: text, stale: fromLogScreen); return true }
    if (text.contains("足下に") || text.contains("足下が")) && text.contains("電気が") && text.contains("かけめぐ") { setTerrain("Electric", via: text, stale: fromLogScreen); return true }
    // 「おいしげ」はグラスフィールドの開始文にしか出ないため、それ
    // だけで拾う (実例: 2026-11-21 battle_20261121_233243、実文が
    // 「定下に草かおいしげった！」と崩れ、足下・草が の両アンカーが
    // 外れて開始行が欠落した)
    if text.contains("おいしげ") { setTerrain("Grassy", via: text, stale: fromLogScreen); return true }
    if (text.contains("足下に") || text.contains("足下が") || text.contains("足元")) && text.contains("草が") && (text.contains("生い茂") || text.contains("おいしげ") || text.contains("しげった") || text.contains("茂った")) { setTerrain("Grassy", via: text, stale: fromLogScreen); return true }
    if text.contains("足下が") && text.contains("霧に") && text.contains("包まれ") { setTerrain("Misty", via: text, stale: fromLogScreen); return true }
    // 天候の終了文 (晴れの実機文面は「日差しが元に戻った！」。
    // 『弱く』だけを条件にしていたため実機の文面では成立せず、晴れが
    // 解除されないまま残った。実例: 2026-11-21 battle_20261121_155801
    // 「ひざ日差しが元に戻った！」— 先頭に読みの重複が付いた崩れでも
    // 『戻った』で拾う)
    if (text.contains("日差し") || text.contains("ひざし")) && (text.contains("戻った") || text.contains("もどった") || text.contains("弱く")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("雨") && (text.contains("やんだ") || text.contains("止んだ") || text.contains("上がった")) { clearWeather(stale: fromLogScreen); return true }
    if (text.contains("あめ") && (text.contains("やんだ") || text.contains("おさまった"))) { clearWeather(stale: fromLogScreen); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("おさま") || text.contains("弱ま")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("雪") && (text.contains("やんだ") || text.contains("止んだ")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("ゆき") && text.contains("やんだ") { clearWeather(stale: fromLogScreen); return true }
    // 天候の開始文 (実機の文面: 「日差しが強くなった」「雨が降り始めた」等。
    // 従来は ひざし/あめ 等の平仮名だけで照合しており、漢字表記に一致せず
    // ひでり等の天候を拾えていなかった)
    if (text.contains("日差し") || text.contains("ひざし")) && text.contains("強く") { setWeather("Sun", "Sunny Day", via: text, stale: fromLogScreen); return true }
    if text.contains("雨") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Rain", "Rain Dance", via: text, stale: fromLogScreen); return true }
    if text.contains("あめ") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Rain", "Rain Dance", via: text, stale: fromLogScreen); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("吹き始") || text.contains("吹き荒") || text.contains("ふきあれ")) { setWeather("Sand", "Sandstorm", via: text, stale: fromLogScreen); return true }
    if text.contains("雪") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Snow", "Snow", via: text, stale: fromLogScreen); return true }
    if text.contains("ゆき") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Snow", "Snow", via: text, stale: fromLogScreen); return true }
    if text.contains("フィールド") && text.contains("ひろが") {
        for (ja, en) in [("エレキ", "Electric"), ("グラス", "Grassy"), ("ミスト", "Misty"), ("サイコ", "Psychic")] where text.contains(ja) {
            setTerrain(en, via: text, stale: fromLogScreen)
            return true
        }
    }
    return false
}

func checkStatusText(text: String, side: String, speciesEn: String, slot: String) {
    let key = "\(side):\(speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // 起床: 「<対象>は 目を覚ました！」(目 が 自 に崩れた形も、覚ました
    // 自体が特徴的なため拾う。実例: 2026-11-21 battle_20261121_234913
    // 「ガブリアスは自を覚ました！」が未翻訳で残った)
    if text.contains("覚ました") {
        if monStates[key]?.status == "slp" {
            emitLog("|-curestatus|\(slot): \(speciesEn)|slp")
        }
        return
    }
    if text.contains("なおった") || text.contains("なおつた") {
        if let cur = monStates[key]?.status, !cur.isEmpty {
            emitLog("|-curestatus|\(slot): \(speciesEn)|\(cur)")  // 状態への反映は applyEvent が行う
        }
        return
    }
    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた", "負った", "負つた"]
    guard cues.contains(where: { text.contains($0) }) else { return }
    var code: String? = nil
    if text.contains("もうどく") { code = "tox" }
    else if text.contains("どく") { code = "psn" }
    else if text.contains("やけど") { code = "brn" }
    else if text.contains("まひ") { code = "par" }
    else if text.contains("ねむ") || (text.contains("眠") && !text.contains("眠気")) { code = "slp" }
    else if text.contains("こおり") || text.contains("こおった") { code = "frz" }
    if let code, monStates[key]?.status != code {
        emitLog("|-status|\(slot): \(speciesEn)|\(code)")  // 状態への反映は applyEvent が行う
    }
}

func checkBoostText(text: String, side: String, speciesEn: String, slot: String) {
    if text.contains("あがらない") || text.contains("さがらない") || text.contains("上がらない") || text.contains("下がらない") { return }
    // 小さい「っ」が通常の「つ」に崩れる OCR ゆれも拾う
    // (実例: 2026-11-20「とくぼう特防が上がつた！」が日本語のまま漏れた)
    let up = text.contains("あがった") || text.contains("上がった") || text.contains("あがつた") || text.contains("上がつた")
    let down = text.contains("さがった") || text.contains("下がった") || text.contains("さがつた") || text.contains("下がつた")
    guard up || down else { return }
    let key = "\(side):\(speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // ゲーム内表記は漢字 (攻撃/防御/特攻/特防/素早さ) が正。ひらがな表記も併記する
    // 「防が下がった」のように 2 文字目が落ちる OCR 崩れも拾う
    // (「攻が」「防が」は「攻撃が」「防御が」の部分文字列にはならないため誤爆しない)
    let stats: [(String, String)] = [("こうげき", "atk"), ("攻撃", "atk"), ("攻が", "atk"), ("ぼうぎょ", "def"), ("防御", "def"), ("防が", "def"), ("とくこう", "spa"), ("特攻", "spa"), ("とくぼう", "spd"), ("特防", "spd"), ("すばやさ", "spe"), ("素早さ", "spe"), ("めいちゅう", "acc"), ("命中率", "acc"), ("かいひ", "eva"), ("回避率", "eva"),
                                     ("コウゲキ", "atk"), ("ボウギョ", "def"), ("トクコウ", "spa"), ("トクボウ", "spd"), ("スバヤサ", "spe"), ("メイチュウ", "acc"), ("カイヒ", "eva")]
    // 「がくっと下がった」も 2 段階 (従来は ぐーんと しか見ておらず、がくっと
    // の低下が 1 段階として記録されていた。検証 R1 #32/#88 で検出。
    // がくっと 自体が「がくつと」に崩れた形も 2 段階とする: 検証 R2 #89/#91。
    // ぐーんと の長音が落ちた「ぐんと」も 2 段階とする: 検証 R4 #13/#45)
    var mag = (text.contains("ぐーんと") || text.contains("ぐんと") || text.contains("がくっと") || text.contains("がくつと")) ? 2 : 1
    // つぼをつく は必ず 2 段階上がる。上昇量の文の「ぐーんと」が
    // 読み落ちて 1 段階として記録されるのを、技の文脈で正す
    // (実例: 2026-11-22 battle_20261122_091721 ターン6)
    if up && mag == 1 && lastMoveName == "Acupressure" && sNow().timeIntervalSince(lastMoveMsgAt) < 20 { mag = 2 }
    if text.contains("すべての") {
        for (_, code) in stats.prefix(5) { applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: code, delta: up ? mag : -mag) }
        return
    }
    // 文中に現れる能力はすべて適用する (たくわえる の 防御+特防 のように
    // 1 文で 2 つ上がる技があるため、最初の 1 つで打ち切らない)。
    // フリガナ+漢字の二重表記は同一コードとして 1 回だけ数える
    var matched: [(String, Int)] = []
    var applied = Set<String>()
    let foldedText = foldDakuten(text)
    for (ja, code) in stats where !applied.contains(code) {
        // 「攻が」「防が」の 1 字落ちフォールバックは「特攻が」「特防が」の
        // 部分文字列でもあるため、特攻/特防の文では使わない
        // (実例: 2026-11-20、サイコキネシスの特防低下に防御低下まで付いた)
        if ja == "攻が" && (text.contains("特攻が") || foldedText.contains("特攻か")) { continue }
        if ja == "防が" && (text.contains("特防が") || foldedText.contains("特防か")) { continue }
        // 濁点ゆれ (スパヤサ等) は両辺を畳んだ形でも照合する (検証 R1)
        guard text.contains(ja) || foldedText.contains(foldDakuten(ja)) else { continue }
        applied.insert(code)
        matched.append((code, up ? mag : -mag))
    }
    // じきゅうりょく の帰属: 特性バナーは画面上部の表示で帯の文には
    // 入らず、帯に届くのは上昇文だけのため、被弾発動の特性行は
    // 今まで出なかった (実例: 2026-11-23 battle_20261123_052626、
    // ブリジュラスの防御上昇に特性行が付かなかった)。「相手の技で
    // 被ダメした直後の 防御 +1 の上昇」で、特性が未判明かつその種族が
    // 持ち得る場合だけ、上昇の適用前に特性行を出す
    if up && mag == 1 && matched.contains(where: { $0.0 == "def" })
        && (damagedBySeq[actionSeq] ?? []).contains("\(slot): \(speciesEn)")
        && !lastMoveLabel.isEmpty && !lastMoveLabel.hasPrefix(side)
        && !battleLog.contains(where: { $0.hasPrefix("|-ability|\(slot): \(speciesEn)|") })
        && (speciesAbilityMap[speciesEn]?.contains("Stamina") ?? false) {
        emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Stamina")
    }
    for m in matched {
        applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: m.0, delta: m.1)
    }
}

func applyBoost(key: String, slot: String, speciesEn: String, stat: String, delta: Int, viaSalvage: Bool = false) {
    // 同じ文の OCR ゆれ違いの再読で二重に適用しない: 同じ行動・同じターン・
    // 4 秒以内の同一変化 (枠・能力・増減) は再読とみなして捨てる
    // (実例: アーマーキャノンの自己低下といかくの攻撃低下が 2 重に出た)。
    // 別の技による正当な再変化は |move| を挟むため行動番号が変わり、適用される
    // 重複防止のキーは枠でなく個体キーにする (複合主語の文で、片方が
    // 既定枠に解決されると、実占有者とキーが衝突して変化が丸ごと
    // 落ちる。実例: 2026-11-23 battle_20261123_060833 の いかく)
    let bk = "\(key)|\(stat)|\(delta)"
    if let lb = lastBoostApply[bk], lb.seq == actionSeq && lb.turn == currentTurn && sNow().timeIntervalSince(lb.at) < 4 { return }
    // 経路をまたぐ二重適用の防止: サルベージ層と正規経路が同じ出来事を
    // 別々に拾った場合、逆経路で 25 秒以内に記録済みの同一変化は捨てる
    // (emitItemOnce の 25 秒ウィンドウと同型)。同経路の再変化は対象外
    let pk = "\(key)|\(stat)|\(delta)"
    if let prev = boostPathAt[pk], prev.salvage != viaSalvage, sNow().timeIntervalSince(prev.at) < 25 { return }
    lastBoostApply[bk] = (seq: actionSeq, turn: currentTurn, at: sNow())
    boostPathAt[pk] = (at: sNow(), salvage: viaSalvage)
    let cur = monStates[key]?.boosts[stat] ?? 0
    let nv = max(-6, min(6, cur + delta))
    if nv == cur { return }
    boostTouchedStats.insert("\(key)|\(stat)")
    if stat == "atk" && delta < 0 { recentAtkDrops[key] = (sNow(), actionSeq) }
    let line = delta > 0 ? "|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)" : "|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)"
    // 状態への適用は発生時点で applyEvent が行う。行の表示は交代行の後まで
    // 保留することがあるため、追記時は再適用しない (applyNow: false)
    applyEvent(line)
    // 交代行がまだ出ていない種族のランク変化行は、交代行の後に出す
    // (実例: 2026-11-20 vs Vanille 戦、場に出る前の サイコシード 発動行が
    //  繰り出し行より先に出た)。状態への適用は即時に行い、行だけ保留する
    if !emittedSwitchKeys.contains(key) && (monStates[key]?.hpPercent ?? 100) > 0 {
        // 行は出さず変化だけ保留する。枠は交代確定の時点で付け直す
        // (読んだ時点では場にいないため slotFor が既定の a 枠を返し、
        //  実際の枠と食い違う。実例: 2026-11-20、オオニューラの
        //  サイコシード発動行が p1a で出た (実際は p1b))
        heldBoostLines[key, default: []].append((stat, delta, sNow()))
    } else if stat == "atk" && delta < 0 && sNow().timeIntervalSince(lastMoveMsgAt) > 3
                && entryEffectPending(key: key) {
        // 入場特性 (いかく) の効果とみられる攻撃低下が、原因側の
        // 交代確定より先に届いた場合は、行だけを保留して交代行の
        // 後に流す (状態への適用は上の applyEvent で済んでいる)。
        // 技の文が直近にある場合は技の効果なので保留しない
        // (実例: 2026-11-22 battle_20261122_050512、ボーマンダの
        //  いかくの低下行が交代行・特性行より前に並んだ)
        heldEntryBoosts.append((key: key, line: line, at: sNow()))
    } else if heldEntryBoosts.contains(where: { $0.key == key }) && sNow().timeIntervalSince(lastMoveMsgAt) > 3 {
        // 入場効果として保留中の個体の後続の変化 (いかくを受けた
        // かちき の特攻上昇など) も、原因の交代行が出るまで一緒に
        // 保留する (片方だけ先に出ると順序が崩れる。実例: 2026-11-22
        // battle_20261122_070237、ミロカロスの攻撃低下と特攻上昇が
        // キュウコンとムクホークの交代行より前に並んだ)
        heldEntryBoosts.append((key: key, line: line, at: sNow()))
    } else {
        emitLog(line, applyNow: false)
    }
    // 地形シードの消費: 対応する地形が出ているとき、その地形のシードが
    // 上げる能力が +1 されたらシードを消費したとみなす (持ち物がその
    // シードだと分かっている場合のみ)。消費が確定すれば かるわざ の判定へ
    let seedFor: [String: (item: String, stat: String)] = ["Psychic": ("サイコシード", "spd"), "Misty": ("ミストシード", "spd"), "Electric": ("エレキシード", "def"), "Grassy": ("グラスシード", "def")]
    if delta == 1, let sd = seedFor[logFieldTerrain], sd.stat == stat {
        let sdSide = String(key.prefix(2))
        let knownItem = sdSide == "p1" ? (teamEntries[speciesEn]?["item"] as? String) : revealedItems[speciesEn]
        if knownItem == sd.item {
            if emittedSwitchKeys.contains(key) { noteItemLost(slot: slot, side: sdSide, speciesEn: speciesEn) }
            else { pendingUnburden.insert(key) }
        } else if !viaSalvage, knownItem == nil, sdSide == "p2", !itemLostActive.contains(key),
                  emittedSwitchKeys.contains(key) {
            // 持ち物が未判明の相手についても、地形シードの発動としか
            // 読めない上昇 (入場直後か、地形が張られた直後に起きて、
            // 本人の技による上昇ではない) は、そのシードを持って
            // いたことの判明として記録する。ゲーム内ではシードの
            // 発動が表示され、対戦ログ上も確定情報として扱われるが、
            // 従来は持ち物が判明済みの場合しか記録しておらず、推定へ
            // 判明情報が届かなかった (実例: 2026-11-22
            // battle_20261122_054802、イエッサンのサイコシードと
            // オオニューラのグラスシード)。自軍の持ち物は登録
            // データで判明しているため、対象は相手のみ
            let justEntered = lastSwitchIn[key].map { sNow().timeIntervalSince($0.at) < 15 } ?? false
            let terrainFresh = sNow().timeIntervalSince(fieldTerrainSetAt) < 15
            let ownMove = lastMoveLabel == "\(slot): \(speciesEn)" && sNow().timeIntervalSince(lastMoveMsgAt) < 20
            if (justEntered || terrainFresh) && !ownMove {
                emitItemOnce(slot: slot, side: sdSide, speciesEn: speciesEn, itemJa: sd.item)
                noteItemLost(slot: slot, side: sdSide, speciesEn: speciesEn)
            }
        }
    }
}

func copyBoosts(fromKey: String, toKey: String, slot: String, speciesEn: String) {
    guard let src = monStates[fromKey]?.boosts else { return }
    if monStates[toKey] == nil { monStates[toKey] = MonState() }
    for stat in ["atk", "def", "spa", "spd", "spe", "acc", "eva"] {
        let target = src[stat] ?? 0
        let cur = monStates[toKey]?.boosts[stat] ?? 0
        if target == cur { continue }
        // 状態への反映は emitLog -> applyEvent が行う (差分行から目標値になる)
        let delta = target - cur
        if delta > 0 { emitLog("|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)") }
        else { emitLog("|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)") }
    }
}

func flushHeldBoosts(forKey key: String, slot: String) {
    guard let arr = heldBoostLines.removeValue(forKey: key) else { return }
    let speciesEn = String(key.dropFirst(3))
    for h in arr { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta), applyNow: false) }
}

func flushHeldBoostsTimeout() {
    let cap: TimeInterval = anyAwaitingReplacement() ? 20 : 6
    if heldEntryBoosts.contains(where: { sNow().timeIntervalSince($0.at) > cap }) { flushHeldEntryBoosts() }
    if heldBoostLines.isEmpty { return }
    let now = sNow()
    for k in Array(heldBoostLines.keys) {
        guard let arr = heldBoostLines[k] else { continue }
        // 交代確定はアニメーションの都合で 1 ターン分遅れることがある
        // (実例: 2026-11-20、4 秒で時間切れになり交代行より先に出た)。
        // フィールド特性の帰属窓と同じ 30 秒まで待つ
        let ready = arr.filter { now.timeIntervalSince($0.at) > 30 }
        if ready.isEmpty { continue }
        let keep = arr.filter { now.timeIntervalSince($0.at) <= 30 }
        if keep.isEmpty { heldBoostLines[k] = nil } else { heldBoostLines[k] = keep }
        let speciesEn = String(k.dropFirst(3))
        let slot = slotFor(side: String(k.prefix(2)), speciesEn: speciesEn)
        for h in ready { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta), applyNow: false) }
    }
}

func completeMega(side: String, baseEn: String, megaEn: String) {
    let key = "\(side):\(baseEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    if monStates[key]?.megaSpecies == megaEn {
        pendingMegaStone[side] = nil
        pendingMegaSpecies[side] = nil
        return
    }
    // megaSpecies への反映は |detailschange| 行の applyEvent が行う
    let slot = slotFor(side: side, speciesEn: baseEn)
    // 場に居ることが確認できていない種族のメガを、別種族が占有して
    // いる枠へ付けることはしない。slotFor は場に無い種族に対して
    // 既定枠 (a 枠) を返すため、そのまま出すと無関係な枠の種族として
    // detailschange が出て、その枠の状態まで巻き込む (実例:
    // 2026-11-22 battle_20261122_071457、交代が未確定だった
    // ムクホークのメガがオオニューラの枠 p1a に付いた)。保留は
    // 維持し、交代の確定後の再試行 (synthesizeMegaIfPending) で
    // 正しい枠に出す
    let megaPlate = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
    if let occ = lastSlots[megaPlate], !sameSpeciesFamily(occ.speciesEn, baseEn) {
        return
    }
    // 行のラベルは場の実表記 (フォルム名) に寄せる。ベース名のまま
    // だと交代行 (Floette-Eternal) と表記が揺れ、状態のキーも場の
    // エントリとずれる (実例: 2026-11-22 battle_20261122_103530)
    let labelSp = (lastSlots[megaPlate]?.speciesEn).flatMap { sameSpeciesFamily($0, baseEn) ? $0 : nil } ?? baseEn
    emitLog("|detailschange|\(slot): \(labelSp)|\(megaEn)")
    var megaLine = "|-mega|\(slot): \(labelSp)|\(baseEn)"
    if let stoneJa = pendingMegaStone[side] { megaLine += "|\(itemJa2En[stoneJa] ?? stoneJa)" }
    emitLog(megaLine)
    pendingMegaStone[side] = nil
    pendingMegaSpecies[side] = nil
}

func synthesizeMegaIfPending(side: String, speciesEn: String) {
    guard pendingMegaSpecies[side] == speciesEn else { return }
    guard (monStates["\(side):\(speciesEn)"]?.megaSpecies ?? "").isEmpty else { return }
    guard let me = pendingMegaForme(side: side, baseEn: speciesEn) else { return }
    completeMega(side: side, baseEn: speciesEn, megaEn: me)
}

func recordSwitchIn(side: String, slot: String, speciesEn: String) {
    lastSwitchIn["\(side):\(speciesEn)"] = (slot, sNow())
    switchInTurn["\(side):\(speciesEn)"] = currentTurn
    fieldSeen[side, default: []].insert(speciesEn)
    // 保留中の特性帰属 (交代確定前に定型文だけが届いた場合) を、
    // 交代行の直後に流す (実例: 2026-11-23 battle_20261123_060833、
    // そうだいしょうの文がプレート確定より先に届いた)
    if let pendingAbility = pendingAbilityReveal.removeValue(forKey: "\(side):\(speciesEn)") {
        emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: pendingAbility)
    }
    // この交代が出所になって、地形の上書き保留が採用できることがある
    confirmHeldTerrainReplace()
    attributeFieldAbilities()
    // いかくの遡及帰属: プレート確定がメッセージより遅れ、攻撃 -1 の適用時に
    // 繰り出しが未記録だった場合は、記録したこの時点で特性行を出す
    // (実例: 2026-11-20 vs BigGuyMan 戦、ズルズキンの いかく が付かなかった)
    let key = "\(side):\(speciesEn)"
    if let sw = lastSwitchIn[key], intimidateDone[key] != sw.at,
       let pool = speciesAbilityMap[speciesEn], pool.contains("Intimidate") {
        let other = side == "p1" ? "p2" : "p1"
        let now = sNow()
        // seq 一致まで要求すると、確定の遅れの間に他の文が処理された
        // 時点で恒常的に外れ、特性行が丸ごと落ちる (実例: 2026-11-22
        // battle_20261122_071457、特性行が 1 行も出なかった)。攻撃
        // 低下の記録が直近 20 秒以内にあれば帰属の根拠として十分
        let hasDrop = recentAtkDrops.contains { $0.key.hasPrefix("\(other):") && now.timeIntervalSince($0.value.at) < 20 }
        if hasDrop {
            intimidateDone[key] = sw.at
            emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Intimidate")  // 判明登録は applyEvent が行う
        }
    }
    // どくびしの吸収: 接地した どくタイプが場に出ると、その側の
    // どくびしは消える (実際の仕様)。タイプと特性プールから確定的に
    // 言える範囲でのみ導出し、ふゆう候補が未判明の種族・ふゆう判明・
    // ふうせん判明の場合は行わない (告知文の経路に任せる)
    if battleHazards[side]?["Toxic Spikes"] != nil,
       let types = pvSpeciesTypes[speciesEn], types.contains("Poison"), !types.contains("Flying") {
        let pool = speciesAbilityMap[speciesEn] ?? []
        var grounded = !pool.contains("Levitate")
        if !grounded {
            let abilityJa = side == "p1" ? (teamEntries[speciesEn]?["ability"] as? String) : revealedAbilities[speciesEn]
            if let abilityJa, abilityJa != "ふゆう" { grounded = true }
        }
        let itemJa = side == "p1" ? (teamEntries[speciesEn]?["item"] as? String) : revealedItems[speciesEn]
        if grounded && itemJa != "ふうせん" {
            emitHazard(side, "Toxic Spikes", start: false)
        }
    }
    // この種族宛てに保留していたランク変化行を、交代行の後に出す
    flushHeldBoosts(forKey: key, slot: slot)
    // 入場特性の効果として保留していた行も、この交代行の後に流す
    flushHeldEntryBoosts()
    // 交代前にシード消費を検知していた場合、かるわざ の発動をここで出す
    if pendingUnburden.remove(key) != nil { noteItemLost(slot: slot, side: side, speciesEn: speciesEn) }
}

func megaTextSide(_ t: String, baseEn: String) -> String {
    if t.contains("相手の") || t.contains("あいての") { return "p2" }
    if t.contains("味方の") || t.contains("じぶんの") { return "p1" }
    let pend = ["p1", "p2"].filter { pendingMegaSpecies[$0] == baseEn }
    if pend.count == 1 { return pend[0] }
    // 場の照合はファミリー単位で行う (場の表記がフォルム名
    // (Floette-Eternal) で文側がベース名 (Floette) の場合に、完全一致
    // では決まらない。実例: 2026-11-22 battle_20261122_103530、
    // フラエッテのメガストーンが自軍のグレンアルマに誤帰属した)
    let inMine = ["mineA", "mineB"].contains { (lastSlots[$0]?.speciesEn).map { sameSpeciesFamily($0, baseEn) } ?? false }
    let inOpp = ["oppA", "oppB"].contains { (lastSlots[$0]?.speciesEn).map { sameSpeciesFamily($0, baseEn) } ?? false }
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    // 場で決まらない場合も、登録の所在が片側だけならそちらを正とする
    // (無条件の自軍帰属はしない)
    let teamMine = teamEntries.keys.contains { sameSpeciesFamily($0, baseEn) }
    let teamOpp = oppTeamSeen.contains { sameSpeciesFamily($0, baseEn) }
    if teamMine != teamOpp { return teamMine ? "p1" : "p2" }
    return "p1"
}

func isBoostShapedText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    guard t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった") || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた") else { return false }
    if t.contains("あがらない") || t.contains("さがらない") || t.contains("上がらない") || t.contains("下がらない") { return false }
    // 「撃が」「御が」は漢字能力名の後半断片 (攻撃の「政撃」のような
    // 1 字化けでも形状として拾う。実例: 2026-11-23
    // battle_20261123_060833、「政撃が下がった！」が未変換で漏れた)
    return ["攻撃", "こうげき", "防御", "ぼうぎょ", "攻が", "防が", "撃が", "御が", "特攻", "とくこう", "特防", "とくぼう", "素早さ", "すばやさ", "命中率", "回避率", "すべての"].contains { t.contains($0) }
}

func isMoveFragmentText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    // 記号と「の」は normalize で落ちる/化けるため、構造判定は生テキストで行う
    guard t.hasSuffix("！") || t.hasSuffix("!") else { return false }
    guard t.contains("の") && normalize(t).count <= 16 else { return false }
    if findSpeciesJa(in: t) != nil { return false }   // 解決できる文は通常経路に任せる
    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") || t.contains("効果は") || t.contains("回復") { return false }
    guard let tail = t.split(separator: "の").last.map(String.init) else { return false }
    // 技名は助詞を含まない短い名詞句。文の形 (助詞入り・長文) は対象外
    if tail.contains("は") || tail.contains("が") || tail.contains("を") || tail.contains("に") { return false }
    let cand = normalize(tail.trimmingCharacters(in: CharacterSet(charactersIn: "！!【】")))
    return cand.count >= 3 && cand.count <= 9
}

func translateBattleMessage(_ text: String) -> Bool {
    let before = battleLog.count
    // 急所の文はダメージ確定 (行の出力) より前に表示されるため、
    // その文のときだけ先行フラッシュを止めて帰属を pending 側に残す
    // (「急所」が OCR 崩れした文も同様に止める)
    let strippedText = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    if !strippedText.contains("急所") && !(strippedText.contains("所に") && (strippedText.contains("当たった") || strippedText.contains("たった")))
        && !strippedText.hasSuffix("に当たった！") && !strippedText.hasSuffix("に当たった!")
        && !strippedText.hasSuffix("にたった！") && !strippedText.hasSuffix("にたった!") { flushPendingDamage() }
    // 照合は空白を除いた形で行う (OCR のボックス分割で空白位置が揺れるため)
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    let nt = normalize(t)
    // ほろびのうたのカウント文と告知文は、場の状態として別途持たない
    // ため消費のみ (表記ゆれ: 滅び/減び、分割読み「ぼろ滅び」「ほろ
    // 滅び」は空白除去後の形で判定する。実例: 2026-11-22
    // battle_20261122_181745、カウント文が |-message| として漏れた)
    if t.contains("カウントが") && (t.contains("滅び") || t.contains("減び")) { return true }
    if t.contains("ほろびのうたを") && t.contains("滅びてしまう") { return true }
    // ポケモンの詳細画面 (様子を見る) の文は対戦文ではない。画面内の
    // 設定ラベル「つよさの表示」は対戦文には現れないため、これを含む
    // 文は詳細画面の混入として消費だけする (実例: 2026-11-21
    // battle_20261121_234913、詳細画面の「特性 もうか / 持ち物
    // リザードナイトY / つよさの表示 オフ / 戻る」が対戦文の経路に
    // 入り、種族の誤認と既定枠への帰属が起きた)
    if t.contains("つよさの表示") { return true }
    // 外れの文が対象種族なしで届いた場合 (文の末尾だけが読めた断片):
    // 直近の技が解決中の間は未翻訳として残さず消費する。被ダメの記録が
    // 無く、まもる も使っておらず、ひんしにもなっていない相手枠が
    // 1 つだけなら、その枠への外れとして記録する (実例: 2026-11-22
    // battle_20261122_103530、「当たらなかった！」だけが未翻訳で残った)
    if t.contains("当たらなかった") && findSpeciesJa(in: t) == nil
        && !lastMoveLabel.isEmpty && sNow().timeIntervalSince(lastMoveMsgAt) < 10 {
        let moverSide = lastMoveLabel.hasPrefix("p1") ? "p1" : "p2"
        let targetPlates = moverSide == "p1" ? ["oppA", "oppB"] : ["mineA", "mineB"]
        var unresolved: [(slot: String, speciesEn: String)] = []
        for pn in targetPlates {
            guard let occ = lastSlots[pn] else { continue }
            let sl = slotId(pn)
            let label = "\(sl): \(occ.speciesEn)"
            if (damagedBySeq[actionSeq] ?? []).contains(label) { continue }
            if protectMoveTurn[sl] == currentTurn { continue }
            if faintedSlots[sl] != nil { continue }
            unresolved.append((slot: sl, speciesEn: occ.speciesEn))
        }
        if unresolved.count == 1 {
            emitLog("|-miss|\(lastMoveLabel)|\(unresolved[0].slot): \(unresolved[0].speciesEn)")
        } else {
            debugCapture(kind: "move_guard", key: "miss_bare:\(currentTurn):\(actionSeq)", rawText: t,
                         detail: ["reason": "bare_miss_consumed", "mover": lastMoveLabel, "candidates": unresolved.count, "turn": currentTurn])
        }
        return true
    }
    // 勝敗: 「<相手>との 勝負に 負けた！/勝った！」
    // (実機ログでは「勝った」が「勝つた」と OCR 崩れしていたため、
    //  小さい「っ」を通常の「つ」に寄せた形でも判定する)
    // 「勝負」の負が別字に崩れる読み (勝質に 等) でも判定できるよう、
    // 勝+任意の1字+に の形で見る (実例: 2026-11-23
    // battle_20261123_052626、帯の読みが「勝質に勝った！」となり
    // 勝敗が確定せず、完結した試合が interrupted で届いた)
    let tw = t.replacingOccurrences(of: "っ", with: "つ").replacingOccurrences(of: "ッ", with: "ツ")
    if t.range(of: "勝.に", options: .regularExpression) != nil && (t.contains("負けた") || tw.contains("勝つた")) {
        if winLogged || winLineEmitted { return true }   // 同じ勝敗文の再読では出さない
        let won = tw.contains("勝つた")
        var oppName = trainerOpp
        if let r = t.range(of: "との") {
            let n = String(t[..<r.lowerBound])
            if !n.isEmpty && n.count <= 20 { oppName = n }
        }
        // 降参の文が拾えなかった場合の推定: 負けた側に「場に出て倒れて
        // いないポケモンがいる」か「場に出たのが 4 体未満」なら、倒し切って
        // の終了ではあり得ないため降参として扱う (実例: 2026-11-20
        // vs Zycloud 戦、相手に 3 体残して勝敗が確定した)
        if forfeitName == nil {
            let loserSide = won ? "p2" : "p1"
            let entered = fieldSeen[loserSide] ?? []
            let anyAlive = entered.contains { (monStates["\(loserSide):\($0)"]?.hpPercent ?? 100) > 0 }
            if anyAlive || entered.count < 4 {
                forfeitName = won ? (oppName.isEmpty ? "Opponent" : oppName) : (trainerMine.isEmpty ? "You" : trainerMine)
            }
        }
        emitPendingFaints()
        if won { emitLog("|win|\(trainerMine.isEmpty ? "p1" : trainerMine)") }
        else { emitLog("|win|\(oppName.isEmpty ? "p2" : oppName)") }
        winLineEmitted = true
        if !oppName.isEmpty { trainerOpp = oppName }
        // 手動モードでは勝敗行だけを記録し、フラグと確定保存は
        // 終了ボタンの押下まで遅らせる
        if !flagManualMode {
            winLogged = true
            archiveCurrentBattle(final: true)
        }
        return true
    }
    if t.contains("あきらめた") {
        if winLogged || winLineEmitted { return true }   // 同じ勝敗文の再読では出さない
        let oppGaveUp = t.contains("相手") || t.contains("あいて")
        forfeitName = oppGaveUp ? (trainerOpp.isEmpty ? "Opponent" : trainerOpp) : (trainerMine.isEmpty ? "You" : trainerMine)
        emitPendingFaints()
        emitLog("|win|\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        winLineEmitted = true
        if !flagManualMode {
            winLogged = true
            archiveCurrentBattle(final: true)
        }
        return true
    }
    // 無操作による対戦終了: 「相手の操作がありませんでした！対戦を終了します！」
    // (実例: 2026-11-20 vs Foxy2905 戦。勝敗文が無いため従来は未保存のまま
    // 終わり、保存も送信もされなかった)。操作しなかった側の負けとして扱う。
    // OCR では文頭に「あいてそうさ」のような重なりゴミが付くことがあるため、
    // 「操作がありません」に部分一致で判定し、どちらの無操作かは
    // 相手/あいて・自分/じぶん の有無で分ける。判別できない場合も
    // 対戦終了として確定保存だけは行う (勝敗行は出さない)
    if t.contains("操作がありません") || (t.contains("対戦を終了します") && t.contains("操作")) {
        if winLogged || winLineEmitted { return true }
        let oppIdle = t.contains("相手") || t.contains("あいて")
        let mineIdle = t.contains("自分") || t.contains("じぶん")
        emitPendingFaints()
        if oppIdle && !mineIdle {
            forfeitName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
            emitLog("|win|\(trainerMine.isEmpty ? "p1" : trainerMine)")
            winLineEmitted = true
            if !flagManualMode { winLogged = true }
        } else if mineIdle && !oppIdle {
            forfeitName = trainerMine.isEmpty ? "You" : trainerMine
            emitLog("|win|\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            winLineEmitted = true
            if !flagManualMode { winLogged = true }
        }
        if !flagManualMode { archiveCurrentBattle(final: true) }
        return true
    }
    // 急所: 「(相手の) Xの 急所に 当たった！」
    // 「急所」は OCR で「還所」「意所」等に崩れるため、「所に当たった」で
    // 判定する (実例: 2026-11-20 の対戦で 2 件とも日本語のまま漏れた)。
    // 対象は文中の種族名を優先する (範囲技では最後に被弾した枠と急所の
    // 対象が食い違うことがあるため)。種族が取れない場合だけ従来通り
    // 直近にダメージを受けた (受けつつある) 枠に付ける
    if (t.contains("急所に") || t.contains("所に") || t.hasSuffix("に当たった！") || t.hasSuffix("に当たった!") || t.hasSuffix("にたった！") || t.hasSuffix("にたった!") || t.hasSuffix("に当たつた！") || t.hasSuffix("にたつた！")) && (t.contains("当たった") || t.contains("たった") || t.contains("当たつた") || t.contains("たつた")) {
        var target = ""
        // 種族名が崩れている場合は緩い照合も試す (場にいる種族に限る)
        var critEntry = findSpeciesJa(in: t)
        if critEntry == nil, let loose = findSpeciesJaLoose(in: t) {
            let anch = fieldAnchoredSpecies(loose.entry)
            if lastSlots.values.contains(where: { $0.speciesEn == anch.en }) { critEntry = loose.entry }
        }
        if let csp = critEntry {
            let anch = fieldAnchoredSpecies(csp)
            let cside: String
            if t.contains("相手の") || t.contains("あいての") { cside = "p2" }
            else if t.contains("味方の") || t.contains("じぶんの") { cside = "p1" }
            else {
                let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
                let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
                cside = inOpp && !inMine ? "p2" : "p1"
            }
            target = "\(slotFor(side: cside, speciesEn: anch.en)): \(anch.en)"
        }
        if target.isEmpty {
            target = !lastPendingLabel.isEmpty ? lastPendingLabel
                : (sNow().timeIntervalSince(lastDamageAt) < 6 ? lastDamageLabel : "")
        }
        // 同じ急所文の再読で二重に出さない (枠ごとに 6 秒あける)
        if !target.isEmpty && sNow().timeIntervalSince(lastCritAt[target] ?? .distantPast) > 6 {
            lastCritAt[target] = sNow()
            critEventMarks[target] = (turn: currentTurn, atk: lastMoveLabel)
            // 急所の告知文は被ダメ行より後に来るため、記録時点では
            // dmg イベントの crit が false のまま残る。対象の直近の
            // イベントを是正する (実例: 2026-11-22
            // battle_20261122_070237 ターン2、プロトコルには急所行が
            // あるのにイベントは crit=false だった)
            var critAtkJson = jsonEscape(lastMoveLabel)
            var critMoveJson = jsonEscape(lastMoveName)
            if let idx = battleEvents.lastIndex(where: { ev in
                ev.contains("\"k\":\"dmg\"") && ev.contains("\"def\":\"\(jsonEscape(target))\"")
                    && !ev.contains("\"atk\":\"\(jsonEscape(target))\"")
            }) {
                let ev = battleEvents[idx]
                if let r = ev.range(of: "\"atk\":\""), let e = ev[r.upperBound...].firstIndex(of: "\"") {
                    critAtkJson = String(ev[r.upperBound..<e])
                }
                if let r = ev.range(of: "\"move\":\""), let e = ev[r.upperBound...].firstIndex(of: "\"") {
                    critMoveJson = String(ev[r.upperBound..<e])
                }
                if ev.contains("\"crit\":false") {
                    battleEvents[idx] = ev.replacingOccurrences(of: "\"crit\":false", with: "\"crit\":true")
                }
            }
            // 急所の確定は独立イベントとしても末尾へ追加する。是正は
            // 既に消費された写しには届かない (UI はイベント列を
            // インデックス単位で一度だけ消費する) ため、後付けで
            // 証拠を届ける経路が要る (実例: 2026-11-22
            // battle_20261122_201011、急所 2 件とも消費済みで是正が
            // 届かず、エンジンに急所が伝わらなかった)
            if battleEvents.count < 600 {
                battleEvents.append("{\"k\":\"crit\",\"turn\":\(currentTurn),\"atk\":\"\(critAtkJson)\",\"def\":\"\(jsonEscape(target))\",\"move\":\"\(critMoveJson)\"}")
            }
            emitLog("|-crit|\(target)")
        }
        return true
    }
    // 技の失敗: 「しかし うまく決まらなかった！」。裸の |-fail| では
    // 誰の失敗か記録から復元できないため、直前の技の使用者を主体に
    // 付ける (この文は失敗した行動の直後にしか出ない。実例:
    // 2026-11-21 battle_20261121_230402 ターン5、帰属が逆に読めた)
    if t.contains("うまく決まらなかった") {
        if !lastMoveLabel.isEmpty && sNow().timeIntervalSince(lastMoveMsgAt) < 8 {
            emitLog("|-fail|\(lastMoveLabel)")
        } else {
            emitLog("|-fail|")
        }
        return true
    }
    // メガシンカの反応 (ストーンと相手トレーナー名がここで判明する)。
    // ストーンは「<種族>の<ストーン>と」の構造から切り出して完全一致で照合する
    // (部分一致の最長マッチだとキーアイテム名などと競合しうるため)
    // 「反応した」は OCR で「受応した」と崩れることがある (実例:
    // 2026-11-20 vs leslie 戦。崩れた文は |-message| に漏れていた)
    // 「反応した」の「反」は OCR で 受/設 などにも崩れるため、「応した」
    // で拾う (実例: 2026-11-22 battle_20261122_050512、「設応した」と
    // 崩れて反応文として扱われず、メガ行にストーンが付かなかった)
    if t.contains("応した") && (t.contains("リングが") || t.contains("ナイト")) {
        // 「リングが」を含む形が基本だが、相手のメガでは末尾の語が
        // 読み落ちて「<種族>の<ストーン>と <相手>の 反応した！」だけが
        // 残ることがある (実例: 2026-11-21 battle_20261121_230402、
        // ライチュウのライチュウナイトX)。その場合は、ストーン名が
        // 辞書で引けた場合に限って反応文として扱い、引けない場合は
        // 消費せず後段 (証拠として |-message|) に委ねる
        var stoneResolved = false
        // 種族はまずストーン名から引く。ストーン名は種族名の途中までを
        // 含むことがあり (リザードナイトY に対する リザードン)、文中の
        // 種族名を素直に検索すると別の種族に誤認する (リザード =
        // Charmeleon。実例: 2026-11-21 battle_20261121_234913、
        // 場にいない Charmeleon の持ち物行が出た)。英語名は
        // 「<種族>ite (X/Y)」の形で機械的なため、そちらから引く
        var megaSp: SpeciesEntry? = nil
        var megaStoneJa: String? = nil
        if let sJa = findInDict(in: t, itemDict), sJa.contains("ナイト"), let sEn = itemJa2En[sJa] {
            megaStoneJa = sJa
            var baseEn = sEn
            for suf in ["ite X", "ite Y", "ite"] where baseEn.hasSuffix(suf) {
                baseEn = String(baseEn.dropLast(suf.count)); break
            }
            megaSp = speciesDict.first(where: { $0.en == baseEn })
        }
        if megaSp == nil { megaSp = findSpeciesJa(in: t) }
        if let sp = megaSp {
            let side = megaTextSide(t, baseEn: sp.en)
            // 完了済みのメガの反応文が再読された場合は、持ち物行や保留を
            // 出し直さない (実例: 2026-11-21 vs Toshiro 戦、終盤に
            // カメックスのストーン反応が再読され |-item| が漏れた)
            if let ms = monStates["\(side):\(sp.en)"]?.megaSpecies, !ms.isEmpty { return true }
            // 完了判定はファミリー単位でも行う: 名前側が崩れて別種族に
            // 解決された再読 (リザードン → リザード = Charmeleon) では
            // 解決先のキーに完了記録が無く素通りし、誤った種族の
            // 持ち物行が出る (実例: 2026-11-22 battle_20261122_051707)
            if monStates.contains(where: { $0.key.hasPrefix("\(side):") && sameSpeciesFamily(String($0.key.dropFirst(3)), sp.en) && !($0.value.megaSpecies ?? "").isEmpty }) { return true }
            if monStates["\(side):\(sp.en)"] == nil { monStates["\(side):\(sp.en)"] = MonState() }
            if let itJa = megaStoneJa {
                stoneResolved = true
                let ml1 = megaLabelSpecies(side: side, speciesEn: sp.en)
                emitItemOnce(slot: ml1.slot, side: side, speciesEn: ml1.speciesEn, itemJa: itJa)
                pendingMegaStone[side] = itJa
                pendingMegaSpecies[side] = sp.en
            } else if let r = t.range(of: sp.ja + "の") {
                // ストーンの切り出しは生テキストで行う (正規化すると助詞の「と」と
                // 「〜ナイト」の「ト」が区別できなくなるため)
                let stoneCand = String(t[r.upperBound...].prefix(while: { $0 != "と" }))
                if let itJa = itemDict[normalize(stoneCand)] {
                    stoneResolved = true
                    // ストーンが特定できたら、種族は文中の名前ではなく
                    // ストーンから引き直す。名前側が崩れていると
                    // (リザードン → リザード)、誤った種族の持ち物行に
                    // なる (実例: 2026-11-22 battle_20261122_051707、
                    // Charmeleon の Charizardite Y 行)
                    var useSp = sp
                    var useSide = side
                    if let sEn = itemJa2En[itJa] {
                        var baseEn = sEn
                        for suf in ["ite X", "ite Y", "ite"] where baseEn.hasSuffix(suf) {
                            baseEn = String(baseEn.dropLast(suf.count)); break
                        }
                        if let stoneSp = speciesDict.first(where: { $0.en == baseEn }) {
                            useSp = stoneSp
                            useSide = megaTextSide(t, baseEn: stoneSp.en)
                        }
                    }
                    let ml2 = megaLabelSpecies(side: useSide, speciesEn: useSp.en)
                    emitItemOnce(slot: ml2.slot, side: useSide, speciesEn: ml2.speciesEn, itemJa: itJa)
                    pendingMegaStone[useSide] = itJa
                    pendingMegaSpecies[useSide] = useSp.en
                }
            }
        }
        if stoneResolved || t.contains("リングが") { return true }
    }
    // メガシンカの完了: 状態をメガ種族に切り替える (キーはベース種族のまま。
    // プレートや技メッセージの名前表記はメガ後もベース名のため)
    if t.contains("メガシンカした") {
        let megaEntry = speciesDict.filter { $0.ja.hasPrefix("メガ") && nt.contains(normalize($0.ja)) }
            .max(by: { $0.ja.count < $1.ja.count })
        if let me = megaEntry {
            var baseEn = me.en
            if let r = baseEn.range(of: "-Mega") { baseEn = String(baseEn[..<r.lowerBound]) }
            let side = megaTextSide(t, baseEn: baseEn)
            completeMega(side: side, baseEn: baseEn, megaEn: me.en)
        }
        return true
    }
    // 繰り出し (相手): 場の左右はプレートが決めるため、ここでは登録だけ行う
    if t.contains("繰り出した") {
        if !flagManualMode && (!logStarted || winLogged) { startBattleLog() }
        if trainerOpp.isEmpty, let r = t.range(of: "は") {
            let name = String(t[..<r.lowerBound])
            if !name.isEmpty && name.count <= 20 { trainerOpp = name }
        }
        for e in findAllSpeciesJa(in: t) {
            if monStates["p2:\(e.en)"] == nil { monStates["p2:\(e.en)"] = MonState() }
            // 途中交代の繰り出し文も文証拠として残す: フェーズ3の文
            // 証拠は ゆけっ 形式だけが対象で、相手の交代が「繰り出した」
            // 形式だとプレート回復後の確定加速が働かなかった (実例:
            // 2026-11-22 battle_20261122_160927、ゴリランダーの交代文
            // からプレート確定まで約 35 秒かかり、従属行が次の
            // セグメントへずれた)
            if logStarted, oppTeamSeen.contains(e.en),
               lastSlots["oppA"]?.speciesEn != e.en, lastSlots["oppB"]?.speciesEn != e.en {
                sendOutTextSeen["p2"] = (species: e.en, at: sNow())
            }
        }
        return true
    }
    // おちゃかい (ヤバソチャの特性): 「相手のヤバソチャが たてた
    // お茶を <相方>は 飲みほした！」(2 行構成。ボックス結合で語順が
    // 崩れて届くこともある)。特性行を出し、回復の発生源を相方へ
    // 控える (プレートの上昇を |-heal| として採用するため。実例:
    // 2026-11-23 battle_20261123_090354、文が |-message| に落ちて
    // 回復行が出ず、後続の低下まで欠落した)
    if t.contains("お茶") && (t.contains("飲みほした") || t.contains("飲み干した") || t.contains("のみほした")) {
        let named = findAllSpeciesJa(in: t)
        let sinistcha = named.first(where: { $0.en == "Sinistcha" })
            ?? lastSlots.values.first(where: { $0.speciesEn == "Sinistcha" }).map { s in
                speciesDict.first(where: { $0.en == s.speciesEn })
            } ?? nil
        if let sc = sinistcha {
            let side = (lastSlots["oppA"]?.speciesEn == sc.en || lastSlots["oppB"]?.speciesEn == sc.en) ? "p2" : "p1"
            let names = side == "p2" ? ["oppA", "oppB"] : ["mineA", "mineB"]
            let scSlot = names.first(where: { lastSlots[$0]?.speciesEn == sc.en }).map { slotId($0) }
            let allyName = names.first(where: { lastSlots[$0]?.speciesEn != sc.en && lastSlots[$0] != nil })
            if let scSlot, let allyName, let ally = lastSlots[allyName] {
                emitAbilityOnce(slot: scSlot, side: side, speciesEn: sc.en, abilityEn: "Hospitality")
                pendingHealFrom["\(side):\(ally.speciesEn)"] = ("ability: Hospitality", sNow())
                return true
            }
        }
    }
    // 繰り出し (自分): 「ゆけっ！ A！ B！」の並び順 = 場の左右 (実機で確認)。
    // Vision は小さい「っ」を「つ」と読むことが多いため両方を拾う
    if t.contains("ゆけっ") || t.contains("ゆけつ") {
        if !flagManualMode && (!logStarted || winLogged) { startBattleLog() }
        // 先発の登録は対戦開始時だけ。途中交代の繰り出し文をここで処理すると
        // 「並び順 = 左右」の前提で誤った枠に |switch| を出してしまう
        // (実例: 2026-11-20、イエッサンの交代要員オオニューラが p1a に
        // 誤登録され、プレート確定の p1b と合わせて "Go! Sneasler!" が
        // 二重に出た)。途中交代はプレート側 (2 フレーム確定) が正しい
        // 枠で記録するため、文は消費するだけにする
        if lastSlots["mineA"] != nil && lastSlots["mineB"] != nil {
            // 途中交代の繰り出し文は、プレート確定を早める文証拠として
            // 残す (フェーズ3)。枠そのものはプレート読みが決める
            if let e = findSpeciesJa(in: t) {
                let inOppOnly = oppTeamSeen.contains(e.en) && teamEntries[e.en] == nil
                    && !battleMineTeam.contains(where: { $0?.species == e.en })
                let evSide = inOppOnly ? "p2" : "p1"
                let onFieldNow = evSide == "p1"
                    ? (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en)
                    : (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en)
                if !onFieldNow { sendOutTextSeen[evSide] = (species: e.en, at: sNow()) }
            }
            return true
        }
        var found = findAllSpeciesJa(in: t)
        // 性別・リージョンフォルムは登録チームと突き合わせて確定させる
        found = found.map { e in
            let grp = formeGroup(e)
            if grp.count > 1 {
                let inTeam = grp.filter { teamEntries[$0.en] != nil }
                if inTeam.count == 1 { return inTeam[0] }
            }
            return e
        }
        for e in found.prefix(2) {
            if monStates["p1:\(e.en)"] == nil { monStates["p1:\(e.en)"] = MonState() }
            // 文が 1 体ずつ届く場合、並び順の決め打ちでは 2 体目が
            // 先発の枠 (mineA) へ重なり、誤った枠の交代行と、プレート
            // 確定時の二重の交代行を生む (実例: 2026-11-22
            // battle_20261122_091721、ブリジュラスが p1a に出て、
            // 先発の交代行が二重になった)。登録済みの種族は飛ばし、
            // 空いている枠の若い方へ割り当てる
            if lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en { continue }
            let plateName = lastSlots["mineA"] == nil ? "mineA" : "mineB"
            if lastSlots[plateName]?.speciesEn != e.en {
                let pct = monStates["p1:\(e.en)"]?.hpPercent ?? 100
                lastSlots[plateName] = SlotState(speciesEn: e.en, hpPercent: pct)
                lastEmittedPct[plateName] = pct
                var hp = monStates["p1:\(e.en)"]!.hpText
                if let st = monStates["p1:\(e.en)"]?.status, !st.isEmpty { hp += " \(st)" }
                emitLog("|switch|\(slotId(plateName)): \(e.en)|\(e.en)|\(hp)")
                recordSwitchIn(side: "p1", slot: slotId(plateName), speciesEn: e.en)
            }
        }
        return !found.isEmpty
    }
    // 天候・フィールドの開始/終了 (種族名が無くても拾う)。
    // 状態が変化した文はフィールドの告知として消費する
    // 天候・フィールドの告知文は、状態が変わらなかった (再読だった) 場合も消費する
    if checkFieldText(text: t) { return true }
    // あくびで眠気を誘った文 (対象は次のターン終了時に眠る)。文中で
    // 対象が特定できる場合は、効果の開始行 (|-start|) も記録する
    // (実例: 2026-11-22 battle_20261122_054802、あくびの効果行が
    // 一切なく、対象も特定できなかった)。特定できない場合は
    // 従来どおり消費だけする
    if (t.contains("眠気") || t.contains("ねむけ")) && (t.contains("誘った") || t.contains("誘つた") || t.contains("さそった") || t.contains("さそつた")) {
        if lastMoveName == "Yawn", let user = parseSlotSpecies(lastMoveLabel) {
            let targetPrefix = user.side == "p1" ? "opp" : "mine"
            let named = lastSlots.filter { plateName, s in
                plateName.hasPrefix(targetPrefix)
                    && (speciesDict.first { $0.en == s.speciesEn }.map { t.contains($0.ja) } ?? false)
            }
            if named.count == 1, let (plateName, s) = named.first {
                emitLog("|-start|\(slotId(plateName)): \(s.speciesEn)|move: Yawn")
            }
        }
        return true
    }
    // やどりぎのたねを植えつけた文 (吸収のダメージ/回復はプレート側で
    // 行が出るため、植えつけ自体は消費だけする)
    if t.contains("植えつけ") || t.contains("植え付け") { return true }
    // サイドコンディション (おいかぜ) の告知文: 種族名を含まないため、
    // 種族照合より前にここで処理する (実例: 2026-11-20 vs Zycloud 戦、
    // 「あいて相手にかぜおはし追い風が吹き始めた！」が日本語のまま漏れた)
    if t.contains("追い風") || t.contains("おいかぜ") {
        let scSide = (t.contains("相手") || t.contains("あいて")) ? "p2" : "p1"
        if t.contains("吹き始") || t.contains("ふきはじ") {
            let k = "\(scSide):Tailwind:start"
            if sNow().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = sNow()
                emitLog("|-sidestart|\(scSide)|move: Tailwind")
            }
            return true
        }
        if t.contains("止ん") || t.contains("やん") || t.contains("終わ") || t.contains("なくな") {
            let k = "\(scSide):Tailwind:end"
            if sNow().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = sNow()
                emitLog("|-sideend|\(scSide)|move: Tailwind")
            }
            return true
        }
    }
    // ワイドガードの持続告知: 「味方の周りを ワイドガードが
    // 守っている！」(種族名を含まない文)。設置は |-sidestart| で
    // 記録済みで、守られた対象は文から特定できないため消費だけする
    // (実例: 2026-11-21 battle_20261121_224409、崩れた再読が
    // 2 回 |-message| に残った)
    if t.contains("ワイドガード") && t.contains("守っている") { return true }
    // 効果の確認文・交代の指示文 (出来事そのものは別の行で記録済みのため、
    // 本文だけを |-message| に残さないよう消費する)
    // ワイドガードの文はここで消費しない (使用告知は後段の技使用として
    // |move| に、防御の確認文は種族固定後の |-activate| 分岐で処理する)。
    // 以前は確認文として一律に消費していたため使用告知まで巻き込まれ、
    // ワイドガードがログに一切出なかった
    // 「身を守った」もここで消費しない: まもるで防いだ際の確認文
    // (「<対象>は 攻撃から 身を守った！」) は、種族固定後の
    // |-activate| 分岐が記録するのが唯一の経路で、ここで消費すると
    // 防がれた技の解決行が残らなかった (実例: 2026-11-21
    // battle_20261121_224409、クチートのまもるに阻まれた
    // サイコキネシス)
    if !t.contains("ワイドガード") && (t.contains("手助けする") || t.contains("守られた") || t.contains("体勢に入った")
        || t.contains("戻れ") || t.contains("引っこめた") || t.contains("引っ込めた")
        || t.contains("引つこめた") || t.contains("引つ込めた")
        || t.contains("引っごめた") || t.contains("引つごめた")
        || (t.contains("引") && t.contains("こめた"))
        || t.contains("イリュージョンが解けた") || t.contains("イリュージョンがとけた")
        || (t.contains("ランク") && t.contains("級"))
        || ((t.contains("ゆけ") || t.contains("もどれ")) && findSpeciesJa(in: t) != nil)
        || t.contains("場所を入れ替えた")) {
        // 引っ込めた は OCR で「引つこめた」(っ->つ、込->こ) と崩れる
        // (実例: 2026-11-20 vs Ony 戦「Onyはコリランダーを引つこめた！」)
        // ラテン文字が混入する崩れ (「引Iっこめた」) もあるため、
        // 「引」と「こめた」の共起でも消費する (実例: 2026-11-20 vs leslie 戦)
        // 場所を入れ替えた はアリーバスイッチの結果文 (技そのものは |move| で記録済み)
        return true
    }
    // はたきおとすの持ち物喪失と、おみとおしの持ち物判明: どちらの文も
    // 主語は攻撃側・特性側で、持ち物の持ち主は文中に出るもう一方の種族
    // のため、通常の種族固定では持ち主を特定できない。「<持ち主>の
    // <持ち物>」の隣接した並びから持ち主と持ち物を切り出し、場の在席
    // から持ち主の側と枠を決めて記録する (実例: 2026-11-21 vs KAM 戦、
    // ハッサムのはたきおとすでイエッサン♀のゴツゴツメット喪失が、
    // おみとおしでサーナイトナイトの判明が、どちらもルールが無く
    // |-message| に落ちていた)
    if t.contains("はたき落とした") || t.contains("見通し") {
        var itemOwner: (item: String, owner: SpeciesEntry)? = nil
        if let it = findInDict(in: t, itemDict),
           let ow = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)の\(it)") }) {
            itemOwner = (it, ow)
        } else {
            // OCR 崩れ救済: 濁点・小書き仮名を畳んだ looseText 空間で
            // 持ち物名と「持ち主の持ち物」の並びを探す (実例:
            // 2026-11-21 battle_20261121_224409、ゴツゴツメットが
            // ゴッゴツメットに崩れて辞書照合できなかった)
            let lt = looseText(t)
            var bestIt: String? = nil
            for orig in itemDict.values {
                let lo = looseText(orig)
                if !lo.isEmpty && lt.contains(lo) && (bestIt == nil || orig.count > bestIt!.count) {
                    bestIt = orig
                }
            }
            if let it = bestIt,
               let ow = speciesDict.first(where: { !$0.ja.isEmpty && lt.contains(looseText("\($0.ja)の\(it)")) }) {
                itemOwner = (it, ow)
                recordDecode(stage: "loose", raw: t, resolved: it)
            }
        }
        if let (itJa, owner) = itemOwner {
            var anch = anchoredSpeciesForText(owner, text: t)
            // 名前表記は雌雄・フォルムで同一のため、場にいるフォルムへ寄せる
            if !lastSlots.values.contains(where: { $0.speciesEn == anch.en }),
               let onField = formeGroup(anch).first(where: { e in lastSlots.values.contains { $0.speciesEn == e.en } }) {
                anch = onField
            }
            let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
            let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
            var ownerSide: String? = nil
            if inMine != inOpp { ownerSide = inOpp ? "p2" : "p1" }
            else if let subj = findSpeciesJa(in: t), subj.en != anch.en {
                // 持ち主が場で定まらない場合は、主語 (攻撃側・特性側) の
                // 反対側とみなす
                let sInMine = lastSlots["mineA"]?.speciesEn == subj.en || lastSlots["mineB"]?.speciesEn == subj.en
                let sInOpp = lastSlots["oppA"]?.speciesEn == subj.en || lastSlots["oppB"]?.speciesEn == subj.en
                if sInMine != sInOpp { ownerSide = sInOpp ? "p1" : "p2" }
                else if t.contains("相手の") || t.contains("あいての") { ownerSide = "p1" }
            }
            if let oside = ownerSide {
                let oslot = slotFor(side: oside, speciesEn: anch.en)
                if monStates["\(oside):\(anch.en)"] == nil { monStates["\(oside):\(anch.en)"] = MonState() }
                emitItemOnce(slot: oslot, side: oside, speciesEn: anch.en, itemJa: itJa)
                if t.contains("はたき落とした") {
                    noteItemLost(slot: oslot, side: oside, speciesEn: anch.en)
                }
                // おみとおしの文は、主語 (特性の持ち主) の特性判明でもある。
                // 判明を記録すると、特性からフォルムを訂正する処理が
                // 必要に応じて働く (バクフーン → ヒスイの判別など)
                if t.contains("見通し"), let subj = findAllSpeciesJa(in: t).first(where: { $0.en != anch.en }) {
                    let sAnch = anchoredSpeciesForText(subj, text: t)
                    let sInMine = lastSlots["mineA"]?.speciesEn == sAnch.en || lastSlots["mineB"]?.speciesEn == sAnch.en
                    let sInOpp = lastSlots["oppA"]?.speciesEn == sAnch.en || lastSlots["oppB"]?.speciesEn == sAnch.en
                    let subjSide: String
                    if sInMine != sInOpp { subjSide = sInOpp ? "p2" : "p1" }
                    else { subjSide = oside == "p1" ? "p2" : "p1" }   // おみとおしは相手の道具を見るため、主語は持ち主の反対側
                    emitAbilityOnce(slot: slotFor(side: subjSide, speciesEn: sAnch.en), side: subjSide, speciesEn: sAnch.en, abilityEn: "Frisk")
                }
                return true
            }
        }
    }
    // はたきおとすの持ち物名が OCR 崩れで辞書照合できなかった場合の
    // 受け皿 (上の分岐は持ち物名が読めることが前提)。「<持ち主>の」
    // の隣接から持ち主を特定し、判明済みの持ち物で喪失を記録する。
    // 判明が無ければ喪失の事実だけを記録する (実例: 2026-11-21
    // battle_20261121_224409、ゴツゴツメットがゴッゴツメットに
    // 崩れて文が |-message| に残った)
    if t.contains("はたき落とした") {
        // 持ち主は「<種族>の」に続き、主語 (攻撃側) は「<種族>は」に続く
        if let owner = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)の") && !t.contains("\($0.ja)は") }) {
            var anch = anchoredSpeciesForText(owner, text: t)
            if !lastSlots.values.contains(where: { $0.speciesEn == anch.en }),
               let onField = formeGroup(anch).first(where: { e in lastSlots.values.contains { $0.speciesEn == e.en } }) {
                anch = onField
            }
            let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
            let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
            var ownerSide: String? = nil
            if inMine != inOpp { ownerSide = inOpp ? "p2" : "p1" }
            else if let subj = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)は") }), subj.en != anch.en {
                let sInMine = lastSlots["mineA"]?.speciesEn == subj.en || lastSlots["mineB"]?.speciesEn == subj.en
                let sInOpp = lastSlots["oppA"]?.speciesEn == subj.en || lastSlots["oppB"]?.speciesEn == subj.en
                if sInMine != sInOpp { ownerSide = sInOpp ? "p1" : "p2" }
                else if t.contains("相手の") || t.contains("あいての") { ownerSide = "p1" }
            }
            if let oside = ownerSide {
                let oslot = slotFor(side: oside, speciesEn: anch.en)
                if monStates["\(oside):\(anch.en)"] == nil { monStates["\(oside):\(anch.en)"] = MonState() }
                let knownItem = oside == "p1" ? (teamEntries[anch.en]?["item"] as? String) : revealedItems[anch.en]
                if let knownItem { emitItemOnce(slot: oslot, side: oside, speciesEn: anch.en, itemJa: knownItem) }
                noteItemLost(slot: oslot, side: oside, speciesEn: anch.en)
                return true
            }
        }
    }
    var sp = findSpeciesJa(in: t)
    var looseMoveStart: Int? = nil
    if sp == nil, let l = findSpeciesJaLoose(in: t) {
        sp = l.entry
        looseMoveStart = l.moveStart
    }
    // フィールドに守られた文の断片 (種族名が欠けて解決できない場合):
    // 対象は特定できないが、フィールドの裏付けだけ取って消費する
    // (実例: 2026-11-20 vs Ony 戦「クスはサイコフィールドに守られている！」が
    //  日本語のまま漏れた。通常形は種族解決後の「守られている」分岐が処理する)
    if sp == nil && t.contains("守られている") {
        for (ja, en) in [("サイコフィールド", "Psychic"), ("エレキフィールド", "Electric"), ("グラスフィールド", "Grassy"), ("ミストフィールド", "Misty")] where t.contains(ja) {
            setTerrain(en, via: t)
            break
        }
        return true
    }
    // 回復の告知文の断片 (種族名が解決できない場合): 回復そのものは
    // プレート側で |-heal| を出すため、文は消費するだけにする
    // (実例: 2026-11-20「シャンデラのかいふく袱力か回復した！」等の漏れ)
    if sp == nil && t.contains("回復した") { return true }
    // ランク変化文の後半の断片 (主語が無く、上がった/下がっただけの
    // 文): 直前に覚えた断片 (主語+能力名) と結合して適用する
    // (実例: 2026-11-22 battle_20261122_091721 ターン4)
    if sp == nil, let frag = prevBoostFragment, sNow().timeIntervalSince(frag.at) < 6,
       (t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
        || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた")) {
        checkBoostText(text: frag.text + t, side: frag.side, speciesEn: frag.speciesEn,
                       slot: slotFor(side: frag.side, speciesEn: frag.speciesEn))
        prevBoostFragment = nil
        return true
    }
    guard var sp else { return battleLog.count > before }
    // 緩い照合は場にいない種族を掴むことがある (実例: 2026-11-20 vs Mark 戦、
    // イエッサンの てだすけ の再読が サンド の てだすけ と誤記録された)。
    // プレートで場の種族が分かっているときは、緩い照合の結果 (フォルム違いを
    // 含む) が場にいなければ採用しない。完全一致の結果には適用しない
    if looseMoveStart != nil && !lastSlots.isEmpty {
        let onField = Set(lastSlots.values.map { $0.speciesEn })
        let grp = Set(formeGroup(sp).map { $0.en })
        if !onField.contains(sp.en) && onField.isDisjoint(with: grp) { return battleLog.count > before }
    }
    // フォルム表記を場の状態に寄せる (メッセージの名前は雌雄で同一のため、
    // 寄せないと技の判明などが基本フォルム側に記録されてしまう)。
    // 「相手の」の手がかりがある場合は相手側のフォルムを優先する
    sp = anchoredSpeciesForText(sp, text: t)
    // 左右: 「相手の」等の前置きを優先し、無ければ場のプレートから推定する。
    // ただし、その種族が片方の場にだけ実在する場合は場の側を正とする
    // (前置きの OCR 崩れや古い文の再処理で、自分のポケモンが「相手の」
    // として技・ひんしを二重に記録された実例: 2026-11-20 グレンアルマ)
    let inMine = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en
    let inOpp = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
    var side: String
    if t.contains("相手の") || t.contains("あいての") { side = "p2" }
    else if t.contains("味方の") || t.contains("じぶんの") { side = "p1" }
    else { side = inOpp && !inMine ? "p2" : "p1" }
    if inMine != inOpp { side = inOpp ? "p2" : "p1" }
    // オーラ特性の告知: 「(相手の) <種族>は <オーラ名>を 放っている！」
    // (フェアリーオーラ/ダークオーラ/オーラブレイク。場に出た直後に
    //  表示される)。従来はこの形の分岐自体が無く、読み重なりの崩れで
    //  帰属も決まらないまま |-message| に落ち、特性が最後まで記録
    //  されなかった (実例: 2026-11-21 battle_20261121_161334、
    //  「あいて相手のフラエッテははなフェアリーオーラを放っている！」)。
    //  オーラ名と「放って」の併存はこの告知にしか現れないため、
    //  崩れに強い部分一致で拾う
    if t.contains("放って") && (t.contains("オーラを") || t.contains("オーラブレイク")) {
        let auras: [(String, String)] = [("フェアリーオーラ", "Fairy Aura"), ("ダークオーラ", "Dark Aura"), ("オーラブレイク", "Aura Break")]
        if let aura = auras.first(where: { t.contains($0.0) }) {
            let aslot = slotFor(side: side, speciesEn: sp.en)
            emitAbilityOnce(slot: aslot, side: side, speciesEn: sp.en, abilityEn: aura.1)
            return true
        }
    }
    // 救済登録: 種族が確実に解決できた (緩い照合ではない) のに、その側の
    // 場にいない場合、その側の空き枠がちょうど 1 つだけなら、その枠へ
    // 繰り出しとして登録してから帰属させる。プレート未確定 (遮蔽・OCR
    // 失敗) でも、文という強い証拠から場の構成を復元し、後続の文が
    // 既定枠 (a 枠) へ誤帰属されるのを防ぐ (実例: 2026-11-21
    // battle_20261121_132153、イエッサン♀のプレートが全試合未確定で、
    // 文がすべて p1a のオオニューラに帰属した)。自軍はチーム登録、
    // 相手は選出同定の範囲と矛盾する場合は登録しない (範囲が未取得の
    // 場合は矛盾とみなさない)。フォルム違いは登録済みフォルムに寄せる
    if looseMoveStart == nil {
        let onSide = side == "p1" ? inMine : inOpp
        if !onSide {
            let allowed: Set<String> = side == "p1" ? Set(teamEntries.keys) : Set(oppTeamSeen)
            var candidate: SpeciesEntry? = nil
            if allowed.isEmpty || allowed.contains(sp.en) { candidate = sp }
            else if let sib = formeGroup(sp).first(where: { allowed.contains($0.en) }) { candidate = sib }
            if let cand = candidate {
                let names = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
                // 空き枠: プレート未登録の枠に加え、前任がひんし済みの
                // 枠も空きとみなす (ひんし済みの枠には交代要員しか
                // 入らないため、行き先は一意に決まる。実例: 2026-11-21
                // battle_20261121_230402、ひんししたイエッサン♀の枠が
                // 「占有中」のまま残り、エルフーンの交代が登録されず
                // アンコールが p1a へ誤帰属された)
                let empty = names.filter { name in
                    if lastSlots[name] == nil { return true }
                    return faintedSlots[slotId(name)] != nil && lastSlots[name]?.speciesEn != cand.en
                }
                if empty.count == 1 {
                    let plateName = empty[0]
                    let rslot = slotId(plateName)
                    // 再登場の場合は前回出場時の HP で入る (新規は満タン)
                    let rkey = "\(side):\(cand.en)"
                    let pct = monStates[rkey]?.hpPercent ?? 100
                    let hpText = monStates[rkey]?.hpText ?? "\(pct)/100"
                    lastSlots[plateName] = SlotState(speciesEn: cand.en, hpPercent: pct)
                    lastEmittedPct[plateName] = pct
                    faintedSlots.removeValue(forKey: rslot)
                    if side == "p2" { updateOppTeam() }
                    emitLog("|switch|\(rslot): \(cand.en)|\(cand.en)|\(hpText)")
                    recordSwitchIn(side: side, slot: rslot, speciesEn: cand.en)
                    print("[log] 文から場を復元しました: \(rslot) に \(cand.en) を繰り出しとして登録 (プレート未確定の救済)")
                    fflush(stdout)
                    sp = cand
                }
            }
        }
    }
    // デフォルト帰属の繰り返しの記録: 確実に解決できた種族が、その側の
    // 場におらず、救済登録 (空き枠が 1 つの場合) も発動しなかった場合、
    // 文は既定枠 (a 枠) へ無言で帰属される。交代の取りこぼしで枠状態が
    // 古いままだと、これが何ターンも続いて内部矛盾 (同じ枠から 2 つの
    // 技行) の原因になる (実例: 2026-11-21 battle_20261121_150535、
    // イエッサン♀への交代が取りこぼされ、エルフーンのままの p1a へ
    // 3 ターン帰属が続いた)。2 回目で証拠を残す。古い枠への自動登録は
    // しない (どちらの枠が古いか文だけでは判別できず、正しい占有者を
    // 消す危険があるため)
    if looseMoveStart == nil {
        let onSideNow = side == "p1"
            ? (lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en)
            : (lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en)
        if !onSideNow {
            let ckey = "\(side)|\(sp.en)"
            defaultAttribCount[ckey, default: 0] += 1
            if defaultAttribCount[ckey] == 2 {
                let names = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
                if debugMode {
                    print("[log] 場にいない種族の文が繰り返し既定枠へ帰属されています: \(sp.en) (\(side)) — 現在の枠状態: \(names.map { "\($0)=\(lastSlots[$0]?.speciesEn ?? "（空き）")" }.joined(separator: ", "))")
                    fflush(stdout)
                }
                debugCapture(kind: "default_attribution", key: "default_attribution:\(side):\(sp.en)", rawText: t,
                             detail: ["species": sp.en, "side": side, "count": 2, "turn": currentTurn,
                                      "slots": names.map { lastSlots[$0]?.speciesEn ?? "" }, "text": t])
            }
        }
    }
    let slot = announcedSlot(side: side, speciesEn: sp.en)
    let key = "\(side):\(sp.en)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // ゴツゴツメット: 接触技で攻撃した側が受ける反動ダメージの予告。
    // ダメージ行に [from] item: Rocky Helmet を付けるため記録だけする
    // (人間可読ログ側の -damage 描画でも発生源として表示する)
    if t.contains("ゴツゴツメット") && t.contains("ダメージを受けた") {
        pendingStatusFrom[key] = ("item: Rocky Helmet", sNow())
        return true
    }
    // 状態異常などのダメージ予告: ダメージ行に [from] を付けるため記録だけする
    if t.contains("ダメージを受けた") {
        // 技の反動: 直前の技の使用者自身の文なら、発生源を控えて
        // 反動の低下行に [from] を付ける (実例: 2026-11-22
        // battle_20261122_193243、ウッドハンマーの反動文が消費
        // されるだけで、低下が訂正吸収されて行が残らなかった)
        if t.contains("反動"), lastMoveLabel == "\(slot): \(sp.en)", !lastMoveName.isEmpty {
            pendingStatusFrom[key] = ("move: \(lastMoveName)", sNow())
            return true
        }
        for (ja, code) in [("毒", "psn"), ("やけど", "brn"), ("砂嵐", "sandstorm"), ("あられ", "hail")] where t.contains(ja) {
            pendingStatusFrom[key] = (code, sNow())
            break
        }
        return true
    }
    // 天候チップの告知文 (実機文面は「すなあらしが Xを 襲う！」。
    // OCR では「すな砂あらし」と混ざって読まれることがある)
    if t.contains("襲う") || t.contains("おそう") {
        if t.contains("砂あらし") || t.contains("すなあらし") || t.contains("砂嵐")
            || t.contains("砂あら") || t.contains("すなあら") {
            pendingStatusFrom[key] = ("sandstorm", sNow())
            return true
        }
        if t.contains("あられ") {
            pendingStatusFrom[key] = ("hail", sNow())
            return true
        }
    }
    // 相性: 「(相手の) <対象>に 効果は いまひとつだ/バツグンだ/ないようだ」
    // (同じ文の再読で二重に出さないよう、枠+種別で 3 秒間抑止する)
    // OCR 崩れ (バツグン -> バッグン) に耐えるよう、小さい ッ/っ を寄せた形でも判定する
    let tk = t.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")
    // 「バツグン」が平仮名 (ばつぐん) で読まれた場合は正規化形でも判定する (検証 R1 #66)
    let ntk = nt.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")
    // バツグン自体の濁点ゆれ (パツグン/バツクン等) は畳んだ形でも判定する (検証 R3)。
    // 平仮名読み (ばつくん) は正規化形を畳んだものとも照合する (検証 vhard R9)
    let ftk = foldDakuten(tk)
    let kind = tk.contains("いまひとつ") ? "resisted" : (tk.contains("バツグン") || ntk.contains("バツグン") || ftk.contains("ハツクン") || foldDakuten(ntk).contains("ハツクン")) ? "supereffective" : tk.contains("ないようだ") ? "immune" : ""
    // 「効果は」が OCR で丸ごと脱落した文 (実例: 2026-11-21
    // battle_20261121_144858「伹手ユキメノコにパツグンだ！」) でも、
    // 末尾の相性語から種別が確定し、文が「だ」で終わる形なら同じ
    // 分岐で消費する。バツグン/いまひとつ/ないようだ は対戦中の
    // 告知ではこの文にしか現れないため、誤爆の心配は小さい
    if t.contains("効果は") || t.contains("こうかは") || (!kind.isEmpty && (t.hasSuffix("だ！") || t.hasSuffix("だ!") || t.hasSuffix("だ") || kind == "immune")) {
        if !kind.isEmpty {
            let ekey = "\(slot)|\(kind)"
            if let at = lastEffectAt[ekey], sNow().timeIntervalSince(at) < 3 { return true }
            lastEffectAt[ekey] = sNow()
            var effLabel = "\(slot): \(sp.en)"
            // 同じ技の解決中に、同じ対象へ別の相性の行が来たら、それは
            // 同じ技で被ダメして相性行がまだ無い別の対象の分とみなして
            // 付け替える (1 つの技が同じ対象に resisted と
            // supereffective の両方になることはない。実例: 2026-11-21
            // battle_20261121_234913、ねっぷうの相性 2 行が両方とも
            // フシギバナに付き、ガブリアスの分が消えた)。付け替え先が
            // 無い矛盾した行は出さない
            if let prevKind = effectBySeq[actionSeq]?[effLabel], prevKind != kind {
                if let other = (damagedBySeq[actionSeq] ?? []).first(where: { $0 != effLabel && effectBySeq[actionSeq]?[$0] == nil }) {
                    effLabel = other
                } else {
                    return true
                }
            }
            effectBySeq[actionSeq, default: [:]][effLabel] = kind
            emitLog("|-\(kind)|\(effLabel)")
            return true
        }
    }
    // フィールドに守られた (優先度技の無効化): フィールド状態の裏付けにもなる
    if t.contains("守られている") {
        for (ja, en) in [("サイコフィールド", "Psychic"), ("エレキフィールド", "Electric"), ("グラスフィールド", "Grassy"), ("ミストフィールド", "Misty")] where t.contains(ja) {
            setTerrain(en, via: t)
            emitLog("|-activate|\(slot): \(sp.en)|move: \(en) Terrain")
            return true
        }
        return true
    }
    // ミス: 「<対象>には 当たらなかった！」(使用者は直近の |move| の枠)
    if t.contains("当たらなかった") {
        if !lastMoveLabel.isEmpty && sNow().timeIntervalSince(lastMoveMsgAt) < 8 {
            // 外れの対象 (枠と種族) が場の記録と矛盾する場合は行を
            // 出さない (実例: 2026-11-22 battle_20261122_071457、
            // 場に出ていないガオガエンが p2a の外れ対象になった)。
            // 交代直後でプレート未確定の間は、交代記録の枠と一致
            // すれば通す
            let missPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            let missTracked = lastSlots[missPn]?.speciesEn
            let missConsistent = (missTracked.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[missPn] == sp.en
                || lastSwitchIn["\(side):\(sp.en)"]?.slot == slot
                // 交代直後でプレートの占有記録が追いついていない間は、
                // このターンの交代記録や交代候補の証拠でも通す
                // (実例: 2026-11-22 battle_20261122_201011、交代直後の
                // ゴリランダーへのミス文が、旧占有者の記録との不整合
                // として抑制された)
                || switchInTurn["\(side):\(sp.en)"] == currentTurn
                // 繰り出し文の証拠も、プレート経路とは独立に入場を
                // 裏付ける (実例: 2026-11-22 battle_20261122_231107、
                // 交代確定が要員選択のガードで落ち、候補も未形成の
                // 間に来たミス文には文証拠だけが残っていた)
                || (sendOutTextSeen[side].map { $0.species == sp.en && sNow().timeIntervalSince($0.at) < 20 } ?? false)
                || (pendingSwitchCandidates[side == "p2" ? "oppA" : "mineA"]?[sp.en] != nil)
                || (pendingSwitchCandidates[side == "p2" ? "oppB" : "mineB"]?[sp.en] != nil)
            if missConsistent {
                // 同じ外れ文の表記ゆれ再読で二重に出さない (行動+
                // 使用者+対象が同じものは 1 回だけ。実例:
                // 2026-11-23 battle_20261123_062508、リーフ
                // ストームの外れが 2 行出た)
                let missKey = "\(actionSeq)|\(lastMoveLabel)|\(slot)"
                if missKey != lastMissKey {
                    lastMissKey = missKey
                    emitLog("|-miss|\(lastMoveLabel)|\(slot): \(sp.en)")
                }
            } else {
                debugCapture(kind: "move_guard", key: "miss_target:\(slot):\(sp.en):\(currentTurn)", rawText: t,
                             detail: ["reason": "miss_target_inconsistent", "slot": slot, "species": sp.en, "tracked": missTracked ?? "", "turn": currentTurn])
            }
        }
        return true
    }
    // どくびしの吸収: 「<種族>は どくびしを 吸収した！」。接地した
    // どくタイプが場に出た際の告知で、その側の どくびしが消える。
    // 交代記録からの導出 (recordSwitchIn) が主経路で、こちらは
    // 文面が取れた場合の経路 (二重に出ても sideend は冪等)
    if t.contains("どくびし") && t.contains("吸収") {
        emitHazard(side, "Toxic Spikes", start: false)
        return true
    }
    // ワイドガードで守られた: 「<対象>は ワイドガードで 守られた！」
    // (まもられた の表記も拾う)。文中の ワイドガード を技の使用と
    // 誤読しないよう、技使用の解析より前にここで処理する
    if t.contains("ワイドガード") && (t.contains("守られ") || t.contains("まもられ")) {
        let pk = slot + "|wideguard"
        if let at = lastSingleActAt[pk], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = sNow()
        emitLog("|-activate|\(slot): \(sp.en)|move: Wide Guard")
        return true
    }
    // アンコールの効果: 「<対象>は アンコールを受けた！」。対象への
    // 効果行 (|-start|) として記録する。技の使用の解析より前に処理
    // しないと、文中の「アンコール」が対象自身の技使用として誤読
    // される (実例: 2026-11-21 battle_20261121_230402、エルフーンの
    // アンコールを受けたオオニューラに |move|Encore が付いた)
    if t.contains("アンコール") && t.contains("受けた") {
        emitLog("|-start|\(slot): \(sp.en)|move: Encore")
        return true
    }
    // 技の使用: 「(相手の) <種族>の <技>！」— <技> は種族名の直後から文末までと完全一致
    // 「たおれた」を含む文は技の告知ではあり得ない (ひんし文を技と誤読する
    // 事故の防止。検証 R5: カイリキーのひんし文から かいりき を誤検出)
    if let bangIdx = t.firstIndex(where: { $0 == "！" || $0 == "!" }),
       !String(t[...bangIdx]).contains("たおれた"), !foldDakuten(String(t[...bangIdx])).contains("たおれた") {
        // 告知文は最初の「！」までで切って扱う。文の後ろに録画表示
        // などの別要素の文字が続いた delivery では、末尾チェックが
        // 外れて技行が丸ごと落ちた (実例: 2026-11-22
        // battle_20261122_185505、「ムービー収録 リザードンの
        // ねっぷう！ 0 KB」で Charizard の Heat Wave が欠落)
        let at = String(t[...bangIdx])
        let ant = normalize(at)
        var cand: String? = nil
        // 長音落ちまで畳んだ変換 (種族名・技名とも全件衝突なしを確認済み)
        let deepFold: (String) -> String = { foldDakuten($0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")).replacingOccurrences(of: "ー", with: "") }
        if let r = ant.range(of: normalize(sp.ja + "の")) {
            cand = String(ant[r.upperBound...])
        } else if let r = foldDakuten(ant).range(of: foldDakuten(normalize(sp.ja + "の"))) {
            // 種族名が濁点ゆれで解決された場合 (アヤシシ→アヤシジ等) は、
            // 畳んだ形で位置を求めて元の文から切り出す (検証 R3 #35)
            let fnt = foldDakuten(ant)
            let off = fnt.distance(from: fnt.startIndex, to: r.upperBound)
            cand = String(ant[ant.index(ant.startIndex, offsetBy: off)...])
        } else if let r = deepFold(ant).range(of: deepFold(normalize(sp.ja + "の"))) {
            // 種族名の長音落ちまで重なった場合 (サーナイト→サナイト) は
            // 変換空間で切り出し、そのまま渡す (moveNameLoose 第3パスが
            // 同じ空間で照合する。検証 最終監査 seed32 vhard:
            // かみなりパンチ→かみなり の誤読対策)
            cand = String(deepFold(ant)[r.upperBound...])
        } else if let ms = looseMoveStart {
            // 種族名が OCR で崩れている場合は、緩い照合で得た位置から切り出す
            let chars = Array(ant)
            if ms <= chars.count { cand = String(chars[ms...]) }
        }
        var mvJaFound: String? = nil
        if let cand {
            let c = cand.trimmingCharacters(in: CharacterSet(charactersIn: "！!・"))
            mvJaFound = moveNameOrig[c] ?? moveNameLoose(c)
        }
        if mvJaFound == nil {
            // 種族名直後の切り出しに失敗した場合は、文中の技名を直接探す
            // (実例: 「あいてペンドラーの相手のつるぎのまい！」のように
            //  前置きが二重に化けた文でも、技名そのものは無事なことが多い。
            //  誤爆を避けるため、場にいる種族の文だけを対象にする)
            let onField = lastSlots.values.contains { $0.speciesEn == sp.en }
                || formeGroup(sp).contains { g in lastSlots.values.contains { $0.speciesEn == g.en } }
                || (fieldSeen[side]?.contains { sameSpeciesFamily($0, sp.en) } ?? false)
            if onField {
                // 種族名そのものと重なる技名は拾わない (カイリキー vs かいりき
                // のような種族名=技名の衝突。検証 R5 で検出)。技名は種族名の
                // 出現位置より後ろにあるものだけを候補にする
                var spEnd = 0
                if let r = ant.range(of: normalize(sp.ja)) {
                    spEnd = ant.distance(from: ant.startIndex, to: r.upperBound)
                } else if let r = foldDakuten(ant).range(of: foldDakuten(normalize(sp.ja))) {
                    let fnt = foldDakuten(ant)
                    spEnd = fnt.distance(from: fnt.startIndex, to: r.upperBound)
                }
                let hit = moveNameOrig.keys.filter { key in
                    guard let kr = ant.range(of: key) else { return false }
                    return ant.distance(from: ant.startIndex, to: kr.lowerBound) >= spEnd
                }.max(by: { $0.count < $1.count })
                if let hit { mvJaFound = moveNameOrig[hit] }
            }
            if mvJaFound == nil && onField, let lr = ant.range(of: "ノ", options: .backwards) {
                // 最後の「の」以降を技名候補として緩く照合する (濁点・半濁点の
                // OCR ゆれ対策。実例: 「あいて相手のゾロアークのハイパーポイス！」
                // = ハイパーボイス が日本語のまま漏れた、2026-11-20 vs Foxy2905 戦)
                // ※ ant は正規化済みで「の」は「ノ」になっている。従来は「の」で
                // 探していたためこのフォールバックは一度も発火していなかった
                // (検証 R3 で検出)
                let tail = String(ant[lr.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "！!"))
                if tail.count >= 3 { mvJaFound = moveNameLoose(tail) }
            }
        }
        if let mvJa = mvJaFound {
                let moveEn = moveJa2En[mvJa] ?? mvJa
                // 同じ文が OCR ゆれ違いで二重に処理されても |move| は 1 回だけ。
                // さらにターン内では同じ枠の同じ技は 1 回だけにする (古い文の
                // 再処理で同じターンの技が繰り返し出た実例: 2026-11-20、
                // ひんし後のグレンアルマの アーマーキャノン 等の再演ブロック)
                let sig = slot + "|" + moveEn + "|t" + String(currentTurn)
                if lastMoveSigAt[sig] != nil {
                    // 同じ枠の同じ技が同じターン番号ですでに出ている場合でも、
                    // その後に技行が 2 件以上進み 10 秒以上経っていて、その枠が
                    // この区間ですでに技を使っているなら、ターン境界の検出が
                    // 遅れている次ターンの技とみなして通す (ターン行は
                    // emitLog のガードが先に出す)。ログ画面の再読のような
                    // 近接した再処理は従来どおり落とす (実例: 2026-11-22
                    // battle_20261122_091721、こだわりスカーフのニョロトノの
                    // だくりゅう が境界検出より先に届いて重複として落ち、
                    // 被ダメ行だけが前のターンに付いた)
                    let moverLabel = "\(slot): \(sp.en)"
                    let advanced = actionSeq - (lastMoveSigSeq[sig] ?? 0) >= 2
                    let waited = sNow().timeIntervalSince(lastMoveSigAt[sig]!) >= 10
                    if !(movesSinceTurnLine.contains(moverLabel) && advanced && waited) { return true }
                }
                if let at = lastMoveSigAt[slot + "|" + moveEn], sNow().timeIntervalSince(at) < 6 { return true }
                // てだすけ (優先度 +5) の告知が、区間に他の技行が既に
                // ある状態で届くことは実戦ではあり得ない (コマンド画面の
                // 技表示や過去文の再読が告知として処理されたもの。
                // 実例: 2026-11-22 battle_20261122_103530 ターン4、
                // 場にいないはずのイエッサンの てだすけ が出た)
                if moveEn == "Helping Hand" {
                    var segHasOtherMove = false
                    if let ti = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                        for l in battleLog[(ti + 1)...] where l.hasPrefix("|move|") {
                            let mf = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                            if mf.count >= 4 && mf[3] != "Helping Hand" { segHasOtherMove = true; break }
                        }
                    }
                    if segHasOtherMove {
                        debugCapture(kind: "move_guard", key: "move_guard_priority:\(slot):\(currentTurn)", rawText: t,
                                     detail: ["reason": "priority_late", "move": moveEn, "slot": slot, "species": sp.en, "turn": currentTurn])
                        return true
                    }
                }
                lastMoveSigAt[sig] = sNow()
                lastMoveSigAt[slot + "|" + moveEn] = sNow()
                lastMoveSigSeq[sig] = actionSeq
                lastMoveLabel = "\(slot): \(sp.en)"
                lastMoveMsgAt = sNow()
                lastMoveName = moveEn
                synthesizeMegaIfPending(side: side, speciesEn: sp.en)
                emitLog("|move|\(slot): \(sp.en)|\(moveEn)")
                lastMoveSeq = actionSeq
                applyMoveField(mvJa, side: side)  // 判明登録は |move| 行の applyEvent が行う
                return true
        }
    }
    // シンプルビームの特性変化: 「<種族>は たんじゅんになった！」を
    // 特性の変化として構造化する (実例: 2026-11-22
    // battle_20261122_091721、効果文が未翻訳のまま残り、特性変化の
    // 行が無かった)
    if t.contains("たんじゅんになった") || t.contains("たんじゅんになつた")
        || foldDakuten(t).contains("たんしゆんになった") {
        if let e = findAllSpeciesJa(in: t).first(where: { cand in lastSlots.values.contains { $0.speciesEn == cand.en } }) {
            let bSide = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en ? "p2" : "p1"
            emitLog("|-ability|\(slotFor(side: bSide, speciesEn: e.en)): \(e.en)|Simple")
        }
        return true
    }
    // エレクトロショットの吸収文: 「<種族>は 電気を 吸収した！」は
    // 雨天時の即時発射の告知で、技行と特攻上昇行は別の文から出るため、
    // 文は消費だけする (実例: 2026-11-22 battle_20261122_091721、
    // 2 回とも未翻訳として残った)
    if t.contains("電気を吸収した") || t.contains("電気を吸収し") {
        return true
    }
    // まもる成功: 「<対象>は 攻撃から 身を守った！」(守つた の OCR 崩れも拾う)
    // activate 行は、同じターンにその枠の まもる の技行がある場合だけ
    // 出す。技行なしの activate は、過去ターンの確認文の再読 (ログ画面
    // 等) が作る偽の記録になる (実例: 2026-11-21
    // battle_20261121_234913 ターン2、技行のない Protect の activate)
    if t.contains("身を守った") || t.contains("身を守つた") || t.contains("守りの入った")
        || (t.contains("体勢") && t.contains("守り") && t.contains("入った")) {
        let pk = slot + "|protect"
        if let at = lastSingleActAt[pk], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = sNow()
        if protectMoveTurn[slot] == currentTurn {
            // 防がれた側の block 行も対で出す (今まで reader は
            // |-block| を一切生成しておらず、技が防がれた記録が
            // activate 行だけだった。実例: 2026-11-23
            // battle_20261123_052626、だいちのちからへの block 行欠落)
            emitLog("|-block|\(slot): \(sp.en)|move: \(protectMoveName[slot] ?? "Protect")")
            emitLog("|-activate|\(slot): \(sp.en)|move: \(protectMoveName[slot] ?? "Protect")")
        }
        return true
    }
    // 状態異常で動けない (行動失敗。実例: 2026-11-20 の対戦で
    // 「イエツサンは 体がしびれて 動けない！」が日本語のまま漏れた)
    // 「動けない」の 動 が 勤 に崩れる OCR ゆれも拾う (実例: 2026-11-22
    // battle_20261122_070237、「凍ってしまって勤けない！」が行動不能行と
    // 併記で日本語のまま残った)
    let cantVerb = t.contains("動けない") || t.contains("勤けない")
    let cantCode = (t.contains("しびれて") && cantVerb) ? "par"
        : (t.contains("凍って") && cantVerb) ? "frz"
        : (t.contains("ひるんで") && t.contains("だせない")) ? "flinch"
        : (t.contains("眠っている") || t.contains("ねむっている")) ? "slp" : ""
    if !cantCode.isEmpty {
        let cantKey = slot + "|cant"
        if let at = lastSingleActAt[cantKey], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[cantKey] = sNow()
        emitLog("|-cant|\(slot): \(sp.en)|\(cantCode)")
        return true
    }
    // このゆびとまれの効果 (OCR ゆれで二重に処理されても 1 回だけ出す)
    if t.contains("注目の的に") && t.contains("なった") {
        if let at = lastSingleActAt[slot], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[slot] = sNow()
        emitLog("|-singleactivate|\(slot): \(sp.en)|move: Follow Me")
        return true
    }
    // 特性の表示: 「<種族>の<特性>」の隣接形だけを拾う (文中の偶然の一致を避ける)
    for (norm, orig) in abilityDict where !norm.isEmpty {
        if nt.contains(normalize(sp.ja + "の") + norm) {
            emitAbilityOnce(slot: slot, side: side, speciesEn: sp.en, abilityEn: abilityJa2En[orig] ?? orig)
            applyAbilityField(orig)
            break
        }
    }
    // きあいのタスキで もちこたえた: 持ち物の判明として記録し、専用行を出す
    // (実例: 2026-11-20 vs Zycloud 戦、グライオンのタスキ発動が日本語のまま漏れた)
    if t.contains("もちこたえた") {
        let sk = slot + "|sash"
        if let at = lastSingleActAt[sk], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[sk] = sNow()
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "きあいのタスキ")
        emitLog("|-activate|\(slot): \(sp.en)|item: Focus Sash")
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // いのちのたまの反動 (実機文面は「いのちのたまの 効果で 命が少し削られた」。
    // OCR 崩れで「いのち命が少し削られた」と読まれることがある)。
    // 判明の帰属は「直近に技を使った枠」と一致する場合だけに限る: 種族名の
    // 誤読で無関係なポケモンに判明が付いた実例がある (2026-11-20、エーフィの
    // 反動がカメックス/イエッサンに付いた)。反動は使用者自身にしか起きない
    if t.contains("命が少し削られた") || (t.contains("削られた") && t.contains("いのち")) {
        if lastMoveLabel == "\(slot): \(sp.en)" && sNow().timeIntervalSince(lastMoveMsgAt) < 10 {
            emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "いのちのたま")
        }
        return true
    }
    // タイプ軽減きのみの発動 (「<対象>へのダメージを オッカのみが弱めた！」。
    // 実例: 2026-11-20、クレッフィのオッカのみ文が日本語のまま漏れた)
    if t.contains("弱めた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // だっしゅつボタンで戻っていく (交代そのものはプレート側で記録する)
    // 「だつしゅつポタン」のような二重ゆれは、正規化 (カナ統一) してから
    // ッ→ツ+濁点畳みにした形でも判定する (検証 hard R7 #90。素の文で畳むと
    // 前半ひらがな/後半カタカナで割れて一致しないため、正規化を先に掛ける)
    let ejFold = foldDakuten(normalize(t).replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ"))
    if t.contains("だっしゅつボタン") || t.contains("しゅつボタン") || (t.contains("だっしゅつ") && t.contains("ボダン")) || (t.contains("ボタン") && (t.contains("戻って") || t.contains("もどって"))) || ejFold.contains("タツシュツホタン") {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "だっしゅつボタン")
        return true
    }
    // 交代技で戻っていく文 (すてゼリフ等: 「<種族>は<相手>の元へ
    // 戻っていく！」)。交代そのものはプレート側で記録するため、
    // ここでは消費だけする。OCR 崩れ (戻→買、場所→完) でも拾う
    // (実例: 2026-11-22 battle_20261122_051707、ターン2の正しい
    //  文面とターン3の崩れた文がどちらも |-message| に残った)
    if (t.contains("戻ってい") || t.contains("買ってい") || t.contains("どってい"))
        && (t.contains("元へ") || t.contains("完へ") || t.contains("場所") || t.contains("もと")) {
        // 戻ることが確定しているため、後任の交代はプレート 1 回の
        // 読みで確定してよい (通常の 2 回確認だと、相手の交代行や
        // ターン終了時の回復行が先に出て順序がずれる。実例:
        // 2026-11-22 battle_20261122_054802 ターン4)
        pivotReturnAt[side] = sNow()
        return true
    }
    // せんせいのツメの発動 (実例: 2026-11-20 の対戦で「キュウコンは
    // せんせいのツメで 行動が はやくなった！」が日本語のまま漏れた)
    if t.contains("せんせいのツメ") || t.contains("せんせいのつめ") {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "せんせいのツメ")
        return true
    }
    // 道具を手に入れた (トリック等で相手の道具が移った場合の判明。
    // 実例: 2026-11-20 vs Gmoneys 戦「イエッサンはこだわりスカーフを
    // 手に入れた！」が日本語のまま漏れ、道具も判明しなかった)
    if t.contains("手に入れた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        return true
    }
    // トリック等の道具交換そのもの (「おたがいの道具を入れ替えた」。
    // 道具 は OCR で「道負」と崩れる。交換自体は消費し、移った道具は
    // 直後の「手に入れた」文で判明させる)
    if (t.contains("道具") || t.contains("道負")) && t.contains("入れ替えた") {
        return true
    }
    // 持ち物の判明: 発動・消費などの文脈があるときだけ拾う
    if t.contains("食べ") || t.contains("発動") || t.contains("なくなった") || t.contains("効果で"),
       let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        // 消費・喪失が伴う文脈なら かるわざ の判定へ (きのみを食べた /
        // 軽減きのみの発動 / 持ち物がなくなった)
        if t.contains("なくなった") || ((itemJa2En[itJa] ?? "").hasSuffix("Berry") && (t.contains("食べ") || t.contains("発動"))) {
            noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        }
    }
    // ふうせんが割れた (持ち物の判明と喪失を同時に記録する。割れた文には
    // 従来の判明分岐の手がかり (食べた/発動/なくなった) が無いため漏れていた。
    // 実例: 2026-11-21 vs Woxofyl 戦、ブリジュラスの文が日本語のまま漏れた)
    if t.contains("ふうせん") && (t.contains("割れた") || t.contains("われた")) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "ふうせん")
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // 身代わりの出現 (技行と消費 HP の行は別経路で出るため、ここでは
    // 開始行だけを出す。既に出ている場合は再読として消費だけする。
    // 実例: 2026-11-21 vs Woxofyl 戦、ゲンガーの出現文が日本語のまま漏れた)
    if t.contains("身代わり") && (t.contains("現れた") || t.contains("あらわれた")) {
        if !subActive.contains(key) { emitLog("|-start|\(slot): \(sp.en)|Substitute") }
        return true
    }
    // 身代わりが攻撃を受けた (身代わりへの被弾では本人の HP が動かないため
    // プレート側では行が出ず、この文が唯一の記録になる。
    // 実例: 2026-11-21 vs Woxofyl 戦、ゲンガーの身代わりへのシャドーボール)
    if t.contains("身代わり") && (t.contains("攻撃を受けた") || t.contains("攻撃をうけた")) {
        let pk = slot + "|subhit"
        if let at = lastSingleActAt[pk], sNow().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = sNow()
        emitLog("|-activate|\(slot): \(sp.en)|move: Substitute")
        return true
    }
    // 回復の告知文: 回復そのものはプレート側で |-heal| を出すため消費のみ
    // (グラッシーフィールド等の回復文が OCR 崩れで漏れた実例: 2026-11-20
    // 「オオニューラのかいふく琳力が回復した！」。持ち物の判明はこの前段の
    // 持ち物分岐が先に処理する)
    if t.contains("回復した") { return true }
    // ひんし (プレート側で既に 0% になっている場合も文は消費する。
    // 消費しないと |-message| に化けて同じ文が残り続ける)。
    // 末尾の濁点ゆれ (たおれだ) も拾う (実例: 2026-11-22
    // battle_20261122_070237、ひんし文が faint 行と併記で残った)
    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        // ひんし文の主語は「種族名+は」の形で決める。文にプレートの
        // 文字など他の種族名が混ざると、本文全体の種族解決 (sp:
        // 辞書順の最初の一致) が無関係な種族になり、占有でないとして
        // 文が捨てられる (実例: 2026-11-22 battle_20261122_181745、
        // Archaludon の ひんし文に オオニューラ のプレート文字が
        // 混ざり、主語が Sneasler と解決された)
        var faintSp = sp
        var faintSlot = slot
        var faintKey = key
        let foldedMsg = foldDakuten(t)
        for cand in findAllSpeciesJa(in: t) where cand.en != sp.en {
            var isSubject = false
            for hay in [t, foldedMsg] {
                var pos = hay.startIndex
                while let r = hay.range(of: cand.ja, range: pos..<hay.endIndex) {
                    if hay[r.upperBound...].hasPrefix("は") { isSubject = true; break }
                    pos = r.upperBound
                }
                if isSubject { break }
            }
            if isSubject {
                faintSp = cand
                let fside = slot.hasPrefix("p1") ? "p1" : "p2"
                faintSlot = slotFor(side: fside, speciesEn: cand.en)
                faintKey = "\(fside):\(cand.en)"
                break
            }
        }
        // 場の占有として記録されていない種族の ひんし文では、
        // 被ダメ行の合成も ひんし行も出さない。未登録のまま倒れた
        // 個体の文や枠解決の誤りで、無関係な枠の HP 基準
        // (lastEmittedPct) を 0 に潰し、後続の正しいプレート読み
        // まで棄却する事故になるため (実例: 2026-11-22
        // battle_20261122_071457、コータスの ひんし文が p1a に
        // 解決され、リキキリンの正しい 65% 読みが棄却された)。
        // 文自体は消費する
        let faintPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][faintSlot] ?? ""
        let faintOccupant = lastSlots[faintPn]?.speciesEn
        let faintIsOccupant = (faintOccupant.map { sameSpeciesFamily($0, faintSp.en) } ?? false)
            || pendingSwitchSpecies[faintPn] == faintSp.en
        if !faintIsOccupant {
            debugCapture(kind: "faint_guard", key: "faint_guard:untracked:\(faintSlot):\(faintSp.en)", rawText: t,
                         detail: ["reason": "faint_text_untracked", "slot": faintSlot, "species": faintSp.en, "occupant": faintOccupant ?? "", "turn": currentTurn])
            return true
        }
        // 占有者の ひんし文は確定情報として扱う。プレートが先に 0%
        // を読んで monStates だけが 0 になっている場合でも、
        // lastEmittedPct が残っていれば被ダメ行はまだ出ていない
        // (プレートの 0% 確定には 2 フレーム必要で、ひんしアニメー
        // ションでプレートが消えると確定しないまま文だけが届く。
        // 実例: 2026-11-22 battle_20261122_171847、Charizard の
        // 被ダメ行・ひんし行が無音で消えた)
        if !faintPn.isEmpty && (lastEmittedPct[faintPn] ?? 1) > 0 {
            heldLine[faintPn] = nil
            // 分母は判明している実最大で統一する。monStates の
            // hpMax は登録済み種族では入らないため battleKnownMax
            // でも引く (プレート 0% 経路と同じ統一。実例:
            // 2026-11-23 battle_20261123_062508、コータスだけ
            // 0/100 になった)
            var fhp = monStates[faintKey]?.hpMax.map { "0/\($0)" }
            if fhp == nil, let fe = speciesDict.first(where: { $0.en == faintSp.en }),
               let km = battleKnownMax(speciesEn: faintSp.en, grp: formeGroup(fe)) {
                fhp = "0/\(km)"
            }
            let fhpText = fhp ?? "0/100"
            _ = emitDamageLine(plateName: faintPn, slot: faintSlot, key: faintKey, speciesEn: faintSp.en,
                               fromPct: lastEmittedPct[faintPn] ?? (monStates[faintKey]?.hpPercent ?? 100),
                               toPct: 0, hpText: fhpText, force: true)
        }
        // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
        deferFaint(slot: faintSlot, speciesEn: faintSp.en)
        return true
    }
    checkStatusText(text: t, side: side, speciesEn: sp.en, slot: slot)
    // サイコアップ: 「<使用者>は <対象>の 能力変化を コピーした！」
    // (文中に上がった/下がったが無いため、ランク変化の照合では拾えない)
    if t.contains("能力変化") && (t.contains("コピー") || t.contains("コビー")) {
        let subjects = findAllSpeciesJa(in: t)
        if subjects.count >= 2 {
            let copier = subjects[0], target = subjects[1]
            let cInOpp = lastSlots["oppA"]?.speciesEn == copier.en || lastSlots["oppB"]?.speciesEn == copier.en
            let cInMine = lastSlots["mineA"]?.speciesEn == copier.en || lastSlots["mineB"]?.speciesEn == copier.en || teamEntries[copier.en] != nil
            let cSide = cInOpp && !cInMine ? "p2" : "p1"
            let tInOpp = lastSlots["oppA"]?.speciesEn == target.en || lastSlots["oppB"]?.speciesEn == target.en
            let tInMine = lastSlots["mineA"]?.speciesEn == target.en || lastSlots["mineB"]?.speciesEn == target.en || teamEntries[target.en] != nil
            let tSide = tInOpp && !tInMine ? "p2" : "p1"
            copyBoosts(fromKey: "\(tSide):\(target.en)", toKey: "\(cSide):\(copier.en)",
                       slot: slotFor(side: cSide, speciesEn: copier.en), speciesEn: copier.en)
        }
        return true
    }
    // たくわえるの蓄積数文: 「<種族>は Nつ たくわえた！」は技が成功
    // した証拠。技告知文を取りこぼした場合は、ここから技行を補う
    // (実例: 2026-11-22 battle_20261122_091721 ターン2、告知文が
    // 断片化して技行が無く、上昇行だけが残った)。既にこの区間で
    // その枠の技行がある場合は消費だけする
    if t.contains("たくわえた") {
        if let e = findAllSpeciesJa(in: t).first {
            let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
            let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
            if inOpp || inMine {
                let mSide = inOpp && !inMine ? "p2" : "p1"
                let mSlot = slotFor(side: mSide, speciesEn: e.en)
                let mLabel = "\(mSlot): \(e.en)"
                if !movesSinceTurnLine.contains(mLabel) {
                    lastMoveSigAt["\(mSlot)|Stockpile|t\(currentTurn)"] = sNow()
                    lastMoveSigAt["\(mSlot)|Stockpile"] = sNow()
                    lastMoveSigSeq["\(mSlot)|Stockpile|t\(currentTurn)"] = actionSeq
                    lastMoveLabel = mLabel
                    lastMoveMsgAt = sNow()
                    lastMoveName = "Stockpile"
                    emitLog("|move|\(mLabel)|Stockpile")
                    lastMoveSeq = actionSeq
                    applyMoveField("たくわえる", side: mSide)
                }
            }
        }
        return true
    }
    // ランク変化文の断片 (主語と能力名だけが先に届き、上がった/
    // 下がったが次の読みに分かれた文) を覚えておく。方向の文が主語
    // なしで届いたら、断片と結合して適用する (実例: 2026-11-22
    // battle_20261122_091721 ターン4、たくわえる の「防御特防が」と
    // 「ぐーんと上がった！」が別々の読みに分かれ、上昇行が丸ごと落ちた)
    if !(t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
         || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた")) {
        let statWords = ["攻撃", "防御", "特攻", "特防", "素早さ", "命中率", "回避率",
                         "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ"]
        // 能力名を含まない主語だけの断片 (「相手のガブリアスの」で
        // 読みが分かれ、能力名と動詞が次の読みに来る形) も覚える。
        // 文の途中で切れた形 (末尾が「の」) に限る (実例: 2026-11-22
        // battle_20261122_171847、がんせきふうじの素早さ低下文が
        // 未翻訳で残った)
        if statWords.contains(where: { t.contains($0) }) || t.hasSuffix("の") {
            let subs = boostSubjects(in: t)
            if subs.count == 1 {
                let e = subs[0]
                let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
                let fSide = (t.contains("相手の") || t.contains("あいての")) && inOpp ? "p2" : (inOpp && !inMine ? "p2" : "p1")
                prevBoostFragment = (text: t, speciesEn: e.en, side: fSide, at: sNow())
            }
        }
    }
    // そうだいしょうの告知文: 「<種族>は 倒された仲間から 力を
    // もらった！」。特性名は帯文に出ず、バナーは画面上部のため、この
    // 定型文から帰属させる。語順が崩れた読み (実例: 2026-11-23
    // battle_20261123_060833、「ドドゲザンはもらった！仲間から
    // 倒された力を」) でも拾えるよう、断片の共存で判定する。交代の
    // 確定前で枠が定まらない間は保留し、recordSwitchIn で流す
    if t.contains("倒された") && t.contains("もらった"),
       let osp = findSpeciesJa(in: t),
       (speciesAbilityMap[osp.en]?.contains("Supreme Overlord") ?? false) {
        var oside = side
        if t.contains("相手の") || t.contains("あいての") { oside = "p2" }
        else if t.contains("味方の") { oside = "p1" }
        else if (fieldSeen["p2"]?.contains(osp.en) ?? false) && !(fieldSeen["p1"]?.contains(osp.en) ?? false) { oside = "p2" }
        let oslot = slotFor(side: oside, speciesEn: osp.en)
        let opn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][oslot] ?? ""
        let oocc = lastSlots[opn]?.speciesEn
        if let oocc, sameSpeciesFamily(oocc, osp.en) {
            emitAbilityOnce(slot: oslot, side: oside, speciesEn: osp.en, abilityEn: "Supreme Overlord")
        } else {
            pendingAbilityReveal["\(oside):\(osp.en)"] = "Supreme Overlord"
        }
        return true
    }
    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する
    // 動詞は漢字表記 (上がった/下がった) も対象にする。小さい「っ」が「つ」に
    // 崩れた形もここで拾う (checkBoostText 自体は対応済みだが、この入口の
    // 判定に無かったため崩れた文が正規経路に入れなかった。検証 R1 で検出)
    if t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
        || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた") {
        // 主語を場のフォルムに寄せる (イエッサン -> イエッサンF 等)。寄せないと
        // 枠が特定できず、二重適用防止のキーが他方と衝突して変化が丸ごと落ちる
        // (実例: 2026-11-20 vs BigGuyMan 戦、いかくのイエッサン分が消えた)。
        // さらに文法上の主語だけに絞る (boostSubjects): 文中に紛れた
        // 無関係な種族名への重複付与を防ぐ
        let subjects = boostSubjects(in: t)
        // ランク変化の側の決定: 文中の側マーカー (相手の/味方の) を
        // 最優先し、両側の場に同種族がいる場合は直前の技の使用者と
        // 一致する側を優先する (自分の技による自己変化は使用者に付く。
        // 実例: 2026-11-21 battle_20261121_234913、げんしのちからの
        // 全能力上昇が、両軍にいるリザードンのうち対象ではなく
        // 使用者ではない自軍側へ付いた)
        func resolvedBoostSide(_ e: SpeciesEntry) -> String {
            // ひんし済みの同種族は場の証拠にしない (倒れた個体は
            // ランク変化を受けない。実例: 2026-11-23
            // battle_20261123_060833、倒れた相手のコータスが枠に
            // 残っていたため、自軍コータスへの いかく の低下が
            // 相手側へ誤帰属した)
            let inOpp = (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en) && !faintedSpecies.contains("p2:\(e.en)")
            let inMine = (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en) && !faintedSpecies.contains("p1:\(e.en)") || teamEntries[e.en] != nil
            if (t.contains("相手の") || t.contains("あいての")) && inOpp { return "p2" }
            if t.contains("味方の") && inMine { return "p1" }
            if inOpp && inMine && lastMoveLabel.hasSuffix(": \(e.en)")
                && sNow().timeIntervalSince(lastMoveMsgAt) < 10 {
                return lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }
            return inOpp && !inMine ? "p2" : "p1"
        }
        // いかくの帰属はランク変化の行より先に [特性] 行を出すため、適用前に行う
        if (t.contains("さがった") || t.contains("下がった") || t.contains("さがつた") || t.contains("下がつた")) && (t.contains("攻撃") || t.contains("こうげき") || t.contains("コウゲキ")) && !t.contains("ぐーんと") {
            var targetSides = Set<String>()
            if subjects.count >= 2 {
                for e in subjects {
                    let inOpp = (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en) && !faintedSpecies.contains("p2:\(e.en)")
                    let inMine = (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en) && !faintedSpecies.contains("p1:\(e.en)") || teamEntries[e.en] != nil
                    targetSides.insert(inOpp && !inMine ? "p2" : "p1")
                }
            } else {
                targetSides.insert(side)
            }
            for ts in targetSides { attributeIntimidate(targetSide: ts) }
        }
        if subjects.count >= 2 {
            for e in subjects {
                let sSide = resolvedBoostSide(e)
                checkBoostText(text: t, side: sSide, speciesEn: e.en, slot: slotFor(side: sSide, speciesEn: e.en))
            }
        } else if subjects.count == 1, subjects[0].en != sp.en {
            // 文法上の主語が、照合で先に掴んだ種族 (混入した名前等) と
            // 食い違う場合は、主語の方へ適用する
            let e = subjects[0]
            let sSide = resolvedBoostSide(e)
            checkBoostText(text: t, side: sSide, speciesEn: e.en, slot: slotFor(side: sSide, speciesEn: e.en))
        } else {
            // 通常経路はアンカーの側を使う。ただし両側の場に同種族が
            // いて、直前の技の使用者がその種族の場合は、使用者の側を
            // 優先する (自己変化の帰属。アンカーは側マーカーが落ちた
            // 文では自軍に寄るため)
            var sSide = side
            let inOppF = (lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en) && !faintedSpecies.contains("p2:\(sp.en)")
            let inMineF = (lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en) && !faintedSpecies.contains("p1:\(sp.en)")
            if (t.contains("相手の") || t.contains("あいての")) && inOppF {
                // 文中の明示の側マーカーは使用者の側の推定より優先する
                // (実例: 2026-11-22 battle_20261122_201011、すてゼリフ
                // の低下が、使用者と同種族の相手側ガオガエンに入る
                // ところ、使用者自身へ帰属した)
                sSide = "p2"
            } else if t.contains("味方の") && inMineF {
                sSide = "p1"
            } else if inOppF && inMineF && lastMoveLabel.hasSuffix(": \(sp.en)")
                && sNow().timeIntervalSince(lastMoveMsgAt) < 10 {
                sSide = lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }
            checkBoostText(text: t, side: sSide, speciesEn: sp.en, slot: slotFor(side: sSide, speciesEn: sp.en))
        }
        // 適用した変化の行が保留中でも、この文は消費済みとして扱う
        if battleLog.count > before || heldBoostLines.values.contains(where: { !$0.isEmpty }) { return true }
    }
    return battleLog.count > before
}

func hpTextFor(_ s: SlotState) -> String {
    if let c = s.hpCur, let m = s.hpMax { return "\(c)/\(m)" }
    return "\(s.hpPercent)/100"
}

func emitDamageLine(plateName: String, slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String, force: Bool = false) -> Bool {
    // 行動内のダメージ/回復行は、HP バーの段階アニメーションの途中値と
    // 区別がつかないため、原則として保留し、次の文の翻訳時かターン境界の
    // flushPendingDamage で「最終値への 1 行」にまとめて出す
    // (実例: 2026-11-20 vs Zycloud 戦、スロートチョップ 1 発が 13% と
    //  60% の 2 行に割れた。また一時的な誤読で下がって元に戻った値は、
    //  確定待ちが自然に消えるため行自体が出ない)。
    // 例外: 0% (ひんし) は即時。方向が反転した行 (被弾直後の きのみ回復等)
    // は途中値ではあり得ないため、保留分を先に確定させてから即時に出す。
    // ターン境界では |turn| の前に flush されるため、ターン終了時の回復が
    // 次のターンにずれることもない (2026-11-20 vs Mark 戦の教訓)
    // 向きは「最後に出力した値」ではなく「保留中の値」を基準に判定する
    // (100 →保留→ 40 → 65 は、出力済みの 100 から見れば減少でも、
    //  実際の HP の動きとしては 40 からの回復 = 反転であるため)
    // 初登場フラグは、異なる値の読みが来たら失効する (同値の重複
    // ダメージ行の抑止は、交代行の直後の一致だけが対象)
    if let fe = firstEntryPlateHP[plateName], fe != hpText { firstEntryPlateHP[plateName] = nil }
    // オボンのみの発動監視の解消: 条件を跨いだ低下の後に回復が
    // 記録されれば通常どおり発動が取れたことになる。回復が無いまま
    // 次の被弾 (または ひんし) に進んだ場合は、発動イベント
    // (回復+持ち物判明) が丸ごと取り込まれていない疑いとして、
    // 証拠だけを残す (行の合成はしない。実例: 2026-11-21
    // battle_20261121_233243、リキキリンが 52% から 7% に落ちた
    // 場面で発動したはずのオボンのみの回復行・持ち物行が無かった)
    if let watched = sitrusWatch[key] {
        if toPct > watched {
            sitrusWatch[key] = nil
        } else if toPct < watched {
            debugCapture(kind: "berry_activation_suspect", key: "berry_activation_suspect|\(key)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "droppedToPct": watched, "toPct": toPct, "turn": currentTurn])
            if debugMode { print("[reader] オボンのみの発動条件を跨いだ後に回復が記録されないまま HP が動きました (発動の取りこぼしの疑い): \(slot): \(speciesEn) \(watched)% -> \(toPct)%") }
            fflush(stdout)
            sitrusWatch[key] = nil
        }
    }
    var effFrom = fromPct
    var dirBase = fromPct
    if let h = heldLine[plateName], h.seq == actionSeq, h.turn == currentTurn { dirBase = h.toPct }
    let dir = toPct < dirBase ? -1 : 1
    if !force && toPct != 0 {
        if let h = heldLine[plateName], h.seq == actionSeq && h.turn == currentTurn, h.dir != dir {
            // 反転先が「保留行を出す前の確定値」と完全一致する場合は、
            // 実ダメージ+回復ではなく一時的な誤読が元に戻っただけと
            // みなし、保留行ごと捨てる (実例: 2026-11-20 vs チェイス戦、
            // ターン頭のサーナイトに被弾行と全回復行のペアが出た)
            if toPct == (lastEmittedPct[plateName] ?? fromPct) {
                debugCapture(kind: "hp_reversal_drop", key: "hp_reversal_drop|\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "heldToPct": h.toPct,
                                      "reversedToPct": toPct, "lastEmittedPct": lastEmittedPct[plateName] ?? fromPct])
                heldLine[plateName] = nil
                return true
            }
            heldLine[plateName] = nil
            _ = emitDamageLine(plateName: plateName, slot: slot, key: key, speciesEn: speciesEn,
                               fromPct: lastEmittedPct[plateName] ?? fromPct, toPct: h.toPct,
                               hpText: h.hpText, force: true)
            effFrom = h.toPct
        } else {
            heldLine[plateName] = (toPct: toPct, dir: dir, seq: actionSeq, turn: currentTurn, hpText: hpText)
            return false
        }
    }
    // 段階アニメーションの尾: 同じ行動・同じターンで、直前の出力行と
    // 同じ向き・わずかな差 (3% 以下) の続きは、行を出さず値だけ取り込む
    // (実例: 2026-11-20、グラススライドの被弾が 79% と 2% に割れた)。
    // 直前の行から 3 秒以内なら 5 ポイントまで広げる (反動ダメージの
    // 途中値が先行行として出て、確定値が第 2 行に割れた実例: 2026-11-22
    // battle_20261122_103530、いのちのたま の反動が 94% と 90% に割れた)
    if toPct != 0, let lp = lastEmittedPct[plateName],
       lastDamageSeq[plateName] == actionSeq, lastDamageTurn[plateName] == currentTurn,
       lastDamageDir[plateName] == dir, toPct != lp,
       abs(toPct - lp) <= 3 || (abs(toPct - lp) <= 5 && (lastDamageTime[plateName].map { sNow().timeIntervalSince($0) <= 3 } ?? false)) {
        heldLine[plateName] = nil
        lastEmittedPct[plateName] = toPct
        return true
    }
    // 回復行なのに HP 表記の現在値が 0 のものは、ひんし直後のバー誤読
    // (割合だけ僅かに読めた) による幻行なので出さない
    // (実例: 2026-11-20 vs チェイス戦、倒れたバサギリに |-heal|0/100)
    if toPct > effFrom, let first = hpText.split(separator: "/").first,
       Int(first.trimmingCharacters(in: .whitespaces)) == 0 {
        lastEmittedPct[plateName] = toPct
        return true
    }
    heldLine[plateName] = nil
    let prevDamageAt = lastDamageTime[plateName]
    let prevDamageSeq = lastDamageSeq[plateName]
    lastDamageSeq[plateName] = actionSeq
    lastDamageTurn[plateName] = currentTurn
    lastDamageDir[plateName] = dir
    lastDamageTime[plateName] = sNow()
    lastEmittedPct[plateName] = toPct
    if lastPendingLabel == "\(slot): \(speciesEn)" { lastPendingLabel = "" }
    // 基準値そのものが「疑わしい跳び」として保留中の値か (下の解消で
    // suspectJump は消えるため、ここで控える)。基準が疑わしい場合、
    // 発生源不明の回復は「幻の回復」ではなく基準側の誤りの訂正として
    // 扱う必要がある (実例: 2026-11-22 battle_20261122_050512、
    // 保留された 25% が基準に固定され、実値 41% への回復が
    // 発生源なしとして抑止され、状態が 25% のまま固定された)
    let baselineWasSuspect = suspectJump[plateName].map { $0.toPct == effFrom } ?? false
    // この呼び出しで「低下の疑わしさ」が解けたかどうか (下の解消で
    // suspectJump は消えるため、ここで控える)
    var clearedDropSuspect = false
    // この呼び出しが「疑わしい 0% の保留の解消 (通常処理への落下)」
    // かどうか。ひんし記録済みでも、この経路の KO 行だけは出す
    // (下の post-faint 抑制の例外判定に使う)
    var suspectZeroFallthrough = false
    // 疑わしい大きな跳びの解消: 保留していた値と同じ読みが次のターン
    // でも続くなら、誤読は内部状態の方だったとみなし、行を出さずに
    // 値だけを取り込む (実例: 2026-11-21 battle_20261121_230402、
    // サーナイトの満タンの正読が「7% への幻の低下」を信じた内部状態
    // のために跳びとして却下され続け、実ダメージまで回復行に化けた)。
    // 別の値に移った場合は疑いを解いて通常処理に戻る
    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct && sj.toPct == 0 {
            // 0% の持続は状態訂正ではなく ひんし。無音で取り込むと
            // 被ダメ行・ひんし行が丸ごと消えるため、疑いを解いて
            // 通常処理へ落とす (実例: 2026-11-22
            // battle_20261122_171847、アーマーキャノンで倒れた
            // Kingambit が hp_jump_adopted で無音採用された)。
            // この場合は「疑いが解けた」扱いにしない (直後の
            // post_suspect 保留に再び捕まらないため)
            suspectJump[plateName] = nil
            clearedDropSuspect = false
            suspectZeroFallthrough = true
        } else if toPct != 0 && abs(toPct - sj.toPct) <= 3 {
            // 保留値の ±3 ポイント以内は、読みの揺れの範囲内として
            // 同じ低下の裏づけとみなす。完全一致に限ると、低 HP での
            // 揺れ (6% の保留後に 5% や 7% が安定する等) が「別の値」
            // として疑いを解き、post_suspect の再保留との往復で永久に
            // 採用されなくなる (実例: 2026-11-23
            // battle_20261123_043809、Dragonite の 54% -> 6% が最後まで
            // 取り込まれず、反動行が古い基準から記録された)
            if currentTurn > sj.turn {
                suspectJump[plateName] = nil
                lastEmittedPct[plateName] = toPct
                monStates[key]?.hpPercent = toPct
                monStates[key]?.hpText = hpText
                debugCapture(kind: "hp_jump_adopted", key: "hp_jump_adopted|\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "toPct": toPct, "suspectTurn": sj.turn])
                if debugMode { print("[reader] 疑わしい跳びとして保留していた値を、持続したため状態訂正として取り込みました: \(slot): \(speciesEn) -> \(toPct)%") }
                fflush(stdout)
            }
            return true
        }
        // 保留した値より更に下がった場合は、保留分が実在した裏づけ
        // (HP は行動の解決中に下がり続ける)。保留分を独立した行と
        // して先に出し、現在の行は保留値から始めさせる。この場合は
        // 疑いが「実在した」として解けたので、未分類の再保留
        // (post_suspect) には回さない (実例: 2026-11-23
        // battle_20261123_062508、ねっぷうの被ダメが保留と再保留の
        // 往復で消え、残りが砂嵐の行に吸収された)
        if toPct < sj.toPct && sj.toPct < effFrom {
            emitLog("|-damage|\(slot): \(speciesEn)|\(sj.hpText)")
            lastEmittedPct[plateName] = sj.toPct
            monStates[key]?.hpPercent = sj.toPct
            effFrom = sj.toPct
            suspectJump[plateName] = nil
        } else {
            if sj.toPct < effFrom, sj.toPct != 0 { clearedDropSuspect = true }
            suspectJump[plateName] = nil
        }
    }
    // ひんし行が出た種族への HP 変動行は出さない。ひんし後に同じ
    // 枠へ残った古い読みが、回復や被ダメとして再演される事故の
    // 防止 (交代で戻れば faintedSpecies から外れるため、正規の
    // 再登場には影響しない。実例: 2026-11-22
    // battle_20261122_185505、ひんし済みの Garchomp に 36/185 の
    // 幻回復が 2 回と、2 回目のひんし行が出た)
    // ただし、その種族自身の「まだ出ていない ひんしに至る被ダメ行」
    // は抑制しない。被ダメが疑わしい跳びとして保留されている間に
    // ひんしが先に記録されると、保留解除後の行まで消えてしまい、
    // ひんし行だけが残る (実例: 2026-11-22 battle_20261122_201011、
    // ゴリランダーの 100 -> 0 が post_faint_suppressed で消えた)
    if faintedSpecies.contains(key),
       !(toPct == 0 && suspectZeroFallthrough) {
        debugCapture(kind: "faint_guard", key: "post_faint_line:\(key)", rawText: "",
                     detail: ["reason": "post_faint_suppressed", "slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "turn": currentTurn])
        return true
    }
    if toPct < effFrom {
        // 直前の技も交代も無い状況での 55 ポイント超の低下は、1 回の
        // 出来事では起こり得ない (設置物は最大でも 25%、反動も技が
        // 先行する)。最後の出来事が交代行で、その後に技が出ていない
        // 場合は、繰り出し演出中のプレート誤読の疑いとして行を出さず
        // に保留する。ただし、直近の技がまだ解決中 (その技の被ダメが
        // 1 件も記録されていない) 場合は対象外: 交代で入った本人が
        // その技を受ける場面では、技行→交代行の順に記録されても
        // 被弾は本物であり、保留すると被ダメが交代行の HP に
        // 畳み込まれて消える (実例: 2026-11-22
        // battle_20261122_050512、交代で入ったガオガエンへの
        // インファイト 75% が保留され、回復もろとも記録が崩れた)。
        // (実例: 2026-11-21 battle_20261121_230402、
        // ペリッパーを倒した直後の交代演出中にサーナイトが 10/145 と
        // 読まれ、93% 喪失の幻行が出た)。状態異常の経過ダメージは
        // 対象外 (どくの経過は大きくなることがある)。保留した値は
        // 上の解消規則で、持続すれば次のターンに取り込まれる
        let moveInFlight = !lastMoveLabel.isEmpty && lastMoveSeq == actionSeq
            && (damagedBySeq[actionSeq] ?? []).isEmpty && sNow().timeIntervalSince(lastMoveMsgAt) < 20
        if effFrom - toPct > 55, toPct != 0, (monStates[key]?.status ?? "").isEmpty,
           pendingStatusFrom[key] == nil, !moveInFlight,
           lastSwitchEmitSeq >= 0, lastSwitchEmitSeq >= lastMoveEmitSeq {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct])
            if debugMode { print("[reader] 大きな低下を誤読の疑いとして保留しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 訂正の吸収: その枠の直前の行から 10 秒以上経ち、別の行動で、
        // 差が 3% 以下の減少は、落ち着いた実値への訂正とみなして
        // 行を出さず値だけ取り込む (実例: 2026-11-21
        // battle_20261121_224409、ゴツゴツメット反動の 55% が交代
        // 要員選択中に 53% へ訂正され、独立したダメージ行として
        // 追記された)。行動中の小さな実ダメージは、直前の行と行動が
        // 近いため、この条件には入らない
        if toPct != 0, effFrom - toPct <= 3, let lt = prevDamageAt, sNow().timeIntervalSince(lt) >= 10,
           prevDamageSeq != actionSeq, sNow().timeIntervalSince(lastMoveMsgAt) >= 5,
           pendingStatusFrom[key] == nil {
            debugCapture(kind: "hp_correction", key: "hp_correction|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct])
            return true
        }
        // 低下していない値への被ダメ行はあり得ない。開幕のプレート
        // 確定時に % 基準 (100) と実数表記がずれて、満タンの被ダメ行
        // が出た実例への対策 (実例: 2026-11-22
        // battle_20261122_181745、ターン 1 冒頭の 145/145・161/161)
        if toPct >= effFrom { return true }
        lastDamageLabel = "\(slot): \(speciesEn)"
        lastDamageAt = sNow()
        var line = "|-damage|\(slot): \(speciesEn)|\(hpText)"
        var fromCode: String? = nil
        var selfClassified = false   // 自分の技の反動として分類できたら、推定用イベントも出す
        var recoilMove = ""          // 反動と分類した技 (遅延帰属では本人の直近の技)
        if let pf = pendingStatusFrom[key], sNow().timeIntervalSince(pf.at) < 5 {
            fromCode = pf.code
            pendingStatusFrom[key] = nil
        }
        // 予告記録が間に合わなかった場合の受け皿: 状態異常が判明して
        // いて、低下量がその経過ダメージに一致し、荒天の経過と紛れ
        // ず、解決中の技の対象でもない低下は、状態異常の経過として
        // 帰属させる (実例: 2026-11-23 battle_20261123_090354
        // ターン3、ミロカロスのやけどチップ行に [from] brn が
        // 付かなかった)
        if fromCode == nil, let st = monStates[key]?.status, st == "brn" || st == "psn",
           logFieldWeather != "Sand" && logFieldWeather != "Snow",
           lastMoveLabel != "\(slot): \(speciesEn)",
           !(damagedBySeq[actionSeq] ?? []).contains("\(slot): \(speciesEn)") {
            let drop = effFrom - toPct
            if (st == "brn" && (drop == 6 || drop == 7)) || (st == "psn" && (drop == 12 || drop == 13)) {
                fromCode = st
            }
        }
        if fromCode == nil {
            // 初登場の交代行が既に同じ HP を示している場合、その値への
            // ダメージ行は重複である (交代行の HP が初記録であり、
            // そこからの変化はまだ何も起きていない。設置物の [from]
            // 行は上の分岐で処理済み。再登場時の差分行は前回出場時の
            // HP からの変化として意味があるため対象外)
            // (実例: 2026-11-21 battle_20261121_233243、マフォクシーの
            // 交代行 76/100 の直後に同値の被ダメ行が重なった)
            if firstEntryPlateHP[plateName] == hpText {
                firstEntryPlateHP[plateName] = nil
                return true
            }
            // 自分が直前に使った技の直後の自己ダメージは、発生源を
            // 分類する (実例: 2026-11-21 battle_20261121_233243、
            // ウッドハンマーの直後に 10% と 37% の自己ダメージが
            // どちらも素のダメージ行になっていた)。ちょうど 10% は
            // いのちのたまの反動 (持ち物の判明としても記録する)、
            // 反動技のそれ以外の自己ダメージは技の反動とする
            if lastMoveLabel == "\(slot): \(speciesEn)",
               sNow().timeIntervalSince(lastMoveMsgAt) < 20 {
                let drop = effFrom - toPct
                let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                    : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
                // 残り HP が少なく反動が上限で切り取られた場合
                // (8% から 0% 等) も、持ち物が判明していれば
                // いのちのたまの反動として分類する (実例: 2026-11-22
                // battle_20261122_171847、ガブリアスの反動ひんし行に
                // [from] が付かなかった)
                if ((9...11).contains(drop) || (toPct == 0 && drop <= 11 && knownItem == "いのちのたま")),
                   knownItem == nil || knownItem == "いのちのたま" {
                    if knownItem == nil {
                        emitItemOnce(slot: slot, side: key.hasPrefix("p2") ? "p2" : "p1",
                                     speciesEn: speciesEn, itemJa: "いのちのたま")
                    }
                    fromCode = "item: Life Orb"
                    selfClassified = true
                } else if recoilMoves.contains(lastMoveName) {
                    fromCode = "move: \(lastMoveName)"
                    selfClassified = true
                    recoilMove = lastMoveName
                } else if (11...18).contains(drop) {
                    // 接触した相手の特性・持ち物による反動 (さめはだ/
                    // てつのトゲ = 最大の 1/8、ゴツゴツメット = 1/6)。
                    // 技を受けた側の特性・持ち物が判明している場合に
                    // 限って帰属させる (実例: 2026-11-22
                    // battle_20261122_050512、ねこだましを受けた
                    // ガブリアスの さめはだ反動に [from] が付かなかった)
                    for targetLabel in damagedBySeq[actionSeq] ?? [] where targetLabel != "\(slot): \(speciesEn)" {
                        guard let tp = parseSlotSpecies(targetLabel) else { continue }
                        let tAbility = tp.side == "p1" ? (teamEntries[tp.speciesEn]?["ability"] as? String) : revealedAbilities[tp.speciesEn]
                        let tItem = tp.side == "p1" ? (teamEntries[tp.speciesEn]?["item"] as? String) : revealedItems[tp.speciesEn]
                        if (11...14).contains(drop), tAbility == "さめはだ" {
                            fromCode = "ability: Rough Skin"; selfClassified = true; break
                        }
                        if (11...14).contains(drop), tAbility == "てつのトゲ" {
                            fromCode = "ability: Iron Barbs"; selfClassified = true; break
                        }
                        if (15...18).contains(drop), tItem == "ゴツゴツメット" {
                            emitItemOnce(slot: tp.slot, side: tp.side, speciesEn: tp.speciesEn, itemJa: "ゴツゴツメット")
                            fromCode = "item: Rocky Helmet"; selfClassified = true; break
                        }
                    }
                }
            }
            // 反動の遅延帰属: 反動行の処理が次の技の告知より遅れて
            // 直近の技が他者になっていても、本人がこのターンに使った
            // 技が反動技で、現在の行動の被ダメ対象に本人が含まれて
            // いなければ、反動として分類する (実例: 2026-11-23
            // battle_20261123_062508、ブレイブバードの反動が
            // ねっとうの技行の後に素のダメージ行として出た)
            if fromCode == nil, lastMoveLabel != "\(slot): \(speciesEn)",
               let own = lastMoveBySlot["\(slot): \(speciesEn)"], own.turn == currentTurn,
               recoilMoves.contains(own.move),
               !(damagedBySeq[actionSeq] ?? []).contains("\(slot): \(speciesEn)"),
               (1...50).contains(effFrom - toPct) {
                fromCode = "move: \(own.move)"
                selfClassified = true
                recoilMove = own.move
            }
        }
        // 分類できない大きな自己ダメージは、プレート誤読の疑いとして
        // 行を出さずに保留する。自分の技の直後に自分が大きく減る経路は、
        // 反動技・いのちのたま・接触反動 (いずれも上で分類済み) のほかは
        // はらだいこ・のろい (自分を削る使い方)・いたみわけ の自己負担
        // しかなく、それらを除けば 18 ポイントを超える自己低下は実在
        // しない (実例: 2026-11-22 battle_20261122_054802、ラグラージの
        // プレートが 116/207 → 10/207 と誤読され、自分の技の被ダメ行
        // として記録されたうえ、本来の対象 (イエッサン) の被ダメまで
        // 「技は解決済み」と誤判定されて保留に巻き込まれた)
        if fromCode == nil, lastMoveLabel == "\(slot): \(speciesEn)",
           sNow().timeIntervalSince(lastMoveMsgAt) < 20, effFrom - toPct > 18,
           !["Belly Drum", "Curse", "Pain Split"].contains(lastMoveName) {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "self_unclassified"])
            if debugMode { print("[reader] 分類できない大きな自己ダメージを誤読の疑いとして保留しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 疑わしい低下を保留した直後に、別の値への説明できない低下が
        // 来た場合は、その値も誤読の連鎖とみて確定させない。保留に
        // なったプレートは読みが安定しておらず、値が変わっただけで
        // 疑いが解けたとは言えない (実例: 2026-11-22
        // battle_20261122_075240、Sneasler に 100% -> 10% の誤読が
        // 保留された後、88% の読みがターン終了時の確定として幻の
        // ダメージ行になった)。持続すれば次ターンに状態訂正として
        // 取り込まれ (冒頭の解消規則)、実値に戻れば何も残らない。
        // 分類できた低下 (状態異常の経過等) は従来どおり出す
        if fromCode == nil, clearedDropSuspect, toPct != 0, effFrom - toPct > 3 {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "post_suspect_unexplained"])
            return true
        }
        // 隣枠と寸分違わぬ HP 文への低下は、枠混入 (隣の枠の数字を
        // 自分のものとして読んだ) の疑いとして行を出さずに保留する。
        // 回復側は発生源なしの行を出さないのに被ダメ側だけ素通りする
        // 非対称への対処も兼ねる (実例: 2026-11-22
        // battle_20261122_160927、ねこだましを受けたエルフーンと
        // 同じ 150/167 が、対象でないサーナイトの被ダメ行になった)。
        // 保留した値は冒頭の解消規則で、持続すれば次ターンに状態
        // 訂正として取り込まれる
        if fromCode == nil && toPct != 0 {
            let sidePrefix = key.hasPrefix("p2") ? "p2" : "p1"
            var siblingIdentical = false
            for (k, v) in monStates where k != key && k.hasPrefix(sidePrefix + ":") && v.hpText == hpText {
                let sibSpecies = String(k.dropFirst(3))
                if lastSlots.values.contains(where: { $0.speciesEn == sibSpecies }) { siblingIdentical = true; break }
            }
            if siblingIdentical {
                suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)
                lastEmittedPct[plateName] = effFrom
                debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "sibling_identical"])
                if debugMode { print("[reader] 隣枠と同じ HP 文への低下を枠混入の疑いとして保留しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
                fflush(stdout)
                return true
            }
        }
        if let fromCode { line += "|[from] \(fromCode)" }
        emitLog(line)
        recordDamageEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, hpText: hpText,
                          directMove: fromCode == nil)
        if selfClassified {
            recordRecoilEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, moveName: recoilMove)
        }
        // 相性行の付け替え判定用に、この行動で被ダメした対象を控える
        damagedBySeq[actionSeq, default: []].insert("\(slot): \(speciesEn)")
        for old in damagedBySeq.keys where old < actionSeq - 1 { damagedBySeq[old] = nil }
        for old in effectBySeq.keys where old < actionSeq - 1 { effectBySeq[old] = nil }
        // オボンのみの発動条件 (HP 半分以下) を跨ぐ低下は、持ち物が
        // 未判明なら発動の監視を始める (解消はこの関数の冒頭で行う)
        if effFrom > 50, toPct <= 50, toPct > 0 {
            let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
            if knownItem == nil { sitrusWatch[key] = toPct }
        }
    } else if toPct > effFrom {
        // 1 回の回復が 55 ポイントを超えることはあり得ない (最大でも
        // じこさいせい/ねがいの 50%)。ログ画面経路と同じ基準で、大きな
        // 回復は誤読として却下し、デバッグ記録を残す (実例: 2026-11-21
        // vs KAM 戦、ふんか演出中にプレートが一時的に満タンと読まれ、
        // 42/177 から全回復の |-heal| が発生源なしで出た)
        if toPct - effFrom > 55 {
            // 記録の state が却下後の値で写るよう、確定基準の巻き戻しを
            // 記録の取得より前に行う (実例: 2026-11-21
            // battle_20261121_145658、却下した 100% が記録の state に
            // そのまま写り、切り分けの妨げになった)
            // ただし却下し続けると、正しい読みが持続している場合に
            // 内部状態の誤りが固定されてしまうため、疑わしい跳び
            // として保留し、次ターンも同じ値なら状態訂正として
            // 取り込む (冒頭の解消規則。実例: 2026-11-21
            // battle_20261121_230402 のサーナイト誤認連鎖)
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_jump_rejected", key: "hp_jump|\(key)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "source": "plate"])
            if debugMode { print("[reader] 大きな回復を誤読として却下しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 回復の発生源 (オボンのみ/たべのこし/グラッシーフィールド) が
        // 推定できれば [from] を付け、持ち物なら判明としても記録する
        let src = healSource(plateName: plateName, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        // オボンのみと分類できた回復が本来の +25% に大きく届かず、かつ
        // プレートの最新読みがさらに上を示している場合は、回復
        // アニメーションの途中値とみて確定せずに戻す (基準値は戻し、
        // 後続の読みが最終値で再駆動する。実例: 2026-11-22
        // battle_20261122_070237、+20% で確定し、残り +5% が出所不明の
        // 回復として二重に残った)
        if src?.label == "item: Sitrus Berry", effFrom <= 50, toPct - effFrom <= 21,
           (lastSlots[plateName]?.hpPercent ?? toPct) > toPct {
            lastEmittedPct[plateName] = effFrom
            return false
        }
        // 発生源を特定できず、回復技・ねがいごとの遅延回復・吸収特性
        // でも説明できない回復は、行を出さず証拠記録だけを残す。
        // 以前は行も出していたが、演出中の一時的な満タン誤読が
        // |-heal| として残り、続く被弾行の喪失率表示まで狂わせた
        // (実例: 2026-11-21 battle_20261121_224409、はたき落としの
        // 演出中にイエッサン♀が 82% から全回復したことになり、
        // ひんし表示が「100% 失った」になった)。記録は枠ごとに
        // 最初の 1 件のみ (デバッグ上限の圧迫を避ける)
        if src == nil {
            let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
            let knownAbility = key.hasPrefix("p2") ? revealedAbilities[speciesEn]
                : ((teamEntries[speciesEn]?["ability"] as? String) ?? revealedAbilities[speciesEn])
            if !healExplained(key: key, slot: slot, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct,
                              knownItem: knownItem, abilityJa: knownAbility) {
                // 基準値が疑わしい跳びとして保留中の値だった場合は、
                // 回復行は出さないが、値だけは訂正として取り込む
                // (基準の誤りを固定すると、以後の全ての喪失率が
                // 狂う。実例: 2026-11-22 battle_20261122_050512)
                if baselineWasSuspect {
                    lastEmittedPct[plateName] = toPct
                    monStates[key]?.hpPercent = toPct
                    monStates[key]?.hpText = hpText
                    debugCapture(kind: "hp_jump_adopted", key: "hp_jump_adopted|\(plateName)", rawText: "",
                                 detail: ["slot": slot, "species": speciesEn, "toPct": toPct,
                                          "via": "heal_from_suspect_baseline"])
                    if debugMode { print("[reader] 疑わしい基準値からの回復を、状態訂正として取り込みました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
                    fflush(stdout)
                    return true
                }
                lastEmittedPct[plateName] = effFrom
                if debugMode { print("[reader] 発生源を特定できない回復を記録し、行は出しませんでした: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
                fflush(stdout)
                debugCapture(kind: "heal_no_source", key: "heal_no_source:\(slot)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct,
                                      "turn": currentTurn, "knownItem": knownItem ?? "", "knownAbility": knownAbility ?? "",
                                      "terrain": logFieldTerrain, "weather": logFieldWeather,
                                      "lastMove": lastMoveName, "lastMoveLabel": lastMoveLabel])
                return true
            }
        }
        if let itemJa = src?.itemJa {
            let srcSide = key.hasPrefix("p2") ? "p2" : "p1"
            emitItemOnce(slot: slot, side: srcSide, speciesEn: speciesEn, itemJa: itemJa)  // 判明登録は applyEvent が行う
            // オボンのみは回復と同時に消費される (たべのこしは消費されない)
            if itemJa == "オボンのみ" { noteItemLost(slot: slot, side: srcSide, speciesEn: speciesEn) }
        }
        // オボンと分類された回復にグラッシーフィールドの回復が
        // 合算されている場合は 2 行に分ける。オボンの回復 (+最大の
        // 1/4) を超えた分が地形の回復量 (最大の 1/16) に一致し、
        // このターンの地形回復がまだ記録されていない場合に限る
        // (実例: 2026-11-22 battle_20261122_201011 ターン7、
        // 46 -> 96 (オボン) -> 108 (地形) の 2 イベントが +62 の
        // 1 行に合算された。動画の静定値で分離確認済み)
        var splitMidText: String? = nil
        if src?.label == "item: Sitrus Berry",
           logFieldTerrain == "Grassy",
           grassyHealTurn[plateName] != currentTurn {
            let hpParts = hpText.split(separator: "/")
            if hpParts.count == 2,
               let curU = Int(hpParts[0].trimmingCharacters(in: .whitespaces)),
               let maxU = Int(hpParts[1].trimmingCharacters(in: .whitespaces)), maxU > 0 {
                let fromU = Int((Double(effFrom) / 100.0 * Double(maxU)).rounded())
                let berryAmt = maxU / 4
                let terrainAmt = curU - fromU - berryAmt
                let expectT = maxU / 16
                let tol = maxU == 100 ? 3 : 2
                if terrainAmt > 0 && abs(terrainAmt - expectT) <= tol {
                    splitMidText = "\(fromU + berryAmt)/\(maxU)"
                }
            }
        }
        if let mid = splitMidText {
            emitLog("|-heal|\(slot): \(speciesEn)|\(mid)|[from] item: Sitrus Berry")
            emitLog("|-heal|\(slot): \(speciesEn)|\(hpText)|[from] Grassy Terrain")
            grassyHealTurn[plateName] = currentTurn
        } else {
            var line = "|-heal|\(slot): \(speciesEn)|\(hpText)"
            if let src { line += "|[from] \(src.label)" }
            emitLog(line)
        }
    }
    if toPct == 0 { deferFaint(slot: slot, speciesEn: speciesEn) }
    return true
}

func deferFaint(slot: String, speciesEn: String) {
    if faintedSlots[slot] == speciesEn { return }  // 既にひんし行を出した枠・種族は再登録しない
    if !pendingFaints.contains(where: { $0.slot == slot }) {
        pendingFaints.append((slot: slot, speciesEn: speciesEn, at: sNow()))
    }
}

func faintStillValid(_ f: (slot: String, speciesEn: String, at: Date)) -> Bool {
    let fside = f.slot.hasPrefix("p2") ? "p2" : "p1"
    if (monStates["\(fside):\(f.speciesEn)"]?.hpPercent ?? 0) > 0 { return false }
    let plateName = (fside == "p1" ? "mine" : "opp") + (f.slot.hasSuffix("a") ? "A" : "B")
    if let cur = lastSlots[plateName], cur.speciesEn != f.speciesEn { return false }
    return true
}

func emitPendingFaints() {
    let fs = pendingFaints
    pendingFaints = []
    for f in fs {
        if faintedSlots[f.slot] == f.speciesEn { continue }
        if !faintStillValid(f) { continue }
        faintedSlots[f.slot] = f.speciesEn
        emitLog("|faint|\(f.slot): \(f.speciesEn)")
    }
}

func flushPendingDamage(force: Bool = false) {
    for plate in plates {
        guard let pend = pendingDamagePct[plate.name], let s = lastSlots[plate.name] else { continue }
        if !force, let since = pendingDamageSince[plate.name], sNow().timeIntervalSince(since) < 2.0 { continue }
        pendingDamagePct[plate.name] = nil
        pendingDamageCount[plate.name] = nil
        pendingDamageSince[plate.name] = nil
        heldLine[plate.name] = nil
        let side = plate.name.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        let from = lastEmittedPct[plate.name] ?? s.hpPercent
        if pend != from, let st = monStates[key] {
            emitDamageLine(plateName: plate.name, slot: slotId(plate.name), key: key,
                           speciesEn: s.speciesEn, fromPct: from, toPct: pend, hpText: st.hpText, force: true)
        } else {
            lastEmittedPct[plate.name] = pend
        }
    }
}

func recordDamageEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String, directMove: Bool = false) {
    let parts = hpText.split(separator: "/")
    var exact: [Int]? = nil
    if parts.count == 2, let c = Int(parts[0].trimmingCharacters(in: .whitespaces)), let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
        exact = [c, m]
    }
    let prevExact = lastExactHp[key]
    if let exact { lastExactHp[key] = exact }
    // 同じ行動・同じ対象・同じ基準 HP からの被ダメが再び放出された
    // 場合は、別イベントとして足さずに先の記録を上書きする。二重の
    // 記録 (推定側での二重処理) を防ぎ、途中値で記録されたイベントを
    // 最終値へ是正するのが目的。連続ヒットは基準 HP が前回の到達値と
    // 一致するため、この条件には当たらず別イベントとして残る
    // (実例: 2026-11-22 battle_20261122_070237、Milotic のイベント
    // 二重化と Farigiraf の amt 食い違い)
    let defLabelForEv = "\(slot): \(speciesEn)"
    let supersedeIdx = battleEvents.lastIndex(where: {
        $0.contains("\"k\":\"dmg\"") && $0.contains("\"turn\":\(currentTurn)")
            && $0.contains("\"atk\":\"\(jsonEscape(lastMoveLabel))\"")
            && $0.contains("\"def\":\"\(jsonEscape(defLabelForEv))\"")
            && $0.contains("\"move\":\"\(jsonEscape(lastMoveName))\"")
            && $0.contains("\"defHp\":\(fromPct)")
    })
    var effPrevExact = prevExact
    if supersedeIdx != nil, let stashed = lastDmgEventPrevExact[key] {
        effPrevExact = stashed.isEmpty ? nil : stashed
    }
    guard battleEvents.count < 600 else { return }
    // 時刻の上限は行動の区切り (actionSeq) 側が本筋の帰属ガードで、
    // こちらは暴走防止の緩い上限にとどめる。開幕の演出や範囲技の
    // 解決が長いと 8 秒では正当な証拠まで落ちる (実例: 2026-11-22
    // battle_20261122_070237 ターン1、ユキメノコのふぶきの被ダメ
    // イベントが欠落した)
    guard !lastMoveLabel.isEmpty, actionSeq - lastMoveSeq <= 1,
          sNow().timeIntervalSince(lastMoveMsgAt) < 20 else { return }
    let defSide = key.hasPrefix("p1") ? "p1" : "p2"
    let atkSide = lastMoveLabel.hasPrefix("p1") ? "p1" : "p2"
    guard atkSide != defSide else { return }
    let atkParts = lastMoveLabel.split(separator: ":", maxSplits: 1)
    guard atkParts.count == 2 else { return }
    let atkSpecies = String(atkParts[1]).trimmingCharacters(in: .whitespaces)
    guard !atkSpecies.isEmpty, atkSpecies != speciesEn else { return }
    let atkKey = "\(atkSide):\(atkSpecies)"
    let crit = (lastCritAt["\(slot): \(speciesEn)"].map { sNow().timeIntervalSince($0) < 6 } ?? false)
        || (critEventMarks["\(slot): \(speciesEn)"].map { $0.turn == currentTurn && $0.atk == lastMoveLabel } ?? false)
    func boostsJson(_ k: String) -> String {
        guard let b = monStates[k]?.boosts, !b.isEmpty else { return "{}" }
        let inner = ["atk", "def", "spa", "spd", "spe"].compactMap { kk -> String? in
            guard let v = b[kk], v != 0 else { return nil }
            return "\"\(kk)\": \(v)"
        }
        return "{\(inner.joined(separator: ", "))}"
    }
    func aliveOnField(_ sidePrefix: String, _ side: String) -> Int {
        var n = 0
        for (slotName, s) in lastSlots where slotName.hasPrefix(sidePrefix) {
            if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { n += 1 }
        }
        return n
    }
    var ev = "{\"k\":\"dmg\",\"turn\":\(currentTurn),\"atk\":\"\(jsonEscape(lastMoveLabel))\",\"def\":\"\(jsonEscape("\(slot): \(speciesEn)"))\",\"move\":\"\(jsonEscape(lastMoveName))\",\"crit\":\(crit)"
    ev += ",\"w\":\"\(logFieldWeather)\",\"t\":\"\(logFieldTerrain)\""
    ev += ",\"atkB\":\(boostsJson(atkKey)),\"defB\":\(boostsJson(key))"
    ev += ",\"atkS\":\"\(jsonEscape(monStates[atkKey]?.status ?? ""))\",\"defS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\""
    ev += ",\"atkMega\":\"\(jsonEscape(monStates[atkKey]?.megaSpecies ?? ""))\",\"defMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\""
    ev += ",\"atkAlive\":\(aliveOnField(atkSide == "p1" ? "mine" : "opp", atkSide)),\"defAlive\":\(aliveOnField(defSide == "p1" ? "mine" : "opp", defSide))"
    ev += ",\"atkHp\":\(monStates[atkKey]?.hpPercent ?? 100),\"defHp\":\(fromPct)"
    // 実数差 (amt) は、基準側と現在側で最大 HP が一致する場合だけ使う。
    // 交代行の HP 表記は確定前に % 形式 (100/100) で出ることがあり、
    // その基準 [100, 100] と実数表記 [37, 177] を引くと、実在しない
    // 被ダメ量 (63) がイベントに載る (実例: 2026-11-21
    // battle_20261121_233243、ウッドハンマーの被ダメとして推定側へ
    // 渡り、攻撃側の自己ダメージと誤認された)
    if defSide == "p1", let pe = effPrevExact, let ce = exact, pe[1] == ce[1], pe[0] > ce[0] {
        ev += ",\"amt\":\(pe[0] - ce[0]),\"max\":\(ce[1])"
    } else {
        ev += ",\"pct\":\(fromPct - toPct)"
    }
    ev += "}"
    if let idx = supersedeIdx {
        battleEvents[idx] = ev
    } else {
        battleEvents.append(ev)
        lastDmgEventPrevExact[key] = prevExact ?? []
    }
    // 行動前に倒れた個体への先行証拠 (spe イベント): この被ダメが
    // 技による直接の KO で、倒れた側がそのターンまだ技も交代も
    // していない場合、攻撃側がその個体より先に行動したことが
    // 確定する。実行された技同士のペア (mv イベント) からは構造的
    // に作れない行動順証拠のため、専用の形で残す。推定側はこれを
    // mv ペアと同種の行動順の観測として扱う。適格性の残り (倒れた
    // 側が優先度技を選んでいた可能性、KO 技自体の優先度) は技
    // データを持つ推定側の判定に委ね、ここでは事実だけを記録する
    // (実例: 2026-11-22 battle_20261122_181745 ターン 1、
    // Archaludon の Steel Beam で行動前の Mega Gardevoir が倒れ、
    // こだわりスカーフ確定の証拠が生成されなかった)
    if directMove, toPct == 0, battleEvents.count < 600 {
        let fastLabel = lastMoveLabel
        let slowLabel = "\(slot): \(speciesEn)"
        let slowMoved = battleEvents.contains {
            $0.contains("\"k\":\"mv\"") && $0.contains("\"turn\":\(currentTurn)")
                && $0.contains("\"label\":\"\(jsonEscape(slowLabel))\"")
        }
        var slowEntered = false
        let turnIdx = battleLog.lastIndex(of: "|turn|\(currentTurn)")
            ?? battleLog.lastIndex(where: { $0.hasPrefix("|turn|") })
        if let tIdx = turnIdx {
            for l in battleLog[(tIdx + 1)...]
            where l.hasPrefix("|switch|\(slowLabel)|") || l.hasPrefix("|drag|\(slowLabel)|") {
                slowEntered = true
                break
            }
        }
        if !slowMoved && !slowEntered {
            var sev = "{\"k\":\"spe\",\"turn\":\(currentTurn),\"fast\":\"\(jsonEscape(fastLabel))\",\"slow\":\"\(jsonEscape(slowLabel))\",\"move\":\"\(jsonEscape(lastMoveName))\""
            sev += ",\"fastB\":\(boostsJson(atkKey)),\"slowB\":\(boostsJson(key))"
            sev += ",\"fastMega\":\"\(jsonEscape(monStates[atkKey]?.megaSpecies ?? ""))\",\"slowMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\""
            sev += "}"
            if let idx = battleEvents.lastIndex(where: {
                $0.contains("\"k\":\"spe\"") && $0.contains("\"turn\":\(currentTurn)")
                    && $0.contains("\"slow\":\"\(jsonEscape(slowLabel))\"")
            }) {
                battleEvents[idx] = sev
            } else {
                battleEvents.append(sev)
            }
        }
    }
}

func recordRecoilEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, moveName: String = "") {
    guard battleEvents.count < 600 else { return }
    let label = "\(slot): \(speciesEn)"
    func boostsJson(_ k: String) -> String {
        guard let b = monStates[k]?.boosts, !b.isEmpty else { return "{}" }
        let inner = ["atk", "def", "spa", "spd", "spe"].compactMap { kk -> String? in
            guard let v = b[kk], v != 0 else { return nil }
            return "\"\(kk)\": \(v)"
        }
        return "{\(inner.joined(separator: ", "))}"
    }
    let sidePrefix = key.hasPrefix("p1") ? "mine" : "opp"
    let side = key.hasPrefix("p1") ? "p1" : "p2"
    var alive = 0
    for (slotName, s) in lastSlots where slotName.hasPrefix(sidePrefix) {
        if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { alive += 1 }
    }
    var ev = "{\"k\":\"dmg\",\"turn\":\(currentTurn),\"atk\":\"\(jsonEscape(label))\",\"def\":\"\(jsonEscape(label))\",\"move\":\"\(jsonEscape(moveName.isEmpty ? lastMoveName : moveName))\",\"crit\":false"
    ev += ",\"w\":\"\(logFieldWeather)\",\"t\":\"\(logFieldTerrain)\""
    ev += ",\"atkB\":\(boostsJson(key)),\"defB\":\(boostsJson(key))"
    ev += ",\"atkS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\",\"defS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\""
    ev += ",\"atkMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\",\"defMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\""
    ev += ",\"atkAlive\":\(alive),\"defAlive\":\(alive)"
    ev += ",\"atkHp\":\(monStates[key]?.hpPercent ?? toPct),\"defHp\":\(fromPct)"
    ev += ",\"pct\":\(fromPct - toPct)"
    ev += "}"
    battleEvents.append(ev)
}

func aliveOnFieldCount(_ platePrefix: String, _ side: String) -> Int {
    var n = 0
    for (name, s) in lastSlots where name.hasPrefix(platePrefix) {
        if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { n += 1 }
    }
    return n
}

func awaitingReplacement(_ platePrefix: String, _ side: String) -> Bool {
    if aliveOnFieldCount(platePrefix, side) >= 2 { return false }
    let seen = fieldSeen[side] ?? []
    if seen.count < 4 { return true }   // まだ場に出ていない選出枠が残っている
    let onField = Set(lastSlots.filter { $0.key.hasPrefix(platePrefix) }.map { $0.value.speciesEn })
    return seen.contains { !onField.contains($0) && (monStates["\(side):\($0)"]?.hpPercent ?? 0) > 0 }
}

func anyAwaitingReplacement() -> Bool {
    sideAwaitingReplacement("mine", "p1") || sideAwaitingReplacement("opp", "p2")
}

func sideAwaitingReplacement(_ prefix: String, _ side: String) -> Bool {
    if aliveOnFieldCount(prefix, side) >= 2 { return false }
    let slotNames = side == "p1" ? ["p1a", "p1b"] : ["p2a", "p2b"]
    if !slotNames.contains(where: { faintedSlots[$0] != nil }) { return false }
    let seen = fieldSeen[side] ?? []
    if seen.count < 4 { return true }
    let onField = Set(lastSlots.filter { $0.key.hasPrefix(prefix) }.values.map { $0.speciesEn })
    return seen.contains { !onField.contains($0) && (monStates["\(side):\($0)"]?.hpPercent ?? 0) > 0 }
}

func entryEffectPending(key: String) -> Bool {
    let otherPrefix = key.hasPrefix("p1") ? "opp" : "mine"
    let otherSide = key.hasPrefix("p1") ? "p2" : "p1"
    return !pendingSwitchSpecies.filter({ $0.key.hasPrefix(otherPrefix) }).isEmpty
        || sideAwaitingReplacement(otherPrefix, otherSide)
        // 開幕は、相手の先発がプレートに読まれる前に特性の効果文が
        // 届くことがある。その間は入場効果が未確定として扱う
        // (実例: 2026-11-22 battle_20261122_091721、いかくの攻撃低下行が
        //  原因の交代行・特性行より先に出た)
        || (currentTurn <= 1 && (fieldSeen[otherSide]?.count ?? 0) < 2)
}

func processPlates(_ hits: [String: SlotState]) {
    // 開始処理を行う条件: (a) まだ開始していない、または (b) 勝敗確定後に
    // 前試合と異なる種族のプレートが現れた (= 次試合の開始証拠なので、
    // 前試合のログへ連結しないよう先に新しい試合を始める。同試合の余韻で
    // プレートが変わらない間は始め直さない)
    if !flagManualMode && (!logStarted || (winLogged && hits.contains { (name, s) in lastSlots[name]?.speciesEn != s.speciesEn })) {
        // 選出画面を経ずにプレートから対戦が始まった場合は、開始処理を
        // 取りこぼしている (対戦開始時に画面がキーボード等で覆われていた、
        // アプリが裏画面だった等。2026-11-21 のユーザー報告)。相手の先発は
        // プレートで確定している種族なので、ヘッダーの |poke| に載せて
        // から開始し、復旧した事実をターミナルとデバッグ情報に残す
        let recovered = !previewTeamWritten
        if recovered {
            for name in ["oppA", "oppB"] {
                if let s = hits[name], !oppTeamSeen.contains(s.speciesEn) {
                    oppTeamSeen.append(s.speciesEn)
                }
            }
        }
        startBattleLog()
        if recovered {
            let leads = ["oppA", "oppB"].compactMap { hits[$0]?.speciesEn }
            print("[log] 対戦開始を取りこぼしたため、プレートから開始状態を復旧しました (相手先発: \(leads.joined(separator: ", ")))")
            fflush(stdout)
            let startNow = sNow()
            debugCapture(kind: "late_start", key: "late_start", rawText: "",
                         detail: ["oppLeads": leads, "note": "preview not captured (screen covered or backgrounded)",
                                  "preStart": preStartEvents.map { "-\(Int(startNow.timeIntervalSince($0.0)))s \($0.1)" },
                                  "readerUptimeSec": Int(startNow.timeIntervalSince(readerStartedAt))])
        }
    }
    // 保留中のランク変化行: 交代行が来なくても 30 秒経ったら出す
    flushHeldBoostsTimeout()
    // 遅延中のひんし行: 文が来なくても 1.5 秒経ったら出す
    if !pendingFaints.isEmpty {
        let now = sNow()
        let ready = pendingFaints.filter { now.timeIntervalSince($0.at) > 1.5 }
        if !ready.isEmpty {
            pendingFaints.removeAll { now.timeIntervalSince($0.at) > 1.5 }
            for f in ready {
                if faintedSlots[f.slot] == f.speciesEn { continue }
                if !faintStillValid(f) { continue }
                faintedSlots[f.slot] = f.speciesEn
                emitLog("|faint|\(f.slot): \(f.speciesEn)")
            }
        }
    }
    // 枠の入れ替わり: 両枠が互いの登録種族を同時に示し、HP もそれぞれの
    // 登録値と一致する場合は、2 件の交代ではなく表示位置の入れ替わり
    // として登録を入れ替える (交代行は出さない)。ひんし交代の後任が
    // 想定と逆の枠に表示される場合に起きる。2 回続けて観測されたら確定
    // する (実例: 2026-11-22 battle_20261122_070237、コータスが左枠・
    //  オオニューラが右枠に表示され、幻の交代行と両枠ともオオニューラ
    //  という状態破損が起きた)
    for (a, b) in [("mineA", "mineB"), ("oppA", "oppB")] {
        let sideKey = a.hasPrefix("mine") ? "mine" : "opp"
        guard let pa = lastSlots[a], let pb = lastSlots[b],
              let ha = hits[a], let hb = hits[b],
              pa.speciesEn != pb.speciesEn,
              ha.speciesEn == pb.speciesEn, hb.speciesEn == pa.speciesEn,
              faintedSlots[slotId(a)] == nil, faintedSlots[slotId(b)] == nil,
              abs(ha.hpPercent - pb.hpPercent) <= 3, abs(hb.hpPercent - pa.hpPercent) <= 3
        else { slotSwapPending[sideKey] = nil; continue }
        if slotSwapPending[sideKey]?.a == ha.speciesEn {
            slotSwapPending[sideKey]?.count += 1
        } else {
            slotSwapPending[sideKey] = (a: ha.speciesEn, b: hb.speciesEn, count: 1)
        }
        guard (slotSwapPending[sideKey]?.count ?? 0) >= 2 else { continue }
        slotSwapPending[sideKey] = nil
        lastSlots[a] = ha
        lastSlots[b] = hb
        let ea = lastEmittedPct[a]; lastEmittedPct[a] = lastEmittedPct[b]; lastEmittedPct[b] = ea
        let fa = firstEntryPlateHP[a]; firstEntryPlateHP[a] = firstEntryPlateHP[b]; firstEntryPlateHP[b] = fa
        for p in [a, b] {
            pendingDamagePct[p] = nil; pendingDamageCount[p] = nil; pendingDamageSince[p] = nil
            pendingSwitchSpecies[p] = nil; pendingSwitchCount[p] = nil; pendingSwitchSince[p] = nil; pendingSwitchCandidates[p] = nil
            heldLine[p] = nil; suspectJump[p] = nil
        }
        debugCapture(kind: "slot_swap", key: "slot_swap:\(sideKey):\(currentTurn)", rawText: "",
                     detail: ["side": sideKey, "a": "\(a)=\(ha.speciesEn)", "b": "\(b)=\(hb.speciesEn)", "turn": currentTurn])
        if debugMode { print("[reader] 枠の表示位置の入れ替わりを検出し、登録を入れ替えました: \(a)=\(ha.speciesEn) / \(b)=\(hb.speciesEn)") }
        fflush(stdout)
    }
    for plate in plates {
        guard var s = hits[plate.name] else { continue }
        let slot = slotId(plate.name)
        let side = plate.name.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        if monStates[key] == nil { monStates[key] = MonState() }
        // 登録チームの実数値がある種族は、プレート読みの最大値で上書きしない
        // (誤読した最大値が knownMax として固定され、正しい読みまで弾く事故を防ぐ)。
        // ただし、この試合で読み側の最大値を採用済みの種族は読みに従う
        if let m = s.hpMax, (teamEntries[s.speciesEn]?["stats"] as? [String: Int])?["hp"] == nil
            || battleMaxOverride[s.speciesEn] == m {
            monStates[key]?.hpMax = m
        }
        // 自軍の読みの最大が既知の最大と食い違う場合 (最大の断片
        // 読み 145 -> 45 等)、割合の方は正しいことが多いため、行の
        // 構築に使う現在値を既知の最大で組み直す。読みの最大その
        // ものの採否は noteBattleMaxRead が別途扱う (実例:
        // 2026-11-22 battle_20261122_171847、サーナイトの被ダメ行が
        // 11/45 になった)
        if side == "p1", let readMax = s.hpMax, s.hpCur != nil,
           let entry = speciesDict.first(where: { $0.en == s.speciesEn }),
           let knownMax = battleKnownMax(speciesEn: s.speciesEn, grp: formeGroup(entry)),
           knownMax > 0, readMax != knownMax {
            if !maxReadPlausible(readMax: readMax, knownMax: knownMax), let prevSlot = lastSlots[plate.name],
               prevSlot.speciesEn == s.speciesEn {
                // 既知の最大と大きく食い違う読みは、最大値の桁誤読
                // ではなく数字の連結等の化けで、割合自体が作られて
                // いる (実例: 2026-11-23 battle_20261123_062508、
                // 177/177 が「177277」と読まれ 64% の幽霊行が出た)。
                // このフレームの HP は読めなかったものとして前回
                // 値を保つ (最大値の採用ゲートと同じ 36 の閾値)
                let curBar = s.hpBarPct
                s = prevSlot
                s.hpBarPct = curBar
            } else {
                s.hpCur = Int((Double(s.hpPercent) / 100.0 * Double(knownMax)).rounded())
                s.hpMax = knownMax
            }
        }
        let prev = lastSlots[plate.name]
        if prev?.speciesEn != s.speciesEn {
            // 交代の確定は、同じ種族が 2 フレーム連続でその枠に見えてから。
            // 繰り出しアニメーションの途中では一瞬だけ隣の枠で読めることが
            // あり、即時確定すると誤った枠への |switch| と巻き戻しが多発する
            // (実例: 登場直後のグレンアルマが p1a / p1b の両方に記録された)
            // 交代候補は区間で管理する (フェーズ3): 候補ごとの証拠
            // (回数・初出・最終観測) を保持し、別候補や占有者が間に
            // 読まれても証拠は消えない。最終観測から 3 秒を超えた候補は
            // 期限切れとして落とす。pendingSwitch* は現在のリーダー
            // 候補の表示として同期する (既存の読み手はそのまま使う)
            let psNow = sNow()
            var psCands = pendingSwitchCandidates[plate.name] ?? [:]
            psCands = psCands.filter { psNow.timeIntervalSince($0.value.lastSeen) <= 3 }
            var psCand = psCands[s.speciesEn] ?? (count: 0, firstSeen: psNow, lastSeen: psNow)
            psCand.count += 1
            psCand.lastSeen = psNow
            psCands[s.speciesEn] = psCand
            pendingSwitchCandidates[plate.name] = psCands
            // リーダーが替わった時だけ開始時刻を取り直す (同じ候補の
            // 再読みで開始時刻が若返ると、保留の経過時間で見るガード
            // (同種族ガード・要員待ち) が永遠に解けない)
            if pendingSwitchSpecies[plate.name] != s.speciesEn || pendingSwitchSince[plate.name] == nil {
                pendingSwitchSince[plate.name] = psCand.firstSeen
            }
            pendingSwitchSpecies[plate.name] = s.speciesEn
            pendingSwitchCount[plate.name] = psCand.count
            // 交代技で戻ることが確定している側は、後任を 1 回の読みで
            // 確定する (戻り文の消費時に pivotReturnAt が立つ)
            // 交代技の戻り消費、または繰り出し文の文証拠がある場合は、
            // 後任を 1 回の読みで確定する
            let pivotFast = pivotReturnAt[side].map { sNow().timeIntervalSince($0) < 20 } ?? false
            let textFast = sendOutTextSeen[side].map { $0.species == s.speciesEn && sNow().timeIntervalSince($0.at) < 20 } ?? false
            let confirmReads = (pivotFast || textFast) ? 1 : 2
            if (pendingSwitchCount[plate.name] ?? 0) >= confirmReads {
                // 同種族が相方枠に在席したままの確定は、同時交代時の
                // 隣枠への写り込みとして保留する (同一個体が 2 枠に
                // 同時に存在することはない。実例: 2026-11-22
                // battle_20261122_051707、場にいる Gardevoir が別枠にも
                // 「入場」した)。相方側の記録が古いだけの場合に備え、
                // 保留が 6 秒を超えたら確定に進む
                let sibPlate = plate.name.hasPrefix("mine") ? (plate.name.hasSuffix("A") ? "mineB" : "mineA") : (plate.name.hasSuffix("A") ? "oppB" : "oppA")
                if let sib = lastSlots[sibPlate]?.speciesEn, sameSpeciesFamily(sib, s.speciesEn),
                   sNow().timeIntervalSince(pendingSwitchSince[plate.name] ?? sNow()) < 6 {
                    debugCapture(kind: "switch_species_dup", key: "switch_species_dup:\(plate.name):\(s.speciesEn):\(currentTurn)", rawText: "",
                                 detail: ["plate": plate.name, "species": s.speciesEn, "sibling": sibPlate, "turn": currentTurn])
                    continue
                }
                let pendingSwitchAge = pendingSwitchSince[plate.name].map { sNow().timeIntervalSince($0) } ?? 0
                // 交代要員を選んでいる間は、控え一覧画面のバーが場のプレートと
                // して読めて、生きている枠にまで交代行が出ることがある
                // (実例: 2026-11-20、グレンアルマの交代要員選択中に
                //  オオニューラが p1a に出現し、直後にサーナイトの交代行も
                //  重複した)。ひんしの枠への交代 (交代要員そのもの) は通す。
                // この破棄は自軍の選択画面が映る場合だけが根拠なので、
                // 自軍側に限る。相手側のプレートは選択画面に映らず、
                // 相手の任意交代が ひんし交代の確定待ちと重なると本物の
                // 交代まで落としてしまう (実例: 2026-11-22
                // battle_20261122_054802、ターン9に相手の任意交代
                // (イエッサン→サーナイト) が破棄され、交代行の順序が
                // 逆転した)
                let prefix = plate.name.hasPrefix("mine") ? "mine" : "opp"
                // 確定試行が 20 秒以上続いている交代は、要員選択画面の
                // 映り込みではあり得ない (選択は交代の確定で終わる) ため、
                // 要員待ちの破棄対象から外す。後任の交代が記録されないまま
                // 要員待ちが居座り、別枠の本物の交代まで巻き込んで落とし
                // 続けた実例: 2026-11-22 battle_20261122_103530、
                // オオニューラの交代が登録で弾かれ続け、グレンアルマの
                // 再登場が全てこのガードで破棄された
                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                    && pendingSwitchAge < 20
                if replacementBusy {
                    // 破棄ではなく保留にする: 候補の蓄積を消すと、要員
                    // 選択が終わった後に確定する道まで断たれる (実例:
                    // 2026-11-22 battle_20261122_231107、ターン2頭の
                    // Charizard→Venusaur の確定試行が Farigiraf の
                    // ひんし後の選択中に届いて破棄され、交代行が
                    // ターン末尾へ遅れた)。静定時計を現在へ戻して
                    // 先送りすれば、選択画面の幻の候補は画面が消えた
                    // 後に新たな静定を得られず期限で落ち、本物の交代
                    // だけが場の読みで静定し直して確定する
                    if var cand = pendingSwitchCandidates[plate.name]?[s.speciesEn] {
                        cand.firstSeen = sNow()
                        cand.count = 1
                        pendingSwitchCandidates[plate.name]?[s.speciesEn] = cand
                    }
                    pendingSwitchSince[plate.name] = sNow()
                    pendingSwitchCount[plate.name] = 1
                } else {
                    pendingSwitchSpecies[plate.name] = nil
                    pendingSwitchCount[plate.name] = nil
                    pendingSwitchSince[plate.name] = nil
                    pendingSwitchCandidates[plate.name] = nil
                    if sendOutTextSeen[side]?.species == s.speciesEn { sendOutTextSeen[side] = nil }
                }
                if !replacementBusy {
                    crossCheckPlateSpecies(plateName: plate.name, speciesEn: s.speciesEn)
                    // 前の種族のランク変化・かるわざの解除は、下の |switch| 行の
                    // applyEvent が行う (交代に伴う状態変化は行から導く)
                    // 入場時点の HP と前回出場時の HP の差は、交代で入った
                    // 直後に受けた技 (や さいせいさいぼう の回復) の分。
                    // 交代行の HP に吸収されて被ダメ行が出ないため、後で補う
                    let prevPct = monStates[key]?.hpPercent ?? 100
                    let prevText = monStates[key]?.hpText ?? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100")
                    pendingDamagePct[plate.name] = nil
                    heldLine[plate.name] = nil
                    // 試合開始時の先発は必ず満タンで出る。登場アニメーション
                    // 途中のバー読み (満タン未満) をそのまま採用すると、
                    // 以後の全ての割合計算がずれる (実例: 2026-11-20 vs
                    // チャンピオン戦、サーナイト 58/145・イエッサン 74/177
                    // で登場したことになった)。技も被ダメもまだ無い間の
                    // 初登場だけは満タンとして採用する
                    let openingLead = prev == nil && actionSeq == 0
                        && !battleLog.contains { $0.hasPrefix("|move|") || $0.hasPrefix("|-damage|") }
                    // ひんし交代での初登場も、設置物が無い限り満タンでしか
                    // 出ない (バーは登場アニメーションで下から満ちていくため、
                    // 途中値を採用すると幻の被ダメ→全回復の組が出る。実例:
                    // 2026-11-20 vs leslie 戦、グレンアルマが 61/161 で登場し
                    // 翌ターン 161/161 に回復した)。初登場を取り逃がして
                    // 後から発見した場合は実ダメージを消しかねないため、
                    // 前任のひんしが記録済みの枠に限る (交代待ち判定は場が
                    // 1 体の間ずっと立つため条件に使えない)
                    let firstEntry = !(fieldSeen[side]?.contains(s.speciesEn) ?? false)
                        && (monStates[key]?.hpPercent ?? 100) >= 100
                    let replacementEntry = firstEntry && (battleHazards[side] ?? [:]).isEmpty
                        && faintedSlots[slot] != nil
                    let adoptFull = openingLead || replacementEntry
                    let effPct = adoptFull ? 100 : s.hpPercent
                    let effText = adoptFull ? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100") : hpTextFor(s)
                    // 交代行の HP は「入場時点の値」として前回出場時の
                    // 値 (prevPct / prevText) を載せ、入場までに受けた
                    // ダメージ・回復は直後の補完行に担わせる (実例:
                    // 2026-11-22 battle_20261122_050512、ガブリアスの
                    // 交代行が被弾後の 156/185 を載せて同値の被ダメ行と
                    // 重なり、地形回復込みの交代行にも同値の回復行が
                    // 重なった)。ログの基準値 (lastEmittedPct) も交代行
                    // の値に合わせ、補完行がその差分を進める。補完行が
                    // 抑止された場合も、基準は交代行と一致したまま
                    // 次のプレート読みが差分を再駆動する
                    let compensating = effPct != prevPct && !adoptFull
                    lastEmittedPct[plate.name] = compensating ? prevPct : effPct
                    monStates[key]?.hpPercent = effPct
                    monStates[key]?.hpText = effText
                    // 初登場は前回記録が無いため、入場時点の表記は
                    // その種族の満タン表記で組み立てる
                    let entryText = firstEntry ? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100") : prevText
                    var hp = compensating ? entryText : effText
                    if let st = monStates[key]?.status, !st.isEmpty { hp += " \(st)" }
                    emitLog("|switch|\(slot): \(s.speciesEn)|\(s.speciesEn)|\(hp)")
                    sitrusWatch[key] = nil   // 交代を挟んだ監視は持ち越さない
                    if firstEntry { firstEntryPlateHP[plate.name] = effText }
                    recordSwitchIn(side: side, slot: slot, speciesEn: s.speciesEn)
                    if side == "p2" { checkHeaderMismatch(slot: slot, speciesEn: s.speciesEn) }
                    // 交代で入った直後の HP 減少は、設置物ダメージとして
                    // 帰属させる (Showdown の [from] 表記)
                    if effPct < prevPct && !adoptFull {
                        if battleHazards[side]?["Stealth Rock"] != nil { pendingStatusFrom[key] = ("Stealth Rock", sNow()) }
                        else if battleHazards[side]?["Spikes"] != nil { pendingStatusFrom[key] = ("Spikes", sNow()) }
                    }
                    // 初登場でも、入場時点で既に受けていたダメージは
                    // 被ダメ行として 1 回だけ出す。出さないと、ダメージが
                    // 交代行の HP に畳み込まれ、被ダメの記録と推定用
                    // イベントが丸ごと消える (実例: 2026-11-21
                    // battle_20261121_234913、交代で入ったガブリアスへの
                    // ねっぷうが入場時点で 19% 減・ダメージ行なし)。
                    // 以前は「交代行と同値の重複」とみなして初登場では
                    // 出さなかったが、その判定が実ダメージの喪失を招いた。
                    // 他の経路から同値の行が重なることは、同値ガード
                    // (firstEntryPlateHP) が防ぐため、ここでの 1 本を
                    // 正規の記録とする (ガードはこの呼び出しの間だけ外す)
                    if effPct != prevPct {
                        if firstEntry { firstEntryPlateHP[plate.name] = nil }
                        _ = emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: prevPct, toPct: effPct, hpText: effText, force: true)
                        if firstEntry { firstEntryPlateHP[plate.name] = effText }
                    }
                    faintedSlots.removeValue(forKey: slot)
                    // 0% で登場した (交代直後に技を受けて倒れた等) 場合は
                    // ひんし行を補う
                    if effPct == 0 { deferFaint(slot: slot, speciesEn: s.speciesEn) }
                    lastSlots[plate.name] = adoptFull
                        ? SlotState(speciesEn: s.speciesEn, hpPercent: 100, hpCur: s.hpMax, hpMax: s.hpMax) : s
                    // ターン開始時の任意交代が、演出の遮蔽で確定が遅れて
                    // 技行より後ろに出た場合は、ターン行の直後へ引き戻す。
                    // 交代した側がこの区間でまだ何もしていない (出す側の
                    // 技行・被ダメ行・ひんし行が区間に無い) 場合に限る
                    // ため、とんぼがえし等の交代技や だっしゅつボタン の
                    // 交代は対象にならない (実例: 2026-11-22
                    // battle_20261122_103530、ゴリランダーのターン1の
                    // 交代が ハイパーボイス より後ろに置かれた)
                    // ひんし交代は引き戻しの対象外: 出ていく側が 0% で
                    // 記録されている (ひんし行自体が落ちていても) 場合と、
                    // ひんし行が出ている枠は、任意交代ではないため戻さない
                    // (実例: 2026-11-22 battle_20261122_171847、ターン3で
                    // 倒れた Charizard の交代要員 Kingambit がターン3
                    // 冒頭の任意交代として引き戻された)
                    if currentTurn >= 1, let prevSp = prev?.speciesEn,
                       prev?.hpPercent != 0, faintedSlots[slot] == nil,
                       let turnIdx0 = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                        let outLabel = "\(slot): \(prevSp)"
                        let seg = battleLog[(turnIdx0 + 1)...]
                        let segHasMove = seg.contains { $0.hasPrefix("|move|") }
                        let outActed = seg.contains { l in
                            guard l.hasPrefix("|move|") || l.hasPrefix("|-damage|") || l.hasPrefix("|faint|") else { return false }
                            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                            return f.count >= 3 && f[2] == outLabel
                        }
                        if segHasMove && !outActed {
                            // 繰り出し文がこのターンに入ってから最初の
                            // 技より前に見えていた場合は、そのターンの
                            // 開始交代である直接証拠があるため、発達
                            // した区間でも引き戻す (実例: 2026-11-23
                            // battle_20261123_090354 ターン3、コータス
                            // の交代は文ではターン頭、プレート確定は
                            // ターン末尾だった)
                            let sideKey = String(slot.prefix(2))
                            let announceOK = sendOutTextSeen[sideKey].map { ev in
                                ev.species == s.speciesEn && ev.at > lastTurnLineAt
                                    && (segmentFirstMoveAt.map { ev.at < $0 } ?? false)
                            } ?? false
                            let pulled = pullBackSwitchBlock(label: "\(slot): \(s.speciesEn)", requireEarlySegment: !announceOK)
                            if !pulled.proto.isEmpty {
                                if let ti = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) {
                                    battleLog.insert(contentsOf: pulled.proto, at: ti + 1)
                                }
                                if !pulled.display.isEmpty {
                                    var dTurn = -1
                                    for (i, l) in displayLog.enumerated() where l.hasPrefix("Turn ") { dTurn = i }
                                    if dTurn >= 0 { displayLog.insert(contentsOf: pulled.display, at: dTurn + 1) }
                                }
                                debugCapture(kind: "turn_guard", key: "turn_guard_pullback:\(slot):\(s.speciesEn):\(currentTurn)", rawText: "",
                                             detail: ["action": "switch_pulled_to_turn_head", "slot": slot, "species": s.speciesEn, "turn": currentTurn, "readerBuild": readerBuild])
                            }
                        }
                    }
                } else {
                    // 交代要員選択中のガードで、確定済みの交代が破棄された
                    // ことを証拠として残す (破棄自体は従来どおり)。
                    // 2026-11-21 battle_20261121_150535 では mineB の交代が
                    // 数ターン確定せず、ガードが確定試行を消費した可能性を
                    // 否定できなかったが、記録が無く切り分けられなかった
                    if debugMode { print("[reader] 交代の確定が交代要員選択中のため破棄されました: \(plate.name) -> \(s.speciesEn)") }
                    fflush(stdout)
                    debugCapture(kind: "switch_guard_drop",
                                 key: "switch_guard_drop:\(plate.name):\(s.speciesEn)",
                                 rawText: "",
                                 detail: ["slot": slot, "species": s.speciesEn,
                                          "occupant": prev?.speciesEn ?? "",
                                          "fainted": faintedSlots.filter { $0.key.hasPrefix(side) }.map { "\($0.key):\($0.value)" }.joined(separator: ","),
                                          "turn": currentTurn,
                                          "readerBuild": readerBuild])
                }
            }
        } else {
            // 占有者の再読みでは交代候補を即消去しない (フェーズ3):
            // 候補は最終観測からの期限 (3 秒) で自然に落ち、リーダーが
            // 期限切れになったら残りの最新候補へ表示を引き継ぐ
            let occNow = sNow()
            if var occCands = pendingSwitchCandidates[plate.name] {
                occCands = occCands.filter { occNow.timeIntervalSince($0.value.lastSeen) <= 3 }
                pendingSwitchCandidates[plate.name] = occCands.isEmpty ? nil : occCands
                if occCands.isEmpty {
                    pendingSwitchSpecies[plate.name] = nil
                    pendingSwitchCount[plate.name] = nil
                    pendingSwitchSince[plate.name] = nil
                } else if let cur = pendingSwitchSpecies[plate.name], occCands[cur] == nil,
                          let lead = occCands.max(by: { $0.value.lastSeen < $1.value.lastSeen }) {
                    pendingSwitchSpecies[plate.name] = lead.key
                    pendingSwitchCount[plate.name] = lead.value.count
                    pendingSwitchSince[plate.name] = lead.value.firstSeen
                }
            } else {
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
            }
            // ひんし確定済みの枠は、交代が確定するまでプレート読みを無視する
            // (交代要員選択画面で満タンのバーが読めて「全回復」行が出たり、
            //  0% に戻って ひんし行が二重に出たりした実例: 2026-11-20)。
            // ただし生存読みが安定して続く場合は、ひんし自体が誤読
            // だったとして取り消す (実例: 2026-11-22
            // battle_20261122_181745、ターン 2 の幻のひんし。バーは
            // 42% を示していた)。条件は 20% 以上の読みが 3 回・
            // 1.5 秒以上続き、ひんし行から 3 秒以上経っていること
            if faintedSlots[slot] == s.speciesEn {
                var revived = false
                if s.hpPercent >= 20,
                   sNow().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                    let rc = (faintReviveCount[plate.name] ?? 0) + 1
                    faintReviveCount[plate.name] = rc
                    if faintReviveSince[plate.name] == nil { faintReviveSince[plate.name] = sNow() }
                    if rc >= 3, sNow().timeIntervalSince(faintReviveSince[plate.name] ?? .distantFuture) >= 1.5 {
                        faintedSlots.removeValue(forKey: slot)
                        faintedSpecies.remove(key)
                        faintReviveCount[plate.name] = nil
                        faintReviveSince[plate.name] = nil
                        lastEmittedPct[plate.name] = s.hpPercent
                        debugCapture(kind: "faint_guard", key: "faint_revived:\(slot):\(s.speciesEn)", rawText: "",
                                     detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
                        revived = true
                    }
                } else {
                    faintReviveCount[plate.name] = nil
                    faintReviveSince[plate.name] = nil
                }
                if !revived { continue }
            }
            // 状態 (state.json) は即時更新し、ログ行だけ確定待ちにする
            monStates[key]?.hpPercent = s.hpPercent
            monStates[key]?.hpText = hpTextFor(s)
            // 排出基準が 0 のまま生存読みが届いた場合は、過去のひんし
            // 記録が誤りだったとして基準を現在値へ戻す。0 のままだと
            // 回復が無言で飲み込まれ、本物のひんし (被ダメ行の合成
            // 条件・ひんし文の確定条件) まで成立しなくなる (実例:
            // 2026-11-22 battle_20261122_181745、ターン 2 の幻の
            // ひんしがターン 7 の ほろびのうた の ひんしを消した)
            if s.hpPercent >= 20, (lastEmittedPct[plate.name] ?? -1) == 0,
               pendingFaints.allSatisfy({ $0.slot != slot }),
               sNow().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                lastEmittedPct[plate.name] = s.hpPercent
                faintedSpecies.remove(key)
                debugCapture(kind: "faint_guard", key: "faint_revived:\(slot):\(s.speciesEn)", rawText: "",
                             detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
            }
            let emitted = lastEmittedPct[plate.name] ?? s.hpPercent
            // HP 3系統の照合 (改善計画フェーズ2): 数字 OCR と HP バーの
            // 画素長が大きく食い違う場合は、黙って選ばず証拠として残す
            // (状態への組み込みは従来どおり数字 OCR 優先。ログ確定値が
            // 第3系統として文脈に併記される)
            if let bar = s.hpBarPct, abs(bar - s.hpPercent) >= 25 {
                debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)",
                             rawText: "",
                             detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                      "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                      "readerBuild": readerBuild])
            }
            if s.hpPercent == emitted {
                // 保留中の被ダメ値がある間は、基準値と一致する読みが
                // 1 回あっただけでは保留を消さない (アニメーション中の
                // 一過性の戻り読みで本物の被ダメが消えた疑い: 2026-11-22
                // battle_20261122_103530、ドレインキッスを受けた
                // サーナイトの 145→73 が行にならなかった)。2 回続けて
                // 基準値に戻ったら、保留側が誤読だったとして消す
                if pendingDamagePct[plate.name] != nil {
                    let rc = (pendingReturnCount[plate.name] ?? 0) + 1
                    if rc >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {
                        pendingReturnCount[plate.name] = rc
                    }
                } else {
                    pendingDamagePct[plate.name] = nil
                    pendingDamageCount[plate.name] = nil
                }
            } else if s.hpPercent == 0 {
                // 0% (ひんし) は原則即時だが、隣の枠の 0% が一瞬だけ混入
                // する誤読で「幻の ひんし」になった実例があるため、
                // 2 フレーム連続で 0% のときだけ確定する
                // (実例: 2026-11-20、場に残っていたアブソルが 0% と
                //  誤読されて ひんし行まで出た)
                if pendingDamagePct[plate.name] == 0 {
                    let n = (pendingDamageCount[plate.name] ?? 1) + 1
                    if n >= 2 && protectMoveTurn[slot] == currentTurn {
                        // このターン まもる を使った枠は、そのターンの攻撃
                        // では倒れない。0% の読みは演出中の誤読として
                        // 捨てる (実例: 2026-11-22 battle_20261122_103530、
                        // まもるで防いだフラエッテに幻のひんしが出て、
                        // 次ターンの本物のひんしが重複として消えた)。
                        // 天候・状態異常等の残りダメージで倒れた場合は、
                        // ひんし文の経路が別途ひんし行を補う
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                        debugCapture(kind: "faint_guard", key: "faint_guard_protected:\(slot):\(currentTurn)", rawText: "",
                                     detail: ["reason": "protected_zero_read", "slot": slot, "species": s.speciesEn, "turn": currentTurn, "readerBuild": readerBuild])
                    } else if n >= 2 {
                        // バー計測が 0% 読みと明確に食い違う場合は
                        // ひんしにしない。バーが 25% 以上残っていれば
                        // 誤読として棄却し、11〜24% では判断を保留して
                        // 次の読みで再判定する (実例: 2026-11-22
                        // battle_20261122_181745、Sneasler のバーが
                        // 42% を示していたのに 0% 読みで幻のひんし行が
                        // 出て、記録全体が連鎖的に崩れた。従来の棄却
                        // 条件はバー 50% 以上で、この値に届かなかった)
                        if let bar = s.hpBarPct, bar >= 25 {
                            pendingDamagePct[plate.name] = nil
                            pendingDamageCount[plate.name] = nil
                            pendingDamageSince[plate.name] = nil
                            pendingReturnCount[plate.name] = nil
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):0:\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": 0,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_zero", "readerBuild": readerBuild])
                        } else if let bar = s.hpBarPct, bar > 10 {
                            pendingDamageCount[plate.name] = n
                        } else {
                            pendingDamagePct[plate.name] = nil
                            pendingDamageCount[plate.name] = nil
                            pendingDamageSince[plate.name] = nil
                            pendingReturnCount[plate.name] = nil
                            // 自軍の 0% 行の分母は、判明している実数の
                            // 最大値で統一する (% 読みしかない場合に
                            // 0/100 へ切り替わって表記が割れた実例:
                            // 同バトル、Gardevoir の 35/145 → 0/100)
                            var zeroText = monStates[key]!.hpText
                            if plate.name.hasPrefix("mine"), s.hpCur == nil,
                               let e0 = speciesDict.first(where: { $0.en == s.speciesEn }),
                               let km = battleKnownMax(speciesEn: s.speciesEn, grp: formeGroup(e0)) {
                                zeroText = "0/\(km)"
                            }
                            emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: emitted, toPct: 0, hpText: zeroText)
                        }
                    } else {
                        pendingDamageCount[plate.name] = n
                    }
                } else {
                    pendingDamagePct[plate.name] = 0
                    pendingDamageCount[plate.name] = 1
                    pendingDamageSince[plate.name] = sNow()
                }
            } else if pendingDamagePct[plate.name] == s.hpPercent {
                pendingReturnCount[plate.name] = nil
                // 同じ値が 3 回続き、かつ現れてから 2.0 秒経った = アニメーションが
                // 落ち着いた (段階アニメーションは途中で 1 秒近く止まることが
                // あり、回数だけでは途中値を確定してしまうため時間でも見る。
                // 範囲技の 2 体同時被弾では片方のバーがもう片方の演出の間
                // 止まるため、当初の 1.2 秒では途中値が確定した)
                let n = (pendingDamageCount[plate.name] ?? 1) + 1
                let stable = sNow().timeIntervalSince(pendingDamageSince[plate.name] ?? .distantPast) >= 2.0
                if n >= 3 && stable {
                    // バー計測が数字読みの低下を強く否定する場合は行を
                    // 出さない (フェーズ2 段階2の採用判定: バー拒否)。
                    // 数字が 8 ポイント以上下がったと言うのに、バーの
                    // 画素長が確定値の 5 ポイント以内に留まるなら、
                    // 数字側 (隣枠の混入や数字融合) の誤読と判断する。
                    // 次ターンも同じ値で食い違いが続けば、数字側を
                    // 状態訂正として静かに取り込む (実例: 2026-11-22
                    // battle_20261122_160927、Sneasler の被ダメ幻行
                    // 3 件はいずれもバーが 95% 以上を維持していた)
                    if let bar = s.hpBarPct, s.hpPercent < emitted,
                       emitted - s.hpPercent >= 8, bar >= emitted - 5 {
                        if let held = barVetoHold[plate.name], held.pct == s.hpPercent, held.turn < currentTurn {
                            barVetoHold[plate.name] = nil
                            lastEmittedPct[plate.name] = s.hpPercent
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_adopted", "readerBuild": readerBuild])
                        } else {
                            barVetoHold[plate.name] = (pct: s.hpPercent, turn: currentTurn)
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_drop", "readerBuild": readerBuild])
                        }
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {
                    // 安定した時点でもバー計測と数字 OCR が食い違う場合は
                    // 系統間の不一致として証拠に残す (フェーズ2)
                    if let bar = s.hpBarPct, abs(bar - s.hpPercent) >= 8 {
                        debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)",
                                     rawText: "",
                                     detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                              "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                              "readerBuild": readerBuild])
                    }
                    if emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                      fromPct: emitted, toPct: s.hpPercent, hpText: monStates[key]!.hpText) {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {
                        // 同一行動内の段階値として保留 (値は保持する)
                        pendingDamageCount[plate.name] = 3
                    }
                    }
                } else {
                    pendingDamageCount[plate.name] = n
                }
            } else {
                pendingDamagePct[plate.name] = s.hpPercent
                pendingDamageCount[plate.name] = 1
                pendingDamageSince[plate.name] = sNow()
                pendingReturnCount[plate.name] = nil
                lastPendingLabel = "\(slot): \(s.speciesEn)"
            }
            lastSlots[plate.name] = s
        }
    }
    // 保留していた天候・地形の開始行を流す: 交代の確定が済んだ時点
    // (確定待ちが空になった) か、6 秒を超えたら強制的に出す。
    // 以前は 2.5 秒だったが、登場演出が長いと確定前に強制分が流れ、
    // 開始行が交代行より前に出た (実例: 2026-11-22
    // battle_20261122_050512、グラスフィールド開始行が
    // ゴリランダーの交代行より前に置かれた)
    if heldWeatherStart != nil || heldTerrainStart != nil {
        // 要員待ちが続く間は上限を延ばす (要員選択は 6 秒を超えることが
        // 普通にある。要員が登録されれば即座に流れる)
        let awaitingNow = anyAwaitingReplacement()
        let heldAge = sNow().timeIntervalSince((heldWeatherStart?.at ?? heldTerrainStart?.at) ?? .distantPast)
        var ready = (pendingSwitchSpecies.isEmpty && !awaitingNow) || heldAge > (awaitingNow ? 20.0 : 6.0)
        // ターン0 で出所 (サージ・天候特性) が場に確認できない開始は、
        // 出所の交代が確定するまで流さない (上限の強制排出は従来どおり。
        // 実例: 2026-11-22 battle_20261122_103530、ゴリランダーの交代が
        // 確定する前に グラスフィールド の開始行だけが対戦開始直後に出た)
        if ready && currentTurn == 0 && heldAge <= 20.0 {
            if let h = heldWeatherStart, !fieldSourceOnField(h.ui) { ready = false }
            if let h = heldTerrainStart, !fieldSourceOnField(h.ui) { ready = false }
        }
        if ready {
            fieldHoldBypass = true
            if let h = heldWeatherStart { heldWeatherStart = nil; setWeather(h.ui, h.logName, via: h.text) }
            if let h = heldTerrainStart { heldTerrainStart = nil; setTerrain(h.ui, via: h.text) }
            fieldHoldBypass = false
        }
    }
    // 入場特性の効果として保留した行: 交代の確定待ちが空になったら流す
    if !heldEntryBoosts.isEmpty && pendingSwitchSpecies.isEmpty && !anyAwaitingReplacement() { flushHeldEntryBoosts() }
    // 出所未確認で保留した地形の上書きの確認 (採用/破棄)
    confirmHeldTerrainReplace()
}

func crossCheckPlateSpecies(plateName: String, speciesEn: String) {
    // 自他はプレート枠名 (mineA 等) で判定する。プロトコル枠 (p1a 等) で
    // 判定すると自軍枠が相手の見せ合いリストと照合されて誤発火する
    // (実例: 2026-11-22 battle_20261122_160927 の debug12)
    let list: [String] = plateName.hasPrefix("mine")
        ? minePreviewEvidence.compactMap { $0["species"] as? String }
        : previewEvidenceTeam.compactMap { $0 }
    guard list.count >= 4, !list.contains(speciesEn) else { return }
    if let e = speciesDict.first(where: { $0.en == speciesEn }) {
        let fam = Set(formeGroup(e).map { $0.en })
        if !fam.isDisjoint(with: list) { return }
    }
    debugCapture(kind: "species_disagree", key: "species_disagree:\(plateName):\(speciesEn)",
                 rawText: "",
                 detail: ["slot": plateName, "species": speciesEn, "preview": list,
                          "source": "plate", "turn": currentTurn, "readerBuild": readerBuild])
}

func fingerprintFiles(_ urls: [URL]) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    func mix(_ byte: UInt8) { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
    for url in urls {
        for byte in url.lastPathComponent.utf8 { mix(byte) }
        mix(0xff)
        if let data = try? Data(contentsOf: url) {
            for byte in data { mix(byte) }
        } else {
            mix(0xee)
        }
        mix(0xfe)
    }
    return String(h, radix: 16)
}

func salvageFromText(_ text: String, allowBoost: Bool = true, fromLogScreen: Bool = false) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    if salvageField(in: t, fromLogScreen: fromLogScreen) { return true }
    if allowBoost && salvageBoost(in: t) { return true }
    if salvageStatus(in: t) { return true }
    if salvageItem(in: t) { return true }
    return false
}

func salvageSubject(in t: String) -> (side: String, slot: String, speciesEn: String)? {
    let sp0 = findSpeciesJa(in: t) ?? findSpeciesJaLoose(in: t)?.entry
    guard let sp0 else { return nil }
    let sp = anchoredSpeciesForText(sp0, text: t)
    let hits = lastSlots.filter { $0.value.speciesEn == sp.en }
    guard hits.count == 1, let plate = hits.first else { return nil }
    let side = plate.key.hasPrefix("mine") ? "p1" : "p2"
    return (side, slotFor(side: side, speciesEn: sp.en), sp.en)
}

func salvageBoost(in t: String) -> Bool {
    // 否定文 (もう上がらない等) では発火しない
    if t.contains("上がらない") || t.contains("あがらない") || t.contains("下がらない") || t.contains("さがらない") { return false }
    let up = t.contains("上がった") || t.contains("上がつた") || t.contains("あがった") || t.contains("あがつた")
    let down = t.contains("下がった") || t.contains("下がつた") || t.contains("さがった") || t.contains("さがつた")
    guard up != down else { return false }  // 方向が確定しないものは入れない
    // 「目一杯上がった」は上限まで = 量が文から確定しないため入れない
    if t.contains("目一杯") || t.contains("めいっぱい") { return false }
    // 能力名 (特攻・特防を先に見る: 「特攻」は「攻撃」を含むため)
    let stats: [(String, String)] = [("特攻", "spa"), ("とくこう", "spa"), ("トクコウ", "spa"), ("特防", "spd"), ("とくぼう", "spd"), ("トクボウ", "spd"),
                                     ("攻撃", "atk"), ("こうげき", "atk"), ("コウゲキ", "atk"), ("防御", "def"), ("ぼうぎょ", "def"), ("ボウギョ", "def"),
                                     ("素早さ", "spe"), ("すばやさ", "spe"), ("スバヤサ", "spe"), ("命中率", "acc"), ("回避率", "eva")]
    // 濁点ゆれ (スパヤサ等) は両辺を畳んだ形でも照合する (検証 R1)
    let stat = stats.first(where: { t.contains($0.0) })?.1
        ?? stats.first(where: { foldDakuten(t).contains(foldDakuten($0.0)) })?.1
    guard let stat else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    var mag = 1
    if up && (t.contains("ぐーんと") || t.contains("ぐんと")) { mag = 2 }
    if down && (t.contains("がくっと") || t.contains("がくつと")) { mag = 2 }
    let key = "\(subj.side):\(subj.speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    applyBoost(key: key, slot: subj.slot, speciesEn: subj.speciesEn, stat: stat, delta: up ? mag : -mag, viaSalvage: true)
    return true
}

func salvageStatus(in t: String) -> Bool {
    // 状態異常の語 + 付与の手がかり (または回復の なおった) があり、対象が
    // 一意なときだけ、正規の状態処理に委ねる。checkStatusText は現在値と
    // 違うときだけ反映・出力するため、二重に効くことはない
    let hasCode = t.contains("もうどく") || t.contains("どく") || t.contains("やけど") || t.contains("まひ")
        || t.contains("ねむ") || (t.contains("眠") && !t.contains("眠気")) || t.contains("こおり") || t.contains("こおった")
    let cured = t.contains("なおった") || t.contains("なおつた")
    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた", "負った", "負つた"]
    guard cured || (hasCode && cues.contains(where: { t.contains($0) })) else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    checkStatusText(text: t, side: subj.side, speciesEn: subj.speciesEn, slot: subj.slot)
    return true
}

func salvageItem(in t: String) -> Bool {
    guard t.contains("食べた") || t.contains("たべた") || t.contains("なくなった") || t.contains("失くなった")
        || t.contains("失った") || t.contains("うしなった") else { return false }
    // きのみ・シード類の名前が本文にあるか (正規化して itemDict の値と照合)
    let nt = normalize(t)
    // 濁点ゆれ (キーのみ→ギーのみ等) は両辺を畳んだ形でも照合する (検証 R2 #17)。
    // 長音落ちまで重なった場合 (サイコシード→サイゴシド) は ッ→ツ+長音落ち
    // まで畳む (検証 R8 #73)。この変換ではアイテム名は全件衝突しない
    let itemFold: (String) -> String = { foldDakuten($0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")).replacingOccurrences(of: "ー", with: "") }
    let itemJa = itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && nt.contains(normalize($0)) })
        ?? itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && foldDakuten(nt).contains(foldDakuten(normalize($0))) })
        ?? itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && itemFold(nt).contains(itemFold(normalize($0))) })
    guard let itemJa else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    let key = "\(subj.side):\(subj.speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    emitItemOnce(slot: subj.slot, side: subj.side, speciesEn: subj.speciesEn, itemJa: itemJa)  // 判明登録は applyEvent が行う
    noteItemLost(slot: subj.slot, side: subj.side, speciesEn: subj.speciesEn)
    return true
}

func salvageField(in t: String, fromLogScreen: Bool = false) -> Bool {
    // 天気・フィールドは正規の照合をそのまま使う (setter は冪等)
    if checkFieldText(text: t, fromLogScreen: fromLogScreen) { return true }
    // サイドコンディションの告知 (種族に依存しない)。開始/終了の語が
    // 明確な場合だけ反映し、重複は lastSideCondAt で抑える (正規経路と共有)
    let scSide = (t.contains("相手") || t.contains("あいて")) ? "p2" : "p1"
    // 設置物の告知。技の検出を取りこぼした場合の受け皿で、開始/終了が
    // 曖昧な文は出さずに消費だけする (本文を |-message| に残さない)
    if t.contains("とがった岩") || t.contains("まきびし") || t.contains("どくびし") {
        let hz = t.contains("とがった岩") ? "Stealth Rock" : (t.contains("どくびし") ? "Toxic Spikes" : "Spikes")
        let start = t.contains("漂") || t.contains("浮か") || t.contains("散らば") || t.contains("ばらまか")
        let end = t.contains("消え") || t.contains("なくな")
        if start != end {
            let k = "\(scSide):\(hz):\(start ? "start" : "end")"
            if sNow().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = sNow()
                emitLog("|-\(start ? "sidestart" : "sideend")|\(scSide)|move: \(hz)")
            }
        }
        return true
    }
    let conds: [(String, String)] = [("リフレクター", "Reflect"), ("ひかりのかべ", "Light Screen"), ("光の壁", "Light Screen"),
                                     ("オーロラベール", "Aurora Veil"), ("しろいきり", "Mist"), ("白い霧", "Mist"),
                                     ("しんぴのまもり", "Safeguard"), ("神秘の守り", "Safeguard"),
                                     ("追い風", "Tailwind"), ("おいかぜ", "Tailwind")]
    guard let cond = conds.first(where: { t.contains($0.0) }) else { return false }
    let start = t.contains("現れた") || t.contains("現れ") || t.contains("張った") || t.contains("張られた")
        || t.contains("包まれた") || t.contains("つつまれた") || t.contains("覆われた") || t.contains("吹き始") || t.contains("ふきはじ")
        || t.contains("強くなった")  // 壁の告知は「ひかりのかべで特殊に強くなった！」の形 (実例: 2026-11-20 vs Destrock 戦)
    let end = t.contains("消えた") || t.contains("なくなった") || t.contains("消え去った") || t.contains("はれた")
        || t.contains("止ん") || t.contains("やん") || t.contains("終わ")
    guard start != end else { return false }  // 開始か終了か確定しないものは入れない
    let k = "\(scSide):\(cond.1):\(start ? "start" : "end")"
    if sNow().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
        lastSideCondAt[k] = sNow()
        emitLog("|-\(start ? "sidestart" : "sideend")|\(scSide)|move: \(cond.1)")
    }
    return true
}

func textSimilarity(_ a: String, _ b: String) -> Double {
    let x = Array(a), y = Array(b)
    if x.isEmpty || y.isEmpty { return 0 }
    var prev = [Int](repeating: 0, count: y.count + 1)
    var cur = [Int](repeating: 0, count: y.count + 1)
    for i in 1...x.count {
        cur[0] = 0
        for j in 1...y.count {
            cur[j] = x[i - 1] == y[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
        }
        swap(&prev, &cur)
    }
    return Double(prev[y.count]) / Double(min(x.count, y.count))
}

func debugShouldCapture(seen: [(key: String, at: Date)], count: Int, key: String, cap: Int, now: Date) -> Bool {
    if count >= cap { return false }
    for e in seen {
        if e.key == key { return false }
        if now.timeIntervalSince(e.at) <= 30 && textSimilarity(e.key, key) >= 0.6 { return false }
    }
    return true
}

func sameSpeciesFamily(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    func famKey(_ n: String) -> String {
        for suf in ["-Mega-X", "-Mega-Y", "-Mega-Z", "-Mega", "-Blade", "-Shield"] where n.hasSuffix(suf) {
            return String(n.dropLast(suf.count))
        }
        return n
    }
    if famKey(a) == famKey(b) { return true }
    return a.hasPrefix(b + "-") || b.hasPrefix(a + "-")
}

func abilityLinePlausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, let ss = parseSlotSpecies(f[2]) else { return true }
    let ability = f[3].trimmingCharacters(in: .whitespaces)
    let familyKeys = speciesAbilityMap.keys.filter {
        $0 == ss.speciesEn || $0.hasPrefix(ss.speciesEn + "-") || ss.speciesEn.hasPrefix($0 + "-")
    }
    guard !familyKeys.isEmpty else { return true }
    var pool = Set<String>()
    for k in familyKeys { pool.formUnion(speciesAbilityMap[k] ?? []) }
    if pool.contains(ability) { return true }
    let copyAbilities: Set<String> = ["Trace", "Receiver", "Power of Alchemy"]
    if !pool.isDisjoint(with: copyAbilities) { return true }
    return false
}

func moveLineHardImplausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    return faintedSpecies.contains("\(ss.side):\(ss.speciesEn)")
}

func moveLineOffField(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    let slotA = "\(ss.side)a", slotB = "\(ss.side)b"
    let plateOf: (String) -> String = { s in (ss.side == "p1" ? "mine" : "opp") + (s.hasSuffix("a") ? "A" : "B") }
    guard let occ = lastSlots[plateOf(ss.slot)]?.speciesEn ?? eventSlotSpecies[ss.slot] else { return false }
    if sameSpeciesFamily(occ, ss.speciesEn) { return false }
    if occ.hasPrefix("Ditto") { return false }   // へんしん中は相手の姿で技文が出る
    let sibSlot = ss.slot == slotA ? slotB : slotA
    if let sib = lastSlots[plateOf(sibSlot)]?.speciesEn ?? eventSlotSpecies[sibSlot], sameSpeciesFamily(sib, ss.speciesEn) { return false }
    // その種族がちょうど交代で入ってくる途中なら、確定待ちの誤差として扱う
    let prefix = ss.side == "p1" ? "mine" : "opp"
    for plate in ["\(prefix)A", "\(prefix)B"] where pendingSwitchSpecies[plate] == ss.speciesEn { return false }
    return true
}

func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:], pickByCandidate: [String: String] = [:], slotMargins: [String: Double] = [:], finalTeams: [String: [String]] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {
    var proto = protocolLines
    var added: [String] = []
    var removed: [String] = []
    for side in ["p1", "p2"] {
        var declared: [String] = []
        var lastPokeIdx: Int? = nil
        for (i, l) in proto.enumerated() {
            if l.hasPrefix("|poke|\(side)|") {
                declared.append(String(l.dropFirst("|poke|\(side)|".count)))
                lastPokeIdx = i
            }
            if l == "|start" { break }
        }
        var appeared: [String] = []
        for l in proto {
            guard l.hasPrefix("|switch|") || l.hasPrefix("|drag|") else { continue }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == side else { continue }
            if !appeared.contains(f[3]) { appeared.append(f[3]) }
        }
        let missing = appeared.filter { a in !declared.contains { sameSpeciesFamily($0, a) } }
        if missing.isEmpty {
            // 最終同定チームによる補完: 登場ベースの補完が無い場合も
            // 同じ規則で補う (手動開始で同定途中にヘッダーが書かれた
            // 場合の、未登場だが同定済みの種族。実例: 2026-11-23
            // battle_20261123_090354、Staraptor と Gholdengo)
            if let fin = finalTeams[side] {
                var extra: [String] = []
                for sp in fin where declared.count + extra.count < 6 {
                    if !declared.contains(where: { sameSpeciesFamily($0, sp) }) && !extra.contains(where: { sameSpeciesFamily($0, sp) }) {
                        extra.append(sp)
                    }
                }
                if !extra.isEmpty {
                    var lastPokeIdx: Int? = nil
                    for (i, l) in proto.enumerated() {
                        if l.hasPrefix("|poke|\(side)|") { lastPokeIdx = i }
                        if l == "|start" { break }
                    }
                    let at = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)
                    proto.insert(contentsOf: extra.map { "|poke|\(side)|\($0)" }, at: at)
                    added += extra.map { "\(side):\($0)" }
                }
            }
            continue
        }
        // 補完で 6 体を超える場合は、実際には登場しなかった宣言側の
        // 種族 (見せ合い同定の誤り) と入れ替える。チームが 7 体に
        // なるヘッダーはあり得ない (実例: 2026-11-22
        // battle_20261122_071457、誤同定の枠が残ったまま実登場した
        // サーフゴーが 7 体目に追記された)
        if declared.count + missing.count > 6 {
            let unused = declared.filter { d in !appeared.contains { sameSpeciesFamily($0, d) } }
            let removeCount = min(unused.count, declared.count + missing.count - 6)
            if removeCount > 0 {
                // 削除候補の選定: (1) 実登場した未宣言種族が次点だった
                // 枠の pick を最優先で落とす (その枠の同定が誤りだった
                // 直接証拠)。(2) 残りは枠内の優位差 (次点とのスコア差)
                // が小さい順 (辛勝の枠ほど誤同定の疑いが強い)。
                // 生スコア順は採らない: スコアは枠ごとの距離であり、
                // 枠をまたいだ比較は意味を持たない (実例: 2026-11-22
                // battle_20261122_231107、正しい Sneasler (-0.190) が
                // 落ち、誤同定の Barbaracle (0.45) が残った。185505
                // では逆の数値関係で生スコア順が偶然機能していた)
                var pool = unused
                var picked: [String] = []
                for m in missing {
                    if let pick = pickByCandidate["\(side):\(m)"],
                       pool.contains(pick), !picked.contains(pick) {
                        picked.append(pick)
                        pool.removeAll { $0 == pick }
                    }
                    if picked.count >= removeCount { break }
                }
                if picked.count < removeCount {
                    let rest = Array(pool.enumerated().sorted { a, b in
                        let ma = slotMargins["\(side):\(a.element)"] ?? .infinity
                        let mb = slotMargins["\(side):\(b.element)"] ?? .infinity
                        if ma != mb { return ma < mb }
                        return a.offset > b.offset
                    }.prefix(removeCount - picked.count).map { $0.element })
                    picked += rest
                }
                let removing = picked
                let removeSet = Set(removing)
                proto = proto.filter { line in
                    guard line.hasPrefix("|poke|\(side)|") else { return true }
                    return !removeSet.contains(String(line.dropFirst("|poke|\(side)|".count)))
                }
                removed += removing.map { "\(side):\($0)" }
                lastPokeIdx = nil
                for (i, l) in proto.enumerated() {
                    if l.hasPrefix("|poke|\(side)|") { lastPokeIdx = i }
                    if l == "|start" { break }
                }
            }
        }
        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)
        proto.insert(contentsOf: missing.map { "|poke|\(side)|\($0)" }, at: insertAt)
        added += missing.map { "\(side):\($0)" }
        // 最終同定チームによる補完: 手動開始で同定の途中にヘッダーが
        // 書かれた場合、同定済みでも登場しなかった種族は上の補完
        // (登場した種族が対象) では拾えない (実例: 2026-11-23
        // battle_20261123_090354、Staraptor と Gholdengo が最終
        // ヘッダーから落ちた)。同定結果を正として、宣言が 6 体に
        // 満たない分だけ同定順に補う
        if let fin = finalTeams[side] {
            let have = proto.compactMap { l -> String? in
                l.hasPrefix("|poke|\(side)|") ? String(l.dropFirst("|poke|\(side)|".count)) : nil
            }
            var extra: [String] = []
            for sp in fin where have.count + extra.count < 6 {
                if !have.contains(where: { sameSpeciesFamily($0, sp) }) && !extra.contains(where: { sameSpeciesFamily($0, sp) }) {
                    extra.append(sp)
                }
            }
            if !extra.isEmpty {
                var at = insertAt + missing.count
                if at > proto.count { at = proto.count }
                proto.insert(contentsOf: extra.map { "|poke|\(side)|\($0)" }, at: at)
                added += extra.map { "\(side):\($0)" }
            }
        }
    }
    // 自軍の交代行の HP 表記を実数へ統一する: 開幕の交代行が % 表記
    // (100/100) で出た枠も、後の被ダメ行などで実数の最大値が判明
    // していれば、その表記 (最大値/最大値) に揃える。実数表記の枠と
    // 混在すると、同じ開幕の交代行で表記が割れる (実例: 2026-11-22
    // battle_20261122_091721、ニョロトノは 167/167、ブリジュラスは
    // 100/100 で出た)
    var realMax: [String: Int] = [:]
    for l in proto {
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 2 else { continue }
        // HP 表記の位置は行種で異なる (交代行は種族名の次、被ダメ・
        // 回復行はラベルの次)
        let hpIdx = f[1] == "switch" ? 4 : (f[1] == "-damage" || f[1] == "-heal" ? 3 : -1)
        guard hpIdx >= 0, f.count > hpIdx else { continue }
        let hpParts = f[hpIdx].split(separator: " ")
        guard let first = hpParts.first else { continue }
        let curMax = first.split(separator: "/")
        if curMax.count == 2, let mx = Int(curMax[1]), mx != 100 {
            realMax[f[2]] = max(realMax[f[2]] ?? 0, mx)
        }
    }
    if !realMax.isEmpty {
        proto = proto.map { l in
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, f[1] == "switch", let mx = realMax[f[2]] else { return l }
            // 満タンで登場した交代行は、後続の行で判明した実数の最大値に
            // 揃える。対象は % 表記 (100/100) の場合と、最大値の採用前に
            // 登録値で出た場合 (157/157 のまま残り、後続は /171 で処理
            // されて 1 つのプロトコル内で表記が割れた。実例: 2026-11-22
            // battle_20261122_181745、Sneasler)
            let parts = f[4].split(separator: "/")
            guard parts.count == 2, let cur = Int(parts[0]), let oldMax = Int(parts[1]),
                  cur == oldMax, mx != oldMax else { return l }
            var g = f
            g[4] = "\(mx)/\(mx)"
            return g.joined(separator: "|")
        }
    }
    var disp = displayLines
    if !added.isEmpty {
        // 表示側: チーム見出し行 (2 つあるうち 1 つ目が自軍、2 つ目が相手)
        // の次の行が種族の一覧行。補った種族を側ごとに追記する
        var teamLineIdxs: [Int] = []
        for (i, l) in disp.enumerated() where l == "Your team:" || l.hasSuffix("'s team:") { teamLineIdxs.append(i) }
        for (n, side) in ["p1", "p2"].enumerated() {
            let sideAdded = added.filter { $0.hasPrefix("\(side):") }.map { String($0.dropFirst(3)) }
            guard !sideAdded.isEmpty, teamLineIdxs.count > n else { continue }
            let namesIdx = teamLineIdxs[n] + 1
            guard namesIdx < disp.count else { continue }
            let existing = disp[namesIdx].isEmpty ? [] : disp[namesIdx].components(separatedBy: " / ")
            let sideRemoved = removed.filter { $0.hasPrefix("\(side):") }.map { String($0.dropFirst(3)) }
            let kept = existing.filter { e in !sideRemoved.contains { sameSpeciesFamily($0, e) } }
            let extra = sideAdded.filter { a in !kept.contains { sameSpeciesFamily($0, a) } }
            if !extra.isEmpty || kept.count != existing.count { disp[namesIdx] = (kept + extra).joined(separator: " / ") }
        }
    }
    return (proto, disp, added, removed)
}

func flushHeldEntryBoosts() {
    if heldEntryBoosts.isEmpty { return }
    let held = heldEntryBoosts
    heldEntryBoosts = []
    for ts in Set(held.map { String($0.key.prefix(2)) }) { attributeIntimidate(targetSide: ts) }
    for h in held { emitLog(h.line, applyNow: false) }
}

func itemLineImplausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    let prefix = ss.side == "p1" ? "mine" : "opp"
    let plate = prefix + (ss.slot.hasSuffix("a") ? "A" : "B")
    guard let occ = lastSlots[plate]?.speciesEn ?? eventSlotSpecies[ss.slot] else { return false }
    if sameSpeciesFamily(occ, ss.speciesEn) { return false }
    if occ.hasPrefix("Ditto") { return false }
    if pendingSwitchSpecies[plate] == ss.speciesEn { return false }
    let sib = prefix + (ss.slot.hasSuffix("a") ? "B" : "A")
    if let sibOcc = lastSlots[sib]?.speciesEn, sameSpeciesFamily(sibOcc, ss.speciesEn) { return false }
    return true
}

func pendingMegaForme(side: String, baseEn: String) -> String? {
    var cands = speciesDict.filter { $0.en.hasPrefix(baseEn + "-Mega") }
    if cands.count > 1, let stoneJa = pendingMegaStone[side], let last = stoneJa.last {
        let filtered = cands.filter { $0.en.hasSuffix("-Mega-\(last)") }
        if filtered.count == 1 { cands = filtered }
    }
    guard cands.count == 1 else { return nil }
    return cands.first?.en
}

func completePendingMegaForField(ability: String) {
    for side in ["p1", "p2"] {
        guard let baseEn = pendingMegaSpecies[side],
              let forme = pendingMegaForme(side: side, baseEn: baseEn),
              let pool = speciesAbilityMap[forme], pool.contains(ability),
              lastSwitchIn["\(side):\(baseEn)"] != nil else { continue }
        completeMega(side: side, baseEn: baseEn, megaEn: forme)
    }
}

func expectedStats(base: [Int], sp: [String: Int], speciesEn: String, up: Int?, down: Int?) -> [Int] {
    let keys = ["hp", "atk", "def", "spa", "spd", "spe"]
    var out: [Int] = []
    for i in 0..<6 {
        let ev = (sp[keys[i]] ?? 0) * 8
        let core = (2 * base[i] + 31 + ev / 4) * 50 / 100
        if i == 0 {
            out.append(speciesEn == "Shedinja" ? 1 : core + 60)
        } else {
            var v = core + 5
            if up == i { v = v * 11 / 10 } else if down == i { v = v * 9 / 10 }
            out.append(v)
        }
    }
    return out
}

func statsFitForme(base: [Int], stats: [String: Int], spHint: [String: Int], speciesEn: String) -> Bool {
    let keys = ["hp", "atk", "def", "spa", "spd", "spe"]
    let read = keys.map { stats[$0] ?? -1 }
    var corrections = Set<String>()
    for nt in natureTable {
        let exp = expectedStats(base: base, sp: spHint, speciesEn: speciesEn, up: nt.up, down: nt.down)
        if exp == read { return true }
        let diffs = (0..<6).filter { exp[$0] != read[$0] }
        if diffs.count == 1 { corrections.insert(keys[diffs[0]]) }
    }
    return corrections.count == 1
}

func noteStateWrite(shape: String, json: String, eventsCount: Int) {
    var take = shape != "battle"
    if shape == "battle" && !stateSnapLastShape.isEmpty && stateSnapLastShape != "battle" { take = true }
    if shape == "battle" && stateSnapFirstBattlePending { take = true }
    if stateSnapLastEvents >= 0 && eventsCount < stateSnapLastEvents { take = true }
    stateSnapLastShape = shape
    stateSnapLastEvents = eventsCount
    if shape == "battle" { stateSnapFirstBattlePending = false }
    if !take { return }
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.formatOptions = [.withInternetDateTime]
    var rec: [String: Any] = ["at": f.string(from: sNow()), "shape": shape]
    if let d = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
        rec["state"] = obj
    } else {
        rec["state"] = json
    }
    if battleArchiveId.isEmpty || winLogged {
        stateSnapLeadIn.append(rec)
    } else {
        stateSnapRecords.append(rec)
        flushStateSnapshots()
    }
}

func battleEventsObjects() -> [Any] {
    battleEvents.compactMap { frag in
        guard let d = frag.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
}

func adoptStateSnapshotsForBattle() {
    stateSnapRecords = stateSnapLeadIn
    stateSnapLeadIn = []
    stateSnapKey = ""
    stateSnapFirstBattlePending = true
    flushStateSnapshots()
}

func terrainSourcePlausible(_ ui: String) -> Bool {
    let surge: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    guard let ab = surge[ui] else { return true }
    // 地形技が直近の技なら、その技からの開始として妥当
    if lastMoveName == "\(ui) Terrain", sNow().timeIntervalSince(lastMoveMsgAt) < 25 { return true }
    // 直近の交代で入った個体が、その特性を持ちうるなら妥当
    // (メガフォルムの特性は別エントリにあるため科単位でも見る)
    for (key, sw) in lastSwitchIn where sNow().timeIntervalSince(sw.at) < 25 {
        let sp = key.split(separator: ":").last.map(String.init) ?? ""
        if (speciesAbilityMap[sp] ?? []).contains(ab) { return true }
        for (other, pool) in speciesAbilityMap where pool.contains(ab) && sameSpeciesFamily(other, sp) { return true }
    }
    return false
}

func confirmHeldTerrainReplace() {
    guard let h = heldTerrainReplace else { return }
    if terrainSourcePlausible(h.ui) {
        heldTerrainReplace = nil
        fieldHoldBypass = true
        setTerrain(h.ui, via: h.text)
        fieldHoldBypass = false
    } else if sNow().timeIntervalSince(h.at) > 4.0 {
        heldTerrainReplace = nil
        debugCapture(kind: "terrain_change", key: "terrain_change_blocked:\(h.ui)", rawText: h.text,
                     detail: ["from": logFieldTerrain, "to": h.ui, "turn": currentTurn, "blocked": true, "reason": "unconfirmed_replace"])
        if debugMode { print("[field] 出所を確認できない地形の上書きを採用しませんでした: \(h.ui) (現在: \(logFieldTerrain))") }
        fflush(stdout)
    }
}

func fieldLineForAbility(_ ability: String) -> String? {
    switch ability {
    case "Drought": return "|-weather|Sunny Day"
    case "Drizzle": return "|-weather|Rain Dance"
    case "Sand Stream": return "|-weather|Sandstorm"
    case "Snow Warning": return "|-weather|Snow"
    case "Electric Surge": return "|-fieldstart|move: Electric Terrain"
    case "Grassy Surge": return "|-fieldstart|move: Grassy Terrain"
    case "Misty Surge": return "|-fieldstart|move: Misty Terrain"
    case "Psychic Surge": return "|-fieldstart|move: Psychic Terrain"
    default: return nil
    }
}

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
    if seg[..<rel].contains(where: { $0.hasPrefix("|move|") && $0.hasSuffix("|\(moveName)") }) { return }
    if let swIdx = seg.lastIndex(where: { $0.hasPrefix("|switch|\(label)|") || $0.hasPrefix("|drag|\(label)|") }), swIdx > rel { return }
    battleLog[turnIdx + 1 + rel] = "\(fieldLine)|[from] ability: \(ability)|[of] \(label)"
}

func fieldLineWithAttribution(_ line: String) -> String {
    let bareLines = ["Drought", "Drizzle", "Sand Stream", "Snow Warning",
                     "Electric Surge", "Grassy Surge", "Misty Surge", "Psychic Surge"]
        .compactMap { fieldLineForAbility($0) }
    guard bareLines.contains(line) else { return line }
    let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) ?? -1
    guard turnIdx + 1 <= battleLog.count else { return line }
    let seg = Array(battleLog[(turnIdx + 1)...])
    let rawName: String
    if line.hasPrefix("|-fieldstart|move: ") {
        rawName = String(line.dropFirst("|-fieldstart|move: ".count))
    } else {
        rawName = String(line.dropFirst("|-weather|".count))
    }
    let moveName = rawName == "Snow" ? "Snowscape" : rawName
    if seg.contains(where: { $0.hasPrefix("|move|") && $0.hasSuffix("|\(moveName)") }) { return line }
    for l in seg where l.hasPrefix("|-ability|") {
        let af = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if af.count >= 4, fieldLineForAbility(af[3]) == line {
            return "\(line)|[from] ability: \(af[3])|[of] \(af[2])"
        }
    }
    return line
}

func isMoveListText(_ text: String) -> Bool {
    let nt = normalize(text)
    var found = Set<String>()
    for (norm, _) in moveNameOrig {
        if norm.isEmpty || norm.count < 2 { continue }
        guard nt.contains(norm) else { continue }
        var speciesPart = false
        for sp in speciesDict where nt.contains(normalize(sp.ja)) {
            if normalize(sp.ja).contains(norm) { speciesPart = true; break }
        }
        if !speciesPart { found.insert(norm) }
    }
    return found.count >= 2
}

func headerDistinctMargin(ranked: [(String, Double)]) -> Double? {
    guard let pick = ranked.first else { return nil }
    guard let runner = ranked.dropFirst().first(where: { !sameSpeciesFamily($0.0, pick.0) }) else { return nil }
    return runner.1 - pick.1
}

func maxReadPlausible(readMax: Int, knownMax: Int) -> Bool {
    if readMax == knownMax { return true }
    if knownMax >= 100 && readMax == knownMax % 100 { return true }
    return abs(readMax - knownMax) <= 36
}

func applyFlagControl(mode: String, startSeq: Int, endSeq: Int) {
    flagManualMode = (mode != "auto")
    if !flagControlAdopted {
        flagControlAdopted = true
        flagStartSeqSeen = startSeq
        flagEndSeqSeen = endSeq
        return
    }
    if startSeq > flagStartSeqSeen {
        flagStartSeqSeen = startSeq
        if flagManualMode && (!logStarted || winLogged) {
            startBattleLog()
            inBattle = true
            // state.json を初期化した形で書き出し、前試合の内容が
            // プレート確認まで残る空白を埋める (手動開始のみ)
            writeManualStartResetState()
        }
    }
    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
            // 終了の確定を state.json に反映する (winLogged が
            // 立った後なので battlePhase は必ず idle になる)
            writeBattleEndState()
        }
    }
}

func flagPhase() -> String { (logStarted && !winLogged) ? "inBattle" : "idle" }

func flagModeName() -> String { flagManualMode ? "manual" : "auto" }

func flagStateFragment() -> String { "\"battlePhase\": \"\(flagPhase())\", \"flagMode\": \"\(flagModeName())\"" }

func writeManualStartResetState() {
    var obj: [String: Any] = [:]
    obj["mine"] = [Any]()
    obj["opps"] = [Any]()
    obj["field"] = [String: Any]()
    obj["oppReset"] = true
    obj["battlePhase"] = flagPhase()
    obj["flagMode"] = flagModeName()
    if previewTeamWritten {
        obj["oppTeam"] = oppTeamSeen.map { $0 as Any }
        if minePreviewTeam.contains(where: { $0 != nil }) {
            obj["minePreview"] = true
            obj["mineTeam"] = minePreviewDetails.map { d -> Any in d.isEmpty ? NSNull() : d }
        }
    } else {
        obj["oppTeam"] = [Any]()
    }
    // 開始したばかりの試合の ID と、消去済みのイベント列を併せる
    // (同定全滅時のリセット書き出しの対戦中形と同じ扱い)
    if !battleArchiveId.isEmpty {
        obj["battle"] = battleArchiveId
        obj["events"] = battleEventsObjects()
    }
    if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8), json != lastWritten {
        lastWritten = json
        try? json.write(to: outURL, atomically: true, encoding: .utf8)
        noteStateWrite(shape: "manualstart", json: json, eventsCount: battleEvents.count)
    }
}

func writeBattleEndState() {
    writeState()
    if lastSlots.isEmpty {
        var obj: [String: Any] = [:]
        obj["mine"] = [Any]()
        obj["opps"] = [Any]()
        obj["field"] = [String: Any]()
        obj["oppReset"] = true
        obj["battlePhase"] = flagPhase()
        obj["flagMode"] = flagModeName()
        obj["oppTeam"] = oppTeamSeen.map { $0 as Any }
        if !battleArchiveId.isEmpty {
            obj["battle"] = battleArchiveId
            obj["events"] = battleEventsObjects()
        }
        if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8), json != lastWritten {
            lastWritten = json
            try? json.write(to: outURL, atomically: true, encoding: .utf8)
            noteStateWrite(shape: "battleend", json: json, eventsCount: battleEvents.count)
        }
    }
}

func safetyNetDraftDue() -> Bool {
    interruptedSaveEnabled && logStarted && !battleArchived && !battleLog.isEmpty && !winLogged
        && emptyBattleFrames > 30
        && sNow().timeIntervalSince(lastLogEventAt) > 45
        && battleLog.count != lastArchiveSnapshotCount
}

func confirmedDisplayCount(isFinal: Bool) -> Int {
    if isFinal { return displayLog.count }
    let turnBound = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) ?? 0
    // ヘッダーは相手の同定がそろう (または同定が終了する) まで
    // 印刷を止める。ヘッダーは displayLog の先頭にあるため、
    // 未完成の間は後続の行も含めて何も印刷しない
    if headerPrintReady { return max(turnBound, headerLineCount) }
    return headerLineCount > 0 ? 0 : turnBound
}

func takeDisplayPrintLines(isFinal: Bool) -> [String] {
    let target = confirmedDisplayCount(isFinal: isFinal)
    guard target > displayPrintedCount else { return [] }
    let lines = Array(displayLog[displayPrintedCount..<target])
    displayPrintedCount = target
    return lines
}

func flushDisplayPrint(isFinal: Bool = false) {
    let lines = takeDisplayPrintLines(isFinal: isFinal)
    for l in lines { Swift.print(l) }
    if !lines.isEmpty { fflush(stdout) }
}

func completeDisplayHeader() {
    guard headerLineCount > 0, displayLog.count >= headerLineCount else { return }
    let mine = trainerMine.isEmpty ? "you" : trainerMine
    let opp = trainerOpp.isEmpty ? "Opponent" : trainerOpp
    let p1Line = headerLineCount > 7 ? displayLog[7] : ""
    var h = ["\(mine) and \(opp) joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg \(regulationDisplay())", "Rated battle",
             "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
             trainerMine.isEmpty ? "Your team:" : "\(trainerMine)'s team:", p1Line,
             "\(opp)'s team:", oppTeamSeen.joined(separator: " / "), "",
             "Battle started between \(mine) and \(opp)!"]
    if !oppRank.isEmpty { h.append("\(opp)'s rank: \(oppRank)") }
    if !oppRating.isEmpty { h.append("\(opp)'s rating: \(oppRating)") }
    h.append("")
    displayLog.replaceSubrange(0..<headerLineCount, with: h)
    headerLineCount = h.count
    try? (displayLog.joined(separator: "\n") + "\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
}

func refreshHeaderState(forceEnd: Bool = false) {
    guard headerLineCount > 0, !headerPrintReady else { return }
    let complete = !trainerOpp.isEmpty && oppTeamSeen.count >= 6
    if complete || previewHandled || forceEnd {
        completeDisplayHeader()
        headerPrintReady = true
        flushDisplayPrint()
    }
}

func renderLogLine(_ line: String) -> [String] {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 2 else { return [] }
    let oppName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
    switch f[1] {
    case "gametype":
        return []
    case "poke":
        if f.count >= 4 {
            if f[2] == "p1" { renderPokeP1.append(f[3]) } else { renderPokeP2.append(f[3]) }
        }
        return []
    case "start":
        let mine = trainerMine.isEmpty ? "you" : trainerMine
        var header = ["\(mine) and \(oppName) joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg \(regulationDisplay())", "Rated battle",
                "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
                trainerMine.isEmpty ? "Your team:" : "\(trainerMine)'s team:", renderPokeP1.joined(separator: " / "),
                "\(oppName)'s team:", renderPokeP2.joined(separator: " / "), "",
                "Battle started between \(mine) and \(oppName)!"]
        // 相手のランク/レート (読み取れた場合のみ、トレーナー名と併記)
        if !oppRank.isEmpty { header.append("\(oppName)'s rank: \(oppRank)") }
        if !oppRating.isEmpty { header.append("\(oppName)'s rating: \(oppRating)") }
        header.append("")
        return header
    case "switch":
        guard f.count >= 5 else { return [] }
        let (slot, side, _) = renderLabelParts(f[2])
        let species = f[3]
        var out: [String] = []
        var display = species
        if let mega = monStates["\(side):\(species)"]?.megaSpecies, !mega.isEmpty {
            display = "\(species) (\(mega))"
        }
        if let prev = renderSlotSpecies[slot], prev != species, !renderFainted.contains(slot) {
            if side == "p2" { out.append("\(oppName) withdrew \(prev)!") }
            else { out.append("\(prev), come back!") }
        }
        if side == "p2" { out.append("\(oppName) sent out \(display)!") }
        else { out.append("Go! \(display)!") }
        renderSlotSpecies[slot] = species
        renderFainted.remove(slot)
        if let pct = renderPct(of: f[4]) { renderLastPct[f[2]] = pct }
        return out
    case "turn":
        var out: [String] = []
        if let n = Int(f[2]), n > 1 {
            switch renderWeatherProto {
            case "Sunny Day": out.append("(The sunlight is strong.)")
            case "Rain Dance": out.append("(Rain continues to fall.)")
            case "Sandstorm": out.append("(The sandstorm is raging.)")
            case "Snow", "Snowscape": out.append("(The snow is falling.)")
            default: break
            }
        }
        out.append("")
        out.append("Turn \(f[2])")
        return out
    case "move":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["\(renderPrefix(side))\(species) used \(f[3])!"]
    case "-damage":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        var out: [String] = []
        if f.count >= 5 {
            if f[4].contains("psn") || f[4].contains("tox") { out.append("\(renderPrefix(side))\(species) was hurt by its poison!") }
            else if f[4].contains("brn") { out.append("\(renderPrefix(side))\(species) was hurt by its burn!") }
            else if f[4].contains("Stealth Rock") { out.append("(The pointed stones dug into \(renderPrefix(side))\(species)!)") }
            else if f[4].contains("Spikes") { out.append("(\(renderPrefix(side))\(species) was hurt by the spikes!)") }
            else if f[4].contains("Rocky Helmet") { out.append("(\(renderPrefix(side))\(species) was hurt by Rocky Helmet!)") }
        }
        if let pct = renderPct(of: f[3]) {
            let lost = (renderLastPct[f[2]] ?? 100) - pct
            renderLastPct[f[2]] = pct
            if lost > 0 { out.append("(\(renderPrefix(side))\(species) lost \(lost)% of its health!)") }
        }
        return out
    case "-heal":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if let pct = renderPct(of: f[3]) { renderLastPct[f[2]] = pct }
        // 発生源が付いている回復は「(Leftovers)」のように後ろへ付ける
        if f.count >= 5 && f[4].hasPrefix("[from] ") {
            renderBerryAt[f[2]] = nil
            var src = String(f[4].dropFirst("[from] ".count))
            if src.hasPrefix("item: ") { src = String(src.dropFirst("item: ".count)) }
            return ["\(renderPrefix(side))\(species) had its HP restored. (\(src))"]
        }
        if let b = renderBerryAt[f[2]], sNow().timeIntervalSince(b.at) < 6 {
            renderBerryAt[f[2]] = nil
            return ["\(renderPrefix(side))\(species) restored HP using its \(b.item)!"]
        }
        return ["\(renderPrefix(side))\(species) had its HP restored."]
    case "faint":
        guard f.count >= 3 else { return [] }
        let (slot, side, species) = renderLabelParts(f[2])
        renderFainted.insert(slot)
        return ["\(renderPrefix(side))\(species) fainted!"]
    case "-crit":
        return ["A critical hit!"]
    case "-supereffective":
        return ["It's super effective!"]
    case "-resisted":
        return ["It's not very effective..."]
    case "-miss":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[3])
        return ["\(renderPrefix(side))\(species) avoided the attack!"]
    case "-status":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let name = "\(renderPrefix(side))\(species)"
        switch f[3] {
        case "brn": return ["\(name) was burned!"]
        case "psn": return ["\(name) was poisoned!"]
        case "tox": return ["\(name) was badly poisoned!"]
        case "par": return ["\(name) was paralyzed! It may be unable to move!"]
        case "slp": return ["\(name) fell asleep!"]
        case "frz": return ["\(name) was frozen solid!"]
        default: return []
        }
    case "-item":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let item = f[3]
        let name = "\(renderPrefix(side))\(species)"
        if item.contains("ite") && item != "Eviolite" {
            return ["\(name)'s \(item) is reacting to the Key Stone!"]
        }
        if item.hasSuffix("Berry") {
            renderBerryAt[f[2]] = (item, sNow())
            return ["\(name) ate its \(item)!"]
        }
        return ["[\(name)'s \(item)]"]
    case "-ability":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["[\(renderPrefix(side))\(species)'s \(f[3])]"]
    case "detailschange":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["\(renderPrefix(side))\(species) has Mega Evolved into Mega \(species)!"]
    case "-mega":
        return []
    case "-weather":
        guard f.count >= 3 else { return [] }
        let w = f[2]
        var out: [String] = []
        switch w {
        case "Sunny Day": out = ["The sunlight turned harsh!"]
        case "Rain Dance": out = ["It started to rain!"]
        case "Sandstorm": out = ["A sandstorm kicked up!"]
        case "Snow", "Snowscape": out = ["It started to snow!"]
        case "none":
            switch renderWeatherProto {
            case "Sunny Day": out = ["The sunlight faded."]
            case "Rain Dance": out = ["The rain stopped."]
            case "Sandstorm": out = ["The sandstorm subsided."]
            case "Snow", "Snowscape": out = ["The snow stopped."]
            default: out = []
            }
        default: out = []
        }
        renderWeatherProto = (w == "none") ? "" : w
        return out
    case "-fieldstart", "-fieldend":
        guard f.count >= 3 else { return [] }
        let terrain = f[2].replacingOccurrences(of: "move: ", with: "").replacingOccurrences(of: " Terrain", with: "")
        if f[1] == "-fieldstart" {
            switch terrain {
            case "Trick Room": return []
            case "Psychic": return ["The battlefield got weird!"]
            case "Electric": return ["An electric current ran across the battlefield!"]
            case "Grassy": return ["Grass grew to cover the battlefield!"]
            case "Misty": return ["Mist swirled around the battlefield!"]
            default: return []
            }
        } else {
            switch terrain {
            case "Trick Room": return ["The dimensions returned to normal!"]
            case "Psychic": return ["The battlefield returned to normal."]
            case "Electric": return ["The electricity disappeared from the battlefield."]
            case "Grassy": return ["The grass disappeared from the battlefield."]
            case "Misty": return ["The mist disappeared from the battlefield."]
            default: return []
            }
        }
    case "-boost", "-unboost":
        guard f.count >= 5, let n = Int(f[4]) else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let statName = ["atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed", "acc": "accuracy", "eva": "evasion"][f[3]] ?? f[3]
        let name = "\(renderPrefix(side))\(species)"
        if f[1] == "-boost" {
            return ["\(name)'s \(statName) \(n >= 3 ? "drastically rose!" : n == 2 ? "sharply rose!" : "rose!")"]
        } else {
            return ["\(name)'s \(statName) \(n >= 3 ? "severely fell!" : n == 2 ? "harshly fell!" : "fell!")"]
        }
    case "-singleactivate":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3].contains("Follow Me") || f[3].contains("Rage Powder") {
            return ["\(renderPrefix(side))\(species) became the center of attention!"]
        }
        return []
    case "-start":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3] == "move: Yawn" { return ["\(renderPrefix(side))\(species) became drowsy!"] }
        return []
    case "-activate":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3].contains("Focus Sash") { return ["(\(renderPrefix(side))\(species) held on thanks to its Focus Sash!)"] }
        if f[3].contains("Protect") || f[3].contains("Detect") { return ["\(renderPrefix(side))\(species) protected itself!"] }
        if f[3].contains("Wide Guard") { return ["\(renderPrefix(side))\(species) was protected by Wide Guard!"] }
        if f[3].contains("Terrain") {
            let tn = f[3].replacingOccurrences(of: "move: ", with: "")
            return ["\(renderPrefix(side))\(species) was protected by the \(tn)!"]
        }
        return []
    case "-sidestart", "-sideend":
        guard f.count >= 4 else { return [] }
        if f[3].contains("Stealth Rock") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Pointed stones float around the opposing team!)" : "(Pointed stones float around your team!)"]
            }
            return [f[2] == "p2" ? "(The pointed stones disappeared from around the opposing team!)" : "(The pointed stones disappeared from around your team!)"]
        }
        if f[3].contains("Toxic Spikes") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Poison spikes were scattered on the ground around the opposing team!)" : "(Poison spikes were scattered on the ground around your team!)"]
            }
            return [f[2] == "p2" ? "(The poison spikes disappeared from the ground around the opposing team!)" : "(The poison spikes disappeared from the ground around your team!)"]
        }
        if f[3].contains("Spikes") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Spikes were scattered on the ground around the opposing team!)" : "(Spikes were scattered on the ground around your team!)"]
            }
            return [f[2] == "p2" ? "(The spikes disappeared from the ground around the opposing team!)" : "(The spikes disappeared from the ground around your team!)"]
        }
        if f[3].contains("Tailwind") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(The Tailwind started blowing on the opposing team's side!)" : "(The Tailwind started blowing!)"]
            }
            return [f[2] == "p2" ? "(The Tailwind on the opposing team's side stopped blowing.)" : "(The Tailwind stopped blowing.)"]
        }
        return []
    case "-cant":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let name = "\(renderPrefix(side))\(species)"
        switch f[3] {
        case "par": return ["\(name) is paralyzed! It can't move!"]
        case "frz": return ["\(name) is frozen solid! It can't move!"]
        case "slp": return ["\(name) is fast asleep."]
        case "flinch": return ["\(name) flinched and couldn't move!"]
        default: return []
        }
    case "-fail":
        return ["But it failed!"]
    case "-message":
        return f.count >= 3 ? [f.dropFirst(2).joined(separator: "|")] : []
    case "win":
        guard f.count >= 3 else { return [] }
        var winner = f[2]
        if winner == "p1" { winner = trainerMine.isEmpty ? "You" : trainerMine }
        if winner == "p2" { winner = oppName }
        if let fn = forfeitName {
            return ["\(fn) forfeited.", "", "\(winner) won the battle!"]
        }
        return ["\(winner) won the battle!"]
    default:
        return []
    }
}

func renderLabelParts(_ label: String) -> (slot: String, side: String, species: String) {
    let parts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let slot = parts.first ?? ""
    return (slot, slot.hasPrefix("p2") ? "p2" : "p1", parts.count > 1 ? parts[1] : "")
}

func renderPrefix(_ side: String) -> String { side == "p2" ? "The opposing " : "" }

func renderPct(of hpText: String) -> Int? {
    if hpText.contains("fnt") { return 0 }
    let parts = hpText.split(separator: "/")
    guard parts.count == 2, let c = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let m = Int(parts[1].trimmingCharacters(in: .whitespaces)), m > 0 else { return nil }
    return Int((Double(c) * 100.0 / Double(m)).rounded())
}

func healSource(plateName: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) -> (label: String, itemJa: String?)? {
    let delta = toPct - fromPct
    guard delta > 0 else { return nil }
    // 文で判明した回復の発生源 (おちゃかいの回復等) が控えてあれば
    // それを最優先する。回復量は最大の 1/4 前後 (実例: 2026-11-23
    // battle_20261123_090354、ミロカロス 62 -> 85 が発生源なしとして
    // 抑えられ、基準値が止まって後続の低下まで呑んだ)
    if let ph = pendingHealFrom[key], sNow().timeIntervalSince(ph.at) < 10, (20...30).contains(delta) {
        pendingHealFrom[key] = nil
        return (ph.label, nil)
    }
    // 自軍データ (teamEntries) は種族キーなので、相手側の同種族に
    // 引きずられないよう p1 の枠のときだけ参照する (実例: 2026-11-20
    // vs チェイス戦、相手エルフーンのオボン回復が、自軍エルフーンの
    // バビリのみ所持に引っ張られて [from] 無しになった)
    let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
        : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
    // 自分が直前に使った吸収技による回復は、持ち物の回復より優先して
    // 技へ帰属させる (実例: 2026-11-22 battle_20261122_091721、
    // ドレインキッスの吸収回復が、消費済みの オボンのみ の再発動に化けた)
    let drainMoves: Set<String> = ["Absorb", "Mega Drain", "Giga Drain", "Drain Punch", "Leech Life",
                                   "Horn Leech", "Oblivion Wing", "Parabolic Charge", "Draining Kiss",
                                   "Dream Eater", "Bitter Blade", "Matcha Gotcha", "Strength Sap"]
    let mySlot = slotFor(side: key.hasPrefix("p2") ? "p2" : "p1", speciesEn: speciesEn)
    if lastMoveLabel == "\(mySlot): \(speciesEn)", drainMoves.contains(lastMoveName),
       sNow().timeIntervalSince(lastMoveMsgAt) < 20 {
        return ("move: \(lastMoveName)", nil)
    }
    // 消費済みの持ち物は二度と発動しない
    if fromPct <= 50 && (12...30).contains(delta) && !itemLostActive.contains(key) {
        // 持ち物がオボンのみと判明している場合は、プレート読みの
        // ぶれ (実例: 2026-11-22 battle_20261122_050512、回復量が
        // +16% と読まれた) を許容して幅を広げる。未判明の場合は
        // 従来どおり +25% 前後の狭い幅でだけ推定する
        if knownItem == "オボンのみ" { return ("item: Sitrus Berry", "オボンのみ") }
        if knownItem == nil && delta >= 20 { return ("item: Sitrus Berry", "オボンのみ") }
        if delta >= 20 { return nil }
    }
    if (3...8).contains(delta) {
        let abilityJa = key.hasPrefix("p2") ? revealedAbilities[speciesEn]
            : ((teamEntries[speciesEn]?["ability"] as? String) ?? revealedAbilities[speciesEn])
        if abilityJa == "あめうけざら" || abilityJa == "アイスボディ" { return nil }
        if logFieldTerrain == "Grassy" && grassyHealTurn[plateName] != currentTurn {
            grassyHealTurn[plateName] = currentTurn
            return ("Grassy Terrain", nil)
        }
        // 持ち物が消費済みと判明している個体に、たべのこし はあり
        // 得ない (実例: 2026-11-22 battle_20261122_201011、T7 に
        // オボンのみが発動した自軍ガオガエンのグラスフィールド
        // 回復が、T8 に たべのこし の判明行へ化けた。自軍の判明は
        // applyEvent が記録しないため knownItem が未判明のままに
        // なる経路の対策)
        if itemLostActive.contains(key) { return nil }
        if knownItem == nil || knownItem == "たべのこし" { return ("item: Leftovers", "たべのこし") }
        return nil
    }
    return nil
}

func boostLine(slot: String, speciesEn: String, stat: String, delta: Int) -> String {
    delta > 0 ? "|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)" : "|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)"
}

func translateLogEntry(chip: String, text: String, side: String, turn: Int) {
    guard let sp0 = findSpeciesJa(in: text) else {
        // 主語が解決できないエントリでも、確度の高い信号だけは救済する。
        // ランク変化は直近ターンのエントリだけ (古いエントリからの適用は
        // 実況経路の一本化方針に反し、二重適用の危険があるため)
        _ = salvageFromText(text, allowBoost: turn >= currentTurn - 1, fromLogScreen: true)
        if debugMode { print("    -> 種族名が本文に無いため取り込めませんでした") }
        return
    }
    // ログ画面の種族名は雌雄表記が同一のため、場のフォルムに寄せる
    // (寄せないと「イエッサン」のような基本フォルム名で記録される)
    let sp = fieldAnchoredSpecies(sp0)
    let side = validatedSide(forSpecies: sp.en, claimed: side)
    let slot = slotFor(side: side, speciesEn: sp.en)
    let key = "\(side):\(sp.en)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // その枠に出てきたばかりの種族への ひんし 帰属は信用しない。
    // ログ画面のエントリ取り違えで、交代直後の生存枠に幻のひんしが
    // 出た実例があるため (2026-11-20 vs チェイス戦のグレンアルマ)。
    // 本当に倒れていれば実況・プレート側の経路が別途ひんしを出す
    let justSwitchedIn = lastSwitchIn[key].map { $0.slot == slot && sNow().timeIntervalSince($0.at) < 30 } ?? false
    switch chip {
    case "技":
        if let mvJa = findInDict(in: text, moveNameOrig) {
            // 実況メッセージ側で記録済みの (枠・技・ターン) は二重に出さない
            // (実例: 2026-11-20、まもる が実況とログ画面の両方から出た)
            let moveEn = moveJa2En[mvJa] ?? mvJa
            let sig = slot + "|" + moveEn + "|t" + String(turn)
            if lastMoveSigAt[sig] != nil { break }
            lastMoveSigAt[sig] = sNow()
            emitLog("|move|\(slot): \(sp.en)|\(moveEn)")  // 判明登録は applyEvent が行う
            applyMoveField(mvJa, side: side)
        } else if debugMode {
            print("    -> 技名が辞書に見つかりませんでした")
        }
    case "HP減少", "回復":
        if let g = regexGroups(#"HP\s*(\d+)(%?)\s*(?:→|->)\s*(\d+)(%?)"#, text), g.count >= 5,
           let bVal = Int(g[3]) {
            let isPct = !g[2].isEmpty || !g[4].isEmpty
            var newPct: Int? = nil
            var hpText = ""
            if isPct {
                newPct = bVal
                hpText = "\(bVal)/100"
            } else if let mx = monStates[key]?.hpMax {
                newPct = Int((Double(bVal) / Double(mx) * 100).rounded())
                hpText = "\(bVal)/\(mx)"
            } else if bVal == 0 {
                newPct = 0
                hpText = "0/100"
            }
            if let np = newPct, let cur = monStates[key]?.hpPercent, np != cur {
                // 1 エントリで 55 ポイントを超える回復はあり得ない
                // (最大でも じこさいせい/ねがいの 50%)。隣の行の値を
                // 拾った誤読とみて取り込まない (実例: 2026-11-20、
                // 残り 4 のイエッサンが「全回復」として取り込まれた)
                if np > cur && np - cur > 55 {
                    debugCapture(kind: "hp_jump_rejected", key: "hp_jump|\(key)", rawText: text,
                                 detail: ["slot": slot, "species": sp.en, "fromPct": cur, "toPct": np])
                    break
                }
                // 状態への反映は emitLog -> applyEvent が行う (行の HP 表記から)
                if np < cur { emitLog("|-damage|\(slot): \(sp.en)|\(hpText)") }
                else { emitLog("|-heal|\(slot): \(sp.en)|\(hpText)") }
                if np == 0 && !justSwitchedIn { emitLog("|faint|\(slot): \(sp.en)") }
                else if np == 0 && justSwitchedIn {
                    debugCapture(kind: "faint_guard", key: "faint_guard|\(key)", rawText: text,
                                 detail: ["slot": slot, "species": sp.en, "source": "logscreen_hp"])
                }
            }
        }
    case "ひんし":
        if !justSwitchedIn && (monStates[key]?.hpPercent ?? 0) > 0 {
            emitLog("|faint|\(slot): \(sp.en)")  // 状態への反映は applyEvent が行う
        } else if justSwitchedIn {
            debugCapture(kind: "faint_guard", key: "faint_guard|\(key)", rawText: text,
                         detail: ["slot": slot, "species": sp.en, "source": "logscreen_faint_text"])
        }
    case "持ち物":
        if let itJa = findInDict(in: text, itemDict) {
            // メガストーンが特定できた場合は、種族をストーンから
            // 決め直す。ログ画面の小さい文字では種族名の末尾が
            // 落ちやすく (リザードン → リザード)、本文の名前検索
            // だけでは別種に一致するため (実例: 2026-11-22
            // battle_20261122_051707、Charmeleon の持ち物行)。
            // 実況側のメガ反応分岐 (build 20261122_0552) と同じ規則
            var useSp = sp
            var useSide = side
            var useSlot = slot
            if itJa.contains("ナイト"), let sEn = itemJa2En[itJa] {
                var baseEn = sEn
                for suf in ["ite X", "ite Y", "ite Z", "ite"] where baseEn.hasSuffix(suf) {
                    baseEn = String(baseEn.dropLast(suf.count)); break
                }
                if let stoneSp = speciesDict.first(where: { $0.en == baseEn }), stoneSp.en != sp.en {
                    useSp = stoneSp
                    useSide = validatedSide(forSpecies: stoneSp.en, claimed: side)
                    useSlot = slotFor(side: useSide, speciesEn: stoneSp.en)
                }
            }
            emitItemOnce(slot: useSlot, side: useSide, speciesEn: useSp.en, itemJa: itJa)  // 判明登録は applyEvent が行う
        }
    case "特性":
        if let abJa = findInDict(in: text, abilityDict) {
            emitLog("|-ability|\(slot): \(sp.en)|\(abilityJa2En[abJa] ?? abJa)")  // 判明登録は applyEvent が行う
        }
    default:
        break
    }
    checkStatusText(text: text, side: side, speciesEn: sp.en, slot: slot)
    // ランク変化はここでは適用しない: 実況メッセージで取り込み済みの変化が
    // ログ画面のエントリから二重に適用されてしまうため (ログが 2 重に出る
    // 原因の 1 つ)。ランク変化の取り込みは実況メッセージ経路に一本化する。
    // 天候・フィールドも、古いエントリの開始/終了文で現行の状態を
    // 上書きしないよう fromLogScreen を伝える (setter 側で stale 判定)
    checkFieldText(text: text, fromLogScreen: true)
}

func validatedSide(forSpecies en: String, claimed: String) -> String {
    let inMine = lastSlots["mineA"]?.speciesEn == en || lastSlots["mineB"]?.speciesEn == en
    let inOpp = lastSlots["oppA"]?.speciesEn == en || lastSlots["oppB"]?.speciesEn == en
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    let teamMine = teamEntries[en] != nil
    let teamOpp = oppTeamSeen.contains(en)
    if teamMine != teamOpp { return teamMine ? "p1" : "p2" }
    return claimed
}

func regexGroups(_ pattern: String, _ text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
}

func pullBackSwitchBlock(label: String, splitMega: Bool = false, requireEarlySegment: Bool = false) -> (proto: [String], display: [String], protoHead: [String], displayHead: [String]) {
    guard let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) else { return ([], [], [], []) }
    if requireEarlySegment {
        // 確定経路からの引き戻しは、そのターンの序盤の区間にだけ
        // 適用する。ひんし行がある、または技行が 3 件以上ある
        // 発達した区間では、ターン行の検出遅れで前ターンの区間と
        // 混ざっている可能性が高く、引き戻すと交代とその後の
        // 出来事まで前ターン側へ連れていかれる (実例: 2026-11-22
        // battle_20261122_185505、実ターン 3 の Sylveon の交代と
        // 被ダメがターン 2 冒頭へ引き戻された)
        var segMoves = 0, segFaints = 0
        for l in battleLog[(turnIdx + 1)...] {
            if l.hasPrefix("|move|") { segMoves += 1 }
            if l.hasPrefix("|faint|") { segFaints += 1 }
        }
        if segFaints >= 1 || segMoves >= 3 { return ([], [], [], []) }
    }
    var switchIdx: Int? = nil
    for i in (turnIdx + 1)..<battleLog.count {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|switch|"), f.count >= 3, f[2] == label { switchIdx = i }
    }
    guard let si = switchIdx else { return ([], [], [], []) }
    let side = String(label.prefix(2))
    for i in (turnIdx + 1)..<si {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|faint|"), f.count >= 3, f[2].hasPrefix(side) { return ([], [], [], []) }
    }
    var idxs = [si]
    if si + 1 < battleLog.count {
        var passedMove = false
        for j in (si + 1)..<battleLog.count {
            let l = battleLog[j]
            if l.hasPrefix("|move|") { passedMove = true }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, f[2] == label else { continue }
            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
            // 交代行に付随する補完の被ダメ・回復行 (入場時点の差分) も
            // ブロックの一部として一緒に引き戻す。ただし次の技行より
            // 後ろの同名行はその技の結果なので対象にしない。
            // 経過ダメージ (天候・状態異常・拘束等) の行はターン終了時
            // の出来事であり、入場差分ではないため一緒に移さない
            // (実例: 2026-11-23 battle_20261123_090354 ターン2、
            // ミロカロスの砂嵐チップ行が交代と一緒にターン頭へ
            // 引き戻された)
            else if !passedMove && (l.hasPrefix("|-damage|") || l.hasPrefix("|-heal|")) {
                let residualFroms = ["sandstorm", "hail", "brn", "psn", "tox", "Leech Seed", "Curse", "Salt Cure",
                                     "Fire Spin", "Sand Tomb", "Whirlpool", "Bind", "Wrap", "Clamp", "Magma Storm",
                                     "Infestation", "Snap Trap", "Thunder Cage", "Nightmare"]
                var isResidual = false
                if let r = l.range(of: "[from] ") {
                    let v = String(l[r.upperBound...]).split(separator: "|").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
                    isResidual = residualFroms.contains(v)
                }
                if !isResidual { idxs.append(j) }
            }
        }
    }
    // メガ進化は、交代で入場したそのターンには起こらない (交代が
    // そのターンの行動を消費する)。検証済みの実像
    // (battle_20261122_091721: 交代はターン5頭、メガ行はターン6頭)
    // に合わせ、splitMega の場合はメガ一式 (石の持ち物行・
    // detailschange・-mega) を分離して返す。呼び手 (ターン行ガード)
    // が、交代側を前のターンの頭へ、メガ側を新しいターンの頭へ置く
    var headIdxs: [Int] = []
    var restIdxs = idxs
    if splitMega, let k = idxs.firstIndex(where: { battleLog[$0].hasPrefix("|detailschange|") || battleLog[$0].hasPrefix("|-mega|") }) {
        var start = k
        if k > 0, battleLog[idxs[k - 1]].hasPrefix("|-item|") { start = k - 1 }
        headIdxs = Array(idxs[..<start])
        restIdxs = Array(idxs[start...])
    }
    let pulled = restIdxs.map { battleLog[$0] }
    let pulledHead = headIdxs.map { battleLog[$0] }
    for i in idxs.reversed() { battleLog.remove(at: i) }
    // 表示側: 交代の描画 (引き戻し行 + 繰り出し行) と石への反応・
    // メガ進化の描画行を、最後のターン見出しより後ろから集める
    let species = label.split(separator: ":").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    var dispIdxs: [Int] = []
    var dStart = 0
    for (i, l) in displayLog.enumerated() where l.hasPrefix("Turn ") { dStart = i + 1 }
    if !species.isEmpty, dStart < displayLog.count {
        var dispPassedMove = false
        for i in dStart..<displayLog.count {
            let l = displayLog[i]
            if l.contains(" used ") { dispPassedMove = true }
            if l == "Go! \(species)!" || l.hasSuffix("sent out \(species)!") { dispIdxs.append(i) }
            else if l.hasSuffix("is reacting to the Key Stone!") && l.contains(species) { dispIdxs.append(i) }
            else if l.contains("has Mega Evolved into") && l.contains(species) { dispIdxs.append(i) }
            else if !dispPassedMove && l.contains("\(species) lost") && l.hasSuffix("of its health!)") { dispIdxs.append(i) }
        }
        if let first = dispIdxs.first, first > dStart {
            let prev = displayLog[first - 1]
            if prev.hasSuffix("come back!") || prev.contains("withdrew") { dispIdxs.insert(first - 1, at: 0) }
        }
    }
    var dispHeadIdxs: [Int] = []
    var dispRestIdxs = dispIdxs
    if !headIdxs.isEmpty {
        // 表示側も同じ分割にする: 石への反応とメガ進化の描画は新しい
        // ターン側、それ以外 (引き戻し・繰り出し・補完の被ダメ描画) は
        // 前のターン側
        dispRestIdxs = dispIdxs.filter { displayLog[$0].hasSuffix("is reacting to the Key Stone!") || displayLog[$0].contains("has Mega Evolved into") }
        dispHeadIdxs = dispIdxs.filter { !dispRestIdxs.contains($0) }
    }
    let pulledDisplay = dispRestIdxs.map { displayLog[$0] }
    let pulledDisplayHead = dispHeadIdxs.map { displayLog[$0] }
    for i in dispIdxs.reversed() { displayLog.remove(at: i) }
    return (pulled, pulledDisplay, pulledHead, pulledDisplayHead)
}

func minePlateAdmitted(plateKey: String, entry: SpeciesEntry) -> Bool {
    // 当該試合の暫定リストにある種族は、登録より優先して受け入れる
    for case let e? in battleMineTeam where sameSpeciesFamily(e.species, entry.en) { return true }
    if teamEntries.isEmpty { return true }
    let grp = formeGroup(entry)
    if grp.contains(where: { teamEntries[$0.en] != nil }) { return true }
    if grp.contains(where: { battleAdmittedSpecies.contains($0.en) }) { return true }
    let k = "\(plateKey)|\(entry.en)"
    let n = (offTeamPlateStreak[k] ?? 0) + 1
    offTeamPlateStreak[k] = n
    if n >= 3 {
        for m in grp { battleAdmittedSpecies.insert(m.en) }
        debugCapture(kind: "off_team_plate", key: "off_team_plate:\(entry.en)", rawText: "",
                     detail: ["species": entry.en, "plate": plateKey, "sightings": n, "turn": currentTurn, "readerBuild": readerBuild])
        return true
    }
    return false
}

func noteBattleMaxRead(speciesEn: String, readMax: Int, registeredMax: Int?) {
    // 採用は各種族・試合ごとに 1 回限り: 最初の採用で登録側の取り違えは
    // 正せるが、それ以降も読みに追随すると、同じ誤読 (数字融合) の
    // 繰り返しで誤った最大へ際限なく乗り換えてしまう (実例:
    // 2026-11-22 battle_20261122_160927、171 の正しい採用の後に
    // 271 の融合読みが上書き採用された)
    if let ov = battleMaxOverride[speciesEn] {
        // 採用後に登録値どおりの読みが続けば、採用の方が誤読だった
        // として取り消す。登録はユーザーが確認した情報であり、離れる
        // 方向 (採用) は慎重に、戻る方向 (取消し) は速くする
        // (実例: 2026-11-23 battle_20261123_043809、Sylveon の最大が
        // 交代直後の誤読 219 で採用され、実値 193 の読みが続いても
        // 上書きが残り続けた)
        if let reg = registeredMax, ov != reg, readMax == reg {
            let n = (battleMaxRevertCount[speciesEn] ?? 0) + 1
            if n >= 3 {
                battleMaxOverride[speciesEn] = nil
                battleMaxRevertCount[speciesEn] = nil
                debugCapture(kind: "team_max_reverted", key: "team_max_reverted:\(speciesEn)", rawText: "",
                             detail: ["species": speciesEn, "registeredMax": reg, "revertedMax": ov, "turn": currentTurn, "readerBuild": readerBuild])
            } else {
                battleMaxRevertCount[speciesEn] = n
            }
        } else if readMax == ov {
            battleMaxRevertCount[speciesEn] = nil
        }
        return
    }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }
    // 候補として数える前の妥当性ゲート: 信頼値から 36 を超えて離れた
    // 読みは、努力値の振り幅 (最大でも 32) では説明できず、数字融合
    // (171 -> 271、177 -> 371) の疑いが強いため候補にしない。また、
    // その種族で既に観測した現在 HP より小さい最大はあり得ない
    if let reg = registeredMax, reg > 0, abs(readMax - reg) > 36 { return }
    if let curText = monStates["p1:\(speciesEn)"]?.hpText,
       let cur = Int(curText.split(separator: "/").first ?? ""), readMax < cur { return }
    // 別種族の既知の最大と寸分違わぬ読みは、隣枠の最大の混入の疑い
    // として候補に数えない (実例: 2026-11-22 battle_20261122_171847、
    // Sneasler の最大として同じ自軍の Indeedee-F の最大 177 が
    // 2 回続けて読まれ、そのまま採用されて幻の被ダメ行が出た)
    for (other, entry) in teamEntries where other != speciesEn {
        if let h = (entry["stats"] as? [String: Int])?["hp"], h == readMax { return }
    }
    for (k, st) in monStates where k.hasPrefix("p1:") && k != "p1:\(speciesEn)" {
        if let h = st.hpMax, h == readMax { return }
    }
    if let cand = battleMaxCandidate[speciesEn], cand.max == readMax {
        let n = cand.count + 1
        // 採用は、候補の初出から 3 秒以上あいた観測での一致を条件と
        // する。交代直後などの短い窓では同じ誤読が連続して出るため、
        // 回数だけでは誤読のバーストを弾けない (実例: 2026-11-23
        // battle_20261123_043809、Sylveon の 219)
        if n >= 2 && sNow().timeIntervalSince(cand.firstAt) >= 3.0 {
            battleMaxOverride[speciesEn] = readMax
            battleMaxCandidate[speciesEn] = nil
            debugCapture(kind: "team_max_mismatch", key: "team_max_mismatch:\(speciesEn)", rawText: "",
                         detail: ["species": speciesEn, "registeredMax": registeredMax ?? -1, "readMax": readMax, "turn": currentTurn, "readerBuild": readerBuild])
        } else {
            battleMaxCandidate[speciesEn] = (max: readMax, count: n, firstAt: cand.firstAt)
        }
    } else {
        battleMaxCandidate[speciesEn] = (max: readMax, count: 1, firstAt: sNow())
    }
}

func battleKnownMax(speciesEn: String, grp: [SpeciesEntry]) -> Int? {
    if let o = battleMaxOverride[speciesEn] { return o }
    // 暫定リストで実数値が判明している種族はそれを使う (登録より優先)
    for case let e? in battleMineTeam where e.species == speciesEn {
        if let m = e.hpMax { return m }
    }
    for m in grp {
        if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { return h }
    }
    return monStates["p1:\(speciesEn)"]?.hpMax
}

func fieldSourceOnField(_ ui: String) -> Bool {
    let ability: String?
    switch ui {
    case "Psychic": ability = "Psychic Surge"
    case "Electric": ability = "Electric Surge"
    case "Grassy": ability = "Grassy Surge"
    case "Misty": ability = "Misty Surge"
    case "Sun": ability = "Drought"
    case "Rain": ability = "Drizzle"
    case "Sand": ability = "Sand Stream"
    case "Snow": ability = "Snow Warning"
    default: ability = nil
    }
    guard let ab = ability else { return true }
    for s in lastSlots.values {
        if (speciesAbilityMap[s.speciesEn] ?? []).contains(ab) { return true }
        for (other, pool) in speciesAbilityMap where pool.contains(ab) && sameSpeciesFamily(other, s.speciesEn) { return true }
    }
    // 交代の記録 (文経路) が先行している場合も出所として認める
    for (key, sw) in lastSwitchIn where sNow().timeIntervalSince(sw.at) < 25 {
        let sp = key.split(separator: ":").last.map(String.init) ?? ""
        if (speciesAbilityMap[sp] ?? []).contains(ab) { return true }
        for (other, pool) in speciesAbilityMap where pool.contains(ab) && sameSpeciesFamily(other, sp) { return true }
    }
    return false
}

func megaLabelSpecies(side: String, speciesEn: String) -> (slot: String, speciesEn: String) {
    let slot = slotFor(side: side, speciesEn: speciesEn)
    let pn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
    if let occ = lastSlots[pn]?.speciesEn, sameSpeciesFamily(occ, speciesEn) { return (slot, occ) }
    return (slot, speciesEn)
}

func syncMineProvisional() {
    if minePreviewTeam != minePreviewSeenCopy {
        minePreviewSeenCopy = minePreviewTeam
        if minePreviewTeam.contains(where: { $0 != nil }) { minePreviewUpdatedAt = sNow() }
    }
    // 鮮度: 同定の更新が直近の試合開始より 120 秒以上前なら、前の
    // 試合の同定結果なので使わない
    let fresh = minePreviewUpdatedAt.map {
        $0.timeIntervalSince(lastBattleStartedAt ?? .distantPast) > -120
    } ?? false
    // 空の同定結果では置き換えない。選出セッションのリセットで
    // minePreviewTeam が空に戻ると、対戦開始直後に暫定リストまで
    // 消えて、プレート受け入れが 3 回観測の off-team 経路に落ちた
    // (実例: 2026-11-22 battle_20261122_185505、ヘッダーは暫定
    // リストで出たのに T1 の Garchomp が off-team 経路を通った)。
    // 対戦中は、暫定リストがまだ無い場合に限り取り込む
    let hasIdentified = minePreviewTeam.contains(where: { $0 != nil })
    if fresh && hasIdentified && minePreviewTeam != minePreviewAppliedCopy
        && (!logStarted || battleMineTeam.isEmpty) {
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
        if e.hpMax == nil, let m = monStates["p1:\(e.species)"]?.hpMax, m > 0 {
            e.hpMax = m
        }
        battleMineTeam[i] = e
    }
}

func mineTeamJSON() -> String {
    var parts: [String] = []
    for case let e? in battleMineTeam {
        var s = "{\"species\": \"\(jsonEscape(e.species))\", \"source\": \"\(jsonEscape(e.source))\""
        if let a = e.ability { s += ", \"ability\": \"\(jsonEscape(a))\"" }
        if let it = e.item { s += ", \"item\": \"\(jsonEscape(it))\"" }
        if !e.moves.isEmpty {
            s += ", \"moves\": [\(e.moves.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]"
        }
        if let m = e.hpMax { s += ", \"hpMax\": \(m)" }
        if e.onField { s += ", \"onField\": true" }
        parts.append(s + "}")
    }
    return parts.isEmpty ? "" : ", \"mineTeam\": [\(parts.joined(separator: ", "))]"
}

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

func mineProvisionalSpecies() -> [String] {
    battleMineTeam.compactMap { $0?.species }
}

func announcedSlot(side: String, speciesEn: String) -> String {
    for (name, s) in lastSlots where (name.hasPrefix("mine") ? "p1" : "p2") == side && s.speciesEn == speciesEn {
        return slotId(name)
    }
    let plates = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
    let candPlates = plates.filter { pendingSwitchCandidates[$0]?[speciesEn] != nil }
    if candPlates.count == 1 { return slotId(candPlates[0]) }
    return slotFor(side: side, speciesEn: speciesEn)
}

func noteItemLost(slot: String, side: String, speciesEn: String) {
    // 消費・喪失の状態反映は applyEvent (|-enditem|) が行う。この行自体は
    // 画面に表示される出来事ではないため、ログには残さず直接適用する
    applyEvent("|-enditem|\(slot): \(speciesEn)")
    let abilityJa = side == "p1" ? (teamEntries[speciesEn]?["ability"] as? String) : revealedAbilities[speciesEn]
    guard abilityJa == "かるわざ" else { return }
    emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Unburden")
}

func writeState() {
    // state.json はバトルログ由来の状態 (monStates) から生成する
    syncMineProvisional()
    func slotJSON(_ key: String) -> String? {
        guard let s = lastSlots[key] else { return nil }
        let side = key.hasPrefix("mine") ? "p1" : "p2"
        let st = monStates["\(side):\(s.speciesEn)"]
        var e = "{\"species\": \"\(jsonEscape(s.speciesEn))\", \"curHPPercent\": \(st?.hpPercent ?? s.hpPercent)"
        if let st, !st.status.isEmpty { e += ", \"status\": \"\(st.status)\"" }
        if unburdenActive.contains("\(side):\(s.speciesEn)") { e += ", \"unburden\": true" }
        if itemLostActive.contains("\(side):\(s.speciesEn)") { e += ", \"itemLost\": true" }
        if let st, !st.megaSpecies.isEmpty { e += ", \"mega\": true, \"megaSpecies\": \"\(jsonEscape(st.megaSpecies))\"" }
        // boosts は常に全7能力をそろえて出す (0 のものも省略しない)
        let bs = stateBoostKeys.map { "\"\($0)\": \(st?.boosts[$0] ?? 0)" }
        e += ", \"boosts\": {\(bs.joined(separator: ", "))}"
        if side == "p2" {
            var rev: [String] = []
            if let mv = revealedMoves[s.speciesEn], !mv.isEmpty {
                rev.append("\"moves\": [\(mv.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]")
            }
            if let it = revealedItems[s.speciesEn] { rev.append("\"item\": \"\(jsonEscape(it))\"") }
            if let ab = revealedAbilities[s.speciesEn] { rev.append("\"ability\": \"\(jsonEscape(ab))\"") }
            if !rev.isEmpty { e += ", \"revealed\": {\(rev.joined(separator: ", "))}" }
        }
        return e + "}"
    }
    let mine = [slotJSON("mineA"), slotJSON("mineB")].compactMap { $0 }
    let opps = [slotJSON("oppA"), slotJSON("oppB")].compactMap { $0 }
    if mine.isEmpty && opps.isEmpty { return }
    let team = oppTeamSeen.isEmpty ? "" : ", \"oppTeam\": [\(oppTeamSeen.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]"
    let mineTeamJson = mineTeamJSON()
    // 判明情報は場に出ていない相手分も含めて全種族分を送る (UI は項目単位で反映する)
    var revAll: [String] = []
    for sp in Set(revealedMoves.keys).union(revealedItems.keys).union(revealedAbilities.keys).sorted() {
        var parts: [String] = []
        if let mv = revealedMoves[sp], !mv.isEmpty {
            parts.append("\"moves\": [\(mv.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]")
        }
        if let it = revealedItems[sp] { parts.append("\"item\": \"\(jsonEscape(it))\"") }
        if let ab = revealedAbilities[sp] { parts.append("\"ability\": \"\(jsonEscape(ab))\"") }
        if !parts.isEmpty { revAll.append("\"\(jsonEscape(sp))\": {\(parts.joined(separator: ", "))}") }
    }
    let revJson = revAll.isEmpty ? "" : ", \"oppRevealed\": {\(revAll.joined(separator: ", "))}"
    // フィールドは両キー常時送る (空文字 = なし)。片方だけ送ると UI 側に
    // 終了したはずの天候・フィールドが残り続けるため。残りターンは
    // 継続中のものだけ追加キーで送る (期限切れ・未設定ではキーを出さない)
    var fieldParts = ["\"terrain\": \"\(logFieldTerrain)\"", "\"weather\": \"\(logFieldWeather)\""]
    let wLeft = turnsLeft(setTurn: fieldWeatherSetTurn, duration: fieldDurations)
    if !logFieldWeather.isEmpty && wLeft > 0 { fieldParts.append("\"weatherTurnsLeft\": \(wLeft)") }
    let tLeft = turnsLeft(setTurn: fieldTerrainSetTurn, duration: fieldDurations)
    if !logFieldTerrain.isEmpty && tLeft > 0 { fieldParts.append("\"terrainTurnsLeft\": \(tLeft)") }
    let rLeft = turnsLeft(setTurn: fieldTrickRoomSetTurn, duration: fieldDurations)
    if logTrickRoom && rLeft > 0 { fieldParts.append("\"trickRoomTurnsLeft\": \(rLeft)") }
    let field = "{\(fieldParts.joined(separator: ", "))}"
    // サイド状態 (壁・おいかぜ等) は継続中のものだけ、サイドごとに
    // 状態名 -> 残りターン で送る
    var scParts: [String] = []
    for sd in ["p1", "p2"] {
        guard let conds = sideCondSetTurns[sd] else { continue }
        let active = conds.compactMap { (name, st) -> String? in
            let left = turnsLeft(setTurn: st, duration: sideCondDurations[name] ?? 5)
            return left > 0 ? "\"\(name)\": \(left)" : nil
        }.sorted()
        if !active.isEmpty { scParts.append("\"\(sd)\": {\(active.joined(separator: ", "))}") }
    }
    let scJson = scParts.isEmpty ? "" : ", \"sideConditions\": {\(scParts.joined(separator: ", "))}"
    // 設置物 (ステルスロック等) はターンで切れないため、残りターン式の
    // sideConditions とは別に、層数つきでそのまま送る
    var hzParts: [String] = []
    for sd in ["p1", "p2"] {
        guard let hz = battleHazards[sd], !hz.isEmpty else { continue }
        let items = hz.keys.sorted().map { "\"\($0)\": \(hz[$0]!)" }
        hzParts.append("\"\(sd)\": {\(items.joined(separator: ", "))}")
    }
    let hzJson = hzParts.isEmpty ? "" : ", \"hazards\": {\(hzParts.joined(separator: ", "))}"
    let trainer = trainerOpp.isEmpty ? "" : ", \"oppTrainer\": \"\(jsonEscape(trainerOpp))\""
    // 相手のランク/レート (見せ合い後に画像認識側が oppRank /
    // oppRating へ読み取る。記録はトレーナー名と並べてここで行う)
    let rankJson = oppRank.isEmpty ? "" : ", \"oppRank\": \"\(jsonEscape(oppRank))\""
    let ratingJson = oppRating.isEmpty ? "" : ", \"oppRating\": \"\(jsonEscape(oppRating))\""
    // 試合 ID (開始時刻ベース)。UI 側が「イベント列が縮んだ」推測ではなく
    // この値の変化で新しい対戦の開始を確実に検知できるようにするための
    // 材料 (前の対戦の自動コンディションが次の対戦に残る事故の対策)
    let battleJson = battleArchiveId.isEmpty ? "" : ", \"battle\": \"\(battleArchiveId)\""
    let eventsJson = ", \"events\": [\(battleEvents.joined(separator: ", "))]"
    let flagJson = ", \(flagStateFragment())"
    let json = "{\"mine\": [\(mine.joined(separator: ", "))], \"opps\": [\(opps.joined(separator: ", "))]\(team)\(mineTeamJson)\(revJson)\(trainer)\(rankJson)\(ratingJson)\(battleJson)\(eventsJson), \"field\": \(field)\(scJson)\(hzJson)\(flagJson)}"
    if json == lastWritten { return }
    lastWritten = json
    try? json.write(to: outURL, atomically: true, encoding: .utf8)
    noteStateWrite(shape: "battle", json: json, eventsCount: battleEvents.count)
}

func trackFieldEvent(_ line: String) {
    let eff = max(currentTurn, 1)
    if line.hasPrefix("|-weather|") {
        // 上書きされる側を控える (開始直後に天候・地形が上書きされた
        // 場合、先発の特性帰属は上書きされた側に対して行うため)
        let wname = String(line.dropFirst(10))
        if wname != "none", let ui = weatherUiByLogName[wname],
           !logFieldWeather.isEmpty, logFieldWeather != ui {
            prevFieldWeather = logFieldWeather
            prevFieldWeatherSetTurn = fieldWeatherSetTurn
        }
        fieldWeatherSetTurn = line.hasSuffix("|none") ? 0 : eff
    } else if line.hasPrefix("|-fieldstart|move: ") {
        let name = String(line.dropFirst("|-fieldstart|move: ".count))
        if name == "Trick Room" { fieldTrickRoomSetTurn = eff }
        else if name.hasSuffix(" Terrain") {
            let newTerrain = String(name.dropLast(8))
            if !logFieldTerrain.isEmpty, logFieldTerrain != newTerrain {
                prevFieldTerrain = logFieldTerrain
                prevFieldTerrainSetTurn = fieldTerrainSetTurn
            }
            fieldTerrainSetTurn = eff
        }
    } else if line.hasPrefix("|-fieldend|move: ") {
        let name = String(line.dropFirst("|-fieldend|move: ".count))
        if name == "Trick Room" { fieldTrickRoomSetTurn = 0 }
        else if name.hasSuffix(" Terrain") { fieldTerrainSetTurn = 0 }
    } else if line.hasPrefix("|-sidestart|") || line.hasPrefix("|-sideend|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 4, f[3].hasPrefix("move: ") else { return }
        let cond = String(f[3].dropFirst("move: ".count))
        guard sideCondDurations[cond] != nil else { return }
        if line.hasPrefix("|-sidestart|") {
            sideCondSetTurns[f[2], default: [:]][cond] = eff
        } else {
            sideCondSetTurns[f[2]]?[cond] = nil
        }
    }
}

func turnsLeft(setTurn: Int, duration: Int) -> Int {
    if setTurn <= 0 { return 0 }
    return max(0, setTurn + duration - max(currentTurn, 1))
}

func jsonEscape(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }

func applyEvent(_ line: String) {
    trackFieldEvent(line)  // 残りターン管理 (開始ターンの記録)
    // 設置物はここを正本として保持する (state.json の hazards 用)。
    // sidestart/sideend 行が唯一の入力で、保存したプロトコルログを
    // 再生すれば設置状態も再構築できる
    if line.hasPrefix("|-sidestart|") || line.hasPrefix("|-sideend|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, f[3].hasPrefix("move: ") {
            let name = String(f[3].dropFirst("move: ".count))
            if let cap = hazardCaps[name] {
                if line.hasPrefix("|-sidestart|") {
                    battleHazards[f[2], default: [:]][name] = min(cap, (battleHazards[f[2]]?[name] ?? 0) + 1)
                } else {
                    battleHazards[f[2]]?[name] = nil
                }
            }
        }
    }
    if line.hasPrefix("|turn|") {
        if let n = Int(line.dropFirst(6)) { currentTurn = n }
        lastTurnLineAt = sNow()
        segmentFirstMoveAt = nil
    } else if line.hasPrefix("|-weather|") {
        let name = String(line.dropFirst(10))
        if name == "none" { logFieldWeather = "" }
        else if let ui = weatherUiByLogName[name] { logFieldWeather = ui }
    } else if line.hasPrefix("|-fieldstart|move: ") {
        let name = String(line.dropFirst(19))
        if name == "Trick Room" { logTrickRoom = true }
        else if name.hasSuffix(" Terrain") { logFieldTerrain = String(name.dropLast(8)) }
    } else if line.hasPrefix("|-fieldend|move: ") {
        let name = String(line.dropFirst(17))
        if name == "Trick Room" { logTrickRoom = false }
        else if name.hasSuffix(" Terrain") { logFieldTerrain = "" }
    } else if line.hasPrefix("|-status|") || line.hasPrefix("|-curestatus|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.status = line.hasPrefix("|-status|") ? f[3] : ""
        }
    } else if line.hasPrefix("|-boost|") || line.hasPrefix("|-unboost|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 5, let ss = parseSlotSpecies(f[2]), let n = Int(f[4]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            let delta = line.hasPrefix("|-boost|") ? n : -n
            let cur = monStates[key]?.boosts[f[3]] ?? 0
            monStates[key]?.boosts[f[3]] = max(-6, min(6, cur + delta))
        }
    } else if line.hasPrefix("|-damage|") || line.hasPrefix("|-heal|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            let hp = f[3].split(separator: "/")
            if hp.count == 2, let a = Int(hp[0].trimmingCharacters(in: .whitespaces)),
               let b = Int(hp[1].trimmingCharacters(in: .whitespaces)) {
                monStates[key]?.hpPercent = b > 0 ? Int((Double(a) / Double(b) * 100).rounded()) : a
                monStates[key]?.hpText = f[3]
            }
            // オボンのみ回復行は「消費した」ことも含む (再生で復元できるように)
            if line.hasPrefix("|-heal|"), f.count >= 5, f[4].contains("item: Sitrus Berry") {
                itemLostActive.insert(key)
            }
        }
    } else if line.hasPrefix("|faint|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.hpPercent = 0
            subActive.remove(key)
            faintedSpecies.insert(key)
        }
    } else if line.hasPrefix("|switch|") || line.hasPrefix("|drag|") {
        lastSwitchEmitSeq = actionSeq
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            // その枠にいた前の種族は交代でランク変化・かるわざが解除される
            if let prev = eventSlotSpecies[ss.slot], prev != ss.speciesEn {
                let pk = "\(ss.side):\(prev)"
                monStates[pk]?.boosts = [:]
                unburdenActive.remove(pk)
                subActive.remove(pk)
            }
            eventSlotSpecies[ss.slot] = ss.speciesEn
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.boosts = [:]  // 入場時はランク変化なし
            faintedSpecies.remove(key)   // 交代で戻れば、ひんし済み扱いは解ける
        }
    } else if line.hasPrefix("|detailschange|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.megaSpecies = f[3].split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? f[3]
        }
    } else if line.hasPrefix("|-ability|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if ss.side == "p2" { revealedAbilities[ss.speciesEn] = abilityJa2En.first { $0.value == f[3] }?.key ?? f[3] }
            // かるわざ の発動行は「持ち物を失った」ことの帰結として出す
            // 行なので、再生時もこの行から両方の状態を復元できる
            if f[3] == "Unburden" { unburdenActive.insert(key); itemLostActive.insert(key) }
        }
    } else if line.hasPrefix("|-item|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == "p2" {
            revealedItems[ss.speciesEn] = itemJa2En.first { $0.value == f[3] }?.key ?? f[3]
        }
    } else if line.hasPrefix("|-start|") || line.hasPrefix("|-end|") {
        // 身代わりの有無を追跡する (出現文の再読で開始行を二重に出さないため)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), f[3] == "Substitute" {
            let key = "\(ss.side):\(ss.speciesEn)"
            if line.hasPrefix("|-start|") { subActive.insert(key) } else { subActive.remove(key) }
        }
    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq
        if segmentFirstMoveAt == nil { segmentFirstMoveAt = sNow() }
        // まもるの使用ターンを控える (activate 行の同ターン照合用)
        let mf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // 枠ごとの直近の技も控える (反動行の処理が次の技の告知より
        // 遅れても帰属が外れないように。実例: 2026-11-23
        // battle_20261123_062508、ブレイブバードの反動)
        if mf.count >= 4 { lastMoveBySlot[mf[2]] = (move: mf[3], turn: currentTurn) }
        if mf.count >= 4 && (mf[3] == "Protect" || mf[3] == "Detect") {
            let pslot = mf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn; protectMoveName[pslot] = mf[3] }
        }
        // 相手の技は判明情報として記録する (行は英語名のため和名に戻す)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == "p2" {
            let mvJa = moveJa2En.first { $0.value == f[3] }?.key ?? f[3]
            if !(revealedMoves[ss.speciesEn]?.contains(mvJa) ?? false) {
                revealedMoves[ss.speciesEn, default: []].append(mvJa)
            }
        }
    } else if line.hasPrefix("|-enditem|") {
        // 持ち物の消費・喪失 (画面に文が出ない推論イベントのため、ログには
        // 残さず applyEvent への直接適用だけで状態に反映する経路)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            itemLostActive.insert(key)
            let abilityJa = ss.side == "p1" ? (teamEntries[ss.speciesEn]?["ability"] as? String) : revealedAbilities[ss.speciesEn]
            if abilityJa == "かるわざ" { unburdenActive.insert(key) }
        }
    }
}

func parseSlotSpecies(_ s: String) -> (slot: String, side: String, speciesEn: String)? {
    let parts = s.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    let slot = parts[0].trimmingCharacters(in: .whitespaces)
    let sp = parts[1].trimmingCharacters(in: .whitespaces)
    guard slot.hasPrefix("p1") || slot.hasPrefix("p2"), !sp.isEmpty else { return nil }
    return (slot, String(slot.prefix(2)), sp)
}
// ---------- driver ----------
func E(_ ja: String, _ en: String) -> SpeciesEntry { SpeciesEntry(ja: ja, en: en, id: en.lowercased(), norm: normalize(ja)) }
func resetAll() {
    battleLog = []; monStates = [:]; lastSlots = [:]; actionSeq = 0; currentTurn = 1
    lastSwitchIn = [:]; fieldSeen = ["p1": [], "p2": []]; intimidateDone = [:]; fieldAbilityDone = [:]
    lastBoostApply = [:]; lastEffectAt = [:]; protectMoveTurn = [:]; protectMoveName = [:]; effectBySeq = [:]; damagedBySeq = [:]; lastAbilityEmit = [:]; lastItemEmit = [:]
    lastMoveSigAt = [:]; lastMoveSigSeq = [:]; prevBoostFragment = nil; lastSingleActAt = [:]; lastSideCondAt = [:]; lastCritAt = [:]
    critEventMarks = [:]
    pendingAbilityReveal = [:]
    pendingDamagePct = [:]; pendingDamageCount = [:]; pendingDamageSince = [:]; heldLine = [:]
    lastDamageSeq = [:]; lastDamageTurn = [:]; lastDamageDir = [:]; lastDamageTime = [:]
    suspectJump = [:]; firstEntryPlateHP = [:]; sitrusWatch = [:]; lastMoveEmitSeq = -1; lastSwitchEmitSeq = -1
    fieldSetByMoveTurn = -1; switchInTurn = [:]
    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false
    battleAdmittedSpecies = []; offTeamPlateStreak = [:]; battleMaxOverride = [:]; battleMaxCandidate = [:]; battleMaxRevertCount = [:]; pendingReturnCount = [:]; barVetoHold = [:]; faintReviveCount = [:]; faintReviveSince = [:]
    battleMineTeam = []; headerMineTeam = []; minePreviewSeenCopy = []; minePreviewAppliedCopy = []; minePreviewUpdatedAt = nil; lastBattleStartedAt = nil; minePreviewTeam = []; minePreviewDetails = []
    pendingSwitchCandidates = [:]
    sendOutTextSeen = [:]
    heldTerrainReplace = nil; pivotReturnAt = [:]
    wishSetTurn = [:]
    pendingFaints = []; faintedSlots = [:]; pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]
    slotSwapPending = [:]
    stateSnapRecords = []; stateSnapLeadIn = []; stateSnapKey = ""; stateSnapLastShape = ""; stateSnapLastEvents = -1; stateSnapFirstBattlePending = true; stateSnapFlushCount = 0
    faintedSpecies = []; heldEntryBoosts = []
    grassyHealTurn = [:]
    logTrickRoom = false
    pendingUnburden = []
    unburdenActive = []
    boostPathAt = [:]
    eventSlotSpecies = [:]
    lastWritten = ""
    fieldWeatherSetTurn = 0; fieldTerrainSetTurn = 0; prevFieldWeather = ""; prevFieldWeatherSetTurn = 0; prevFieldTerrain = ""; prevFieldTerrainSetTurn = 0; fieldTrickRoomSetTurn = 0; sideCondSetTurns = [:]
    itemLostActive = []
    lastEmittedPct = [:]; lastDamageLabel = ""; lastPendingLabel = "" 
    lastDamageAt = Date.distantPast; lastDamageLabel = ""; lastPendingLabel = ""
    lastMoveLabel = ""; lastMoveName = ""; lastMoveMsgAt = Date.distantPast; lastMoveSeq = -1; lastMissKey = ""; lastMoveBySlot = [:]
    pendingStatusFrom = [:]; pendingMegaStone = [:]; pendingMegaSpecies = [:]
    battleHazards = [:]; pendingHazard = nil; pendingRemoval = nil
    emittedSwitchKeys = []; heldBoostLines = [:]; recentAtkDrops = [:]
    revealedMoves = [:]; revealedItems = [:]; revealedAbilities = [:]
    logFieldWeather = ""; logFieldTerrain = ""; winLogged = false; logStarted = true; headerPrintReady = false; headerLineCount = 0; displayPrintedCount = 0
    winLineEmitted = false; pendingHealFrom = [:]; segmentFirstMoveAt = nil; lastTurnLineAt = Date.distantPast
    movesSinceTurnLine = []; roundEventSeen = false; suppressNextDetectorTurn = false
    enteredThisSegment = []
    defaultAttribCount = [:]; debugCaptureCalls = []
    trainerOpp = ""; oppRank = ""; oppRating = ""
    headerOppTeam = []; headerMismatchFired = []
    forfeitName = nil; oppTeamSeen = []; teamEntries = [:]
    subActive = []; boostTouchedStats = []; battleArchiveId = ""
}
speciesDict = [
    E("カメックス", "Blastoise"), E("サーナイト", "Gardevoir"), E("オオニューラ", "Sneasler"),
    E("イエッサン", "Indeedee"), E("イエッサン", "Indeedee-F"), E("カイリュー", "Dragonite"),
    E("グレンアルマ", "Armarouge"), E("エルフーン", "Whimsicott"),
    E("ドリュウズ", "Excadrill"), E("サーフゴー", "Gholdengo"), E("ゴリランダー", "Rillaboom"),
    E("ゲンガー", "Gengar"), E("ズルズキン", "Scrafty"), E("ガブリアス", "Garchomp"),
    E("メガガブリアス", "Garchomp-Mega"),
    E("リザードン", "Charizard"), E("メガリザードンX", "Charizard-Mega-X"), E("メガリザードンY", "Charizard-Mega-Y"),
    E("キュウコン", "Ninetales"), E("キュウコン", "Ninetales-Alola"), E("ロトム", "Rotom"),
    E("ミロカロス", "Milotic"), E("コータス", "Torkoal"), E("スターミー", "Starmie"), E("ジャラランガ", "Kommo-o"), E("クレッフィ", "Klefki"), E("エーフィ", "Espeon"),
    E("ムクホーク", "Staraptor"), E("メガムクホーク", "Staraptor-Mega"),
    E("ブリジュラス", "Archaludon"),
    E("ニョロトノ", "Politoed"), E("ハリーマン", "Overqwil"), E("ピクシー", "Clefable"),
    E("ハッサム", "Scizor"),
    E("バクフーン", "Typhlosion"), E("バクフーン", "Typhlosion-Hisui"),
    E("ユキメノコ", "Froslass"),
]
speciesAbilityMap = [
    "Scrafty": ["Shed Skin", "Moxie", "Intimidate"],
    "Garchomp": ["Sand Veil", "Rough Skin"],
    "Indeedee-F": ["Synchronize", "Psychic Surge"],
    "Rillaboom": ["Overgrow", "Grassy Surge"],
    "Gardevoir": ["Synchronize", "Trace"],
    "Typhlosion": ["Blaze", "Flash Fire"],
    "Typhlosion-Hisui": ["Blaze", "Frisk"],
    "Ninetales": ["Flash Fire", "Drought"],
    "Ninetales-Alola": ["Snow Cloak", "Snow Warning"],
    "Milotic": ["Marvel Scale", "Competitive", "Cute Charm"],
    "Torkoal": ["White Smoke", "Drought", "Shell Armor"],
    "Staraptor": ["Intimidate", "Reckless"],
    "Farigiraf": ["Cud Chew", "Armor Tail", "Sap Sipper"],
]
var pvSpeciesTypes: [String: [String]] = [:]
for (ja, en) in [("じしん", "Earthquake"), ("まもる", "Protect"), ("アーマーキャノン", "Armor Cannon"), ("ハイパーボイス", "Hyper Voice"), ("シャドーボール", "Shadow Ball"), ("てだすけ", "Helping Hand"), ("サイコキネシス", "Psychic"), ("はかいこうせん", "Hyper Beam"), ("だくりゅう", "Muddy Water"), ("たくわえる", "Stockpile"), ("ドレインキッス", "Draining Kiss"), ("つぼをつく", "Acupressure")] {
    moveNameOrig[normalize(ja)] = ja; moveJa2En[ja] = en
}
for (ja, en) in [("いのちのたま", "Life Orb"), ("だっしゅつボタン", "Eject Button"), ("きあいのタスキ", "Focus Sash"), ("ガブリアスナイトZ", "Garchompite Z"), ("リザードナイトX", "Charizardite X"), ("リザードナイトY", "Charizardite Y"), ("サーナイトナイト", "Gardevoirite"), ("ムクホークナイト", "Staraptite"), ("せんせいのツメ", "Quick Claw"), ("こだわりスカーフ", "Choice Scarf"), ("オッカのみ", "Occa Berry"), ("オボンのみ", "Sitrus Berry"), ("たべのこし", "Leftovers"), ("ふうせん", "Air Balloon"), ("サイコシード", "Psychic Seed"), ("グラスシード", "Grassy Seed"), ("ゴツゴツメット", "Rocky Helmet")] {
    itemDict[normalize(ja)] = ja; itemJa2En[ja] = en
}
abilityJa2En = ["いかく": "Intimidate"]

// T1: 相性文の OCR 崩れ (バッグン)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 100)
let t1 = translateBattleMessage("あいて相手のドリュウズに効果はバッグンだ！")
check("T1 consumed", t1)
check("T1 supereffective", battleLog.contains("|-supereffective|p2a: Excadrill"))

// T2: 砂あらしチップ告知 (襲う)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Blastoise", hpPercent: 100)
let t2 = translateBattleMessage("すな砂あらしがカメックスを襲う！")
check("T2 consumed", t2)
check("T2 pendingStatusFrom", pendingStatusFrom["p1:Blastoise"]?.0 == "sandstorm")

// T3: いのちのたま反動の OCR 崩れ
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gholdengo", hpPercent: 100)
lastMoveLabel = "p2a: Gholdengo"; lastMoveMsgAt = Date()
let t3 = translateBattleMessage("あいて相手のサーフゴーはいのち命が少し削られた！")
check("T3 consumed", t3)
check("T3 item line", battleLog.contains("|-item|p2a: Gholdengo|Life Orb"))
check("T3 revealed", revealedItems["Gholdengo"] == "いのちのたま")

// T4: だっしゅつボタン
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
let t4 = translateBattleMessage("あいて相手のゴリランダーはもどだっしゅつボタンで戻っていく！")
check("T4 consumed", t4)
check("T4 item line", battleLog.contains("|-item|p2a: Rillaboom|Eject Button"))

// T5: まもる成功の OCR 崩れ
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
emitLog("|move|p2a: Gengar|Protect")
let t5 = translateBattleMessage("あいて相手のゲンガーはたいせいまも体勢に守りの入った！")
check("T5 consumed", t5)
check("T5 activate", battleLog.contains("|-activate|p2a: Gengar|move: Protect"))

// T6: グラスフィールド開始の OCR 崩れ
resetAll()
let t6 = checkFieldText(text: "足下に草がおいしげった！")
check("T6 consumed", t6)
check("T6 terrain", logFieldTerrain == "Grassy")

// T7: いかく複合文 (2 体同時 + anchoring + 特性行)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Scrafty", hpPercent: 100)
emittedSwitchKeys = ["p1:Gardevoir", "p1:Indeedee-F", "p2:Gengar", "p2:Scrafty"]
fieldSeen = ["p1": ["Gardevoir", "Indeedee-F"], "p2": ["Gengar", "Scrafty"]]
lastSwitchIn["p2:Scrafty"] = ("p2b", Date())
teamEntries = ["Indeedee-F": [:], "Gardevoir": [:]]
let t7 = translateBattleMessage("サーナイトとイエッサンのこうげきが下がった！")
check("T7 consumed", t7)
check("T7 bracket", battleLog.contains("|-ability|p2b: Scrafty|Intimidate"))
check("T7 gardevoir drop", battleLog.contains("|-unboost|p1a: Gardevoir|atk|1"))
check("T7 indeedee drop", battleLog.contains("|-unboost|p1b: Indeedee-F|atk|1"))
check("T7 states", (monStates["p1:Gardevoir"]?.boosts["atk"] ?? 0) == -1 && (monStates["p1:Indeedee-F"]?.boosts["atk"] ?? 0) == -1)
check("T7 no phantom", monStates["p1:Indeedee"] == nil)
// T7b: 同じ文の再読では二重適用しない (行も増えない)
let beforeCount = battleLog.count
_ = translateBattleMessage("サーナイトとイエッサンのこうげさ攻撃が下がった！")
check("T7b no double", battleLog.count == beforeCount && (monStates["p1:Gardevoir"]?.boosts["atk"] ?? 0) == -1 && (monStates["p1:Indeedee-F"]?.boosts["atk"] ?? 0) == -1)
check("T7b net catches", isBoostShapedText("サーナイトとイエッサンのこうげさ攻撃が下がった！"))
check("T7c net rejects", !isBoostShapedText("相手のポケモンは眠ってしまった！"))

// T8: 交代行より先のランク変化は保留され、交代行の後に出る
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
let t8 = translateBattleMessage("相手のオオニューラのとくぼうが上がった！")
check("T8 consumed", t8)
check("T8 held", !battleLog.contains("|-boost|p2a: Sneasler|spd|1") && (heldBoostLines["p2:Sneasler"]?.count ?? 0) == 1)
check("T8 state applied", (monStates["p2:Sneasler"]?.boosts["spd"] ?? 0) == 1)
recordSwitchIn(side: "p2", slot: "p2a", speciesEn: "Sneasler")
check("T8 flushed", battleLog.contains("|-boost|p2a: Sneasler|spd|1"))

// T9: いかく遡及帰属 (適用時に繰り出し未記録 -> 記録時に特性行)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
emittedSwitchKeys = ["p1:Gardevoir"]
fieldSeen = ["p1": ["Gardevoir"], "p2": ["Gengar", "Dragonite"]]
let t9 = translateBattleMessage("サーナイトのこうげきが下がった！")
check("T9 drop applied", t9 && battleLog.contains("|-unboost|p1a: Gardevoir|atk|1"))
check("T9 no bracket yet", !battleLog.contains { $0.contains("Intimidate") })
recordSwitchIn(side: "p2", slot: "p2b", speciesEn: "Scrafty")
check("T9 retro bracket", battleLog.contains("|-ability|p2b: Scrafty|Intimidate"))

// T10: メガ完了の合成 (反応のみ拾えた場合、技の直前に補う)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
emittedSwitchKeys = ["p2:Garchomp"]
pendingMegaSpecies["p2"] = "Garchomp"
pendingMegaStone["p2"] = "ガブリアスナイトZ"
let t10 = translateBattleMessage("相手のガブリアスのじしん！")
check("T10 consumed", t10)
if let di = battleLog.firstIndex(of: "|detailschange|p2a: Garchomp|Garchomp-Mega"), let mi = battleLog.firstIndex(of: "|move|p2a: Garchomp|Earthquake") {
    check("T10 order", di < mi)
} else { check("T10 order", false) }
check("T10 mega state", monStates["p2:Garchomp"]?.megaSpecies == "Garchomp-Mega")
check("T10 pending cleared", pendingMegaSpecies["p2"] == nil)

// T11: メガ完了文の通常経路
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
let t11 = translateBattleMessage("相手のガブリアスはメガガブリアスにメガシンカした！")
check("T11 consumed", t11)
check("T11 detailschange", battleLog.filter { $0.hasPrefix("|detailschange|") }.count == 1 && monStates["p2:Garchomp"]?.megaSpecies == "Garchomp-Mega")

// T12: メガ X/Y のストーン字による判別
resetAll()
synthesizeMegaIfPending(side: "p2", speciesEn: "Charizard")
check("T12 no pending no-op", battleLog.isEmpty)
pendingMegaSpecies["p2"] = "Charizard"
pendingMegaStone["p2"] = "リザードナイトY"
synthesizeMegaIfPending(side: "p2", speciesEn: "Charizard")
check("T12 Y chosen", monStates["p2:Charizard"]?.megaSpecies == "Charizard-Mega-Y")

// T13: せんせいのツメの発動
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
let t13 = translateBattleMessage("あいて相手の相手のキュウコンはせんせいのツメでこうどう行動がはやくなった！")
check("T13 consumed", t13)
check("T13 item line", battleLog.contains("|-item|p2a: Ninetales|Quick Claw"))
check("T13 revealed", revealedItems["Ninetales"] == "せんせいのツメ")

// T14: 道具を手に入れた (トリックで移った道具の判明)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
let t14 = translateBattleMessage("イエッサンはこだわりスカーフを手に入れた！")
check("T14 consumed", t14)
check("T14 item line", battleLog.contains("|-item|p1a: Indeedee-F|Choice Scarf"))

// T15: トリックの交換文 (道具->道負 の OCR 崩れ) は消費する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Rotom", hpPercent: 100)
let t15 = translateBattleMessage("あいて相手のロトムはどうぐおたがいの道負を入れ替えた！")
check("T15 consumed", t15)

// T16: 引っ込めた の OCR 崩れ (引つこめた) は消費する
resetAll()
let t16 = translateBattleMessage("Onyはコリランダーを引つこめた！")
check("T16 consumed", t16)

// T17: 守られている文の断片 (種族名欠落) は消費し、フィールドを裏付ける
resetAll()
let t17 = translateBattleMessage("クスはサイコフィールドに守られている！")
check("T17 consumed", t17)
check("T17 terrain", logFieldTerrain == "Psychic")

// T18: 技告知文の断片ネット
check("T18 fragment caught", isMoveFragmentText("イトの【ーポイス！"))
check("T18 status text rejected", !isMoveFragmentText("相手のポケモンは眠ってしまった！"))
check("T18 full move rejected", !isMoveFragmentText("相手のガブリアスのじしん！"))


// T19: 急所文の OCR 崩れ (還所) を拾い、文中の種族名で帰属する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Starmie", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
lastDamageLabel = "p2b: Gengar"
lastDamageAt = Date()
let t19 = translateBattleMessage("あいて相手のスターミーの還所に当たった！")
check("T19 consumed", t19)
check("T19 crit on named species", battleLog.contains("|-crit|p2a: Starmie"))

// T20: まひで動けない
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
let t20 = translateBattleMessage("イエツサンはからだうご体がしびれて動けない！")
check("T20 consumed", t20)
check("T20 cant line", battleLog.contains("|-cant|p1b: Indeedee-F|par"))


// T21: ねむりで動けない
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
let t21 = translateBattleMessage("ガブリアスはぐっすり眠っている！")
check("T21 consumed", t21)
check("T21 cant line", battleLog.contains("|-cant|p1a: Garchomp|slp"))


// T22: グラッシーフィールド回復文の OCR 崩れは消費する
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Chandelure", hpPercent: 80)
let t22 = translateBattleMessage("あいて相手のシャンデラのかいふく袱力か回復した！")
check("T22 consumed", t22)

// T23: アリーバスイッチの結果文は消費する
resetAll()
let t23 = translateBattleMessage("相手のシャンテラとミカルゲは場所を入れ替えた！")
check("T23 consumed", t23)

// T24: 急所文の断片 (〜に当たった！) は直近の被弾枠に付ける
resetAll()
lastDamageLabel = "p2b: Spiritomb"
lastDamageAt = Date()
let t24 = translateBattleMessage("慧帯に当たった！")
check("T24 consumed", t24)
check("T24 crit line", battleLog.contains("|-crit|p2b: Spiritomb"))

// T25: 場に片側だけいる種族は前置きより場の側を優先する
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
let t25 = translateBattleMessage("あいて相手のグレンアルマのシャドーボール！")
check("T25 consumed", t25)
check("T25 move on p1", battleLog.contains("|move|p1a: Armarouge|Shadow Ball"))
check("T25 no p2 move", !battleLog.contains("|move|p2a: Armarouge|Shadow Ball"))

// T26: 先発登録済みの「ゆけっ」文は消費のみ (枠の誤登録をしない)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
let t26 = translateBattleMessage("ゆけっ！オオニューラ！")
check("T26 consumed", t26)
check("T26 no switch emitted", !battleLog.contains { $0.contains("|switch|") && $0.contains("Sneasler") })

// T26b: 対戦開始時の「ゆけっ」は従来通り先発を登録する
resetAll()
let t26b = translateBattleMessage("ゆけっ！ガブリアス！イエッサン！")
check("T26b consumed", t26b)
check("T26b lead switch", battleLog.contains { $0.contains("|switch|p1a: Garchomp") })

// T27: 同じターンの同じ技は 6 秒を超えても二重に出ない。ターンが変われば出る
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
_ = translateBattleMessage("あいて相手のゲンガーのシャドーボール！")
let movesAfterFirst = battleLog.filter { $0.contains("|move|") }.count
lastMoveSigAt["p2a|Shadow Ball"] = Date().addingTimeInterval(-10)
_ = translateBattleMessage("あいて相手のゲンガーのシャドーボール！")
let movesAfterSecond = battleLog.filter { $0.contains("|move|") }.count
currentTurn = 2
_ = translateBattleMessage("あいて相手のゲンガーのシャドーボール！")
let movesAfterThird = battleLog.filter { $0.contains("|move|") }.count
check("T27 first emitted", movesAfterFirst == 1)
check("T27 same-turn suppressed", movesAfterSecond == 1)
check("T27 next turn emitted", movesAfterThird == 2)


// T28: 引っごめた (濁点崩れ) も消費する
resetAll()
check("T28 consumed", translateBattleMessage("Esragivはゴリランダーを引っごめた！"))

// T29: サイコフィールド開始文の崩れ (足下・不思議が落ちても拾う)
resetAll()
check("T29 consumed", translateBattleMessage("下か不態議な感じになった！"))
check("T29 terrain", logFieldTerrain == "Psychic")

// T30: グラッシーフィールド終了文 (草が消え去った)
resetAll()
logFieldTerrain = "Grassy"
check("T30 consumed", translateBattleMessage("あしもと足下の草が消え去った！"))
check("T30 terrain cleared", logFieldTerrain == "")

// T31: 防が下がった (2 文字目落ち) のランク変化
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Kommo-o", hpPercent: 100)
_ = translateBattleMessage("あいて相手のジャラランガの相手の防が下がった！")
check("T31 def drop", monStates["p2:Kommo-o"]?.boosts["def"] == -1)
check("T31 net catches", isBoostShapedText("あいて相手のジャラランガの相手の防が下がった！"))

// T32: まもる成功行は 6 秒以内の再読で二重に出ない
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
emitLog("|move|p1b: Armarouge|Protect")
_ = translateBattleMessage("グレンアルマは攻撃から身を守つた！")
_ = translateBattleMessage("グレンアルマは攻撃から身を守つた！")
check("T32 protect once", battleLog.filter { $0.contains("-activate") && $0.contains("Protect") }.count == 1)

// T33: 遅延ひんしの再検証 (回復していたら捨てる、本当に 0 なら出す)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 77)
monStates["p1:Indeedee-F"] = MonState(); monStates["p1:Indeedee-F"]!.hpPercent = 77
deferFaint(slot: "p1a", speciesEn: "Indeedee-F")
emitPendingFaints()
check("T33 spurious faint dropped", !battleLog.contains { $0.contains("|faint|") })
monStates["p1:Indeedee-F"]!.hpPercent = 0
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 0)
deferFaint(slot: "p1a", speciesEn: "Indeedee-F")
emitPendingFaints()
check("T33 real faint emitted", battleLog.contains("|faint|p1a: Indeedee-F"))
check("T33 faintedSlots marked", faintedSlots["p1a"] == "Indeedee-F")

// T34: 0% で登場したら ひんし行を補う
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
processPlates(["oppB": SlotState(speciesEn: "Kleavor", hpPercent: 0)])
processPlates(["oppB": SlotState(speciesEn: "Kleavor", hpPercent: 0)])
check("T34 switch emitted", battleLog.contains { $0.contains("|switch|p2b: Kleavor") })
emitPendingFaints()
check("T34 faint emitted", battleLog.contains("|faint|p2b: Kleavor"))

// T35: ひんし確定済みの枠は交代までプレート読みを無視する
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 0)
monStates["p1:Armarouge"] = MonState(); monStates["p1:Armarouge"]!.hpPercent = 0
faintedSlots["p1b"] = "Armarouge"
processPlates(["mineB": SlotState(speciesEn: "Armarouge", hpPercent: 100)])
check("T35 no heal line", !battleLog.contains { $0.contains("-heal") })
processPlates(["mineB": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
processPlates(["mineB": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
check("T35 replacement switch", battleLog.contains { $0.contains("|switch|p1b: Sneasler") })
check("T35 faint mark cleared", faintedSlots["p1b"] == nil)

// T36: 交代要員選択中は生きている枠の交代確定を抑止する
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 0)
monStates["p1:Armarouge"] = MonState(); monStates["p1:Armarouge"]!.hpPercent = 0
faintedSlots["p1b"] = "Armarouge"
fieldSeen["p1"] = ["Gardevoir", "Armarouge"]
processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
check("T36 bogus switch suppressed", !battleLog.contains { $0.contains("|switch|") })

// T37: 段階アニメーションの尾 (同じ行動・同じ向き・3% 以下) は行を出さない
resetAll()
actionSeq = 5; currentTurn = 3
lastEmittedPct["mineA"] = 100
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 21, hpText: "30/145", force: true)
let dmgAfterBig = battleLog.filter { $0.contains("-damage") }.count
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 21, toPct: 19, hpText: "27/145", force: true)
let dmgAfterTail = battleLog.filter { $0.contains("-damage") }.count
let lpAfterTail = lastEmittedPct["mineA"] ?? -1
actionSeq = 6
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 19, toPct: 10, hpText: "15/145", force: true)
let dmgAfterNext = battleLog.filter { $0.contains("-damage") }.count
check("T37 big hit emitted", dmgAfterBig == 1)
check("T37 tail suppressed", dmgAfterTail == 1 && lpAfterTail == 19)
check("T37 next action emitted", dmgAfterNext == 2)


resetAll()
actionSeq = 5; currentTurn = 3
lastEmittedPct["mineA"] = 100
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 21, hpText: "30/145", force: true)
out("after1 log=\(battleLog) seq=\(lastDamageSeq) turn=\(lastDamageTurn) dir=\(lastDamageDir) lp=\(lastEmittedPct)")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 21, toPct: 19, hpText: "27/145", force: true)
out("after2 log=\(battleLog) lp=\(lastEmittedPct)")

resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
_ = translateBattleMessage("グレンアルマは攻撃から身を守った！")
out("protect1 log=\(battleLog) single=\(lastSingleActAt)")
_ = translateBattleMessage("グレンアルマは攻撃から身を守った！")
out("protect2 log=\(battleLog)")


// T38: プレート値の安定待ち (現れて 1.2 秒経つまで確定しない)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 100
lastEmittedPct["mineA"] = 100
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50)])
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50)])
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50)])
processPlates(["mineA": SlotState(speciesEn: "Gardevoir", hpPercent: 50)])
check("T38 not settled yet", !battleLog.contains { $0.contains("-damage") })
flushPendingDamage()
check("T38 flush gated", !battleLog.contains { $0.contains("-damage") })
flushPendingDamage(force: true)
check("T38 force flush emits", battleLog.contains { $0.contains("-damage|p1a: Gardevoir") })

// T39: きあいのタスキ発動行は二重に出ない
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
_ = translateBattleMessage("グレンアルマはきあいのタスキでもちこたえた！")
_ = translateBattleMessage("グレンアルマはきあいのタスキでもちこたえた！")
check("T39 sash once", battleLog.filter { $0.contains("-activate") && $0.contains("Focus Sash") }.count == 1)

// T40: いのちのたま判明は直近の使用者と一致するときだけ
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
lastMoveLabel = "p1a: Gardevoir"; lastMoveMsgAt = Date()
let t40 = translateBattleMessage("あいて相手のゲンガーはいのちのたまの効果で命が少し削られた！")
check("T40 consumed", t40)
check("T40 no reveal for non-mover", revealedItems["Gengar"] == nil && !battleLog.contains { $0.contains("-item|p2a: Gengar") })

// T41: タイプ軽減きのみの発動文は判明として処理する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Klefki", hpPercent: 100)
let t41 = translateBattleMessage("ぁいて相手の相手のクレッフィへのダメージをオッカのみが弱めた！")
check("T41 consumed", t41)
check("T41 revealed", revealedItems["Klefki"] == "オッカのみ")

// T42: フィールド特性の帰属は 30 秒窓で拾う (文とプレート確定の遅延対策)
resetAll()
lastSwitchIn["p2:Indeedee-F"] = (slot: "p2a", at: Date().addingTimeInterval(-20))
speciesAbilityMap["Indeedee-F"] = ["Synchronize", "Psychic Surge"]
logFieldTerrain = "Psychic"; fieldTerrainSetAt = Date().addingTimeInterval(-20)
attributeFieldAbilities()
check("T42 ability bracket", battleLog.contains("|-ability|p2a: Indeedee-F|Psychic Surge"))


// T43: オボンのみ回復 (50% 以下から +25%) は [from] と判明が付く
resetAll()
actionSeq = 7; currentTurn = 2
lastEmittedPct["oppA"] = 60
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 40, toPct: 65, hpText: "65/100", force: true)
check("T43 sitrus from", battleLog.contains("|-heal|p2a: Gengar|65/100|[from] item: Sitrus Berry"))
check("T43 sitrus item line", battleLog.contains("|-item|p2a: Gengar|Sitrus Berry"))
check("T43 sitrus revealed", revealedItems["Gengar"] == "オボンのみ")

// T44: たべのこし回復 (+6%、フィールドなし)
resetAll()
actionSeq = 7; currentTurn = 2
lastEmittedPct["oppA"] = 50
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 50, toPct: 56, hpText: "56/100", force: true)
check("T44 leftovers from", battleLog.contains("|-heal|p2a: Gengar|56/100|[from] item: Leftovers"))
check("T44 leftovers revealed", revealedItems["Gengar"] == "たべのこし")

// T45: グラッシーフィールド中は 1 回目がフィールド、2 回目が たべのこし
resetAll()
actionSeq = 7; currentTurn = 2
logFieldTerrain = "Grassy"
lastEmittedPct["oppA"] = 50
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 50, toPct: 56, hpText: "56/100", force: true)
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 56, toPct: 62, hpText: "62/100", force: true)
check("T45 grassy first", battleLog.contains("|-heal|p2a: Gengar|56/100|[from] Grassy Terrain"))
check("T45 leftovers second", battleLog.contains("|-heal|p2a: Gengar|62/100|[from] item: Leftovers"))

// T46: 別の持ち物が判明済みなら帰属しない。発生源を特定できない
// 回復は行自体を出さない方針 (T106a) になったため、帰属以前に
// 行が出ないこともあわせて確認する
resetAll()
actionSeq = 7; currentTurn = 2
revealedItems["Gengar"] = "こだわりスカーフ"
lastEmittedPct["oppA"] = 60
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 40, toPct: 65, hpText: "65/100", force: true)
check("T46 no attribution", !battleLog.contains { $0.contains("[from] item: Sitrus") } && !battleLog.contains("|-heal|p2a: Gengar|65/100"))


// T47: 特防/特攻の文で 防/攻 まで落ちない (1 字落ちフォールバックの誤爆防止)
resetAll()
monStates["p1:Indeedee-F"] = MonState()
checkBoostText(text: "イエッサンの特防が下がった！", side: "p1", speciesEn: "Indeedee-F", slot: "p1b")
check("T47 spd only", monStates["p1:Indeedee-F"]?.boosts["spd"] == -1 && monStates["p1:Indeedee-F"]?.boosts["def"] == nil)
resetAll()
monStates["p1:Indeedee-F"] = MonState()
checkBoostText(text: "イエッサンの特攻が下がった！", side: "p1", speciesEn: "Indeedee-F", slot: "p1b")
check("T47 spa only", monStates["p1:Indeedee-F"]?.boosts["spa"] == -1 && monStates["p1:Indeedee-F"]?.boosts["atk"] == nil)
resetAll()
monStates["p2:Clang"] = MonState()
checkBoostText(text: "防が下がった！", side: "p2", speciesEn: "Clang", slot: "p2a")
check("T47 garble def still works", monStates["p2:Clang"]?.boosts["def"] == -1)

// T48: 急所の崩れ「慧所にたった！」を拾う
resetAll()
lastDamageLabel = "p2b: Sylveon"; lastDamageAt = Date()
check("T48 crit garble consumed", translateBattleMessage("慧所にたった！") == true)
check("T48 crit emitted", battleLog.contains("|-crit|p2b: Sylveon"))

// T49: あくびの眠気文を消費する
resetAll()
check("T49 yawn consumed", translateBattleMessage("イエッサンのねわけ眠気を誘った！") == true)

// T50: トリックルームの開始/終了
resetAll()
check("T50 trickroom start", checkFieldText(text: "あいて相手のリキキリンは時空をゆがめた！") == true && battleLog.contains("|-fieldstart|move: Trick Room"))
check("T50 trickroom end", checkFieldText(text: "時空のゆがみが元に戻った！") == true && battleLog.contains("|-fieldend|move: Trick Room"))

// T51: 保留したランク変化行は、出す時点で正しい枠が付く
resetAll()
monStates["p1:Sneasler"] = MonState()
applyBoost(key: "p1:Sneasler", slot: "p1a", speciesEn: "Sneasler", stat: "def", delta: 1)
check("T51 held not emitted", !battleLog.contains { $0.contains("|-boost|") })
flushHeldBoosts(forKey: "p1:Sneasler", slot: "p1b")
check("T51 flushed with right slot", battleLog.contains("|-boost|p1b: Sneasler|def|1"))

// T52: 交代で入った直後に技を受けていたら、交代行の後に被ダメ行を補う
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 28)
monStates["p2:Sylveon"] = MonState(); monStates["p2:Sylveon"]!.hpPercent = 45
processPlates(["oppB": SlotState(speciesEn: "Sylveon", hpPercent: 4)])
processPlates(["oppB": SlotState(speciesEn: "Sylveon", hpPercent: 4)])
let swI = battleLog.firstIndex { $0.contains("|switch|p2b: Sylveon") }
let dmI = battleLog.firstIndex { $0.contains("|-damage|p2b: Sylveon") }
check("T52 switch-in damage emitted", swI != nil && dmI != nil && swI! < dmI!)


// T53: ログ画面の side は場の実態で検証される (自分の ひんし が相手に付かない)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 59)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 59
translateLogEntry(chip: "ひんし", text: "サーナイトがたおれた", side: "p2", turn: 3)
check("T53 faint side corrected", battleLog.contains("|faint|p1a: Gardevoir") && !battleLog.contains { $0.contains("|faint|p2a") })

// T54: 実況で記録済みの技はログ画面から二重に出ない
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
lastMoveSigAt["p2a|Shadow Ball|t6"] = Date()
translateLogEntry(chip: "技", text: "ゲンガーはシャドーボールをつかった", side: "p2", turn: 6)
check("T54 dup move suppressed", !battleLog.contains { $0.contains("|move|") })
translateLogEntry(chip: "技", text: "ゲンガーはシャドーボールをつかった", side: "p2", turn: 7)
check("T54 other turn emits", battleLog.contains("|move|p2a: Gengar|Shadow Ball"))

// T55: ログ画面の回復エントリの異常な跳ね上がりは取り込まない
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 4)
monStates["p1:Indeedee-F"] = MonState(); monStates["p1:Indeedee-F"]!.hpPercent = 4
translateLogEntry(chip: "回復", text: "イエッサン HP 4% → 100%", side: "p1", turn: 7)
check("T55 bogus full heal skipped", monStates["p1:Indeedee-F"]?.hpPercent == 4 && !battleLog.contains { $0.contains("|-heal|") })
translateLogEntry(chip: "HP減少", text: "イエッサン HP 4% → 0%", side: "p1", turn: 7)
check("T55 real zero applied", monStates["p1:Indeedee-F"]?.hpPercent == 0 && battleLog.contains("|faint|p1b: Indeedee-F"))

// T56: やどりぎのたねを植えつけた文を消費する
resetAll()
check("T56 leech seed consumed", translateBattleMessage("オオニューラにうたね種を植えつけた！") == true)

// T57: たべのこし判定は +3% でも付く (バー読みの量子化対策)
resetAll()
actionSeq = 7; currentTurn = 2
lastEmittedPct["oppA"] = 30
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Gengar", speciesEn: "Gengar", fromPct: 30, toPct: 33, hpText: "33/100", force: true)
check("T57 leftovers delta3", battleLog.contains("|-heal|p2a: Gengar|33/100|[from] item: Leftovers"))


// T58: サイコシード消費で かるわざ 発動が出る (場に出ている場合)
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "サイコシード"]
logFieldTerrain = "Psychic"
monStates["p1:Sneasler"] = MonState()
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
emittedSwitchKeys = ["p1:Sneasler"]
applyBoost(key: "p1:Sneasler", slot: "p1b", speciesEn: "Sneasler", stat: "spd", delta: 1)
check("T58 unburden on seed", battleLog.contains("|-ability|p1b: Sneasler|Unburden"))

// T59: 交代行より前に検知した場合は、交代行の後に出る
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "サイコシード"]
logFieldTerrain = "Psychic"
monStates["p1:Sneasler"] = MonState()
applyBoost(key: "p1:Sneasler", slot: "p1a", speciesEn: "Sneasler", stat: "spd", delta: 1)
check("T59 pending before switch", !battleLog.contains { $0.contains("|-ability|") } && pendingUnburden.contains("p1:Sneasler"))
recordSwitchIn(side: "p1", slot: "p1b", speciesEn: "Sneasler")
check("T59 unburden after switch", battleLog.contains("|-ability|p1b: Sneasler|Unburden"))

// T60: きのみを食べた場合も発動する
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "オボンのみ"]
monStates["p1:Sneasler"] = MonState()
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 40)
emittedSwitchKeys = ["p1:Sneasler"]
check("T60 berry text consumed", translateBattleMessage("オオニューラは オボンのみを 食べた！") == true)
check("T60 unburden on berry", battleLog.contains("|-ability|p1b: Sneasler|Unburden"))

// T61: 特性が かるわざ でなければ出ない
resetAll()
teamEntries["Sneasler"] = ["ability": "どくしゅ", "item": "サイコシード"]
logFieldTerrain = "Psychic"
monStates["p1:Sneasler"] = MonState()
emittedSwitchKeys = ["p1:Sneasler"]
applyBoost(key: "p1:Sneasler", slot: "p1b", speciesEn: "Sneasler", stat: "spd", delta: 1)
check("T61 no unburden", !battleLog.contains { $0.contains("Unburden") })


// T62: かるわざ発動が state 用フラグに残り、交代で解除される
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "サイコシード"]
logFieldTerrain = "Psychic"
monStates["p1:Sneasler"] = MonState()
emittedSwitchKeys = ["p1:Sneasler"]
emitLog("|switch|p1b: Sneasler|Sneasler|100/100")
applyBoost(key: "p1:Sneasler", slot: "p1b", speciesEn: "Sneasler", stat: "spd", delta: 1)
check("T62 unburden flag set", unburdenActive.contains("p1:Sneasler"))
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
processPlates(["mineB": SlotState(speciesEn: "Gardevoir", hpPercent: 100)])
processPlates(["mineB": SlotState(speciesEn: "Gardevoir", hpPercent: 100)])
check("T62 unburden flag cleared on switch", !unburdenActive.contains("p1:Sneasler"))


// T63: 「上がつた」(小さいっ崩れ) でもランク変化として処理し、漏らさない
resetAll()
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
checkBoostText(text: "相手のオオニューラのとくぼう特防が上がつた！", side: "p2", speciesEn: "Sneasler", slot: "p2a")
check("T63 garbled boost applied", monStates["p2:Sneasler"]?.boosts["spd"] == 1)
check("T63 no phantom def boost", monStates["p2:Sneasler"]?.boosts["def"] == nil)
check("T63 boost-shaped net", isBoostShapedText("オオニューラのとくぼう特防が上がつた！"))

// T64: プレートで 0% を読めなかった ひんし は「たおれた」文から被ダメ行を補う
resetAll()
var ms64 = MonState(); ms64.hpPercent = 100; ms64.hpMax = 177; ms64.hpText = "177/177"
monStates["p1:Indeedee"] = ms64
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee", hpPercent: 100)
lastEmittedPct["mineB"] = 100
_ = translateBattleMessage("イエッサンは たおれた！")
check("T64 faint damage from text", battleLog.contains("|-damage|p1b: Indeedee|0/177"))
check("T64 faint deferred", pendingFaints.contains { $0.speciesEn == "Indeedee" })

// T65: プレートの 0% は 2 フレーム連続で初めて確定 (一瞬の誤読では出さない)
resetAll()
var ms65 = MonState(); ms65.hpPercent = 37; ms65.hpText = "37/100"
monStates["p2:Absol"] = ms65
lastSlots["oppB"] = SlotState(speciesEn: "Absol", hpPercent: 37)
lastEmittedPct["oppB"] = 37
processPlates(["oppB": SlotState(speciesEn: "Absol", hpPercent: 0)])
check("T65 single 0 read ignored", !battleLog.contains("|-damage|p2b: Absol"))
processPlates(["oppB": SlotState(speciesEn: "Absol", hpPercent: 37)])
check("T65 recovered read no line", !battleLog.contains("|-damage|p2b: Absol"))
processPlates(["oppB": SlotState(speciesEn: "Absol", hpPercent: 0)])
processPlates(["oppB": SlotState(speciesEn: "Absol", hpPercent: 0)])
check("T65 stable 0 confirmed", battleLog.contains("|-damage|p2b: Absol|0/100"))


// T66: ファイル指紋は内容が変わると変わり、同じ内容では変わらない
let dir66 = NSTemporaryDirectory() + "fp_test_\(ProcessInfo.processInfo.processIdentifier)"
try? FileManager.default.createDirectory(atPath: dir66, withIntermediateDirectories: true)
let f66a = URL(fileURLWithPath: dir66 + "/a.json")
let f66b = URL(fileURLWithPath: dir66 + "/b.json")
try! "{\"x\": 1}".write(to: f66a, atomically: true, encoding: .utf8)
try! "{\"y\": 2}".write(to: f66b, atomically: true, encoding: .utf8)
let fp66 = fingerprintFiles([f66a, f66b])
check("T66 fingerprint stable", fingerprintFiles([f66a, f66b]) == fp66)
try! "{\"x\": 9}".write(to: f66a, atomically: true, encoding: .utf8)
check("T66 fingerprint changes on edit", fingerprintFiles([f66a, f66b]) != fp66)
check("T66 missing file distinct", fingerprintFiles([f66a, f66b]) != fingerprintFiles([f66a]))

// T67: 壁・オーロラベールの技名解決 (mv イベントの技名が UI チップ判定の要)
for (ja, en) in [("オーロラベール", "Aurora Veil"), ("リフレクター", "Reflect"), ("ひかりのかべ", "Light Screen"), ("おいかぜ", "Tailwind")] {
    moveNameOrig[normalize(ja)] = ja; moveJa2En[ja] = en
}
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
_ = translateBattleMessage("相手のキュウコンのオーロラベール！")
check("T67 veil move name", battleLog.contains("|move|p2a: Ninetales|Aurora Veil"))
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
_ = translateBattleMessage("相手のキュウコンのリフレクター！")
check("T67 reflect move name", battleLog.contains("|move|p2a: Ninetales|Reflect"))
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Ninetales", hpPercent: 100)
_ = translateBattleMessage("相手のキュウコンのひかりのかべ！")
check("T67 light screen move name", battleLog.contains("|move|p2a: Ninetales|Light Screen"))



// T68 (a): 能力名がカタカナ表記でも正規経路で入る (検証 R1 で正規経路にも
// カタカナ表記を追加。従来の「正規は失敗しサルベージで入る」前提は廃止し、
// 正規経路・サルベージ双方で入ることを確認する)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
check("T68 regular consumes", translateBattleMessage("オオニューラのトクボウが上がった！") == true)
check("T68 regular boost applied", monStates["p2:Sneasler"]?.boosts["spd"] == 1)
check("T68 regular log line", battleLog.contains("|-boost|p2a: Sneasler|spd|1"))
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
check("T68 salvage consumes", salvageFromText("オオニューラのトクボウが上がった！"))
check("T68 salvage boost applied", monStates["p2:Sneasler"]?.boosts["spd"] == 1)
check("T68 salvage log line", battleLog.contains("|-boost|p2a: Sneasler|spd|1"))
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
check("T68b salvage x2", salvageFromText("オオニューラのトクコウがぐーんと上がった！") && monStates["p2:Sneasler"]?.boosts["spa"] == 2)

// T69 (b): 種族が一意でない (両サイドに同種族 / 場にいない) 場合は入れない
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState(); monStates["p1:Sneasler"] = MonState()
check("T69 mirror no salvage", salvageFromText("オオニューラのトクボウが上がった！") == false)
check("T69 mirror no boost", (monStates["p2:Sneasler"]?.boosts["spd"] ?? 0) == 0 && (monStates["p1:Sneasler"]?.boosts["spd"] ?? 0) == 0)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
check("T69 absent no salvage", salvageFromText("ガブリアスのトクボウが上がった！") == false)

// T70 (c): サルベージ→正規 / 正規→サルベージ の順でも二重適用されない
// (間に別の行動を挟み、既存の 4 秒・同一行動ガードが効かない条件で検証)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
_ = salvageFromText("オオニューラのトクボウが上がった！")
actionSeq += 1
_ = translateBattleMessage("相手のオオニューラのとくぼうが上がった！")
check("T70 salvage-then-regular no double", monStates["p2:Sneasler"]?.boosts["spd"] == 1)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
_ = translateBattleMessage("相手のオオニューラのとくぼうが上がった！")
actionSeq += 1
check("T70 regular-then-salvage consumed", salvageFromText("オオニューラのトクボウが上がった！"))
check("T70 regular-then-salvage no double", monStates["p2:Sneasler"]?.boosts["spd"] == 1)

// T71 (d): 否定文では発火しない
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
emittedSwitchKeys = ["p2:Sneasler"]
check("T71 negation up", salvageFromText("オオニューラのトクボウはもう上がらない！") == false && (monStates["p2:Sneasler"]?.boosts["spd"] ?? 0) == 0)
check("T71 negation down", salvageFromText("オオニューラのトクボウは下がらない！") == false && (monStates["p2:Sneasler"]?.boosts["spd"] ?? 0) == 0)

// T72: 状態異常の救済 (対象が一意なときだけ)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
check("T72 status salvage", salvageFromText("相手のオオニューラはどくをあびた！") && monStates["p2:Sneasler"]?.status == "psn")
check("T72 status log line", battleLog.contains("|-status|p2a: Sneasler|psn"))

// T73: 持ち物消費の救済
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p2:Sneasler"] = MonState()
check("T73 item salvage", salvageFromText("オオニューラはオボンのみを食べた！") && itemLostActive.contains("p2:Sneasler"))
check("T73 item revealed", revealedItems["Sneasler"] == "オボンのみ")

// T74: 場の状態の救済 (壁は checkFieldText の対象外 = サルベージ固有の範囲)
resetAll()
check("T74 wall salvage", salvageFromText("相手の側にリフレクターが現れた！") && battleLog.contains("|-sidestart|p2|move: Reflect"))
check("T74 wall end salvage", salvageFromText("相手の側のリフレクターが消えた！") && battleLog.contains("|-sideend|p2|move: Reflect"))


// T75: state.json スキーマ検証 (生成物のキーがスキーマ定義の範囲内か) +
// boosts 全7能力 + 残りターンの出力
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 73)
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 55)
var stA = MonState(); stA.status = "par"; stA.boosts = ["atk": 1, "spe": -1]; stA.hpPercent = 73
monStates["p1:Garchomp"] = stA
var stB = MonState(); stB.boosts = ["spd": 1]; stB.hpPercent = 55
monStates["p2:Sneasler"] = stB
unburdenActive = ["p2:Sneasler"]; itemLostActive = ["p2:Sneasler"]
revealedMoves["Sneasler"] = ["Fake Out"]; revealedItems["Sneasler"] = "オボンのみ"; revealedAbilities["Sneasler"] = "かるわざ"
oppTeamSeen = ["Sneasler"]
currentTurn = 3
logFieldWeather = "Rain"
emitLog("|-weather|Rain")
emitLog("|-sidestart|p2|move: Reflect")
currentTurn = 5
writeState()
let raw = try! String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)
let obj = try! JSONSerialization.jsonObject(with: Data(raw.utf8)) as! [String: Any]
check("T75 top keys within schema", Set(obj.keys).isSubset(of: stateTopKeys))
let mine0 = (obj["mine"] as! [[String: Any]])[0]
let opp0 = (obj["opps"] as! [[String: Any]])[0]
check("T75 mon keys within schema", Set(mine0.keys).isSubset(of: stateMonKeys) && Set(opp0.keys).isSubset(of: stateMonKeys))
check("T75 revealed keys within schema", Set((opp0["revealed"] as! [String: Any]).keys).isSubset(of: stateRevealedKeys))
check("T75 boosts exactly 7", Set((opp0["boosts"] as! [String: Any]).keys) == Set(stateBoostKeys))
check("T75 boosts values", (opp0["boosts"] as! [String: Any])["spd"] as? Int == 1 && (opp0["boosts"] as! [String: Any])["atk"] as? Int == 0)
let fieldObj = obj["field"] as! [String: Any]
check("T75 field keys within schema", Set(fieldObj.keys).isSubset(of: stateFieldKeys))
check("T75 weatherTurnsLeft", fieldObj["weatherTurnsLeft"] as? Int == 3)
let scObj = obj["sideConditions"] as! [String: Any]
check("T75 sideConditions reflect", (scObj["p2"] as! [String: Any])["Reflect"] as? Int == 3)
// 期限切れではキーが消える
currentTurn = 8
lastWritten = ""
writeState()
let raw2 = try! String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)
let obj2 = try! JSONSerialization.jsonObject(with: Data(raw2.utf8)) as! [String: Any]
check("T75 expired turns key gone", (obj2["field"] as! [String: Any])["weatherTurnsLeft"] == nil)
check("T75 expired sideConditions gone", obj2["sideConditions"] == nil)
// おいかぜは4ターン
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
monStates["p1:Garchomp"] = MonState()
currentTurn = 2
emitLog("|-sidestart|p1|move: Tailwind")
currentTurn = 5
writeState()
let raw3 = try! String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)
let obj3 = try! JSONSerialization.jsonObject(with: Data(raw3.utf8)) as! [String: Any]
check("T75 tailwind 4 turns", ((obj3["sideConditions"] as! [String: Any])["p1"] as! [String: Any])["Tailwind"] as? Int == 1)


// T76: イベント再生の回帰テスト — 実況経路で作った状態と、発行された
// プロトコル行だけを applyEvent に再生して再構築した状態が一致すること
func snapshotState() -> String {
    var parts: [String] = []
    for k in monStates.keys.sorted() {
        let st = monStates[k]!
        let b = st.boosts.keys.sorted().map { "\($0)=\(st.boosts[$0]!)" }.joined(separator: ",")
        parts.append("\(k): hp=\(st.hpPercent) st=\(st.status) mega=\(st.megaSpecies) boosts[\(b)]")
    }
    parts.append("field: w=\(logFieldWeather) t=\(logFieldTerrain) tr=\(logTrickRoom) turn=\(currentTurn)")
    parts.append("turns: w=\(fieldWeatherSetTurn) t=\(fieldTerrainSetTurn) tr=\(fieldTrickRoomSetTurn)")
    parts.append("sc: " + sideCondSetTurns.keys.sorted().map { "\($0)=\(sideCondSetTurns[$0]!)" }.joined(separator: " "))
    parts.append("revM: " + revealedMoves.keys.sorted().map { "\($0)=\(revealedMoves[$0]!)" }.joined(separator: " "))
    parts.append("revI: " + revealedItems.keys.sorted().map { "\($0)=\(revealedItems[$0]!)" }.joined(separator: " "))
    parts.append("revA: " + revealedAbilities.keys.sorted().map { "\($0)=\(revealedAbilities[$0]!)" }.joined(separator: " "))
    parts.append("unb: \(unburdenActive.sorted().joined(separator: ",")) lost: \(itemLostActive.sorted().joined(separator: ","))")
    parts.append("slots: " + eventSlotSpecies.keys.sorted().map { "\($0)=\(eventSlotSpecies[$0]!)" }.joined(separator: " "))
    return parts.joined(separator: "\n")
}
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "サイコシード"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
emitLog("|switch|p1a: Garchomp|Garchomp|100/100")
emitLog("|switch|p1b: Sneasler|Sneasler|100/100")
emitLog("|switch|p2a: Incineroar|Incineroar|100/100")
emitLog("|switch|p2b: Gardevoir|Gardevoir|100/100")
emitLog("|turn|1")
_ = translateBattleMessage("相手のサーナイトのハイパーボイス！")
applyBoost(key: "p2:Incineroar", slot: "p2a", speciesEn: "Incineroar", stat: "atk", delta: -1)
checkStatusText(text: "サーナイトはやけどをおった！", side: "p2", speciesEn: "Gardevoir", slot: "p2b")
_ = checkFieldText(text: "雨が降り始めた！")
_ = checkFieldText(text: "足下が不思議な感じになった！")
_ = salvageFromText("味方のおいかぜが吹き始めた！")
applyBoost(key: "p1:Sneasler", slot: "p1b", speciesEn: "Sneasler", stat: "spd", delta: 1)
lastEmittedPct["oppA"] = 100
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Incineroar", speciesEn: "Incineroar", fromPct: 100, toPct: 40, hpText: "40/100", force: true)
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Incineroar", speciesEn: "Incineroar", fromPct: 40, toPct: 65, hpText: "65/100", force: true)
completeMega(side: "p1", baseEn: "Garchomp", megaEn: "Garchomp-Mega")
lastEmittedPct["oppB"] = 100
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
emitPendingFaints()
emitLog("|turn|2")
let liveSnap = snapshotState()
let savedLines = battleLog
resetAll()
for l in savedLines { applyEvent(l) }
let replaySnap = snapshotState()
check("T76 replay matches live", liveSnap == replaySnap)
if liveSnap != replaySnap { print("LIVE:\n\(liveSnap)\nREPLAY:\n\(replaySnap)\nLINES:\n\(savedLines.joined(separator: "\n"))") }


// T77: 保存済み battle_protocol.log (実戦5試合分) の再生 — 決定性と
// 不変条件 (HP 0..100 / ランク ±6) を検証し、第1試合は具体値も照合する
for fx in ["battle_protocol.log", "battle_protocol-2.log", "battle_protocol-3.log", "battle_protocol-4.log", "battle_protocol-5.log"] {
    let text = try! String(contentsOfFile: "fixtures/\(fx)", encoding: .utf8)
    let lines = text.split(separator: "\n").map(String.init)
    resetAll()
    for l in lines { applyEvent(l) }
    let snap1 = snapshotState()
    resetAll()
    for l in lines { applyEvent(l) }
    let snap2 = snapshotState()
    check("T77 \(fx) deterministic", snap1 == snap2)
    var inv = true
    for (_, st) in monStates {
        if st.hpPercent < 0 || st.hpPercent > 100 { inv = false }
        for (_, v) in st.boosts { if v < -6 || v > 6 { inv = false } }
    }
    check("T77 \(fx) invariants", inv)
}
resetAll()
let fxText1 = try! String(contentsOfFile: "fixtures/battle_protocol.log", encoding: .utf8)
for l in fxText1.split(separator: "\n").map(String.init) { applyEvent(l) }
check("T77 fixture1 final turn", currentTurn == 9)
check("T77 fixture1 kommo-o fainted", monStates["p2:Kommo-o"]?.hpPercent == 0)

// T78: 入場バッチ 'ab' イベント — 同時入場の特性だけが発動順で記録され、
// 入場していない個体の発動やウィンドウ外の発動は記録されない
resetAll()
battleEvents = []; lastExactHp = [:]
entryBatchId = 0; entryBatchOpen = false; entryBatchMembers = []; entryBatchAbBuffer = []
emitLog("|switch|p1a: Indeedee-F|Indeedee-F|100/100")
emitLog("|switch|p1b: Armarouge|Armarouge|100/100")
emitLog("|switch|p2a: Kleavor|Kleavor|100/100")
emitLog("|switch|p2b: Rillaboom|Rillaboom|100/100")
emitLog("|-ability|p1a: Indeedee-F|Psychic Surge")
emitLog("|-ability|p2b: Rillaboom|Grassy Surge")
emitLog("|turn|1")
var abEvs = battleEvents.filter { $0.contains("\"k\":\"ab\"") }
check("T78 battle-start ab count", abEvs.count == 2)
check("T78 ab order preserved", abEvs.count == 2 && abEvs[0].contains("Indeedee-F") && abEvs[1].contains("Rillaboom"))
check("T78 ab batch shared", abEvs.allSatisfy { $0.contains("\"batch\":1") })
emitLog("|switch|p1a: Garchomp|Garchomp|100/100")
emitLog("|switch|p2a: Incineroar|Incineroar|100/100")
emitLog("|-ability|p2a: Incineroar|Intimidate")
emitLog("|-ability|p1b: Armarouge|Flash Fire")
emitLog("|turn|2")
abEvs = battleEvents.filter { $0.contains("\"k\":\"ab\"") }
check("T78 non-entrant ability excluded", abEvs.count == 3 && abEvs[2].contains("Incineroar") && abEvs[2].contains("\"batch\":2"))
emitLog("|move|p1a: Garchomp|Earthquake")
emitLog("|-ability|p1a: Garchomp|Rough Skin")
emitLog("|turn|3")
abEvs = battleEvents.filter { $0.contains("\"k\":\"ab\"") }
check("T78 outside-window ability ignored", abEvs.count == 3)

// T79: OCR検証ループ (2026-11-20 R1-R5) で見つけたクラスの恒久回帰テスト
// (a) カイリキーのひんし文を「かいりき」使用と誤読しない
speciesDict.append(E("カイリキー", "Machamp"))
moveNameOrig[normalize("かいりき")] = "かいりき"; moveJa2En["かいりき"] = "Strength"
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Machamp", hpPercent: 0)
monStates["p2:Machamp"] = MonState()
_ = translateBattleMessage("相手のカイリキーはたおれた！")
emitPendingFaints()
check("T79a no phantom Strength", !battleLog.contains { $0.contains("|move|") })
check("T79a faint emitted", battleLog.contains("|faint|p2a: Machamp"))
// (b) がくっと は正規経路でも -2
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
monStates["p2:Gengar"] = MonState()
emittedSwitchKeys = ["p2:Gengar"]
_ = translateBattleMessage("相手のゲンガーのとくこうががくっと下がった！")
check("T79b gakutto is -2", battleLog.contains("|-unboost|p2a: Gengar|spa|2"))
// (c) ぐんと (長音落ち) も +2
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
teamEntries = ["Gardevoir": [:]]
monStates["p1:Gardevoir"] = MonState()
emittedSwitchKeys = ["p1:Gardevoir"]
_ = translateBattleMessage("サーナイトのとくこうがぐんと上がった！")
check("T79c gunto is +2", battleLog.contains("|-boost|p1a: Gardevoir|spa|2"))
// (d) 種族名の濁点ゆれ (ザーナイト) でも状態が付く
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
teamEntries = ["Gardevoir": [:]]
monStates["p1:Gardevoir"] = MonState()
_ = translateBattleMessage("ザーナイトはやけどをおった！")
check("T79d folded species status", battleLog.contains("|-status|p1a: Gardevoir|brn"))
// (e) 上がつた (っ→つ) が正規経路で入る
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
monStates["p2:Gengar"] = MonState()
emittedSwitchKeys = ["p2:Gengar"]
_ = translateBattleMessage("相手のゲンガーのすばやさが上がつた！")
check("T79e tsu-variant boost", battleLog.contains("|-boost|p2a: Gengar|spe|1"))

// T80: 最終監査 (seed31/32) で見つけたクラスの恒久回帰テスト
// (a) 両軍に同ーフォルム違い (自分のイエッサン♀ / 相手のイエッサン♂) が
// いる場で、相手のひんしが自分のポケモンに誤帰属しない
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee", hpPercent: 0)
teamEntries = ["Indeedee-F": [:]]
monStates["p1:Indeedee-F"] = MonState()
monStates["p2:Indeedee"] = MonState()
emittedSwitchKeys = ["p1:Indeedee-F", "p2:Indeedee"]
_ = translateBattleMessage("相手のイエッサンはたおれた！")
emitPendingFaints()
check("T80a opp faint correct side", battleLog.contains("|faint|p2a: Indeedee"))
check("T80a no self faint", !battleLog.contains { $0.contains("p1b") && $0.contains("faint") })
// (b) 長音2連落ちの技名が第3パスで解決する
moveNameOrig[normalize("ワンダールーム")] = "ワンダールーム"; moveJa2En["ワンダールーム"] = "Wonder Room"
check("T80b wonder room delonged", moveNameLoose("ワンダルム") == "ワンダールーム")

// T81: 設置物 (ステルスロック等) の恒久回帰テスト
// (a) ステルスロックの技は相手側に即時設置される
resetAll()
applyMoveField("ステルスロック", side: "p1")
check("T81a SR sidestart", battleLog.contains("|-sidestart|p2|move: Stealth Rock"))
check("T81a SR state", battleHazards["p2"]?["Stealth Rock"] == 1)
// (b) がんせきアックスは保留になり、相手へのダメージ行で確定する
resetAll()
emitLog("|move|p1a: Kleavor|Stone Axe")
applyMoveField("がんせきアックス", side: "p1")
check("T81b pending set", pendingHazard != nil && !battleLog.contains { $0.hasPrefix("|-sidestart|") })
emitLog("|-damage|p2a: Dragapult|83/100")
check("T81b SR confirmed", battleLog.contains("|-sidestart|p2|move: Stealth Rock") && battleHazards["p2"]?["Stealth Rock"] == 1)
// (c) がんせきアックスが外れた/守られた (ダメージ行なし) 場合は設置されない
resetAll()
emitLog("|move|p1a: Kleavor|Stone Axe")
applyMoveField("がんせきアックス", side: "p1")
emitLog("|move|p2a: Dragapult|U-turn")
applyMoveField("とんぼがえり", side: "p2")
check("T81c pending expired", pendingHazard == nil && !battleLog.contains { $0.hasPrefix("|-sidestart|") })
// (d) こうそくスピンは自軍の設置物を消す (当たった場合のみ)
resetAll()
emitHazard("p1", "Stealth Rock", start: true)
emitLog("|move|p1a: Blastoise|Rapid Spin")
applyMoveField("こうそくスピン", side: "p1")
emitLog("|-damage|p2a: Dragapult|90/100")
check("T81d spin clears", battleLog.contains("|-sideend|p1|move: Stealth Rock") && (battleHazards["p1"] ?? [:]).isEmpty)
// (e) きりばらいは両側の設置物を消す
resetAll()
emitHazard("p1", "Stealth Rock", start: true)
emitHazard("p2", "Spikes", start: true)
applyMoveField("きりばらい", side: "p1")
check("T81e defog clears both", (battleHazards["p1"] ?? [:]).isEmpty && (battleHazards["p2"] ?? [:]).isEmpty)
// (f) まきびしは層が増え、上限3で止まる
resetAll()
for _ in 0..<4 { applyMoveField("まきびし", side: "p2") }
check("T81f spikes layers cap", battleHazards["p1"]?["Spikes"] == 3)
// (g) 設置文の救済: 技を取りこぼしても本文から設置が入る
resetAll()
_ = salvageFromText("相手の周りに とがった岩が 漂い始めた！")
check("T81g text salvage SR", battleLog.contains("|-sidestart|p2|move: Stealth Rock"))

// T82: vs Destrock 戦 (2026-11-20) の回帰テスト
// (a) 壁の告知文 (「〜で特殊に強くなった」) から sidestart が出る
resetAll()
check("T82a screen text consumed", salvageFromText("あいて相手はひかりのかべでとくしゃ特殊に強くなった！"))
check("T82a Light Screen sidestart", battleLog.contains("|-sidestart|p2|move: Light Screen"))
// (b) 登場時の掛け声 (OCR で崩れた実物) は消費され、出来事として残らない
// (崩れていない掛け声は先発の登場として処理される設計なので、対象は崩れた形)
resetAll()
check("T82b shout consumed", translateBattleMessage("ゆけう！サーナイト！おねむなエルフーン！"))
check("T82b no shout event", battleLog.isEmpty)

// T83: vs leslie 戦 (2026-11-20) の回帰テスト
// (a) ひんし交代の初登場は、設置物が無ければ満タン採用する
// (登場アニメーション途中のバー 61/161 を採用すると幻の被ダメ→全回復が出る)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 0)
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 0
faintedSlots["p1a"] = "Gardevoir"
fieldSeen["p1"] = ["Gardevoir", "Whimsicott"]
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
check("T83a switch full", battleLog.contains("|switch|p1a: Armarouge|Armarouge|161/161"))
check("T83a no phantom damage", !battleLog.contains { $0.contains("-damage|p1a: Armarouge") })
check("T83a state full", monStates["p1:Armarouge"]?.hpPercent == 100)
// (b) 設置物がある側の初登場は読み値を採用する (設置ダメージを消さない)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 0)
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 0
faintedSlots["p1a"] = "Gardevoir"
fieldSeen["p1"] = ["Gardevoir", "Whimsicott"]
battleHazards["p1"] = ["Stealth Rock": 1]
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
check("T83b switch entry value", battleLog.contains("|switch|p1a: Armarouge|Armarouge|161/161"))
check("T83b state read value", monStates["p1:Armarouge"]?.hpPercent == 38)
check("T83b hazard attribution", battleLog.contains { $0.contains("-damage|p1a: Armarouge|61/161|[from] Stealth Rock") })
// (c) 交代待ちでない枠の初登場は満タン採用しない
// (初登場を取り逃がして後から発見した場合に実ダメージを消さないため)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
fieldSeen["p1"] = ["Gardevoir", "Whimsicott"]
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
processPlates(["mineA": SlotState(speciesEn: "Armarouge", hpPercent: 38, hpCur: 61, hpMax: 161)])
check("T83c switch entry value", battleLog.contains("|switch|p1a: Armarouge|Armarouge|161/161"))
check("T83c state read value", monStates["p1:Armarouge"]?.hpPercent == 38)
// (d) メガ反応文の OCR 崩れ (反応→受応) でも消費され、ストーンが記録される
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
check("T83d mega garble consumed", translateBattleMessage("サーナイトの サーナイトナイトとRenのゼンブイリングが受応した！"))
check("T83d stone recorded", battleLog.contains { $0.contains("|-item|p1a: Gardevoir|Gardevoirite") })
// (e) 交代文の OCR 崩れ (ラテン文字混入「引Iっこめた」) を消費する
resetAll()
check("T83e withdrawal garble consumed", translateBattleMessage("leslieはドドゲザンを引Iっこめた！"))
check("T83e no leak", battleLog.isEmpty)

// T84: デバッグ撮影の判定 (debugShouldCapture): 初出は撮る、類似文 (OCR ゆれ) は
// 直近 30 秒だけまとめ、別文は撮る、上限で止まる。完全一致キーは時間が
// 空いても 1 件。内部矛盾キー (種別|対象) も同じ規則
let t84_0 = Date(timeIntervalSince1970: 1_000_000)
check("T84a first fires", debugShouldCapture(seen: [], count: 0, key: "あいてのポケモンはふしぎなまもりでまもられている", cap: 10, now: t84_0))
check("T84b jitter merged", !debugShouldCapture(seen: [(key: "あいてのポケモンはふしぎなまもりでまもられている", at: t84_0)], count: 1, key: "あいてのポケモンはふしぎなまもりてまもられている", cap: 10, now: t84_0.addingTimeInterval(10)))
check("T84c distinct fires", debugShouldCapture(seen: [(key: "あいてのポケモンはふしぎなまもりでまもられている", at: t84_0)], count: 1, key: "hp_reversal_drop|p1a: Gardevoir", cap: 10, now: t84_0.addingTimeInterval(10)))
check("T84d same internal key merged", !debugShouldCapture(seen: [(key: "hp_reversal_drop|p1a: Gardevoir", at: t84_0)], count: 2, key: "hp_reversal_drop|p1a: Gardevoir", cap: 10, now: t84_0.addingTimeInterval(3600)))
check("T84e cap blocks", !debugShouldCapture(seen: [], count: 10, key: "あたらしいぶんしょう", cap: 10, now: t84_0))
// T84f/g: 2026-11-21 battle_20261121_132153 の実例。身代わりの「出現」と
// 「被弾」は主語を共有して類似度が高い (0.84) が別の出来事。出現の撮影から
// 時間が空いていれば被弾も撮り (f)、直後なら再読としてまとめる (g)
check("T84f substitute hit after window fires", debugShouldCapture(seen: [(key: "あいて相手のゲンガーの身代わりが現れた", at: t84_0)], count: 2, key: "あいて相手のゲンガーにかわってみかこうげきざ身代わりが攻撃を受けた", cap: 10, now: t84_0.addingTimeInterval(120)))
check("T84g substitute hit within window merged", !debugShouldCapture(seen: [(key: "あいて相手のゲンガーの身代わりが現れた", at: t84_0)], count: 2, key: "あいて相手のゲンガーにかわってみかこうげきざ身代わりが攻撃を受けた", cap: 10, now: t84_0.addingTimeInterval(10)))

// T85: vs Toshiro 戦 (2026-11-21) の回帰テスト
// (a)(b) 相手のメガ完了文が「相手の」を欠いた形で再読されても、自陣に
// 幻のメガシンカを出さない (場の実態から p2 と判定し、完了済みで抑止される)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Staraptor", hpPercent: 100)
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
check("T85a marked completion consumed", translateBattleMessage("相手のムクホークはメガムクホークにメガシンカした！"))
check("T85a p2 mega state", monStates["p2:Staraptor"]?.megaSpecies == "Staraptor-Mega")
check("T85b unmarked re-read consumed", translateBattleMessage("ムクホークはメガムクホークにメガシンカした！"))
check("T85b no phantom p1 mega", !battleLog.contains { $0.contains("p1a: Staraptor") } && monStates["p1:Staraptor"] == nil)
check("T85b detailschange once", battleLog.filter { $0.hasPrefix("|detailschange|") }.count == 1)
// (c) 完了済みメガの反応文の再読では、持ち物行も保留も出し直さない
check("T85c stale reaction consumed", translateBattleMessage("ムクホークの ムクホークナイトとToshiroのゼンブイリングが反応した！"))
check("T85c no item line", !battleLog.contains { $0.hasPrefix("|-item|") })
check("T85c no pending", pendingMegaSpecies["p1"] == nil && pendingMegaSpecies["p2"] == nil)
// (d) 反応の保留がある場合は、標識の無い完了文でも保留側に帰属する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Staraptor", hpPercent: 100)
pendingMegaSpecies["p2"] = "Staraptor"
pendingMegaStone["p2"] = "ムクホークナイト"
check("T85d unmarked completion consumed", translateBattleMessage("ムクホークはメガムクホークにメガシンカした！"))
check("T85d p2 mega state", monStates["p2:Staraptor"]?.megaSpecies == "Staraptor-Mega")
check("T85d no p1 state", monStates["p1:Staraptor"] == nil)

// T86: vs Woxofyl 戦 (2026-11-21 battle_20261121_132153) の回帰テスト
// (a) ふうせんが割れた文: 持ち物の判明と喪失を記録する (実文そのまま)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Archaludon", hpPercent: 100)
check("T86a balloon consumed", translateBattleMessage("あいて相手のブリジュラスのふうせんが割れた！"))
check("T86a item line", battleLog.contains("|-item|p2a: Archaludon|Air Balloon"))
check("T86a item lost", itemLostActive.contains("p2:Archaludon"))
check("T86a revealed", revealedItems["Archaludon"] == "ふうせん")
// (b) 身代わりの出現文: 開始行を出し、再読では二重に出さない (実文そのまま)
resetAll()
lastSlots["oppB"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
check("T86b appearance consumed", translateBattleMessage("あいて相手のゲンガーの身代わりが現れた！"))
check("T86b start line", battleLog.contains("|-start|p2b: Gengar|Substitute"))
check("T86b subActive", subActive.contains("p2:Gengar"))
check("T86b re-read consumed", translateBattleMessage("あいて相手のゲンガーの身代わりが現れた！"))
check("T86b start once", battleLog.filter { $0.hasPrefix("|-start|") }.count == 1)
// (c) 身代わりが攻撃を受けた文 (実戦の OCR 崩れ文そのまま)
check("T86c hit consumed", translateBattleMessage("あいて相手の ゲンガーにかわってみかぅこうげさ身代わりが攻撃を受けた！"))
check("T86c activate line", battleLog.contains("|-activate|p2b: Gengar|move: Substitute"))
// (d) 地形の遅延検出時のシード消費の遡及記録: 同能力に記録済みの変化が
// ある場合は消費と かるわざ だけを記録し、上昇は重ねない (実戦の形)
resetAll()
teamEntries["Sneasler"] = ["item": "サイコシード", "ability": "かるわざ"]
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
emitLog("|switch|p1a: Sneasler|Sneasler|157/157")
applyBoost(key: "p1:Sneasler", slot: "p1a", speciesEn: "Sneasler", stat: "spd", delta: -1)
check("T86d pre-terrain no unburden", !unburdenActive.contains("p1:Sneasler"))
setTerrain("Psychic")
check("T86d fieldstart", battleLog.contains("|-fieldstart|move: Psychic Terrain"))
check("T86d unburden", unburdenActive.contains("p1:Sneasler"))
check("T86d item lost", itemLostActive.contains("p1:Sneasler"))
check("T86d ability line", battleLog.contains("|-ability|p1a: Sneasler|Unburden"))
check("T86d spd stays -1", monStates["p1:Sneasler"]?.boosts["spd"] == -1)
// (e) 同能力に変化が無い場合は、シードの上昇分も補う
resetAll()
teamEntries["Sneasler"] = ["item": "サイコシード", "ability": "かるわざ"]
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
emitLog("|switch|p1a: Sneasler|Sneasler|157/157")
setTerrain("Psychic")
check("T86e boost applied", monStates["p1:Sneasler"]?.boosts["spd"] == 1)
check("T86e boost line", battleLog.contains("|-boost|p1a: Sneasler|spd|1"))
check("T86e unburden", unburdenActive.contains("p1:Sneasler"))
// (f) state.json に試合 ID が載る (UI 側の対戦切り替え検知の材料)
resetAll()
battleArchiveId = "20261121_132153"
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p1:Sneasler"] = MonState()
writeState()
let raw86 = try! String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)
let obj86 = try! JSONSerialization.jsonObject(with: Data(raw86.utf8)) as! [String: Any]
check("T86f battle id", obj86["battle"] as? String == "20261121_132153")
check("T86f top keys within schema", Set(obj86.keys).isSubset(of: stateTopKeys))

// T87: ゴツゴツメットのダメージ表示 (2026-11-21 のユーザー備考
// 「ゴツゴツメットの表示がログに出ない」を受けたログ分析チャットの指示)。
// 文 → pendingStatusFrom への記録 → ダメージ行への [from] 付与 →
// 人間可読ログでの発生源表示までを通す
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Gengar", hpPercent: 100)
check("T87a helmet text consumed", translateBattleMessage("味方のオオニューラはゴツゴツメットでダメージを受けた！"))
check("T87a from recorded", pendingStatusFrom["p1:Sneasler"]?.code == "item: Rocky Helmet")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 84, hpText: "132/157", force: true)
check("T87b damage line attributed", battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler|") && $0.contains("[from] item: Rocky Helmet") })
let helmetLine87 = battleLog.first { $0.hasPrefix("|-damage|p1a: Sneasler|") } ?? ""
renderLastPct = [:]
check("T87c readable shows helmet", renderLogLine(helmetLine87).contains { $0.contains("Rocky Helmet") })

// T88: 勝敗確定後のログ連結ガード (2026-11-20 battle_20261120_124322 の
// 実例: |win| で完結した前試合に、開始検出が発火しなかった次試合の行が
// ヘッダーなしで追記され 2 試合が 1 ファイルに連結していた)
// (a) emitLog の最終防衛: 勝敗確定後の新規行は新ログのヘッダーの後に出る
resetAll()
battleLog = ["|gametype|doubles", "|start", "|win|Ren"]
winLogged = true
battleArchived = true
emitLog("|-damage|p2a: Gengar|50/100")
check("T88a new log started", battleLog.contains("|start") && !battleLog.contains("|win|Ren"))
check("T88a line after header", (battleLog.firstIndex(of: "|-damage|p2a: Gengar|50/100") ?? -1) > (battleLog.firstIndex(of: "|start") ?? -1))
check("T88a winLogged cleared", !winLogged)
// (b) プレート由来の開始証拠: 前試合と異なる種族のプレートで新ログが始まり、
// 先発がヘッダーに載る
resetAll()
battleLog = ["|gametype|doubles", "|start", "|win|Ren"]
winLogged = true
battleArchived = true
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 50)
processPlates(["oppA": SlotState(speciesEn: "Archaludon", hpPercent: 100)])
check("T88b plate evidence starts new log", battleLog.contains("|poke|p2|Archaludon") && !battleLog.contains("|win|Ren"))
// (c) 同試合の余韻: プレートが変わらなければ始め直さない
resetAll()
battleLog = ["|gametype|doubles", "|start", "|win|Ren"]
winLogged = true
battleArchived = true
lastSlots["oppA"] = SlotState(speciesEn: "Gengar", hpPercent: 50)
processPlates(["oppA": SlotState(speciesEn: "Gengar", hpPercent: 50)])
check("T88c same plates keep log", battleLog.contains("|win|Ren"))

// T89: 文からの場の救済登録 (2026-11-21 battle_20261121_132153 の実例:
// イエッサン♀のプレートが全試合未確定で、文がすべて p1a のオオニューラに
// 誤帰属した。種族が確実に解決できたのに場にいない場合、空き枠が
// ちょうど 1 つなら繰り出しとして登録してから帰属させる)
// (a) 再現: 自軍の空き枠 1 つ + チーム登録済み種族の文 → 登録後に帰属
// (文の「イエッサン」は性別表記なしのため、登録はチーム側の ♀ に寄る)
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ"]
teamEntries["Indeedee-F"] = ["ability": "サイコメイカー"]
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
check("T89a text consumed", translateBattleMessage("味方のイエッサンのとくこうが上がった！"))
check("T89a switch registered", battleLog.contains("|switch|p1b: Indeedee-F|Indeedee-F|100/100"))
check("T89a slot filled", lastSlots["mineB"]?.speciesEn == "Indeedee-F")
check("T89a boost on p1b", battleLog.contains("|-boost|p1b: Indeedee-F|spa|1"))
// (b) 否定: 空き枠が 2 つある場合は登録しない
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ"]
teamEntries["Indeedee-F"] = ["ability": "サイコメイカー"]
_ = translateBattleMessage("味方のイエッサンのとくこうが上がった！")
check("T89b no register when two empty", !battleLog.contains { $0.hasPrefix("|switch|") })
// (c) 否定: 緩い照合でしか解決できない崩れ名では登録しない
// (サ→タ の置換は正規化では直らず、編集距離の緩い照合でのみ拾える)
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ"]
teamEntries["Indeedee-F"] = ["ability": "サイコメイカー"]
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
_ = translateBattleMessage("味方のイエッタンのとくこうが上がった！")
check("T89c no register when loose", !battleLog.contains { $0.hasPrefix("|switch|") })

// T90: はたきおとすの持ち物喪失文とおみとおしの判明文 (2026-11-21
// vs KAM 戦の実例: どちらの文型もルールが無く |-message| に落ち、
// 持ち物の喪失・判明が記録されなかった)。主語は攻撃側・特性側で、
// 持ち主は「<持ち主>の<持ち物>」の並びから切り出す
// (a) はたきおとす: 持ち主の判明 + 喪失が記録される
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Scizor", hpPercent: 100)
check("T90a knockoff consumed", translateBattleMessage("相手のハッサムはイエッサンのゴツゴツメットをはたき落とした！"))
check("T90a item revealed", battleLog.contains("|-item|p1b: Indeedee-F|Rocky Helmet"))
check("T90a item lost", itemLostActive.contains("p1:Indeedee-F"))
// (b) おみとおし: 持ち主の持ち物判明が記録される (喪失はしない)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
check("T90b frisk consumed", translateBattleMessage("相手のイエッサンはサーナイトのサーナイトナイトをお見通しだ！"))
check("T90b item revealed", battleLog.contains("|-item|p1a: Gardevoir|Gardevoirite"))
check("T90b item kept", !itemLostActive.contains("p1:Gardevoir"))

// T91: プレート経路の大きな回復の却下 (2026-11-21 vs KAM 戦の実例:
// ふんか演出中にプレートが一時的に満タンと読まれ、42/177 から全回復の
// |-heal| が発生源なしで出た。55 ポイント超の回復は誤読として出さない)
// (a) 大きな回復は却下され、出力済み HP は元の値のままになる
resetAll()
monStates["p1:Indeedee-F"] = MonState()
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 24, toPct: 100, hpText: "177/177", force: true)
check("T91a huge heal rejected", !battleLog.contains { $0.hasPrefix("|-heal|") })
check("T91a emitted pct kept", lastEmittedPct["mineB"] == 24)
// (b) 発生源を説明できる通常の回復は従来どおり出る
resetAll()
monStates["p1:Indeedee-F"] = MonState()
lastMoveName = "Giga Drain"; lastMoveLabel = "p1b: Indeedee-F"
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 60, toPct: 85, hpText: "85/100", force: true)
check("T91b normal heal emitted", battleLog.contains("|-heal|p1b: Indeedee-F|85/100"))

// T92: 判明した特性からのフォルム訂正 (2026-11-21 vs KAM 戦の実例:
// 相手のバクフーンが おみとおし を発動したが、交代行は通常フォルムで
// 記録されていた。おみとおし はヒスイだけの特性のため、判明時点で
// 記録を Typhlosion-Hisui へ訂正する)
// (a) おみとおし判明 → 場・選出蓄積・状態・交代行・特性行が訂正される
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Typhlosion", hpPercent: 100)
oppTeamSeen = ["Typhlosion"]
emitLog("|switch|p2a: Typhlosion|Typhlosion|100/100")
emitAbilityOnce(slot: "p2a", side: "p2", speciesEn: "Typhlosion", abilityEn: "Frisk")
check("T92a plate corrected", lastSlots["oppA"]?.speciesEn == "Typhlosion-Hisui")
check("T92a team corrected", oppTeamSeen == ["Typhlosion-Hisui"])
check("T92a state moved", monStates["p2:Typhlosion-Hisui"] != nil && monStates["p2:Typhlosion"] == nil)
check("T92a switch line corrected", battleLog.contains("|switch|p2a: Typhlosion-Hisui|Typhlosion-Hisui|100/100"))
check("T92a ability line corrected", battleLog.contains("|-ability|p2a: Typhlosion-Hisui|Frisk"))
// (b) 否定: 両フォルムが持ち得る特性 (もうか) では訂正しない
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Typhlosion", hpPercent: 100)
emitLog("|switch|p2a: Typhlosion|Typhlosion|100/100")
emitAbilityOnce(slot: "p2a", side: "p2", speciesEn: "Typhlosion", abilityEn: "Blaze")
check("T92b no correction for shared ability", lastSlots["oppA"]?.speciesEn == "Typhlosion")
// (c) おみとおし文からの連鎖: 判明文 → 主語の特性判明 → フォルム訂正
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Typhlosion", hpPercent: 100)
check("T92c frisk text consumed", translateBattleMessage("相手のバクフーンはサーナイトのサーナイトナイトをお見通しだ！"))
check("T92c item revealed", battleLog.contains("|-item|p1a: Gardevoir|Gardevoirite"))
check("T92c forme corrected", lastSlots["oppA"]?.speciesEn == "Typhlosion-Hisui")

// T93: ターン行の構造ガード (2026-11-21 battle_20261121_140658 の実例:
// 初回ラウンド全体が |turn|1 より前に記録された。ターン判定が遅れても、
// ラウンドの出来事より先にそのラウンドのターン行が出ることを担保する)
// (a) ターン行より前に技が来たら |turn|1 が先に出て、判定側の抑止が武装する
resetAll()
currentTurn = 0
emitLog("|move|p2a: Gengar|Shadow Ball")
check("T93a turn line first", battleLog == ["|turn|1", "|move|p2a: Gengar|Shadow Ball"])
check("T93a current turn", currentTurn == 1)
check("T93a suppress armed", suppressNextDetectorTurn)
// (b) 開始直後の繰り出しでは発火しない
resetAll()
currentTurn = 0
emitLog("|switch|p2a: Gengar|Gengar|100/100")
check("T93b no fire on switch", !battleLog.contains { $0.hasPrefix("|turn|") })
// (c) ラウンド途中では発火せず、同じ枠の 2 回目の技で次のターン行が先に出る
resetAll()
currentTurn = 0
emitLog("|turn|1")
emitLog("|move|p2a: Gengar|Shadow Ball")
emitLog("|move|p1a: Sneasler|Close Combat")
check("T93c no mid-round fire", battleLog.filter { $0.hasPrefix("|turn|") }.count == 1)
emitLog("|move|p2a: Gengar|Shadow Ball")
check("T93c next turn on repeat mover", (battleLog.lastIndex(of: "|turn|2") ?? -1) >= 0
      && (battleLog.lastIndex(of: "|turn|2") ?? -1) < (battleLog.lastIndex(of: "|move|p2a: Gengar|Shadow Ball") ?? -1))

// T94: 相性文の「効果は」脱落 + 濁点落ち + 「相手の」の字形崩れ
// (2026-11-21 battle_20261121_144858 の実例: 実文は「相手の
// ユキメノコに 効果は バツグンだ！」で、OCR は「伹手ユキメノコに
// パツグンだ！」と崩し、消費マッチから漏れて |-message| に残った)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Froslass", hpPercent: 100)
let t94 = translateBattleMessage("伹手ユキメノコにパツグンだ！")
check("T94 consumed", t94)
check("T94 supereffective", battleLog.contains("|-supereffective|p2a: Froslass"))

// T94: 発生源を特定できない回復のデバッグ記録 (2026-11-21
// battle_20261121_144858 の実例: タスキ判明済みのフシギバナに
// 発生源のない +33% の幻回復。当初は行を出し証拠だけを残す方針
// だったが、battle_20261121_224409 で幻回復が後続の喪失率表示
// まで狂わせたため、行を出さず証拠だけを残す方針に変更した)
// (a) 判明持ち物が回復系でなく、直前の技も回復系でない → 記録され、行は出ない
resetAll()
monStates["p2:Venusaur"] = MonState()
revealedItems["Venusaur"] = "きあいのタスキ"
lastMoveName = "Protect"; lastMoveLabel = "p2a: Venusaur"
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Venusaur", speciesEn: "Venusaur", fromPct: 1, toPct: 34, hpText: "34/100", force: true)
check("T94a heal suppressed", !battleLog.contains("|-heal|p2a: Venusaur|34/100"))
check("T94a no-source recorded", debugCaptureCalls.contains("heal_no_source"))
// (b) 自分の直前の技が回復技なら説明ありとして記録しない
resetAll()
monStates["p1:Blastoise"] = MonState()
lastMoveName = "Recover"; lastMoveLabel = "p1a: Blastoise"
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Blastoise", speciesEn: "Blastoise", fromPct: 30, toPct: 80, hpText: "80/100", force: true)
check("T94b heal emitted", battleLog.contains("|-heal|p1a: Blastoise|80/100"))
check("T94b explained by move", !debugCaptureCalls.contains("heal_no_source"))
// (c) オボンのみと推定できる回復は発生源つきになり、記録しない
resetAll()
monStates["p2:Swampert"] = MonState()
lastMoveName = "High Horsepower"; lastMoveLabel = "p2b: Swampert"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Swampert", speciesEn: "Swampert", fromPct: 40, toPct: 65, hpText: "65/100", force: true)
check("T94c sitrus attributed", battleLog.contains("|-heal|p2b: Swampert|65/100|[from] item: Sitrus Berry"))
check("T94c no record", !debugCaptureCalls.contains("heal_no_source"))

// T95: デバッグ記録の state はログに確定した HP を優先する
// (2026-11-21 battle_20261121_145658: 却下した誤読値 100% が
// 記録の state にそのまま写った)
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Venusaur", hpPercent: 100)
lastEmittedPct["oppA"] = 27
let exSlots = (debugStateExcerpt()["slots"] as? [String: Any]) ?? [:]
let exOppA = (exSlots["oppA"] as? [String: Any]) ?? [:]
check("T95 excerpt prefers committed", (exOppA["hpPct"] as? Int) == 27)

// T96: デフォルト帰属の繰り返しのデバッグ記録 (2026-11-21
// battle_20261121_150535 の実例: イエッサン♀への交代が取りこぼされ、
// 両枠が埋まったまま文が p1a へ帰属され続けた)
// (a) 1 回目では記録せず、2 回目で記録する。技行は既定枠へ出る
// (ランク変化の文は場にいない種族では保留されるため、実例どおり
// 技行で検証する)
resetAll()
teamEntries["Whimsicott"] = ["ability": "いたずらごころ"]
teamEntries["Indeedee-F"] = ["ability": "サイコメイカー"]
teamEntries["Armarouge"] = ["ability": "くだけるよろい"]
lastSlots["mineA"] = SlotState(speciesEn: "Whimsicott", hpPercent: 80)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
_ = translateBattleMessage("味方のイエッサンのサイコキネシス！")
check("T96 first no record", !debugCaptureCalls.contains("default_attribution"))
check("T96 defaulted to p1a", battleLog.contains("|move|p1a: Indeedee-F|Psychic"))
_ = translateBattleMessage("味方のイエッサンのはかいこうせん！")
check("T96 second records", debugCaptureCalls.contains("default_attribution"))

// T97: 相手のランク/レートのヘッダー併記 (記録側)。読み取れた場合のみ
// Battle started 行の直後に rank / rating 行が付き、読めていない場合は
// 付かない
resetAll()
trainerOpp = "Filliman"
oppRank = "ハイパーボール級"
oppRating = "1823"
let hdr97 = renderLogLine("|start")
check("T97 rank line", hdr97.contains("Filliman's rank: ハイパーボール級"))
check("T97 rating line", hdr97.contains("Filliman's rating: 1823"))
check("T97 after start line",
      hdr97.firstIndex(of: "Filliman's rank: ハイパーボール級")
        == (hdr97.firstIndex { $0.hasPrefix("Battle started between") } ?? -1) + 1)
resetAll()
trainerOpp = "Filliman"
let hdr97b = renderLogLine("|start")
check("T97 no rank when unread", !hdr97b.contains { $0.contains("'s rank:") })
check("T97 no rating when unread", !hdr97b.contains { $0.contains("'s rating:") })

// T98: header_mismatch の記録。ヘッダー6体に無い相手種族がプレートで
// 確定したら記録し、ヘッダー内の種族では記録しない。ヘッダーが
// 6体そろっていない場合は記録しない
resetAll()
headerOppTeam = ["Talonflame", "Sneasler", "Gardevoir", "Indeedee-F", "Armarouge", "Whimsicott"]
lastSlots["oppA"] = SlotState(speciesEn: "Talonflame", hpPercent: 100)
processPlates(["oppA": SlotState(speciesEn: "Kingambit", hpPercent: 100)])
processPlates(["oppA": SlotState(speciesEn: "Kingambit", hpPercent: 100)])
check("T98 switch emitted", battleLog.contains { $0.contains("|switch|p2a: Kingambit") })
check("T98 mismatch recorded", debugCaptureCalls.contains("header_mismatch"))
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
let callsBefore98 = debugCaptureCalls.count
processPlates(["oppB": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
processPlates(["oppB": SlotState(speciesEn: "Sneasler", hpPercent: 100)])
check("T98 in-header no record", debugCaptureCalls.count == callsBefore98)
resetAll()
headerOppTeam = ["Talonflame", "Sneasler"]
lastSlots["oppA"] = SlotState(speciesEn: "Talonflame", hpPercent: 100)
processPlates(["oppA": SlotState(speciesEn: "Kingambit", hpPercent: 100)])
processPlates(["oppA": SlotState(speciesEn: "Kingambit", hpPercent: 100)])
check("T98 partial header no record", !debugCaptureCalls.contains("header_mismatch"))

// T99: ターン行ガードの条件 (c)。最後のターン行以降に交代で入った
// 枠の最初の技は、区間に既に他の技がある場合に次のターン行を先行
// させる。区間の最初の技では発火しない (交代確定の遅れとの誤認防止)
resetAll()
currentTurn = 3
emitLog("|turn|3")
emitLog("|move|p1a: Gardevoir|Moonblast")
emitLog("|switch|p2a: Garchomp|Garchomp|100/100")
emitLog("|move|p2a: Garchomp|Earthquake")
check("T99a guard fired turn 4", battleLog.contains("|turn|4"))
check("T99a turn before move",
      (battleLog.firstIndex(of: "|turn|4") ?? 99)
        < (battleLog.firstIndex { $0.hasPrefix("|move|p2a: Garchomp") } ?? 99))
check("T99a suppress armed", suppressNextDetectorTurn)
resetAll()
currentTurn = 3
emitLog("|turn|3")
emitLog("|switch|p2a: Garchomp|Garchomp|100/100")
emitLog("|move|p2a: Garchomp|Earthquake")
check("T99b first move no fire", !battleLog.contains("|turn|4"))
resetAll()
currentTurn = 3
emitLog("|turn|3")
emitLog("|move|p1a: Gardevoir|Moonblast")
emitLog("|move|p2b: Sneasler|Ice Shard")
check("T99c non-entrant no fire", !battleLog.contains("|turn|4"))

// T100: switch_guard_drop の記録。交代要員選択中 (同じ側にひんし枠が
// あり交代待ち) に生きている枠の交代が確定すると、確定は破棄され、
// その事実が記録される。ひんし枠が無ければ通常どおり確定する
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 0)
faintedSlots["p1a"] = "Gardevoir"
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
fieldSeen["p1"] = ["Gardevoir", "Whimsicott"]
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 100)])
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 100)])
check("T100 drop recorded", debugCaptureCalls.contains("switch_guard_drop"))
check("T100 no switch emitted", !battleLog.contains { $0.contains("|switch|p1b: Indeedee-F") })
check("T100 occupant unchanged", lastSlots["mineB"]?.speciesEn == "Whimsicott")
resetAll()
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 100)])
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 100)])
check("T100 control switch emitted", battleLog.contains { $0.contains("|switch|p1b: Indeedee-F") })
check("T100 control no record", !debugCaptureCalls.contains("switch_guard_drop"))

// T101: ランク変化文の主語の絞り込み。文中に紛れた無関係な種族名
// (プレート名の混入等) へは変化を付けず、文法上の主語だけに付ける。
// 複合主語 (「Aと Bの」) は従来どおり全員に付ける
// (実例: battle_20261121_155801、くだけるよろいの防御低下が
//  イエッサン♀にも付いた)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
emittedSwitchKeys = ["p1:Indeedee-F", "p1:Armarouge"]
teamEntries = ["Indeedee-F": [:], "Armarouge": [:]]
_ = translateBattleMessage("イエッサングレンアルマのぼうぎょがさがった！")
check("T101 armarouge def drop", battleLog.contains("|-unboost|p1b: Armarouge|def|1"))
check("T101 no indeedee phantom", !battleLog.contains { $0.contains("Indeedee-F|def") })
check("T101 indeedee state clean", (monStates["p1:Indeedee-F"]?.boosts["def"] ?? 0) == 0)
check("T101 armarouge state", (monStates["p1:Armarouge"]?.boosts["def"] ?? 0) == -1)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
emittedSwitchKeys = ["p1:Indeedee-F", "p1:Armarouge"]
teamEntries = ["Indeedee-F": [:], "Armarouge": [:]]
_ = translateBattleMessage("グレンアルマのすばやさがぐーんとあがった！")
check("T101 armarouge spe boost", battleLog.contains("|-boost|p1b: Armarouge|spe|2"))
check("T101 no indeedee spe", !battleLog.contains { $0.contains("Indeedee-F|spe") })
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
emittedSwitchKeys = ["p1:Indeedee-F", "p1:Armarouge"]
fieldSeen = ["p1": ["Indeedee-F", "Armarouge"], "p2": ["Gengar", "Dragonite"]]
teamEntries = ["Indeedee-F": [:], "Armarouge": [:]]
_ = translateBattleMessage("グレンアルマとイエッサンのこうげきがさがった！")
check("T101 compound armarouge", battleLog.contains("|-unboost|p1b: Armarouge|atk|1"))
check("T101 compound indeedee", battleLog.contains("|-unboost|p1a: Indeedee-F|atk|1"))

// T101: 晴れの終了文。実機文面は「日差しが元に戻った！」で、終了分岐が
// 『戻った』で消費して |-weather|none が出ること。battle_20261121_155801
// の実例 (先頭に読みの重複が付いた崩れ「ひざ日差しが元に戻った！」)
// でも消費できること
resetAll()
check("T101 sun start", checkFieldText(text: "日差しが強くなった！") && battleLog.contains("|-weather|Sunny Day"))
check("T101 garbled sun end", checkFieldText(text: "ひざ日差しが元に戻った！") && battleLog.contains("|-weather|none"))

// T102: ログ画面経由の古い地形文は現行の地形を上書きしない
// (battle_20261121_161334: グラスフィールド下で対戦開始時の
//  サイコフィールド文が再適用され、サイコシード消費まで補完された)。
// 実況 (stale でない) の採用と、現行が空のときの復旧は従来どおり。
// なお上書きの採用には出所 (地形技・サージ特性の交代) が要る
// (battle_20261122_054802 で追加された確認ゲート。ここでは地形技の
// 使用を直近の技として与えて実況の上書きを再現する)
resetAll()
teamEntries["Sneasler"] = ["ability": "かるわざ", "item": "サイコシード"]
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
_ = checkFieldText(text: "足下に草が生い茂った！")
check("T102 grassy live", logFieldTerrain == "Grassy")
_ = checkFieldText(text: "足下が不思議な感じになった！", fromLogScreen: true)
check("T102 stale blocked", logFieldTerrain == "Grassy")
check("T102 no phantom fieldstart", !battleLog.contains("|-fieldstart|move: Psychic Terrain"))
check("T102 no phantom seed boost", (monStates["p1:Sneasler"]?.boosts["spd"] ?? 0) == 0)
lastMoveName = "Psychic Terrain"; lastMoveMsgAt = Date()
_ = checkFieldText(text: "足下が不思議な感じになった！")
check("T102 live adopts", logFieldTerrain == "Psychic")
resetAll()
_ = checkFieldText(text: "足下に草が生い茂った！", fromLogScreen: true)
check("T102 stale recovery when empty", logFieldTerrain == "Grassy")
// T102b: 緩い開始分岐の絞り込み。地形文らしい断片が無い文では倒れず、
// 記録済みの崩れ (下か不態議) では従来どおり拾う
resetAll()
_ = checkFieldText(text: "フィールドの様子が変わった感じになった！")
check("T102b fragmentless no flip", logFieldTerrain == "")
_ = checkFieldText(text: "下か不態議な感じになった！")
check("T102b garble still flips", logFieldTerrain == "Psychic")

// T103: オーラ特性の告知 (battle_20261121_161334 の実例文と崩れ文)
resetAll()
speciesDict.append(E("フラエッテ", "Floette"))
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 100)
emittedSwitchKeys = ["p2:Rillaboom", "p2:Floette"]
check("T103 garbled aura consumed", translateBattleMessage("あいて相手のフラエッテははなフェアリーオーラを放っている！"))
check("T103 aura ability line", battleLog.contains("|-ability|p2b: Floette|Fairy Aura"))
check("T103 clean aura consumed", translateBattleMessage("相手のフラエッテはフェアリーオーラを放っている！"))

// T104: ワイドガード (使用告知が確認文として一律に消費され、ログに一切出なかった)
moveNameOrig[normalize("ワイドガード")] = "ワイドガード"; moveJa2En["ワイドガード"] = "Wide Guard"
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
check("T104a use consumed", translateBattleMessage("相手のグレンアルマのワイドガード！"))
check("T104a move line", battleLog.contains("|move|p2a: Armarouge|Wide Guard"))
check("T104a sidestart line", battleLog.contains("|-sidestart|p2|move: Wide Guard"))
check("T104a state tracked", sideCondSetTurns["p2"]?["Wide Guard"] != nil)
resetAll()
currentTurn = 2
lastSlots["mineA"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
check("T104b own use move line", translateBattleMessage("グレンアルマのワイドガード！") && battleLog.contains("|move|p1a: Armarouge|Wide Guard") && battleLog.contains("|-sidestart|p1|move: Wide Guard"))
resetAll()
currentTurn = 2
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
check("T104c block consumed", translateBattleMessage("サーナイトはワイドガードで守られた！"))
check("T104c activate line", battleLog.contains("|-activate|p1a: Gardevoir|move: Wide Guard"))
check("T104c no bogus move", !battleLog.contains("|move|p1a: Gardevoir|Wide Guard"))
lastSingleActAt = [:]
check("T104d mamorare variant", translateBattleMessage("サーナイトはワイドガードでまもられた！") && battleLog.filter { $0.contains("-activate") }.count == 2)
resetAll()
currentTurn = 2
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
let t104before = battleLog.count
check("T104e quick guard block still consumed", translateBattleMessage("サーナイトはファストガードで守られた！") && battleLog.count == t104before)

// T105: どくびし (設置・層数・吸収・救済・描画)。まきびしは既存実装
speciesDict.append(E("ドヒドイデ", "Toxapex"))
speciesAbilityMap["Toxapex"] = ["Merciless", "Limber", "Regenerator"]
speciesAbilityMap["Weezing-Galar"] = ["Levitate", "Neutralizing Gas", "Mist Surge"]
pvSpeciesTypes["Toxapex"] = ["Water", "Poison"]
pvSpeciesTypes["Weezing-Galar"] = ["Poison", "Fairy"]
resetAll()
applyMoveField("どくびし", side: "p1")
check("T105a sidestart", battleLog.contains("|-sidestart|p2|move: Toxic Spikes"))
check("T105a layer 1", battleHazards["p2"]?["Toxic Spikes"] == 1)
applyMoveField("どくびし", side: "p1")
check("T105a layer 2", battleHazards["p2"]?["Toxic Spikes"] == 2)
applyMoveField("どくびし", side: "p1")
check("T105a capped at 2", battleHazards["p2"]?["Toxic Spikes"] == 2)
resetAll()
battleHazards["p1"] = ["Toxic Spikes": 2]
recordSwitchIn(side: "p1", slot: "p1a", speciesEn: "Toxapex")
check("T105b absorb sideend", battleLog.contains("|-sideend|p1|move: Toxic Spikes"))
check("T105b hazards cleared", battleHazards["p1"]?["Toxic Spikes"] == nil)
resetAll()
battleHazards["p2"] = ["Toxic Spikes": 1]
recordSwitchIn(side: "p2", slot: "p2a", speciesEn: "Weezing-Galar")
check("T105c levitate-pool unrevealed keeps spikes", battleHazards["p2"]?["Toxic Spikes"] == 1)
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Toxapex", hpPercent: 100)
battleHazards["p2"] = ["Toxic Spikes": 1]
check("T105d absorb text consumed", translateBattleMessage("相手のドヒドイデはどくびしを吸収した！"))
check("T105d sideend", battleLog.contains("|-sideend|p2|move: Toxic Spikes"))
resetAll()
check("T105e salvage set", salvageField(in: "相手のあしもとにどくびしがばらまかれた！") && battleLog.contains("|-sidestart|p2|move: Toxic Spikes"))
check("T105f render start", renderLogLine("|-sidestart|p2|move: Toxic Spikes").contains { $0.contains("Poison spikes were scattered") })
check("T105f render end", renderLogLine("|-sideend|p1|move: Toxic Spikes").contains { $0.contains("poison spikes disappeared") })
check("T105f spikes render intact", renderLogLine("|-sidestart|p2|move: Spikes").contains { $0.contains("(Spikes were scattered") })

// T106: battle_20261121_224409 の5件 (幻回復/はたき落とし崩れ/
// ワイドガード告知/まもる確認文/訂正の追記/くだけるよろい)
speciesDict.append(E("クチート", "Mawile"))
resetAll()
currentTurn = 5
teamEntries["Indeedee-F"] = ["item": "ゴツゴツメット", "ability": "サイコメイカー"]
lastEmittedPct["mineA"] = 82
lastMoveName = "Knock Off"; lastMoveLabel = "p2b: Mawile"
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 82, toPct: 100, hpText: "177/177", force: true)
check("T106a heal suppressed", !battleLog.contains("|-heal|p1a: Indeedee-F|177/177"))
check("T106a emitted pct rolled back", lastEmittedPct["mineA"] == 82)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 82, toPct: 0, hpText: "0/177", force: true)
check("T106a real damage still emitted", battleLog.contains("|-damage|p1a: Indeedee-F|0/177"))
resetAll()
currentTurn = 3
lastEmittedPct["mineA"] = 40
lastMoveName = "Recover"; lastMoveLabel = "p1a: Gardevoir"
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 40, toPct: 90, hpText: "130/145", force: true)
check("T106b self heal emitted", battleLog.contains("|-heal|p1a: Gardevoir|130/145"))
resetAll()
currentTurn = 4
wishSetTurn["p1"] = 3
lastEmittedPct["mineB"] = 50
lastMoveName = "Psychic"; lastMoveLabel = "p2a: Indeedee"
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Whimsicott", speciesEn: "Whimsicott", fromPct: 50, toPct: 100, hpText: "167/167", force: true)
check("T106c wish heal emitted", battleLog.contains("|-heal|p1b: Whimsicott|167/167"))
resetAll()
currentTurn = 5
teamEntries["Indeedee-F"] = ["item": "ゴツゴツメット", "ability": "サイコメイカー"]
lastSlots["oppB"] = SlotState(speciesEn: "Mawile", hpPercent: 70)
lastSlots["mineA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 82)
check("T106d knock off garbled consumed", translateBattleMessage("相手のクチートはイエッサンのゴッゴツメットをはたき落とした！"))
check("T106d item line", battleLog.contains("|-item|p1a: Indeedee-F|Rocky Helmet"))
resetAll()
let t106before = battleLog.count
check("T106e wide guard ambient consumed", translateBattleMessage("味方の周りをワイドガードが守っている！") && battleLog.count == t106before)
resetAll()
currentTurn = 3
lastSlots["oppB"] = SlotState(speciesEn: "Mawile", hpPercent: 70)
emitLog("|move|p2b: Mawile|Protect")
check("T106f protect block consumed", translateBattleMessage("相手のクチートは攻撃から身を守った！"))
check("T106f activate line", battleLog.contains("|-activate|p2b: Mawile|move: Protect"))
resetAll()
currentTurn = 5
actionSeq = 9
lastEmittedPct["oppB"] = 55
lastDamageTime["oppB"] = Date(timeIntervalSinceNow: -60)
lastDamageSeq["oppB"] = 3
lastMoveMsgAt = Date(timeIntervalSinceNow: -30)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Mawile", speciesEn: "Mawile", fromPct: 55, toPct: 53, hpText: "53/100", force: true)
check("T106g correction silent", !battleLog.contains("|-damage|p2b: Mawile|53/100"))
check("T106g value adopted", lastEmittedPct["oppB"] == 53)
actionSeq = 10
lastDamageTime["oppB"] = Date()
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Mawile", speciesEn: "Mawile", fromPct: 53, toPct: 51, hpText: "51/100", force: true)
check("T106g fresh small damage emitted", battleLog.contains("|-damage|p2b: Mawile|51/100"))
resetAll()
currentTurn = 4
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
emitLog("|switch|p1b: Armarouge|Armarouge|161/161")
check("T106h weak armor def", translateBattleMessage("グレンアルマの防御が下がった！") && battleLog.contains("|-unboost|p1b: Armarouge|def|1"))
check("T106h weak armor spe", translateBattleMessage("グレンアルマの素早さがぐーんと上がった！") && battleLog.contains("|-boost|p1b: Armarouge|spe|2"))

// T107: はたき落としの持ち物名 OCR 崩れを loose 照合で救済する
// (持ち物が未判明でも、崩れた名前から復元して記録できること)
resetAll()
currentTurn = 5
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 82)
lastSlots["mineB"] = SlotState(speciesEn: "Mawile", hpPercent: 70)
check("T107 knock off loose consumed", translateBattleMessage("相手のイエッサンのゴッゴツメットをはたき落とした！"))
check("T107 item recovered", battleLog.contains("|-item|p2a: Indeedee-F|Rocky Helmet"))

// T108: battle_20261121_230402 (vs Wizzle 戦) の回帰テスト
// (a) 大きな回復の却下が持続した場合の状態訂正: 内部状態 7% に対して
// 満タンの正読が 2 ターン続いたら、行を出さずに値を取り込む。
// その後の実ダメージは正しい基準から計算される
resetAll()
currentTurn = 5
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 7, hpCur: 10, hpMax: 145)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 7; monStates["p1:Gardevoir"]!.hpText = "10/145"
lastEmittedPct["mineA"] = 7
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 7, toPct: 100, hpText: "145/145", force: true)
check("T108a jump rejected first", !battleLog.contains { $0.contains("-heal|p1a: Gardevoir") } && suspectJump["mineA"]?.toPct == 100)
currentTurn = 6
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 7, toPct: 100, hpText: "145/145", force: true)
check("T108a adopted silently next turn", !battleLog.contains { $0.contains("-heal|p1a: Gardevoir") } && monStates["p1:Gardevoir"]?.hpPercent == 100 && lastEmittedPct["mineA"] == 100)
currentTurn = 7
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 37, hpText: "53/145", force: true)
check("T108a real damage from corrected base", battleLog.contains("|-damage|p1a: Gardevoir|53/145"))
// (b) 交代行の直後 (技がまだ出ていない) の大きな低下は誤読の疑いで
// 保留する。技が出た後の大きな低下は通常どおり出す
resetAll()
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 100
lastEmittedPct["mineA"] = 100
emitLog("|switch|p2a: Archaludon|Archaludon|100/100")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 7, hpText: "10/145", force: true)
check("T108b drop after switch held as suspect", !battleLog.contains { $0.contains("-damage|p1a: Gardevoir") } && suspectJump["mineA"]?.toPct == 7)
resetAll()
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100, hpCur: 145, hpMax: 145)
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 100
lastEmittedPct["mineA"] = 100
emitLog("|switch|p2a: Archaludon|Archaludon|100/100")
emitLog("|move|p2a: Archaludon|Flash Cannon")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 7, hpText: "10/145", force: true)
check("T108b drop after move emitted", battleLog.contains("|-damage|p1a: Gardevoir|10/145"))
// (c) 初登場の交代では、交代行の直後に同値の被ダメ行を重ねない
resetAll()
currentTurn = 1
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 100)
fieldSeen["p1"] = ["Gardevoir", "Whimsicott"]
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 41, hpCur: 72, hpMax: 177)])
processPlates(["mineB": SlotState(speciesEn: "Indeedee-F", hpPercent: 41, hpCur: 72, hpMax: 177)])
check("T108c first entry switch", battleLog.contains("|switch|p1b: Indeedee-F|Indeedee-F|177/177"))
check("T108c no duplicate damage", !battleLog.contains { $0.contains("-damage|p1b: Indeedee-F") })
// (d) フィールド特性のターン一致帰属: 交代確定が 30 秒窓を超えて
// 遅れても、同じターンに入った交代なら特性を帰属する
resetAll()
currentTurn = 1
speciesAbilityMap["Indeedee-F"] = ["Synchronize", "Psychic Surge"]
speciesAbilityMap["Floette-Eternal"] = ["Fairy Aura"]
speciesAbilityMap["Floette"] = ["Flower Veil", "Symbiosis"]
setTerrain("Psychic", via: "足下が不思議な感じになった！")
fieldTerrainSetAt = Date(timeIntervalSinceNow: -45)
recordSwitchIn(side: "p1", slot: "p1b", speciesEn: "Indeedee-F")
attributeFieldAbilities()
check("T108d surge attributed by turn", battleLog.contains("|-ability|p1b: Indeedee-F|Psychic Surge"))
// (e) ひんし枠への文救済: 場にいない種族の文は、ひんし済みの枠へ
// 繰り出しとして登録してから帰属する (既定枠への誤帰属を防ぐ)
resetAll()
currentTurn = 3
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 0)
monStates["p1:Indeedee-F"] = MonState(); monStates["p1:Indeedee-F"]!.hpPercent = 0
faintedSlots["p1b"] = "Indeedee-F"
teamEntries["Whimsicott"] = ["ability": "いたずらごころ", "item": "バビリのみ"]
moveNameOrig[normalize("アンコール")] = "アンコール"; moveJa2En["アンコール"] = "Encore"
check("T108e encore consumed", translateBattleMessage("エルフーンのアンコール！"))
check("T108e switch rescued into fainted slot", battleLog.contains("|switch|p1b: Whimsicott|Whimsicott|100/100"))
check("T108e move attributed to p1b", battleLog.contains("|move|p1b: Whimsicott|Encore"))
check("T108e no p1a misattribution", !battleLog.contains("|move|p1a: Whimsicott|Encore"))
// (f) アンコールの効果行: 対象への |-start| として記録し、対象自身の
// 技使用とは誤読しない
resetAll()
currentTurn = 3
lastSlots["oppB"] = SlotState(speciesEn: "Sneasler", hpPercent: 83)
check("T108f encore effect consumed", translateBattleMessage("相手のオオニューラはアンコールを受けた！"))
check("T108f start line", battleLog.contains("|-start|p2b: Sneasler|move: Encore"))
check("T108f no bogus move", !battleLog.contains("|move|p2b: Sneasler|Encore"))
// (g) メガ反応文: 「リングが」が読み落ちても、ストーンが引ければ
// 反応として処理する
resetAll()
currentTurn = 1
speciesDict.append(E("ライチュウ", "Raichu"))
itemDict[normalize("ライチュウナイトX")] = "ライチュウナイトX"; itemJa2En["ライチュウナイトX"] = "Raichunite X"
lastSlots["oppA"] = SlotState(speciesEn: "Raichu", hpPercent: 100)
oppTeamSeen = ["Raichu"]
check("T108g mega reaction consumed", translateBattleMessage("相手のライチュウのライチュウナイトXとWizzleの反応した！"))
check("T108g stone recorded", battleLog.contains { $0.contains("|-item|p2a: Raichu|Raichunite X") })
// (h) エレキフィールドの終了文 (消え去った) で地形が消える
resetAll()
currentTurn = 7
setTerrain("Electric", via: "足下に電気がかけめぐった！")
check("T108h terrain end consumed", checkFieldText(text: "足下の電気が消え去った！"))
check("T108h fieldend line", battleLog.contains("|-fieldend|move: Electric Terrain"))
check("T108h state cleared", logFieldTerrain.isEmpty)
// (i) 失敗行への主体付与: 直前の技の使用者が付く
resetAll()
currentTurn = 5
lastSlots["oppB"] = SlotState(speciesEn: "Sneasler", hpPercent: 83)
_ = translateBattleMessage("相手のオオニューラのまもる！")
check("T108i fail has subject", translateBattleMessage("しかしうまく決まらなかった！") && battleLog.contains("|-fail|p2b: Sneasler"))
// (j) ワイドガードの周囲告知 (相手側): ルビ混入の崩れ文と、除去後の
// きれいな文のどちらも消費され、行は出ない
resetAll()
currentTurn = 3
lastSlots["oppA"] = SlotState(speciesEn: "Pelipper", hpPercent: 100)
check("T108j ambient garbled consumed", translateBattleMessage("あいてまわ相手の周りをまもワイドガードが守っている！"))
check("T108j ambient clean consumed", translateBattleMessage("相手の周りをワイドガードが守っている！"))
check("T108j no lines", battleLog.isEmpty)

// T109: battle_20261121_233243 (vs brim 戦) の回帰テスト
speciesDict.append(E("ゴリランダー", "Rillaboom"))
speciesDict.append(E("マフォクシー", "Delphox"))
itemDict[normalize("いのちのたま")] = "いのちのたま"; itemJa2En["いのちのたま"] = "Life Orb"
// (a) 自己ダメージの分類: 自分の技の直後の 10% は いのちのたま、
// 反動技の残りは技の反動として [from] が付き、判明も記録される
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
monStates["p2:Rillaboom"] = MonState()
lastEmittedPct["oppA"] = 100
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Wood Hammer"; lastMoveMsgAt = Date()
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 90, hpText: "90/100", force: true)
check("T109a life orb item line", battleLog.contains("|-item|p2a: Rillaboom|Life Orb"))
check("T109a life orb from", battleLog.contains("|-damage|p2a: Rillaboom|90/100|[from] item: Life Orb"))
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 90, toPct: 53, hpText: "53/100", force: true)
check("T109a recoil from", battleLog.contains("|-damage|p2a: Rillaboom|53/100|[from] move: Wood Hammer"))
// (b) グラスフィールド開始文: アンカーが両方崩れた文でも
// 「おいしげ」で拾い、開始行が出る
resetAll()
currentTurn = 0
check("T109b garbled grassy consumed", checkFieldText(text: "定下に草かおいしげった！"))
check("T109b grassy fieldstart", battleLog.contains("|-fieldstart|move: Grassy Terrain"))
// (c) 開始直後の上書き: 先発 (ターン 0 で記録) は、上書きされた側の
// 地形に対しても特性が帰属する
resetAll()
currentTurn = 0
speciesAbilityMap["Rillaboom"] = ["Overgrow", "Grassy Surge"]
setTerrain("Grassy", via: "足下に草がおいしげった！")
setTerrain("Psychic", via: "足下が不思議な感じになった！")
recordSwitchIn(side: "p2", slot: "p2a", speciesEn: "Rillaboom")
attributeFieldAbilities()
check("T109c surge attributed to overwritten terrain", battleLog.contains("|-ability|p2a: Rillaboom|Grassy Surge"))
// (d) トリックルーム終了: 管理側が先に終了行を出していても、終了文は
// 消費され、|-message| に残らない (終了行は 1 本だけ)
resetAll()
currentTurn = 5
emitLog("|-fieldstart|move: Trick Room")
emitLog("|-fieldend|move: Trick Room")
check("T109d end text consumed after fieldend", checkFieldText(text: "ゆがんだ時空が元に戻った！"))
check("T109d single fieldend", battleLog.filter { $0.contains("-fieldend|move: Trick Room") }.count == 1)
// (e) 初登場の交代行と同値のダメージ行は重複として出ない。
// 設置物の [from] 行は従来どおり出る
resetAll()
currentTurn = 2
lastSlots["oppB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 52)
fieldSeen["p2"] = ["Rillaboom", "Farigiraf"]
monStates["p2:Farigiraf"] = MonState(); monStates["p2:Farigiraf"]!.hpPercent = 52
processPlates(["oppB": SlotState(speciesEn: "Delphox", hpPercent: 76)])
processPlates(["oppB": SlotState(speciesEn: "Delphox", hpPercent: 76)])
check("T109e first entry switch", battleLog.contains("|switch|p2b: Delphox|Delphox|100/100"))
// 交代ブロック自体が入場時ダメージを 1 回だけ記録する (正規の記録)
check("T109e entry damage recorded once", battleLog.filter { $0.contains("-damage|p2b: Delphox") }.count == 1)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Delphox", speciesEn: "Delphox", fromPct: 100, toPct: 76, hpText: "76/100", force: true)
check("T109e duplicate suppressed", battleLog.filter { $0.contains("-damage|p2b: Delphox") }.count == 1)
resetAll()
currentTurn = 2
lastSlots["oppB"] = SlotState(speciesEn: "Farigiraf", hpPercent: 52)
fieldSeen["p2"] = ["Rillaboom", "Farigiraf"]
monStates["p2:Farigiraf"] = MonState(); monStates["p2:Farigiraf"]!.hpPercent = 52
processPlates(["oppB": SlotState(speciesEn: "Delphox", hpPercent: 76)])
processPlates(["oppB": SlotState(speciesEn: "Delphox", hpPercent: 76)])
pendingStatusFrom["p2:Delphox"] = ("Stealth Rock", Date())
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Delphox", speciesEn: "Delphox", fromPct: 100, toPct: 76, hpText: "76/100", force: true)
check("T109e hazard line kept", battleLog.contains("|-damage|p2b: Delphox|76/100|[from] Stealth Rock"))
// (f) 確定待ちの静定時間: 1.5 秒では出ず、2.0 秒を超えると出る
resetAll()
currentTurn = 4
lastSlots["oppB"] = SlotState(speciesEn: "Delphox", hpPercent: 30)
monStates["p2:Delphox"] = MonState(); monStates["p2:Delphox"]!.hpPercent = 30; monStates["p2:Delphox"]!.hpText = "30/100"
lastEmittedPct["oppB"] = 76
pendingDamagePct["oppB"] = 30
pendingDamageSince["oppB"] = Date(timeIntervalSinceNow: -1.5)
flushPendingDamage()
check("T109f not flushed at 1.5s", !battleLog.contains { $0.contains("-damage|p2b: Delphox") })
pendingDamageSince["oppB"] = Date(timeIntervalSinceNow: -2.1)
flushPendingDamage()
check("T109f flushed after 2s", battleLog.contains("|-damage|p2b: Delphox|30/100"))

// T110: オボンのみの発動取りこぼしの監視 (battle_20261121_233243)
// 条件 (半分以下) を跨ぐ低下の後、回復が無いまま次の被弾に進んだら
// 証拠記録が残る。回復が記録されれば記録は残らない
resetAll()
currentTurn = 4
speciesDict.append(E("リキキリン", "Farigiraf"))
lastSlots["oppA"] = SlotState(speciesEn: "Farigiraf", hpPercent: 52)
monStates["p2:Farigiraf"] = MonState(); monStates["p2:Farigiraf"]!.hpPercent = 52
lastEmittedPct["oppA"] = 52
debugCaptureCalls = []
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Farigiraf", speciesEn: "Farigiraf", fromPct: 52, toPct: 7, hpText: "7/100", force: true)
check("T110 watch set, no record yet", sitrusWatch["p2:Farigiraf"] == 7 && !debugCaptureCalls.contains("berry_activation_suspect"))
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Farigiraf", speciesEn: "Farigiraf", fromPct: 7, toPct: 0, hpText: "0/100", force: true)
check("T110 suspect recorded at faint", debugCaptureCalls.contains("berry_activation_suspect") && sitrusWatch["p2:Farigiraf"] == nil)
resetAll()
currentTurn = 4
lastSlots["oppA"] = SlotState(speciesEn: "Farigiraf", hpPercent: 52)
monStates["p2:Farigiraf"] = MonState(); monStates["p2:Farigiraf"]!.hpPercent = 52
lastEmittedPct["oppA"] = 52
debugCaptureCalls = []
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Farigiraf", speciesEn: "Farigiraf", fromPct: 52, toPct: 7, hpText: "7/100", force: true)
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Farigiraf", speciesEn: "Farigiraf", fromPct: 7, toPct: 32, hpText: "32/100", force: true)
check("T110 heal clears watch silently", sitrusWatch["p2:Farigiraf"] == nil && !debugCaptureCalls.contains("berry_activation_suspect"))

// T111: battle_20261121_234913 (vs zayblicki 戦) の回帰テスト
// (a) メガ反応文: 種族名が落ちてストーン名だけが残った文でも、種族は
// ストーンから引く (リザードナイトY -> Charizard。Charmeleon と誤認しない)
resetAll()
currentTurn = 1
_ = translateBattleMessage("相手のリザードナイトYとzayblickiの反応した！")
check("T111a stone resolves species", battleLog.contains("|-item|p2a: Charizard|Charizardite Y"))
check("T111a no charmeleon", !battleLog.contains { $0.contains("Charmeleon") })
check("T111a pending mega species", pendingMegaSpecies["p2"] == "Charizard")
// (b) 詳細画面の文は対戦文として処理しない (消費のみで、帰属も行も無い)
resetAll()
currentTurn = 1
debugCaptureCalls = []
let logCountBefore111 = battleLog.count
_ = translateBattleMessage("特性もうか100%リザードナイトY持ち物つよさの表示オフ06:43戻る")
_ = translateBattleMessage("特性もうか100%リザードナイトY持ち物つよさの表示オフ06:43戻る")
check("T111b detail text consumed silently", battleLog.count == logCountBefore111 && !debugCaptureCalls.contains("default_attribution"))

// T112: dmg イベントの amt 誤帰属と反動イベント (battle_20261121_233243)
// (a) 交代行の % 形式 (100/100) を基準にした実数差は作らない。
// 基準と現在の最大 HP が一致する場合だけ amt を使う
resetAll()
currentTurn = 2
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
monStates["p1:Indeedee-F"] = MonState()
lastEmittedPct["mineB"] = 100
battleEvents = []; lastDmgEventPrevExact = [:]
lastExactHp["p1:Indeedee-F"] = [100, 100]
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Wood Hammer"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 100, toPct: 21, hpText: "37/177", force: true)
let evA = battleEvents.last { $0.contains("\"k\":\"dmg\"") } ?? ""
check("T112a no bogus amt", evA.contains("\"pct\":79") && !evA.contains("\"amt\""))
resetAll()
currentTurn = 2
lastSlots["mineB"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
monStates["p1:Indeedee-F"] = MonState()
lastEmittedPct["mineB"] = 100
battleEvents = []; lastDmgEventPrevExact = [:]
lastExactHp["p1:Indeedee-F"] = [177, 177]
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Wood Hammer"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Indeedee-F", speciesEn: "Indeedee-F", fromPct: 100, toPct: 21, hpText: "37/177", force: true)
let evB = battleEvents.last { $0.contains("\"k\":\"dmg\"") } ?? ""
check("T112a exact amt kept", evB.contains("\"amt\":140,\"max\":177"))
// (b) 反動は atk == def の dmg イベントとして出る (推定エンジンとの契約)
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
monStates["p2:Rillaboom"] = MonState()
lastEmittedPct["oppA"] = 100
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Wood Hammer"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 90, hpText: "90/100", force: true)
let evC = battleEvents.last { $0.contains("\"atk\":\"p2a: Rillaboom\",\"def\":\"p2a: Rillaboom\"") } ?? ""
check("T112b recoil event emitted", evC.contains("\"k\":\"dmg\"") && evC.contains("\"pct\":10"))

// T113: battle_20261121_234913 (vs zayblicki 戦) の回帰テスト
// (a) 両軍に同種族がいる場合の自己変化は、直前の技の使用者に付く
resetAll()
currentTurn = 2
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 79)
lastSlots["oppB"] = SlotState(speciesEn: "Charizard", hpPercent: 74)
monStates["p1:Charizard"] = MonState(); monStates["p2:Charizard"] = MonState()
lastMoveLabel = "p2b: Charizard"; lastMoveName = "Ancient Power"; lastMoveMsgAt = Date()
_ = translateBattleMessage("リザードンのこうげきが上がった！")
check("T113a omniboost on user", monStates["p2:Charizard"]?.boosts["atk"] == 1 && (monStates["p1:Charizard"]?.boosts["atk"] ?? 0) == 0)
// (b) 同じ技で同じ対象に別の相性行が来たら、相性行の無い被ダメ対象へ付け替える
resetAll()
speciesDict.append(E("フシギバナ", "Venusaur"))
currentTurn = 8
actionSeq = 5
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Venusaur", hpPercent: 100)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Venusaur"] = MonState()
lastEmittedPct["mineA"] = 100; lastEmittedPct["mineB"] = 100
lastMoveLabel = "p2b: Charizard"; lastMoveName = "Heat Wave"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 100, toPct: 39, hpText: "61/157", force: true)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Garchomp", speciesEn: "Garchomp", fromPct: 100, toPct: 75, hpText: "139/185", force: true)
_ = translateBattleMessage("フシギバナに効果はバツグンだ！")
_ = translateBattleMessage("フシギバナに効果はいまひとつだ！")
check("T113b supereffective on venusaur", battleLog.contains("|-supereffective|p1b: Venusaur"))
check("T113b resisted reassigned to garchomp", battleLog.contains("|-resisted|p1a: Garchomp") && !battleLog.contains("|-resisted|p1b: Venusaur"))
// (c) ひるみ文は |-cant|flinch になる
resetAll()
currentTurn = 9
lastSlots["oppB"] = SlotState(speciesEn: "Sneasler", hpPercent: 56)
monStates["p2:Sneasler"] = MonState()
check("T113c flinch consumed", translateBattleMessage("相手のオオニューラはひるんで技がだせない！"))
check("T113c flinch line", battleLog.contains("|-cant|p2b: Sneasler|flinch"))
// (d) 起床文 (目→自 の崩れ) は |-curestatus|slp になる
resetAll()
currentTurn = 8
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 25)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.status = "slp"
check("T113d wake consumed", translateBattleMessage("ガブリアスは自を覚ました！"))
check("T113d curestatus line", battleLog.contains("|-curestatus|p1a: Garchomp|slp") && (monStates["p1:Garchomp"]?.status ?? "x") == "")
// (e) まもるの技行が無いターンの確認文は消費するが行は出ない
resetAll()
currentTurn = 3
lastSlots["oppB"] = SlotState(speciesEn: "Mawile", hpPercent: 70)
check("T113e orphan protect consumed", translateBattleMessage("相手のクチートは攻撃から身を守った！"))
check("T113e no activate line", !battleLog.contains { $0.contains("-activate") && $0.contains("Protect") })

// T114: battle_20261122_050512 (vs Curtle 戦) の回帰テスト
// (a) 交代行の HP は入場時点の値、入場までの被弾は補完行が担う
resetAll()
currentTurn = 1
lastSlots["mineB"] = SlotState(speciesEn: "Incineroar", hpPercent: 100, hpCur: 202, hpMax: 202)
monStates["p1:Garchomp"] = MonState()
processPlates(["mineB": SlotState(speciesEn: "Garchomp", hpPercent: 84, hpCur: 156, hpMax: 185)])
processPlates(["mineB": SlotState(speciesEn: "Garchomp", hpPercent: 84, hpCur: 156, hpMax: 185)])
check("T114a switch shows entry hp", battleLog.contains("|switch|p1b: Garchomp|Garchomp|185/185"))
check("T114a compensation damage line", battleLog.contains("|-damage|p1b: Garchomp|156/185"))
// (b) 解決中の技がある大きな低下は保留しない / 技が無ければ保留する
resetAll()
currentTurn = 2
monStates["p1:Incineroar"] = MonState(); monStates["p1:Incineroar"]!.hpPercent = 100
lastEmittedPct["mineB"] = 100; lastSwitchEmitSeq = 5; lastMoveEmitSeq = 3
lastMoveLabel = "p2b: Sneasler"; lastMoveName = "Close Combat"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 100, toPct: 25, hpText: "50/202", force: true)
check("T114b in-flight move damage emitted", battleLog.contains("|-damage|p1b: Incineroar|50/202"))
resetAll()
currentTurn = 2
monStates["p1:Incineroar"] = MonState(); monStates["p1:Incineroar"]!.hpPercent = 100
lastEmittedPct["mineB"] = 100; lastSwitchEmitSeq = 5; lastMoveEmitSeq = 3
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 100, toPct: 25, hpText: "50/202", force: true)
check("T114b no move still suspects", !battleLog.contains("|-damage|p1b: Incineroar|50/202") && suspectJump["mineB"] != nil)
// (c) 判明オボンの回復は幅を広げて帰属させる / 未判明の小幅は帰属させない
resetAll()
teamEntries["Incineroar"] = ["item": "オボンのみ"]
check("T114c known sitrus wide window", healSource(plateName: "mineB", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 25, toPct: 41)?.label == "item: Sitrus Berry")
resetAll()
check("T114c unknown item narrow window", healSource(plateName: "mineB", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 25, toPct: 41) == nil)
check("T114c unknown item normal window", healSource(plateName: "mineB", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 25, toPct: 50)?.label == "item: Sitrus Berry")
// (d) 疑わしい基準値からの回復は状態訂正として取り込む / 通常基準では抑止する
resetAll()
currentTurn = 2
monStates["p1:Incineroar"] = MonState()
lastEmittedPct["mineB"] = 25; suspectJump["mineB"] = (toPct: 25, turn: 2, hpText: "51/202")
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 25, toPct: 41, hpText: "83/202", force: true)
check("T114d heal adopted as correction", !battleLog.contains { $0.hasPrefix("|-heal|") } && lastEmittedPct["mineB"] == 41 && (monStates["p1:Incineroar"]?.hpPercent ?? -1) == 41)
resetAll()
currentTurn = 2
monStates["p1:Incineroar"] = MonState()
lastEmittedPct["mineB"] = 25
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 25, toPct: 41, hpText: "83/202", force: true)
check("T114d trusted baseline still suppresses", !battleLog.contains { $0.hasPrefix("|-heal|") } && lastEmittedPct["mineB"] == 25)
// (e) 特性行の妥当性ガード
resetAll()
speciesAbilityMap["Charizard"] = ["Blaze", "Solar Power"]
speciesAbilityMap["Charizard-Mega-X"] = ["Tough Claws"]
speciesAbilityMap["Charizard-Mega-Y"] = ["Drought"]
speciesAbilityMap["Incineroar"] = ["Blaze", "Intimidate"]
check("T114e impossible ability rejected", !abilityLinePlausible("|-ability|p1a: Charizard|Intimidate"))
check("T114e mega ability allowed", abilityLinePlausible("|-ability|p1a: Charizard|Drought"))
check("T114e own ability allowed", abilityLinePlausible("|-ability|p1b: Incineroar|Intimidate"))
check("T114e trace species exempt", abilityLinePlausible("|-ability|p1a: Gardevoir|Intimidate"))
check("T114e unknown species allowed", abilityLinePlausible("|-ability|p2a: Mew|Intimidate"))
emitLog("|-ability|p1a: Charizard|Intimidate")
check("T114e emitLog suppresses", !battleLog.contains("|-ability|p1a: Charizard|Intimidate") && debugCaptureCalls.contains { $0.hasPrefix("ability_guard") })
// (f) 技行の妥当性ガード: ひんし済みは決定的に弾き、場不在は証拠のみ
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Volcarona", hpPercent: 6)
lastSlots["oppB"] = SlotState(speciesEn: "Salamence", hpPercent: 100)
faintedSpecies = ["p2:Sneasler"]
check("T114f fainted user rejected", moveLineHardImplausible("|move|p2a: Sneasler|Heat Wave"))
check("T114f occupant not off-field", !moveLineOffField("|move|p2a: Volcarona|Heat Wave"))
check("T114f sibling occupant not off-field", !moveLineOffField("|move|p2b: Salamence|Tailwind"))
faintedSpecies = []
check("T114f absent species off-field", moveLineOffField("|move|p2a: Sneasler|Heat Wave"))
emitLog("|move|p2a: Sneasler|Heat Wave")
check("T114f off-field still emitted with evidence", battleLog.contains("|move|p2a: Sneasler|Heat Wave") && debugCaptureCalls.contains { $0.hasPrefix("move_guard") })
pendingSwitchSpecies["oppA"] = "Sneasler"
check("T114f pending switch not off-field", !moveLineOffField("|move|p2a: Sneasler|Heat Wave"))
// (g) メガ反応文の「設応した」崩れでもストーンが付く
resetAll()
speciesDict.append(E("ボーマンダ", "Salamence"))
itemDict[normalize("ボーマンダナイト")] = "ボーマンダナイト"; itemJa2En["ボーマンダナイト"] = "Salamencite"
lastSlots["oppB"] = SlotState(speciesEn: "Salamence", hpPercent: 100)
monStates["p2:Salamence"] = MonState()
check("T114g garbled mega consumed", translateBattleMessage("あいて相手の相手のボーマンダの／ボーマンダナイトとCurtleの センプイリングが設応した！"))
check("T114g stone pending", pendingMegaStone["p2"] == "ボーマンダナイト")
check("T114g item line", battleLog.contains { $0.hasPrefix("|-item|") && $0.contains("Salamencite") })
// (h) アーカイブ時のヘッダー補完
resetAll()
let proto114 = ["|gametype|doubles", "|poke|p1|Charizard", "|poke|p1|Incineroar", "|poke|p2|Volcarona", "|poke|p2|Sneasler", "|start",
                "|switch|p2a: Volcarona|Volcarona|100/100", "|switch|p2b: Sneasler|Sneasler|100/100",
                "|switch|p1a: Charizard|Charizard|153/153", "|switch|p2b: Salamence|Salamence|100/100", "|switch|p2a: Rillaboom|Rillaboom|100/100"]
let disp114 = ["you and Opponent joined", "Your team:", "Charizard / Incineroar", "Opponent's team:", "Volcarona / Sneasler", "", "Battle started between you and Opponent!"]
let comp114 = completeArchiveHeader(protocolLines: proto114, displayLines: disp114)
check("T114h pokes completed", comp114.protocolLines.contains("|poke|p2|Salamence") && comp114.protocolLines.contains("|poke|p2|Rillaboom")
      && (comp114.protocolLines.firstIndex(of: "|poke|p2|Rillaboom") ?? 99) < (comp114.protocolLines.firstIndex(of: "|start") ?? 0))
check("T114h added list", comp114.added == ["p2:Salamence", "p2:Rillaboom"])
check("T114h display completed", comp114.displayLines.contains("Volcarona / Sneasler / Salamence / Rillaboom"))
// (i) 入場特性の低下行は原因側の交代行の後に出る (特性行 → 低下行の順)
resetAll()
currentTurn = 2
speciesAbilityMap["Salamence"] = ["Intimidate"]
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 95)
monStates["p1:Charizard"] = MonState()
emittedSwitchKeys = ["p1:Charizard"]
pendingSwitchSpecies["oppB"] = "Salamence"
applyBoost(key: "p1:Charizard", slot: "p1a", speciesEn: "Charizard", stat: "atk", delta: -1)
check("T114i drop held", !battleLog.contains("|-unboost|p1a: Charizard|atk|1") && heldEntryBoosts.count == 1 && (monStates["p1:Charizard"]?.boosts["atk"] ?? 0) == -1)
pendingSwitchSpecies = [:]
lastSwitchIn["p2:Salamence"] = ("p2b", Date())
recordSwitchIn(side: "p2", slot: "p2b", speciesEn: "Salamence")
let abIdx = battleLog.firstIndex(of: "|-ability|p2b: Salamence|Intimidate") ?? -1
let ubIdx = battleLog.firstIndex(of: "|-unboost|p1a: Charizard|atk|1") ?? -1
check("T114i flushed in order", abIdx >= 0 && ubIdx > abIdx && heldEntryBoosts.isEmpty)
// (j) ひんし行は次の技行より先に出る
resetAll()
currentTurn = 4
monStates["p2:Volcarona"] = MonState(); monStates["p2:Volcarona"]!.hpPercent = 0
lastSlots["oppA"] = SlotState(speciesEn: "Volcarona", hpPercent: 0)
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 90)
deferFaint(slot: "p2a", speciesEn: "Volcarona")
emitLog("|move|p1a: Charizard|Heat Wave")
let fIdx = battleLog.firstIndex(of: "|faint|p2a: Volcarona") ?? -1
let mIdx = battleLog.firstIndex(of: "|move|p1a: Charizard|Heat Wave") ?? -1
check("T114j faint before next move", fIdx >= 0 && mIdx > fIdx)

// ===== T115: battle_20261122_051707 =====
// (a) 持ち物行ガード: 場にいない種族の持ち物行は出さない
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 62)
lastSlots["mineB"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
emitLog("|-item|p1a: Charmeleon|Charizardite Y")
check("T115a off-field item suppressed", !battleLog.contains("|-item|p1a: Charmeleon|Charizardite Y") && debugCaptureCalls.contains { $0.hasPrefix("item_guard") })
emitLog("|-item|p1a: Charizard|Charizardite Y")
check("T115a occupant item allowed", battleLog.contains("|-item|p1a: Charizard|Charizardite Y"))

// (b) メガ反応の再読: 名前が崩れて別種族に解決されても、ファミリーの
// メガが完了済みなら消費だけして持ち物行を出さない。ストーンが
// 特定できた場合は種族をストーンから引き直す
resetAll()
if !speciesDict.contains(where: { $0.en == "Charmeleon" }) { speciesDict.append(E("リザード", "Charmeleon")) }
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.megaSpecies = "Charizard-Mega-Y"
_ = translateBattleMessage("リザードのリザードナイト Yと Renのキーリングが反応した！")
check("T115b family-completed mega re-read consumed", !battleLog.contains { $0.contains("Charmeleon") })
resetAll()
monStates["p1:Charizard"] = MonState()
_ = translateBattleMessage("リザードのリザードナイト Yと Renのキーリングが反応した！")
check("T115b species re-derived from stone", battleLog.contains("|-item|p1a: Charizard|Charizardite Y") && pendingMegaSpecies["p1"] == "Charizard")

// (c) フィールド特性によるメガ完了: 反応保留中のまま日照しが発生
// したら、天候行より先に完了を補い、特性行もメガ名で出す
resetAll()
currentTurn = 1
if !speciesDict.contains(where: { $0.en == "Charizard-Mega-Y" }) { speciesDict.append(E("メガリザードンY", "Charizard-Mega-Y")) }
speciesAbilityMap["Charizard-Mega-Y"] = ["Drought"]
speciesAbilityMap["Charizard"] = ["Blaze"]
pendingMegaSpecies["p1"] = "Charizard"; pendingMegaStone["p1"] = "リザードナイトY"
lastSwitchIn["p1:Charizard"] = ("p1a", Date()); switchInTurn["p1:Charizard"] = 1
monStates["p1:Charizard"] = MonState()
setWeather("Sun", "Sunny Day", via: "ひざしが つよくなった！")
check("T115c mega completed before weather", battleLog.contains("|detailschange|p1a: Charizard|Charizard-Mega-Y") && battleLog.firstIndex(of: "|detailschange|p1a: Charizard|Charizard-Mega-Y")! < battleLog.firstIndex(where: { $0.hasPrefix("|-weather|Sunny Day") })!)
check("T115c drought ability with mega name", battleLog.contains("|-ability|p1a: Charizard-Mega-Y|Drought"))

// (d) すてゼリフの帰還文は、正しい文面でも崩れた文面でも消費する
resetAll()
if !speciesDict.contains(where: { $0.en == "Incineroar" }) { speciesDict.append(E("ガオガエン", "Incineroar")) }
check("T115d return text consumed", translateBattleMessage("相手のガオガエンはVの元へ戻っていく！") && !battleLog.contains { $0.contains("戻っていく") })
resetAll()
check("T115d garbled return text consumed", translateBattleMessage("ガオガエンはもともどRenの完へ買っていく！") && !battleLog.contains { $0.contains("買っていく") })

// (e) 同種族の二重確定ガード: 相方枠に在席中の種族は別枠で確定
// しない。保留が 6 秒を超えたら確定に進む
resetAll()
currentTurn = 4
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 93)
monStates["p2:Gardevoir"] = MonState(); monStates["p2:Gardevoir"]!.hpPercent = 93; monStates["p2:Gardevoir"]!.hpText = "93/100"
var pg = SlotState(speciesEn: "Gardevoir", hpPercent: 93)
processPlates(["oppA": pg])
processPlates(["oppA": pg])
check("T115e duplicate species switch held", !battleLog.contains("|switch|p2a: Gardevoir") && debugCaptureCalls.contains { $0.hasPrefix("switch_species_dup") })
pendingSwitchSince["oppA"] = Date(timeIntervalSinceNow: -10)
processPlates(["oppA": pg])
processPlates(["oppA": pg])
check("T115e held switch confirms after timeout", battleLog.contains { $0.hasPrefix("|switch|p2a: Gardevoir|Gardevoir|") })

// ===== T116: ステータス撮影のフォルム判別 (チーム18のキュウコン) =====
// 実測値 HP149/攻78/防96/特攻133/特防120/素早177、SP 1/0/1/32/0/32 は
// アローラ種族値では おくびょう で完全一致し、原種では再現できない
let nineStats: [String: Int] = ["hp": 149, "atk": 78, "def": 96, "spa": 133, "spd": 120, "spe": 177]
let nineSp: [String: Int] = ["hp": 1, "atk": 0, "def": 1, "spa": 32, "spd": 0, "spe": 32]
check("T116 alola fits", statsFitForme(base: [73, 67, 75, 81, 100, 109], stats: nineStats, spHint: nineSp, speciesEn: "Ninetales-Alola"))
check("T116 base does not fit", !statsFitForme(base: [73, 76, 75, 81, 100, 100], stats: nineStats, spHint: nineSp, speciesEn: "Ninetales"))
// 1 項目だけの誤読は補正込みで一致とみなす (HP を 1 ずらした読み)
var nineStatsOff = nineStats; nineStatsOff["hp"] = 148
check("T116 one-stat misread still fits", statsFitForme(base: [73, 67, 75, 81, 100, 109], stats: nineStatsOff, spHint: nineSp, speciesEn: "Ninetales-Alola"))

// ===== T117: ログ画面の持ち物エントリのストーン優先 (battle_20261122_051707) =====
// ログ画面の小さい文字で「リザードン」の末尾が落ちて「リザード」に
// なると、本文の名前検索では Charmeleon に一致する。メガストーンが
// 特定できた場合は種族をストーンから決め直す
resetAll()
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 60)
translateLogEntry(chip: "持ち物", text: "リザードのリザードナイトY", side: "p1", turn: 1)
check("T117 stone overrides truncated name", battleLog.contains("|-item|p1a: Charizard|Charizardite Y"))
check("T117 no charmeleon", !battleLog.contains { $0.contains("Charmeleon") })
// ストーンでない持ち物では本文の種族をそのまま使う (決め直しはストーンのみ)
resetAll()
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 60)
translateLogEntry(chip: "持ち物", text: "リザードンのたべのこし", side: "p1", turn: 1)
check("T117 non-stone keeps text species", battleLog.contains("|-item|p1a: Charizard|Leftovers"))

// ===== T118: state.json スナップショット (証拠保全) の記録判定 =====
resetAll()
battleArchiveId = "20261122_060000"
winLogged = false
// 開始前の選出形は合間のバッファ (leadIn) に入る
battleArchiveId = ""
noteStateWrite(shape: "preview", json: "{\"oppPreview\": true}", eventsCount: 0)
check("T118a pre-battle preview goes to lead-in", stateSnapLeadIn.count == 1 && stateSnapRecords.isEmpty)
// 試合開始で引き継がれ、最初の対戦形が (d) で記録される
battleArchiveId = "20261122_060000"
adoptStateSnapshotsForBattle()
check("T118b lead-in adopted at battle start", stateSnapRecords.count == 1 && stateSnapLeadIn.isEmpty)
noteStateWrite(shape: "battle", json: "{\"events\": []}", eventsCount: 2)
check("T118c first battle write recorded", stateSnapRecords.count == 2)
// 形が変わらない対戦形の連続は記録しない
noteStateWrite(shape: "battle", json: "{\"events\": [1]}", eventsCount: 3)
check("T118d steady battle writes skipped", stateSnapRecords.count == 2)
// 対戦中の選出形は (a) で記録され、続く対戦形は (b) で記録される
noteStateWrite(shape: "preview", json: "{\"oppPreview\": true}", eventsCount: 3)
check("T118e mid-battle preview recorded", stateSnapRecords.count == 3)
noteStateWrite(shape: "battle", json: "{\"events\": [1, 2]}", eventsCount: 3)
check("T118f first battle write after preview recorded", stateSnapRecords.count == 4)
// events 件数が減った書き出しは (c) で記録される
noteStateWrite(shape: "battle", json: "{\"events\": []}", eventsCount: 1)
check("T118g shrinking events recorded", stateSnapRecords.count == 5)
// 勝敗確定後の選出形は次の試合の lead-in に入る
winLogged = true
noteStateWrite(shape: "preview", json: "{\"oppPreview\": true}", eventsCount: 0)
check("T118h post-battle preview goes to lead-in", stateSnapLeadIn.count == 1 && stateSnapRecords.count == 5)
// battleEventsObjects: 断片をオブジェクト列に変換する
resetAll()
battleEvents = ["{\"k\":\"mv\",\"turn\":1}", "not json"]
check("T118i events objects parsed", battleEventsObjects().count == 1)

// ===== T119: battle_20261122_054802 の修正群 =====
// T119a-d: 地形の上書き確認ゲート (出所のない上書きは保留→破棄、
// サージ特性の交代が記録されれば採用)
resetAll()
logStarted = true
currentTurn = 3
logFieldTerrain = "Psychic"
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 39)
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
_ = checkFieldText(text: "足下に草がおいしげった！")
check("T119a unconfirmed terrain replace held", logFieldTerrain == "Psychic" && heldTerrainReplace?.ui == "Grassy" && !battleLog.contains("|-fieldstart|move: Grassy Terrain"))
recordSwitchIn(side: "p2", slot: "p2a", speciesEn: "Rillaboom")
check("T119b replace confirmed by surge switch-in", logFieldTerrain == "Grassy" && battleLog.contains { $0.hasPrefix("|-fieldstart|move: Grassy Terrain") } && heldTerrainReplace == nil)
_ = checkFieldText(text: "足下が不思議な感じになった！")
check("T119c psychic replace held again", heldTerrainReplace?.ui == "Psychic" && logFieldTerrain == "Grassy")
heldTerrainReplace = (ui: "Psychic", text: "x", at: Date(timeIntervalSinceNow: -5))
confirmHeldTerrainReplace()
check("T119d unconfirmed replace dropped", heldTerrainReplace == nil && logFieldTerrain == "Grassy" && !battleLog.contains("|-fieldstart|move: Psychic Terrain"))
// T119f: 分類できない大きな自己ダメージは保留する (行を出さない)
resetAll()
logStarted = true
currentTurn = 6
monStates["p1:Swampert"] = MonState(); monStates["p1:Swampert"]!.hpPercent = 56; monStates["p1:Swampert"]!.hpText = "116/207"; monStates["p1:Swampert"]!.hpMax = 207
lastEmittedPct["mineB"] = 56
lastMoveLabel = "p1b: Swampert"; lastMoveName = "High Horsepower"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "mineB", slot: "p1b", key: "p1:Swampert", speciesEn: "Swampert", fromPct: 56, toPct: 5, hpText: "10/207", force: true)
check("T119f unclassified self drop held", suspectJump["mineB"]?.toPct == 5 && !battleLog.contains("|-damage|p1b: Swampert|10/207"))
// T119g: あくびの効果開始行 (対象が文中で特定できる場合)
resetAll()
logStarted = true
currentTurn = 5
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastMoveLabel = "p1b: Swampert"; lastMoveName = "Yawn"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のイエッサンはねむけをさそった！")
check("T119g yawn start line", battleLog.contains("|-start|p2a: Indeedee-F|move: Yawn"))
// T119h: ひんし直前の端数 HP 表記 (1/202) を 0 表記に直す
resetAll()
logStarted = true
emitLog("|-damage|p1a: Incineroar|1/202")
emitLog("|faint|p1a: Incineroar")
check("T119h faint sliver rewritten", battleLog.contains("|-damage|p1a: Incineroar|0/202") && !battleLog.contains("|-damage|p1a: Incineroar|1/202"))
// T119i: 交代技で戻った直後の後任は 1 回のプレート読みで確定する
resetAll()
logStarted = true
currentTurn = 4
lastSlots["mineA"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
pivotReturnAt["p1"] = Date()
processPlates(["mineA": SlotState(speciesEn: "Dragonite", hpPercent: 100, hpCur: 167, hpMax: 167)])
check("T119i pivot switch confirmed in one read", battleLog.contains { $0.hasPrefix("|switch|p1a: Dragonite") })

// ===== T120: 地形シードの判明の印付け (054802 の追加確認) =====
resetAll()
logStarted = true
currentTurn = 1
logFieldTerrain = "Psychic"
fieldTerrainSetAt = Date()
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
emittedSwitchKeys = ["p2:Indeedee-F"]
lastSwitchIn["p2:Indeedee-F"] = ("p2a", Date())
monStates["p2:Indeedee-F"] = MonState()
applyBoost(key: "p2:Indeedee-F", slot: "p2a", speciesEn: "Indeedee-F", stat: "spd", delta: 1)
check("T120a psychic seed revealed", battleLog.contains("|-item|p2a: Indeedee-F|Psychic Seed") && revealedItems["Indeedee-F"] == "サイコシード")
// 本人の技による上昇 (めいそう等) では判明にしない
resetAll()
logStarted = true
currentTurn = 3
logFieldTerrain = "Psychic"
fieldTerrainSetAt = Date()
lastSlots["oppA"] = SlotState(speciesEn: "Indeedee-F", hpPercent: 100)
emittedSwitchKeys = ["p2:Indeedee-F"]
lastSwitchIn["p2:Indeedee-F"] = ("p2a", Date())
monStates["p2:Indeedee-F"] = MonState()
lastMoveLabel = "p2a: Indeedee-F"; lastMoveName = "Calm Mind"; lastMoveMsgAt = Date()
applyBoost(key: "p2:Indeedee-F", slot: "p2a", speciesEn: "Indeedee-F", stat: "spd", delta: 1)
check("T120b own move boost not a seed reveal", !battleLog.contains { $0.hasPrefix("|-item|p2a: Indeedee-F") } && revealedItems["Indeedee-F"] == nil)
// グラスシード (入場直後の防御上昇)
resetAll()
logStarted = true
currentTurn = 3
logFieldTerrain = "Grassy"
lastSlots["oppA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
emittedSwitchKeys = ["p2:Sneasler"]
lastSwitchIn["p2:Sneasler"] = ("p2a", Date())
monStates["p2:Sneasler"] = MonState()
applyBoost(key: "p2:Sneasler", slot: "p2a", speciesEn: "Sneasler", stat: "def", delta: 1)
check("T120c grassy seed revealed", battleLog.contains("|-item|p2a: Sneasler|Grassy Seed") && revealedItems["Sneasler"] == "グラスシード")


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

// T123a: トリックルーム開始文の濁点崩れ (ゆかめた) を拾う
resetAll()
check("T123a trick room garble", checkFieldText(text: "リキキリンは時空をゆかめた！") && battleLog.contains("|-fieldstart|move: Trick Room"))

// T123b: ヘッダー補完は 6 体を超えたら未登場の宣言種族と入れ替える
let proto123 = ["|gametype|doubles",
                "|poke|p1|Sneasler", "|poke|p1|Farigiraf",
                "|poke|p2|Raichu", "|poke|p2|Rillaboom", "|poke|p2|Volcarona",
                "|poke|p2|Incineroar", "|poke|p2|Scrafty", "|poke|p2|Garchomp",
                "|start",
                "|switch|p2a: Volcarona|Volcarona|100/100",
                "|switch|p2b: Garchomp|Garchomp|100/100",
                "|switch|p2b: Incineroar|Incineroar|100/100",
                "|switch|p2b: Gholdengo|Gholdengo|100/100"]
let disp123 = ["Your team:", "Sneasler / Farigiraf",
               "Grekraus's team:", "Raichu / Rillaboom / Volcarona / Incineroar / Scrafty / Garchomp"]
let comp123 = completeArchiveHeader(protocolLines: proto123, displayLines: disp123)
let pokes123 = comp123.protocolLines.filter { $0.hasPrefix("|poke|p2|") }
check("T123b header capped at 6", pokes123.count == 6 && pokes123.contains("|poke|p2|Gholdengo") && !pokes123.contains("|poke|p2|Scrafty"))
check("T123b removed reported", comp123.removed == ["p2:Scrafty"] && comp123.added == ["p2:Gholdengo"])
check("T123b display swapped", (comp123.displayLines.last ?? "").contains("Gholdengo") && !(comp123.displayLines.last ?? "").contains("Scrafty"))

// T123c: 場にいない種族のメガは、別種族の占有枠へ付けない (保留を維持する)
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
pendingMegaSpecies["p1"] = "Staraptor"
pendingMegaStone["p1"] = "ムクホークナイト"
completeMega(side: "p1", baseEn: "Staraptor", megaEn: "Staraptor-Mega")
check("T123c mega not attached to other slot", !battleLog.contains { $0.contains("detailschange") } && pendingMegaSpecies["p1"] == "Staraptor")
lastSlots["mineB"] = SlotState(speciesEn: "Staraptor", hpPercent: 100)
synthesizeMegaIfPending(side: "p1", speciesEn: "Staraptor")
check("T123c mega completes at own slot", battleLog.contains("|detailschange|p1b: Staraptor|Staraptor-Mega"))

// T123d: いかく遡及は、間に他の文が処理されて seq が進んでも特性行を出す
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
emittedSwitchKeys = ["p1:Gardevoir"]
_ = translateBattleMessage("サーナイトのこうげきが下がった！")
actionSeq += 3
recordSwitchIn(side: "p2", slot: "p2b", speciesEn: "Scrafty")
check("T123d retro intimidate despite seq advance", battleLog.contains("|-ability|p2b: Scrafty|Intimidate"))

// T123e: 外れの対象が場の記録と矛盾する場合は行を出さない
resetAll()
if !speciesDict.contains(where: { $0.en == "Volcarona" }) { speciesDict.append(E("ウルガモス", "Volcarona")) }
lastSlots["oppA"] = SlotState(speciesEn: "Volcarona", hpPercent: 100)
lastSwitchIn["p2:Incineroar"] = ("p2b", Date())
lastMoveLabel = "p1a: Sneasler"
lastMoveMsgAt = Date()
_ = translateBattleMessage("ガオガエンには当たらなかった！")
check("T123e inconsistent miss suppressed", !battleLog.contains { $0.contains("-miss") } && debugCaptureCalls.contains("move_guard"))
battleLog = []
_ = translateBattleMessage("ウルガモスには当たらなかった！")
check("T123e consistent miss emitted", battleLog.contains("|-miss|p1a: Sneasler|p2a: Volcarona"))

// T123f: 場の占有でない種族の ひんし文では被ダメ行を合成せず、HP 基準を守る
resetAll()
lastSlots["mineA"] = SlotState(speciesEn: "Farigiraf", hpPercent: 65)
lastSlots["mineB"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
monStates["p1:Farigiraf"] = MonState()
monStates["p1:Farigiraf"]?.hpPercent = 65
lastEmittedPct["mineA"] = 65
_ = translateBattleMessage("コータスはたおれた！")
check("T123f untracked faint text guarded", !battleLog.contains { $0.contains("-damage") } && lastEmittedPct["mineA"] == 65 && debugCaptureCalls.contains("faint_guard"))
battleLog = []
_ = translateBattleMessage("リキキリンはたおれた！")
check("T123f occupant faint synthesized", battleLog.contains("|-damage|p1a: Farigiraf|0/100"))

// T124a: 疑わしい低下の保留が解けた直後の説明できない低下は確定しない
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 1
monStates["p2:Sneasler"] = MonState()
monStates["p2:Sneasler"]?.hpPercent = 100
suspectJump["oppA"] = (toPct: 10, turn: 1, hpText: "17/171")
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
suspectJump["oppA"] = (toPct: 10, turn: 1, hpText: "17/171")
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
suspectJump["oppA"] = (toPct: 10, turn: 1, hpText: "17/171")
lastEmittedPct["oppA"] = 100
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 98, hpText: "168/171", force: true)
check("T124c small drop emitted", battleLog.contains("|-damage|p2a: Sneasler|168/171"))

// T125a: 急所行は同じ対象の ひんし行より前に置く
resetAll()
emitLog("|-damage|p2a: Charizard|0/160")
emitLog("|faint|p2a: Charizard")
emitLog("|-crit|p2a: Charizard")
let critPos = battleLog.firstIndex(of: "|-crit|p2a: Charizard")
let faintPos = battleLog.firstIndex(of: "|faint|p2a: Charizard")
check("T125a crit before faint", critPos != nil && faintPos != nil && (critPos ?? -1) < (faintPos ?? -1))

// T125b: 特性行は対応する天候行より前に置く
resetAll()
emitLog("|-weather|Sunny Day")
emitLog("|-ability|p2b: Torkoal|Drought")
let abPos = battleLog.firstIndex(of: "|-ability|p2b: Torkoal|Drought")
let wPos = battleLog.firstIndex(where: { $0.hasPrefix("|-weather|Sunny Day") })
check("T125b ability before weather", abPos != nil && wPos != nil && (abPos ?? -1) < (wPos ?? -1))

// T125c: ターンを跨いだ特性行は前のターンの天候行より前に動かさない
resetAll()
emitLog("|-weather|Sunny Day")
emitLog("|turn|2")
emitLog("|-ability|p2b: Torkoal|Drought")
let abPos2 = battleLog.firstIndex(of: "|-ability|p2b: Torkoal|Drought")
let wPos2 = battleLog.firstIndex(of: "|-weather|Sunny Day")
check("T125c no reorder across turns", abPos2 != nil && wPos2 != nil && (wPos2 ?? -1) < (abPos2 ?? -1))


// ===== T119: プレート HP のスラッシュ融合読み (battle_20261122_071457) =====
// "150m71" ("/1" が "m" に融合) を既知の最大値で補完して読む
check("T119 fused slash with knownMax", parseMineHPText("150m71", knownMax: 171)?.cur == 150 && parseMineHPText("150m71", knownMax: 171)?.max == 171)
// 既知値が無ければ成り立つ最小の補完
check("T119 fused slash without knownMax", parseMineHPText("150m71", knownMax: nil)?.max == 171)
// 既知値と一致しない補完は採らない
check("T119 fused slash wrong knownMax", parseMineHPText("150m71", knownMax: 200) == nil)
// 通常のスラッシュ形式と数字ペアは従来どおり
check("T119 plain slash", parseMineHPText("150/171", knownMax: nil)?.pct == 88)
check("T119 plain pair", parseMineHPText("137 137", knownMax: nil)?.pct == 100)

// T126: battle_20261122_091721 の対応 (境界の帰属・二重発動・断片結合ほか)
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
let t6Pos = battleLog.firstIndex(of: "|turn|6") ?? -1
check("T126b switch pulled to old turn head", t6Pos >= 0 && swPos == t6Pos + 1)
check("T126b mega block in new turn", t7Pos >= 0 && megaPos > t7Pos && mvPos > megaPos)
check("T126b unrelated line stays in old turn", loPos >= 0 && loPos < t7Pos)
let dGo = displayLog.firstIndex(of: "Go! Gengar!") ?? -1
let dBack = displayLog.firstIndex(of: "Politoed, come back!") ?? -1
let dHeal = displayLog.firstIndex(of: "The opposing Overqwil restored a little HP!") ?? -1
let dMega = displayLog.firstIndex(of: "Gengar has Mega Evolved into Mega Gengar!") ?? -1
check("T126b display split too", dBack >= 0 && dGo == dBack + 1 && dHeal == dGo + 1 && dMega > dHeal)
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
emittedSwitchKeys.insert("p2:Overqwil")
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
emittedSwitchKeys.insert("p2:Clefable")
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
battleMaxCandidate["Armarouge"] = (max: 161, count: 1, firstAt: Date(timeIntervalSinceNow: -4))
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

// T129: 交代候補の区間管理 (フェーズ3)
// a: 占有者との交互読みでも候補の証拠は消えず、2 回目の入場者読みで確定する
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 80)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p2:Floette"] = MonState(); monStates["p2:Floette"]?.hpPercent = 80
fieldSeen["p2"] = ["Floette"]
emittedSwitchKeys = ["p2:Floette", "p1:Gardevoir", "p1:Armarouge"]
let altHits1: [String: SlotState] = ["oppB": SlotState(speciesEn: "Gholdengo", hpPercent: 100)]
let altHitsOcc: [String: SlotState] = ["oppB": SlotState(speciesEn: "Floette", hpPercent: 80)]
processPlates(altHits1)
check("T129a candidate kept after 1st read", pendingSwitchCandidates["oppB"]?["Gholdengo"]?.count == 1)
processPlates(altHitsOcc)
check("T129a candidate survives occupant read", pendingSwitchCandidates["oppB"]?["Gholdengo"]?.count == 1)
check("T129a not confirmed yet", !battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })
processPlates(altHits1)
check("T129a confirmed on 2nd entrant read", battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })
check("T129a store cleared on confirm", pendingSwitchCandidates["oppB"] == nil)

// b: 候補は最終観測から 3 秒を超えると期限切れになり、リーダー表示も消える
resetAll()
currentTurn = 2
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 80)
monStates["p2:Floette"] = MonState(); monStates["p2:Floette"]?.hpPercent = 80
processPlates(altHits1)
pendingSwitchCandidates["oppB"] = ["Gholdengo": (count: 1, firstSeen: Date(timeIntervalSinceNow: -10), lastSeen: Date(timeIntervalSinceNow: -10))]
processPlates(altHitsOcc)
check("T129b expired candidate dropped", pendingSwitchCandidates["oppB"] == nil && pendingSwitchSpecies["oppB"] == nil)
check("T129b no switch emitted", !battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })

// T130: 文証拠と候補優先の帰属 (フェーズ3)
// a: 繰り出し文の証拠があれば、交代は 1 回のプレート読みで確定する
resetAll()
currentTurn = 3
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Floette", hpPercent: 80)
lastSlots["mineA"] = SlotState(speciesEn: "Gardevoir", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Armarouge", hpPercent: 100)
monStates["p2:Floette"] = MonState(); monStates["p2:Floette"]?.hpPercent = 80
fieldSeen["p2"] = ["Floette"]
emittedSwitchKeys = ["p2:Floette", "p1:Gardevoir", "p1:Armarouge"]
sendOutTextSeen["p2"] = (species: "Gholdengo", at: Date())
processPlates(["oppB": SlotState(speciesEn: "Gholdengo", hpPercent: 100)])
check("T130a text evidence fast-confirms", battleLog.contains { $0.hasPrefix("|switch|p2b: Gholdengo") })
check("T130a evidence consumed", sendOutTextSeen["p2"] == nil)

// b: 告知の帰属枠は、場にいない種族でも交代候補の枠を既定枠より優先する
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Floette", hpPercent: 75)
lastSlots["oppB"] = SlotState(speciesEn: "Rillaboom", hpPercent: 90)
pendingSwitchCandidates["oppB"] = ["Gholdengo": (count: 1, firstSeen: Date(), lastSeen: Date())]
check("T130b candidate slot preferred", announcedSlot(side: "p2", speciesEn: "Gholdengo") == "p2b")
check("T130b on-field slot exact", announcedSlot(side: "p2", speciesEn: "Floette") == "p2a")
check("T130b default preserved", announcedSlot(side: "p2", speciesEn: "Dragapult") == "p2a")

// T131: 開幕区間では入場効果のラウンド行でターン行を出さない (フェーズ4、
// battle_20261122_091721 の +1 の再現: debug02 は いかく の低下行で
// |turn|1 を挿入していた)
resetAll()
currentTurn = 0
battleLog = []
displayLog = []
roundEventSeen = false
movesSinceTurnLine = []
enteredThisSegment = []
emitLog("|-unboost|p1a: Politoed|atk|1")
check("T131a entry unboost makes no turn line", !battleLog.contains { $0.hasPrefix("|turn|") } && currentTurn == 0)
emitLog("|-boost|p2b: Overqwil|def|1")
check("T131b entry boost makes no turn line", !battleLog.contains { $0.hasPrefix("|turn|") } && currentTurn == 0)
emitLog("|move|p2a: Sableye|Fake Out")
check("T131c first move inserts turn 1", battleLog.firstIndex(of: "|turn|1") != nil && (battleLog.firstIndex(of: "|turn|1") ?? 99) < (battleLog.firstIndex(of: "|move|p2a: Sableye|Fake Out") ?? -1) && currentTurn == 1)
check("T131d exactly one turn line", battleLog.filter { $0.hasPrefix("|turn|") }.count == 1)

// T132: battle_20261122_160927 の修正群
// (a) 最大 HP の採用ゲート: 正当な採用は従来どおり、融合読みは候補に
//     ならず、採用は 1 回限り
resetAll()
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
battleMaxCandidate["Sneasler"] = (max: 171, count: 1, firstAt: Date(timeIntervalSinceNow: -4))
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
check("T132a legit adoption still works", battleMaxOverride["Sneasler"] == 171)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 271, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 271, registeredMax: 157)
check("T132a adoption is once-only", battleMaxOverride["Sneasler"] == 171)
resetAll()
noteBattleMaxRead(speciesEn: "Indeedee-F", readMax: 371, registeredMax: 177)
noteBattleMaxRead(speciesEn: "Indeedee-F", readMax: 371, registeredMax: 177)
check("T132b fused max never adopted", battleMaxOverride["Indeedee-F"] == nil && battleMaxCandidate["Indeedee-F"] == nil)
// (b) バー拒否: 数字だけが大きく下がり、バーが確定値を維持する場合は
//     行を出さない。次ターンも続けば状態訂正として静かに取り込む
resetAll()
var ms132 = MonState(); ms132.hpPercent = 100; ms132.hpText = "171/171"
monStates["p1:Sneasler"] = ms132
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 100)
lastEmittedPct["mineA"] = 100
let barState132 = SlotState(speciesEn: "Sneasler", hpPercent: 63, hpCur: 108, hpMax: 171, hpBarPct: 98)
processPlates(["mineA": barState132])
pendingDamageSince["mineA"] = Date(timeIntervalSinceNow: -3)
processPlates(["mineA": barState132])
processPlates(["mineA": barState132])
check("T132c bar veto blocks phantom drop", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") } && barVetoHold["mineA"]?.pct == 63)
currentTurn = 2
processPlates(["mineA": barState132])
pendingDamageSince["mineA"] = Date(timeIntervalSinceNow: -3)
processPlates(["mineA": barState132])
processPlates(["mineA": barState132])
check("T132c persistent value adopted silently next turn", lastEmittedPct["mineA"] == 63 && !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") })
// (c) 隣枠と寸分違わぬ HP 文への低下は枠混入として保留する
resetAll()
var ms132w = MonState(); ms132w.hpPercent = 90; ms132w.hpText = "150/167"
monStates["p1:Whimsicott"] = ms132w
lastSlots["mineB"] = SlotState(speciesEn: "Whimsicott", hpPercent: 90)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 90, hpText: "150/167", force: true)
check("T132d sibling-identical drop held", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Gardevoir") } && suspectJump["mineA"]?.toPct == 90)
resetAll()
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 90, hpText: "150/167", force: true)
check("T132d distinct text emitted", battleLog.contains("|-damage|p1a: Gardevoir|150/167"))
// T133: battle_20261122_171847 修正群
// (a) 兄弟枠ガードは ひんし (0%) には効かない (相手2体の "0/100" は
// 常に一致してしまうため、0% まで保留すると ひんしが丸ごと消える)
resetAll()
var ms133z = MonState(); ms133z.hpPercent = 0; ms133z.hpText = "0/100"
monStates["p2:Charizard"] = ms133z
lastSlots["oppB"] = SlotState(speciesEn: "Charizard", hpPercent: 0)
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Sneasler", speciesEn: "Sneasler", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T133a sibling guard does not hold a faint", battleLog.contains("|-damage|p2a: Sneasler|0/100"))
// (b) suspect として保留された 0% は、持続しても無音採用せず行を出す
resetAll()
currentTurn = 1
suspectJump["oppB"] = (toPct: 0, turn: 1, hpText: "0/100")
currentTurn = 2
lastMoveLabel = "p1a: Armarouge"
lastMoveName = "Armor Cannon"
lastMoveMsgAt = Date()
lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Kingambit", speciesEn: "Kingambit", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T133b suspect zero falls through to emission", battleLog.contains("|-damage|p2b: Kingambit|0/100") && suspectJump["oppB"] == nil)
// (c) 別種族の登録最大と一致する読みは採用候補に数えない
resetAll()
teamEntries["Indeedee-F"] = ["stats": ["hp": 177]]
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 177, registeredMax: 157)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 177, registeredMax: 157)
check("T133c sibling-max collision not adopted", battleMaxOverride["Sneasler"] == nil)
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
battleMaxCandidate["Sneasler"] = (max: 171, count: 1, firstAt: Date(timeIntervalSinceNow: -4))
noteBattleMaxRead(speciesEn: "Sneasler", readMax: 171, registeredMax: 157)
check("T133c genuine max adopted after collision blocked", battleMaxOverride["Sneasler"] == 171)
teamEntries["Indeedee-F"] = nil
// (d) ひんし交代はターン冒頭へ引き戻さない
resetAll()
currentTurn = 3
battleLog = ["|turn|3", "|move|p1a: Armarouge|Expanding Force"]
displayLog = ["Turn 3", "Armarouge used Expanding Force!"]
lastSlots["oppB"] = SlotState(speciesEn: "Charizard", hpPercent: 0)
let kbState = SlotState(speciesEn: "Kingambit", hpPercent: 100)
processPlates(["oppB": kbState])
processPlates(["oppB": kbState])
processPlates(["oppB": kbState])
let swIdx133 = battleLog.firstIndex(of: "|switch|p2b: Kingambit|Kingambit|100/100") ?? -1
let mvIdx133 = battleLog.firstIndex(of: "|move|p1a: Armarouge|Expanding Force") ?? -1
check("T133d faint replacement not pulled to turn head", swIdx133 > mvIdx133 && mvIdx133 >= 0)
// (e) ひんし文: プレートが先に monStates を 0 にしていても、被ダメ行が
// 未出なら文側で補う
resetAll()
var ms133g2 = MonState(); ms133g2.hpPercent = 0; ms133g2.hpText = "8/100"; ms133g2.hpMax = 100
monStates["p2:Garchomp"] = ms133g2
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 0)
lastEmittedPct["oppA"] = 8
_ = translateBattleMessage("相手のガブリアスは たおれた！")
check("T133e faint text compensates when plate state already 0", battleLog.contains("|-damage|p2a: Garchomp|0/100") && pendingFaints.contains { $0.slot == "p2a" })
// (f) 最大の断片読みは既知の最大で組み直す
resetAll()
teamEntries["Gardevoir"] = ["stats": ["hp": 145]]
let gvState = SlotState(speciesEn: "Gardevoir", hpPercent: 24, hpCur: 11, hpMax: 45)
processPlates(["mineB": gvState])
processPlates(["mineB": gvState])
processPlates(["mineB": gvState])
check("T133f fragment max rescaled to known max", lastSlots["mineB"]?.hpMax == 145 && lastSlots["mineB"]?.hpCur == 35)
teamEntries["Gardevoir"] = nil
// (g) 主語だけの断片 + 能力名・動詞の断片で ランク変化が適用される
resetAll()
lastSlots["oppA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100)
var ms133g3 = MonState(); ms133g3.hpPercent = 100; ms133g3.hpText = "100/100"
monStates["p2:Garchomp"] = ms133g3
emittedSwitchKeys.insert("p2:Garchomp")
_ = translateBattleMessage("相手のガブリアスの")
_ = translateBattleMessage("回避率が下がった！")
check("T133g subject-only fragment merges into unboost", battleLog.contains("|-unboost|p2a: Garchomp|eva|1"))
// (h) いのちのたまの反動が残量で切り取られた ひんしにも [from] が付く
resetAll()
revealedItems["Garchomp"] = "いのちのたま"
lastMoveLabel = "p2a: Garchomp"
lastMoveName = "Earthquake"
lastMoveMsgAt = Date()
lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Garchomp", speciesEn: "Garchomp", fromPct: 8, toPct: 0, hpText: "0/100", force: true)
check("T133h capped Life Orb recoil classified", battleLog.contains("|-damage|p2a: Garchomp|0/100|[from] item: Life Orb"))
// ===== T134: battle_20261122_181745 round =====
// T134a: the 0% branch vetoes a zero read when the bar shows 42%
resetAll()
currentTurn = 2
battleLog = ["|turn|2"]
monStates["p1:Sneasler"] = MonState(); monStates["p1:Sneasler"]!.hpPercent = 61; monStates["p1:Sneasler"]!.hpText = "104/171"
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 61, hpCur: 104, hpMax: 171, hpBarPct: 61)
lastEmittedPct["mineA"] = 61
monStates["p1:Sneasler"]?.hpPercent = 61
for _ in 0..<3 {
    processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 0, hpCur: 0, hpMax: 171, hpBarPct: 42)])
}
check("T134a bar 42 vetoes phantom faint", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Sneasler") } && !battleLog.contains("|faint|p1a: Sneasler") && debugCaptureCalls.contains("hp_disagree"))
// T134b: Steel Beam recoil is classified, not held as unclassified
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastSlots["oppA"] = SlotState(speciesEn: "Archaludon", hpPercent: 100, hpCur: nil, hpMax: nil, hpBarPct: nil)
lastEmittedPct["oppA"] = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Archaludon", speciesEn: "Archaludon", fromPct: 100, toPct: 79, hpText: "79/100", force: true)
check("T134b Steel Beam recoil classified", battleLog.contains("|-damage|p2a: Archaludon|79/100|[from] move: Steel Beam") && suspectJump["oppA"] == nil)
// T134c: the faint subject comes from the name+wa grammar, not the
// first dictionary match in a contaminated text
resetAll()
currentTurn = 2
battleLog = ["|turn|2"]
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 49
lastSlots["oppA"] = SlotState(speciesEn: "Archaludon", hpPercent: 49, hpCur: nil, hpMax: nil, hpBarPct: nil)
lastEmittedPct["oppA"] = 49
emittedSwitchKeys.insert("p2:Archaludon")
_ = translateBattleMessage("相手のブリジュラスは オオニューラ 69/171 たおれた！")
check("T134c faint grammar subject", battleLog.contains("|-damage|p2a: Archaludon|0/100") && pendingFaints.contains { $0.slot == "p2a" && $0.speciesEn == "Archaludon" })
// T134d: a poisoned zero baseline is rebased when the occupant reads alive
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
monStates["p1:Sneasler"] = MonState(); monStates["p1:Sneasler"]!.hpPercent = 40
lastSlots["mineA"] = SlotState(speciesEn: "Sneasler", hpPercent: 40, hpCur: 69, hpMax: 171, hpBarPct: 40)
lastEmittedPct["mineA"] = 0
lastDamageTime["mineA"] = Date(timeIntervalSinceNow: -30)
monStates["p1:Sneasler"]?.hpPercent = 40
processPlates(["mineA": SlotState(speciesEn: "Sneasler", hpPercent: 40, hpCur: 69, hpMax: 171, hpBarPct: 40)])
check("T134d zero baseline rebased on alive read", lastEmittedPct["mineA"] == 40)
// T134e: the archive header unifies a full-HP switch line to the
// adopted real max
let proto134 = ["|poke|p1|Sneasler", "|start",
                "|switch|p1a: Sneasler|Sneasler|157/157",
                "|-damage|p1a: Sneasler|120/171"]
let comp134 = completeArchiveHeader(protocolLines: proto134, displayLines: [])
check("T134e switch max unified to adopted max", comp134.protocolLines.contains("|switch|p1a: Sneasler|Sneasler|171/171"))
// T134f: Perish Song count/announcement texts are consumed
resetAll()
battleLog = []
let perish1 = translateBattleMessage("オオニューラの減びのカウントが3になった！")
let perish2 = translateBattleMessage("ほろびのうたを 聴いたポケモンは3ターン後に滅びてしまう！")
check("T134f perish texts consumed", perish1 && perish2 && battleLog.isEmpty)
// T134g: no damage line at full HP
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 100
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 100, toPct: 100, hpText: "145/145", force: true)
check("T134g no full-hp damage line", !battleLog.contains { $0.hasPrefix("|-damage|p1a: Gardevoir") })
// ===== T135: spe events (speed evidence for pre-move KOs) =====
// (a) acceptance scene (battle_20261122_181745 T1): Steel Beam KOs
// Gardevoir before it moves -> spe event fast=Archaludon slow=Gardevoir
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\"k\":\"mv\",\"turn\":1,\"label\":\"p2a: Archaludon\",\"move\":\"Steel Beam\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135a spe event for pre-move KO", battleEvents.contains { $0.contains("\"k\":\"spe\"") && $0.contains("\"fast\":\"p2a: Archaludon\"") && $0.contains("\"slow\":\"p1a: Gardevoir\"") && $0.contains("\"move\":\"Steel Beam\"") })
// (b) the defender already moved this turn -> no spe event
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p1a: Gardevoir|Moonblast", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\"k\":\"mv\",\"turn\":1,\"label\":\"p1a: Gardevoir\",\"move\":\"Moonblast\"}",
                "{\"k\":\"mv\",\"turn\":1,\"label\":\"p2a: Archaludon\",\"move\":\"Steel Beam\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135b no spe when defender moved", !battleEvents.contains { $0.contains("\"k\":\"spe\"") })
// (c) the defender switched in this turn -> no spe event
resetAll()
currentTurn = 2
battleLog = ["|turn|2", "|switch|p1a: Gardevoir|Gardevoir|145/145", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\"k\":\"mv\",\"turn\":2,\"label\":\"p2a: Archaludon\",\"move\":\"Steel Beam\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: true)
check("T135c no spe when defender entered this turn", !battleEvents.contains { $0.contains("\"k\":\"spe\"") })
// (d) no KO (or not a direct move) -> no spe event
resetAll()
currentTurn = 1
battleLog = ["|turn|1", "|move|p2a: Archaludon|Steel Beam"]
battleEvents = ["{\"k\":\"mv\",\"turn\":1,\"label\":\"p2a: Archaludon\",\"move\":\"Steel Beam\"}"]
monStates["p1:Gardevoir"] = MonState(); monStates["p1:Gardevoir"]!.hpPercent = 24
monStates["p2:Archaludon"] = MonState(); monStates["p2:Archaludon"]!.hpPercent = 100
lastMoveLabel = "p2a: Archaludon"; lastMoveName = "Steel Beam"; lastMoveSeq = actionSeq; lastMoveMsgAt = Date()
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 10, hpText: "14/145", directMove: true)
recordDamageEvent(slot: "p1a", key: "p1:Gardevoir", speciesEn: "Gardevoir", fromPct: 24, toPct: 0, hpText: "0/145", directMove: false)
check("T135d no spe without a direct-move KO", !battleEvents.contains { $0.contains("\"k\":\"spe\"") })
// ===== T136: 185505 fixes (announcement bang-cut, post-faint lines, pull-back guard) =====
moveNameOrig[normalize("ねっぷう")] = "ねっぷう"; moveJa2En["ねっぷう"] = "Heat Wave"
// (a) announcement with trailing junk after the bang (recording overlay)
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100, hpCur: 185, hpMax: 185, hpBarPct: nil)
lastSlots["mineB"] = SlotState(speciesEn: "Garchomp", hpPercent: 89, hpCur: 165, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 100
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
fieldSeen["p1"] = ["Charizard", "Garchomp"]
emittedSwitchKeys.insert("p1:Charizard"); emittedSwitchKeys.insert("p1:Garchomp")
_ = translateBattleMessage("ムービー収録 リザードンの ねっぷう！ 0 KB")
check("T136a announcement survives trailing junk", battleLog.contains("|move|p1a: Charizard|Heat Wave"))
// (b) announcement with a "・" before the move name
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 100, hpCur: 185, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 100
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
fieldSeen["p1"] = ["Charizard", "Garchomp"]
emittedSwitchKeys.insert("p1:Charizard"); emittedSwitchKeys.insert("p1:Garchomp")
_ = translateBattleMessage("リザードンの ・ねっぷう！")
check("T136b announcement survives nakaguro", battleLog.contains { $0.hasPrefix("|move|") && $0.contains("Charizard|Heat Wave") })
// (c) no HP lines for a species already recorded fainted
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
faintedSpecies.insert("p1:Garchomp")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Garchomp", speciesEn: "Garchomp", fromPct: 0, toPct: 19, hpText: "36/185", force: true)
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Garchomp", speciesEn: "Garchomp", fromPct: 19, toPct: 0, hpText: "0/185", force: true)
check("T136c post-faint HP lines suppressed", !battleLog.contains { $0.hasPrefix("|-heal|p1a: Garchomp") || $0.hasPrefix("|-damage|p1a: Garchomp") })
// (d) pull-back skipped in a developed segment, allowed in an early one
resetAll()
currentTurn = 3
battleLog = ["|turn|2", "|move|p2a: Indeedee-F|Helping Hand", "|move|p1a: Charizard|Weather Ball", "|-damage|p2a: Indeedee-F|0/100", "|faint|p2a: Indeedee-F", "|move|p2b: Armarouge|Expanding Force", "|switch|p1b: Sylveon|Sylveon|193/193"]
let pbDev = pullBackSwitchBlock(label: "p1b: Sylveon", requireEarlySegment: true)
check("T136d pull-back skipped in developed segment", pbDev.proto.isEmpty && battleLog.last == "|switch|p1b: Sylveon|Sylveon|193/193")
battleLog = ["|turn|2", "|move|p2a: Indeedee-F|Helping Hand", "|switch|p1b: Sylveon|Sylveon|193/193"]
let pbEarly = pullBackSwitchBlock(label: "p1b: Sylveon", requireEarlySegment: true)
check("T136e pull-back still fires in early segment", !pbEarly.proto.isEmpty)
// ===== T137: provisional list is not wiped by an empty preview reset =====
resetAll()
minePreviewTeam = ["Charizard", "Venusaur", "Garchomp", "Incineroar", "Sylveon", "Farigiraf"]
minePreviewDetails = []
syncMineProvisional()
check("T137a provisional applied", battleMineTeam.compactMap { $0?.species }.count == 6)
minePreviewTeam = []
syncMineProvisional()
check("T137b empty reset does not wipe", battleMineTeam.compactMap { $0?.species }.count == 6)
// in-battle first intake still works when the list is empty
battleMineTeam = []
minePreviewTeam = ["Blastoise", "Gardevoir", "Sneasler", "Indeedee-F", "Armarouge", "Whimsicott"]
syncMineProvisional()
check("T137c in-battle intake when empty", battleMineTeam.compactMap { $0?.species }.count == 6)
// ===== T138: header completion removes smallest-margin unused species =====
let hdrProto = ["|gametype|doubles",
                "|poke|p2|Absol", "|poke|p2|Delphox", "|poke|p2|Slowking-Galar", "|poke|p2|Arcanine", "|poke|p2|Sneasler", "|poke|p2|Kommo-o",
                "|start",
                "|switch|p2b: Absol|Absol|100/100",
                "|switch|p2a: Indeedee-F|Indeedee-F|100/100",
                "|switch|p2b: Armarouge|Armarouge|100/100",
                "|switch|p2a: Sneasler|Sneasler|100/100"]
let hdrMargins: [String: Double] = ["p2:Delphox": 0.90, "p2:Slowking-Galar": 0.05, "p2:Arcanine": 0.08, "p2:Kommo-o": 0.40]
let hdrDone = completeArchiveHeader(protocolLines: hdrProto, displayLines: [], slotMargins: hdrMargins)
check("T138a Kommo-o kept by margin", hdrDone.protocolLines.contains("|poke|p2|Kommo-o"))
check("T138b smallest margins removed", hdrDone.removed.contains("p2:Slowking-Galar") && hdrDone.removed.contains("p2:Arcanine") && !hdrDone.removed.contains("p2:Kommo-o"))
check("T138c appeared species added", hdrDone.added.contains("p2:Indeedee-F") && hdrDone.added.contains("p2:Armarouge"))
let hdrDoneOld = completeArchiveHeader(protocolLines: hdrProto, displayLines: [])
check("T138d unscored falls back to suffix rule", hdrDoneOld.removed.contains("p2:Kommo-o"))
// ===== T139: 193243 fixes (immune text; recoil text source) =====
resetAll()
currentTurn = 1
battleLog = ["|turn|1"]
lastSlots["mineA"] = SlotState(speciesEn: "Garchomp", hpPercent: 87, hpCur: 161, hpMax: 185, hpBarPct: nil)
monStates["p1:Garchomp"] = MonState(); monStates["p1:Garchomp"]!.hpPercent = 87
fieldSeen["p1"] = ["Garchomp", "Farigiraf"]
_ = translateBattleMessage("ガブリアスにはこうかはないようだ…")
check("T139a immune line from the hiragana trailing-ellipsis form", battleLog.contains("|-immune|p1a: Garchomp"))
resetAll()
currentTurn = 3
battleLog = ["|turn|3"]
lastMoveLabel = "p2b: Rillaboom"
lastMoveName = "Wood Hammer"
lastMoveMsgAt = Date(timeIntervalSinceNow: -10)
lastDamageTime["oppB"] = Date(timeIntervalSinceNow: -20)
lastDamageSeq["oppB"] = actionSeq - 1
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 100
lastSlots["oppB"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100, hpCur: 100, hpMax: 100, hpBarPct: nil)
fieldSeen["p2"] = ["Raichu", "Rillaboom"]
emittedSwitchKeys.insert("p2:Rillaboom")
let recoilCtl = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 99, hpText: "99/100", force: true)
check("T139b small drop absorbed silently without a source", recoilCtl && !battleLog.contains("|-damage|p2b: Rillaboom|99/100"))
lastDamageTime["oppB"] = Date(timeIntervalSinceNow: -20)
lastDamageSeq["oppB"] = actionSeq - 1
_ = translateBattleMessage("相手のゴリランダーはウッドハンマーの反動によるダメージを受けた！")
check("T139c recoil text records the pending source", pendingStatusFrom["p2:Rillaboom"]?.code == "move: Wood Hammer")
let recoilEmit = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 99, hpText: "99/100", force: true)
check("T139d recoil drop emitted with its [from]", recoilEmit && battleLog.contains("|-damage|p2b: Rillaboom|99/100|[from] move: Wood Hammer"))






revealedItems["Garchomp"] = nil

// ===== T140: battle_20261122_201011 =====
// (a) ひんし記録済みでも、その種族の未発行の KO 被ダメ行は出す
resetAll()
currentTurn = 5
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 0
lastEmittedPct["oppA"] = 100
faintedSpecies.insert("p2:Rillaboom")
suspectJump["oppA"] = (toPct: 0, turn: 5, hpText: "0/100")
lastMoveLabel = "p1a: Charizard"; lastMoveName = "Heat Wave"; lastMoveMsgAt = Date(); lastMoveSeq = actionSeq
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T140a owed KO line survives the post-faint guard", battleLog.contains("|-damage|p2a: Rillaboom|0/100"))
// (b) 対照: ひんし後の古い読み (0 でない被ダメ) は従来どおり抑制
resetAll()
currentTurn = 5
monStates["p2:Rillaboom"] = MonState(); monStates["p2:Rillaboom"]!.hpPercent = 0
lastEmittedPct["oppA"] = 0
faintedSpecies.insert("p2:Rillaboom")
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Rillaboom", speciesEn: "Rillaboom", fromPct: 50, toPct: 36, hpText: "36/100", force: true)
check("T140b stale post-faint read still suppressed", !battleLog.contains { $0.contains("Rillaboom") && $0.contains("36/100") })
// (c) 持ち物消費済みの個体に たべのこし は帰属しない
resetAll()
currentTurn = 8
logFieldTerrain = ""
itemLostActive.insert("p1:Incineroar")
check("T140c no Leftovers guess for a consumed item", healSource(plateName: "mineA", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 29, toPct: 35) == nil)
itemLostActive.remove("p1:Incineroar")
check("T140c2 Leftovers guess intact otherwise", healSource(plateName: "mineA", key: "p1:Incineroar", speciesEn: "Incineroar", fromPct: 29, toPct: 35)?.label == "item: Leftovers")
// (d) 交代直後のミス文: このターンの交代記録があれば通す
resetAll()
currentTurn = 4
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 46)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 100)
switchInTurn["p2:Rillaboom"] = 4
lastMoveLabel = "p1a: Charizard"; lastMoveName = "Heat Wave"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のゴリランダーには当たらなかった！")
check("T140d miss accepted with this-turn switch record", battleLog.contains("|-miss|p1a: Charizard|p2a: Rillaboom"))
// (e) すてゼリフの低下は、文中の相手マーカーで相手側へ帰属する
resetAll()
currentTurn = 1
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 100)
emittedSwitchKeys.insert("p2:Incineroar"); emittedSwitchKeys.insert("p1:Incineroar")
lastMoveLabel = "p1b: Incineroar"; lastMoveName = "Parting Shot"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のガオガエンのこうげきが下がった！")
check("T140e Parting Shot drop goes to the opponent", battleLog.contains("|-unboost|p2a: Incineroar|atk|1") && !battleLog.contains { $0.contains("unboost|p1b: Incineroar") })
// (f) 探針: T5 ねっぷう告知 (正確な文と近似した場の状態)
resetAll()
currentTurn = 5
lastSlots["mineA"] = SlotState(speciesEn: "Charizard", hpPercent: 100)
lastSlots["mineB"] = SlotState(speciesEn: "Venusaur", hpPercent: 78)
lastSlots["oppA"] = SlotState(speciesEn: "Rillaboom", hpPercent: 100)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 67)
monStates["p1:Charizard"] = MonState(); monStates["p1:Charizard"]!.hpPercent = 100
lastMoveLabel = "p2a: Rillaboom"; lastMoveName = "Fake Out"; lastMoveMsgAt = Date()
_ = translateBattleMessage("リザードンのねっぷう！")
check("T140f PROBE heat wave announcement at T5", battleLog.contains("|move|p1a: Charizard|Heat Wave"))
// (g) 探針: めいそう の上昇行 (T2 適用後に T3 で同じ文が来る場合)
resetAll()
currentTurn = 2
lastSlots["oppA"] = SlotState(speciesEn: "Incineroar", hpPercent: 46)
lastSlots["oppB"] = SlotState(speciesEn: "Floette-Eternal", hpPercent: 61)
monStates["p2:Floette-Eternal"] = MonState(); monStates["p2:Floette-Eternal"]!.hpPercent = 61
emittedSwitchKeys.insert("p2:Floette-Eternal")
_ = translateBattleMessage("あいて相手のフラエッテのとくこうとくぼう特攻特防が上がった！")
let t140gAfterT2 = battleLog.filter { $0.contains("boost|p2b: Floette-Eternal") }.count
currentTurn = 3
_ = translateBattleMessage("相手のフラエッテのめいそう！")
_ = translateBattleMessage("相手のフラエッテのとくにう特攻特防が上がった！")
_ = translateBattleMessage("あいて相手のフラエッテのとくこうとくぼう特攻特防が上がった！")
let t140gAfterT3 = battleLog.filter { $0.contains("boost|p2b: Floette-Eternal") }.count
check("T140g PROBE calm mind boosts land on both turns", t140gAfterT2 == 2 && t140gAfterT3 == 4)

// T145 (battle_20261122_231107 切り分け): ターン2末のひんし交代で
// 登場した Charizard がターン3に行動前に倒れた場面の spe イベント。
// recordDamageEvent を直接呼び、battleLog の状態だけを変えて
// 生成条件 (slowEntered 判定) の効き方を確認する
func t145Setup(_ log: [String]) {
    resetAll()
    battleEvents = []
    lastExactHp = [:]
    lastDmgEventPrevExact = [:]
    battleLog = log
    currentTurn = 3
    monStates["p2:Basculegion-F"] = MonState(hpPercent: 80, hpText: "80/100")
    monStates["p1:Charizard"] = MonState(hpPercent: 100, hpText: "153/153")
    lastMoveLabel = "p2b: Basculegion-F"
    lastMoveName = "Muddy Water"
    actionSeq = 5
    lastMoveSeq = 5
    lastMoveMsgAt = Date()
}
func t145HasSpe() -> Bool { battleEvents.contains { $0.contains("\"k\":\"spe\"") } }
func t145HasDmg() -> Bool { battleEvents.contains { $0.contains("\"k\":\"dmg\"") } }
// A: |turn|3 がまだ battleLog に無い (フォールバックで |turn|2 が錨)
t145Setup(["|turn|2", "|switch|p1b: Charizard|Charizard|153/153"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145a no |turn|3 yet: dmg created, spe suppressed", t145HasDmg() && !t145HasSpe())
// B: |turn|3 はあるが、交代行がその後ろに登録されている (遅延登録)
t145Setup(["|turn|2", "|turn|3", "|switch|p1b: Charizard|Charizard|153/153"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145b switch registered after |turn|3: spe suppressed", t145HasDmg() && !t145HasSpe())
// C: 対照: 交代行が |turn|3 より前に登録されている通常形
t145Setup(["|turn|2", "|switch|p1b: Charizard|Charizard|153/153", "|turn|3"])
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145c switch before |turn|3: spe created", t145HasDmg() && t145HasSpe())
// D (ダメージ計算側の論点 a): 範囲技が別対象に外れてから命中した
// 並び (ミス行 + 使用者の mv イベント) があっても、交代行が正しい
// 位置にあれば spe は生成される (ミスは生成条件に触れない)
t145Setup(["|turn|2", "|switch|p1b: Charizard|Charizard|153/153", "|turn|3", "|move|p2b: Basculegion-F|Muddy Water", "|-miss|p2b: Basculegion-F|p1a: Venusaur"])
battleEvents.append("{\"k\":\"mv\",\"turn\":3,\"label\":\"p2b: Basculegion-F\",\"move\":\"Muddy Water\"}")
recordDamageEvent(slot: "p1b", key: "p1:Charizard", speciesEn: "Charizard", fromPct: 100, toPct: 0, hpText: "0/153", directMove: true)
check("T145d miss-then-hit sequence does not suppress spe", t145HasDmg() && t145HasSpe())

// T146 (battle_20261122_231107): ヘッダー補正の置換先は誤同定の枠。
// Barbaracle (pick 0.45) の次点が実登場の Basculegion-F (0.591)、
// Sneasler (-0.19) の次点は 0.707 で大差。正しい Sneasler を残し
// Barbaracle を落とすこと
let hdr2Proto = ["|gametype|doubles",
                 "|poke|p2|Golisopod", "|poke|p2|Raichu", "|poke|p2|Pelipper", "|poke|p2|Barbaracle", "|poke|p2|Archaludon", "|poke|p2|Sneasler",
                 "|start",
                 "|switch|p2a: Pelipper|Pelipper|100/100",
                 "|switch|p2b: Basculegion-F|Basculegion-F|100/100",
                 "|switch|p2a: Archaludon|Archaludon|100/100",
                 "|switch|p2b: Golisopod|Golisopod|100/100"]
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

// T150 (battle_20261123_043809): suspect 解消の ±3 採用、最大 HP のバースト不採用と取消し、漢字「眠」、Detect の activate
// a: 保留値の ±3 以内の読みは次ターンに無音採用される
resetAll()
battleEvents = []; lastExactHp = [:]; lastDmgEventPrevExact = [:]
currentTurn = 3
monStates["p2:Dragonite"] = MonState()
monStates["p2:Dragonite"]?.hpPercent = 54
suspectJump["oppB"] = (toPct: 6, turn: 3, hpText: "6/100")
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
suspectJump["oppB"] = (toPct: 6, turn: 3, hpText: "6/100")
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
lastSlots = ["oppA": SlotState(speciesEn: "Primarina", hpPercent: 63)]
if !speciesDict.contains(where: { $0.en == "Primarina" }) { speciesDict.append(E("アシレーヌ", "Primarina")) }
check("T150d salvage kanji sleep", salvageStatus(in: "相手のアシレーヌは眠ってしまった！") && battleLog.contains("|-status|p2a: Primarina|slp"))
check("T150d yawn text not salvaged as sleep", !salvageStatus(in: "相手のアシレーヌは眠気を誘った！"))
// e: Detect の成功文に activate 行 (move: Detect) が付く
resetAll()
logStarted = true
currentTurn = 6
lastSingleActAt = [:]
lastSlots = ["mineA": SlotState(speciesEn: "Sylveon", hpPercent: 88)]
if !speciesDict.contains(where: { $0.en == "Sylveon" }) { speciesDict.append(E("ニンフィア", "Sylveon")) }
emitLog("|move|p1a: Sylveon|Detect")
_ = translateBattleMessage("ニンフィアは攻撃から身を守った！")
check("T150e detect activate emitted", battleLog.contains("|-activate|p1a: Sylveon|move: Detect"))
// T151 (battle_20261123_052626): 技リスト誤認 / 勝敗文の化け / Stamina 帰属 / block 行 / 天候の付け直し
// a: コマンド画面の技リスト連結文は技リストと判定し、実告知と種族名に重なる技名は数えない
moveNameOrig[normalize("てだすけ")] = "てだすけ"; moveJa2En["てだすけ"] = "Helping Hand"
moveNameOrig[normalize("サイコキネシス")] = "サイコキネシス"; moveJa2En["サイコキネシス"] = "Psychic"
moveNameOrig[normalize("でんじは")] = "でんじは"; moveJa2En["でんじは"] = "Thunder Wave"
moveNameOrig[normalize("つるぎのまい")] = "つるぎのまい"; moveJa2En["つるぎのまい"] = "Swords Dance"
check("T151a move list text detected", isMoveListText("リキキリンサイコキネシスてだすけ10まんボルトでんじは"))
check("T151a real announcement not a list", !isMoveListText("リキキリンの てだすけ！"))
check("T151a species-substring move not counted", !isMoveListText("カイリキーの つるぎのまい！"))
// b: 勝ち文の「勝負」が「勝質」に崩れても |win| になる
resetAll()
_ = translateBattleMessage("Kiwiとの勝質に勝った！")
check("T151b garbled win text produces win", battleLog.contains(where: { $0.hasPrefix("|win|") }) && winLogged)
// c: 被ダメ直後の防御 +1 上昇に Stamina の特性行が先行する
resetAll()
speciesAbilityMap["Archaludon"] = ["Stamina"]
monStates["p2:Archaludon"] = MonState()
emittedSwitchKeys.insert("p2:Archaludon")
lastMoveLabel = "p1a: Garchomp"; lastMoveName = "Earth Power"; lastMoveMsgAt = Date()
damagedBySeq[actionSeq, default: []].insert("p2a: Archaludon")
checkBoostText(text: "相手のブリジュラスの 防御が上がった！", side: "p2", speciesEn: "Archaludon", slot: "p2a")
check("T151c stamina ability precedes boost", battleLog.contains("|-ability|p2a: Archaludon|Stamina") && battleLog.contains("|-boost|p2a: Archaludon|def|1") && battleLog.firstIndex(of: "|-ability|p2a: Archaludon|Stamina")! < battleLog.firstIndex(of: "|-boost|p2a: Archaludon|def|1")!)
// d: まもる成功文に block 行と activate 行の両方が付く
resetAll()
logStarted = true
currentTurn = 3
lastSingleActAt = [:]
lastSlots = ["oppA": SlotState(speciesEn: "Archaludon", hpPercent: 44)]
emitLog("|move|p2a: Archaludon|Protect")
_ = translateBattleMessage("相手のブリジュラスは 攻撃から 身を守った！")
check("T151d block line emitted", battleLog.contains("|-block|p2a: Archaludon|move: Protect"))
check("T151d activate line emitted", battleLog.contains("|-activate|p2a: Archaludon|move: Protect"))
// e: 特性行が先行する配置でも天候行に [from] が付く。技による開始では付かない
resetAll()
if !speciesDict.contains(where: { $0.en == "Pelipper" }) { speciesDict.append(E("ペリッパー", "Pelipper")) }
speciesAbilityMap["Pelipper"] = ["Keen Eye", "Drizzle", "Hydration"]
emitLog("|-ability|p2b: Pelipper|Drizzle")
emitLog("|-weather|Rain Dance")
check("T151e weather attributed when ability precedes", battleLog.contains("|-weather|Rain Dance|[from] ability: Drizzle|[of] p2b: Pelipper"))
resetAll()
speciesAbilityMap["Pelipper"] = ["Keen Eye", "Drizzle", "Hydration"]
emitLog("|move|p2b: Pelipper|Rain Dance")
emitLog("|-ability|p2b: Pelipper|Drizzle")
emitLog("|-weather|Rain Dance")
check("T151e no attribution when set by move", battleLog.contains("|-weather|Rain Dance") && !battleLog.contains("|-weather|Rain Dance|[from]"))
// T152 (battle_20261123_060833): TR 補完 / ひんし同種族の誤帰属 / Overlord / マージン / 形状判定
// a: 開始文の主語から技行を補い、告知済みなら二重化しない
resetAll()
if !speciesDict.contains(where: { $0.en == "Farigiraf" }) { speciesDict.append(E("リキキリン", "Farigiraf")) }
lastSlots = ["oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100)]
monStates["p2:Farigiraf"] = MonState()
emitLog("|turn|1")
_ = checkFieldText(text: "相手のリキキリンは時空をゆがめた！")
check("T152a trick room move synthesized", battleLog.contains("|move|p2a: Farigiraf|Trick Room") && battleLog.contains("|-fieldstart|move: Trick Room") && battleLog.firstIndex(of: "|move|p2a: Farigiraf|Trick Room")! < battleLog.firstIndex(of: "|-fieldstart|move: Trick Room")!)
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100)]
monStates["p2:Farigiraf"] = MonState()
emitLog("|turn|1")
emitLog("|move|p2a: Farigiraf|Trick Room")
_ = checkFieldText(text: "相手のリキキリンは時空をゆがめた！")
check("T152a no duplicate when announced", battleLog.filter { $0 == "|move|p2a: Farigiraf|Trick Room" }.count == 1)
// b: 倒れた相手の同種族が枠に残っていても、自軍への低下が相手へ付かない
resetAll()
for (ja, en) in [("マフォクシー", "Delphox"), ("コータス", "Torkoal")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37),
             "mineB": SlotState(speciesEn: "Farigiraf", hpPercent: 0),
             "oppA": SlotState(speciesEn: "Farigiraf", hpPercent: 100),
             "oppB": SlotState(speciesEn: "Torkoal", hpPercent: 0)]
monStates["p1:Delphox"] = MonState(); monStates["p2:Torkoal"] = MonState()
faintedSpecies = ["p2:Torkoal", "p1:Farigiraf"]
emittedSwitchKeys = ["p1:Delphox", "p2:Farigiraf", "p2:Torkoal"]
teamEntries["Delphox"] = ["item": "Delphoxite"]
lastMoveLabel = "p1a: Delphox"; lastMoveMsgAt = Date()
_ = translateBattleMessage("マフォクシーとコータスのこうげきが下がった！")
check("T152b fainted namesake not used", !battleLog.contains("|-unboost|p2b: Torkoal|atk|1"))
recordSwitchIn(side: "p1", slot: "p1b", speciesEn: "Torkoal")
check("T152b boost lands on mine after switch-in", battleLog.contains("|-unboost|p1b: Torkoal|atk|1"))
// c: そうだいしょうの定型文は交代確定まで保留され、確定時に流れる (語順崩れでも)
resetAll()
if !speciesDict.contains(where: { $0.en == "Kingambit" }) { speciesDict.append(E("ドドゲザン", "Kingambit")) }
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37), "mineB": SlotState(speciesEn: "Torkoal", hpPercent: 100)]
fieldSeen["p1"] = ["Delphox", "Torkoal", "Kingambit"]
_ = translateBattleMessage("ドドゲザンは倒された仲間から力をもらった！")
check("T152c overlord held before switch-in", !battleLog.contains(where: { $0.contains("Supreme Overlord") }) && pendingAbilityReveal["p1:Kingambit"] == "Supreme Overlord")
recordSwitchIn(side: "p1", slot: "p1a", speciesEn: "Kingambit")
check("T152c overlord emitted at switch-in", battleLog.contains("|-ability|p1a: Kingambit|Supreme Overlord"))
resetAll()
speciesAbilityMap["Kingambit"] = ["Defiant", "Supreme Overlord", "Inner Focus"]
lastSlots = ["mineA": SlotState(speciesEn: "Delphox", hpPercent: 37), "mineB": SlotState(speciesEn: "Torkoal", hpPercent: 100)]
fieldSeen["p1"] = ["Delphox", "Torkoal", "Kingambit"]
_ = translateBattleMessage("ドドゲザンはもらった！仲間から倒された力を")
check("T152c scrambled text also held", pendingAbilityReveal["p1:Kingambit"] == "Supreme Overlord")
// d: マージンは同種族のフォルム差を飛ばして別種族との差を取る
check("T152d forme margin skipped", headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114), ("Garchomp", 0.300)]) != nil && abs(headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114), ("Garchomp", 0.300)])! - 0.200) < 0.0001)
check("T152d distinct margin plain", headerDistinctMargin(ranked: [("Sneasler", 0.050), ("Garchomp", 0.090)]) != nil && abs(headerDistinctMargin(ranked: [("Sneasler", 0.050), ("Garchomp", 0.090)])! - 0.040) < 0.0001)
check("T152d no distinct rival", headerDistinctMargin(ranked: [("Aegislash-Blade", 0.100), ("Aegislash-Shield", 0.114)]) == nil)
// e: 漢字能力名の化け断片でも形状として消費される
check("T152e garbled stat shape", isBoostShapedText("マフォクシーとコータスの政撃が下がった！"))
// T153 (battle_20261123_062508): 保留した低下が更なる低下で裏づけられたら行として出す
// a: sibling 保留 → 分類済みチップで 2 行に分かれる
resetAll()
for (ja, en) in [("ミロカロス", "Milotic"), ("バンギラス", "Tyranitar")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Tyranitar"]?.hpText = "86/100"
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 100, toPct: 86, hpText: "86/100", force: true)
check("T153a held by sibling", battleLog.filter { $0.contains("|-damage|") }.isEmpty && suspectJump["oppA"]?.toPct == 86)
pendingStatusFrom["p2:Milotic"] = ("sandstorm", Date())
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 100, toPct: 80, hpText: "80/100", force: true)
check("T153a held segment emitted first", battleLog.contains("|-damage|p2a: Milotic|86/100") && battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm") && battleLog.firstIndex(of: "|-damage|p2a: Milotic|86/100")! < battleLog.firstIndex(of: "|-damage|p2a: Milotic|80/100|[from] sandstorm")!)
// b: sibling 保留 → 未分類の更なる低下でも 2 行出て、再保留されない
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Milotic"]?.hpText = "85/100"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 85, hpText: "85/100", force: true)
check("T153b held by sibling", suspectJump["oppB"]?.toPct == 85)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 7, hpText: "7/100", force: true)
check("T153b both lines emitted", battleLog.contains("|-damage|p2b: Tyranitar|85/100") && battleLog.contains("|-damage|p2b: Tyranitar|7/100") && suspectJump["oppB"] == nil)
// c: 保留 → ひんしでも保留分が先に出る
resetAll()
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|2")
monStates["p2:Milotic"]?.hpText = "85/100"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 85, hpText: "85/100", force: true)
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Tyranitar", speciesEn: "Tyranitar", fromPct: 100, toPct: 0, hpText: "0/100", force: true)
check("T153c held then faint", battleLog.contains("|-damage|p2b: Tyranitar|85/100") && battleLog.contains("|-damage|p2b: Tyranitar|0/100"))
// T154: あり得ない最大値の読みは状態に採用しない (幽霊行の防止)
resetAll()
if !speciesDict.contains(where: { $0.en == "Kingambit" }) { speciesDict.append(E("ドドゲザン", "Kingambit")) }
teamEntries["Kingambit"] = ["item": "Life Orb", "stats": ["hp": 177]]
lastSlots = ["mineA": SlotState(speciesEn: "Kingambit", hpPercent: 100, hpCur: 177, hpMax: 177)]
monStates["p1:Kingambit"] = MonState(); monStates["p1:Kingambit"]?.hpPercent = 100; monStates["p1:Kingambit"]?.hpText = "177/177"; monStates["p1:Kingambit"]?.hpMax = 177
emittedSwitchKeys.insert("p1:Kingambit")
emitLog("|turn|5")
processPlates(["mineA": SlotState(speciesEn: "Kingambit", hpPercent: 64, hpCur: 177, hpMax: 277)])
check("T154 implausible max dropped", lastSlots["mineA"]?.hpPercent == 100 && (monStates["p1:Kingambit"]?.hpText ?? "") == "177/177" && !battleLog.contains(where: { $0.contains("|-damage|") }))
// T155: ひんし文経路の分母は登録最大で統一される
resetAll()
if !speciesDict.contains(where: { $0.en == "Torkoal" }) { speciesDict.append(E("コータス", "Torkoal")) }
teamEntries["Torkoal"] = ["item": "Charcoal", "stats": ["hp": 177]]
lastSlots = ["mineB": SlotState(speciesEn: "Torkoal", hpPercent: 24, hpCur: 43, hpMax: 177)]
monStates["p1:Torkoal"] = MonState(); monStates["p1:Torkoal"]?.hpPercent = 24; monStates["p1:Torkoal"]?.hpText = "43/177"
lastEmittedPct["mineB"] = 24
emittedSwitchKeys.insert("p1:Torkoal")
_ = translateBattleMessage("コータスは たおれた！")
check("T155 faint denominator", battleLog.contains("|-damage|p1b: Torkoal|0/177"))
// T156: 同じ行動の外れ文は 1 行だけ
resetAll()
for (ja, en) in [("フシギバナ", "Venusaur"), ("バンギラス", "Tyranitar")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
moveNameOrig[normalize("リーフストーム")] = "リーフストーム"; moveJa2En["リーフストーム"] = "Leaf Storm"
lastSlots = ["mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100), "oppB": SlotState(speciesEn: "Tyranitar", hpPercent: 100)]
for k in ["p1:Venusaur", "p2:Tyranitar"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|1")
emitLog("|move|p1a: Venusaur|Leaf Storm")
lastMoveLabel = "p1a: Venusaur"; lastMoveMsgAt = Date()
_ = translateBattleMessage("相手のバンギラスには当たらなかった！")
_ = translateBattleMessage("相手のバンギラスには当たらなかった！")
check("T156 miss not duplicated", battleLog.filter { $0.hasPrefix("|-miss|") }.count == 1)
// T157: 反動行の処理が次の技より遅れても [from] が付く
resetAll()
for (ja, en) in [("ムクホーク", "Staraptor"), ("ミロカロス", "Milotic"), ("フシギバナ", "Venusaur"), ("コータス", "Torkoal")] {
    if !speciesDict.contains(where: { $0.en == en }) { speciesDict.append(E(ja, en)) }
}
moveNameOrig[normalize("ブレイブバード")] = "ブレイブバード"; moveJa2En["ブレイブバード"] = "Brave Bird"
moveNameOrig[normalize("ねっとう")] = "ねっとう"; moveJa2En["ねっとう"] = "Scald"
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 100), "oppB": SlotState(speciesEn: "Staraptor", hpPercent: 100),
             "mineA": SlotState(speciesEn: "Venusaur", hpPercent: 100), "mineB": SlotState(speciesEn: "Torkoal", hpPercent: 100)]
for k in ["p2:Milotic", "p2:Staraptor", "p1:Venusaur", "p1:Torkoal"] { monStates[k] = MonState(); monStates[k]?.hpPercent = 100; monStates[k]?.hpText = "100/100"; emittedSwitchKeys.insert(k) }
emitLog("|turn|4")
emitLog("|move|p2b: Staraptor|Brave Bird")
_ = emitDamageLine(plateName: "mineA", slot: "p1a", key: "p1:Venusaur", speciesEn: "Venusaur", fromPct: 100, toPct: 20, hpText: "20/100", force: true)
emitLog("|move|p2a: Milotic|Scald")
lastMoveLabel = "p2a: Milotic"; lastMoveMsgAt = Date()
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Staraptor", speciesEn: "Staraptor", fromPct: 100, toPct: 75, hpText: "75/100", force: true)
check("T157 late recoil classified", battleLog.contains("|-damage|p2b: Staraptor|75/100|[from] move: Brave Bird") && battleEvents.contains(where: { $0.contains("\"atk\":\"p2b: Staraptor\"") && $0.contains("\"def\":\"p2b: Staraptor\"") && $0.contains("\"move\":\"Brave Bird\"") }))
// T158: 砂あらじの化け文でも天候チップとして消費され [from] が付く
resetAll()
if !speciesDict.contains(where: { $0.en == "Milotic" }) { speciesDict.append(E("ミロカロス", "Milotic")) }
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 86)]
monStates["p2:Milotic"] = MonState(); monStates["p2:Milotic"]?.hpPercent = 86; monStates["p2:Milotic"]?.hpText = "86/100"
emittedSwitchKeys.insert("p2:Milotic")
_ = translateBattleMessage("砂あらじが相手のミロカロスを襲う！")
check("T158 garbled sandstorm consumed", (pendingStatusFrom["p2:Milotic"]?.code ?? "") == "sandstorm" && !battleLog.contains(where: { $0.hasPrefix("|-message|") }))
_ = emitDamageLine(plateName: "oppA", slot: "p2a", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 86, toPct: 80, hpText: "80/100", force: true)
check("T158 chip line has from", battleLog.contains("|-damage|p2a: Milotic|80/100|[from] sandstorm"))
// T159 (手動フラグモード): 制御の取り込みと自動オンの抑止
// a: 起動後の最初の取り込みは連番を採用するだけで実行しない
resetAll()
flagManualMode = false; flagStartSeqSeen = 0; flagEndSeqSeen = 0; flagControlAdopted = false; logStarted = false; inBattle = false
applyFlagControl(mode: "manual", startSeq: 5, endSeq: 2)
check("T159a adoption only", flagControlAdopted && flagManualMode && !logStarted && flagStartSeqSeen == 5 && flagEndSeqSeen == 2)
// b: 開始要求で開始し、phase が inBattle になる
applyFlagControl(mode: "manual", startSeq: 6, endSeq: 2)
check("T159b manual start", logStarted && inBattle && flagPhase() == "inBattle" && flagModeName() == "manual")
// c: 開始済みへの開始要求は再開始しない (冪等)
let logCount159 = battleLog.count
applyFlagControl(mode: "manual", startSeq: 7, endSeq: 2)
check("T159c duplicate start ignored", battleLog.count == logCount159 && flagStartSeqSeen == 7)
// d: 終了要求でフラグが立ち phase が idle に戻る
applyFlagControl(mode: "manual", startSeq: 7, endSeq: 3)
check("T159d manual end", winLogged && !inBattle && flagPhase() == "idle")
// e: auto モードでは要求を実行しない
resetAll()
flagManualMode = true; flagStartSeqSeen = 0; flagEndSeqSeen = 0; flagControlAdopted = false; logStarted = false; inBattle = false
applyFlagControl(mode: "auto", startSeq: 1, endSeq: 0)
applyFlagControl(mode: "auto", startSeq: 2, endSeq: 0)
check("T159e auto ignores requests", !flagManualMode && !logStarted && flagStartSeqSeen == 2)
// f: 手動モードでは勝敗文でフラグが立たない (行は残る)
resetAll()
flagManualMode = true; winLogged = false
_ = translateBattleMessage("Kiwiとの勝負に勝った！")
check("T159f win line without flag", battleLog.contains("|win|Ren") && !winLogged)
// g: 自動モードでは従来どおりフラグが立つ
resetAll()
flagManualMode = false; winLogged = false
_ = translateBattleMessage("Kiwiとの勝負に勝った！")
check("T159g auto win sets flag", winLogged)
// h: state.json に battlePhase / flagMode が載る
resetAll()
flagManualMode = true
if !speciesDict.contains(where: { $0.en == "Milotic" }) { speciesDict.append(E("ミロカロス", "Milotic")) }
lastSlots = ["oppA": SlotState(speciesEn: "Milotic", hpPercent: 66)]
monStates["p2:Milotic"] = MonState(); monStates["p2:Milotic"]?.hpPercent = 66; monStates["p2:Milotic"]?.hpText = "66/100"
writeState()
let stFlag = (try? String(contentsOfFile: "/tmp/harness_state.json", encoding: .utf8)) ?? ""
check("T159h state carries flag", stFlag.contains("\"battlePhase\": \"inBattle\"") && stFlag.contains("\"flagMode\": \"manual\""))
// T160 (安全網の下書き保存の無効化): 条件が揃ってもスイッチが
// 切れていれば due にならない。スイッチを入れれば従来どおり
resetAll()
battleLog = ["|gametype|doubles", "|start"]
battleArchived = false; winLogged = false
emptyBattleFrames = 31
lastLogEventAt = Date().addingTimeInterval(-100)
lastArchiveSnapshotCount = -1
interruptedSaveEnabled = false
check("T160a suspended stays not due", !safetyNetDraftDue())
interruptedSaveEnabled = true
check("T160b enabled becomes due", safetyNetDraftDue())
winLogged = true
check("T160c win settled stays not due", !safetyNetDraftDue())
winLogged = false; emptyBattleFrames = 10
check("T160d frames short stays not due", !safetyNetDraftDue())
interruptedSaveEnabled = false

// ===== END PROBE-B =====
// ===== END PROBE =====

// ===== T161 (battle_20261123_090354) =====
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
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 68, toPct: 62, hpText: "62/100", force: true)
check("T161i burn chip attributed from status", battleLog.contains("|-damage|p2b: Milotic|62/100|[from] brn"))
resetAll()
monStates["p2:Milotic"] = MonState()
monStates["p2:Milotic"]?.status = "brn"
monStates["p2:Milotic"]?.hpPercent = 68
logFieldWeather = "Sand"
_ = emitDamageLine(plateName: "oppB", slot: "p2b", key: "p2:Milotic", speciesEn: "Milotic", fromPct: 68, toPct: 62, hpText: "62/100", force: true)
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

// ===== T162 (delayed print, plan 2) =====
// a: 確定境界は最後の Turn 見出しの位置。現在の区間は印刷されない
resetAll()
displayLog = ["you and Opponent joined", "Your team:", "Venusaur / Torkoal", "Turn 1", "Go! Venusaur!", "Go! Torkoal!"]
var printed162: [String] = []
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a only the header prints before Turn 2", printed162 == ["you and Opponent joined", "Your team:", "Venusaur / Torkoal"])
displayLog.append("The opposing Excadrill used Protect!")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a current segment stays unprinted", printed162.count == 3)
displayLog.append("Turn 2")
displayLog.append("Go! Kingambit!")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162a previous segment prints when the next heading lands", printed162 == Array(displayLog[0..<7]) && printed162.count == 7)
// b: 現在の区間への差し込みは、区間が閉じるまで印刷されず、閉じた後は差し込み位置どおりに出る
let before162 = printed162
displayLog.insert("The opposing Milotic was burned!", at: 8)
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162b insertion in the current segment is not printed early", printed162 == before162)
displayLog.append("Turn 3")
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162b inserted line prints in its final position", printed162 == Array(displayLog[0..<printed162.count]) && printed162[8] == "The opposing Milotic was burned!")
// c: pullback の後でも印刷済み接頭辞は崩れない
resetAll()
displayPrintedCount = 0
battleLog = ["|turn|2", "|move|p2a: Excadrill|Protect", "|switch|p2b: Milotic|Milotic|100/100"]
displayLog = ["Turn 1", "Go! Excadrill!", "Turn 2", "The opposing Excadrill used Protect!", "Opponent sent out Milotic!"]
printed162 = takeDisplayPrintLines(isFinal: false)
check("T162c prints up to the current heading", printed162 == ["Turn 1", "Go! Excadrill!"])
let pb162 = pullBackSwitchBlock(label: "p2b: Milotic")
if !pb162.display.isEmpty, let ti = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) {
    displayLog.insert(contentsOf: pb162.display, at: ti + 1)
}
printed162 += takeDisplayPrintLines(isFinal: false)
check("T162c pullback keeps the printed prefix intact", printed162 == Array(displayLog[0..<printed162.count]))
// d: 最終フラッシュで全文が一致する
printed162 += takeDisplayPrintLines(isFinal: true)
check("T162d final flush matches the whole log", printed162 == displayLog && displayPrintedCount == displayLog.count)
// e: 印刷カウンタは後退しない
let cnt162 = displayPrintedCount
_ = takeDisplayPrintLines(isFinal: false)
check("T162e print counter never retreats", displayPrintedCount == cnt162)

// ===== T163 (header completion gating) =====
func headerFixture163() -> [String] {
    return ["you and Opponent joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg M-C", "Rated battle",
            "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
            "Your team:", "Venusaur / Torkoal / Garchomp / Delphox / Farigiraf / Kingambit",
            "Opponent's team:", "Excadrill / Tyranitar / Milotic / Sinistcha", "",
            "Battle started between you and Opponent!", ""]
}
// a: 判明前はヘッダーも後続も印刷されない
resetAll()
displayLog = headerFixture163()
headerLineCount = displayLog.count
trainerOpp = ""
oppTeamSeen = ["Excadrill", "Tyranitar", "Milotic", "Sinistcha"]
previewHandled = false
displayLog.append("Turn 1")
displayLog.append("Go! Venusaur!")
check("T163a nothing prints before identification completes", takeDisplayPrintLines(isFinal: false).isEmpty && displayPrintedCount == 0)
// b: 2条件がそろった時点で完成形に書き直され、印刷範囲に入る
trainerOpp = "くさ"
oppTeamSeen = ["Excadrill", "Tyranitar", "Milotic", "Sinistcha", "Staraptor", "Gholdengo"]
refreshHeaderState()
check("T163b header rewritten in completed form", displayLog[0] == "Ren and くさ joined" && displayLog[8] == "くさ's team:" && displayLog[9] == "Excadrill / Tyranitar / Milotic / Sinistcha / Staraptor / Gholdengo" && displayLog[11] == "Battle started between Ren and くさ!")
check("T163b header released to the printer", headerPrintReady && displayPrintedCount == headerLineCount)
// c: 同定終了時の例外 — そろっている分で完成する
resetAll()
displayLog = headerFixture163()
headerLineCount = displayLog.count
trainerOpp = ""
oppTeamSeen = ["Excadrill", "Tyranitar"]
previewHandled = true
refreshHeaderState()
check("T163c partial header completes at identification end", headerPrintReady && displayLog[9] == "Excadrill / Tyranitar" && displayLog[0] == "Ren and Opponent joined")
// d: 最終フラッシュで全文が一致する
displayLog.append("Turn 1")
let rest163 = takeDisplayPrintLines(isFinal: true)
check("T163d final flush matches the whole log", displayPrintedCount == displayLog.count && rest163.count == 1)

// ===== T164 (manual start state.json reset) =====
func stateJson164() -> [String: Any]? {
    guard let data = try? Data(contentsOf: outURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return obj
}
func clearState164() {
    try? FileManager.default.removeItem(at: outURL)
    lastWritten = ""
}
// a: 手動開始の時点で初期化した形が書き出される (applyFlagControl 経由)
resetAll()
clearState164()
logStarted = false
flagControlAdopted = true
flagStartSeqSeen = 0
flagEndSeqSeen = 0
previewTeamWritten = false
oppTeamSeen = []
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 0)
if let obj = stateJson164() {
    check("T164a manual start writes the reset shape", (obj["oppReset"] as? Bool) == true && (obj["mine"] as? [Any])?.count == 0 && (obj["opps"] as? [Any])?.count == 0 && (obj["oppTeam"] as? [Any])?.count == 0 && (obj["battlePhase"] as? String) == "inBattle" && (obj["flagMode"] as? String) == "manual")
} else {
    check("T164a manual start writes the reset shape", false)
}
// b: 同定済みの新しい試合の oppTeam と mineTeam は保持される
resetAll()
clearState164()
previewTeamWritten = true
oppTeamSeen = ["Milotic", "Staraptor", "Tyranitar", "Sinistcha", "Excadrill", "Gholdengo"]
minePreviewTeam = ["Venusaur", nil, nil, nil, nil, nil]
minePreviewDetails = [["species": "Venusaur"], [:], [:], [:], [:], [:]]
battleArchiveId = "20261123_120000"
battleEvents = []
writeManualStartResetState()
if let obj = stateJson164() {
    let team = (obj["oppTeam"] as? [Any])?.map { ($0 as? String) ?? "?" } ?? []
    let mineTeam = obj["mineTeam"] as? [Any] ?? []
    check("T164b identified teams are preserved", team == ["Milotic", "Staraptor", "Tyranitar", "Sinistcha", "Excadrill", "Gholdengo"] && mineTeam.count == 6 && (obj["oppReset"] as? Bool) == true && (obj["battle"] as? String) == "20261123_120000" && (obj["events"] as? [Any])?.count == 0)
} else {
    check("T164b identified teams are preserved", false)
}
// c: 自動モードの開始では初期化書き出しは起きない (既存の流れは不変)
resetAll()
clearState164()
flagControlAdopted = true
flagStartSeqSeen = 0
flagEndSeqSeen = 0
previewTeamWritten = false
applyFlagControl(mode: "auto", startSeq: 1, endSeq: 0)
check("T164c auto start writes no reset state", stateJson164() == nil)

// ===== T165 (battle end state.json write, flag series) =====
// a: 終了要求の取り込み後に state.json が書き出され、phase は idle
resetAll()
clearState164()
battleLog = ["|turn|1", "|move|p1a: Blastoise|Surf"]
battleArchived = false
battleArchiveId = "20261123_111415"
lastSlots["mineA"] = SlotState(speciesEn: "Blastoise", hpPercent: 100)
lastSlots["oppA"] = SlotState(speciesEn: "Excadrill", hpPercent: 100)
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 0
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
if let obj = stateJson164() {
    check("T165a end writes state with idle phase", winLogged && (obj["battlePhase"] as? String) == "idle" && (obj["flagMode"] as? String) == "manual")
} else {
    check("T165a end writes state with idle phase", false)
}
// b: 場の情報が無い場合も、リセット形で phase が書き出される
resetAll()
clearState164()
battleLog = ["|turn|1"]
battleArchived = false
battleArchiveId = "20261123_111415"
lastSlots = [:]
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 0
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
if let obj = stateJson164() {
    check("T165b end writes the reset shape when the field is empty", (obj["battlePhase"] as? String) == "idle" && (obj["oppReset"] as? Bool) == true)
} else {
    check("T165b end writes the reset shape when the field is empty", false)
}
// c: 終了要求が増えていない場合は書き出されない
resetAll()
clearState164()
battleLog = ["|turn|1"]
battleArchived = false
lastSlots["mineA"] = SlotState(speciesEn: "Blastoise", hpPercent: 100)
flagControlAdopted = true
flagStartSeqSeen = 1
flagEndSeqSeen = 1
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 1)
check("T165c no end request, no write", stateJson164() == nil && !winLogged)

out(failures == 0 ? "ALL PASS" : "\(failures) FAILURES")
