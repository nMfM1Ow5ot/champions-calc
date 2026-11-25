#!/usr/bin/env python3
# reader.swift patch: write an initialized state.json at manual
# start (start button), closing the gap where the previous battle's
# state.json stayed on file until the first plates were seen.
# Delegated by the Q&A chat on the user's explicit instruction.
import sys

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

rep('let readerBuild = "20261123_1033"', 'let readerBuild = "20261123_1039"', "build")

# the write function, placed right after applyFlagControl
rep('''    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
        }
    }
}''',
    '''    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
        }
    }
}

// 手動開始の時点での state.json 初期化書き出し: プレートが見える
// まで前試合の内容がファイルに残り続ける空白を埋める。形は同定
// 全滅時のリセット書き出しに揃え (oppReset 付きで場・イベント・
// 判明情報を消す)、新しい試合の見せ合い同定が既に書き出されて
// いれば、その結果 (oppTeam と mineTeam) は保持する。同定前に
// 押された場合は、後の同定の書き出しで従来どおり入ってくる
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
}''',
    "write function")

# call it in the manual start branch
rep('''    if startSeq > flagStartSeqSeen {
        flagStartSeqSeen = startSeq
        if flagManualMode && (!logStarted || winLogged) {
            startBattleLog()
            inBattle = true
        }
    }''',
    '''    if startSeq > flagStartSeqSeen {
        flagStartSeqSeen = startSeq
        if flagManualMode && (!logStarted || winLogged) {
            startBattleLog()
            inBattle = true
            // state.json を初期化した形で書き出し、前試合の内容が
            // プレート確認まで残る空白を埋める (手動開始のみ)
            writeManualStartResetState()
        }
    }''',
    "call site")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
