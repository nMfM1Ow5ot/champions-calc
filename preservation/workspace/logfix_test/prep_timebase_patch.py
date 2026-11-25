#!/usr/bin/env python3
# reader.swift: introduce the frame capture-time base (frameAt/sNow)
# and migrate the screen-event time families to it, region by region.
# Protected (real-time) islands: the debug capture section, salvage /
# startup, notePreStartEvent, maybeRestartForUpdate's throttle, the
# HTTP handlers, the main loop, capture code. Step 0 design:
# CAPTURE_DECOUPLING_DESIGN.md (image chat consultation 2026-11-22:
# migrate screen-event families wholesale; half-migration is worse).
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
orig = src

def region(a, b, text):
    i = text.find(a)
    if i < 0:
        print(f"ABORT: region start not found: {a[:50]}")
        sys.exit(1)
    j = text.find(b, i)
    if j < 0:
        print(f"ABORT: region end not found: {b[:50]}")
        sys.exit(1)
    return i, j

def migrate(name, a, b, text, protect=None):
    i, j = region(a, b, text)
    seg = text[i:j]
    n0 = seg.count("Date()")
    if protect:
        pi, pj = region(protect[0], protect[1], seg)
        inner = seg[pi:pj]
        seg = seg[:pi] + inner.replace("Date()", "\x00PROTECTED\x00") + seg[pj:]
    seg = seg.replace("Date()", "sNow()")
    seg = seg.replace("\x00PROTECTED\x00", "Date()")
    n1 = n0 - (seg.count("Date()") - (text[i:j].count("Date()") - n0))
    text = text[:i] + seg + text[j:]
    print(f"OK: {name}: migrated region ({n0} Date() occurrences present)")
    return text

# 0. the frameAt / sNow declarations, after the obs declarations
anchor = "let obsMaxBytes = 32 * 1024 * 1024"
if src.count(anchor) != 1:
    print("ABORT: obs anchor")
    sys.exit(1)
src = src.replace(anchor, anchor + """

// 撮影と認識の独立 (ステップ1): 処理中フレームの撮影時刻。画面に
// ついての判定 (静定・失効・静穏・分類窓など画面イベントどうしの
// 時間関係) はこの時刻を基準にする。処理の滞留で画面上の時間関係
// が歪まないようにするためで、系統ごとに一括で移行する (半分だけ
// 移すと異なる時計の差分に遅延が混入する)。処理都合の時刻 (再起
// 動スロットル、デバッグ発火抑制、ファイルの時刻など) は実時間の
// まま。単発モード (--image 等) では従来どおり処理時刻が入る
var frameAt = Date()
func sNow() -> Date { frameAt }""", 1)
print("OK: declarations")

# R1: recordObservation .. just before the debug caps section
src = migrate("R1", "func recordObservation(", "let debugRoutineMaxPerBattle", src)
# R2: startBattleLog .. notePreStartEvent
src = migrate("R2", "func startBattleLog()", "func notePreStartEvent", src)
# R3: updateMatchingDisplay .. savePNG, protecting maybeRestartForUpdate
src = migrate("R3", "func updateMatchingDisplay(", "func savePNG(", src,
              protect=("func maybeRestartForUpdate()", "func runOnce(image:"))
open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
