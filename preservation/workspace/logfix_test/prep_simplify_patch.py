#!/usr/bin/env python3
# reader.swift patch: (1) suspend the detection-based interrupted
# draft (safety net) via a switch; (2) limit terminal output to the
# human-readable log via a print shadow (switch-based).
# User instruction via the comprehensive chat, 2026-11-23.
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

# T1: terminal output limiter (print shadow) + switch, near the top
rep('''let scriptDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)''',
    '''let scriptDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

// terminal 表示の限定 (2026-11-23、ユーザーの指示で一時的に有効):
// 人間可読ログ以外の terminal 表示を出さない。このファイル内の
// print は下の同名関数に解決され、限定中は握りつぶされる。人間
// 可読ログの表示箇所だけは Swift.print を直接使って限定を素通り
// させる。限定の解除は limitTerminalOutput を false に戻すだけ
// (それ以外の表示経路には手を入れていない)。ファイルへの記録は
// terminal 表示ではないため対象外
var limitTerminalOutput = true

func print(_ items: Any..., separator: String = " ", terminator: String = "\\n") {
    if !limitTerminalOutput {
        Swift.print(items.map { String(describing: $0) }.joined(separator: separator), terminator: terminator)
    }
}''',
    "T1 print shadow")

# T2: the human-readable log bypasses the limiter
rep('''    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
        print(out[0])
    } else {
        for l in out {
            displayLog.append(l)
            print(l)
        }
    }''',
    '''    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
        Swift.print(out[0])
    } else {
        for l in out {
            displayLog.append(l)
            Swift.print(l)
        }
    }''',
    "T2 render bypass")

# T3a: safety-net switch + due predicate, next to its snapshot state
rep('''var lastArchiveSnapshotCount = -1  // 安全網の下書き保存をした時点の battleLog 行数''',
    '''var lastArchiveSnapshotCount = -1  // 安全網の下書き保存をした時点の battleLog 行数

// 安全網 (検出に基づく interrupted の下書き保存) は、ユーザーの
// 指示により一時的に無効化している (2026-11-23)。再有効化は
// この値を true に戻すだけ。検出に基づかない interrupted 保存
// (次の試合の開始時の後始末、起動時の salvage) は対象外で、
// 従来どおり動く
var safetyNetDraftEnabled = false

// 安全網の下書き保存が due か (条件は無効化前と同一)
func safetyNetDraftDue() -> Bool {
    safetyNetDraftEnabled && logStarted && !battleArchived && !battleLog.isEmpty && !winLogged
        && emptyBattleFrames > 30
        && sNow().timeIntervalSince(lastLogEventAt) > 45
        && battleLog.count != lastArchiveSnapshotCount
}''',
    "T3a safety-net switch")

# T3b: the safety-net block uses the predicate
rep('''            if logStarted && !battleArchived && !battleLog.isEmpty && !winLogged
                && emptyBattleFrames > 30
                && sNow().timeIntervalSince(lastLogEventAt) > 45
                && battleLog.count != lastArchiveSnapshotCount {''',
    '''            if safetyNetDraftDue() {''',
    "T3b safety-net block")

# T4: build stamp
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK T4 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
