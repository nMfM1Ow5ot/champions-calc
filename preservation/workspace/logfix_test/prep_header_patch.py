#!/usr/bin/env python3
# reader.swift patch: header printing waits for identification.
# The display header is born provisional when the start flag turns
# on; it is rewritten in completed form (opponent trainer name +
# six identified species) and released to the printer once
# (a) the trainer name is known and (b) six species are identified,
# or, failing that, when identification ends. Delegated by the Q&A
# chat on the user's explicit instruction.
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

rep('let readerBuild = "20261123_1007"', 'let readerBuild = "20261123_1033"', "build")

# header-gate globals
rep('''var displayPrintedCount = 0               // 可読ログのうち terminal へ印刷済みの行数 (遅延印刷の管理)''',
    '''var displayPrintedCount = 0               // 可読ログのうち terminal へ印刷済みの行数 (遅延印刷の管理)
var headerPrintReady = false              // ヘッダーが完成形になり印刷可能になったか (相手同定の完了待ち)
var headerLineCount = 0                   // displayLog 冒頭のヘッダー行数 (0 = ヘッダー未生成)''',
    "globals")

# confirmed range honors the header gate
rep('''func confirmedDisplayCount(isFinal: Bool) -> Int {
    if isFinal { return displayLog.count }
    return displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) ?? 0
}''',
    '''func confirmedDisplayCount(isFinal: Bool) -> Int {
    if isFinal { return displayLog.count }
    let turnBound = displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) ?? 0
    // ヘッダーは相手の同定がそろう (または同定が終了する) まで
    // 印刷を止める。ヘッダーは displayLog の先頭にあるため、
    // 未完成の間は後続の行も含めて何も印刷しない
    if headerPrintReady { return max(turnBound, headerLineCount) }
    return headerLineCount > 0 ? 0 : turnBound
}

// ヘッダーを現在の同定結果で完成形に書き直す (renderLogLine の
// |start| と同じ組み立て。自分のチーム行は生成時のものを保持
// する)。battle.log のヘッダーもこの時点で正しい内容になる
func completeDisplayHeader() {
    guard headerLineCount > 0, displayLog.count >= headerLineCount else { return }
    let mine = trainerMine.isEmpty ? "you" : trainerMine
    let opp = trainerOpp.isEmpty ? "Opponent" : trainerOpp
    let p1Line = headerLineCount > 7 ? displayLog[7] : ""
    var h = ["\\(mine) and \\(opp) joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg \\(regulationDisplay())", "Rated battle",
             "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
             trainerMine.isEmpty ? "Your team:" : "\\(trainerMine)'s team:", p1Line,
             "\\(opp)'s team:", oppTeamSeen.joined(separator: " / "), "",
             "Battle started between \\(mine) and \\(opp)!"]
    if !oppRank.isEmpty { h.append("\\(opp)'s rank: \\(oppRank)") }
    if !oppRating.isEmpty { h.append("\\(opp)'s rating: \\(oppRating)") }
    h.append("")
    displayLog.replaceSubrange(0..<headerLineCount, with: h)
    headerLineCount = h.count
    try? (displayLog.joined(separator: "\\n") + "\\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
}

// ヘッダーの完成判定: (a) 選出画面で相手トレーナー名が判明し、
// (b) 相手チーム 6 体がそろった時点で完成形に書き直して印刷
// 可能にする。同定が終了してもそろわない場合は、その時点で
// そろっている分で完成させる (ユーザーの決定)。試合終了時の
// 最終確認では同定終了とみなす (forceEnd)
func refreshHeaderState(forceEnd: Bool = false) {
    guard headerLineCount > 0, !headerPrintReady else { return }
    let complete = !trainerOpp.isEmpty && oppTeamSeen.count >= 6
    if complete || previewHandled || forceEnd {
        completeDisplayHeader()
        headerPrintReady = true
        flushDisplayPrint()
    }
}''',
    "print manager extension")

# reset in resetLogState
rep('''    displayLog = []; displayPrintedCount = 0; renderSlotSpecies = [:]; renderFainted = []; renderLastPct = [:]''',
    '''    displayLog = []; displayPrintedCount = 0; headerPrintReady = false; headerLineCount = 0; renderSlotSpecies = [:]; renderFainted = []; renderLastPct = [:]''',
    "reset")

# birth evaluation in startBattleLog
rep('''    emitLog("|start")
    logStarted = true
}''',
    '''    emitLog("|start")
    // ヘッダーの印刷可否の初期判定: この時点で displayLog の冒頭が
    // ヘッダー。同定が済んでいれば完成形で生まれ、未了なら判明
    // した時点で refreshHeaderState が書き直す
    headerLineCount = displayLog.count
    refreshHeaderState()
    logStarted = true
}''',
    "birth")

# identification-update hook (end of the preview identification block)
rep('''                }
            }
        }
        inBattle = false
        return
    }''',
    '''                }
            }
        }
        // 同定の更新のたびにヘッダーの完成判定を行う (開始ボタンが
        // 同定完了より先に押された場合の書き直し)
        refreshHeaderState()
        inBattle = false
        return
    }''',
    "preview hook")

# archive-time completion before the final flush
rep('''        // 試合終了時は未印刷分をすべて印刷し、terminal のログを
        // battle.log と一致させて締める (遅延印刷・案2)
        if final { flushDisplayPrint(isFinal: true) }''',
    '''        // 試合終了時は未印刷分をすべて印刷し、terminal のログを
        // battle.log と一致させて締める (遅延印刷・案2)。ヘッダーが
        // 未完成なら、そろっている分で完成させてから出す
        if final { refreshHeaderState(forceEnd: true); flushDisplayPrint(isFinal: true) }''',
    "archive completion")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
