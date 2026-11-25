#!/usr/bin/env python3
"""reader.swift から対象関数を verbatim 抽出して検証ハーネスを生成する。"""
import re, sys

SRC = open('/home/hatch/workspace/champions_calc/reader.swift').read()

def extract_func(name, src=SRC):
    i = src.index(f'func {name}(')
    j = src.index('{', i)
    depth = 0
    k = j
    while True:
        c = src[k]
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: break
        k += 1
    return src[i:k + 1]

def extract_struct(name, src=SRC):
    i = src.index(f'struct {name}')
    j = src.index('{', i)
    depth = 0
    k = j
    while True:
        c = src[k]
        if c == '{': depth += 1
        elif c == '}':
            depth -= 1
            if depth == 0: break
        k += 1
    return src[i:k + 1]

FUNCS = [
    'normalize', 'foldDakuten', 'levenshtein', 'editDistance',
    'findSpeciesJa', 'findAllSpeciesJa', 'findSpeciesJaLoose', 'moveNameLoose', 'findInDict', 'looseText', 'parseMineHPText', 'asciiDigits', 'numberGroups', 'recordDecode',
    'slotId', 'slotFor', 'formeGroup', 'anchoredSpecies', 'fieldAnchoredSpecies', 'anchoredSpeciesForText',
    'isRoundEventLine',
    'healExplained', 'debugStateExcerpt', 'checkHeaderMismatch', 'boostSubjects',
    'emitAbilityOnce', 'emitItemOnce', 'correctFormeByAbility', 'attributeIntimidate', 'attributeFieldAbilities',
    'setWeather', 'clearWeather', 'setTerrain', 'clearTerrain', 'retroSeedCheck', 'applyMoveField', 'applyAbilityField',
    'emitHazard', 'clearSideHazards',
    'checkFieldText', 'checkStatusText', 'checkBoostText', 'applyBoost', 'copyBoosts',
    'flushHeldBoosts', 'flushHeldBoostsTimeout',
    'completeMega', 'synthesizeMegaIfPending', 'recordSwitchIn', 'megaTextSide',
    'isBoostShapedText', 'isMoveFragmentText', 'translateBattleMessage',
    'hpTextFor', 'emitDamageLine', 'deferFaint', 'faintStillValid', 'emitPendingFaints',
    'flushPendingDamage', 'recordDamageEvent', 'recordRecoilEvent', 'aliveOnFieldCount', 'awaitingReplacement', 'anyAwaitingReplacement', 'sideAwaitingReplacement', 'entryEffectPending', 'processPlates', 'crossCheckPlateSpecies', 'fingerprintFiles',
    'salvageFromText', 'salvageSubject', 'salvageBoost', 'salvageStatus', 'salvageItem', 'salvageField',
    'textSimilarity', 'debugShouldCapture',
    'sameSpeciesFamily', 'abilityLinePlausible', 'moveLineHardImplausible', 'moveLineOffField', 'completeArchiveHeader', 'flushHeldEntryBoosts', 'itemLineImplausible', 'pendingMegaForme', 'completePendingMegaForField', 'expectedStats', 'statsFitForme', 'noteStateWrite', 'battleEventsObjects', 'adoptStateSnapshotsForBattle', 'terrainSourcePlausible', 'confirmHeldTerrainReplace', 'fieldLineForAbility', 'annotateFieldLineFromAbility', 'fieldLineWithAttribution', 'isMoveListText', 'headerDistinctMargin', 'maxReadPlausible', 'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment', 'writeManualStartResetState', 'writeBattleEndState', 'safetyNetDraftDue', 'confirmedDisplayCount', 'takeDisplayPrintLines', 'flushDisplayPrint', 'completeDisplayHeader', 'refreshHeaderState', 
    'renderLogLine', 'renderLabelParts', 'renderPrefix', 'renderPct',
    'healSource', 'boostLine', 'translateLogEntry', 'validatedSide', 'regexGroups', 'pullBackSwitchBlock', 'minePlateAdmitted', 'noteBattleMaxRead', 'battleKnownMax', 'fieldSourceOnField', 'megaLabelSpecies', 'syncMineProvisional', 'mineTeamJSON', 'noteMineMove', 'mergeMineDetailFromCapture', 'mineProvisionalSpecies', 'announcedSlot',
    'noteItemLost', 'writeState', 'trackFieldEvent', 'turnsLeft', 'jsonEscape', 'applyEvent', 'parseSlotSpecies',
]

CONSTS = ['stateTopKeys', 'stateMonKeys', 'stateBoostKeys', 'stateRevealedKeys', 'stateFieldKeys', 'sideCondDurations', 'fieldDurations', 'weatherUiByLogName', 'hazardCaps']

def extract_const(name, src=SRC):
    for line in src.split('\n'):
        s = line.strip()
        if s.startswith('let ' + name + ' ') or s.startswith('let ' + name + ':') or s.startswith('let ' + name + '='):
            return line
    raise KeyError('const not found: ' + name)


prelude = r'''
import Foundation

func out(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
var failures = 0
func check(_ name: String, _ cond: Bool) {
    if cond { out("PASS \(name)") } else { failures += 1; out("FAIL \(name)") }
}

''' + extract_struct('SpeciesEntry') + '\n' + extract_struct('SlotState') + '\n' + extract_struct('MonState') + r'''

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

'''

body = '\n'.join(extract_const(c) for c in CONSTS) + '\n\n' + '\n\n'.join(extract_func(f) for f in FUNCS)

driver = r'''
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
'''

open('/home/hatch/workspace/logfix_test/harness.swift', 'w').write(prelude + body + driver)
print('harness written')
