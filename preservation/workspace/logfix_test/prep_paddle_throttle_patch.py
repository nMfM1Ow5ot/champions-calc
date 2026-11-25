#!/usr/bin/env python3
"""PaddleOCR step 2 fix: supply-side offer throttle + build bump.

Step-2 measurement showed the supply (every obs-bearing frame, ~6+/s)
far outrunning the sidecar, so most requests ended dropped/unprocessed.
Add a per-(pass, region) minimum offer interval on the recognition
thread (plates 3s, boxes 4s; debug-priority offers bypass it). The
fixed matters (input scope, evidence format, supervision, kill
switch) are unchanged.
"""
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(old, new, n=1):
    global src
    c = src.count(old)
    if c != n:
        print(f"ABORT: anchor count {c} != {n}: {old[:70]!r}")
        sys.exit(1)
    src = src.replace(old, new)

rep('let readerBuild = "20261123_0241"', 'let readerBuild = "20261123_0304"')

rep('''var paddleLastHash: [String: UInt64] = [:]       // pass|領域 -> 前回送った切り出しのハッシュ''',
    '''var paddleLastHash: [String: UInt64] = [:]       // pass|領域 -> 前回送った切り出しのハッシュ
var paddleLastOfferAt: [String: Date] = [:]      // pass|領域 -> 前回供給した時刻 (供給量の調整用)''')

rep('''    // 全画面は場面を絞る: デバッグ記録が発火したフレームに限る
    let isFull = region[0] <= 0.001 && region[1] <= 0.001 && region[2] >= 0.999 && region[3] >= 0.999
    let priority = (obsFrameSeq == paddleLastDebugFrame)
    if isFull && !priority { return }''',
    '''    // 全画面は場面を絞る: デバッグ記録が発火したフレームに限る
    let isFull = region[0] <= 0.001 && region[1] <= 0.001 && region[2] >= 0.999 && region[3] >= 0.999
    let priority = (obsFrameSeq == paddleLastDebugFrame)
    if isFull && !priority { return }
    // 供給量の調整 (ステップ2の実測で判明): obs の出たフレームごとに
    // 送ると毎秒6件超になり、サイドカーの処理が追いつかず大半が
    // 破棄・未処理になった。pass・領域ごとに最小間隔を空ける
    // (証拠は全フレームではなく第2の読みの見本で足りる。obs 側には
    // 全フレームが残っている)。デバッグ発火フレームの優先投入は
    // 間隔の対象外とする。
    if !priority {
        let key = pass + "|" + region.map { String(format: "%.3f", $0) }.joined(separator: ",")
        let interval: Double = pass.hasPrefix("plate:") ? 3.0 : 4.0
        if let last = paddleLastOfferAt[key], sNow().timeIntervalSince(last) < interval { return }
        paddleLastOfferAt[key] = sNow()
    }''')

rep('''    battleArchiveId = battleStamp()
    flushPendingSkipObs()
    paddleStartBattle()''',
    '''    battleArchiveId = battleStamp()
    flushPendingSkipObs()
    paddleLastOfferAt = [:]
    paddleStartBattle()''')

open(PATH, "w", encoding="utf-8").write(src)
print("OK")
