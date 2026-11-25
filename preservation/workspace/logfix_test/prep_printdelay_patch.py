#!/usr/bin/env python3
# reader.swift patch: delayed terminal printing of the readable log
# (plan 2 — print only the confirmed range, battle.log as the source
# of truth). Delegated by the Q&A chat on the user's instruction.
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

rep('let readerBuild = "20261123_0948"', 'let readerBuild = "20261123_1007"', "build")

# print-manager global (next to displayLog)
rep('''var displayLog: [String] = []''',
    '''var displayLog: [String] = []
var displayPrintedCount = 0               // 可読ログのうち terminal へ印刷済みの行数 (遅延印刷の管理)''',
    "global")

# print-manager functions, placed right before emitLog
rep('''func emitLog(_ line: String) { emitLog(line, applyNow: true) }''',
    '''// 可読ログの遅延印刷 (案2): terminal には、もう並べ替え・差し込み・
// 削除が起きない範囲 (確定範囲) だけを displayLog の順序どおりに
// 印刷する。確定範囲は「最後の『Turn 』見出しより前」までとする。
// 根拠: 差し込み (displayInsertAt) の走査は見出しで止まり遡行も
// 最大 60 行、交代の引き戻しの収集・挿入も最後の見出し以降が範囲、
// ターン行ガードが書き換えるのは見出しが載る直前の最後の区間
// だけであり、見出しが載った後の区間へ到達する機構は無い。
// 試合終了時 (final のアーカイブ時) は未印刷分をすべて印刷し、
// terminal 上のログが battle.log と一致した状態で締める
func confirmedDisplayCount(isFinal: Bool) -> Int {
    if isFinal { return displayLog.count }
    return displayLog.lastIndex(where: { $0.hasPrefix("Turn ") }) ?? 0
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

func emitLog(_ line: String) { emitLog(line, applyNow: true) }''',
    "print manager")

# reset in resetLogState
rep('''    displayLog = []; renderSlotSpecies = [:]; renderFainted = []; renderLastPct = [:]''',
    '''    displayLog = []; displayPrintedCount = 0; renderSlotSpecies = [:]; renderFainted = []; renderLastPct = [:]''',
    "reset")

# render tail: replace the immediate prints with the managed flush
rep('''    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
        Swift.print(out[0])
    } else {
        for l in out {
            displayLog.append(l)
            Swift.print(l)
        }
    }
    fflush(stdout)''',
    '''    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
    } else {
        for l in out {
            displayLog.append(l)
        }
    }
    // 可読ログの terminal 印刷は印刷管理に一元化する (確定した
    // 範囲だけを遅れて印刷する。案2)
    flushDisplayPrint()''',
    "render tail")

# final flush at archive time
rep('''    // interrupted 無効化中はファイルだけを出さない (後始末は従来どおり)
    if final || interruptedSaveEnabled {
        archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    }''',
    '''    // interrupted 無効化中はファイルだけを出さない (後始末は従来どおり)
    if final || interruptedSaveEnabled {
        // 試合終了時は未印刷分をすべて印刷し、terminal のログを
        // battle.log と一致させて締める (遅延印刷・案2)
        if final { flushDisplayPrint(isFinal: true) }
        archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    }''',
    "final flush")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
