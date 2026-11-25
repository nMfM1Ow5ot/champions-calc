#!/usr/bin/env python3
"""PaddleOCR step 1: reader.swift supply side + supervision + evidence.

Edits:
 1. readerBuild bump -> 20261123_0241
 2. New Paddle section after recordObservation (before // MARK: - OCR)
 3. ocr() exit: paddleOffer for plates
 4. ocrBoxes() exit: paddleOffer for boxes
 5. debugCapture: record the frame a debug record fired on
 6. startBattleLog: paddleStartBattle() after flushPendingSkipObs()
 7. archiveCurrentBattle: paddleEndBattle() after archiving
 8. recognitionMainLoop: paddlePollResults() + paddleSupervise()
 9. main section: paddleComputeEnabled() + paddleAdoptAtStartup()
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

rep('let readerBuild = "20261122_2339"', 'let readerBuild = "20261123_0241"')

PADDLE_SECTION = r'''
// MARK: - PaddleOCR 補助チャンネル (証拠記録のみ。状態の決定には一切使わない)
// Mac ローカルの Python サイドカー (paddle_sidecar.py) に、obs に記録が
// 出たフレームの切り出しだけを渡し、生の読みを battle_<試合>_paddle.jsonl
// へ併記する。設計と固定事項は PADDLE_DESIGN.md。サイドカーとの受け渡しは
// ~/champions_paddle/spool/ のファイル経由で、reader はサイドカーを
// 一切待たない (切り出しと結果の取り込みは専用の直列キューで行う)。
let paddleHomeURL = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("champions_paddle")
let paddleSpoolURL = paddleHomeURL.appendingPathComponent("spool")
let paddleQueue = DispatchQueue(label: "champions.paddle")
var paddleEnabled = false            // 起動時にスイッチを確認して確定する
var paddleSessionActive = false      // 現在の試合のセッションが生きているか
var paddleBattleKey = ""
var paddleReqSeq = 0
var paddleRequested = 0
var paddleReturned = 0
var paddleDroppedCount = 0
var paddleRequests: [Int: [String: Any]] = [:]   // reqid -> 証拠行の組み立て材料
var paddleResultsOffset = 0
var paddleLastHash: [String: UInt64] = [:]       // pass|領域 -> 前回送った切り出しのハッシュ
var paddleSidecarPid: Int32 = 0
var paddleLastDebugFrame = -1                    // デバッグ記録が発火した直近フレーム
var paddleUnavailable = false
var paddleUnavailableNotified = false
var paddleLastLaunchTry = Date(timeIntervalSince1970: 0)
var paddleLastRelaunch = Date(timeIntervalSince1970: 0)
var paddleLastSupervise = Date(timeIntervalSince1970: 0)
var paddleOfferCounter = 0

func paddleComputeEnabled() {
    if CommandLine.arguments.contains("--no-paddle") { paddleEnabled = false; return }
    if ProcessInfo.processInfo.environment["CHAMPIONS_PADDLE_OFF"] == "1" { paddleEnabled = false; return }
    if FileManager.default.fileExists(atPath: paddleHomeURL.appendingPathComponent("DISABLED").path) {
        paddleEnabled = false; return
    }
    paddleEnabled = true
}

// 心拍が新しく pid が生きていれば、前の reader が残したサイドカーを
// 引き継ぐ (二重起動の防止。実際の立て直しは次の試合開始時に行う)
func paddleAdoptAtStartup() {
    guard paddleEnabled else { return }
    let hbURL = paddleSpoolURL.appendingPathComponent("heartbeat.json")
    guard let data = try? Data(contentsOf: hbURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
          let pid = (obj["pid"] as? NSNumber)?.int32Value,
          let at = (obj["at"] as? NSNumber)?.doubleValue else { return }
    if Date().timeIntervalSince1970 - at < 20, kill(pid, 0) == 0 {
        paddleSidecarPid = pid
    }
}

func paddleTerminateSidecar() {
    if paddleSidecarPid > 0 {
        kill(paddleSidecarPid, SIGTERM)
        paddleSidecarPid = 0
    }
}

// サイドカーの起動 (paddleQueue 上で呼ぶ)。truncate = true は新しい
// 試合の開始時で、スプールの要求・結果を空にしてから起動する。
// 再監督での再起動は truncate = false で、サイドカー側の offset から
// 再開させる (要求の再処理はしない)。
func paddleLaunchSidecar(truncate: Bool) {
    paddleTerminateSidecar()
    paddleLastLaunchTry = Date()
    let fm = FileManager.default
    try? fm.createDirectory(at: paddleSpoolURL.appendingPathComponent("crops"),
                            withIntermediateDirectories: true)
    if truncate {
        for name in ["requests.jsonl", "results.jsonl", "offset.txt"] {
            try? fm.removeItem(at: paddleSpoolURL.appendingPathComponent(name))
        }
        paddleResultsOffset = 0
    }
    let python = paddleHomeURL.appendingPathComponent(".venv/bin/python")
    guard fm.fileExists(atPath: python.path) else {
        paddleMarkUnavailable("venv が見つかりません")
        return
    }
    let proc = Process()
    proc.executableURL = URL(fileURLWithPath: "/usr/bin/nice")
    proc.arguments = ["-n", "10", python.path,
                      scriptDir.appendingPathComponent("paddle_sidecar.py").path,
                      "--spool", paddleSpoolURL.path, "--battle", paddleBattleKey]
    proc.standardOutput = FileHandle.nullDevice
    proc.standardError = FileHandle.nullDevice
    do {
        try proc.run()
        paddleSidecarPid = proc.processIdentifier
        paddleSessionActive = true
    } catch {
        paddleMarkUnavailable("サイドカーを起動できませんでした")
    }
}

func paddleMarkUnavailable(_ why: String) {
    paddleUnavailable = true
    paddleSessionActive = false
    if !paddleUnavailableNotified {
        paddleUnavailableNotified = true
        print("[paddle] 利用できないため証拠記録を無効化します (\(why))")
    }
}

func paddleStartBattle() {
    paddleQueue.async {
        paddleBattleKey = battleArchiveId
        paddleReqSeq = 0
        paddleRequested = 0
        paddleReturned = 0
        paddleDroppedCount = 0
        paddleRequests = [:]
        paddleLastHash = [:]
        paddleSessionActive = false
        guard paddleEnabled, !paddleBattleKey.isEmpty else { return }
        // 利用不可の環境では再試行の間隔を長く空ける
        if paddleUnavailable,
           Date().timeIntervalSince(paddleLastLaunchTry) < 1800 { return }
        paddleUnavailable = false
        paddleLaunchSidecar(truncate: true)
    }
}

// 切り出しの供給。ocr / ocrBoxes の出口 (obs 記録と同じ箇所) から
// 呼ばれる。認識スレッドでは依頼を積むだけで、切り出し・書き出し・
// 重複除去は paddleQueue で行う。
func paddleOffer(image: CGImage, pass: String, region: [Double]) {
    guard paddleEnabled, paddleSessionActive, logStarted, !winLogged,
          !battleArchiveId.isEmpty, region.count == 4 else { return }
    // 全画面は場面を絞る: デバッグ記録が発火したフレームに限る
    let isFull = region[0] <= 0.001 && region[1] <= 0.001 && region[2] >= 0.999 && region[3] >= 0.999
    let priority = (obsFrameSeq == paddleLastDebugFrame)
    if isFull && !priority { return }
    let frame = obsFrameSeq
    let at = sNow()
    let key = battleArchiveId
    paddleQueue.async {
        guard paddleSessionActive, paddleBattleKey == key else { return }
        // 余白 (ステップ0の確定値): プレートは縦 ±0.010 / 横 ±0.006、
        // メッセージ帯は上側だけ開始を 0.65 まで広げる
        var crop = region
        if pass.hasPrefix("plate:") {
            crop = [region[0] - 0.006, region[1] - 0.010, region[2] + 0.006, region[3] + 0.010]
        } else if pass == "boxes", region[1] > 0.6, region[1] < 0.7, region[3] >= 0.999 {
            crop = [region[0], min(region[1], 0.65), region[2], region[3]]
        }
        crop = [max(0, crop[0]), max(0, crop[1]), min(1, crop[2]), min(1, crop[3])]
        let W = image.width, H = image.height
        let px = Int(crop[0] * Double(W)), py = Int(crop[1] * Double(H))
        let pw = max(8, Int((crop[2] - crop[0]) * Double(W)))
        let ph = max(8, Int((crop[3] - crop[1]) * Double(H)))
        guard let cropped = image.cropping(to: CGRect(x: px, y: py, width: pw, height: ph)),
              let data = NSBitmapImageRep(cgImage: cropped)
                .representation(using: .jpeg, properties: [.compressionFactor: 0.85])
        else { return }
        // 重複除去: 同じ pass・領域で前回と同一内容なら送らない
        var hash: UInt64 = 1469598103934665603
        for b in data { hash = (hash ^ UInt64(b)) &* 1099511628211 }
        let dedupeKey = pass + "|" + region.map { String(format: "%.3f", $0) }.joined(separator: ",")
        if paddleLastHash[dedupeKey] == hash { return }
        paddleLastHash[dedupeKey] = hash
        paddleReqSeq += 1
        let reqid = paddleReqSeq
        let fileName = "crop_\(reqid).jpg"
        let cropsURL = paddleSpoolURL.appendingPathComponent("crops")
        do {
            try FileManager.default.createDirectory(at: cropsURL, withIntermediateDirectories: true)
            try data.write(to: cropsURL.appendingPathComponent(fileName))
            let req: [String: Any] = ["reqid": reqid, "file": fileName,
                                      "pass": pass, "priority": priority]
            let line = try JSONSerialization.data(withJSONObject: req, options: [])
            let reqURL = paddleSpoolURL.appendingPathComponent("requests.jsonl")
            if !FileManager.default.fileExists(atPath: reqURL.path) {
                FileManager.default.createFile(atPath: reqURL.path, contents: nil)
            }
            let fh = try FileHandle(forWritingTo: reqURL)
            _ = fh.seekToEndOfFile()
            fh.write(line)
            fh.write("\n".data(using: .utf8)!)
            try fh.close()
        } catch { return }
        let f = ISO8601DateFormatter()
        f.timeZone = TimeZone(identifier: "Asia/Tokyo")
        paddleRequests[reqid] = ["frame": frame, "at": f.string(from: at),
                                 "region": pass, "base": region, "crop": crop]
        paddleRequested += 1
        // 滞留の上限管理: 未処理の切り出しが溜まりすぎたら古い方から
        // ファイルを消す (その要求はサイドカー側で破棄として記録される)
        paddleOfferCounter += 1
        if paddleOfferCounter % 20 == 0 {
            if let files = try? FileManager.default.contentsOfDirectory(atPath: cropsURL.path) {
                let ids = files.compactMap { name -> Int? in
                    guard name.hasPrefix("crop_"), name.hasSuffix(".jpg") else { return nil }
                    return Int(name.dropFirst(5).dropLast(4))
                }.sorted()
                if ids.count > 120 {
                    for id in ids.prefix(ids.count - 120) {
                        try? FileManager.default.removeItem(
                            at: cropsURL.appendingPathComponent("crop_\(id).jpg"))
                    }
                }
            }
        }
    }
}

// 結果の取り込み (認識ループから呼ばれる。実作業は paddleQueue)。
func paddlePollResults() {
    guard paddleEnabled, paddleSessionActive else { return }
    let url = paddleSpoolURL.appendingPathComponent("results.jsonl")
    let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int ?? 0
    if size > paddleResultsOffset {
        paddleQueue.async { paddleConsumeResults() }
    }
}

// paddleQueue 上で呼ぶ。結果を証拠ファイルへ行として追加する。
func paddleConsumeResults() {
    let url = paddleSpoolURL.appendingPathComponent("results.jsonl")
    guard let fh = try? FileHandle(forReadingFrom: url) else { return }
    _ = fh.seekToEndOfFile()
    let fileSize = Int(fh.offsetInFile)
    if fileSize <= paddleResultsOffset { try? fh.close(); return }
    fh.seek(toFileOffset: UInt64(paddleResultsOffset))
    let data = fh.readDataToEndOfFile()
    try? fh.close()
    guard let text = String(data: data, encoding: .utf8) else { return }
    var consumed = paddleResultsOffset
    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
        if line.isEmpty { consumed += 1; continue }
        consumed += line.utf8.count + 1
        guard let ld = String(line).data(using: .utf8),
              let rec = (try? JSONSerialization.jsonObject(with: ld)) as? [String: Any],
              let reqid = (rec["reqid"] as? NSNumber)?.intValue,
              let info = paddleRequests[reqid] else { continue }
        if (rec["status"] as? String) == "done" {
            var ev = info
            ev["model"] = "PP-OCRv6_small"
            ev["paddleocr"] = "3.7.0"
            ev["texts"] = rec["texts"] ?? []
            ev["elapsed_ms"] = rec["elapsed_ms"] ?? 0
            paddleAppendEvidence(ev)
            paddleReturned += 1
        } else {
            paddleDroppedCount += 1
        }
        paddleRequests.removeValue(forKey: reqid)
    }
    paddleResultsOffset = consumed
}

func paddleAppendEvidence(_ rec: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: rec, options: []),
          let lineText = String(data: data, encoding: .utf8) else { return }
    let url = logsDirURL.appendingPathComponent("battle_\(paddleBattleKey)_paddle.jsonl")
    do {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: url)
        _ = fh.seekToEndOfFile()
        if let d = (lineText + "\n").data(using: .utf8) { fh.write(d) }
        try fh.close()
    } catch {
        // 証拠の記録失敗で対戦処理を止めない
    }
}

// 試合終了時の締め (archiveCurrentBattle から呼ばれる)。残りの結果を
// 最大で約10秒だけ吸い上げ、未処理の件数を締め行に記録して
// サイドカーを終了する。実作業は paddleQueue で行い、認識ループは
// ブロックしない。次の試合の開始処理も同じキューに積まれるため、
// 締め→再起動の順序が保たれる。
func paddleEndBattle() {
    paddleQueue.async {
        guard paddleEnabled, paddleSessionActive else { return }
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            paddleConsumeResults()
            if paddleReturned + paddleDroppedCount >= paddleRequested { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        paddleConsumeResults()
        let unprocessed = max(0, paddleRequested - paddleReturned - paddleDroppedCount)
        paddleAppendEvidence(["end": true, "requested": paddleRequested,
                              "returned": paddleReturned, "dropped": paddleDroppedCount,
                              "unprocessed": unprocessed, "model": "PP-OCRv6_small"])
        print("[paddle] 要求 \(paddleRequested) / 返却 \(paddleReturned) / 破棄 \(paddleDroppedCount) / 未処理 \(unprocessed)")
        paddleTerminateSidecar()
        paddleSessionActive = false
    }
}

// 監督 (認識ループから呼ばれる)。心拍が45秒を超えて古ければ、
// 間隔を空けて1回だけ再起動を試みる。
func paddleSupervise() {
    guard paddleEnabled, paddleSessionActive else { return }
    if Date().timeIntervalSince(paddleLastSupervise) < 5 { return }
    paddleLastSupervise = Date()
    let hbURL = paddleSpoolURL.appendingPathComponent("heartbeat.json")
    let mtime = (try? FileManager.default.attributesOfItem(atPath: hbURL.path))?[.modificationDate] as? Date
    let stale = mtime.map { Date().timeIntervalSince($0) > 45 } ?? true
    // 心拍に unavailable が残っていたら、その試合のセッションは閉じる
    if let data = try? Data(contentsOf: hbURL),
       let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
       (obj["status"] as? String) == "unavailable" {
        paddleQueue.async {
            if paddleSessionActive { paddleMarkUnavailable("サイドカーが利用不可を報告しました") }
        }
        return
    }
    if stale, Date().timeIntervalSince(paddleLastRelaunch) > 60 {
        paddleLastRelaunch = Date()
        paddleQueue.async {
            guard paddleSessionActive else { return }
            paddleLaunchSidecar(truncate: false)
        }
    }
}
'''

rep('\n// MARK: - OCR\n', PADDLE_SECTION + '\n// MARK: - OCR\n')

rep('''    recordObservation(pass: "plate:\\(plate.name)", region: [plate.x0, plate.y0, plate.x1, plate.y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found.map { $0.text }''',
    '''    recordObservation(pass: "plate:\\(plate.name)", region: [plate.x0, plate.y0, plate.x1, plate.y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    paddleOffer(image: image, pass: "plate:\\(plate.name)", region: [plate.x0, plate.y0, plate.x1, plate.y1])
    return found.map { $0.text }''')

rep('''    recordObservation(pass: "boxes", region: [x0, y0, x1, y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found''',
    '''    recordObservation(pass: "boxes", region: [x0, y0, x1, y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    paddleOffer(image: image, pass: "boxes", region: [x0, y0, x1, y1])
    return found''')

rep('''    debugSeenEntries.append((key: key, at: Date()))''',
    '''    debugSeenEntries.append((key: key, at: Date()))
    paddleLastDebugFrame = obsFrameSeq''')

rep('''    battleArchiveId = battleStamp()
    flushPendingSkipObs()''',
    '''    battleArchiveId = battleStamp()
    flushPendingSkipObs()
    paddleStartBattle()''')

rep('''    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    battleArchived = true''',
    '''    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    paddleEndBattle()
    battleArchived = true''')

rep('''        serviceCaptureHeartbeat()
        flushSkippedEvidence()''',
    '''        serviceCaptureHeartbeat()
        flushSkippedEvidence()
        paddlePollResults()
        paddleSupervise()''')

rep('''startCaptureServer()
if teamMode {''',
    '''paddleComputeEnabled()
paddleAdoptAtStartup()
startCaptureServer()
if teamMode {''')

open(PATH, "w", encoding="utf-8").write(src)
print("OK")
