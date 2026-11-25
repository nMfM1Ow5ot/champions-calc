#!/usr/bin/env python3
# reader.swift patch: manual flag mode (UI button starts/ends battles).
# Aborts without writing if any anchor count mismatches.
import re, sys, datetime

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
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

# R1: state.json top-level key documentation
rep('''let stateTopKeys: Set<String> = ["mine", "opps", "oppTeam", "oppRevealed", "oppTrainer", "events", "field", "sideConditions", "hazards", "oppReset", "oppPreview", "battle", "minePreview", "mineTeam"]''',
    '''let stateTopKeys: Set<String> = ["mine", "opps", "oppTeam", "oppRevealed", "oppTrainer", "events", "field", "sideConditions", "hazards", "oppReset", "oppPreview", "battle", "minePreview", "mineTeam", "battlePhase", "flagMode"]''',
    "R1 stateTopKeys")

# R2: flag globals + control functions, after the winLogged declaration
rep('''var winLogged = false                             // このバトルで勝敗が確定したか''',
    '''var winLogged = false                             // このバトルで勝敗が確定したか
// 手動フラグモード: 試合開始・終了のフラグは自動で立てず、ダメ計 UI
// 上部のボタン (serve.py の POST /battle_flag 経由で flag_control.json
// に記録される連番つき要求) でのみ立てる。出荷状態は手動モード。
// mode が auto の間は制御ファイルの要求を無視し、全て従来どおり
// 自動で立つ (自動経路のコードは削除していない)
var flagManualMode = true                         // 制御ファイルの mode で決まる (ファイルが無ければ manual)
var flagStartSeqSeen = 0                          // 取り込み済みの開始要求の連番
var flagEndSeqSeen = 0                            // 取り込み済みの終了要求の連番
var flagControlAdopted = false                    // 起動後の最初の取り込みが済んだか (古い要求を再生しない)
var flagControlExists = false                     // 制御ファイルの有無 (監視用)
var flagControlMtime: Date? = nil                 // 制御ファイルの更新時刻 (監視用)

func flagPhase() -> String { (logStarted && !winLogged) ? "inBattle" : "idle" }
func flagModeName() -> String { flagManualMode ? "manual" : "auto" }
func flagStateFragment() -> String { "\\"battlePhase\\": \\"\\(flagPhase())\\", \\"flagMode\\": \\"\\(flagModeName())\\"" }

// 制御ファイルの要求を取り込む。判断部分は applyFlagControl に分けて
// ある (ハーネスで検証できるように)。起動後の最初の取り込みでは、
// 連番を「取り込み済み」として採用するだけで要求は実行しない
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
        }
    }
    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
        }
    }
}

func pollFlagControl() {
    let url = scriptDir.appendingPathComponent("flag_control.json")
    let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
    let mtime = attrs?[.modificationDate] as? Date
    let exists = attrs != nil
    if flagControlAdopted && exists == flagControlExists && mtime == flagControlMtime { return }
    flagControlExists = exists
    flagControlMtime = mtime
    var mode = "manual"
    var startSeq = 0
    var endSeq = 0
    if exists, let data = try? Data(contentsOf: url),
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
        if let m = obj["mode"] as? String { mode = m }
        startSeq = (obj["startSeq"] as? NSNumber)?.intValue ?? 0
        endSeq = (obj["endSeq"] as? NSNumber)?.intValue ?? 0
    }
    applyFlagControl(mode: mode, startSeq: startSeq, endSeq: endSeq)
}''',
    "R2 flag machinery")

# R3: poll from the recognition loop
rep('''        paddlePollResults()
        paddleSupervise()''',
    '''        paddlePollResults()
        paddleSupervise()
        pollFlagControl()''',
    "R3 loop hook")

# R4: emitLog next-battle start guard
rep('''    if winLogged { startBattleLog() }''',
    '''    if winLogged && !flagManualMode { startBattleLog() }''',
    "R4 emitLog guard")

# R5: processPlates start block
rep('''    if !logStarted || (winLogged && hits.contains { (name, s) in lastSlots[name]?.speciesEn != s.speciesEn }) {''',
    '''    if !flagManualMode && (!logStarted || (winLogged && hits.contains { (name, s) in lastSlots[name]?.speciesEn != s.speciesEn })) {''',
    "R5 processPlates start")

# R6: log screen start
rep('''    if !logStarted || winLogged { startBattleLog() }
    scanFieldHeader(boxes)''',
    '''    if !flagManualMode && (!logStarted || winLogged) { startBattleLog() }
    scanFieldHeader(boxes)''',
    "R6 log screen start")

# R7: send-out texts (2 sites) + preview-confirmed start (1 site whose
# line contains the same text as a substring at a deeper indent)
rep('''        if !logStarted || winLogged { startBattleLog() }''',
    '''        if !flagManualMode && (!logStarted || winLogged) { startBattleLog() }''',
    "R7 text/preview starts", count=3)

# R9: inBattle on via log screen
rep('''    if parseLogScreen(image: image) {
        inBattle = true''',
    '''    if parseLogScreen(image: image) {
        if !flagManualMode { inBattle = true }''',
    "R9 inBattle log screen")

# R10: inBattle on via plates
rep('''    emptyBattleFrames = 0
    inBattle = true
    lastFramePlatesMissing = false''',
    '''    emptyBattleFrames = 0
    if !flagManualMode { inBattle = true }
    lastFramePlatesMissing = false''',
    "R10 inBattle plates")

# R11: win branch — defer flag + archive in manual mode (line itself stays)
rep('''        if !oppName.isEmpty { trainerOpp = oppName }
        winLogged = true
        archiveCurrentBattle(final: true)''',
    '''        if !oppName.isEmpty { trainerOpp = oppName }
        // 手動モードでは勝敗行だけを記録し、フラグと確定保存は
        // 終了ボタンの押下まで遅らせる
        if !flagManualMode {
            winLogged = true
            archiveCurrentBattle(final: true)
        }''',
    "R11 win branch")

# R12: forfeit branch
rep('''        emitLog("|win|\\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        winLogged = true
        archiveCurrentBattle(final: true)''',
    '''        emitLog("|win|\\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        if !flagManualMode {
            winLogged = true
            archiveCurrentBattle(final: true)
        }''',
    "R12 forfeit branch")

# R13: idle-end branch
rep('''            emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)")
            winLogged = true''',
    '''            emitLog("|win|\\(trainerMine.isEmpty ? "p1" : trainerMine)")
            if !flagManualMode { winLogged = true }''',
    "R13a idle opp")
rep('''            emitLog("|win|\\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            winLogged = true''',
    '''            emitLog("|win|\\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            if !flagManualMode { winLogged = true }''',
    "R13b idle mine")
rep('''        archiveCurrentBattle(final: true)
        return true
    }
    // 急所: 「(相手の) Xの 急所に 当たった！」''',
    '''        if !flagManualMode { archiveCurrentBattle(final: true) }
        return true
    }
    // 急所: 「(相手の) Xの 急所に 当たった！」''',
    "R13c idle archive")

# R14: writeState carries the flag state
rep('''    let eventsJson = ", \\"events\\": [\\(battleEvents.joined(separator: ", \"))]"''',
    '''    let eventsJson = ", \\"events\\": [\\(battleEvents.joined(separator: ", \"))]"
    let flagJson = ", \\(flagStateFragment())"''',
    "R14a flagJson")
rep('''\\(battleJson)\\(eventsJson), \\"field\\": \\(field)\\(scJson)\\(hzJson)}"''',
    '''\\(battleJson)\\(eventsJson), \\"field\\": \\(field)\\(scJson)\\(hzJson)\\(flagJson)}"''',
    "R14b writeState json")

# R15: preview write carries the flag state
rep('''                obj["oppPreview"] = true''',
    '''                obj["oppPreview"] = true
                obj["battlePhase"] = flagPhase()
                obj["flagMode"] = flagModeName()''',
    "R15 preview write")

# R16: reset write carries the flag state (string + dict forms)
rep('''                        var json = "{\\"mine\\": [], \\"opps\\": [], \\"oppTeam\\": [], \\"oppReset\\": true, \\"field\\": {}}"''',
    '''                        var json = "{\\"mine\\": [], \\"opps\\": [], \\"oppTeam\\": [], \\"oppReset\\": true, \\"field\\": {}, \\"battlePhase\\": \\"\\(flagPhase())\\", \\"flagMode\\": \\"\\(flagModeName())\\"}"''',
    "R16a reset string")
rep('''                            let obj: [String: Any] = ["mine": [Any](), "opps": [Any](), "oppTeam": [Any](), "oppReset": true, "field": [String: Any](), "battle": battleArchiveId, "events": battleEventsObjects()]''',
    '''                            let obj: [String: Any] = ["mine": [Any](), "opps": [Any](), "oppTeam": [Any](), "oppReset": true, "field": [String: Any](), "battle": battleArchiveId, "events": battleEventsObjects(), "battlePhase": flagPhase(), "flagMode": flagModeName()]''',
    "R16b reset dict")

# R17: build stamp
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK R17 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
