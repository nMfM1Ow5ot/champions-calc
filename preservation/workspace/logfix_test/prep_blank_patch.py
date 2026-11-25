#!/usr/bin/env python3
# reader.swift patch: temporarily suspend the blank-frame standby
# (user instruction via the Q&A chat, 2026-11-23). Switch-based, no
# code deletion. Request-handling uses of isBlankFrame (preview test,
# team-capture endpoint, captureTeamScreen) are NOT touched.
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

# B1: the switch, next to the standby state it controls
rep('''var blankFrameActive = false   // 空フレームが続いているか (遷移通知用)''',
    '''// 黒画面 (空フレーム) 検知による待機は、ユーザーの指示により一時的に
// 無効化している (2026-11-23)。再有効化はこの値を true に戻すだけ。
// 無効化中は、認識経路 (runOnce / runTeamOnce) で黒いフレームも通常の
// 処理に流れ、待機の遷移通知 ([待機] / [再開]、blank_start /
// blank_end) も出ない。リクエスト処理 (プレビューテスト、チーム
// 撮影) での isBlankFrame の利用は待機とは別の用途のため対象外
var blankStandbyEnabled = false
var blankFrameActive = false   // 空フレームが続いているか (遷移通知用)''',
    "B1 switch")

# B2: runOnce standby gate
rep('''    if isBlankFrame(image) { noteBlankFrame(true); return }
    noteBlankFrame(false)
    debugUpdateRing(image)''',
    '''    if blankStandbyEnabled && isBlankFrame(image) { noteBlankFrame(true); return }
    if blankStandbyEnabled { noteBlankFrame(false) }
    debugUpdateRing(image)''',
    "B2 runOnce")

# B3: runTeamOnce standby gate
rep('''func runTeamOnce(image: CGImage) {
    if isBlankFrame(image) { noteBlankFrame(true); return }
    noteBlankFrame(false)''',
    '''func runTeamOnce(image: CGImage) {
    if blankStandbyEnabled && isBlankFrame(image) { noteBlankFrame(true); return }
    if blankStandbyEnabled { noteBlankFrame(false) }''',
    "B3 runTeamOnce")

# B4: startup notice so the suspended state is identifiable
rep('''salvageLeftoverLogs()
cleanupOldDebugShots()''',
    '''salvageLeftoverLogs()
cleanupOldDebugShots()
if !blankStandbyEnabled {
    print("[blank] 黒画面 (空フレーム) 検知による待機は一時的に無効化されています — 黒いフレームも通常の処理に流れます")
    fflush(stdout)
    notePreStartEvent("blank_suspended")
}''',
    "B4 startup notice")

# B5: build stamp
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK B5 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
