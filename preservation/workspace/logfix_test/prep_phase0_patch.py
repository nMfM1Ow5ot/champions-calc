#!/usr/bin/env python3
"""フェーズ0: 生観測のアーカイブ (reader.swift + serve.py)。
reader の OCR 出口で結果 (文字列・位置・確信度) を解釈せずに
試合単位の観測ファイルへ残し、serve.py が試合一式として同梱する。
使い方: python3 prep_phase0_patch.py [apply]"""
import re
import subprocess
import sys

RPATH = "/home/hatch/workspace/champions_calc/reader.swift"
SPATH = "/home/hatch/workspace/champions_calc/serve.py"
rsrc = open(RPATH).read()
ssrc = open(SPATH).read()

R_EDITS = []
S_EDITS = []

# P1: OcrBox に確信度を持たせる
R_EDITS.append((
"""struct OcrBox { let text: String; let cx, cy, x0, y0, x1, y1: Double } // 座標は左上原点の割合""",
"""struct OcrBox { let text: String; let cx, cy, x0, y0, x1, y1: Double; let conf: Double } // 座標は左上原点の割合"""))

# P2: 観測アーカイブの本体 (OCR の直前へ)
R_EDITS.append((
"""// MARK: - OCR

func ocr(_ image: CGImage, plate: Plate) -> [String] {""",
"""// MARK: - 生観測アーカイブ (改善計画フェーズ0: 証拠と解釈の分離)
// reader が処理したフレームの OCR 結果 (文字列・位置・確信度) を、
// 解釈せずに試合単位の観測ファイル (logs/battle_<試合キー>_obs.jsonl)
// へ残す。対象フレームへの参照として、runOnce の通し番号と時刻を
// 記録する。ログ組み立ての挙動には一切影響しない (記録は OCR の
// 出口での副作用のみで、失敗は無視する)。周期は現行の処理周期
// (処理時間 + 0.5 秒待機) のまま
var obsFrameSeq = 0
var obsFileKey = ""
var obsFileBytes = 0
let obsLock = NSLock()
let obsMaxBytes = 32 * 1024 * 1024

func recordObservation(pass: String, region: [Double],
                       boxes: [(text: String, x0: Double, y0: Double, x1: Double, y1: Double, conf: Double)]) {
    guard logStarted, !winLogged, !battleArchiveId.isEmpty, !boxes.isEmpty else { return }
    obsLock.lock()
    defer { obsLock.unlock() }
    if obsFileKey != battleArchiveId { obsFileKey = battleArchiveId; obsFileBytes = 0 }
    if obsFileBytes >= obsMaxBytes { return }
    func r4(_ v: Double) -> Double { (v * 10000).rounded() / 10000 }
    let rec: [String: Any] = [
        "t": Int(Date().timeIntervalSince1970 * 1000),
        "frame": obsFrameSeq,
        "pass": pass,
        "region": region.map(r4),
        "boxes": boxes.map { ["s": $0.text, "x": r4($0.x0), "y": r4($0.y0),
                              "w": r4($0.x1 - $0.x0), "h": r4($0.y1 - $0.y0),
                              "c": ($0.conf * 1000).rounded() / 1000] },
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: rec, options: []),
          let lineText = String(data: data, encoding: .utf8) else { return }
    let line = lineText + "\\n"
    let url = logsDirURL.appendingPathComponent("battle_\\(battleArchiveId)_obs.jsonl")
    do {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let fh = try FileHandle(forWritingTo: url)
        _ = fh.seekToEndOfFile()
        if let d = line.data(using: .utf8) { fh.write(d) }
        try fh.close()
        obsFileBytes += line.utf8.count
    } catch {
        // 観測の記録失敗で対戦処理を止めない
    }
}

// MARK: - OCR

func ocr(_ image: CGImage, plate: Plate) -> [String] {"""))

# P3: プレート OCR の出口で記録する (戻り値は従来どおり文字列だけ)
R_EDITS.append((
"""    try? handler.perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}""",
"""    try? handler.perform([req])
    let found = (req.results ?? []).compactMap { obs -> (text: String, x0: Double, y0: Double, x1: Double, y1: Double, conf: Double)? in
        guard let cand = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return (text: cand.string, x0: Double(b.minX), y0: 1.0 - Double(b.maxY),
                x1: Double(b.maxX), y1: 1.0 - Double(b.minY), conf: Double(cand.confidence))
    }
    recordObservation(pass: "plate:\\(plate.name)", region: [plate.x0, plate.y0, plate.x1, plate.y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found.map { $0.text }
}"""))

# P4: ocrBoxes の出口で記録する (確信度も拾う)
R_EDITS.append((
"""    return (req.results ?? []).compactMap { obs -> OcrBox? in
        guard let t = obs.topCandidates(1).first?.string else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return OcrBox(text: t, cx: Double(b.midX), cy: 1.0 - Double(b.midY),
                      x0: Double(b.minX), y0: 1.0 - Double(b.maxY), x1: Double(b.maxX), y1: 1.0 - Double(b.minY))
    }
}""",
"""    let found = (req.results ?? []).compactMap { obs -> OcrBox? in
        guard let cand = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return OcrBox(text: cand.string, cx: Double(b.midX), cy: 1.0 - Double(b.midY),
                      x0: Double(b.minX), y0: 1.0 - Double(b.maxY), x1: Double(b.maxX), y1: 1.0 - Double(b.minY),
                      conf: Double(cand.confidence))
    }
    recordObservation(pass: "boxes", region: [x0, y0, x1, y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found
}"""))

# P5: フレーム通し番号
R_EDITS.append((
"""func runOnce(image: CGImage) {
    // 空フレーム (暗転・消灯・切断) はどの判定にも流さず待機する。""",
"""func runOnce(image: CGImage) {
    obsFrameSeq += 1   // 生観測アーカイブのフレーム参照 (通し番号)
    // 空フレーム (暗転・消灯・切断) はどの判定にも流さず待機する。"""))

# S1: 送信対象に観測ファイルを加える
S_EDITS.append((
"""    if name.endswith("_states.json"):
        # state.json のスナップショット (reader が形の切り替わり点で
        # 蓄積)。推論過程ログと同じく、その試合のファイル一式の
        # 一部として、備考ゲート付きで試合ログと一緒に送る
        return True""",
"""    if name.endswith("_states.json"):
        # state.json のスナップショット (reader が形の切り替わり点で
        # 蓄積)。推論過程ログと同じく、その試合のファイル一式の
        # 一部として、備考ゲート付きで試合ログと一緒に送る
        return True
    if name.endswith("_obs.jsonl"):
        # 生観測アーカイブ (reader が処理したフレームの OCR 結果を
        # 解釈せずに残したもの。改善計画フェーズ0)。その試合の
        # ファイル一式の一部として、備考ゲート付きで試合ログと
        # 一緒に送る
        return True"""))

# S2: 試合キーへの束ね
S_EDITS.append((
"""    elif rest.endswith("_states.json"):
        rest = rest[: -len("_states.json")]""",
"""    elif rest.endswith("_states.json"):
        rest = rest[: -len("_states.json")]
    elif rest.endswith("_obs.jsonl"):
        rest = rest[: -len("_obs.jsonl")]"""))

apply = len(sys.argv) > 1 and sys.argv[1] == "apply"
bad = 0
for tag, edits, src in (("reader", R_EDITS, rsrc), ("serve", S_EDITS, ssrc)):
    for i, (old, new) in enumerate(edits):
        n = src.count(old)
        print(f"{tag} edit {i + 1}: anchor count = {n}")
        if n != 1:
            bad += 1
if bad:
    print(f"{bad} anchors not unique/found — aborting")
    sys.exit(1)
if apply:
    for old, new in R_EDITS:
        rsrc = rsrc.replace(old, new, 1)
    for old, new in S_EDITS:
        ssrc = ssrc.replace(old, new, 1)
    stamp = subprocess.run(["date", "+%Y%m%d_%H%M"], env={"TZ": "Asia/Tokyo", "PATH": "/usr/bin:/bin"},
                           capture_output=True, text=True).stdout.strip()
    rsrc, n = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', rsrc)
    print(f"build stamp -> {stamp} (replaced {n})")
    open(RPATH, "w").write(rsrc)
    open(SPATH, "w").write(ssrc)
    print("applied all edits")
else:
    print("dry run ok")
