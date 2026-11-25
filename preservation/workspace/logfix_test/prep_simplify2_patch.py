#!/usr/bin/env python3
# Follow-up to prep_simplify_patch.py: widen the interrupted
# suspension to ALL paths that produce _interrupted files (the user
# said "disable everything"; audit fixed point re-read 2026-11-23).
# One switch: interruptedSaveEnabled. Also renames the safety-net
# switch from the first patch to the shared one.
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

# U1: shared switch declaration + predicate uses it
rep('''// 安全網 (検出に基づく interrupted の下書き保存) は、ユーザーの
// 指示により一時的に無効化している (2026-11-23)。再有効化は
// この値を true に戻すだけ。検出に基づかない interrupted 保存
// (次の試合の開始時の後始末、起動時の salvage) は対象外で、
// 従来どおり動く
var safetyNetDraftEnabled = false

// 安全網の下書き保存が due か (条件は無効化前と同一)
func safetyNetDraftDue() -> Bool {
    safetyNetDraftEnabled && logStarted && !battleArchived && !battleLog.isEmpty && !winLogged''',
    '''// interrupted 保存 (未確定の試合ログの保存) は、ユーザーの指示
// により一時的にすべて無効化している (2026-11-23)。対象は、
// 安全網の検出に基づく下書き保存、次の試合の開始時の後始末と
// しての保存、起動時の salvage の勝敗行なし側の保存のすべて。
// 再有効化はこの値を true に戻すだけ。final の確定保存は対象外
var interruptedSaveEnabled = false

// 安全網の下書き保存が due か (条件は無効化前と同一)
func safetyNetDraftDue() -> Bool {
    interruptedSaveEnabled && logStarted && !battleArchived && !battleLog.isEmpty && !winLogged''',
    "U1 shared switch")

# U2: archiveCurrentBattle writes only final (or interrupted while enabled)
rep('''    guard logStarted, !battleArchived, !battleLog.isEmpty else { return }
    let id = battleArchiveId.isEmpty ? battleStamp() : battleArchiveId
    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)''',
    '''    guard logStarted, !battleArchived, !battleLog.isEmpty else { return }
    let id = battleArchiveId.isEmpty ? battleStamp() : battleArchiveId
    // interrupted 無効化中はファイルだけを出さない (後始末は従来どおり)
    if final || interruptedSaveEnabled {
        archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    }''',
    "U2 archiveCurrentBattle gate")

# U3: salvage writes only when the leftover is a final (or while enabled)
rep('''    archiveBattleLogs(final: lines.contains(where: { $0.hasPrefix("|win|") }),
                      protocolLines: lines, displayLines: dispLines, id: stamp + "_salvage", quiet: true)''',
    '''    if lines.contains(where: { $0.hasPrefix("|win|") }) || interruptedSaveEnabled {
        archiveBattleLogs(final: lines.contains(where: { $0.hasPrefix("|win|") }),
                          protocolLines: lines, displayLines: dispLines, id: stamp + "_salvage", quiet: true)
    }''',
    "U3 salvage gate")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
