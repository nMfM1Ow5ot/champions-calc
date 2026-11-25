#!/usr/bin/env python3
# reader.swift patch: after the manual end is processed, write
# state.json so the file's battlePhase becomes idle. Diagnosis:
# battle_20261123_111415 — the end was processed and archived, but
# no state write followed, so the file kept reporting inBattle.
# Delegated by the comprehensive chat on the user's instruction.
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

rep('let readerBuild = "20261123_1039"', 'let readerBuild = "20261123_1146"', "build")

# the end-state writer, placed right after writeManualStartResetState
rep('''// 手動開始の時点での state.json 初期化書き出し: プレートが見える''',
    '''// 終了確定時の state.json 書き出し: 終了分岐の後に書き出しが
// 無いと、ファイルが inBattle のまま残り続け、UI のボタン表示も
// toggle の判断も古い phase に従ってしまう (実例: 2026-11-23
// battle_20261123_111415)。通常は writeState で盤面ごと現在の
// 内部状態を反映する。場の情報が無い場合 (writeState が書き
// 出さない条件) だけ、リセット形で phase を書き出す
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

// 手動開始の時点での state.json 初期化書き出し: プレートが見える''',
    "writer")

# call it in the end branch, after the archive
rep('''    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
        }
    }''',
    '''    if endSeq > flagEndSeqSeen {
        flagEndSeqSeen = endSeq
        if flagManualMode && logStarted && !winLogged {
            winLogged = true
            archiveCurrentBattle(final: true)
            inBattle = false
            // 終了の確定を state.json に反映する (winLogged が
            // 立った後なので battlePhase は必ず idle になる)
            writeBattleEndState()
        }
    }''',
    "call site")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
