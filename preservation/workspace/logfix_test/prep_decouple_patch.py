#!/usr/bin/env python3
# reader.swift: capture/recognition decoupling, steps 1b + 1c + 2.
# - captureScreenToFile (silent capture) + captureQuickTime as the
#   single-shot wrapper
# - FrameHandoff (queue of 10 + heartbeat + latest) and the capture
#   producer (adaptive interval, ring files, never writes logs/)
# - recognition main loop (heartbeat notices, cheap signature skip,
#   capture-time gap handling, battle-boundary drain)
# - 8899 handlers use the queue's latest image
# - frame_skipped evidence (dedicated seq band 31-60, allowance 30,
#   obs line) for overflow / restart discards
# Design: CAPTURE_DECOUPLING_DESIGN.md
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def sub(name, old, new, count=1):
    global src
    if src.count(old) != count:
        print(f"ABORT {name}: count={src.count(old)}")
        sys.exit(1)
    src = src.replace(old, new, count)
    print(f"OK {name}")

# ---- 1. capture refactor -------------------------------------------------
old_capture = '''func captureQuickTime() -> CGImage? {
    // 最小化・サムネイル化した極小ウィンドウは取り込み対象にしない
    guard let win = findQuickTimeWindow(), win.bounds.width >= 200, win.bounds.height >= 200 else {
        noteCaptureFailed("QuickTime Player のウィンドウが見つかりません")
        return nil
    }
    // 取り込み先は呼び出しごとに変える: メインループと撮影ボタン受付
    // (localhost:8899) が同時に取り込むと同じファイルを取り合って
    // 壊れた画像や前回の残り画像を読んでしまう。また起動に失敗した
    // 場合に前回のファイルが「新しいフレーム」として読まれる事故も防ぐ
    let tmp = NSTemporaryDirectory() + "champions_capture_\\(UUID().uuidString).png"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l", "\\(win.id)", "-o", "-x", tmp]
    do { try p.run() } catch {
        noteCaptureFailed("画面の取り込みを開始できませんでした")
        return nil
    }
    // スリープ復帰直後や QuickTime のハングでは screencapture が戻って
    // こないことがある。無期限に待つとリーダー全体が固まってしまう
    // ため、5 秒で打ち切って次の試行に回す
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { p.waitUntilExit(); done.signal() }
    if done.wait(timeout: .now() + 5) == .timedOut {
        p.terminate()
        _ = done.wait(timeout: .now() + 1)
        noteCaptureFailed("画面の取り込みがタイムアウトしました")
        return nil
    }
    guard p.terminationStatus == 0,
          let img = NSImage(contentsOfFile: tmp),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
          cg.width >= 50, cg.height >= 50 else {
        noteCaptureFailed("画面の取り込みに失敗しました")
        return nil
    }
    noteCaptureOK()
    return cg
}'''
new_capture = '''// 撮影だけを行う (通知・表示は一切しない)。成功したら nil、失敗したら
// 理由を返す。スリープ復帰直後や QuickTime のハングでは screencapture
// が戻ってこないことがあるため、5 秒で打ち切る守りはここに置く
// (撮影側の実時間都合)。最小化・サムネイル化した極小ウィンドウは
// 取り込み対象にしない
func captureScreenToFile(_ path: String) -> String? {
    guard let win = findQuickTimeWindow(), win.bounds.width >= 200, win.bounds.height >= 200 else {
        return "QuickTime Player のウィンドウが見つかりません"
    }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l", "\\(win.id)", "-o", "-x", path]
    do { try p.run() } catch {
        return "画面の取り込みを開始できませんでした"
    }
    let done = DispatchSemaphore(value: 0)
    DispatchQueue.global().async { p.waitUntilExit(); done.signal() }
    if done.wait(timeout: .now() + 5) == .timedOut {
        p.terminate()
        _ = done.wait(timeout: .now() + 1)
        return "画面の取り込みがタイムアウトしました"
    }
    guard p.terminationStatus == 0,
          let img = NSImage(contentsOfFile: path),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil),
          cg.width >= 50, cg.height >= 50 else {
        return "画面の取り込みに失敗しました"
    }
    return nil
}

// 単発モード (--debug / --team-screen / --once) 用: 従来どおり撮影して
// 画像を返し、失敗・復帰の通知も出す。取り込み先は呼び出しごとに変える
// (前回の残り画像を新しいフレームと読む事故を防ぐ)。継続モードでは
// 撮影側 (startCaptureProducer) と認識側の心拍サービスが役割を分担
// するため、こちらは使わない
func captureQuickTime() -> CGImage? {
    let tmp = NSTemporaryDirectory() + "champions_capture_\\(UUID().uuidString).png"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    if let reason = captureScreenToFile(tmp) {
        noteCaptureFailed(reason)
        return nil
    }
    noteCaptureOK()
    return loadImage(path: tmp)
}'''
sub("capture refactor", old_capture, new_capture)

# ---- 2. handoff + producer + recognition machinery -----------------------
anchor2 = "func sNow() -> Date { frameAt }"
block2 = anchor2 + '''

// MARK: - 撮影と認識の受け渡し (独立化ステップ1・2)
//
// 撮影側と認識側が共有するのはこのオブジェクトだけ。列の要素は
// (画像ファイル・撮影時刻・連番) の 3 つ。心拍は最終試行・最終成功・
// 最終の失敗 (時刻と理由)。状態更新 (場の状態・デバッグ保持・試合 ID・
// ログ出力) はすべて認識側が行い、撮影側は一時領域へファイルを書いて
// 列へ入れることと心拍の更新だけを行う。設計は
// CAPTURE_DECOUPLING_DESIGN.md
final class FrameHandoff {
    struct Item { let file: URL; let capturedAt: Date; let seq: Int }
    let capacity = 10
    private let lock = NSLock()
    private var items: [Item] = []
    private var droppedItems: [Item] = []
    private var attemptAt: Date? = nil
    private var successAt: Date? = nil
    private var successFile: URL? = nil
    private var failureAt: Date? = nil
    private var failureReason = ""
    func noteAttempt() { lock.lock(); attemptAt = Date(); lock.unlock() }
    func noteSuccess(file: URL) { lock.lock(); successAt = Date(); successFile = file; lock.unlock() }
    func noteFailure(_ reason: String) { lock.lock(); failureAt = Date(); failureReason = reason; lock.unlock() }
    func heartbeat() -> (attempt: Date?, success: Date?, failure: Date?, reason: String) {
        lock.lock(); defer { lock.unlock() }
        return (attemptAt, successAt, failureAt, failureReason)
    }
    func latestFile() -> URL? { lock.lock(); defer { lock.unlock() }; return successFile }
    func enqueue(_ item: Item) {
        lock.lock()
        if items.count >= capacity { droppedItems.append(items.removeFirst()) }
        items.append(item)
        lock.unlock()
    }
    func dequeue() -> Item? {
        lock.lock(); defer { lock.unlock() }
        return items.isEmpty ? nil : items.removeFirst()
    }
    func takeDropped() -> [Item] {
        lock.lock(); defer { lock.unlock() }
        let d = droppedItems; droppedItems = []; return d
    }
    func drainAll() -> [Item] {
        lock.lock(); defer { lock.unlock() }
        let d = items; items = []; return d
    }
    func isReferenced(_ url: URL) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if successFile == url { return true }
        return items.contains { $0.file == url } || droppedItems.contains { $0.file == url }
    }
}
let frameHandoff = FrameHandoff()

// 小さな輝度署名 (58×38)。撮影側の適応間隔と、認識側の安い見分け
// (前回本処理したフレームと実質同じ画面なら本処理しない) で使う
func frameSignature(_ image: CGImage) -> [UInt8] {
    let buf = makePixelBuffer(image)
    if buf.w <= 0 || buf.h <= 0 { return [] }
    let gw = 58, gh = 38
    var sig = [UInt8](repeating: 0, count: gw * gh)
    for gy in 0..<gh {
        for gx in 0..<gw {
            let px = pixelAt(buf, fx: (Double(gx) + 0.5) / Double(gw), fy: (Double(gy) + 0.5) / Double(gh))
            sig[gy * gw + gx] = UInt8((px.r + px.g + px.b) / 3)
        }
    }
    return sig
}

func signatureDiff(_ a: [UInt8], _ b: [UInt8]) -> Double {
    if a.isEmpty || b.isEmpty || a.count != b.count { return 255 }
    var total = 0
    for i in 0..<a.count { total += abs(Int(a[i]) - Int(b[i])) }
    return Double(total) / Double(a.count)
}

// 撮影側: 独立した直列キューで単一実行する。logs へは直接書かない
let captureProducerQueue = DispatchQueue(label: "champions.capture")
let captureRingDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("champions_frames", isDirectory: true)
var captureSeqCounter = 0
var captureRingSlot = 0
var capturePrevSignature: [UInt8]? = nil
var captureStillStreak = 0

func captureRingFile() -> URL {
    try? FileManager.default.createDirectory(at: captureRingDir, withIntermediateDirectories: true)
    for _ in 0..<24 {
        let url = captureRingDir.appendingPathComponent(String(format: "frame_%02d.png", captureRingSlot))
        captureRingSlot = (captureRingSlot + 1) % 24
        if !frameHandoff.isReferenced(url) { return url }
    }
    return captureRingDir.appendingPathComponent(String(format: "frame_%02d.png", captureRingSlot))
}

func startCaptureProducer() {
    captureProducerQueue.async {
        while true {
            frameHandoff.noteAttempt()
            let file = captureRingFile()
            let startedAt = Date()
            var interval = 1.0
            if let reason = captureScreenToFile(file.path) {
                frameHandoff.noteFailure(reason)
                captureStillStreak = 0
            } else {
                frameHandoff.noteSuccess(file: file)
                captureSeqCounter += 1
                frameHandoff.enqueue(FrameHandoff.Item(file: file, capturedAt: startedAt, seq: captureSeqCounter))
                if let img = loadImage(path: file.path) {
                    let sig = frameSignature(img)
                    if let prev = capturePrevSignature {
                        let d = signatureDiff(prev, sig)
                        if d >= 6.0 { interval = 0.5; captureStillStreak = 0 }
                        else if d >= 1.5 { interval = 1.0; captureStillStreak = 0 }
                        else { captureStillStreak += 1; interval = captureStillStreak >= 2 ? 2.0 : 1.0 }
                    }
                    capturePrevSignature = sig
                }
            }
            Thread.sleep(forTimeInterval: interval)
        }
    }
}

// 認識側: 心拍の遷移で撮影失敗・復帰の通知を出す (表示と記録は認識側
// だけが行う)。最終成功から 10 秒を超えたら現行の撮影失敗と同じ扱い
var heartbeatNoticeFailed = false
func serviceCaptureHeartbeat() {
    let hb = frameHandoff.heartbeat()
    let now = Date()
    if heartbeatNoticeFailed, let s = hb.success, hb.failure == nil || s > hb.failure! {
        noteCaptureOK()
        heartbeatNoticeFailed = false
    }
    if !heartbeatNoticeFailed {
        if let f = hb.failure, hb.success == nil || f > hb.success! {
            noteCaptureFailed(hb.reason.isEmpty ? "画面の取り込みに失敗しました" : hb.reason)
            heartbeatNoticeFailed = true
        } else if let s = hb.success, now.timeIntervalSince(s) > 10 {
            noteCaptureFailed("画面の取り込みが10秒以上成功していません")
            heartbeatNoticeFailed = true
        }
    }
}

// スキップ証拠 (ステップ2): あふれた画像と破棄された画像を、既存の
// デバッグ上限 (イベント系 12・全体 19) と重複まとめの対象外として、
// 専用帯の連番 (31〜60) と専用枠 (1 試合 30 件) で保存する
var skippedShotsThisBattle = 0
var pendingSkipObs: [(seq: Int, capturedAt: Date, reason: String)] = []
let skippedShotAllowance = 30

func recordSkipObservation(seq: Int, capturedAt: Date, reason: String) {
    recordObservation(pass: "frame_skipped", region: [0, 0, 0, 0],
                      boxes: [(text: "seq=\\(seq)|at=\\(Int(capturedAt.timeIntervalSince1970 * 1000))|reason=\\(reason)",
                               x0: 0, y0: 0, x1: 0, y1: 0, conf: 1.0)])
}

func saveSkippedFrameEvidence(_ item: FrameHandoff.Item, reason: String) {
    // 対戦中で試合キーが定まっているときだけ画像を保存する。対戦外の
    // 分は件数だけを数え、次の試合の観測アーカイブへ行として残す
    guard logStarted, !battleArchiveId.isEmpty else {
        pendingSkipObs.append((seq: item.seq, capturedAt: item.capturedAt, reason: reason))
        return
    }
    if skippedShotsThisBattle < skippedShotAllowance, let img = loadImage(path: item.file.path) {
        skippedShotsThisBattle += 1
        let seqNo = 30 + skippedShotsThisBattle
        let base = String(format: "battle_%@_debug%02d", battleArchiveId, seqNo)
        try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
        if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? data.write(to: logsDirURL.appendingPathComponent(base + ".jpg"))
            let f = ISO8601DateFormatter()
            f.timeZone = TimeZone(identifier: "Asia/Tokyo")
            f.formatOptions = [.withInternetDateTime]
            let ev: [String: Any] = ["battle": battleArchiveId, "seq": seqNo, "kind": "frame_skipped",
                                     "at": f.string(from: item.capturedAt), "turn": currentTurn, "rawText": "",
                                     "readerBuild": readerBuild, "state": debugStateExcerpt(),
                                     "detail": ["queueSeq": item.seq, "reason": reason]]
            if let d = try? JSONSerialization.data(withJSONObject: ev, options: [.prettyPrinted, .sortedKeys]) {
                try? d.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)
            }
        }
    }
    recordSkipObservation(seq: item.seq, capturedAt: item.capturedAt, reason: reason)
}

func flushSkippedEvidence() {
    for item in frameHandoff.takeDropped() {
        saveSkippedFrameEvidence(item, reason: "queue_overflow")
        try? FileManager.default.removeItem(at: item.file)
    }
}

func flushPendingSkipObs() {
    let pend = pendingSkipObs
    pendingSkipObs = []
    for p in pend { recordSkipObservation(seq: p.seq, capturedAt: p.capturedAt, reason: p.reason) }
}

// 再起動で列が破棄される前に、残っているフレームを証拠化する
func noteQueueDiscardBeforeExit() {
    let rest = frameHandoff.drainAll() + frameHandoff.takeDropped()
    for item in rest {
        saveSkippedFrameEvidence(item, reason: "discarded_on_restart")
        try? FileManager.default.removeItem(at: item.file)
    }
}

// 認識側メインループ: 列から古い順に取り出して処理する。確定保存が
// 起きたら、その時点で列に残っている分を当該試合の残りとして先に
// 処理する (その間に新しく入った分は対象外)
var lastProcessedCapturedAt: Date? = nil
var lastProcessedSignature: [UInt8]? = nil
var lastFramePlatesMissing = false      // 直近に本処理したフレームがプレート不在だったか (runOnce が更新)
var lastFramePreviewUnresolved = false  // 直近に本処理したフレームが見せ合い (未確定) だったか (runOnce が更新)
var battleBoundaryRequested = false
var boundaryDrainItems: [FrameHandoff.Item] = []

func processHandoffItem(_ item: FrameHandoff.Item) {
    defer { try? FileManager.default.removeItem(at: item.file) }
    // 撮影時刻どうしの間隔でスリープ・停止からの復帰を判定する。
    // 復帰直後の 1 フレームは画面遷移の途中かもしれないため読み捨てる
    if let last = lastProcessedCapturedAt, item.capturedAt.timeIntervalSince(last) > 10 {
        print("[再開] スリープ/停止から復帰したようです。前回の処理から \\(Int(item.capturedAt.timeIntervalSince(last))) 秒経過していたため、このフレームは読み捨てます")
        fflush(stdout)
        emptyBattleFrames = 0
        turnRawFrames = 0
        lastProcessedCapturedAt = item.capturedAt
        return
    }
    guard let image = loadImage(path: item.file.path) else {
        lastProcessedCapturedAt = item.capturedAt
        return
    }
    let sig = frameSignature(image)
    // 安い見分け: 前回本処理したフレームと実質同じ画面なら本処理しない。
    // ただし見せ合い未確定の間と、プレート不在の対戦中 (安全網の時間
    // 判定が関わる場面) は毎フレーム処理する
    if let prev = lastProcessedSignature, signatureDiff(prev, sig) < 1.5,
       !lastFramePreviewUnresolved, !(logStarted && lastFramePlatesMissing) {
        lastProcessedCapturedAt = item.capturedAt
        return
    }
    frameAt = item.capturedAt
    if teamMode { runTeamOnce(image: image) } else { runOnce(image: image) }
    lastProcessedSignature = sig
    lastProcessedCapturedAt = item.capturedAt
}

func recognitionMainLoop() -> Never {
    while true {
        serviceCaptureHeartbeat()
        flushSkippedEvidence()
        var item: FrameHandoff.Item? = nil
        if !boundaryDrainItems.isEmpty { item = boundaryDrainItems.removeFirst() }
        else { item = frameHandoff.dequeue() }
        if let item {
            processHandoffItem(item)
        } else {
            Thread.sleep(forTimeInterval: 0.25)
        }
        if battleBoundaryRequested {
            battleBoundaryRequested = false
            boundaryDrainItems = frameHandoff.drainAll()
        }
    }
}'''
sub("handoff block", anchor2, block2)

# ---- 3. runOnce flag updates ---------------------------------------------
sub("preview flag", '''    if detectPreview(image: image) {
        previewFrames += 1''', '''    if detectPreview(image: image) {
        previewFrames += 1
        lastFramePreviewUnresolved = !previewHandled''')
sub("preview flag clear", "    var hits = locatePlates(image: image)",
    "    lastFramePreviewUnresolved = false\n    var hits = locatePlates(image: image)")
sub("plates missing flag", "    if hits.isEmpty {",
    "    if hits.isEmpty {\n        lastFramePlatesMissing = true")
sub("plates found flag", "    processPlates(hits)",
    "    lastFramePlatesMissing = false\n    processPlates(hits)")

# ---- 4. battle boundary + pending flush + counters ------------------------
sub("boundary request", '''    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    battleArchived = true''', '''    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    battleArchived = true
    battleBoundaryRequested = true''')
sub("pending skip flush", '''    resetLogState()
    battleArchiveId = battleStamp()''', '''    resetLogState()
    battleArchiveId = battleStamp()
    flushPendingSkipObs()''')
sub("skip counter reset", "        renderHold = []",
    "        renderHold = []\n        skippedShotsThisBattle = 0")

# ---- 5. exit discard -------------------------------------------------------
sub("exit discard", '''    print("[sync] reader.swift または data ファイルの更新 (\\(disk)) が届いたため再起動します")
    fflush(stdout)
    exit(42)''', '''    print("[sync] reader.swift または data ファイルの更新 (\\(disk)) が届いたため再起動します")
    fflush(stdout)
    noteQueueDiscardBeforeExit()
    exit(42)''')

# ---- 6. 8899 handlers use the latest queued image --------------------------
sub("latest image helper", "func handlePreviewTestRequest() -> String {",
    '''// 撮影ボタン用: 列の最新画像 (最後に成功した撮影) を使う
func latestCapturedImage() -> CGImage? {
    guard let f = frameHandoff.latestFile() else { return nil }
    return loadImage(path: f.path)
}

func handlePreviewTestRequest() -> String {''')
sub("previewtest latest", '''    guard let img = captureQuickTime() else {
        return "{\\"ok\\":false,\\"error\\":\\"QuickTime の画面を取得できませんでした\\"}"
    }''', '''    guard let img = latestCapturedImage() else {
        return "{\\"ok\\":false,\\"error\\":\\"撮影がまだ成功していません（少し待ってからお試しください）\\"}"
    }''')
sub("capture handler latest", "            if let img = captureQuickTime() {",
    "            if let img = latestCapturedImage() {")

# ---- 7. main loop -----------------------------------------------------------
old_main = '''startCaptureServer()
if teamMode {
    print("チーム登録モード開始 (Ctrl+C で終了)。「様子を見る」で1体ずつ選び、能力タブとステータスタブをそれぞれ映してください。")
}
var lastLoopWorkEndAt: Date? = nil
var discardNextFrame = false   // 復帰直後の 1 フレームは遷移中の可能性があるため読み捨てる
while true {
    // 前の周回から大きく時間が空いた = Mac のスリープや長時間の停止
    // から復帰した可能性が高い。その場合はフレーム数ベースの判定
    // (対戦終了カウンタ・ターン進行) をリセットし、復帰直後の
    // 1 フレームは読み捨てて、遷移途中の画面で状態を壊さないようにする
    if let last = lastLoopWorkEndAt, Date().timeIntervalSince(last) > 10 {
        print("[再開] スリープ/停止から復帰したようです。読み取りを再開します")
        fflush(stdout)
        emptyBattleFrames = 0
        turnRawFrames = 0
        discardNextFrame = true
    }
    if let img = captureQuickTime() {
        if discardNextFrame {
            discardNextFrame = false
        } else if teamMode { runTeamOnce(image: img) } else { runOnce(image: img) }
    }
    if once { break }
    lastLoopWorkEndAt = Date()
    Thread.sleep(forTimeInterval: intervalSec)
}'''
new_main = '''startCaptureServer()
if teamMode {
    print("チーム登録モード開始 (Ctrl+C で終了)。「様子を見る」で1体ずつ選び、能力タブとステータスタブをそれぞれ映してください。")
}
if once {
    // --once は従来どおり 1 回だけ直接撮影して処理する
    frameAt = Date()
    if let img = captureQuickTime() {
        if teamMode { runTeamOnce(image: img) } else { runOnce(image: img) }
    }
} else {
    // 継続モード: 撮影側を独立に走らせ、認識側のループで処理する
    startCaptureProducer()
    recognitionMainLoop()
}'''
sub("main loop", old_main, new_main)

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
