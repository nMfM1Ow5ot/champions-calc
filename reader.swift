// Champions 対戦画面リーダー (macOS)
// QuickTime Player に映った iPad の対戦画面を取り込み、名前とHPを読み取って state.json を書く。
// 使い方:
//   swift reader.swift                 : 2秒ごとに読み取り続ける
//   swift reader.swift --once          : 1回だけ読む
//   swift reader.swift --image a.png   : 保存済みスクショで試す (QuickTime不要)
//   swift reader.swift --interval 3    : 間隔を変更
//   swift reader.swift --team          : チーム登録モード (様子を見るの能力/ステータスタブを映して my_team.json を作る)
//   swift reader.swift --team-screen ability --image a.png : チーム確認画面 (6体一覧) の取り込みを画像で試す
//   起動中は UI の撮影ボタン用に localhost:8899 で撮影リクエストを受け付ける
import Foundation
import Vision
import CoreGraphics
import AppKit
import Network

// MARK: - 設定

let scriptDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outURL = scriptDir.appendingPathComponent("state.json")
let indexURL = scriptDir.appendingPathComponent("data/names_index.json")

// プレート領域 (画面に対する割合, 左上原点で定義)。実スクショ (2266x1488) で調整済み。
struct Plate { let name: String; let x0, y0, x1, y1: Double; let isMine: Bool }
let plates: [Plate] = [
    Plate(name: "oppA",  x0: 0.560, y0: 0.025, x1: 0.780, y1: 0.135, isMine: false),
    Plate(name: "oppB",  x0: 0.762, y0: 0.025, x1: 0.988, y1: 0.135, isMine: false),
    Plate(name: "mineA", x0: 0.012, y0: 0.855, x1: 0.238, y1: 0.972, isMine: true),
    Plate(name: "mineB", x0: 0.218, y0: 0.850, x1: 0.442, y1: 0.972, isMine: true),
]

// MARK: - 名前辞書

struct SpeciesEntry { let ja: String; let en: String; let id: String; let norm: String }
var speciesDict: [SpeciesEntry] = []

func normalize(_ s: String) -> String {
    // ひらがな→カタカナ, 全角英数字→半角, 空白・中点・記号を除去
    // (OCR は「１０まんボルト」「ＤＤラリアット」のように全角で返すことがある)
    var out = ""
    for ch in s {
        if ch == " " || ch == "　" || ch == "・" { continue }
        if let v = ch.unicodeScalars.first,
           (0xFF10...0xFF19).contains(v.value) || (0xFF21...0xFF3A).contains(v.value) || (0xFF41...0xFF5A).contains(v.value),
           let half = UnicodeScalar(v.value - 0xFEE0) {
            out.append(Character(half))
        } else if let v = ch.unicodeScalars.first, (0x3041...0x3096).contains(v.value),
           let kata = UnicodeScalar(v.value + 0x60) {
            out.append(Character(kata))
        } else if ch.isLetter || ch.isNumber {
            out.append(ch)
        }
    }
    return out
}

// OCR の揺れを吸収する比較用正規化: normalize に加え、濁点・半濁点を落とし、小書き仮名を大文字に揃える
// (実機 OCR では「ぼうぎょ」が「ほうきよ」等、濁点落ち+小書き→大文字で返ることが多いため)
func looseText(_ s: String) -> String {
    let small: [Character: Character] = ["ャ": "ヤ", "ュ": "ユ", "ョ": "ヨ", "ッ": "ツ",
                                          "ァ": "ア", "ィ": "イ", "ゥ": "ウ", "ェ": "エ", "ォ": "オ",
                                          "ヮ": "ワ", "ヵ": "カ", "ヶ": "ケ"]
    let nfd = normalize(s).decomposedStringWithCanonicalMapping
    var stripped = ""
    for sc in nfd.unicodeScalars {
        if sc.value == 0x3099 || sc.value == 0x309A { continue }
        stripped.append(Character(sc))
    }
    let recomposed = stripped.precomposedStringWithCanonicalMapping
    return String(recomposed.map { small[$0] ?? $0 })
}

// 濁点・半濁点を落とした形 (OCR の濁点ゆれ対策: スバヤサ→スパヤサ、
// トクコウ→トグゴウ のような崩れを、能力名の照合だけ両辺を畳んで吸収する)
func foldDakuten(_ s: String) -> String {
    let map: [Character: Character] = ["ガ": "カ", "ギ": "キ", "グ": "ク", "ゲ": "ケ", "ゴ": "コ",
        "ザ": "サ", "ジ": "シ", "ズ": "ス", "ゼ": "セ", "ゾ": "ソ",
        "ダ": "タ", "ヂ": "チ", "ヅ": "ツ", "デ": "テ", "ド": "ト",
        "バ": "ハ", "ビ": "ヒ", "ブ": "フ", "ベ": "ヘ", "ボ": "ホ",
        "パ": "ハ", "ピ": "ヒ", "プ": "フ", "ペ": "ヘ", "ポ": "ホ",
        "が": "か", "ぎ": "き", "ぐ": "く", "げ": "け", "ご": "こ",
        "ざ": "さ", "じ": "し", "ず": "す", "ぜ": "せ", "ぞ": "そ",
        "だ": "た", "ぢ": "ち", "づ": "つ", "で": "て", "ど": "と",
        "ば": "は", "び": "ひ", "ぶ": "ふ", "べ": "へ", "ぼ": "ほ",
        "ぱ": "は", "ぴ": "ひ", "ぷ": "ふ", "ぺ": "へ", "ぽ": "ほ"]
    return String(s.map { map[$0] ?? $0 })
}

func loadDict() {
    guard let data = try? Data(contentsOf: indexURL),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let arr = obj["species"] as? [[String: String]] else {
        fputs("names_index.json が読めません: \(indexURL.path)\n", stderr)
        exit(1)
    }
    speciesDict = arr.map { SpeciesEntry(ja: $0["ja"] ?? "", en: $0["en"] ?? "", id: $0["id"] ?? "", norm: normalize($0["ja"] ?? "")) }
}

// OCR文字列群から最も合う種族を探す (最長一致を優先し、次に編集距離の近さ)
func levenshtein(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = Array(0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

func matchSpecies(texts: [String]) -> SpeciesEntry? {
    let joined = normalize(texts.joined(separator: ""))
    if joined.isEmpty { return nil }
    // 含まれる名前の中で最長のものを優先 (例: メガガブリアスZ を ガブリアス より優先)
    var best: SpeciesEntry? = nil
    for e in speciesDict where !e.norm.isEmpty && joined.contains(e.norm) {
        if best == nil || e.norm.count > best!.norm.count { best = e }
    }
    if let b = best { return b }
    // 部分一致がなければ編集距離で近いものを探す (OCRの1〜2文字ミス対策)
    var bestScore = 0.0
    for e in speciesDict {
        let n = Array(e.norm)
        if n.count < 3 { continue }
        for t in texts {
            let tn = Array(normalize(t))
            if tn.count < 3 || abs(tn.count - n.count) > 2 { continue }
            let d = levenshtein(tn, n)
            let score = 1.0 - Double(d) / Double(max(tn.count, n.count))
            if score > bestScore { bestScore = score; best = e }
        }
    }
    return bestScore >= 0.6 ? best : nil
}

// MARK: - 画面取得

func findQuickTimeWindow() -> (id: CGWindowID, bounds: CGRect)? {
    guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
    var best: (CGWindowID, CGRect)? = nil
    var bestArea = 0.0
    for w in list {
        guard let owner = w[kCGWindowOwnerName as String] as? String, owner == "QuickTime Player",
              let num = w[kCGWindowNumber as String] as? Int,
              let b = w[kCGWindowBounds as String] as? [String: Any],
              let x = b["X"] as? Double, let y = b["Y"] as? Double,
              let width = b["Width"] as? Double, let height = b["Height"] as? Double else { continue }
        let area = width * height
        if area > bestArea { bestArea = area; best = (CGWindowID(num), CGRect(x: x, y: y, width: width, height: height)) }
    }
    return best
}

var lastCaptureOK = true
var debugMode = false    // --debug のときだけ診断メッセージを出す (通常時はターミナルにバトルログのみ表示)
var teamDiag = false     // チーム画面取り込みの診断表示 (--team-screen 単発実行時のみ)
func diagPrint(_ s: String) { if teamDiag { print(s); fflush(stdout) } }

// 取得失敗・復帰の通知は通常時も遷移時に 1 回だけ出す。暗転・スリープ・
// QuickTime 終了・iPad 切断のいずれでも、リーダーは終了せず待機して
// 取得できるようになったら自動で再開するのが前提なので、「止まって
// いる」のか「待っている」のかをターミナルで区別できるようにする
func noteCaptureFailed(_ reason: String) {
    if lastCaptureOK { print("[待機] \(reason) — 復帰を待っています"); fflush(stdout); notePreStartEvent("capture_failed") }
    lastCaptureOK = false
}

func noteCaptureOK() {
    if !lastCaptureOK { print("[再開] 画面の取得を再開しました"); fflush(stdout); notePreStartEvent("capture_ok") }
    lastCaptureOK = true
}

func captureQuickTime() -> CGImage? {
    // 最小化・サムネイル化した極小ウィンドウは取り込み対象にしない
    guard let win = findQuickTimeWindow(), win.bounds.width >= 200, win.bounds.height >= 200 else {
        noteCaptureFailed("QuickTime Player のウィンドウが見つかりません")
        return nil
    }
    // 取り込み先は呼び出しごとに変える: メインループと撮影ボタン受付
    // (localhost:8899) が同時に取り込むと同じファイルを取り合って
    // 壊れた画像や前回の残り画像を読んでしまう。また起動に失敗した
    // 場合に前回のファイルが「新しいフレーム」として読まれる事故も防ぐ
    let tmp = NSTemporaryDirectory() + "champions_capture_\(UUID().uuidString).png"
    defer { try? FileManager.default.removeItem(atPath: tmp) }
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l", "\(win.id)", "-o", "-x", tmp]
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
}

func loadImage(path: String) -> CGImage? {
    guard let img = NSImage(contentsOfFile: path) else { return nil }
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// MARK: - 空フレーム (暗転・真っ黒・単色) の判定

var blankFrameActive = false   // 空フレームが続いているか (遷移通知用)

// フレームの平均輝度とばらつきを小さなバッファで測り、「絵が無い」
// フレームかどうかを返す。暗転フェード・iPad の画面消灯・スリープ
// 復帰直後の真っ黒な画面・QuickTime の切断画面などが該当する。
// 空フレームは OCR や各種判定に流さず、その間は待機するだけにする
// (真っ黒な時間が続いただけで対戦終了と誤判定したり、暗い画面の
// ノイズをメッセージと誤読したりしないため)
func isBlankFrame(_ image: CGImage) -> Bool {
    if image.width < 50 || image.height < 50 { return true }
    let buf = makePixelBuffer(image)
    if buf.w <= 0 || buf.h <= 0 || buf.data.count < buf.w * buf.h * 4 { return true }
    var sum = 0.0, sumSq = 0.0, n = 0.0
    var i = 0
    while i + 2 < buf.data.count {
        let lum = (Double(buf.data[i]) + Double(buf.data[i + 1]) + Double(buf.data[i + 2])) / 3.0
        sum += lum; sumSq += lum * lum; n += 1
        i += 16   // 4 ピクセルに 1 個のサンプリング (小バッファなので十分)
    }
    if n == 0 { return true }
    let mean = sum / n
    let sd = sqrt(max(0, sumSq / n - mean * mean))
    return mean < 12 || sd < 2.0
}

func noteBlankFrame(_ blank: Bool) {
    if blank && !blankFrameActive { print("[待機] 画面が暗い/真っ黒なため待機します"); fflush(stdout); notePreStartEvent("blank_start") }
    if !blank && blankFrameActive { print("[再開] 画面が戻りました"); fflush(stdout); notePreStartEvent("blank_end") }
    blankFrameActive = blank
}

// MARK: - 生観測アーカイブ (改善計画フェーズ0: 証拠と解釈の分離)
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
    let line = lineText + "\n"
    let url = logsDirURL.appendingPathComponent("battle_\(battleArchiveId)_obs.jsonl")
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

func ocr(_ image: CGImage, plate: Plate) -> [String] {
    if image.width < 50 || image.height < 50 { return [] } // 検出器の内部クラッシュ回避 (ocrBoxes 参照)
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ja-JP", "en-US"]
    req.usesLanguageCorrection = false
    // Vision の regionOfInterest は左下原点・正規化座標
    req.regionOfInterest = CGRect(x: plate.x0, y: 1.0 - plate.y1, width: plate.x1 - plate.x0, height: plate.y1 - plate.y0)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([req])
    let found = (req.results ?? []).compactMap { obs -> (text: String, x0: Double, y0: Double, x1: Double, y1: Double, conf: Double)? in
        guard let cand = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return (text: cand.string, x0: Double(b.minX), y0: 1.0 - Double(b.maxY),
                x1: Double(b.maxX), y1: 1.0 - Double(b.minY), conf: Double(cand.confidence))
    }
    recordObservation(pass: "plate:\(plate.name)", region: [plate.x0, plate.y0, plate.x1, plate.y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found.map { $0.text }
}

// MARK: - パース

struct SlotState { var speciesEn: String; var hpPercent: Int; var hpCur: Int? = nil; var hpMax: Int? = nil; var hpBarPct: Int? = nil }
var lastSlots: [String: SlotState] = [:]
var firstSlotConfirmedAt: Date? = nil   // この試合で最初にプレート枠が確定した時刻 (未確定枠の検出用)
var lastWritten = ""
// 相手の6体コレクション: 対戦中にプレートで読み取れた相手種族を登場順に蓄積する (見せ合い画面には名前テキストが無いため)
var oppTeamSeen: [String] = []
var headerOppTeam: [String] = []          // ログ開始時にヘッダーへ書いた相手6体 (開始時点の控え)
var headerMismatchFired: Set<String> = []  // header_mismatch を記録済みの種族
// 選出同定で入ったが、対戦中にまだ実物が観測されていない種族。
// 選出の推定 (仮置きはもちろん、タイプで「確定」した枠もアイコン誤読なら
// ありうる) はプレートの名前テキストより弱い証拠なので、未確認の間は
// 実物が観測された種族で差し替え可能にしておく。観測された種族は
// ここから外れ、以後差し替えられない。
var oppUnconfirmed: Set<String> = []

func updateOppTeam() {
    let cur = [lastSlots["oppA"]?.speciesEn, lastSlots["oppB"]?.speciesEn].compactMap { $0 }
    for sp in cur { oppUnconfirmed.remove(sp) }  // 場に出た種族は確認済み
    if cur.count == 2 && oppTeamSeen.count >= 4 && oppUnconfirmed.isEmpty
        && cur.allSatisfy({ !oppTeamSeen.contains($0) }) {
        oppTeamSeen = []  // 両方とも未見の種族なら新しい対戦とみなしてリセット
    }
    for sp in cur where !oppTeamSeen.contains(sp) {
        if oppTeamSeen.count < 6 {
            oppTeamSeen.append(sp)
        } else if let idx = oppTeamSeen.lastIndex(where: { oppUnconfirmed.contains($0) }) {
            // 6枠が選出推定で埋まっていると実物が入る余地がなく、仮置きが
            // 対戦終了まで残り続けていた。未確認の推定枠 (末尾側から) を
            // 実物で差し替える。確認済みの枠は絶対に差し替えないので、
            // 実際に登場した種族が順に確定していく
            oppUnconfirmed.remove(oppTeamSeen[idx])
            oppTeamSeen[idx] = sp
        }
    }
}

func parsePlate(image: CGImage, plate: Plate) -> SlotState? {
    let texts = ocr(image, plate: plate)
    guard let raw = matchSpecies(texts: texts) else { return nil }
    // 自軍の固定領域読み: 登録チーム (フォルム違い含む) に無い種族は誤読として捨てる
    if plate.isMine && !teamEntries.isEmpty
        && !formeGroup(raw).contains(where: { teamEntries[$0.en] != nil }) { return nil }
    // フォルム表記を登録側に寄せる (名前 OCR は雌雄フォルムを区別できない)
    let sp = anchoredSpecies(raw, mine: plate.isMine)
    var hp: Int? = nil
    var hpCur: Int? = nil
    var hpMax: Int? = nil
    let joined = texts.joined(separator: " ")
    if plate.isMine {
        var knownMax: Int? = nil
        for m in formeGroup(sp) {
            if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { knownMax = h; break }
        }
        if knownMax == nil { knownMax = monStates["p1:\(sp.en)"]?.hpMax }
        for t in texts + [joined] {
            if let r = parseMineHPText(t, knownMax: knownMax) {
                if let km = knownMax, let mx = r.max, mx != km { continue }
                hp = r.pct; hpCur = r.cur; hpMax = r.max
                break
            }
        }
    } else {
        // "100 %" の形
        if let r = joined.range(of: #"(\d{1,3})\s*%"#, options: .regularExpression) {
            hp = Int(joined[r].filter { $0.isNumber })
        }
    }
    guard let h = hp else { return nil }
    return SlotState(speciesEn: sp.en, hpPercent: max(0, min(100, h)), hpCur: hpCur, hpMax: hpMax)
}

func jsonEscape(_ s: String) -> String { s.replacingOccurrences(of: "\"", with: "\\\"") }

// MARK: - state.json スキーマ (正本)
// writeState が出しうるキーは、ここに列挙したものだけとする。キーを
// 追加・変更するときは必ずここを更新すること (ハーネスが、実際に生成
// した state.json のキーと突き合わせて検証する。aurora/veil のような
// キー名の食い違いを機械で検出するため)
let stateTopKeys: Set<String> = ["mine", "opps", "oppTeam", "oppRevealed", "oppTrainer", "events", "field", "sideConditions", "hazards", "oppReset", "oppPreview", "battle"]
let stateMonKeys: Set<String> = ["species", "curHPPercent", "status", "unburden", "itemLost", "mega", "megaSpecies", "boosts", "revealed"]
let stateBoostKeys: [String] = ["atk", "def", "spa", "spd", "spe", "acc", "eva"]  // boosts は常時この7能力をそろえて出す
let stateRevealedKeys: Set<String> = ["moves", "item", "ability"]
let stateFieldKeys: Set<String> = ["terrain", "weather", "terrainTurnsLeft", "weatherTurnsLeft", "trickRoomTurnsLeft"]
// sideConditions は { "p1": { 状態名(EN): 残りターン, ... }, "p2": {...} } の形

func writeState() {
    // state.json はバトルログ由来の状態 (monStates) から生成する
    func slotJSON(_ key: String) -> String? {
        guard let s = lastSlots[key] else { return nil }
        let side = key.hasPrefix("mine") ? "p1" : "p2"
        let st = monStates["\(side):\(s.speciesEn)"]
        var e = "{\"species\": \"\(jsonEscape(s.speciesEn))\", \"curHPPercent\": \(st?.hpPercent ?? s.hpPercent)"
        if let st, !st.status.isEmpty { e += ", \"status\": \"\(st.status)\"" }
        if unburdenActive.contains("\(side):\(s.speciesEn)") { e += ", \"unburden\": true" }
        if itemLostActive.contains("\(side):\(s.speciesEn)") { e += ", \"itemLost\": true" }
        if let st, !st.megaSpecies.isEmpty { e += ", \"mega\": true, \"megaSpecies\": \"\(jsonEscape(st.megaSpecies))\"" }
        // boosts は常に全7能力をそろえて出す (0 のものも省略しない)
        let bs = stateBoostKeys.map { "\"\($0)\": \(st?.boosts[$0] ?? 0)" }
        e += ", \"boosts\": {\(bs.joined(separator: ", "))}"
        if side == "p2" {
            var rev: [String] = []
            if let mv = revealedMoves[s.speciesEn], !mv.isEmpty {
                rev.append("\"moves\": [\(mv.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]")
            }
            if let it = revealedItems[s.speciesEn] { rev.append("\"item\": \"\(jsonEscape(it))\"") }
            if let ab = revealedAbilities[s.speciesEn] { rev.append("\"ability\": \"\(jsonEscape(ab))\"") }
            if !rev.isEmpty { e += ", \"revealed\": {\(rev.joined(separator: ", "))}" }
        }
        return e + "}"
    }
    let mine = [slotJSON("mineA"), slotJSON("mineB")].compactMap { $0 }
    let opps = [slotJSON("oppA"), slotJSON("oppB")].compactMap { $0 }
    if mine.isEmpty && opps.isEmpty { return }
    let team = oppTeamSeen.isEmpty ? "" : ", \"oppTeam\": [\(oppTeamSeen.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]"
    // 判明情報は場に出ていない相手分も含めて全種族分を送る (UI は項目単位で反映する)
    var revAll: [String] = []
    for sp in Set(revealedMoves.keys).union(revealedItems.keys).union(revealedAbilities.keys).sorted() {
        var parts: [String] = []
        if let mv = revealedMoves[sp], !mv.isEmpty {
            parts.append("\"moves\": [\(mv.map { "\"\(jsonEscape($0))\"" }.joined(separator: ", "))]")
        }
        if let it = revealedItems[sp] { parts.append("\"item\": \"\(jsonEscape(it))\"") }
        if let ab = revealedAbilities[sp] { parts.append("\"ability\": \"\(jsonEscape(ab))\"") }
        if !parts.isEmpty { revAll.append("\"\(jsonEscape(sp))\": {\(parts.joined(separator: ", "))}") }
    }
    let revJson = revAll.isEmpty ? "" : ", \"oppRevealed\": {\(revAll.joined(separator: ", "))}"
    // フィールドは両キー常時送る (空文字 = なし)。片方だけ送ると UI 側に
    // 終了したはずの天候・フィールドが残り続けるため。残りターンは
    // 継続中のものだけ追加キーで送る (期限切れ・未設定ではキーを出さない)
    var fieldParts = ["\"terrain\": \"\(logFieldTerrain)\"", "\"weather\": \"\(logFieldWeather)\""]
    let wLeft = turnsLeft(setTurn: fieldWeatherSetTurn, duration: fieldDurations)
    if !logFieldWeather.isEmpty && wLeft > 0 { fieldParts.append("\"weatherTurnsLeft\": \(wLeft)") }
    let tLeft = turnsLeft(setTurn: fieldTerrainSetTurn, duration: fieldDurations)
    if !logFieldTerrain.isEmpty && tLeft > 0 { fieldParts.append("\"terrainTurnsLeft\": \(tLeft)") }
    let rLeft = turnsLeft(setTurn: fieldTrickRoomSetTurn, duration: fieldDurations)
    if logTrickRoom && rLeft > 0 { fieldParts.append("\"trickRoomTurnsLeft\": \(rLeft)") }
    let field = "{\(fieldParts.joined(separator: ", "))}"
    // サイド状態 (壁・おいかぜ等) は継続中のものだけ、サイドごとに
    // 状態名 -> 残りターン で送る
    var scParts: [String] = []
    for sd in ["p1", "p2"] {
        guard let conds = sideCondSetTurns[sd] else { continue }
        let active = conds.compactMap { (name, st) -> String? in
            let left = turnsLeft(setTurn: st, duration: sideCondDurations[name] ?? 5)
            return left > 0 ? "\"\(name)\": \(left)" : nil
        }.sorted()
        if !active.isEmpty { scParts.append("\"\(sd)\": {\(active.joined(separator: ", "))}") }
    }
    let scJson = scParts.isEmpty ? "" : ", \"sideConditions\": {\(scParts.joined(separator: ", "))}"
    // 設置物 (ステルスロック等) はターンで切れないため、残りターン式の
    // sideConditions とは別に、層数つきでそのまま送る
    var hzParts: [String] = []
    for sd in ["p1", "p2"] {
        guard let hz = battleHazards[sd], !hz.isEmpty else { continue }
        let items = hz.keys.sorted().map { "\"\($0)\": \(hz[$0]!)" }
        hzParts.append("\"\(sd)\": {\(items.joined(separator: ", "))}")
    }
    let hzJson = hzParts.isEmpty ? "" : ", \"hazards\": {\(hzParts.joined(separator: ", "))}"
    let trainer = trainerOpp.isEmpty ? "" : ", \"oppTrainer\": \"\(jsonEscape(trainerOpp))\""
    // 相手のランク/レート (見せ合い後に画像認識側が oppRank /
    // oppRating へ読み取る。記録はトレーナー名と並べてここで行う)
    let rankJson = oppRank.isEmpty ? "" : ", \"oppRank\": \"\(jsonEscape(oppRank))\""
    let ratingJson = oppRating.isEmpty ? "" : ", \"oppRating\": \"\(jsonEscape(oppRating))\""
    // 試合 ID (開始時刻ベース)。UI 側が「イベント列が縮んだ」推測ではなく
    // この値の変化で新しい対戦の開始を確実に検知できるようにするための
    // 材料 (前の対戦の自動コンディションが次の対戦に残る事故の対策)
    let battleJson = battleArchiveId.isEmpty ? "" : ", \"battle\": \"\(battleArchiveId)\""
    let eventsJson = ", \"events\": [\(battleEvents.joined(separator: ", "))]"
    let json = "{\"mine\": [\(mine.joined(separator: ", "))], \"opps\": [\(opps.joined(separator: ", "))]\(team)\(revJson)\(trainer)\(rankJson)\(ratingJson)\(battleJson)\(eventsJson), \"field\": \(field)\(scJson)\(hzJson)}"
    if json == lastWritten { return }
    lastWritten = json
    try? json.write(to: outURL, atomically: true, encoding: .utf8)
    noteStateWrite(shape: "battle", json: json, eventsCount: battleEvents.count)
}

// MARK: - state.json スナップショット (証拠保全)
// battle_20261122_051707 の切り分けで、対戦中の state.json の実物が
// 残っておらず、UI がどの書き出しを読んだか断定できなかった。
// 形の切り替わり点の書き出しだけを試合ごとに蓄積し、次回以降の
// 切り分けに使う (serve.py が推論過程ログと同じ扱いで同梱する)
var stateSnapRecords: [[String: Any]] = []  // 対戦中 (未確定) の試合分
var stateSnapLeadIn: [[String: Any]] = []   // 試合の合間 (開始前・勝敗確定後) の分。次の試合の開始時に引き継ぐ
var stateSnapKey = ""                       // stateSnapRecords の書き出し先の試合キー
var stateSnapLastShape = ""                 // 直前の書き出しの形 ("battle" / "preview" / "reset")
var stateSnapLastEvents = -1                // 直前の書き出しが載せた events の件数
var stateSnapFirstBattlePending = true      // その試合の最初の対戦形をまだ記録していない

// events の JSON 断片列をオブジェクト列として返す (選出形の書き出しに
// 試合 ID と events を併記するために使う)
func battleEventsObjects() -> [Any] {
    battleEvents.compactMap { frag in
        guard let d = frag.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d)
    }
}

// state.json の書き出しのたびに呼び、残すべき切り替わり点であれば
// その内容をスナップショットとして蓄積する。残すのは (a) 選出形・
// リセット形の書き出し、(b) それに続く最初の対戦形、(c) events の
// 件数が前回より減った書き出し、(d) その試合の最初の対戦形
func noteStateWrite(shape: String, json: String, eventsCount: Int) {
    var take = shape != "battle"
    if shape == "battle" && !stateSnapLastShape.isEmpty && stateSnapLastShape != "battle" { take = true }
    if shape == "battle" && stateSnapFirstBattlePending { take = true }
    if stateSnapLastEvents >= 0 && eventsCount < stateSnapLastEvents { take = true }
    stateSnapLastShape = shape
    stateSnapLastEvents = eventsCount
    if shape == "battle" { stateSnapFirstBattlePending = false }
    if !take { return }
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.formatOptions = [.withInternetDateTime]
    var rec: [String: Any] = ["at": f.string(from: Date()), "shape": shape]
    if let d = json.data(using: .utf8), let obj = try? JSONSerialization.jsonObject(with: d) {
        rec["state"] = obj
    } else {
        rec["state"] = json
    }
    if battleArchiveId.isEmpty || winLogged {
        stateSnapLeadIn.append(rec)
    } else {
        stateSnapRecords.append(rec)
        flushStateSnapshots()
    }
}

// 蓄積したスナップショットを logs/battle_<試合キー>_states.json へ
// 書き出す (その試合の蓄積全件を毎回上書きする)
func flushStateSnapshots() {
    let key = battleArchiveId
    if key.isEmpty { return }
    if stateSnapKey != key {
        stateSnapKey = key
        // reader 再起動で対戦中の試合を引き継いだ場合は、既存の
        // 蓄積を読み込んでから続ける
        if stateSnapRecords.isEmpty {
            let url = scriptDir.appendingPathComponent("logs/battle_\(key)_states.json")
            if let data = try? Data(contentsOf: url),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let arr = obj["snapshots"] as? [[String: Any]] {
                stateSnapRecords = arr
            }
        }
    }
    if stateSnapRecords.isEmpty { return }
    let payload: [String: Any] = ["version": 1, "battle": key, "snapshots": stateSnapRecords]
    guard let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
    let dir = scriptDir.appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    try? data.write(to: dir.appendingPathComponent("battle_\(key)_states.json"))
}

// 新しい試合の開始時に呼ぶ: 合間に蓄積した選出形の記録をその試合の
// 冒頭の記録として引き継ぎ、最初の対戦形の記録を再武装する
func adoptStateSnapshotsForBattle() {
    stateSnapRecords = stateSnapLeadIn
    stateSnapLeadIn = []
    stateSnapKey = ""
    stateSnapFirstBattlePending = true
    flushStateSnapshots()
}

// MARK: - バトルログ (Showdown プロトコル形式)
// 画面から観測した出来事を Showdown のバトルログ形式で蓄積する。
// ターミナルにはこのログだけを表示し、battle.log にも保存する。
// ダメ計への反映 (state.json) は、このログ由来の状態から生成する。

let battleLogURL = scriptDir.appendingPathComponent("battle.log")
var battleLog: [String] = []
var logStarted = false
var currentTurn = 0
// ターン行の構造ガード用: 最後のターン行以降に技を使った枠のラベルと、
// ラウンド内の出来事を記録したか、ガード発火直後の判定側発火の抑止
var movesSinceTurnLine: Set<String> = []
var roundEventSeen = false
var suppressNextDetectorTurn = false
// 最後のターン行以降に交代で入った枠 (ターン行ガードの条件 (c) 用)
var enteredThisSegment: Set<String> = []
// 場にいない種族の文が既定枠へ帰属された回数 (側+種族ごと)。
// 繰り返しのデフォルト帰属をデバッグ記録するための数え
var defaultAttribCount: [String: Int] = [:]
// 場・サイド状態の残りターン管理: 開始した実効ターン (対戦開始前の
// 繰り出しで張られた場合は 1 として数える) を記録し、writeState が
// 現在ターンとの差から残りターンを出す。追跡は emitLog のフックで行う
// (プロトコル行が全ての状態変化の正本であるため)
var eventSlotSpecies: [String: String] = [:]  // slot -> その枠にいる種族 (プロトコル行からのみ追跡する)
var fieldWeatherSetTurn = 0
var fieldTerrainSetTurn = 0
var prevFieldWeather = ""        // 上書きされた直前の天候 (開始直後の特性帰属用)
var prevFieldWeatherSetTurn = 0
var prevFieldTerrain = ""        // 上書きされた直前の地形 (同上)
var prevFieldTerrainSetTurn = 0
let recoilMoves: Set<String> = ["Double-Edge", "Take Down", "Submission", "Volt Tackle",
                                "Flare Blitz", "Brave Bird", "Wood Hammer", "Head Smash",
                                "Wild Charge", "Head Charge", "Struggle"]
var fieldTrickRoomSetTurn = 0
var sideCondSetTurns: [String: [String: Int]] = [:]  // side -> 状態名(EN) -> 実効開始ターン
let sideCondDurations: [String: Int] = ["Reflect": 5, "Light Screen": 5, "Aurora Veil": 5, "Tailwind": 4, "Mist": 5, "Safeguard": 5, "Wide Guard": 1]
let fieldDurations = 5  // 天気・フィールド・トリックルームの基本継続ターン (岩・粘土等の延長は画面から知りえないため数えない)

func turnsLeft(setTurn: Int, duration: Int) -> Int {
    if setTurn <= 0 { return 0 }
    return max(0, setTurn + duration - max(currentTurn, 1))
}

// プロトコル行から場・サイド状態の開始/終了を追跡する (emitLog のフック)
func trackFieldEvent(_ line: String) {
    let eff = max(currentTurn, 1)
    if line.hasPrefix("|-weather|") {
        // 上書きされる側を控える (開始直後に天候・地形が上書きされた
        // 場合、先発の特性帰属は上書きされた側に対して行うため)
        let wname = String(line.dropFirst(10))
        if wname != "none", let ui = weatherUiByLogName[wname],
           !logFieldWeather.isEmpty, logFieldWeather != ui {
            prevFieldWeather = logFieldWeather
            prevFieldWeatherSetTurn = fieldWeatherSetTurn
        }
        fieldWeatherSetTurn = line.hasSuffix("|none") ? 0 : eff
    } else if line.hasPrefix("|-fieldstart|move: ") {
        let name = String(line.dropFirst("|-fieldstart|move: ".count))
        if name == "Trick Room" { fieldTrickRoomSetTurn = eff }
        else if name.hasSuffix(" Terrain") {
            let newTerrain = String(name.dropLast(8))
            if !logFieldTerrain.isEmpty, logFieldTerrain != newTerrain {
                prevFieldTerrain = logFieldTerrain
                prevFieldTerrainSetTurn = fieldTerrainSetTurn
            }
            fieldTerrainSetTurn = eff
        }
    } else if line.hasPrefix("|-fieldend|move: ") {
        let name = String(line.dropFirst("|-fieldend|move: ".count))
        if name == "Trick Room" { fieldTrickRoomSetTurn = 0 }
        else if name.hasSuffix(" Terrain") { fieldTerrainSetTurn = 0 }
    } else if line.hasPrefix("|-sidestart|") || line.hasPrefix("|-sideend|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 4, f[3].hasPrefix("move: ") else { return }
        let cond = String(f[3].dropFirst("move: ".count))
        guard sideCondDurations[cond] != nil else { return }
        if line.hasPrefix("|-sidestart|") {
            sideCondSetTurns[f[2], default: [:]][cond] = eff
        } else {
            sideCondSetTurns[f[2]]?[cond] = nil
        }
    }
}
var logFieldTerrain = ""
var logTrickRoom = false
var logFieldWeather = ""   // UI 表記 (Sun/Rain/Sand/Snow)

struct MonState {
    var hpPercent: Int = 100
    var hpText: String = "100/100"
    var hpMax: Int? = nil
    var status: String = ""   // Showdown コード (brn/par/psn/tox/slp/frz)、なしは ""
    var boosts: [String: Int] = [:]   // ランク変化 (atk/def/spa/spd/spe/acc/eva)
    var megaSpecies: String = ""   // メガシンカ済みならその種族EN (キーはベース種族のまま)
}
var monStates: [String: MonState] = [:]          // key: "p1:Species" / "p2:Species"
var revealedMoves: [String: [String]] = [:]      // speciesEn -> 技 (日本語)
var revealedItems: [String: String] = [:]        // speciesEn -> 持ち物 (日本語)
var revealedAbilities: [String: String] = [:]    // speciesEn -> 特性 (日本語)
var logSeenEntries = Set<String>()               // ゲーム内ログ画面エントリの重複排除
// ダメージ行の確定待ち管理: HP は被弾アニメーションで段階的に変わるため、
// 同じ値が 2 回続いて読めてからログに出す (途中値の行が量産されるのを防ぐ)
var pendingDamagePct: [String: Int] = [:]        // プレート名 -> 確定待ちの HP%
var lastEmittedPct: [String: Int] = [:]          // プレート名 -> ログ出力済みの HP%
var suspectJump: [String: (toPct: Int, turn: Int)] = [:]  // プレート名 -> 疑わしい大きな HP 跳びの保留 (誤読の疑い)
var firstEntryPlateHP: [String: String] = [:]  // プレート名 -> 初登場の交代行が示した HP 表記 (同値のダメージ行の重複抑止)
var sitrusWatch: [String: Int] = [:]  // key -> オボンのみ発動条件 (HP 半分以下) を跨いだ直後の HP% (発動の取りこぼし監視)
var lastMoveEmitSeq = -1                          // 最後に |move| 行を出した時点の actionSeq
var lastSwitchEmitSeq = -1                        // 最後に |switch| 行を出した時点の actionSeq
var fieldSetByMoveTurn = -1                       // 技で天候・地形を張ったターン (特性帰属のターン一致判定用。技が原因の場合は交代帰属しない)
var switchInTurn: [String: Int] = [:]             // "side:Species" -> 交代で入ったターン
var heldWeatherStart: (ui: String, logName: String, text: String, at: Date)? = nil  // 交代確定待ちで保留した天候開始
var heldTerrainStart: (ui: String, text: String, at: Date)? = nil                  // 同・地形開始
var heldTerrainReplace: (ui: String, text: String, at: Date)? = nil  // 出所を確認できない地形の上書き開始の保留
var pivotReturnAt: [String: Date] = [:]           // side -> 交代技で戻る文を消費した時刻 (後任の交代確定を早める)
var fieldHoldBypass = false                       // 保留した天候・地形を流す際の再保留防止
var pendingStatusFrom: [String: (code: String, at: Date)] = [:]  // "p1:Species" -> 状態異常ダメージの帰属
var wishSetTurn: [String: Int] = [:]               // side -> ねがいごとを使ったターン (回復の説明用)
var pendingHazard: (side: String, hazard: String, seq: Int)? = nil   // がんせきアックスの設置保留 (当たって初めて確定する)
var pendingRemoval: (side: String, seq: Int)? = nil                  // スピン系の設置物解除保留 (同上)
var battleHazards: [String: [String: Int]] = [:]                     // side -> 設置物EN -> 層数 (applyEvent が正本として保持)
let hazardCaps: [String: Int] = ["Stealth Rock": 1, "Spikes": 3, "Toxic Spikes": 2, "Sticky Web": 1]
var lastDamageLabel = ""                          // 直近にダメージを受けた枠 (急所の帰属先)
var lastDamageAt = Date.distantPast
var lastPendingLabel = ""                         // 確定待ちダメージの枠 (急所はダメージ行より先に表示される)
var pendingSwitchSpecies: [String: String] = [:]  // プレート名 -> 確定待ちの交代先種族
var pendingSwitchSince: [String: Date] = [:]      // プレート名 -> その種族を最初に検出した時刻
var slotLastHitAt: [String: Date] = [:]           // 枠ごとの最終プレートヒット時刻 (plate_stale 監視用)
var plateStaleOtherHits: [String: Int] = [:]      // その枠が無ヒットの間に相方枠がヒットしたフレーム数
var pendingSwitchCount: [String: Int] = [:]       // 同じ種族が連続で見えた回数
var slotSwapPending: [String: (a: String, b: String, count: Int)] = [:]  // 側 -> 枠入れ替わり候補 (2 回連続で確定)
var actionSeq = 0                                  // |move| / |turn| の通し番号 (行動の区切り)
var lastDamageSeq: [String: Int] = [:]             // プレート名 -> ダメージ行を出した行動番号
var lastDamageTurn: [String: Int] = [:]            // プレート名 -> ダメージ行を出したターン番号
var lastDamageDir: [String: Int] = [:]             // プレート名 -> 最後に出した行の向き (-1: ダメージ / +1: 回復)
var lastDamageTime: [String: Date] = [:]           // プレート名 -> 最後にダメージ/回復行を出した時刻
var lastCritAt: [String: Date] = [:]               // 枠 -> 最後に |-crit| を出した時刻
var heldLine: [String: (toPct: Int, dir: Int, seq: Int, turn: Int, hpText: String)] = [:]  // プレート名 -> 行動内に保留したダメージ/回復行
var pendingFaints: [(slot: String, speciesEn: String, at: Date)] = []  // 遅延出力するひんし行 (効果行より後に並べるため)
var faintedSlots: [String: String] = [:]           // ひんし行を出した枠 -> 種族 (交代が確定するまでプレート読みを無視する)
var grassyHealTurn: [String: Int] = [:]            // プレート名 -> グラッシーフィールド回復を帰属したターン (1 ターン 1 回まで)
var lastSideCondAt: [String: Date] = [:]          // "side:move:phase" -> サイドコンディション告知を処理した時刻
var commandPhaseSeen = false                      // コマンド選択中 (全プレート表示) かどうか。ターン数え用
var pendingDamageCount: [String: Int] = [:]       // プレート名 -> 同じ HP% が続いた回数 (3 回で確定)
var pendingDamageSince: [String: Date] = [:]       // プレート名 -> その HP% が最初に現れた時刻 (段階アニメーションの途中値と区別する)
var winLogged = false                             // このバトルで勝敗が確定したか
var lastLogEventAt = Date.distantPast              // 最後にログ行が出た時刻 (開始直後の監視継続用)
var lastMoveSigAt: [String: Date] = [:]           // "枠|技EN" -> |move| を出した時刻 (OCR ゆれでの二重出力防止)
var lastMoveSigSeq: [String: Int] = [:]           // "枠|技EN|tN" -> その技行を出した時点の行動番号 (境界検出の遅れ判定)
var prevBoostFragment: (text: String, speciesEn: String, side: String, at: Date)? = nil   // ランク変化文の断片 (主語+能力名だけ先に届いた文)
var lastSingleActAt: [String: Date] = [:]         // 枠 -> |-singleactivate| を出した時刻
var lastAbilityEmit: [String: Date] = [:]         // "side:種族:特性" -> |-ability| を出した時刻 (二重出力の抑止)
var turnRawFrames = 0                             // プレート生読みで 4 枚見えた連続フレーム数 (ターン誤発火の保険)
var lastMoveLabel = ""                            // 直近の |move| の使用者ラベル (ミスの帰属用)
var lastMoveName = ""                             // 直近の |move| の技名 (EN, 推定イベント用)
var lastMoveSeq = -1                              // 直近の |move| が出た actionSeq
var battleEvents: [String] = []                   // 推定エンジン用イベント (JSON 断片の配列)
var entryBatchId = 0                              // 同時入場バッチの通し番号 ('ab' イベント用)
var entryBatchOpen = false                        // 入場ウィンドウ (|switch| の連続区間) が開いているか
var entryBatchMembers: Set<String> = []           // 現バッチで入場したラベル ("p2a: 種族")
var entryBatchAbBuffer: [(label: String, ability: String)] = []  // ウィンドウ内の |-ability| 行 (発動順)
var lastExactHp: [String: [Int]] = [:]            // key -> [現在HP, 最大HP] (自軍の正確な数値の追跡)
var lastDmgEventPrevExact: [String: [Int]] = [:]  // key -> 直近の dmg イベントが使った基準実数 ([] = 基準なし)。再放出の上書き時に amt を元の基準から計算し直すため
var lastMoveMsgAt = Date.distantPast
var lastFallbackText = ""                         // 直近の |-message| の正規化文 (OCR ゆれの重複防止)
var fieldWeatherSetAt = Date.distantPast          // 天候が張られた時刻 (特性の帰属判定用)
var fieldTerrainSetAt = Date.distantPast          // フィールドが張られた時刻
var lastSwitchIn: [String: (slot: String, at: Date)] = [:]  // "side:Species" -> 場に出た枠と時刻
var fieldAbilityDone: [String: Date] = [:]        // "side:Species" -> 特性帰属済みの繰り出し時刻
var intimidateDone: [String: Date] = [:]          // "side:Species" -> いかく帰属済みの繰り出し時刻
var lastBoostApply: [String: (seq: Int, turn: Int, at: Date)] = [:]  // "slot|stat|delta" -> 最終適用 (再読での二重適用防止)
var boostPathAt: [String: (at: Date, salvage: Bool)] = [:]  // "side:種族|stat|delta" -> 経路 (正規/サルベージ) をまたぐ二重適用防止
var emittedSwitchKeys: Set<String> = []            // |switch| を出した "side:Species" (ランク変化行の保留判定)
var pendingUnburden: Set<String> = []              // 交代行が出る前にシード消費を検知した種族 (かるわざ発動を交代行の後に出す)
var unburdenActive: Set<String> = []               // かるわざ発動中 (state.json の unburden フラグ用。交代で解除)
var itemLostActive: Set<String> = []               // 持ち物を消費・喪失した種族 (state.json の itemLost フラグ用。対戦中は交代しても解除されない)
var subActive: Set<String> = []                    // 身代わりが出ている種族 ("side:Species"。出現文の二重出力防止)
var boostTouchedStats: Set<String> = []            // この対戦でランク変化を記録した "side:Species|stat" (地形シード遡及補完の二重適用防止)
var heldBoostLines: [String: [(stat: String, delta: Int, at: Date)]] = [:]  // 交代行より先に届いたランク変化の保留 (枠は出す時点で付け直す)
var faintedSpecies: Set<String> = []   // "p2:Sneasler" 形式: ひんし行が出て、まだ交代で戻っていない種族 (あり得ない技行の抑止用)
var heldEntryBoosts: [(key: String, line: String, at: Date)] = []  // 入場特性 (いかく等) の効果行が原因側の交代行より先に届いた場合の保留
var recentAtkDrops: [String: (at: Date, seq: Int)] = [:]  // "side:Species" -> 攻撃 -1 の適用 (いかく遡及帰属用)
var lastEffectAt: [String: Date] = [:]            // 相性行の二重出力防止 ("slot|kind")
var protectMoveTurn: [String: Int] = [:]         // 枠 -> まもるを使ったターン (activate 行の照合用)
var effectBySeq: [Int: [String: String]] = [:]    // 行動番号 -> ラベル -> 相性種別 (同じ技での相性の付け替え判定)
var damagedBySeq: [Int: Set<String>] = [:]       // 行動番号 -> 被ダメしたラベルの集合 (同上)
var lastFallbackAt = Date.distantPast

var moveJa2En: [String: String] = [:]
var itemJa2En: [String: String] = [:]
var abilityJa2En: [String: String] = [:]

func loadLogNames() {
    let url = scriptDir.appendingPathComponent("data/log_names.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    moveJa2En = obj["moves"] as? [String: String] ?? [:]
    itemJa2En = obj["items"] as? [String: String] ?? [:]
    abilityJa2En = obj["abilities"] as? [String: String] ?? [:]
}

var speciesAbilityMap: [String: [String]] = [:]   // 種族EN -> 特性EN一覧 (フォルム判別用)
var speciesMoveMap: [String: [String]] = [:]      // 種族EN -> 習得技EN一覧 (フォルム判別用)

func loadSpeciesAbilities() {
    let url = scriptDir.appendingPathComponent("data/species_abilities.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
    speciesAbilityMap = obj
}

func loadSpeciesMoves() {
    let url = scriptDir.appendingPathComponent("data/species_moves.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: [String]] else { return }
    speciesMoveMap = obj
}

// MARK: - 表示用ログ (Showdown のテキストログ風レンダリング)
// 内部イベント (プロトコル形式) は battle_protocol.log に残し、ターミナルと
// battle.log には人間可読な Showdown 風テキストを出す
var displayLog: [String] = []
let protocolLogURL = scriptDir.appendingPathComponent("battle_protocol.log")
var renderSlotSpecies: [String: String] = [:]   // 枠 ("p1a") -> 現在の種族
var renderFainted: Set<String> = []              // ひんしになった枠 (交代が引き戻しかの判定)
var renderLastPct: [String: Int] = [:]           // ラベル -> 最後に表示した HP% (喪失 % の計算用)
var renderPokeP1: [String] = []
var renderPokeP2: [String] = []
var renderWeatherProto = ""                     // 現在の天候 (プロトコル名)
var renderHold: [String] = []                     // フィールド開始行の保留 (特性行が直後に来たら順序を入れ替える)
var renderPendingBlank = false                    // 繰り出しブロックの後に空行を入れる予約
var renderMovesSeen = false                       // このターンで技が既に出たか
var renderFaintPending = false                    // ひんし後で交代待ちか (繰り出しブロック判定)
var renderBerryAt: [String: (item: String, at: Date)] = [:]  // ラベル -> きのみを食べた時刻・名前 (回復行の具体化)
var forfeitName: String? = nil                  // 降参したトレーナー名

func regulationDisplay() -> String {
    if let text = try? String(contentsOf: scriptDir.appendingPathComponent("data/regulation.json"), encoding: .utf8),
       let r = text.range(of: "\"regulation\"") {
        let rest = text[r.upperBound...]
        if let q1 = rest.firstIndex(of: "\"") {
            let after = rest[rest.index(after: q1)...]
            if let q2 = after.firstIndex(of: "\"") { return String(after[..<q2]) }
        }
    }
    return "M-C"
}

func renderLabelParts(_ label: String) -> (slot: String, side: String, species: String) {
    let parts = label.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
    let slot = parts.first ?? ""
    return (slot, slot.hasPrefix("p2") ? "p2" : "p1", parts.count > 1 ? parts[1] : "")
}

func renderPrefix(_ side: String) -> String { side == "p2" ? "The opposing " : "" }

func renderPct(of hpText: String) -> Int? {
    if hpText.contains("fnt") { return 0 }
    let parts = hpText.split(separator: "/")
    guard parts.count == 2, let c = Int(parts[0].trimmingCharacters(in: .whitespaces)),
          let m = Int(parts[1].trimmingCharacters(in: .whitespaces)), m > 0 else { return nil }
    return Int((Double(c) * 100.0 / Double(m)).rounded())
}

func renderLogLine(_ line: String) -> [String] {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 2 else { return [] }
    let oppName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
    switch f[1] {
    case "gametype":
        return []
    case "poke":
        if f.count >= 4 {
            if f[2] == "p1" { renderPokeP1.append(f[3]) } else { renderPokeP2.append(f[3]) }
        }
        return []
    case "start":
        let mine = trainerMine.isEmpty ? "you" : trainerMine
        var header = ["\(mine) and \(oppName) joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg \(regulationDisplay())", "Rated battle",
                "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
                trainerMine.isEmpty ? "Your team:" : "\(trainerMine)'s team:", renderPokeP1.joined(separator: " / "),
                "\(oppName)'s team:", renderPokeP2.joined(separator: " / "), "",
                "Battle started between \(mine) and \(oppName)!"]
        // 相手のランク/レート (読み取れた場合のみ、トレーナー名と併記)
        if !oppRank.isEmpty { header.append("\(oppName)'s rank: \(oppRank)") }
        if !oppRating.isEmpty { header.append("\(oppName)'s rating: \(oppRating)") }
        header.append("")
        return header
    case "switch":
        guard f.count >= 5 else { return [] }
        let (slot, side, _) = renderLabelParts(f[2])
        let species = f[3]
        var out: [String] = []
        var display = species
        if let mega = monStates["\(side):\(species)"]?.megaSpecies, !mega.isEmpty {
            display = "\(species) (\(mega))"
        }
        if let prev = renderSlotSpecies[slot], prev != species, !renderFainted.contains(slot) {
            if side == "p2" { out.append("\(oppName) withdrew \(prev)!") }
            else { out.append("\(prev), come back!") }
        }
        if side == "p2" { out.append("\(oppName) sent out \(display)!") }
        else { out.append("Go! \(display)!") }
        renderSlotSpecies[slot] = species
        renderFainted.remove(slot)
        if let pct = renderPct(of: f[4]) { renderLastPct[f[2]] = pct }
        return out
    case "turn":
        var out: [String] = []
        if let n = Int(f[2]), n > 1 {
            switch renderWeatherProto {
            case "Sunny Day": out.append("(The sunlight is strong.)")
            case "Rain Dance": out.append("(Rain continues to fall.)")
            case "Sandstorm": out.append("(The sandstorm is raging.)")
            case "Snow", "Snowscape": out.append("(The snow is falling.)")
            default: break
            }
        }
        out.append("")
        out.append("Turn \(f[2])")
        return out
    case "move":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["\(renderPrefix(side))\(species) used \(f[3])!"]
    case "-damage":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        var out: [String] = []
        if f.count >= 5 {
            if f[4].contains("psn") || f[4].contains("tox") { out.append("\(renderPrefix(side))\(species) was hurt by its poison!") }
            else if f[4].contains("brn") { out.append("\(renderPrefix(side))\(species) was hurt by its burn!") }
            else if f[4].contains("Stealth Rock") { out.append("(The pointed stones dug into \(renderPrefix(side))\(species)!)") }
            else if f[4].contains("Spikes") { out.append("(\(renderPrefix(side))\(species) was hurt by the spikes!)") }
            else if f[4].contains("Rocky Helmet") { out.append("(\(renderPrefix(side))\(species) was hurt by Rocky Helmet!)") }
        }
        if let pct = renderPct(of: f[3]) {
            let lost = (renderLastPct[f[2]] ?? 100) - pct
            renderLastPct[f[2]] = pct
            if lost > 0 { out.append("(\(renderPrefix(side))\(species) lost \(lost)% of its health!)") }
        }
        return out
    case "-heal":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if let pct = renderPct(of: f[3]) { renderLastPct[f[2]] = pct }
        // 発生源が付いている回復は「(Leftovers)」のように後ろへ付ける
        if f.count >= 5 && f[4].hasPrefix("[from] ") {
            renderBerryAt[f[2]] = nil
            var src = String(f[4].dropFirst("[from] ".count))
            if src.hasPrefix("item: ") { src = String(src.dropFirst("item: ".count)) }
            return ["\(renderPrefix(side))\(species) had its HP restored. (\(src))"]
        }
        if let b = renderBerryAt[f[2]], Date().timeIntervalSince(b.at) < 6 {
            renderBerryAt[f[2]] = nil
            return ["\(renderPrefix(side))\(species) restored HP using its \(b.item)!"]
        }
        return ["\(renderPrefix(side))\(species) had its HP restored."]
    case "faint":
        guard f.count >= 3 else { return [] }
        let (slot, side, species) = renderLabelParts(f[2])
        renderFainted.insert(slot)
        return ["\(renderPrefix(side))\(species) fainted!"]
    case "-crit":
        return ["A critical hit!"]
    case "-supereffective":
        return ["It's super effective!"]
    case "-resisted":
        return ["It's not very effective..."]
    case "-miss":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[3])
        return ["\(renderPrefix(side))\(species) avoided the attack!"]
    case "-status":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let name = "\(renderPrefix(side))\(species)"
        switch f[3] {
        case "brn": return ["\(name) was burned!"]
        case "psn": return ["\(name) was poisoned!"]
        case "tox": return ["\(name) was badly poisoned!"]
        case "par": return ["\(name) was paralyzed! It may be unable to move!"]
        case "slp": return ["\(name) fell asleep!"]
        case "frz": return ["\(name) was frozen solid!"]
        default: return []
        }
    case "-item":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let item = f[3]
        let name = "\(renderPrefix(side))\(species)"
        if item.contains("ite") && item != "Eviolite" {
            return ["\(name)'s \(item) is reacting to the Key Stone!"]
        }
        if item.hasSuffix("Berry") {
            renderBerryAt[f[2]] = (item, Date())
            return ["\(name) ate its \(item)!"]
        }
        return ["[\(name)'s \(item)]"]
    case "-ability":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["[\(renderPrefix(side))\(species)'s \(f[3])]"]
    case "detailschange":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        return ["\(renderPrefix(side))\(species) has Mega Evolved into Mega \(species)!"]
    case "-mega":
        return []
    case "-weather":
        guard f.count >= 3 else { return [] }
        let w = f[2]
        var out: [String] = []
        switch w {
        case "Sunny Day": out = ["The sunlight turned harsh!"]
        case "Rain Dance": out = ["It started to rain!"]
        case "Sandstorm": out = ["A sandstorm kicked up!"]
        case "Snow", "Snowscape": out = ["It started to snow!"]
        case "none":
            switch renderWeatherProto {
            case "Sunny Day": out = ["The sunlight faded."]
            case "Rain Dance": out = ["The rain stopped."]
            case "Sandstorm": out = ["The sandstorm subsided."]
            case "Snow", "Snowscape": out = ["The snow stopped."]
            default: out = []
            }
        default: out = []
        }
        renderWeatherProto = (w == "none") ? "" : w
        return out
    case "-fieldstart", "-fieldend":
        guard f.count >= 3 else { return [] }
        let terrain = f[2].replacingOccurrences(of: "move: ", with: "").replacingOccurrences(of: " Terrain", with: "")
        if f[1] == "-fieldstart" {
            switch terrain {
            case "Trick Room": return []
            case "Psychic": return ["The battlefield got weird!"]
            case "Electric": return ["An electric current ran across the battlefield!"]
            case "Grassy": return ["Grass grew to cover the battlefield!"]
            case "Misty": return ["Mist swirled around the battlefield!"]
            default: return []
            }
        } else {
            switch terrain {
            case "Trick Room": return ["The dimensions returned to normal!"]
            case "Psychic": return ["The battlefield returned to normal."]
            case "Electric": return ["The electricity disappeared from the battlefield."]
            case "Grassy": return ["The grass disappeared from the battlefield."]
            case "Misty": return ["The mist disappeared from the battlefield."]
            default: return []
            }
        }
    case "-boost", "-unboost":
        guard f.count >= 5, let n = Int(f[4]) else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let statName = ["atk": "Attack", "def": "Defense", "spa": "Sp. Atk", "spd": "Sp. Def", "spe": "Speed", "acc": "accuracy", "eva": "evasion"][f[3]] ?? f[3]
        let name = "\(renderPrefix(side))\(species)"
        if f[1] == "-boost" {
            return ["\(name)'s \(statName) \(n >= 3 ? "drastically rose!" : n == 2 ? "sharply rose!" : "rose!")"]
        } else {
            return ["\(name)'s \(statName) \(n >= 3 ? "severely fell!" : n == 2 ? "harshly fell!" : "fell!")"]
        }
    case "-singleactivate":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3].contains("Follow Me") || f[3].contains("Rage Powder") {
            return ["\(renderPrefix(side))\(species) became the center of attention!"]
        }
        return []
    case "-start":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3] == "move: Yawn" { return ["\(renderPrefix(side))\(species) became drowsy!"] }
        return []
    case "-activate":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3].contains("Focus Sash") { return ["(\(renderPrefix(side))\(species) held on thanks to its Focus Sash!)"] }
        if f[3].contains("Protect") { return ["\(renderPrefix(side))\(species) protected itself!"] }
        if f[3].contains("Wide Guard") { return ["\(renderPrefix(side))\(species) was protected by Wide Guard!"] }
        if f[3].contains("Terrain") {
            let tn = f[3].replacingOccurrences(of: "move: ", with: "")
            return ["\(renderPrefix(side))\(species) was protected by the \(tn)!"]
        }
        return []
    case "-sidestart", "-sideend":
        guard f.count >= 4 else { return [] }
        if f[3].contains("Stealth Rock") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Pointed stones float around the opposing team!)" : "(Pointed stones float around your team!)"]
            }
            return [f[2] == "p2" ? "(The pointed stones disappeared from around the opposing team!)" : "(The pointed stones disappeared from around your team!)"]
        }
        if f[3].contains("Toxic Spikes") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Poison spikes were scattered on the ground around the opposing team!)" : "(Poison spikes were scattered on the ground around your team!)"]
            }
            return [f[2] == "p2" ? "(The poison spikes disappeared from the ground around the opposing team!)" : "(The poison spikes disappeared from the ground around your team!)"]
        }
        if f[3].contains("Spikes") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(Spikes were scattered on the ground around the opposing team!)" : "(Spikes were scattered on the ground around your team!)"]
            }
            return [f[2] == "p2" ? "(The spikes disappeared from the ground around the opposing team!)" : "(The spikes disappeared from the ground around your team!)"]
        }
        if f[3].contains("Tailwind") {
            if f[1] == "-sidestart" {
                return [f[2] == "p2" ? "(The Tailwind started blowing on the opposing team's side!)" : "(The Tailwind started blowing!)"]
            }
            return [f[2] == "p2" ? "(The Tailwind on the opposing team's side stopped blowing.)" : "(The Tailwind stopped blowing.)"]
        }
        return []
    case "-cant":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        let name = "\(renderPrefix(side))\(species)"
        switch f[3] {
        case "par": return ["\(name) is paralyzed! It can't move!"]
        case "frz": return ["\(name) is frozen solid! It can't move!"]
        case "slp": return ["\(name) is fast asleep."]
        case "flinch": return ["\(name) flinched and couldn't move!"]
        default: return []
        }
    case "-fail":
        return ["But it failed!"]
    case "-message":
        return f.count >= 3 ? [f.dropFirst(2).joined(separator: "|")] : []
    case "win":
        guard f.count >= 3 else { return [] }
        var winner = f[2]
        if winner == "p1" { winner = trainerMine.isEmpty ? "You" : trainerMine }
        if winner == "p2" { winner = oppName }
        if let fn = forfeitName {
            return ["\(fn) forfeited.", "", "\(winner) won the battle!"]
        }
        return ["\(winner) won the battle!"]
    default:
        return []
    }
}

// MARK: - イベント適用 (状態の正本)
// プロトコル行を状態へ畳み込む単一の適用経路。検出側は行を出すことに
// 専念し、状態はこちらでのみ変える。保存した battle_protocol.log を
// この関数に再生すれば、対戦中の状態が再構築できる (ハーネスで検証)
let weatherUiByLogName: [String: String] = ["Rain Dance": "Rain", "Sunny Day": "Sun", "Sandstorm": "Sand", "Snow": "Snow"]

func applyEvent(_ line: String) {
    trackFieldEvent(line)  // 残りターン管理 (開始ターンの記録)
    // 設置物はここを正本として保持する (state.json の hazards 用)。
    // sidestart/sideend 行が唯一の入力で、保存したプロトコルログを
    // 再生すれば設置状態も再構築できる
    if line.hasPrefix("|-sidestart|") || line.hasPrefix("|-sideend|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, f[3].hasPrefix("move: ") {
            let name = String(f[3].dropFirst("move: ".count))
            if let cap = hazardCaps[name] {
                if line.hasPrefix("|-sidestart|") {
                    battleHazards[f[2], default: [:]][name] = min(cap, (battleHazards[f[2]]?[name] ?? 0) + 1)
                } else {
                    battleHazards[f[2]]?[name] = nil
                }
            }
        }
    }
    if line.hasPrefix("|turn|") {
        if let n = Int(line.dropFirst(6)) { currentTurn = n }
    } else if line.hasPrefix("|-weather|") {
        let name = String(line.dropFirst(10))
        if name == "none" { logFieldWeather = "" }
        else if let ui = weatherUiByLogName[name] { logFieldWeather = ui }
    } else if line.hasPrefix("|-fieldstart|move: ") {
        let name = String(line.dropFirst(19))
        if name == "Trick Room" { logTrickRoom = true }
        else if name.hasSuffix(" Terrain") { logFieldTerrain = String(name.dropLast(8)) }
    } else if line.hasPrefix("|-fieldend|move: ") {
        let name = String(line.dropFirst(17))
        if name == "Trick Room" { logTrickRoom = false }
        else if name.hasSuffix(" Terrain") { logFieldTerrain = "" }
    } else if line.hasPrefix("|-status|") || line.hasPrefix("|-curestatus|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.status = line.hasPrefix("|-status|") ? f[3] : ""
        }
    } else if line.hasPrefix("|-boost|") || line.hasPrefix("|-unboost|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 5, let ss = parseSlotSpecies(f[2]), let n = Int(f[4]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            let delta = line.hasPrefix("|-boost|") ? n : -n
            let cur = monStates[key]?.boosts[f[3]] ?? 0
            monStates[key]?.boosts[f[3]] = max(-6, min(6, cur + delta))
        }
    } else if line.hasPrefix("|-damage|") || line.hasPrefix("|-heal|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            let hp = f[3].split(separator: "/")
            if hp.count == 2, let a = Int(hp[0].trimmingCharacters(in: .whitespaces)),
               let b = Int(hp[1].trimmingCharacters(in: .whitespaces)) {
                monStates[key]?.hpPercent = b > 0 ? Int((Double(a) / Double(b) * 100).rounded()) : a
                monStates[key]?.hpText = f[3]
            }
            // オボンのみ回復行は「消費した」ことも含む (再生で復元できるように)
            if line.hasPrefix("|-heal|"), f.count >= 5, f[4].contains("item: Sitrus Berry") {
                itemLostActive.insert(key)
            }
        }
    } else if line.hasPrefix("|faint|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.hpPercent = 0
            subActive.remove(key)
            faintedSpecies.insert(key)
        }
    } else if line.hasPrefix("|switch|") || line.hasPrefix("|drag|") {
        lastSwitchEmitSeq = actionSeq
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            // その枠にいた前の種族は交代でランク変化・かるわざが解除される
            if let prev = eventSlotSpecies[ss.slot], prev != ss.speciesEn {
                let pk = "\(ss.side):\(prev)"
                monStates[pk]?.boosts = [:]
                unburdenActive.remove(pk)
                subActive.remove(pk)
            }
            eventSlotSpecies[ss.slot] = ss.speciesEn
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.boosts = [:]  // 入場時はランク変化なし
            faintedSpecies.remove(key)   // 交代で戻れば、ひんし済み扱いは解ける
        }
    } else if line.hasPrefix("|detailschange|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if monStates[key] == nil { monStates[key] = MonState() }
            monStates[key]?.megaSpecies = f[3].split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? f[3]
        }
    } else if line.hasPrefix("|-ability|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            if ss.side == "p2" { revealedAbilities[ss.speciesEn] = abilityJa2En.first { $0.value == f[3] }?.key ?? f[3] }
            // かるわざ の発動行は「持ち物を失った」ことの帰結として出す
            // 行なので、再生時もこの行から両方の状態を復元できる
            if f[3] == "Unburden" { unburdenActive.insert(key); itemLostActive.insert(key) }
        }
    } else if line.hasPrefix("|-item|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == "p2" {
            revealedItems[ss.speciesEn] = itemJa2En.first { $0.value == f[3] }?.key ?? f[3]
        }
    } else if line.hasPrefix("|-start|") || line.hasPrefix("|-end|") {
        // 身代わりの有無を追跡する (出現文の再読で開始行を二重に出さないため)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), f[3] == "Substitute" {
            let key = "\(ss.side):\(ss.speciesEn)"
            if line.hasPrefix("|-start|") { subActive.insert(key) } else { subActive.remove(key) }
        }
    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq
        // まもるの使用ターンを控える (activate 行の同ターン照合用)
        let mf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if mf.count >= 4 && mf[3] == "Protect" {
            let pslot = mf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn }
        }
        // 相手の技は判明情報として記録する (行は英語名のため和名に戻す)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == "p2" {
            let mvJa = moveJa2En.first { $0.value == f[3] }?.key ?? f[3]
            if !(revealedMoves[ss.speciesEn]?.contains(mvJa) ?? false) {
                revealedMoves[ss.speciesEn, default: []].append(mvJa)
            }
        }
    } else if line.hasPrefix("|-enditem|") {
        // 持ち物の消費・喪失 (画面に文が出ない推論イベントのため、ログには
        // 残さず applyEvent への直接適用だけで状態に反映する経路)
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3, let ss = parseSlotSpecies(f[2]) {
            let key = "\(ss.side):\(ss.speciesEn)"
            itemLostActive.insert(key)
            let abilityJa = ss.side == "p1" ? (teamEntries[ss.speciesEn]?["ability"] as? String) : revealedAbilities[ss.speciesEn]
            if abilityJa == "かるわざ" { unburdenActive.insert(key) }
        }
    }
}

// "p2a: Sneasler" -> (slot, side, speciesEn)
func parseSlotSpecies(_ s: String) -> (slot: String, side: String, speciesEn: String)? {
    let parts = s.split(separator: ":", maxSplits: 1)
    guard parts.count == 2 else { return nil }
    let slot = parts[0].trimmingCharacters(in: .whitespaces)
    let sp = parts[1].trimmingCharacters(in: .whitespaces)
    guard slot.hasPrefix("p1") || slot.hasPrefix("p2"), !sp.isEmpty else { return nil }
    return (slot, String(slot.prefix(2)), sp)
}

// ラウンドの中でしか起きない出来事の行か (ターン行の構造ガード用)。
// 対戦開始時にも出る行 (繰り出し・入場特性・フィールドや天候の開始) は
// 含めない
func isRoundEventLine(_ line: String) -> Bool {
    for p in ["|move|", "|-damage|", "|-heal|", "|faint|", "|-status|", "|-boost|", "|-unboost|",
              "|-activate|", "|-start|", "|-end|", "|-item|", "|-enditem|", "|-sidestart|", "|-sideend|",
              "|detailschange|", "|-mega|", "|-crit|", "|-fail|"] {
        if line.hasPrefix(p) { return true }
    }
    return false
}

// 同一種族ファミリーか (ベース名と、そのフォルム・メガは同一視する)。
// 行の主語が場の実在と食い違う「あり得ない行」を弾く判定に使う
func sameSpeciesFamily(_ a: String, _ b: String) -> Bool {
    if a == b { return true }
    func famKey(_ n: String) -> String {
        for suf in ["-Mega-X", "-Mega-Y", "-Mega-Z", "-Mega", "-Blade", "-Shield"] where n.hasSuffix(suf) {
            return String(n.dropLast(suf.count))
        }
        return n
    }
    if famKey(a) == famKey(b) { return true }
    return a.hasPrefix(b + "-") || b.hasPrefix(a + "-")
}

// |-ability| 行の妥当性: その種族ファミリー (ベース+全フォルム+メガ) の
// 持ち得る特性に含まれない特性行は、崩れた文の誤帰属として弾く
// (実例: 2026-11-22 battle_20261122_050512、ターン3に
//  「|-ability|p1a: Charizard|Intimidate」という不可能な行が出た)。
// ファミリーのデータが無い種族は判定できないため通す。コピー特性
// (トレース等) を持つ種族は、相手の特性を名乗る行があり得るため通す
func abilityLinePlausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 4, let ss = parseSlotSpecies(f[2]) else { return true }
    let ability = f[3].trimmingCharacters(in: .whitespaces)
    let familyKeys = speciesAbilityMap.keys.filter {
        $0 == ss.speciesEn || $0.hasPrefix(ss.speciesEn + "-") || ss.speciesEn.hasPrefix($0 + "-")
    }
    guard !familyKeys.isEmpty else { return true }
    var pool = Set<String>()
    for k in familyKeys { pool.formUnion(speciesAbilityMap[k] ?? []) }
    if pool.contains(ability) { return true }
    let copyAbilities: Set<String> = ["Trace", "Receiver", "Power of Alchemy"]
    if !pool.isDisjoint(with: copyAbilities) { return true }
    return false
}

// |move| 行の決定的な不可能性: 使用者がひんし済みで場に戻って
// いない場合は、崩れた文の誤帰属として弾く (実例: 2026-11-22
// battle_20261122_050512、ターン2で倒れた Sneasler がターン3に
//  p2a の技行として現れた)
func moveLineHardImplausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    return faintedSpecies.contains("\(ss.side):\(ss.speciesEn)")
}

// |move| 行の使用者が、その側のどちらの枠の現 occupants でもないか。
// 交代の取りこぼし時は既定帰属で技行を出すのが従来方針のため、
// これは行を弾く判定には使わず、証拠記録専用とする。枠の
// occupants はプレート側 (lastSlots) が正 (交代行がガードで
// 破棄されても場には出ているため、行ベースの記録は予備に回す)
func moveLineOffField(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    let slotA = "\(ss.side)a", slotB = "\(ss.side)b"
    let plateOf: (String) -> String = { s in (ss.side == "p1" ? "mine" : "opp") + (s.hasSuffix("a") ? "A" : "B") }
    guard let occ = lastSlots[plateOf(ss.slot)]?.speciesEn ?? eventSlotSpecies[ss.slot] else { return false }
    if sameSpeciesFamily(occ, ss.speciesEn) { return false }
    if occ.hasPrefix("Ditto") { return false }   // へんしん中は相手の姿で技文が出る
    let sibSlot = ss.slot == slotA ? slotB : slotA
    if let sib = lastSlots[plateOf(sibSlot)]?.speciesEn ?? eventSlotSpecies[sibSlot], sameSpeciesFamily(sib, ss.speciesEn) { return false }
    // その種族がちょうど交代で入ってくる途中なら、確定待ちの誤差として扱う
    let prefix = ss.side == "p1" ? "mine" : "opp"
    for plate in ["\(prefix)A", "\(prefix)B"] where pendingSwitchSpecies[plate] == ss.speciesEn { return false }
    return true
}

// 天候・地形を呼ぶ特性と、対応するフィールド行 (プロトコル表記と
// 表示表記) の対応。特性行の生成がフィールド行より遅れた場合の
// 並び訂正に使う (emitLog / 描画部)
func fieldLineForAbility(_ ability: String) -> String? {
    switch ability {
    case "Drought": return "|-weather|Sunny Day"
    case "Drizzle": return "|-weather|Rain Dance"
    case "Sand Stream": return "|-weather|Sandstorm"
    case "Snow Warning": return "|-weather|Snow"
    case "Electric Surge": return "|-fieldstart|move: Electric Terrain"
    case "Grassy Surge": return "|-fieldstart|move: Grassy Terrain"
    case "Misty Surge": return "|-fieldstart|move: Misty Terrain"
    case "Psychic Surge": return "|-fieldstart|move: Psychic Terrain"
    default: return nil
    }
}

func fieldRenderForAbility(_ ability: String) -> String? {
    switch ability {
    case "Drought": return "The sunlight turned harsh!"
    case "Drizzle": return "It started to rain!"
    case "Sand Stream": return "A sandstorm kicked up!"
    case "Snow Warning": return "It started to snow!"
    case "Electric Surge": return "An electric current ran across the battlefield!"
    case "Grassy Surge": return "Grass grew to cover the battlefield!"
    case "Misty Surge": return "Mist swirled around the battlefield!"
    case "Psychic Surge": return "The battlefield got weird!"
    default: return nil
    }
}

// ターン開始の交代行ブロックを、挿入するターン行の直後へ移す。
// 交代行と、その枠の付随行 (持ち物の判明・フォルム変化・メガ進化・
// 特性) だけを対象にする。ターン行以降・交代行より前に同じ側の
// ひんし行がある交代 (ひんし交代) は対象にしない。表示側は交代の
// 描画行を一緒に移す (実例: 2026-11-22 battle_20261122_091721、
// ゲンガーの交代とメガ進化がターン6の末尾に記録された)
func pullBackSwitchBlock(label: String) -> (proto: [String], display: [String]) {
    guard let turnIdx = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) else { return ([], []) }
    var switchIdx: Int? = nil
    for i in (turnIdx + 1)..<battleLog.count {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|switch|"), f.count >= 3, f[2] == label { switchIdx = i }
    }
    guard let si = switchIdx else { return ([], []) }
    let side = String(label.prefix(2))
    for i in (turnIdx + 1)..<si {
        let l = battleLog[i]
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if l.hasPrefix("|faint|"), f.count >= 3, f[2].hasPrefix(side) { return ([], []) }
    }
    var idxs = [si]
    if si + 1 < battleLog.count {
        for j in (si + 1)..<battleLog.count {
            let l = battleLog[j]
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 3, f[2] == label else { continue }
            if l.hasPrefix("|-item|") || l.hasPrefix("|detailschange|") || l.hasPrefix("|-mega|") || l.hasPrefix("|-ability|") { idxs.append(j) }
        }
    }
    let pulled = idxs.map { battleLog[$0] }
    for i in idxs.reversed() { battleLog.remove(at: i) }
    // 表示側: 交代の描画 (引き戻し行 + 繰り出し行) と石への反応・
    // メガ進化の描画行を、最後のターン見出しより後ろから集める
    let species = label.split(separator: ":").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
    var dispIdxs: [Int] = []
    var dStart = 0
    for (i, l) in displayLog.enumerated() where l.hasPrefix("Turn ") { dStart = i + 1 }
    if !species.isEmpty, dStart < displayLog.count {
        for i in dStart..<displayLog.count {
            let l = displayLog[i]
            if l == "Go! \(species)!" || l.hasSuffix("sent out \(species)!") { dispIdxs.append(i) }
            else if l.hasSuffix("is reacting to the Key Stone!") && l.contains(species) { dispIdxs.append(i) }
            else if l.contains("has Mega Evolved into") && l.contains(species) { dispIdxs.append(i) }
        }
        if let first = dispIdxs.first, first > dStart {
            let prev = displayLog[first - 1]
            if prev.hasSuffix("come back!") || prev.contains("withdrew") { dispIdxs.insert(first - 1, at: 0) }
        }
    }
    let pulledDisplay = dispIdxs.map { displayLog[$0] }
    for i in dispIdxs.reversed() { displayLog.remove(at: i) }
    return (pulled, pulledDisplay)
}

func emitLog(_ line: String) { emitLog(line, applyNow: true) }

// applyNow=false は「状態への適用は発生時点で済んでいる」行の追記専用
// (交代行の後に出す保留ランク行など。適用は applyEvent で発生時に行う)
func emitLog(_ line: String, applyNow: Bool) {
    // 勝敗が確定した後の新規行は次試合のものなので、前試合のログへ
    // 連結しないよう先に新しい試合のログを始める (最終防衛)。
    // 入口側のガード (繰り出し文・プレート・ログ画面・見せ合い) を
    // すり抜けた行もここで必ず切り分ける。実例: 2026-11-20 の
    // battle_20261120_124322 は、|win| で完結した vs Ryzz 戦に
    // 次試合 (開始検出が発火しなかった vs Foxy2905 戦) の行が
    // ヘッダーなしで追記され、2 試合が 1 ファイルに連結していた。
    // startBattleLog 内のヘッダー行は resetLogState で winLogged が
    // 落ちた後に emitLog されるため、ここで再帰はしない
    if winLogged { startBattleLog() }
    // あり得ない行のガード: 文の取得が崩れて断片が誤帰属された場合、
    // 場の実在と矛盾する特性行・技行は記録しない (証拠は残す)。
    // 実例: 2026-11-22 battle_20261122_050512 のターン3、
    // 「|-ability|p1a: Charizard|Intimidate」 (メガ後の特性ではあり得ない)
    // と「|move|p2a: Sneasler|Heat Wave」 (前ターンに倒れた種族) が出た
    if line.hasPrefix("|-ability|"), !abilityLinePlausible(line) {
        if debugMode { print("[reader] あり得ない特性行を記録しませんでした: \(line)") }
        fflush(stdout)
        debugCapture(kind: "ability_guard", key: "ability_guard:\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    if line.hasPrefix("|move|") {
        // 前の行動で倒れた個体のひんし行が、次の技行より後ろに
        // ならないよう、先に流す (実例: 2026-11-22
        // battle_20261122_050512、ウルガモスのひんし行が
        // てみだしの技行の後に置かれた)
        emitPendingFaints()
        if moveLineHardImplausible(line) {
            if debugMode { print("[reader] あり得ない技行を記録しませんでした: \(line)") }
            fflush(stdout)
            debugCapture(kind: "move_guard", key: "move_guard:\(line)", rawText: "",
                         detail: ["line": line, "turn": currentTurn])
            return
        }
        // 場にいない種族の技行は、交代の取りこぼし時の既定帰属が
        // あり得るため行は出すが、証拠だけ残す
        if moveLineOffField(line) {
            debugCapture(kind: "move_guard", key: "move_guard:\(line)", rawText: "",
                         detail: ["line": line, "turn": currentTurn, "mode": "off_field_evidence"])
        }
    }
    if line.hasPrefix("|-item|"), itemLineImplausible(line) {
        if debugMode { print("[reader] 場にいない種族の持ち物行を記録しませんでした: \(line)") }
        fflush(stdout)
        debugCapture(kind: "item_guard", key: "item_guard:\(line)", rawText: "",
                     detail: ["line": line, "turn": currentTurn])
        return
    }
    // ターン行の構造ガード: ターン判定 (コマンドフェーズ検出) が遅れて、
    // ラウンドの出来事がそのラウンドの |turn| 行より先に記録されることが
    // ある (実例: 2026-11-21 battle_20261121_140658、初回ラウンド全体が
    // |turn|1 より前に出た)。並びの保証はここで構造的に担保する。
    // (a) ターン行がまだ無いのにラウンド内の出来事が来たら、それは
    //     第 1 ラウンドの出来事なので、先に |turn|1 を出す
    // (b) 同じポケモンは 1 ラウンドに 2 回技を使えず、ダブルでは
    //     1 ラウンドの技は最大 4 件のため、最後のターン行以降に既に
    //     技を使った枠の技 (または 5 件目の技) が来たら、それは次の
    //     ラウンドの最初の出来事なので、先に次のターン行を出す
    // (c) 交代で入ったポケモンは、入ったラウンドには技を使えない。
    //     最後のターン行以降に交代で入った枠の最初の技で、かつその
    //     区間に既に他の技が記録されている場合は、次のラウンドの
    //     技なので先にターン行を出す (実例: 2026-11-21
    //     battle_20261121_153443、ひんし交代で入ったガブリアスの
    //     最初の技に |turn|4 が先行しなかった)。区間の最初の技では
    //     発火しない (交代の確定がターン行より遅れただけの場合に
    //     誤発火しないため)
    // 発火した場合は、判定側の次の発火を 1 回抑止して二重に出さない
    if logStarted && !winLogged {
        if line.hasPrefix("|turn|") {
            movesSinceTurnLine = []
            roundEventSeen = false
            enteredThisSegment = []
        } else if line.hasPrefix("|switch|") {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 3 {
                enteredThisSegment.insert(f[2].split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            }
        } else if isRoundEventLine(line) {
            let mover: String? = line.hasPrefix("|move|")
                ? line.split(separator: "|", omittingEmptySubsequences: false).map(String.init).dropFirst(2).first?.trimmingCharacters(in: .whitespaces)
                : nil
            var guardN: Int? = nil
            // (c) の条件 (この区間で交代で入った枠の最初の技) は、交代行
            // ブロックの引き戻し判定にも使うため先に確定させる
            let ruleC = mover.map { mv in
                currentTurn >= 1 && !movesSinceTurnLine.isEmpty && !movesSinceTurnLine.contains(mv)
                    && enteredThisSegment.contains(mv.split(separator: ":").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? "")
            } ?? false
            if currentTurn == 0 && !roundEventSeen { guardN = 1 }
            else if let mover, movesSinceTurnLine.contains(mover) || movesSinceTurnLine.count >= 4 { guardN = currentTurn + 1 }
            else if ruleC { guardN = currentTurn + 1 }
            if let n = guardN {
                // (c) で発火した場合、原因の交代はターン開始の交代であり、
                // その行ブロックが前のターンの末尾に出ていることがある。
                // ターン行の直後へ移す (実例: 2026-11-22
                // battle_20261122_091721、ゲンガーの交代とメガ進化)
                var pulledProto: [String] = []
                var pulledDisplay: [String] = []
                if ruleC, let mover { (pulledProto, pulledDisplay) = pullBackSwitchBlock(label: mover) }
                if debugMode { print("[reader] ターン行ガードが発火しました: |turn|\(n) を先に出します (きっかけ: \(line))") }
                fflush(stdout)
                debugCapture(kind: "turn_guard", key: "turn_guard:\(n)", rawText: "",
                             detail: ["turn": n, "line": line, "readerBuild": readerBuild,
                                      "action": "inserted_turn_line"])
                suppressNextDetectorTurn = true
                emitLog("|turn|\(n)")   // この呼び出しで追跡状態はリセットされる
                if !pulledProto.isEmpty {
                    battleLog.append(contentsOf: pulledProto)
                    displayLog.append(contentsOf: pulledDisplay)
                }
            }
            roundEventSeen = true
            if let mover { movesSinceTurnLine.insert(mover) }
        }
    }
    // 終了行 (sideend/fieldend) が開始行なしで出た場合は、開始側を
    // 取りこぼした可能性をまず疑う (2026-11-20 vs チャンピオン戦の
    // 教訓: 序盤の取り込み失敗で開始行が欠け、実在した条件の終了行
    // だけが残った)。終了行は証拠としてそのまま残す
    if applyNow {
        if line.hasPrefix("|move|") || line.hasPrefix("|turn|") { actionSeq += 1 }
        applyEvent(line)
    }
    // ひんし行の直前で、その枠の直近の被ダメ行の HP 表記が「1/202」の
    // ような 1% 未満の端数だった場合は 0 表記に直す (割合としては
    // 0% の行であり、ひんしと並ぶと表記だけが矛盾する。実例:
    // 2026-11-22 battle_20261122_054802、ガオガエンの被ダメ行が
    // 1/202 なのに ひんし行が続いた)
    if line.hasPrefix("|faint|") {
        let ff = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if ff.count >= 3 {
            let label = ff[2]
            for i in battleLog.indices.reversed() {
                let bl = battleLog[i]
                if bl.hasPrefix("|switch|") && bl.contains("|\(label)|") { break }
                if bl.hasPrefix("|-damage|\(label)|") {
                    let parts = bl.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
                    if parts.count >= 4 {
                        let hp = parts[3].split(separator: "/")
                        if hp.count == 2, let cur = Int(hp[0].trimmingCharacters(in: .whitespaces)),
                           let maxHp = Int(hp[1].trimmingCharacters(in: .whitespaces)),
                           cur > 0, maxHp > 0, Int((Double(cur) / Double(maxHp) * 100).rounded()) == 0 {
                            battleLog[i] = "|-damage|\(label)|0/\(maxHp)" + (parts.count >= 5 ? "|\(parts[4])" : "")
                        }
                    }
                    break
                }
            }
        }
    }
    // 並びの訂正: 急所行は同じ対象の ひんし行より前に、天候・地形を
    // 呼ぶ特性行は対応するフィールド行より前に置く。ゲーム内の発生
    // 順はその順だが、プレート確定や帰属が遅れると行の生成が前後
    // する (実例: 2026-11-22 battle_20261122_075240、急所行が
    // ひんし行の後ろに、天候行が ひでり の特性行より前に出た)。
    // 表示ログ側の並びは描画部で対処する
    var insertAt: Int? = nil
    if line.hasPrefix("|-crit|") {
        let cf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if cf.count >= 3 {
            let label = cf[2]
            var i = battleLog.count - 1
            while i >= 0 && battleLog.count - i <= 40 {
                let bl = battleLog[i]
                if bl.hasPrefix("|turn|") || bl.hasPrefix("|move|") || bl.hasPrefix("|switch|") { break }
                if bl == "|faint|\(label)" { insertAt = i; break }
                i -= 1
            }
        }
    } else if line.hasPrefix("|-ability|") {
        let af = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if af.count >= 4, let fieldLine = fieldLineForAbility(af[3]) {
            let label = af[2]
            var i = battleLog.count - 1
            while i >= 0 && battleLog.count - i <= 40 {
                let bl = battleLog[i]
                if bl == fieldLine { insertAt = i; break }
                if bl.hasPrefix("|turn|") { break }
                if bl.hasPrefix("|switch|") && bl.contains("|\(label)|") { break }
                i -= 1
            }
        }
    }
    if let insertAt { battleLog.insert(line, at: insertAt) } else { battleLog.append(line) }
    // 推定エンジン用イベント (技の使用順)
    if line.hasPrefix("|move|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4 && battleEvents.count < 600 {
            battleEvents.append("{\"k\":\"mv\",\"turn\":\(currentTurn),\"label\":\"\(jsonEscape(f[2]))\",\"move\":\"\(jsonEscape(f[3]))\"}")
        }
    }
    // 推定エンジン用イベント (特性の発動順): |switch| の連続区間を 1 回の同時入場
    // とみなし、その間に入場した個体が発動した特性を発動順のまま 'ab' イベント
    // として記録する。ゲーム内では同時入場時の特性は素早さ順に発動する
    // (天候の奪い合いで遅い方が勝つのもこのため) ので、素早さ推定の証拠になる。
    // ウィンドウは |turn| / |move| で閉じ、その時点で入場個体分だけを吐き出す
    // (かるわざ等の非入場発動は入場集合に無いため自動的に除外される)
    if line.hasPrefix("|switch|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3 {
            if !entryBatchOpen { entryBatchId += 1; entryBatchMembers = []; entryBatchAbBuffer = []; entryBatchOpen = true }
            entryBatchMembers.insert(f[2])
        }
    } else if line.hasPrefix("|-ability|") {
        if entryBatchOpen {
            let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if f.count >= 4 { entryBatchAbBuffer.append((label: f[2], ability: f[3])) }
        }
    }
    if (line.hasPrefix("|turn|") || line.hasPrefix("|move|")) && entryBatchOpen {
        for ab in entryBatchAbBuffer where entryBatchMembers.contains(ab.label) {
            if battleEvents.count < 600 {
                battleEvents.append("{\"k\":\"ab\",\"turn\":\(currentTurn),\"label\":\"\(jsonEscape(ab.label))\",\"ability\":\"\(jsonEscape(ab.ability))\",\"batch\":\(entryBatchId)}")
            }
        }
        entryBatchOpen = false
        entryBatchMembers = []
        entryBatchAbBuffer = []
    }
    if line.hasPrefix("|switch|") {
        let sf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if sf.count >= 4 {
            let sside = sf[2].hasPrefix("p2") ? "p2" : "p1"
            emittedSwitchKeys.insert("\(sside):\(sf[3].trimmingCharacters(in: .whitespaces))")
        }
    }
    // 自軍の繰り出しで正確な HP を初期化する (被ダメ量の算出用)
    if line.hasPrefix("|switch|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 5 && f[2].hasPrefix("p1") {
            let sp = f[2].split(separator: ":", maxSplits: 1)
            let hp = f[4].split(separator: "/")
            if sp.count == 2 && hp.count == 2, let c = Int(hp[0].trimmingCharacters(in: .whitespaces)), let m = Int(hp[1].trimmingCharacters(in: .whitespaces)) {
                lastExactHp["p1:\(sp[1].trimmingCharacters(in: .whitespaces))"] = [c, m]
            }
        }
    }
    try? (battleLog.joined(separator: "\n") + "\n").write(to: protocolLogURL, atomically: true, encoding: .utf8)
    let rendered = renderLogLine(line)
    // フィールド開始行は、直後に特性行が来たら順序を入れ替えて出す
    // (お手本: [X's Drought] → The sunlight turned harsh! の順)
    let isFieldLine = line.hasPrefix("|-fieldstart|") || (line.hasPrefix("|-weather|") && !line.contains("|none"))
    var out: [String] = []
    if isFieldLine {
        out = renderHold
        renderHold = rendered
    } else {
        if !rendered.isEmpty && rendered[0].hasPrefix("[") && !renderHold.isEmpty {
            out = rendered + renderHold
        } else {
            out = renderHold + rendered
        }
        renderHold = []
    }
    // 繰り出しブロック (行動前の繰り出し・ひんし後の交代と、それに続く
    // 特性/フィールド行) の後には空行を入れる (お手本の体裁)
    let kf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    let kind = kf.count > 1 ? kf[1] : ""
    switch kind {
    case "start", "turn":
        renderPendingBlank = false
        renderMovesSeen = false
        renderFaintPending = false
    case "switch":
        if renderPendingBlank && !out.isEmpty { out.insert("", at: 0) }
        if !renderMovesSeen || renderFaintPending { renderPendingBlank = true }
    case "-ability":
        break   // ブロックの一部
    case "faint":
        if renderPendingBlank && !out.isEmpty { out.insert("", at: 0) }
        renderPendingBlank = false
        renderFaintPending = true
    default:
        if !isFieldLine {
            if renderPendingBlank && !out.isEmpty { out.insert("", at: 0) }
            renderPendingBlank = false
            if kind == "move" { renderMovesSeen = true }
        }
    }
    // 表示ログの並び訂正 (プロトコル側の挿入と対): 急所の表示は
    // 同じ対象の ひんし表示より前に、天候・地形特性の表示は対応する
    // フィールド表示より前に割り込ませる。表示ログは逐次構築のため、
    // 既に積まれた行の前へ挿入する必要がある。ターミナルへのライブ
    // 出力は発生順のまま (過去の表示は遡れないため)
    var displayInsertAt: Int? = nil
    if out.count == 1 {
        if line.hasPrefix("|-crit|") {
            let cf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if cf.count >= 3 {
                let (_, side, species) = renderLabelParts(cf[2])
                let anchor = "\(renderPrefix(side))\(species) fainted!"
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        } else if line.hasPrefix("|-ability|") {
            let af = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            if af.count >= 4, let anchor = fieldRenderForAbility(af[3]) {
                var i = displayLog.count - 1
                while i >= 0 && displayLog.count - i <= 60 {
                    let dl = displayLog[i]
                    if dl.hasPrefix("Turn ") { break }
                    if dl == anchor { displayInsertAt = i; break }
                    i -= 1
                }
            }
        }
    }
    if let displayInsertAt {
        displayLog.insert(out[0], at: displayInsertAt)
        print(out[0])
    } else {
        for l in out {
            displayLog.append(l)
            print(l)
        }
    }
    fflush(stdout)
    try? (displayLog.joined(separator: "\n") + "\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
    // 行動が起きたらコマンド選択フェーズは終わっている (ターン数えのリセット)
    if line.hasPrefix("|move|") || line.hasPrefix("|switch|") || line.hasPrefix("|faint|") {
        commandPhaseSeen = false
    }
    // 設置・解除の保留確定: がんせきアックスとスピン系は当たって初めて
    // 効果が出るため、相手側へのダメージ行を確定の合図にする
    // (まもる・無効・外しではダメージ行が出ず、保留は次の技で失効する)
    if line.hasPrefix("|turn|") { pendingHazard = nil; pendingRemoval = nil }
    if line.hasPrefix("|-damage|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 3 {
            let dmgSide = f[2].hasPrefix("p1") ? "p1" : "p2"
            if let ph = pendingHazard, dmgSide == ph.side {
                pendingHazard = nil
                emitHazard(ph.side, ph.hazard, start: true)
            }
            if let pr = pendingRemoval, dmgSide != pr.side {
                pendingRemoval = nil
                clearSideHazards(pr.side)
            }
        }
    }
    lastLogEventAt = Date()
    // 特性判明によるフォルム訂正 (相手側のみ): プレートの種族同定は
    // 名前テキストの照合のため同名フォルムを区別できない。判明した
    // 特性が現在のフォルムでは持ち得ず、別フォルムのちょうど 1 つだけが
    // 持ち得る場合は、そちらが正しいフォルムだと確定できる
    if line.hasPrefix("|-ability|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4 {
            let lp = f[2].split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if lp.count == 2 && lp[0].hasPrefix("p2") {
                correctFormeByAbility(side: "p2", slot: lp[0], speciesEn: lp[1],
                                      abilityEn: f[3].trimmingCharacters(in: .whitespaces))
            }
        }
    }
}

func resetLogState() {
    // 見せ合い画面の保持フレームはこの試合で消費済みとして消す
    // (次の試合が選出を経ない開始でも、前の画面が付かないように)
    previewLastImage = nil
    previewLastImageAt = nil
    slotLastHitAt = [:]
    plateStaleOtherHits = [:]
    monStates = [:]
    revealedMoves = [:]
    revealedItems = [:]
    revealedAbilities = [:]
    logSeenEntries = []
    lastMsgNorm = ""
    lastMsgAt = Date.distantPast
    pendingDamagePct = [:]
    pendingDamageCount = [:]
    pendingDamageSince = [:]
    lastEmittedPct = [:]
    winLogged = false
    movesSinceTurnLine = []
    roundEventSeen = false
    suppressNextDetectorTurn = false
    enteredThisSegment = []
    defaultAttribCount = [:]
    headerOppTeam = []
    headerMismatchFired = []
    // 相手のランク/レート (画像認識側が oppRank / oppRating に入れる):
    // 見せ合いが直近 (60 秒以内) に目撃されていれば、この対戦の開始
    // 前に読み取られた値として保持する (同定が失敗して開始処理が
    // 読み取り後に走る経路で消えないように)。そうでなければ前対戦の
    // 残りなので消す (見せ合いを取り逃した対戦で前対戦のランクが
    // 記録されるのを防ぐ)。新しい見せ合い画面の出現時にも画像認識
    // 側で消去される
    if Date().timeIntervalSince(lastPreviewSeenAt) >= 60 {
        oppRank = ""
        oppRating = ""
        oppRankRecorded = false
    }
    lastMoveSigAt = [:]
    lastMoveSigSeq = [:]
    lastSingleActAt = [:]
    battleEvents = []
    entryBatchId = 0
    entryBatchOpen = false
    entryBatchMembers = []
    entryBatchAbBuffer = []
    lastExactHp = [:]
    lastDmgEventPrevExact = [:]
    lastMoveName = ""
    lastMoveSeq = -1
    lastMoveLabel = ""
    lastMoveMsgAt = Date.distantPast
    lastFallbackText = ""
    lastFallbackAt = Date.distantPast
    fieldWeatherSetAt = Date.distantPast
    fieldTerrainSetAt = Date.distantPast
    lastSwitchIn = [:]
    fieldSeen = ["p1": [], "p2": []]
    fieldAbilityDone = [:]
    intimidateDone = [:]
    lastBoostApply = [:]
    boostPathAt = [:]
    lastEffectAt = [:]
    pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]
    lastDamageSeq = [:]; lastDamageTurn = [:]; lastDamageDir = [:]; lastDamageTime = [:]; lastCritAt = [:]; actionSeq = 0
    suspectJump = [:]; firstEntryPlateHP = [:]; sitrusWatch = [:]; lastMoveEmitSeq = -1; lastSwitchEmitSeq = -1
    fieldSetByMoveTurn = -1; switchInTurn = [:]
    heldWeatherStart = nil; heldTerrainStart = nil; fieldHoldBypass = false
    heldTerrainReplace = nil; pivotReturnAt = [:]
    wishSetTurn = [:]
    heldLine = [:]; pendingFaints = []; faintedSlots = [:]; grassyHealTurn = [:]; lastSideCondAt = [:]
    faintedSpecies = []; heldEntryBoosts = []
    battleHazards = [:]; pendingHazard = nil; pendingRemoval = nil
    debugShotsThisBattle = 0; debugRoutineShots = 0; debugEventShots = 0; debugSeenEntries = []; debugFrameRing = []
    displayLog = []; renderSlotSpecies = [:]; renderFainted = []; renderLastPct = [:]
    renderPokeP1 = []; renderPokeP2 = []; renderWeatherProto = ""; forfeitName = nil
    renderHold = []
    renderPendingBlank = false
    renderMovesSeen = false
    renderFaintPending = false
    renderBerryAt = [:]
    lastAbilityEmit = [:]
    lastItemEmit = [:]
    turnRawFrames = 0
    pendingStatusFrom = [:]
    pendingMegaStone = [:]
    pendingMegaSpecies = [:]
    emittedSwitchKeys = []
    pendingUnburden = []
    unburdenActive = []
    itemLostActive = []
    heldBoostLines = [:]
    recentAtkDrops = [:]
    lastDamageLabel = ""
    lastDamageAt = Date.distantPast
    lastPendingLabel = ""
    commandPhaseSeen = false
    currentTurn = 0
    logFieldTerrain = ""
    logTrickRoom = false
    logFieldWeather = ""
    fieldWeatherSetTurn = 0
    fieldTerrainSetTurn = 0
    prevFieldWeather = ""; prevFieldWeatherSetTurn = 0
    prevFieldTerrain = ""; prevFieldTerrainSetTurn = 0
    fieldTrickRoomSetTurn = 0
    sideCondSetTurns = [:]
    eventSlotSpecies = [:]
    logStarted = false
    lastSlots = [:]
    firstSlotConfirmedAt = nil
    headerWeatherPending = (ui: "", logName: "", count: 0, lastAt: Date.distantPast)
}

// MARK: - 試合ごとのログアーカイブ (自動送信の下準備)
// battle.log / battle_protocol.log は常に「現在の試合」だけを保持し、
// 次の試合が始まると上書きされる。試合ごとに logs/ へ複写して残し、
// serve.py が暗号化して送信する (送信済み管理も serve.py 側)。
// 保存タイミングは 3 つ:
//  1. 勝敗が確定したとき (final)
//  2. 次の試合の startBattleLog で前試合が未保存だったとき (interrupted)
//  3. reader 起動時、前回セッションの残留ログがあったとき (interrupted)
//     — タスクキル・電池切れ・クラッシュで強制中断された試合の救済。
//     battle.log は emitLog のたびに全行書き直されるため、中断時点までの
//     内容はディスクに残っている
var battleArchiveId = ""        // 現在の試合のアーカイブ名 (開始時刻ベース)
var battleArchived = false      // 現在の試合を logs/ へ保存済みか
var lastArchiveSnapshotCount = -1  // 安全網の下書き保存をした時点の battleLog 行数
let logsDirURL = scriptDir.appendingPathComponent("logs")

func battleStamp(for date: Date = Date()) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.dateFormat = "yyyyMMdd_HHmmss"
    return f.string(from: date)
}

// |-item| 行の不可能性: 持ち主がその枠の occupants と同種族
// ファミリーでなく、相方枠の occupants でも交代確定待ちでもない
// 場合は、種族名の誤読が持ち物の再掲経路から入ったものとして弾く
// (実例: 2026-11-22 battle_20261122_051707、リザードンの名前が
//  リザードに崩れ、Charmeleon の持ち物行が出た)。枠の occupants が
// 未確定なら通す
func itemLineImplausible(_ line: String) -> Bool {
    let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    guard f.count >= 3, let ss = parseSlotSpecies(f[2]) else { return false }
    let prefix = ss.side == "p1" ? "mine" : "opp"
    let plate = prefix + (ss.slot.hasSuffix("a") ? "A" : "B")
    guard let occ = lastSlots[plate]?.speciesEn ?? eventSlotSpecies[ss.slot] else { return false }
    if sameSpeciesFamily(occ, ss.speciesEn) { return false }
    if occ.hasPrefix("Ditto") { return false }
    if pendingSwitchSpecies[plate] == ss.speciesEn { return false }
    let sib = prefix + (ss.slot.hasSuffix("a") ? "B" : "A")
    if let sibOcc = lastSlots[sib]?.speciesEn, sameSpeciesFamily(sibOcc, ss.speciesEn) { return false }
    return true
}

// アーカイブ時のヘッダー補完: 見せ合いが取得できなかった試合
// (late_start) では、ヘッダーの |poke| が先発の 2 体だけで、途中から
// 出た種族の宣言が無いままになる (実例: 2026-11-22
// battle_20261122_050512、Salamence / Rillaboom の宣言が無かった)。
// 交代行に実際に現れた種族は対戦にいたことが確定しているため、
// 保存時に限り、現れた順で宣言へ補う (ライブの状態には触れない)
func completeArchiveHeader(protocolLines: [String], displayLines: [String]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {
    var proto = protocolLines
    var added: [String] = []
    var removed: [String] = []
    for side in ["p1", "p2"] {
        var declared: [String] = []
        var lastPokeIdx: Int? = nil
        for (i, l) in proto.enumerated() {
            if l.hasPrefix("|poke|\(side)|") {
                declared.append(String(l.dropFirst("|poke|\(side)|".count)))
                lastPokeIdx = i
            }
            if l == "|start" { break }
        }
        var appeared: [String] = []
        for l in proto {
            guard l.hasPrefix("|switch|") || l.hasPrefix("|drag|") else { continue }
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 4, let ss = parseSlotSpecies(f[2]), ss.side == side else { continue }
            if !appeared.contains(f[3]) { appeared.append(f[3]) }
        }
        let missing = appeared.filter { a in !declared.contains { sameSpeciesFamily($0, a) } }
        if missing.isEmpty { continue }
        // 補完で 6 体を超える場合は、実際には登場しなかった宣言側の
        // 種族 (見せ合い同定の誤り) と入れ替える。チームが 7 体に
        // なるヘッダーはあり得ない (実例: 2026-11-22
        // battle_20261122_071457、誤同定の枠が残ったまま実登場した
        // サーフゴーが 7 体目に追記された)
        if declared.count + missing.count > 6 {
            let unused = declared.filter { d in !appeared.contains { sameSpeciesFamily($0, d) } }
            let removeCount = min(unused.count, declared.count + missing.count - 6)
            if removeCount > 0 {
                let removing = Array(unused.suffix(removeCount))
                let removeSet = Set(removing)
                proto = proto.filter { line in
                    guard line.hasPrefix("|poke|\(side)|") else { return true }
                    return !removeSet.contains(String(line.dropFirst("|poke|\(side)|".count)))
                }
                removed += removing.map { "\(side):\($0)" }
                lastPokeIdx = nil
                for (i, l) in proto.enumerated() {
                    if l.hasPrefix("|poke|\(side)|") { lastPokeIdx = i }
                    if l == "|start" { break }
                }
            }
        }
        let insertAt = lastPokeIdx.map { $0 + 1 } ?? (proto.firstIndex(of: "|start") ?? proto.count)
        proto.insert(contentsOf: missing.map { "|poke|\(side)|\($0)" }, at: insertAt)
        added += missing.map { "\(side):\($0)" }
    }
    // 自軍の交代行の HP 表記を実数へ統一する: 開幕の交代行が % 表記
    // (100/100) で出た枠も、後の被ダメ行などで実数の最大値が判明
    // していれば、その表記 (最大値/最大値) に揃える。実数表記の枠と
    // 混在すると、同じ開幕の交代行で表記が割れる (実例: 2026-11-22
    // battle_20261122_091721、ニョロトノは 167/167、ブリジュラスは
    // 100/100 で出た)
    var realMax: [String: Int] = [:]
    for l in proto {
        let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 2 else { continue }
        // HP 表記の位置は行種で異なる (交代行は種族名の次、被ダメ・
        // 回復行はラベルの次)
        let hpIdx = f[1] == "switch" ? 4 : (f[1] == "-damage" || f[1] == "-heal" ? 3 : -1)
        guard hpIdx >= 0, f.count > hpIdx else { continue }
        let hpParts = f[hpIdx].split(separator: " ")
        guard let first = hpParts.first else { continue }
        let curMax = first.split(separator: "/")
        if curMax.count == 2, let mx = Int(curMax[1]), mx != 100 {
            realMax[f[2]] = max(realMax[f[2]] ?? 0, mx)
        }
    }
    if !realMax.isEmpty {
        proto = proto.map { l in
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, f[1] == "switch", f[4] == "100/100", let mx = realMax[f[2]] else { return l }
            var g = f
            g[4] = "\(mx)/\(mx)"
            return g.joined(separator: "|")
        }
    }
    var disp = displayLines
    if !added.isEmpty {
        // 表示側: チーム見出し行 (2 つあるうち 1 つ目が自軍、2 つ目が相手)
        // の次の行が種族の一覧行。補った種族を側ごとに追記する
        var teamLineIdxs: [Int] = []
        for (i, l) in disp.enumerated() where l == "Your team:" || l.hasSuffix("'s team:") { teamLineIdxs.append(i) }
        for (n, side) in ["p1", "p2"].enumerated() {
            let sideAdded = added.filter { $0.hasPrefix("\(side):") }.map { String($0.dropFirst(3)) }
            guard !sideAdded.isEmpty, teamLineIdxs.count > n else { continue }
            let namesIdx = teamLineIdxs[n] + 1
            guard namesIdx < disp.count else { continue }
            let existing = disp[namesIdx].isEmpty ? [] : disp[namesIdx].components(separatedBy: " / ")
            let sideRemoved = removed.filter { $0.hasPrefix("\(side):") }.map { String($0.dropFirst(3)) }
            let kept = existing.filter { e in !sideRemoved.contains { sameSpeciesFamily($0, e) } }
            let extra = sideAdded.filter { a in !kept.contains { sameSpeciesFamily($0, a) } }
            if !extra.isEmpty || kept.count != existing.count { disp[namesIdx] = (kept + extra).joined(separator: " / ") }
        }
    }
    return (proto, disp, added, removed)
}

func archiveBattleLogs(final: Bool, protocolLines: [String], displayLines: [String], id: String) {
    guard protocolLines.contains("|start") else { return }
    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines)
    if !completed.added.isEmpty {
        print("[log] ヘッダーに宣言の無かった種族を補いました: \(completed.added.joined(separator: ", "))")
        fflush(stdout)
    }
    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
    let base = "battle_\(id)_\(final ? "final" : "interrupted")"
    let protoText = completed.protocolLines.joined(separator: "\n") + "\n"
    let dispText = completed.displayLines.joined(separator: "\n") + "\n"
    try? protoText.write(to: logsDirURL.appendingPathComponent(base + "_protocol.log"), atomically: true, encoding: .utf8)
    try? dispText.write(to: logsDirURL.appendingPathComponent(base + ".log"), atomically: true, encoding: .utf8)
    print("[log] 試合ログを保存しました: logs/\(base).log / logs/\(base)_protocol.log")
    fflush(stdout)
}

// 現在進行中の試合を logs/ へ保存する (勝敗確定時は final: true)
func archiveCurrentBattle(final: Bool) {
    guard logStarted, !battleArchived, !battleLog.isEmpty else { return }
    let id = battleArchiveId.isEmpty ? battleStamp() : battleArchiveId
    archiveBattleLogs(final: final, protocolLines: battleLog, displayLines: displayLog, id: id)
    battleArchived = true
    if final {
        // 安全網の下書き (interrupted) が残っていれば取り除く (確定版が正)
        for suffix in ["_interrupted.log", "_interrupted_protocol.log"] {
            try? FileManager.default.removeItem(at: logsDirURL.appendingPathComponent("battle_\(id)\(suffix)"))
        }
    }
}

// MARK: - デバッグ用スクリーンショット (2026-11-20、ユーザーの指示)
// 翻訳に落ちて |-message| になった平文の初出時と、リーダーが内部の矛盾を
// 検出した箇所で、直近フレームの画面全体を
// JPEG で logs/ に保存し、イベントごとの JSON を添える。serve.py が試合
// ログと同じ暗号化の便で logs_enc/ へ送り、ログ分析側がログ2点と突き合わ
// せる。ファイル名は battle_<試合ID>_debugNN.jpg/.json で、ログファイルと
// battle_<日時> の接頭辞を共有する。同一文・同一箇所の繰り返しは
// 1 件にまとめる (類似文の集約は再読対策として直近 30 秒のみ)。
// 上限はクラス別: preview_id は毎試合保証のため対象外、ターン判定の
// 定常記録 (turn_decided / turn_guard) は合計 6 件、それ以外の
// イベント記録は 12 件 (全体の安全上限 19 件)。従来の一律 10 件では
// 定常記録とイベント記録が枠を取り合い、長引いた試合の終盤で証拠が
// 残らなかった (実例: 2026-11-21 battle_20261121_155801、ターン 9 で
// 上限に達しターン 10 以降の異常を切り分けられなかった)。
// Mac ローカルの保持は 14 日。
let debugRoutineMaxPerBattle = 6
let debugEventMaxPerBattle = 12
let debugTotalMaxPerBattle = 19
let debugRingSize = 4   // 参照されるのは最新フレームだけのため、全画面で保持してもメモリを抑える
let debugRetentionDays = 14
var debugShotsThisBattle = 0
var debugRoutineShots = 0
var debugEventShots = 0
var debugSeenEntries: [(key: String, at: Date)] = []
var debugFrameRing: [(at: Date, img: CGImage)] = []

// 撮影可否の判定 (純粋関数: ハーネスの T84 で検証する)。
// 上限到達なら撮らない。完全一致のキーは試合中ずっと 1 件にまとめる。
// 類似キーの集約は「直近 30 秒以内」だけに限る: OCR の再読は同じ文が
// 表示されている数秒の間に起きるが、主語などの定型部分を共有する
// 別イベントの文 (例: 身代わりの出現と身代わりへの被弾) は類似度が
// 高くても別の出来事なので、時間を空けて現れたら撮り直す
// (2026-11-21 の battle_20261121_132153 で実際に撮りこぼした)
func debugShouldCapture(seen: [(key: String, at: Date)], count: Int, key: String, cap: Int, now: Date) -> Bool {
    if count >= cap { return false }
    for e in seen {
        if e.key == key { return false }
        if now.timeIntervalSince(e.at) <= 30 && textSimilarity(e.key, key) >= 0.6 { return false }
    }
    return true
}

func debugStateExcerpt() -> [String: Any] {
    var slots: [String: Any] = [:]
    // HP はプレートの最新観測値ではなく、ログに確定した値を優先する。
    // 観測値には却下された誤読 (満タンの跳ね等) が混ざっており、その
    // まま写すと記録の state がログと食い違う (実例: 2026-11-21
    // battle_20261121_145658 の hp_jump_rejected 記録)
    for (k, s) in lastSlots { slots[k] = ["species": s.speciesEn, "hpPct": lastEmittedPct[k] ?? s.hpPercent] }
    return ["turn": currentTurn, "weather": logFieldWeather, "terrain": logFieldTerrain, "slots": slots]
}

// デバッグ画像は画面全体を保存する (2026-11-21、ユーザーの指示)。
// 以前はメッセージ表示欄 (画面下部) の切り抜きだったが、切り抜きの
// 座標・向きの不具合が続いたこと (実例: 2026-11-21
// battle_20261121_132153 の debug01/02 は画面上部の帯が上下反転した
// 画像で、メッセージ欄が一切写っていなかった) と、全体があれば
// プレートやフィールドの状態まで裏付けに使えるため、全画面に統一した

// 直近フレームをリングバッファに保持する (内部矛盾の検出は
// メッセージ処理と別の経路で起きるため、その時点の画面を後から使えるように)
func debugUpdateRing(_ image: CGImage) {
    guard logStarted else { return }
    debugFrameRing.append((at: Date(), img: image))
    if debugFrameRing.count > debugRingSize { debugFrameRing.removeFirst(debugFrameRing.count - debugRingSize) }
}

// デバッグ記録のクラス: 0 = 上限対象外 (preview_id)、
// 1 = 定常系 (ターン判定)、2 = イベント系 (その他)
func debugKindClass(_ kind: String) -> Int {
    if kind == "preview_id" { return 0 }
    if kind == "turn_decided" || kind == "turn_guard" { return 1 }
    return 2
}

func debugCapture(kind: String, key: String, rawText: String, detail: [String: Any], image: CGImage? = nil) {
    let cls = debugKindClass(kind)
    if cls == 1 && debugRoutineShots >= debugRoutineMaxPerBattle { return }
    if cls == 2 && debugEventShots >= debugEventMaxPerBattle { return }
    guard debugShouldCapture(seen: debugSeenEntries, count: debugShotsThisBattle, key: key, cap: debugTotalMaxPerBattle, now: Date()) else { return }
    debugSeenEntries.append((key: key, at: Date()))
    debugShotsThisBattle += 1
    if cls == 1 { debugRoutineShots += 1 }
    if cls == 2 { debugEventShots += 1 }
    let seq = debugShotsThisBattle
    let id = battleArchiveId.isEmpty ? battleStamp() : battleArchiveId
    let base = String(format: "battle_%@_debug%02d", id, seq)
    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
    var shot: CGImage? = nil
    if let image { shot = image }
    if shot == nil { shot = debugFrameRing.last?.img }
    var imageFile: String? = nil
    // 画像は画面全体。解像度は証拠の読み取りに必要なため落とさず、
    // 配信経路 (暗号化して GitHub 経由) のサイズは JPEG 品質で抑える
    if let shot, let data = NSBitmapImageRep(cgImage: shot).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
        let url = logsDirURL.appendingPathComponent(base + ".jpg")
        if (try? data.write(to: url)) != nil { imageFile = base + ".jpg" }
    }
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.formatOptions = [.withInternetDateTime]
    var ev: [String: Any] = ["battle": id, "seq": seq, "kind": kind, "at": f.string(from: Date()),
                             "turn": currentTurn, "rawText": rawText, "readerBuild": readerBuild,
                             "state": debugStateExcerpt(), "detail": detail]
    if let imageFile { ev["image"] = imageFile }
    if let data = try? JSONSerialization.data(withJSONObject: ev, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)
    }
    if debugMode { print("[debug] デバッグ情報を保存しました: logs/\(base) (\(kind))") }
    fflush(stdout)
}

// ターン判定の証拠を残す (2026-11-21、ログ分析チャットからの指示)。
// ターン番号のずれ (ターン行の欠落や遅れ) は序盤に集中して起きており、
// 対象は序盤のターン (1〜3) と、生フレーム連続のフォールバック経路で
// 確定したターンに絞る (1 試合 10 件のデバッグ上限を圧迫しないため)。
// 経路は plates_settled (プレート確定による即時) / raw_frames
// (フォールバック) / log_screen (ゲーム内ログ画面経由) のいずれか
func recordTurnEvidence(turn: Int, path: String, image: CGImage, extra: [String: Any] = [:]) {
    guard turn <= 3 || path == "raw_frames" else { return }
    var slots: [String: Any] = [:]
    for name in ["mineA", "mineB", "oppA", "oppB"] {
        if let s = lastSlots[name] {
            slots[name] = ["species": s.speciesEn, "hp": s.hpPercent] as [String: Any]
        } else {
            slots[name] = ["species": "", "hp": -1] as [String: Any]
        }
    }
    var detail: [String: Any] = ["turn": turn, "path": path, "slots": slots, "readerBuild": readerBuild]
    for (k, v) in extra { detail[k] = v }
    debugCapture(kind: "turn_decided", key: "turn_decided:\(turn):\(path)", rawText: "", detail: detail, image: image)
}

// 起動時: 保持期間 (14 日) を過ぎたローカルのデバッグ情報を掃除する
func cleanupOldDebugShots() {
    guard let names = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) else { return }
    let cutoff = Date().addingTimeInterval(-Double(debugRetentionDays) * 86400)
    for name in names where name.contains("_debug") {
        let url = logsDirURL.appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date, mtime < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }
}

// 起動時: 前回セッションの残留ログが未保存の試合なら救済する
func salvageLeftoverLogs() {
    guard let proto = try? String(contentsOf: protocolLogURL, encoding: .utf8) else { return }
    let lines = proto.split(separator: "\n").map(String.init)
    guard lines.count >= 5, lines.contains("|start") else { return }
    // 同じ内容が保存済みなら二重に作らない
    if let names = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) {
        for name in names where name.hasSuffix("_protocol.log") {
            if let saved = try? String(contentsOf: logsDirURL.appendingPathComponent(name), encoding: .utf8), saved == proto {
                return
            }
        }
    }
    var stamp = battleStamp()
    if let attrs = try? FileManager.default.attributesOfItem(atPath: protocolLogURL.path),
       let mtime = attrs[.modificationDate] as? Date {
        stamp = battleStamp(for: mtime)
    }
    // 元の試合 ID が残留 state.json から復元できれば、そちらを優先する。
    // デバッグ一式 (preview_id を含む) は元の試合 ID で保存されている
    // ため、更新日時のスタンプで救済すると serve.py 側で同じ試合として
    // 束ねられず、一式が備考ゲートに残り続けて届かなくなる
    if let raw = try? String(contentsOf: outURL, encoding: .utf8),
       let data = raw.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let bid = obj["battle"] as? String,
       bid.count == 15, bid.allSatisfy({ $0.isNumber || $0 == "_" }) {
        stamp = bid
    }
    let disp = (try? String(contentsOf: battleLogURL, encoding: .utf8)) ?? ""
    let dispLines = disp.isEmpty ? [] : disp.split(separator: "\n").map(String.init)
    archiveBattleLogs(final: lines.contains(where: { $0.hasPrefix("|win|") }),
                      protocolLines: lines, displayLines: dispLines, id: stamp + "_salvage")
}

func startBattleLog() {
    // 前の試合が未保存のまま新しい試合が始まる場合は、先に前試合を残す
    if logStarted && !battleArchived && !battleLog.isEmpty {
        archiveCurrentBattle(final: winLogged)
    }
    resetLogState()
    battleArchiveId = battleStamp()
    adoptStateSnapshotsForBattle()
    battleArchived = false
    lastArchiveSnapshotCount = -1
    battleLog = []
    emitLog("|gametype|doubles")
    for sp in teamOrder { emitLog("|poke|p1|\(sp)") }
    for sp in oppTeamSeen { emitLog("|poke|p2|\(sp)") }
    // ヘッダーに書いた6体を開始時点のまま控える (oppTeamSeen は対戦中
    // に判明した種族で増えていくため、食い違いの照合にはこちらを使う)
    headerOppTeam = oppTeamSeen
    emitLog("|start")
    logStarted = true
}

func slotId(_ plateName: String) -> String {
    switch plateName {
    case "mineA": return "p1a"
    case "mineB": return "p1b"
    case "oppA": return "p2a"
    case "oppB": return "p2b"
    default: return plateName
    }
}

func hpTextFor(_ s: SlotState) -> String {
    if let c = s.hpCur, let m = s.hpMax { return "\(c)/\(m)" }
    return "\(s.hpPercent)/100"
}

// 持ち物を消費・喪失したとき、特性が かるわざ なら発動として記録する。
// かるわざはゲーム内に発動表示が無い (とくぼう上昇などの結果だけが出る)
// ため、消費の事実から推定するしかない。自軍はチーム登録の特性で確定
// でき、相手は特性が判明済みのときだけ記録する (推測では記録しない)
func noteItemLost(slot: String, side: String, speciesEn: String) {
    // 消費・喪失の状態反映は applyEvent (|-enditem|) が行う。この行自体は
    // 画面に表示される出来事ではないため、ログには残さず直接適用する
    applyEvent("|-enditem|\(slot): \(speciesEn)")
    let abilityJa = side == "p1" ? (teamEntries[speciesEn]?["ability"] as? String) : revealedAbilities[speciesEn]
    guard abilityJa == "かるわざ" else { return }
    emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Unburden")
}

// 回復の発生源の推定 (プレート回復行に [from] を付けるため)。
// - オボンのみ: HP が 50% 以下から約 25% 回復 (きのみは被弾直後に発動する)
// - たべのこし / グラッシーフィールド: ターン終了時に約 1/16 (6%) 回復。
//   グラッシーが出ているターンは、そのターンの 1 回目の 6% 回復を
//   フィールド側に、2 回目を たべのこし に帰属する
// 判明済みの持ち物・特性と矛盾する場合は帰属しない (あめうけざら/
// アイスボディの 1/16 回復を たべのこし と誤認しないため)
func healSource(plateName: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) -> (label: String, itemJa: String?)? {
    let delta = toPct - fromPct
    guard delta > 0 else { return nil }
    // 自軍データ (teamEntries) は種族キーなので、相手側の同種族に
    // 引きずられないよう p1 の枠のときだけ参照する (実例: 2026-11-20
    // vs チェイス戦、相手エルフーンのオボン回復が、自軍エルフーンの
    // バビリのみ所持に引っ張られて [from] 無しになった)
    let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
        : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
    // 自分が直前に使った吸収技による回復は、持ち物の回復より優先して
    // 技へ帰属させる (実例: 2026-11-22 battle_20261122_091721、
    // ドレインキッスの吸収回復が、消費済みの オボンのみ の再発動に化けた)
    let drainMoves: Set<String> = ["Absorb", "Mega Drain", "Giga Drain", "Drain Punch", "Leech Life",
                                   "Horn Leech", "Oblivion Wing", "Parabolic Charge", "Draining Kiss",
                                   "Dream Eater", "Bitter Blade", "Matcha Gotcha", "Strength Sap"]
    let mySlot = slotFor(side: key.hasPrefix("p2") ? "p2" : "p1", speciesEn: speciesEn)
    if lastMoveLabel == "\(mySlot): \(speciesEn)", drainMoves.contains(lastMoveName),
       Date().timeIntervalSince(lastMoveMsgAt) < 20 {
        return ("move: \(lastMoveName)", nil)
    }
    // 消費済みの持ち物は二度と発動しない
    if fromPct <= 50 && (12...30).contains(delta) && !itemLostActive.contains(key) {
        // 持ち物がオボンのみと判明している場合は、プレート読みの
        // ぶれ (実例: 2026-11-22 battle_20261122_050512、回復量が
        // +16% と読まれた) を許容して幅を広げる。未判明の場合は
        // 従来どおり +25% 前後の狭い幅でだけ推定する
        if knownItem == "オボンのみ" { return ("item: Sitrus Berry", "オボンのみ") }
        if knownItem == nil && delta >= 20 { return ("item: Sitrus Berry", "オボンのみ") }
        if delta >= 20 { return nil }
    }
    if (3...8).contains(delta) {
        let abilityJa = key.hasPrefix("p2") ? revealedAbilities[speciesEn]
            : ((teamEntries[speciesEn]?["ability"] as? String) ?? revealedAbilities[speciesEn])
        if abilityJa == "あめうけざら" || abilityJa == "アイスボディ" { return nil }
        if logFieldTerrain == "Grassy" && grassyHealTurn[plateName] != currentTurn {
            grassyHealTurn[plateName] = currentTurn
            return ("Grassy Terrain", nil)
        }
        if knownItem == nil || knownItem == "たべのこし" { return ("item: Leftovers", "たべのこし") }
        return nil
    }
    return nil
}

// プレート経路の回復に、発生源として説明が付くか (healSource で
// 推定できない分を補う)。自分または相方の直前の技が回復系の場合、
// 判明持ち物が回復系の場合、フィラのみ系のパターンと判明持ち物が
// 矛盾しない場合、天候や状態と噛み合う回復特性が判明している場合は
// 説明ありとする
func healExplained(key: String, slot: String, speciesEn: String, fromPct: Int, toPct: Int,
                   knownItem: String?, abilityJa: String?) -> Bool {
    let delta = toPct - fromPct
    let selfHeal: Set<String> = ["Recover", "Soft-Boiled", "Milk Drink", "Slack Off", "Heal Order",
                                 "Roost", "Synthesis", "Morning Sun", "Moonlight", "Shore Up", "Rest",
                                 "Wish", "Strength Sap", "Life Dew", "Lunar Blessing", "Jungle Healing",
                                 "Absorb", "Mega Drain", "Giga Drain", "Drain Punch", "Leech Life",
                                 "Horn Leech", "Oblivion Wing", "Parabolic Charge", "Draining Kiss",
                                 "Dream Eater", "Bitter Blade", "Matcha Gotcha"]
    let allyHeal: Set<String> = ["Life Dew", "Heal Pulse", "Floral Healing", "Pollen Puff",
                                 "Lunar Blessing", "Jungle Healing"]
    let label = "\(slot): \(speciesEn)"
    if lastMoveLabel == label && selfHeal.contains(lastMoveName) { return true }
    if allyHeal.contains(lastMoveName) && lastMoveLabel != label
        && lastMoveLabel.hasPrefix(String(slot.prefix(2))) { return true }
    if knownItem == "たべのこし" || knownItem == "くろいヘドロ" { return true }
    let figyBerries: Set<String> = ["フィラのみ", "ウイのみ", "マゴのみ", "バンジのみ", "イアのみ"]
    if fromPct <= 34 && (30...36).contains(delta)
        && (knownItem == nil || figyBerries.contains(knownItem ?? "")) { return true }
    if abilityJa == "あめうけざら" && logFieldWeather == "Rain" { return true }
    if abilityJa == "アイスボディ" && logFieldWeather == "Snow" { return true }
    if abilityJa == "どくしゅ" {
        let st = monStates[key]?.status ?? ""
        if st == "psn" || st == "tox" { return true }
    }
    // ねがいごと: 使った次のターンの終わりに、使用側の場のポケモンが
    // 50% 回復する。受け手は使用者とは限らない (交代先の枠が受ける)
    // ため、直前の技ではなく使用ターンと側で判定する
    if (40...55).contains(delta), let wt = wishSetTurn[key.hasPrefix("p2") ? "p2" : "p1"],
       wt == currentTurn - 1 { return true }
    // 吸収特性: 相手の技を受けて回復する (みずをすいこむ等は 25%)。
    // 直前の技が相手側のもので、増分が吸収量と一致する場合のみ
    let absorb: Set<String> = ["みずをすいこむ", "ちくでん", "どしょく", "かんそうはだ"]
    if let abilityJa, absorb.contains(abilityJa), (20...30).contains(delta),
       !lastMoveLabel.isEmpty, !lastMoveLabel.hasPrefix(key.hasPrefix("p2") ? "p2" : "p1") { return true }
    // かんそうはだは雨のターン終了時にも 1/8 回復する
    if abilityJa == "かんそうはだ" && logFieldWeather == "Rain" && (9...16).contains(delta) { return true }
    return false
}

// ダメージ/回復行を 1 件出す (確定待ちの消化と新規確定の両方から呼ばれる)
@discardableResult
func emitDamageLine(plateName: String, slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String, force: Bool = false) -> Bool {
    // 行動内のダメージ/回復行は、HP バーの段階アニメーションの途中値と
    // 区別がつかないため、原則として保留し、次の文の翻訳時かターン境界の
    // flushPendingDamage で「最終値への 1 行」にまとめて出す
    // (実例: 2026-11-20 vs Zycloud 戦、スロートチョップ 1 発が 13% と
    //  60% の 2 行に割れた。また一時的な誤読で下がって元に戻った値は、
    //  確定待ちが自然に消えるため行自体が出ない)。
    // 例外: 0% (ひんし) は即時。方向が反転した行 (被弾直後の きのみ回復等)
    // は途中値ではあり得ないため、保留分を先に確定させてから即時に出す。
    // ターン境界では |turn| の前に flush されるため、ターン終了時の回復が
    // 次のターンにずれることもない (2026-11-20 vs Mark 戦の教訓)
    // 向きは「最後に出力した値」ではなく「保留中の値」を基準に判定する
    // (100 →保留→ 40 → 65 は、出力済みの 100 から見れば減少でも、
    //  実際の HP の動きとしては 40 からの回復 = 反転であるため)
    // 初登場フラグは、異なる値の読みが来たら失効する (同値の重複
    // ダメージ行の抑止は、交代行の直後の一致だけが対象)
    if let fe = firstEntryPlateHP[plateName], fe != hpText { firstEntryPlateHP[plateName] = nil }
    // オボンのみの発動監視の解消: 条件を跨いだ低下の後に回復が
    // 記録されれば通常どおり発動が取れたことになる。回復が無いまま
    // 次の被弾 (または ひんし) に進んだ場合は、発動イベント
    // (回復+持ち物判明) が丸ごと取り込まれていない疑いとして、
    // 証拠だけを残す (行の合成はしない。実例: 2026-11-21
    // battle_20261121_233243、リキキリンが 52% から 7% に落ちた
    // 場面で発動したはずのオボンのみの回復行・持ち物行が無かった)
    if let watched = sitrusWatch[key] {
        if toPct > watched {
            sitrusWatch[key] = nil
        } else if toPct < watched {
            debugCapture(kind: "berry_activation_suspect", key: "berry_activation_suspect|\(key)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "droppedToPct": watched, "toPct": toPct, "turn": currentTurn])
            if debugMode { print("[reader] オボンのみの発動条件を跨いだ後に回復が記録されないまま HP が動きました (発動の取りこぼしの疑い): \(slot): \(speciesEn) \(watched)% -> \(toPct)%") }
            fflush(stdout)
            sitrusWatch[key] = nil
        }
    }
    var effFrom = fromPct
    var dirBase = fromPct
    if let h = heldLine[plateName], h.seq == actionSeq, h.turn == currentTurn { dirBase = h.toPct }
    let dir = toPct < dirBase ? -1 : 1
    if !force && toPct != 0 {
        if let h = heldLine[plateName], h.seq == actionSeq && h.turn == currentTurn, h.dir != dir {
            // 反転先が「保留行を出す前の確定値」と完全一致する場合は、
            // 実ダメージ+回復ではなく一時的な誤読が元に戻っただけと
            // みなし、保留行ごと捨てる (実例: 2026-11-20 vs チェイス戦、
            // ターン頭のサーナイトに被弾行と全回復行のペアが出た)
            if toPct == (lastEmittedPct[plateName] ?? fromPct) {
                debugCapture(kind: "hp_reversal_drop", key: "hp_reversal_drop|\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "heldToPct": h.toPct,
                                      "reversedToPct": toPct, "lastEmittedPct": lastEmittedPct[plateName] ?? fromPct])
                heldLine[plateName] = nil
                return true
            }
            heldLine[plateName] = nil
            _ = emitDamageLine(plateName: plateName, slot: slot, key: key, speciesEn: speciesEn,
                               fromPct: lastEmittedPct[plateName] ?? fromPct, toPct: h.toPct,
                               hpText: h.hpText, force: true)
            effFrom = h.toPct
        } else {
            heldLine[plateName] = (toPct: toPct, dir: dir, seq: actionSeq, turn: currentTurn, hpText: hpText)
            return false
        }
    }
    // 段階アニメーションの尾: 同じ行動・同じターンで、直前の出力行と
    // 同じ向き・わずかな差 (3% 以下) の続きは、行を出さず値だけ取り込む
    // (実例: 2026-11-20、グラススライドの被弾が 79% と 2% に割れた)
    if toPct != 0, let lp = lastEmittedPct[plateName],
       lastDamageSeq[plateName] == actionSeq, lastDamageTurn[plateName] == currentTurn,
       lastDamageDir[plateName] == dir, toPct != lp, abs(toPct - lp) <= 3 {
        heldLine[plateName] = nil
        lastEmittedPct[plateName] = toPct
        return true
    }
    // 回復行なのに HP 表記の現在値が 0 のものは、ひんし直後のバー誤読
    // (割合だけ僅かに読めた) による幻行なので出さない
    // (実例: 2026-11-20 vs チェイス戦、倒れたバサギリに |-heal|0/100)
    if toPct > effFrom, let first = hpText.split(separator: "/").first,
       Int(first.trimmingCharacters(in: .whitespaces)) == 0 {
        lastEmittedPct[plateName] = toPct
        return true
    }
    heldLine[plateName] = nil
    let prevDamageAt = lastDamageTime[plateName]
    let prevDamageSeq = lastDamageSeq[plateName]
    lastDamageSeq[plateName] = actionSeq
    lastDamageTurn[plateName] = currentTurn
    lastDamageDir[plateName] = dir
    lastDamageTime[plateName] = Date()
    lastEmittedPct[plateName] = toPct
    if lastPendingLabel == "\(slot): \(speciesEn)" { lastPendingLabel = "" }
    // 基準値そのものが「疑わしい跳び」として保留中の値か (下の解消で
    // suspectJump は消えるため、ここで控える)。基準が疑わしい場合、
    // 発生源不明の回復は「幻の回復」ではなく基準側の誤りの訂正として
    // 扱う必要がある (実例: 2026-11-22 battle_20261122_050512、
    // 保留された 25% が基準に固定され、実値 41% への回復が
    // 発生源なしとして抑止され、状態が 25% のまま固定された)
    let baselineWasSuspect = suspectJump[plateName].map { $0.toPct == effFrom } ?? false
    // この呼び出しで「低下の疑わしさ」が解けたかどうか (下の解消で
    // suspectJump は消えるため、ここで控える)
    var clearedDropSuspect = false
    // 疑わしい大きな跳びの解消: 保留していた値と同じ読みが次のターン
    // でも続くなら、誤読は内部状態の方だったとみなし、行を出さずに
    // 値だけを取り込む (実例: 2026-11-21 battle_20261121_230402、
    // サーナイトの満タンの正読が「7% への幻の低下」を信じた内部状態
    // のために跳びとして却下され続け、実ダメージまで回復行に化けた)。
    // 別の値に移った場合は疑いを解いて通常処理に戻る
    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct {
            if currentTurn > sj.turn {
                suspectJump[plateName] = nil
                lastEmittedPct[plateName] = toPct
                monStates[key]?.hpPercent = toPct
                monStates[key]?.hpText = hpText
                debugCapture(kind: "hp_jump_adopted", key: "hp_jump_adopted|\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "toPct": toPct, "suspectTurn": sj.turn])
                if debugMode { print("[reader] 疑わしい跳びとして保留していた値を、持続したため状態訂正として取り込みました: \(slot): \(speciesEn) -> \(toPct)%") }
                fflush(stdout)
            }
            return true
        }
        if sj.toPct < effFrom { clearedDropSuspect = true }
        suspectJump[plateName] = nil
    }
    if toPct < effFrom {
        // 直前の技も交代も無い状況での 55 ポイント超の低下は、1 回の
        // 出来事では起こり得ない (設置物は最大でも 25%、反動も技が
        // 先行する)。最後の出来事が交代行で、その後に技が出ていない
        // 場合は、繰り出し演出中のプレート誤読の疑いとして行を出さず
        // に保留する。ただし、直近の技がまだ解決中 (その技の被ダメが
        // 1 件も記録されていない) 場合は対象外: 交代で入った本人が
        // その技を受ける場面では、技行→交代行の順に記録されても
        // 被弾は本物であり、保留すると被ダメが交代行の HP に
        // 畳み込まれて消える (実例: 2026-11-22
        // battle_20261122_050512、交代で入ったガオガエンへの
        // インファイト 75% が保留され、回復もろとも記録が崩れた)。
        // (実例: 2026-11-21 battle_20261121_230402、
        // ペリッパーを倒した直後の交代演出中にサーナイトが 10/145 と
        // 読まれ、93% 喪失の幻行が出た)。状態異常の経過ダメージは
        // 対象外 (どくの経過は大きくなることがある)。保留した値は
        // 上の解消規則で、持続すれば次のターンに取り込まれる
        let moveInFlight = !lastMoveLabel.isEmpty && lastMoveSeq == actionSeq
            && (damagedBySeq[actionSeq] ?? []).isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 20
        if effFrom - toPct > 55, toPct != 0, (monStates[key]?.status ?? "").isEmpty,
           pendingStatusFrom[key] == nil, !moveInFlight,
           lastSwitchEmitSeq >= 0, lastSwitchEmitSeq >= lastMoveEmitSeq {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct])
            if debugMode { print("[reader] 大きな低下を誤読の疑いとして保留しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 訂正の吸収: その枠の直前の行から 10 秒以上経ち、別の行動で、
        // 差が 3% 以下の減少は、落ち着いた実値への訂正とみなして
        // 行を出さず値だけ取り込む (実例: 2026-11-21
        // battle_20261121_224409、ゴツゴツメット反動の 55% が交代
        // 要員選択中に 53% へ訂正され、独立したダメージ行として
        // 追記された)。行動中の小さな実ダメージは、直前の行と行動が
        // 近いため、この条件には入らない
        if toPct != 0, effFrom - toPct <= 3, let lt = prevDamageAt, Date().timeIntervalSince(lt) >= 10,
           prevDamageSeq != actionSeq, Date().timeIntervalSince(lastMoveMsgAt) >= 5 {
            debugCapture(kind: "hp_correction", key: "hp_correction|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct])
            return true
        }
        lastDamageLabel = "\(slot): \(speciesEn)"
        lastDamageAt = Date()
        var line = "|-damage|\(slot): \(speciesEn)|\(hpText)"
        var fromCode: String? = nil
        var selfClassified = false   // 自分の技の反動として分類できたら、推定用イベントも出す
        if let pf = pendingStatusFrom[key], Date().timeIntervalSince(pf.at) < 5 {
            fromCode = pf.code
            pendingStatusFrom[key] = nil
        }
        if fromCode == nil {
            // 初登場の交代行が既に同じ HP を示している場合、その値への
            // ダメージ行は重複である (交代行の HP が初記録であり、
            // そこからの変化はまだ何も起きていない。設置物の [from]
            // 行は上の分岐で処理済み。再登場時の差分行は前回出場時の
            // HP からの変化として意味があるため対象外)
            // (実例: 2026-11-21 battle_20261121_233243、マフォクシーの
            // 交代行 76/100 の直後に同値の被ダメ行が重なった)
            if firstEntryPlateHP[plateName] == hpText {
                firstEntryPlateHP[plateName] = nil
                return true
            }
            // 自分が直前に使った技の直後の自己ダメージは、発生源を
            // 分類する (実例: 2026-11-21 battle_20261121_233243、
            // ウッドハンマーの直後に 10% と 37% の自己ダメージが
            // どちらも素のダメージ行になっていた)。ちょうど 10% は
            // いのちのたまの反動 (持ち物の判明としても記録する)、
            // 反動技のそれ以外の自己ダメージは技の反動とする
            if lastMoveLabel == "\(slot): \(speciesEn)",
               Date().timeIntervalSince(lastMoveMsgAt) < 20 {
                let drop = effFrom - toPct
                let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                    : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
                if (9...11).contains(drop), knownItem == nil || knownItem == "いのちのたま" {
                    if knownItem == nil {
                        emitItemOnce(slot: slot, side: key.hasPrefix("p2") ? "p2" : "p1",
                                     speciesEn: speciesEn, itemJa: "いのちのたま")
                    }
                    fromCode = "item: Life Orb"
                    selfClassified = true
                } else if recoilMoves.contains(lastMoveName) {
                    fromCode = "move: \(lastMoveName)"
                    selfClassified = true
                } else if (11...18).contains(drop) {
                    // 接触した相手の特性・持ち物による反動 (さめはだ/
                    // てつのトゲ = 最大の 1/8、ゴツゴツメット = 1/6)。
                    // 技を受けた側の特性・持ち物が判明している場合に
                    // 限って帰属させる (実例: 2026-11-22
                    // battle_20261122_050512、ねこだましを受けた
                    // ガブリアスの さめはだ反動に [from] が付かなかった)
                    for targetLabel in damagedBySeq[actionSeq] ?? [] where targetLabel != "\(slot): \(speciesEn)" {
                        guard let tp = parseSlotSpecies(targetLabel) else { continue }
                        let tAbility = tp.side == "p1" ? (teamEntries[tp.speciesEn]?["ability"] as? String) : revealedAbilities[tp.speciesEn]
                        let tItem = tp.side == "p1" ? (teamEntries[tp.speciesEn]?["item"] as? String) : revealedItems[tp.speciesEn]
                        if (11...14).contains(drop), tAbility == "さめはだ" {
                            fromCode = "ability: Rough Skin"; selfClassified = true; break
                        }
                        if (11...14).contains(drop), tAbility == "てつのトゲ" {
                            fromCode = "ability: Iron Barbs"; selfClassified = true; break
                        }
                        if (15...18).contains(drop), tItem == "ゴツゴツメット" {
                            emitItemOnce(slot: tp.slot, side: tp.side, speciesEn: tp.speciesEn, itemJa: "ゴツゴツメット")
                            fromCode = "item: Rocky Helmet"; selfClassified = true; break
                        }
                    }
                }
            }
        }
        // 分類できない大きな自己ダメージは、プレート誤読の疑いとして
        // 行を出さずに保留する。自分の技の直後に自分が大きく減る経路は、
        // 反動技・いのちのたま・接触反動 (いずれも上で分類済み) のほかは
        // はらだいこ・のろい (自分を削る使い方)・いたみわけ の自己負担
        // しかなく、それらを除けば 18 ポイントを超える自己低下は実在
        // しない (実例: 2026-11-22 battle_20261122_054802、ラグラージの
        // プレートが 116/207 → 10/207 と誤読され、自分の技の被ダメ行
        // として記録されたうえ、本来の対象 (イエッサン) の被ダメまで
        // 「技は解決済み」と誤判定されて保留に巻き込まれた)
        if fromCode == nil, lastMoveLabel == "\(slot): \(speciesEn)",
           Date().timeIntervalSince(lastMoveMsgAt) < 20, effFrom - toPct > 18,
           !["Belly Drum", "Curse", "Pain Split"].contains(lastMoveName) {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "self_unclassified"])
            if debugMode { print("[reader] 分類できない大きな自己ダメージを誤読の疑いとして保留しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 疑わしい低下を保留した直後に、別の値への説明できない低下が
        // 来た場合は、その値も誤読の連鎖とみて確定させない。保留に
        // なったプレートは読みが安定しておらず、値が変わっただけで
        // 疑いが解けたとは言えない (実例: 2026-11-22
        // battle_20261122_075240、Sneasler に 100% -> 10% の誤読が
        // 保留された後、88% の読みがターン終了時の確定として幻の
        // ダメージ行になった)。持続すれば次ターンに状態訂正として
        // 取り込まれ (冒頭の解消規則)、実値に戻れば何も残らない。
        // 分類できた低下 (状態異常の経過等) は従来どおり出す
        if fromCode == nil, clearedDropSuspect, effFrom - toPct > 3 {
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\(plateName)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "post_suspect_unexplained"])
            return true
        }
        if let fromCode { line += "|[from] \(fromCode)" }
        emitLog(line)
        recordDamageEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, hpText: hpText)
        if selfClassified {
            recordRecoilEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        }
        // 相性行の付け替え判定用に、この行動で被ダメした対象を控える
        damagedBySeq[actionSeq, default: []].insert("\(slot): \(speciesEn)")
        for old in damagedBySeq.keys where old < actionSeq - 1 { damagedBySeq[old] = nil }
        for old in effectBySeq.keys where old < actionSeq - 1 { effectBySeq[old] = nil }
        // オボンのみの発動条件 (HP 半分以下) を跨ぐ低下は、持ち物が
        // 未判明なら発動の監視を始める (解消はこの関数の冒頭で行う)
        if effFrom > 50, toPct <= 50, toPct > 0 {
            let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
            if knownItem == nil { sitrusWatch[key] = toPct }
        }
    } else if toPct > effFrom {
        // 1 回の回復が 55 ポイントを超えることはあり得ない (最大でも
        // じこさいせい/ねがいの 50%)。ログ画面経路と同じ基準で、大きな
        // 回復は誤読として却下し、デバッグ記録を残す (実例: 2026-11-21
        // vs KAM 戦、ふんか演出中にプレートが一時的に満タンと読まれ、
        // 42/177 から全回復の |-heal| が発生源なしで出た)
        if toPct - effFrom > 55 {
            // 記録の state が却下後の値で写るよう、確定基準の巻き戻しを
            // 記録の取得より前に行う (実例: 2026-11-21
            // battle_20261121_145658、却下した 100% が記録の state に
            // そのまま写り、切り分けの妨げになった)
            // ただし却下し続けると、正しい読みが持続している場合に
            // 内部状態の誤りが固定されてしまうため、疑わしい跳び
            // として保留し、次ターンも同じ値なら状態訂正として
            // 取り込む (冒頭の解消規則。実例: 2026-11-21
            // battle_20261121_230402 のサーナイト誤認連鎖)
            suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
            lastEmittedPct[plateName] = effFrom
            debugCapture(kind: "hp_jump_rejected", key: "hp_jump|\(key)", rawText: "",
                         detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "source": "plate"])
            if debugMode { print("[reader] 大きな回復を誤読として却下しました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
            fflush(stdout)
            return true
        }
        // 回復の発生源 (オボンのみ/たべのこし/グラッシーフィールド) が
        // 推定できれば [from] を付け、持ち物なら判明としても記録する
        let src = healSource(plateName: plateName, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        // オボンのみと分類できた回復が本来の +25% に大きく届かず、かつ
        // プレートの最新読みがさらに上を示している場合は、回復
        // アニメーションの途中値とみて確定せずに戻す (基準値は戻し、
        // 後続の読みが最終値で再駆動する。実例: 2026-11-22
        // battle_20261122_070237、+20% で確定し、残り +5% が出所不明の
        // 回復として二重に残った)
        if src?.label == "item: Sitrus Berry", effFrom <= 50, toPct - effFrom <= 21,
           (lastSlots[plateName]?.hpPercent ?? toPct) > toPct {
            lastEmittedPct[plateName] = effFrom
            return false
        }
        // 発生源を特定できず、回復技・ねがいごとの遅延回復・吸収特性
        // でも説明できない回復は、行を出さず証拠記録だけを残す。
        // 以前は行も出していたが、演出中の一時的な満タン誤読が
        // |-heal| として残り、続く被弾行の喪失率表示まで狂わせた
        // (実例: 2026-11-21 battle_20261121_224409、はたき落としの
        // 演出中にイエッサン♀が 82% から全回復したことになり、
        // ひんし表示が「100% 失った」になった)。記録は枠ごとに
        // 最初の 1 件のみ (デバッグ上限の圧迫を避ける)
        if src == nil {
            let knownItem = key.hasPrefix("p2") ? revealedItems[speciesEn]
                : ((teamEntries[speciesEn]?["item"] as? String) ?? revealedItems[speciesEn])
            let knownAbility = key.hasPrefix("p2") ? revealedAbilities[speciesEn]
                : ((teamEntries[speciesEn]?["ability"] as? String) ?? revealedAbilities[speciesEn])
            if !healExplained(key: key, slot: slot, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct,
                              knownItem: knownItem, abilityJa: knownAbility) {
                // 基準値が疑わしい跳びとして保留中の値だった場合は、
                // 回復行は出さないが、値だけは訂正として取り込む
                // (基準の誤りを固定すると、以後の全ての喪失率が
                // 狂う。実例: 2026-11-22 battle_20261122_050512)
                if baselineWasSuspect {
                    lastEmittedPct[plateName] = toPct
                    monStates[key]?.hpPercent = toPct
                    monStates[key]?.hpText = hpText
                    debugCapture(kind: "hp_jump_adopted", key: "hp_jump_adopted|\(plateName)", rawText: "",
                                 detail: ["slot": slot, "species": speciesEn, "toPct": toPct,
                                          "via": "heal_from_suspect_baseline"])
                    if debugMode { print("[reader] 疑わしい基準値からの回復を、状態訂正として取り込みました: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
                    fflush(stdout)
                    return true
                }
                lastEmittedPct[plateName] = effFrom
                if debugMode { print("[reader] 発生源を特定できない回復を記録し、行は出しませんでした: \(slot): \(speciesEn) \(effFrom)% -> \(toPct)%") }
                fflush(stdout)
                debugCapture(kind: "heal_no_source", key: "heal_no_source:\(slot)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct,
                                      "turn": currentTurn, "knownItem": knownItem ?? "", "knownAbility": knownAbility ?? "",
                                      "terrain": logFieldTerrain, "weather": logFieldWeather,
                                      "lastMove": lastMoveName, "lastMoveLabel": lastMoveLabel])
                return true
            }
        }
        if let itemJa = src?.itemJa {
            let srcSide = key.hasPrefix("p2") ? "p2" : "p1"
            emitItemOnce(slot: slot, side: srcSide, speciesEn: speciesEn, itemJa: itemJa)  // 判明登録は applyEvent が行う
            // オボンのみは回復と同時に消費される (たべのこしは消費されない)
            if itemJa == "オボンのみ" { noteItemLost(slot: slot, side: srcSide, speciesEn: speciesEn) }
        }
        var line = "|-heal|\(slot): \(speciesEn)|\(hpText)"
        if let src { line += "|[from] \(src.label)" }
        emitLog(line)
    }
    if toPct == 0 { deferFaint(slot: slot, speciesEn: speciesEn) }
    return true
}

// ひんし行の遅延出力: プレートは HP 0% を即座に拾うが、ゲームの文は
// 「効果は バツグンだ」の後に「たおれた」が出るため、即時に出すと
// 効果行より先に ひんしが並んでしまう (実例: 2026-11-20 vs Zycloud 戦)。
// 文の翻訳が終わったタイミング (watchBattleMessage の末尾) でまとめて出す
func deferFaint(slot: String, speciesEn: String) {
    if faintedSlots[slot] == speciesEn { return }  // 既にひんし行を出した枠・種族は再登録しない
    if !pendingFaints.contains(where: { $0.slot == slot }) {
        pendingFaints.append((slot: slot, speciesEn: speciesEn, at: Date()))
    }
}

// 遅延中のひんし行がまだ有効か: 遅延の間にプレート読みが 0% から回復
// していたら一時的な誤読、枠の種族が入れ替わっていたら交代だったもの
// として捨てる (実例: 2026-11-20、交代しただけのイエッサンに |faint| が出た)
func faintStillValid(_ f: (slot: String, speciesEn: String, at: Date)) -> Bool {
    let fside = f.slot.hasPrefix("p2") ? "p2" : "p1"
    if (monStates["\(fside):\(f.speciesEn)"]?.hpPercent ?? 0) > 0 { return false }
    let plateName = (fside == "p1" ? "mine" : "opp") + (f.slot.hasSuffix("a") ? "A" : "B")
    if let cur = lastSlots[plateName], cur.speciesEn != f.speciesEn { return false }
    return true
}

func emitPendingFaints() {
    let fs = pendingFaints
    pendingFaints = []
    for f in fs {
        if faintedSlots[f.slot] == f.speciesEn { continue }
        if !faintStillValid(f) { continue }
        faintedSlots[f.slot] = f.speciesEn
        emitLog("|faint|\(f.slot): \(f.speciesEn)")
    }
}

// 推定エンジン用: ダメージイベントを記録する (直近の技に帰属できる場合のみ)
func recordDamageEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String) {
    let parts = hpText.split(separator: "/")
    var exact: [Int]? = nil
    if parts.count == 2, let c = Int(parts[0].trimmingCharacters(in: .whitespaces)), let m = Int(parts[1].trimmingCharacters(in: .whitespaces)) {
        exact = [c, m]
    }
    let prevExact = lastExactHp[key]
    if let exact { lastExactHp[key] = exact }
    // 同じ行動・同じ対象・同じ基準 HP からの被ダメが再び放出された
    // 場合は、別イベントとして足さずに先の記録を上書きする。二重の
    // 記録 (推定側での二重処理) を防ぎ、途中値で記録されたイベントを
    // 最終値へ是正するのが目的。連続ヒットは基準 HP が前回の到達値と
    // 一致するため、この条件には当たらず別イベントとして残る
    // (実例: 2026-11-22 battle_20261122_070237、Milotic のイベント
    // 二重化と Farigiraf の amt 食い違い)
    let defLabelForEv = "\(slot): \(speciesEn)"
    let supersedeIdx = battleEvents.lastIndex(where: {
        $0.contains("\"k\":\"dmg\"") && $0.contains("\"turn\":\(currentTurn)")
            && $0.contains("\"atk\":\"\(jsonEscape(lastMoveLabel))\"")
            && $0.contains("\"def\":\"\(jsonEscape(defLabelForEv))\"")
            && $0.contains("\"move\":\"\(jsonEscape(lastMoveName))\"")
            && $0.contains("\"defHp\":\(fromPct)")
    })
    var effPrevExact = prevExact
    if supersedeIdx != nil, let stashed = lastDmgEventPrevExact[key] {
        effPrevExact = stashed.isEmpty ? nil : stashed
    }
    guard battleEvents.count < 600 else { return }
    // 時刻の上限は行動の区切り (actionSeq) 側が本筋の帰属ガードで、
    // こちらは暴走防止の緩い上限にとどめる。開幕の演出や範囲技の
    // 解決が長いと 8 秒では正当な証拠まで落ちる (実例: 2026-11-22
    // battle_20261122_070237 ターン1、ユキメノコのふぶきの被ダメ
    // イベントが欠落した)
    guard !lastMoveLabel.isEmpty, actionSeq - lastMoveSeq <= 1,
          Date().timeIntervalSince(lastMoveMsgAt) < 20 else { return }
    let defSide = key.hasPrefix("p1") ? "p1" : "p2"
    let atkSide = lastMoveLabel.hasPrefix("p1") ? "p1" : "p2"
    guard atkSide != defSide else { return }
    let atkParts = lastMoveLabel.split(separator: ":", maxSplits: 1)
    guard atkParts.count == 2 else { return }
    let atkSpecies = String(atkParts[1]).trimmingCharacters(in: .whitespaces)
    guard !atkSpecies.isEmpty, atkSpecies != speciesEn else { return }
    let atkKey = "\(atkSide):\(atkSpecies)"
    let crit = lastCritAt["\(slot): \(speciesEn)"].map { Date().timeIntervalSince($0) < 6 } ?? false
    func boostsJson(_ k: String) -> String {
        guard let b = monStates[k]?.boosts, !b.isEmpty else { return "{}" }
        let inner = ["atk", "def", "spa", "spd", "spe"].compactMap { kk -> String? in
            guard let v = b[kk], v != 0 else { return nil }
            return "\"\(kk)\": \(v)"
        }
        return "{\(inner.joined(separator: ", "))}"
    }
    func aliveOnField(_ sidePrefix: String, _ side: String) -> Int {
        var n = 0
        for (slotName, s) in lastSlots where slotName.hasPrefix(sidePrefix) {
            if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { n += 1 }
        }
        return n
    }
    var ev = "{\"k\":\"dmg\",\"turn\":\(currentTurn),\"atk\":\"\(jsonEscape(lastMoveLabel))\",\"def\":\"\(jsonEscape("\(slot): \(speciesEn)"))\",\"move\":\"\(jsonEscape(lastMoveName))\",\"crit\":\(crit)"
    ev += ",\"w\":\"\(logFieldWeather)\",\"t\":\"\(logFieldTerrain)\""
    ev += ",\"atkB\":\(boostsJson(atkKey)),\"defB\":\(boostsJson(key))"
    ev += ",\"atkS\":\"\(jsonEscape(monStates[atkKey]?.status ?? ""))\",\"defS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\""
    ev += ",\"atkMega\":\"\(jsonEscape(monStates[atkKey]?.megaSpecies ?? ""))\",\"defMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\""
    ev += ",\"atkAlive\":\(aliveOnField(atkSide == "p1" ? "mine" : "opp", atkSide)),\"defAlive\":\(aliveOnField(defSide == "p1" ? "mine" : "opp", defSide))"
    ev += ",\"atkHp\":\(monStates[atkKey]?.hpPercent ?? 100),\"defHp\":\(fromPct)"
    // 実数差 (amt) は、基準側と現在側で最大 HP が一致する場合だけ使う。
    // 交代行の HP 表記は確定前に % 形式 (100/100) で出ることがあり、
    // その基準 [100, 100] と実数表記 [37, 177] を引くと、実在しない
    // 被ダメ量 (63) がイベントに載る (実例: 2026-11-21
    // battle_20261121_233243、ウッドハンマーの被ダメとして推定側へ
    // 渡り、攻撃側の自己ダメージと誤認された)
    if defSide == "p1", let pe = effPrevExact, let ce = exact, pe[1] == ce[1], pe[0] > ce[0] {
        ev += ",\"amt\":\(pe[0] - ce[0]),\"max\":\(ce[1])"
    } else {
        ev += ",\"pct\":\(fromPct - toPct)"
    }
    ev += "}"
    if let idx = supersedeIdx {
        battleEvents[idx] = ev
    } else {
        battleEvents.append(ev)
        lastDmgEventPrevExact[key] = prevExact ?? []
    }
}

// 自分自身への反動ダメージのイベント (推定エンジンとの契約:
// atk と def が同一ラベルの dmg イベント。相手側で低下が 8〜11% の
// ものが いのちのたま の反動として取り込まれる。技の反動も同じ形で
// 出すが、割合が一定しないため推定側では取り込まれない)
func recordRecoilEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int) {
    guard battleEvents.count < 600 else { return }
    let label = "\(slot): \(speciesEn)"
    func boostsJson(_ k: String) -> String {
        guard let b = monStates[k]?.boosts, !b.isEmpty else { return "{}" }
        let inner = ["atk", "def", "spa", "spd", "spe"].compactMap { kk -> String? in
            guard let v = b[kk], v != 0 else { return nil }
            return "\"\(kk)\": \(v)"
        }
        return "{\(inner.joined(separator: ", "))}"
    }
    let sidePrefix = key.hasPrefix("p1") ? "mine" : "opp"
    let side = key.hasPrefix("p1") ? "p1" : "p2"
    var alive = 0
    for (slotName, s) in lastSlots where slotName.hasPrefix(sidePrefix) {
        if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { alive += 1 }
    }
    var ev = "{\"k\":\"dmg\",\"turn\":\(currentTurn),\"atk\":\"\(jsonEscape(label))\",\"def\":\"\(jsonEscape(label))\",\"move\":\"\(jsonEscape(lastMoveName))\",\"crit\":false"
    ev += ",\"w\":\"\(logFieldWeather)\",\"t\":\"\(logFieldTerrain)\""
    ev += ",\"atkB\":\(boostsJson(key)),\"defB\":\(boostsJson(key))"
    ev += ",\"atkS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\",\"defS\":\"\(jsonEscape(monStates[key]?.status ?? ""))\""
    ev += ",\"atkMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\",\"defMega\":\"\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\""
    ev += ",\"atkAlive\":\(alive),\"defAlive\":\(alive)"
    ev += ",\"atkHp\":\(monStates[key]?.hpPercent ?? toPct),\"defHp\":\(fromPct)"
    ev += ",\"pct\":\(fromPct - toPct)"
    ev += "}"
    battleEvents.append(ev)
}

// 確定待ちのダメージをすべて吐き出す (新しいメッセージやターンの開始前に呼ぶ)。
// 値が現れてから 2.0 秒経っていないプレートは、HP バーの段階アニメーション
// 途中かもしれないため force でない限り吐かない (途中値で吐くと 1 発の被弾が
// 53%+20% のように 2 行に割れる。実例: 2026-11-20 の複数対戦。当初は
// 1.2 秒だったが、範囲技の 2 体同時被弾では片方のバーの減りが
// もう片方の演出の間止まることがあり、1.2 秒では途中値で確定した
// 実例: 2026-11-21 battle_20261121_233243、ワイドフォースが 46%+23% に割れた)
func flushPendingDamage(force: Bool = false) {
    for plate in plates {
        guard let pend = pendingDamagePct[plate.name], let s = lastSlots[plate.name] else { continue }
        if !force, let since = pendingDamageSince[plate.name], Date().timeIntervalSince(since) < 2.0 { continue }
        pendingDamagePct[plate.name] = nil
        pendingDamageCount[plate.name] = nil
        pendingDamageSince[plate.name] = nil
        heldLine[plate.name] = nil
        let side = plate.name.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        let from = lastEmittedPct[plate.name] ?? s.hpPercent
        if pend != from, let st = monStates[key] {
            emitDamageLine(plateName: plate.name, slot: slotId(plate.name), key: key,
                           speciesEn: s.speciesEn, fromPct: from, toPct: pend, hpText: st.hpText, force: true)
        } else {
            lastEmittedPct[plate.name] = pend
        }
    }
}

// プレートの差分をログ行に変換する
// ヘッダー (開始時に書いた相手6体) とプレートで確定した相手種族の
// 照合。ヘッダーが6体そろっているのに、確定した種族が (フォルム
// 違いを除いて) ヘッダーに無い場合は、見せ合い同定が実チームと
// 食い違っていた硬い証拠として記録する (ヘッダー自体は書き換え
// ない)。種族ごとに試合中1回まで
func checkHeaderMismatch(slot: String, speciesEn: String) {
    guard headerOppTeam.count == 6 else { return }
    guard !headerMismatchFired.contains(speciesEn) else { return }
    let entry = speciesDict.first(where: { $0.en == speciesEn })
    let inHeader = headerOppTeam.contains { h in
        h == speciesEn || (entry != nil && formeGroup(entry!).contains { $0.en == h })
    }
    guard !inHeader else { return }
    headerMismatchFired.insert(speciesEn)
    if debugMode { print("[reader] ヘッダーと異なる相手種族がプレートで確定しました: \(speciesEn) (ヘッダー: \(headerOppTeam.joined(separator: ", ")))") }
    fflush(stdout)
    debugCapture(kind: "header_mismatch", key: "header_mismatch:\(speciesEn)", rawText: "",
                 detail: ["species": speciesEn, "header": headerOppTeam,
                          "slot": slot, "turn": currentTurn,
                          "readerBuild": readerBuild])
}

func processPlates(_ hits: [String: SlotState]) {
    // 開始処理を行う条件: (a) まだ開始していない、または (b) 勝敗確定後に
    // 前試合と異なる種族のプレートが現れた (= 次試合の開始証拠なので、
    // 前試合のログへ連結しないよう先に新しい試合を始める。同試合の余韻で
    // プレートが変わらない間は始め直さない)
    if !logStarted || (winLogged && hits.contains { (name, s) in lastSlots[name]?.speciesEn != s.speciesEn }) {
        // 選出画面を経ずにプレートから対戦が始まった場合は、開始処理を
        // 取りこぼしている (対戦開始時に画面がキーボード等で覆われていた、
        // アプリが裏画面だった等。2026-11-21 のユーザー報告)。相手の先発は
        // プレートで確定している種族なので、ヘッダーの |poke| に載せて
        // から開始し、復旧した事実をターミナルとデバッグ情報に残す
        let recovered = !previewTeamWritten
        if recovered {
            for name in ["oppA", "oppB"] {
                if let s = hits[name], !oppTeamSeen.contains(s.speciesEn) {
                    oppTeamSeen.append(s.speciesEn)
                }
            }
        }
        startBattleLog()
        if recovered {
            let leads = ["oppA", "oppB"].compactMap { hits[$0]?.speciesEn }
            print("[log] 対戦開始を取りこぼしたため、プレートから開始状態を復旧しました (相手先発: \(leads.joined(separator: ", ")))")
            fflush(stdout)
            let startNow = Date()
            debugCapture(kind: "late_start", key: "late_start", rawText: "",
                         detail: ["oppLeads": leads, "note": "preview not captured (screen covered or backgrounded)",
                                  "preStart": preStartEvents.map { "-\(Int(startNow.timeIntervalSince($0.0)))s \($0.1)" },
                                  "readerUptimeSec": Int(startNow.timeIntervalSince(readerStartedAt))])
        }
    }
    // 保留中のランク変化行: 交代行が来なくても 30 秒経ったら出す
    flushHeldBoostsTimeout()
    // 遅延中のひんし行: 文が来なくても 1.5 秒経ったら出す
    if !pendingFaints.isEmpty {
        let now = Date()
        let ready = pendingFaints.filter { now.timeIntervalSince($0.at) > 1.5 }
        if !ready.isEmpty {
            pendingFaints.removeAll { now.timeIntervalSince($0.at) > 1.5 }
            for f in ready {
                if faintedSlots[f.slot] == f.speciesEn { continue }
                if !faintStillValid(f) { continue }
                faintedSlots[f.slot] = f.speciesEn
                emitLog("|faint|\(f.slot): \(f.speciesEn)")
            }
        }
    }
    // 枠の入れ替わり: 両枠が互いの登録種族を同時に示し、HP もそれぞれの
    // 登録値と一致する場合は、2 件の交代ではなく表示位置の入れ替わり
    // として登録を入れ替える (交代行は出さない)。ひんし交代の後任が
    // 想定と逆の枠に表示される場合に起きる。2 回続けて観測されたら確定
    // する (実例: 2026-11-22 battle_20261122_070237、コータスが左枠・
    //  オオニューラが右枠に表示され、幻の交代行と両枠ともオオニューラ
    //  という状態破損が起きた)
    for (a, b) in [("mineA", "mineB"), ("oppA", "oppB")] {
        let sideKey = a.hasPrefix("mine") ? "mine" : "opp"
        guard let pa = lastSlots[a], let pb = lastSlots[b],
              let ha = hits[a], let hb = hits[b],
              pa.speciesEn != pb.speciesEn,
              ha.speciesEn == pb.speciesEn, hb.speciesEn == pa.speciesEn,
              faintedSlots[slotId(a)] == nil, faintedSlots[slotId(b)] == nil,
              abs(ha.hpPercent - pb.hpPercent) <= 3, abs(hb.hpPercent - pa.hpPercent) <= 3
        else { slotSwapPending[sideKey] = nil; continue }
        if slotSwapPending[sideKey]?.a == ha.speciesEn {
            slotSwapPending[sideKey]?.count += 1
        } else {
            slotSwapPending[sideKey] = (a: ha.speciesEn, b: hb.speciesEn, count: 1)
        }
        guard (slotSwapPending[sideKey]?.count ?? 0) >= 2 else { continue }
        slotSwapPending[sideKey] = nil
        lastSlots[a] = ha
        lastSlots[b] = hb
        let ea = lastEmittedPct[a]; lastEmittedPct[a] = lastEmittedPct[b]; lastEmittedPct[b] = ea
        let fa = firstEntryPlateHP[a]; firstEntryPlateHP[a] = firstEntryPlateHP[b]; firstEntryPlateHP[b] = fa
        for p in [a, b] {
            pendingDamagePct[p] = nil; pendingDamageCount[p] = nil; pendingDamageSince[p] = nil
            pendingSwitchSpecies[p] = nil; pendingSwitchCount[p] = nil; pendingSwitchSince[p] = nil
            heldLine[p] = nil; suspectJump[p] = nil
        }
        debugCapture(kind: "slot_swap", key: "slot_swap:\(sideKey):\(currentTurn)", rawText: "",
                     detail: ["side": sideKey, "a": "\(a)=\(ha.speciesEn)", "b": "\(b)=\(hb.speciesEn)", "turn": currentTurn])
        if debugMode { print("[reader] 枠の表示位置の入れ替わりを検出し、登録を入れ替えました: \(a)=\(ha.speciesEn) / \(b)=\(hb.speciesEn)") }
        fflush(stdout)
    }
    for plate in plates {
        guard let s = hits[plate.name] else { continue }
        let slot = slotId(plate.name)
        let side = plate.name.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        if monStates[key] == nil { monStates[key] = MonState() }
        // 登録チームの実数値がある種族は、プレート読みの最大値で上書きしない
        // (誤読した最大値が knownMax として固定され、正しい読みまで弾く事故を防ぐ)
        if let m = s.hpMax, (teamEntries[s.speciesEn]?["stats"] as? [String: Int])?["hp"] == nil {
            monStates[key]?.hpMax = m
        }
        let prev = lastSlots[plate.name]
        if prev?.speciesEn != s.speciesEn {
            // 交代の確定は、同じ種族が 2 フレーム連続でその枠に見えてから。
            // 繰り出しアニメーションの途中では一瞬だけ隣の枠で読めることが
            // あり、即時確定すると誤った枠への |switch| と巻き戻しが多発する
            // (実例: 登場直後のグレンアルマが p1a / p1b の両方に記録された)
            if pendingSwitchSpecies[plate.name] == s.speciesEn {
                pendingSwitchCount[plate.name] = (pendingSwitchCount[plate.name] ?? 1) + 1
            } else {
                pendingSwitchSpecies[plate.name] = s.speciesEn
                pendingSwitchCount[plate.name] = 1
                pendingSwitchSince[plate.name] = Date()
            }
            // 交代技で戻ることが確定している側は、後任を 1 回の読みで
            // 確定する (戻り文の消費時に pivotReturnAt が立つ)
            let confirmReads = (pivotReturnAt[side].map { Date().timeIntervalSince($0) < 20 } ?? false) ? 1 : 2
            if (pendingSwitchCount[plate.name] ?? 0) >= confirmReads {
                // 同種族が相方枠に在席したままの確定は、同時交代時の
                // 隣枠への写り込みとして保留する (同一個体が 2 枠に
                // 同時に存在することはない。実例: 2026-11-22
                // battle_20261122_051707、場にいる Gardevoir が別枠にも
                // 「入場」した)。相方側の記録が古いだけの場合に備え、
                // 保留が 6 秒を超えたら確定に進む
                let sibPlate = plate.name.hasPrefix("mine") ? (plate.name.hasSuffix("A") ? "mineB" : "mineA") : (plate.name.hasSuffix("A") ? "oppB" : "oppA")
                if let sib = lastSlots[sibPlate]?.speciesEn, sameSpeciesFamily(sib, s.speciesEn),
                   Date().timeIntervalSince(pendingSwitchSince[plate.name] ?? Date()) < 6 {
                    debugCapture(kind: "switch_species_dup", key: "switch_species_dup:\(plate.name):\(s.speciesEn):\(currentTurn)", rawText: "",
                                 detail: ["plate": plate.name, "species": s.speciesEn, "sibling": sibPlate, "turn": currentTurn])
                    continue
                }
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
                // 交代要員を選んでいる間は、控え一覧画面のバーが場のプレートと
                // して読めて、生きている枠にまで交代行が出ることがある
                // (実例: 2026-11-20、グレンアルマの交代要員選択中に
                //  オオニューラが p1a に出現し、直後にサーナイトの交代行も
                //  重複した)。ひんしの枠への交代 (交代要員そのもの) は通す。
                // この破棄は自軍の選択画面が映る場合だけが根拠なので、
                // 自軍側に限る。相手側のプレートは選択画面に映らず、
                // 相手の任意交代が ひんし交代の確定待ちと重なると本物の
                // 交代まで落としてしまう (実例: 2026-11-22
                // battle_20261122_054802、ターン9に相手の任意交代
                // (イエッサン→サーナイト) が破棄され、交代行の順序が
                // 逆転した)
                let prefix = plate.name.hasPrefix("mine") ? "mine" : "opp"
                let replacementBusy = plate.name.hasPrefix("mine") && faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                if !replacementBusy {
                    // 前の種族のランク変化・かるわざの解除は、下の |switch| 行の
                    // applyEvent が行う (交代に伴う状態変化は行から導く)
                    // 入場時点の HP と前回出場時の HP の差は、交代で入った
                    // 直後に受けた技 (や さいせいさいぼう の回復) の分。
                    // 交代行の HP に吸収されて被ダメ行が出ないため、後で補う
                    let prevPct = monStates[key]?.hpPercent ?? 100
                    let prevText = monStates[key]?.hpText ?? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100")
                    pendingDamagePct[plate.name] = nil
                    heldLine[plate.name] = nil
                    // 試合開始時の先発は必ず満タンで出る。登場アニメーション
                    // 途中のバー読み (満タン未満) をそのまま採用すると、
                    // 以後の全ての割合計算がずれる (実例: 2026-11-20 vs
                    // チャンピオン戦、サーナイト 58/145・イエッサン 74/177
                    // で登場したことになった)。技も被ダメもまだ無い間の
                    // 初登場だけは満タンとして採用する
                    let openingLead = prev == nil && actionSeq == 0
                        && !battleLog.contains { $0.hasPrefix("|move|") || $0.hasPrefix("|-damage|") }
                    // ひんし交代での初登場も、設置物が無い限り満タンでしか
                    // 出ない (バーは登場アニメーションで下から満ちていくため、
                    // 途中値を採用すると幻の被ダメ→全回復の組が出る。実例:
                    // 2026-11-20 vs leslie 戦、グレンアルマが 61/161 で登場し
                    // 翌ターン 161/161 に回復した)。初登場を取り逃がして
                    // 後から発見した場合は実ダメージを消しかねないため、
                    // 前任のひんしが記録済みの枠に限る (交代待ち判定は場が
                    // 1 体の間ずっと立つため条件に使えない)
                    let firstEntry = !(fieldSeen[side]?.contains(s.speciesEn) ?? false)
                        && (monStates[key]?.hpPercent ?? 100) >= 100
                    let replacementEntry = firstEntry && (battleHazards[side] ?? [:]).isEmpty
                        && faintedSlots[slot] != nil
                    let adoptFull = openingLead || replacementEntry
                    let effPct = adoptFull ? 100 : s.hpPercent
                    let effText = adoptFull ? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100") : hpTextFor(s)
                    // 交代行の HP は「入場時点の値」として前回出場時の
                    // 値 (prevPct / prevText) を載せ、入場までに受けた
                    // ダメージ・回復は直後の補完行に担わせる (実例:
                    // 2026-11-22 battle_20261122_050512、ガブリアスの
                    // 交代行が被弾後の 156/185 を載せて同値の被ダメ行と
                    // 重なり、地形回復込みの交代行にも同値の回復行が
                    // 重なった)。ログの基準値 (lastEmittedPct) も交代行
                    // の値に合わせ、補完行がその差分を進める。補完行が
                    // 抑止された場合も、基準は交代行と一致したまま
                    // 次のプレート読みが差分を再駆動する
                    let compensating = effPct != prevPct && !adoptFull
                    lastEmittedPct[plate.name] = compensating ? prevPct : effPct
                    monStates[key]?.hpPercent = effPct
                    monStates[key]?.hpText = effText
                    // 初登場は前回記録が無いため、入場時点の表記は
                    // その種族の満タン表記で組み立てる
                    let entryText = firstEntry ? (s.hpMax.map { "\($0)/\($0)" } ?? "100/100") : prevText
                    var hp = compensating ? entryText : effText
                    if let st = monStates[key]?.status, !st.isEmpty { hp += " \(st)" }
                    emitLog("|switch|\(slot): \(s.speciesEn)|\(s.speciesEn)|\(hp)")
                    sitrusWatch[key] = nil   // 交代を挟んだ監視は持ち越さない
                    if firstEntry { firstEntryPlateHP[plate.name] = effText }
                    recordSwitchIn(side: side, slot: slot, speciesEn: s.speciesEn)
                    if side == "p2" { checkHeaderMismatch(slot: slot, speciesEn: s.speciesEn) }
                    // 交代で入った直後の HP 減少は、設置物ダメージとして
                    // 帰属させる (Showdown の [from] 表記)
                    if effPct < prevPct && !adoptFull {
                        if battleHazards[side]?["Stealth Rock"] != nil { pendingStatusFrom[key] = ("Stealth Rock", Date()) }
                        else if battleHazards[side]?["Spikes"] != nil { pendingStatusFrom[key] = ("Spikes", Date()) }
                    }
                    // 初登場でも、入場時点で既に受けていたダメージは
                    // 被ダメ行として 1 回だけ出す。出さないと、ダメージが
                    // 交代行の HP に畳み込まれ、被ダメの記録と推定用
                    // イベントが丸ごと消える (実例: 2026-11-21
                    // battle_20261121_234913、交代で入ったガブリアスへの
                    // ねっぷうが入場時点で 19% 減・ダメージ行なし)。
                    // 以前は「交代行と同値の重複」とみなして初登場では
                    // 出さなかったが、その判定が実ダメージの喪失を招いた。
                    // 他の経路から同値の行が重なることは、同値ガード
                    // (firstEntryPlateHP) が防ぐため、ここでの 1 本を
                    // 正規の記録とする (ガードはこの呼び出しの間だけ外す)
                    if effPct != prevPct {
                        if firstEntry { firstEntryPlateHP[plate.name] = nil }
                        _ = emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: prevPct, toPct: effPct, hpText: effText, force: true)
                        if firstEntry { firstEntryPlateHP[plate.name] = effText }
                    }
                    faintedSlots.removeValue(forKey: slot)
                    // 0% で登場した (交代直後に技を受けて倒れた等) 場合は
                    // ひんし行を補う
                    if effPct == 0 { deferFaint(slot: slot, speciesEn: s.speciesEn) }
                    lastSlots[plate.name] = adoptFull
                        ? SlotState(speciesEn: s.speciesEn, hpPercent: 100, hpCur: s.hpMax, hpMax: s.hpMax) : s
                } else {
                    // 交代要員選択中のガードで、確定済みの交代が破棄された
                    // ことを証拠として残す (破棄自体は従来どおり)。
                    // 2026-11-21 battle_20261121_150535 では mineB の交代が
                    // 数ターン確定せず、ガードが確定試行を消費した可能性を
                    // 否定できなかったが、記録が無く切り分けられなかった
                    if debugMode { print("[reader] 交代の確定が交代要員選択中のため破棄されました: \(plate.name) -> \(s.speciesEn)") }
                    fflush(stdout)
                    debugCapture(kind: "switch_guard_drop",
                                 key: "switch_guard_drop:\(plate.name):\(s.speciesEn)",
                                 rawText: "",
                                 detail: ["slot": slot, "species": s.speciesEn,
                                          "occupant": prev?.speciesEn ?? "",
                                          "fainted": faintedSlots.filter { $0.key.hasPrefix(side) }.map { "\($0.key):\($0.value)" }.joined(separator: ","),
                                          "turn": currentTurn,
                                          "readerBuild": readerBuild])
                }
            }
        } else {
            pendingSwitchSpecies[plate.name] = nil
            pendingSwitchCount[plate.name] = nil
            pendingSwitchSince[plate.name] = nil
            // ひんし確定済みの枠は、交代が確定するまでプレート読みを無視する
            // (交代要員選択画面で満タンのバーが読めて「全回復」行が出たり、
            //  0% に戻って ひんし行が二重に出たりした実例: 2026-11-20)
            if faintedSlots[slot] == s.speciesEn { continue }
            // 状態 (state.json) は即時更新し、ログ行だけ確定待ちにする
            monStates[key]?.hpPercent = s.hpPercent
            monStates[key]?.hpText = hpTextFor(s)
            let emitted = lastEmittedPct[plate.name] ?? s.hpPercent
            // HP 3系統の照合 (改善計画フェーズ2): 数字 OCR と HP バーの
            // 画素長が大きく食い違う場合は、黙って選ばず証拠として残す
            // (状態への組み込みは従来どおり数字 OCR 優先。ログ確定値が
            // 第3系統として文脈に併記される)
            if let bar = s.hpBarPct, abs(bar - s.hpPercent) >= 25 {
                debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)",
                             rawText: "",
                             detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                      "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                      "readerBuild": readerBuild])
            }
            if s.hpPercent == emitted {
                pendingDamagePct[plate.name] = nil
                pendingDamageCount[plate.name] = nil
            } else if s.hpPercent == 0 {
                // 0% (ひんし) は原則即時だが、隣の枠の 0% が一瞬だけ混入
                // する誤読で「幻の ひんし」になった実例があるため、
                // 2 フレーム連続で 0% のときだけ確定する
                // (実例: 2026-11-20、場に残っていたアブソルが 0% と
                //  誤読されて ひんし行まで出た)
                if pendingDamagePct[plate.name] == 0 {
                    let n = (pendingDamageCount[plate.name] ?? 1) + 1
                    if n >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                       fromPct: emitted, toPct: 0, hpText: monStates[key]!.hpText)
                    } else {
                        pendingDamageCount[plate.name] = n
                    }
                } else {
                    pendingDamagePct[plate.name] = 0
                    pendingDamageCount[plate.name] = 1
                    pendingDamageSince[plate.name] = Date()
                }
            } else if pendingDamagePct[plate.name] == s.hpPercent {
                // 同じ値が 3 回続き、かつ現れてから 2.0 秒経った = アニメーションが
                // 落ち着いた (段階アニメーションは途中で 1 秒近く止まることが
                // あり、回数だけでは途中値を確定してしまうため時間でも見る。
                // 範囲技の 2 体同時被弾では片方のバーがもう片方の演出の間
                // 止まるため、当初の 1.2 秒では途中値が確定した)
                let n = (pendingDamageCount[plate.name] ?? 1) + 1
                let stable = Date().timeIntervalSince(pendingDamageSince[plate.name] ?? .distantPast) >= 2.0
                if n >= 3 && stable {
                    // 安定した時点でもバー計測と数字 OCR が食い違う場合は
                    // 系統間の不一致として証拠に残す (フェーズ2)
                    if let bar = s.hpBarPct, abs(bar - s.hpPercent) >= 8 {
                        debugCapture(kind: "hp_disagree", key: "hp_disagree:\(plate.name):\(s.hpPercent):\(bar)",
                                     rawText: "",
                                     detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                              "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                              "readerBuild": readerBuild])
                    }
                    if emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                      fromPct: emitted, toPct: s.hpPercent, hpText: monStates[key]!.hpText) {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                    } else {
                        // 同一行動内の段階値として保留 (値は保持する)
                        pendingDamageCount[plate.name] = 3
                    }
                } else {
                    pendingDamageCount[plate.name] = n
                }
            } else {
                pendingDamagePct[plate.name] = s.hpPercent
                pendingDamageCount[plate.name] = 1
                pendingDamageSince[plate.name] = Date()
                lastPendingLabel = "\(slot): \(s.speciesEn)"
            }
            lastSlots[plate.name] = s
        }
    }
    // 保留していた天候・地形の開始行を流す: 交代の確定が済んだ時点
    // (確定待ちが空になった) か、6 秒を超えたら強制的に出す。
    // 以前は 2.5 秒だったが、登場演出が長いと確定前に強制分が流れ、
    // 開始行が交代行より前に出た (実例: 2026-11-22
    // battle_20261122_050512、グラスフィールド開始行が
    // ゴリランダーの交代行より前に置かれた)
    if heldWeatherStart != nil || heldTerrainStart != nil {
        // 要員待ちが続く間は上限を延ばす (要員選択は 6 秒を超えることが
        // 普通にある。要員が登録されれば即座に流れる)
        let awaitingNow = anyAwaitingReplacement()
        let heldAge = Date().timeIntervalSince((heldWeatherStart?.at ?? heldTerrainStart?.at) ?? .distantPast)
        let ready = (pendingSwitchSpecies.isEmpty && !awaitingNow) || heldAge > (awaitingNow ? 20.0 : 6.0)
        if ready {
            fieldHoldBypass = true
            if let h = heldWeatherStart { heldWeatherStart = nil; setWeather(h.ui, h.logName, via: h.text) }
            if let h = heldTerrainStart { heldTerrainStart = nil; setTerrain(h.ui, via: h.text) }
            fieldHoldBypass = false
        }
    }
    // 入場特性の効果として保留した行: 交代の確定待ちが空になったら流す
    if !heldEntryBoosts.isEmpty && pendingSwitchSpecies.isEmpty && !anyAwaitingReplacement() { flushHeldEntryBoosts() }
    // 出所未確認で保留した地形の上書きの確認 (採用/破棄)
    confirmHeldTerrainReplace()
}

// MARK: - ゲーム内ログ画面の解析
// 「ログを見る」画面 (ターン別) を OCR し、エントリを Showdown プロトコルに翻訳する。
// 状態異常・技・持ち物・特性の判明はこの画面から拾う (プレートには状態異常が出ないため)。

let logChips: Set<String> = ["技", "HP減少", "ひんし", "持ち物", "状態異常", "特性", "回復", "交代", "能力変化", "天気"]

func regexGroups(_ pattern: String, _ text: String) -> [String]? {
    guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = text as NSString
    guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
    return (0..<m.numberOfRanges).map { ns.substring(with: m.range(at: $0)) }
}

func findSpeciesJa(in text: String) -> SpeciesEntry? {
    let t = normalize(text)
    var best: SpeciesEntry? = nil
    for e in speciesDict where !e.ja.isEmpty {
        if t.contains(normalize(e.ja)) && (best == nil || e.ja.count > best!.ja.count) { best = e }
    }
    // 「メガ」が「メカ」に崩れると基本フォルムに落ちて状態の記録先キーが
    // ずれるため、メカ→メガに直した文でも照合する (検証 R1 #83 で検出)
    if t.contains("メカ") {
        let t2 = t.replacingOccurrences(of: "メカ", with: "メガ")
        for e in speciesDict where !e.ja.isEmpty {
            if t2.contains(normalize(e.ja)) && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
    }
    // 濁点ゆれで名前が崩れた場合 (サーナイト→ザーナイト、ドラパルト→
    // ドラパルド等) は、両辺の濁点を畳んだ形でも照合する。通常照合で
    // 何も見つからなかった場合だけ使う (検証 R2 で検出)
    if best == nil {
        let ft = foldDakuten(t)
        for e in speciesDict where !e.ja.isEmpty {
            if ft.contains(foldDakuten(normalize(e.ja))) && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
    }
    // さらに「ー」落ちまで重なった場合 (サーナイト→ザナイト) は、長音も
    // 落として照合する。カラカラ/ガラガラ のような衝突があるため、場か
    // チームで裏付けが取れた候補だけを採る (検証 R2 で検出)。
    // ッ→ツも畳む (イエッサン→イエツザン の二重ゆれ対策、検証 hard R7)。
    // この変換 (畳み+ッ→ツ+長音落ち) の衝突は全件フォルム違いのみで
    // あることを辞書全件で確認済み
    if best == nil {
        let tsuFold: (String) -> String = { $0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ") }
        let ft = tsuFold(foldDakuten(t)).replacingOccurrences(of: "ー", with: "")
        for e in speciesDict where !e.ja.isEmpty {
            let nk = tsuFold(foldDakuten(normalize(e.ja))).replacingOccurrences(of: "ー", with: "")
            guard ft.contains(nk) else { continue }
            let anch = fieldAnchoredSpecies(e)
            let backed = lastSlots.values.contains { $0.speciesEn == anch.en }
                || teamEntries[anch.en] != nil || oppTeamSeen.contains(anch.en)
            if backed && (best == nil || e.ja.count > best!.ja.count) { best = e }
        }
    }
    return best
}

func findInDict(in text: String, _ dict: [String: String]) -> String? {
    let t = normalize(text)
    var best: String? = nil
    for (norm, orig) in dict {
        if !norm.isEmpty && t.contains(norm) && (best == nil || orig.count > best!.count) { best = orig }
    }
    return best
}

func slotFor(side: String, speciesEn: String) -> String {
    for (name, s) in lastSlots where (name.hasPrefix("mine") ? "p1" : "p2") == side && s.speciesEn == speciesEn {
        return slotId(name)
    }
    return side + "a"
}

func checkStatusText(text: String, side: String, speciesEn: String, slot: String) {
    let key = "\(side):\(speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // 起床: 「<対象>は 目を覚ました！」(目 が 自 に崩れた形も、覚ました
    // 自体が特徴的なため拾う。実例: 2026-11-21 battle_20261121_234913
    // 「ガブリアスは自を覚ました！」が未翻訳で残った)
    if text.contains("覚ました") {
        if monStates[key]?.status == "slp" {
            emitLog("|-curestatus|\(slot): \(speciesEn)|slp")
        }
        return
    }
    if text.contains("なおった") || text.contains("なおつた") {
        if let cur = monStates[key]?.status, !cur.isEmpty {
            emitLog("|-curestatus|\(slot): \(speciesEn)|\(cur)")  // 状態への反映は applyEvent が行う
        }
        return
    }
    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた"]
    guard cues.contains(where: { text.contains($0) }) else { return }
    var code: String? = nil
    if text.contains("もうどく") { code = "tox" }
    else if text.contains("どく") { code = "psn" }
    else if text.contains("やけど") { code = "brn" }
    else if text.contains("まひ") { code = "par" }
    else if text.contains("ねむ") { code = "slp" }
    else if text.contains("こおり") || text.contains("こおった") { code = "frz" }
    if let code, monStates[key]?.status != code {
        emitLog("|-status|\(slot): \(speciesEn)|\(code)")  // 状態への反映は applyEvent が行う
    }
}

// ログ画面のチップ色から決めた side の検証: 色の読み違いで自分の
// ポケモンの技や ひんし が相手側に付いた実例があるため (2026-11-20、
// サーナイトの ハイパーボイス と ひんし が p2a に付いた)、場・チームの
// 実態と矛盾する場合は実態側を優先する
func validatedSide(forSpecies en: String, claimed: String) -> String {
    let inMine = lastSlots["mineA"]?.speciesEn == en || lastSlots["mineB"]?.speciesEn == en
    let inOpp = lastSlots["oppA"]?.speciesEn == en || lastSlots["oppB"]?.speciesEn == en
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    let teamMine = teamEntries[en] != nil
    let teamOpp = oppTeamSeen.contains(en)
    if teamMine != teamOpp { return teamMine ? "p1" : "p2" }
    return claimed
}

func translateLogEntry(chip: String, text: String, side: String, turn: Int) {
    guard let sp0 = findSpeciesJa(in: text) else {
        // 主語が解決できないエントリでも、確度の高い信号だけは救済する。
        // ランク変化は直近ターンのエントリだけ (古いエントリからの適用は
        // 実況経路の一本化方針に反し、二重適用の危険があるため)
        _ = salvageFromText(text, allowBoost: turn >= currentTurn - 1, fromLogScreen: true)
        if debugMode { print("    -> 種族名が本文に無いため取り込めませんでした") }
        return
    }
    // ログ画面の種族名は雌雄表記が同一のため、場のフォルムに寄せる
    // (寄せないと「イエッサン」のような基本フォルム名で記録される)
    let sp = fieldAnchoredSpecies(sp0)
    let side = validatedSide(forSpecies: sp.en, claimed: side)
    let slot = slotFor(side: side, speciesEn: sp.en)
    let key = "\(side):\(sp.en)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // その枠に出てきたばかりの種族への ひんし 帰属は信用しない。
    // ログ画面のエントリ取り違えで、交代直後の生存枠に幻のひんしが
    // 出た実例があるため (2026-11-20 vs チェイス戦のグレンアルマ)。
    // 本当に倒れていれば実況・プレート側の経路が別途ひんしを出す
    let justSwitchedIn = lastSwitchIn[key].map { $0.slot == slot && Date().timeIntervalSince($0.at) < 30 } ?? false
    switch chip {
    case "技":
        if let mvJa = findInDict(in: text, moveNameOrig) {
            // 実況メッセージ側で記録済みの (枠・技・ターン) は二重に出さない
            // (実例: 2026-11-20、まもる が実況とログ画面の両方から出た)
            let moveEn = moveJa2En[mvJa] ?? mvJa
            let sig = slot + "|" + moveEn + "|t" + String(turn)
            if lastMoveSigAt[sig] != nil { break }
            lastMoveSigAt[sig] = Date()
            emitLog("|move|\(slot): \(sp.en)|\(moveEn)")  // 判明登録は applyEvent が行う
            applyMoveField(mvJa, side: side)
        } else if debugMode {
            print("    -> 技名が辞書に見つかりませんでした")
        }
    case "HP減少", "回復":
        if let g = regexGroups(#"HP\s*(\d+)(%?)\s*(?:→|->)\s*(\d+)(%?)"#, text), g.count >= 5,
           let bVal = Int(g[3]) {
            let isPct = !g[2].isEmpty || !g[4].isEmpty
            var newPct: Int? = nil
            var hpText = ""
            if isPct {
                newPct = bVal
                hpText = "\(bVal)/100"
            } else if let mx = monStates[key]?.hpMax {
                newPct = Int((Double(bVal) / Double(mx) * 100).rounded())
                hpText = "\(bVal)/\(mx)"
            } else if bVal == 0 {
                newPct = 0
                hpText = "0/100"
            }
            if let np = newPct, let cur = monStates[key]?.hpPercent, np != cur {
                // 1 エントリで 55 ポイントを超える回復はあり得ない
                // (最大でも じこさいせい/ねがいの 50%)。隣の行の値を
                // 拾った誤読とみて取り込まない (実例: 2026-11-20、
                // 残り 4 のイエッサンが「全回復」として取り込まれた)
                if np > cur && np - cur > 55 {
                    debugCapture(kind: "hp_jump_rejected", key: "hp_jump|\(key)", rawText: text,
                                 detail: ["slot": slot, "species": sp.en, "fromPct": cur, "toPct": np])
                    break
                }
                // 状態への反映は emitLog -> applyEvent が行う (行の HP 表記から)
                if np < cur { emitLog("|-damage|\(slot): \(sp.en)|\(hpText)") }
                else { emitLog("|-heal|\(slot): \(sp.en)|\(hpText)") }
                if np == 0 && !justSwitchedIn { emitLog("|faint|\(slot): \(sp.en)") }
                else if np == 0 && justSwitchedIn {
                    debugCapture(kind: "faint_guard", key: "faint_guard|\(key)", rawText: text,
                                 detail: ["slot": slot, "species": sp.en, "source": "logscreen_hp"])
                }
            }
        }
    case "ひんし":
        if !justSwitchedIn && (monStates[key]?.hpPercent ?? 0) > 0 {
            emitLog("|faint|\(slot): \(sp.en)")  // 状態への反映は applyEvent が行う
        } else if justSwitchedIn {
            debugCapture(kind: "faint_guard", key: "faint_guard|\(key)", rawText: text,
                         detail: ["slot": slot, "species": sp.en, "source": "logscreen_faint_text"])
        }
    case "持ち物":
        if let itJa = findInDict(in: text, itemDict) {
            // メガストーンが特定できた場合は、種族をストーンから
            // 決め直す。ログ画面の小さい文字では種族名の末尾が
            // 落ちやすく (リザードン → リザード)、本文の名前検索
            // だけでは別種に一致するため (実例: 2026-11-22
            // battle_20261122_051707、Charmeleon の持ち物行)。
            // 実況側のメガ反応分岐 (build 20261122_0552) と同じ規則
            var useSp = sp
            var useSide = side
            var useSlot = slot
            if itJa.contains("ナイト"), let sEn = itemJa2En[itJa] {
                var baseEn = sEn
                for suf in ["ite X", "ite Y", "ite Z", "ite"] where baseEn.hasSuffix(suf) {
                    baseEn = String(baseEn.dropLast(suf.count)); break
                }
                if let stoneSp = speciesDict.first(where: { $0.en == baseEn }), stoneSp.en != sp.en {
                    useSp = stoneSp
                    useSide = validatedSide(forSpecies: stoneSp.en, claimed: side)
                    useSlot = slotFor(side: useSide, speciesEn: stoneSp.en)
                }
            }
            emitItemOnce(slot: useSlot, side: useSide, speciesEn: useSp.en, itemJa: itJa)  // 判明登録は applyEvent が行う
        }
    case "特性":
        if let abJa = findInDict(in: text, abilityDict) {
            emitLog("|-ability|\(slot): \(sp.en)|\(abilityJa2En[abJa] ?? abJa)")  // 判明登録は applyEvent が行う
        }
    default:
        break
    }
    checkStatusText(text: text, side: side, speciesEn: sp.en, slot: slot)
    // ランク変化はここでは適用しない: 実況メッセージで取り込み済みの変化が
    // ログ画面のエントリから二重に適用されてしまうため (ログが 2 重に出る
    // 原因の 1 つ)。ランク変化の取り込みは実況メッセージ経路に一本化する。
    // 天候・フィールドも、古いエントリの開始/終了文で現行の状態を
    // 上書きしないよう fromLogScreen を伝える (setter 側で stale 判定)
    checkFieldText(text: text, fromLogScreen: true)
}

// 天候・フィールドの setter (ログ行は変化したときだけ出す)
func setWeather(_ ui: String, _ logName: String, via text: String = "", stale: Bool = false) {
    if logFieldWeather == ui { return }
    // ログ画面経由の古い開始文は、実況で追えている現行の天候を上書きしない
    // (地形側と同じ再適用の穴。現行が空のときの復旧は従来どおり行う)
    if stale && !logFieldWeather.isEmpty {
        if debugMode { print("[field] ログ画面の古い天候文を採用しませんでした: \(ui) (現在: \(logFieldWeather))") }
        debugCapture(kind: "weather_change", key: "weather_change_blocked:\(ui)", rawText: text,
                     detail: ["from": logFieldWeather, "to": ui, "turn": currentTurn, "blocked": true])
        return
    }
    // 交代の確定 (プレート 2 フレーム) がまだの間に開始文だけが先に
    // 届くと、開始行が交代行より前に出てしまう (実例: 2026-11-21
    // battle_20261121_230402、ペリッパーの あめふらし の雨開始行が
    // 繰り出し行より前に出た)。交代確定待ちがある間は開始文を保留し、
    // プレート処理の末尾で流す (最大 2.5 秒で強制的に流す)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {
        if heldWeatherStart?.ui != ui {
            heldWeatherStart = (ui: ui, logName: logName, text: text, at: Date())
        }
        return
    }
    let prev = logFieldWeather
    fieldWeatherSetAt = Date()
    // この天候が保留中のメガのフィールド特性によるものなら、
    // 天候行より先にメガ完了を補う (順序の保持)
    let weatherAbility: [String: String] = ["Sun": "Drought", "Rain": "Drizzle", "Sand": "Sand Stream", "Snow": "Snow Warning"]
    if let ab = weatherAbility[ui] { completePendingMegaForField(ability: ab) }
    emitLog("|-weather|\(logName)")  // 状態への反映は applyEvent が行う
    attributeFieldAbilities()
    // 天候の変化は根拠テキストごと残す (変化の経路を後から特定できるように)
    if !text.isEmpty {
        debugCapture(kind: "weather_change", key: "weather_change:\(currentTurn):\(ui)", rawText: text,
                     detail: ["from": prev, "to": ui, "turn": currentTurn])
    }
}
func clearWeather(stale: Bool = false) {
    if logFieldWeather.isEmpty { return }
    if stale {
        if debugMode { print("[field] ログ画面の古い天候終了文で現行の天候を消しませんでした: \(logFieldWeather)") }
        return
    }
    emitLog("|-weather|none")
}
// 地形の開始に、その地形を張れる出所 (サージ特性での交代・地形技の
// 使用) が直近にあるか。開始文の再読や古いフレームの再処理は出所を
// 伴わないため、別の地形への上書き採用の可否の判定に使う
func terrainSourcePlausible(_ ui: String) -> Bool {
    let surge: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    guard let ab = surge[ui] else { return true }
    // 地形技が直近の技なら、その技からの開始として妥当
    if lastMoveName == "\(ui) Terrain", Date().timeIntervalSince(lastMoveMsgAt) < 25 { return true }
    // 直近の交代で入った個体が、その特性を持ちうるなら妥当
    // (メガフォルムの特性は別エントリにあるため科単位でも見る)
    for (key, sw) in lastSwitchIn where Date().timeIntervalSince(sw.at) < 25 {
        let sp = key.split(separator: ":").last.map(String.init) ?? ""
        if (speciesAbilityMap[sp] ?? []).contains(ab) { return true }
        for (other, pool) in speciesAbilityMap where pool.contains(ab) && sameSpeciesFamily(other, sp) { return true }
    }
    return false
}

// 出所未確認で保留した地形の上書き: 出所が付けば採用し、4 秒
// 付かなければ開始文の再読・古いフレームの再処理とみなして破棄する
func confirmHeldTerrainReplace() {
    guard let h = heldTerrainReplace else { return }
    if terrainSourcePlausible(h.ui) {
        heldTerrainReplace = nil
        fieldHoldBypass = true
        setTerrain(h.ui, via: h.text)
        fieldHoldBypass = false
    } else if Date().timeIntervalSince(h.at) > 4.0 {
        heldTerrainReplace = nil
        debugCapture(kind: "terrain_change", key: "terrain_change_blocked:\(h.ui)", rawText: h.text,
                     detail: ["from": logFieldTerrain, "to": h.ui, "turn": currentTurn, "blocked": true, "reason": "unconfirmed_replace"])
        if debugMode { print("[field] 出所を確認できない地形の上書きを採用しませんでした: \(h.ui) (現在: \(logFieldTerrain))") }
        fflush(stdout)
    }
}

func setTerrain(_ ui: String, via text: String = "", stale: Bool = false) {
    if logFieldTerrain == ui { return }
    // ログ画面経由の古い開始文は、実況で追えている現行の地形を上書きしない
    // (実例: 2026-11-21 battle_20261121_161334、対戦開始時のサイコフィールドの
    //  文がターン2終了時に再適用され、グラスフィールド下でサイコシードの
    //  消費まで補完された。現行が空のときの復旧は従来どおり行う)
    if stale && !logFieldTerrain.isEmpty {
        if debugMode { print("[field] ログ画面の古い地形文を採用しませんでした: \(ui) (現在: \(logFieldTerrain))") }
        debugCapture(kind: "terrain_change", key: "terrain_change_blocked:\(ui)", rawText: text,
                     detail: ["from": logFieldTerrain, "to": ui, "turn": currentTurn, "blocked": true])
        return
    }
    // 天候と同じく、交代確定待ちの間は開始文を保留する (順序の保持)
    if !stale && !text.isEmpty && !fieldHoldBypass && (!pendingSwitchSpecies.isEmpty || anyAwaitingReplacement()) {
        if heldTerrainStart?.ui != ui {
            heldTerrainStart = (ui: ui, text: text, at: Date())
        }
        return
    }
    // 別の地形が張られている状態への上書きは、出所 (サージ特性の
    // 交代・地形技) が直近に確認できる場合だけ即時に採用する。
    // 出所の無い上書きは開始文の再読や古いフレームの再処理の疑いが
    // 強いため短時間保留し、出所が付けば採用し、付かなければ
    // 破棄する (実例: 2026-11-22 battle_20261122_054802、開始時の
    // サイコフィールド文がターン3に再処理され、張られたばかりの
    // グラスフィールドを上書きした)
    if !logFieldTerrain.isEmpty && !stale && !text.isEmpty && !fieldHoldBypass && !terrainSourcePlausible(ui) {
        if heldTerrainReplace?.ui != ui {
            heldTerrainReplace = (ui: ui, text: text, at: Date())
        }
        return
    }
    let prev = logFieldTerrain
    fieldTerrainSetAt = Date()
    let terrainAbility: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    if let ab = terrainAbility[ui] { completePendingMegaForField(ability: ab) }
    emitLog("|-fieldstart|move: \(ui) Terrain")  // 状態への反映は applyEvent が行う
    attributeFieldAbilities()
    retroSeedCheck(terrain: ui)
    // 地形の変化は根拠テキストごと残す (変化の経路を後から特定できるように)
    if !text.isEmpty {
        debugCapture(kind: "terrain_change", key: "terrain_change:\(currentTurn):\(ui)", rawText: text,
                     detail: ["from": prev, "to": ui, "turn": currentTurn])
    }
}

// フィールドが張られた瞬間、その地形に対応するシードを持つ場のポケモンは
// ゲーム内で即座にシードを消費している。地形の開始を取りこぼして後から
// 検出した場合、通常の消費検知 (対応する能力の +1 が地形判明下で起きること)
// が働かないため、ここで遡って消費を記録する。持ち物が判明していない
// 個体には推測で記録しない
// (実例: 2026-11-21 vs Woxofyl 戦、サイコフィールドの開始を取りこぼし、
//  オオニューラのサイコシード消費と かるわざ が最後まで反映されなかった)
func retroSeedCheck(terrain: String) {
    let seedFor: [String: (item: String, stat: String)] = ["Psychic": ("サイコシード", "spd"), "Misty": ("ミストシード", "spd"), "Electric": ("エレキシード", "def"), "Grassy": ("グラスシード", "def")]
    guard let sd = seedFor[terrain] else { return }
    for (plateName, s) in lastSlots {
        let side = plateName.hasPrefix("mine") ? "p1" : "p2"
        let key = "\(side):\(s.speciesEn)"
        if itemLostActive.contains(key) { continue }
        if monStates[key] == nil { monStates[key] = MonState() }
        if (monStates[key]?.hpPercent ?? 100) <= 0 { continue }
        let knownItem = side == "p1" ? (teamEntries[s.speciesEn]?["item"] as? String) : revealedItems[s.speciesEn]
        guard knownItem == sd.item else { continue }
        let slot = slotId(plateName)
        // シードの上昇分も取りこぼしている場合だけ補う。その能力に既に
        // 記録済みの変化がある場合は、内訳を分解できないため重ねない
        // (上昇だけはサルベージ経由で入れる。直後に本物の上昇文が届いた
        //  場合は経路をまたぐ二重適用防止が 25 秒間はじく)
        if !boostTouchedStats.contains("\(key)|\(sd.stat)") {
            applyBoost(key: key, slot: slot, speciesEn: s.speciesEn, stat: sd.stat, delta: 1, viaSalvage: true)
        }
        noteItemLost(slot: slot, side: side, speciesEn: s.speciesEn)
    }
}

// 天候・フィールドが張られた直後に場に出たポケモンが、その天候・フィールドを
// 張る特性を 1 つだけ持つ場合は、その特性の発動として記録する。ゲーム内では
// 特性バナーと天候/フィールド文が別々に表示され、バナーを読み落とすことが
// あるため (例: コータスのひでり、イエッサンのサイコメイカーの 2 回目)。
// いかくの帰属: 特性名はバナー表示のみでメッセージ文に出ないため、
// [X's Intimidate] の行は今まで出なかった。「繰り出し直後 (その後まだ
// 技の文が無い) に相手側へ 攻撃 -1 が入った」場合、その繰り出しが
// いかく持ちなら特性として帰属する
func attributeIntimidate(targetSide: String) {
    let other = targetSide == "p1" ? "p2" : "p1"
    let now = Date()
    for (key, sw) in lastSwitchIn where key.hasPrefix("\(other):") {
        if intimidateDone[key] == sw.at { continue }
        guard now.timeIntervalSince(sw.at) < 8 else { continue }
        guard lastMoveMsgAt < sw.at else { continue }   // 繰り出し後に技が使われていたら、その技の効果とみなす
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let en = String(parts[1])
        guard let pool = speciesAbilityMap[en], pool.contains("Intimidate") else { continue }
        intimidateDone[key] = sw.at
        emitAbilityOnce(slot: sw.slot, side: other, speciesEn: en, abilityEn: "Intimidate")  // 判明登録は applyEvent が行う
    }
}

func attributeFieldAbilities() {
    let weatherAb: [String: String] = ["Sun": "Drought", "Rain": "Drizzle", "Sand": "Sand Stream", "Snow": "Snow Warning"]
    let terrainAb: [String: String] = ["Psychic": "Psychic Surge", "Electric": "Electric Surge", "Grassy": "Grassy Surge", "Misty": "Misty Surge"]
    let allField: Set<String> = Set(weatherAb.values).union(terrainAb.values)
    let now = Date()
    for (key, sw) in lastSwitchIn {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        guard let pool = speciesAbilityMap[en] else { continue }
        let fieldOnes = pool.filter { allField.contains($0) }
        guard fieldOnes.count == 1, let ab = fieldOnes.first else { continue }
        var matched = false
        // 窓は 30 秒: フィールド文 (即時) とプレート確定 (2 フレーム+演出の
        // バックログ) の間隔が 12 秒を超えることがある (実例: 2026-11-20、
        // イエッサンのサイコメイカー括弧行が落ちた)
        if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        // ターン一致: 交代の確定が大きく遅れると 30 秒の窓を超える
        // (実例: 2026-11-21 battle_20261121_230402、イエッサン♀の
        // 確定が地形開始から約 41 秒遅れ、サイコメイカーが付かなかった)。
        // フィールドを張ったのと同じターンに入った交代は、その入場が
        // 原因とみなす。ただし、そのフィールドが技で張られたターン
        // は除く (技の使用者が原因のため)
        let inTurn = switchInTurn[key].map { max($0, 1) }   // trackFieldEvent の eff (max(currentTurn, 1)) に合わせる
        if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
        if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
        // 開始直後の上書き: 先発は最初のターン行より前に場に出ており、
        // その入場で張った天候・地形が、相手の先発の特性で即座に
        // 上書きされることがある (実例: 2026-11-21 battle_20261121_233243、
        // ゴリランダーのグラスフィールドがサイコフィールドに上書き
        // され、グラスメイカーが付かなかった)。先発 (ターン 0 で記録)
        // に限り、上書きされた側に対しても帰属する
        if switchInTurn[key] == 0 {
            if weatherAb[prevFieldWeather] == ab && fieldSetByMoveTurn != prevFieldWeatherSetTurn { matched = true }
            if terrainAb[prevFieldTerrain] == ab && fieldSetByMoveTurn != prevFieldTerrainSetTurn { matched = true }
        }
        if matched {
            fieldAbilityDone[key] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: en, abilityEn: ab)
        }
    }
    // メガフォルム側のフィールド特性: ベース種族のプールには含まれない
    // (リザードンの ひでり は メガリザードンY 側)。完了済み・保留中の
    // メガフォルムの特性で現在の天候・地形と一致するものがあれば、
    // その特性行をメガフォルム名で出す (完了が保留中なら先に補う)
    for (key, sw) in lastSwitchIn {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        let forme = monStates[key]?.megaSpecies ?? pendingMegaForme(side: side, baseEn: en)
        guard let forme, forme != en, let mpool = speciesAbilityMap[forme] else { continue }
        let mfield = mpool.filter { allField.contains($0) }
        guard mfield.count == 1, let ab = mfield.first else { continue }
        var matched = false
        if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
        let inTurn = switchInTurn[key].map { max($0, 1) }
        if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
        if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
        if switchInTurn[key] == 0 {
            if weatherAb[prevFieldWeather] == ab && fieldSetByMoveTurn != prevFieldWeatherSetTurn { matched = true }
            if terrainAb[prevFieldTerrain] == ab && fieldSetByMoveTurn != prevFieldTerrainSetTurn { matched = true }
        }
        if matched {
            fieldAbilityDone[key] = sw.at
            if pendingMegaSpecies[side] == en { completeMega(side: side, baseEn: en, megaEn: forme) }
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: forme, abilityEn: ab)
        }
    }
    // 別フォルム側のフィールド特性: 現在の天候・地形が、場の誰の現在の
    // フォルムでも説明できず、交代で入った相手の同種族の別フォルム
    // (リージョンフォルム等) の特性でだけ説明できる場合は、フォルムの
    // 登録自体が誤りとみて訂正した上で帰属する (プレート同定は同名
    // フォルムを区別できず、見せ合い側でも通常種として登録される
    // ことがある。実例: 2026-11-22 battle_20261122_070237、キュウコン
    // (アローラ) が通常種で登録され、ゆきふらし が帰属しなかった)
    for (key, sw) in Array(lastSwitchIn) {
        if fieldAbilityDone[key] == sw.at { continue }
        let parts = key.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { continue }
        let side = String(parts[0]), en = String(parts[1])
        guard side == "p2" else { continue }
        for ab in [weatherAb[logFieldWeather], terrainAb[logFieldTerrain]].compactMap({ $0 }) {
            // 場の誰かの現在のフォルムで説明できるなら、その個体が原因
            if lastSlots.values.contains(where: { (speciesAbilityMap[$0.speciesEn] ?? []).contains(ab) }) { continue }
            // 自分の現在のフォルムで持てるなら通常の帰属が担当する
            if (speciesAbilityMap[en] ?? []).contains(ab) { continue }
            guard let entry = speciesDict.first(where: { $0.en == en }) else { continue }
            let cands = formeGroup(entry).filter { $0.en != en && (speciesAbilityMap[$0.en] ?? []).contains(ab) }
            guard cands.count == 1, let newEn = cands.first?.en else { continue }
            var matched = false
            if weatherAb[logFieldWeather] == ab && now.timeIntervalSince(fieldWeatherSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            if terrainAb[logFieldTerrain] == ab && now.timeIntervalSince(fieldTerrainSetAt) < 30 && now.timeIntervalSince(sw.at) < 30 { matched = true }
            let inTurn = switchInTurn[key].map { max($0, 1) }
            if weatherAb[logFieldWeather] == ab && inTurn != nil && inTurn == fieldWeatherSetTurn && fieldSetByMoveTurn != fieldWeatherSetTurn { matched = true }
            if terrainAb[logFieldTerrain] == ab && inTurn != nil && inTurn == fieldTerrainSetTurn && fieldSetByMoveTurn != fieldTerrainSetTurn { matched = true }
            guard matched else { continue }
            correctFormeByAbility(side: side, slot: sw.slot, speciesEn: en, abilityEn: ab)
            fieldAbilityDone["\(side):\(newEn)"] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: newEn, abilityEn: ab)
        }
    }
}

// |-ability| の二重出力抑止 (バナー読みとフィールド帰属が同じ特性を二重に出さない)
func emitAbilityOnce(slot: String, side: String, speciesEn: String, abilityEn: String) {
    let k = "\(side):\(speciesEn):\(abilityEn)"
    if let at = lastAbilityEmit[k], Date().timeIntervalSince(at) < 10 { return }
    lastAbilityEmit[k] = Date()
    emitLog("|-ability|\(slot): \(speciesEn)|\(abilityEn)")
}

// 判明した特性からのフォルム訂正 (相手側のみ。自軍はチーム登録が正のため
// 適用しない)。現在のフォルムでは持ち得ない特性が判明し、同種族の別
// フォルムのうちちょうど 1 つだけが持ち得る場合に、記録をそのフォルム
// へ訂正する。プレート同定は名前テキストの照合で同名フォルムを区別
// できないため、特性が対戦中にフォルムを確定できる唯一の確実な信号に
// なる (実例: 2026-11-21 vs KAM 戦、相手のバクフーンが おみとおし を
// 発動したが通常フォルムで記録されていた。おみとおし はヒスイだけの
// 特性で、タイプも ほのお単 → ほのお/ゴースト に変わるため影響が大きい)。
// 訂正の対象: 場のプレート、状態 (次の state.json 書き出しに反映)、
// 選出の蓄積、プロトコルログの過去行 (見せ合い・交代・この特性行を含む
// この枠のラベル)、人間可読ログの相手側の行
func correctFormeByAbility(side: String, slot: String, speciesEn: String, abilityEn: String) {
    guard side == "p2" else { return }
    // 現在のフォルムでも持ち得る特性なら訂正しない
    if (speciesAbilityMap[speciesEn] ?? []).contains(abilityEn) { return }
    guard let entry = speciesDict.first(where: { $0.en == speciesEn }) else { return }
    let cands = formeGroup(entry).filter { $0.en != speciesEn && (speciesAbilityMap[$0.en] ?? []).contains(abilityEn) }
    guard cands.count == 1, let newEn = cands.first?.en else { return }
    for name in ["oppA", "oppB"] where lastSlots[name]?.speciesEn == speciesEn {
        lastSlots[name]?.speciesEn = newEn
    }
    let oldKey = "\(side):\(speciesEn)", newKey = "\(side):\(newEn)"
    if let st = monStates[oldKey] {
        if monStates[newKey] == nil { monStates[newKey] = st }
        monStates[oldKey] = nil
    }
    oppTeamSeen = oppTeamSeen.map { $0 == speciesEn ? newEn : $0 }
    if oppUnconfirmed.contains(speciesEn) { oppUnconfirmed.remove(speciesEn); oppUnconfirmed.insert(newEn) }
    if fieldSeen[side]?.contains(speciesEn) == true { fieldSeen[side]?.remove(speciesEn); fieldSeen[side]?.insert(newEn) }
    if let sw = lastSwitchIn[oldKey] { lastSwitchIn[newKey] = sw; lastSwitchIn[oldKey] = nil }
    if let ab = revealedAbilities[speciesEn] { revealedAbilities[newEn] = ab; revealedAbilities[speciesEn] = nil }
    if emittedSwitchKeys.contains("\(side):\(speciesEn)") {
        emittedSwitchKeys.remove("\(side):\(speciesEn)")
        emittedSwitchKeys.insert("\(side):\(newEn)")
    }
    renderSlotSpecies[slot] = newEn
    for i in battleLog.indices {
        let f = battleLog[i].split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 3 else { continue }
        if battleLog[i].hasPrefix("|poke|p2|") && f[3] == speciesEn {
            var nf = f; nf[3] = newEn
            battleLog[i] = nf.joined(separator: "|")
        } else if f[2] == "\(slot): \(speciesEn)" {
            var nf = f; nf[2] = "\(slot): \(newEn)"
            if battleLog[i].hasPrefix("|switch|") && nf.count >= 4 { nf[3] = newEn }
            battleLog[i] = nf.joined(separator: "|")
        }
    }
    for i in displayLog.indices {
        if displayLog[i].contains("opposing \(speciesEn)") || displayLog[i].contains("sent out \(speciesEn)") || displayLog[i].contains("withdrew \(speciesEn)") {
            displayLog[i] = displayLog[i].replacingOccurrences(of: speciesEn, with: newEn)
        }
    }
    try? (battleLog.joined(separator: "\n") + "\n").write(to: protocolLogURL, atomically: true, encoding: .utf8)
    try? (displayLog.joined(separator: "\n") + "\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
    if debugMode { print("[reader] 特性 \(abilityEn) の判明によりフォルムを訂正しました: \(speciesEn) -> \(newEn)") }
    fflush(stdout)
}

var lastItemEmit: [String: Date] = [:]   // "side:Species:ItemJa" -> 最後に |-item| を出した時刻

// |-item| の二重出力抑止。同じ持ち物判明が、メッセージ監視とゲーム内ログ画面の
// 両経路から (あるいは OCR ゆれ違いで) 二重に届くことがある
// (実例: 2026-11-20 vs Mark 戦、サーナイトナイトの反応行が 2 行連続で出た)
func emitItemOnce(slot: String, side: String, speciesEn: String, itemJa: String) {
    let k = "\(side):\(speciesEn):\(itemJa)"
    if let at = lastItemEmit[k], Date().timeIntervalSince(at) < 25 { return }
    lastItemEmit[k] = Date()
    emitLog("|-item|\(slot): \(speciesEn)|\(itemJa2En[itemJa] ?? itemJa)")
}

// メガシンカの完了を状態とログに反映する (キーはベース種族のまま)
func completeMega(side: String, baseEn: String, megaEn: String) {
    let key = "\(side):\(baseEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    if monStates[key]?.megaSpecies == megaEn {
        pendingMegaStone[side] = nil
        pendingMegaSpecies[side] = nil
        return
    }
    // megaSpecies への反映は |detailschange| 行の applyEvent が行う
    let slot = slotFor(side: side, speciesEn: baseEn)
    // 場に居ることが確認できていない種族のメガを、別種族が占有して
    // いる枠へ付けることはしない。slotFor は場に無い種族に対して
    // 既定枠 (a 枠) を返すため、そのまま出すと無関係な枠の種族として
    // detailschange が出て、その枠の状態まで巻き込む (実例:
    // 2026-11-22 battle_20261122_071457、交代が未確定だった
    // ムクホークのメガがオオニューラの枠 p1a に付いた)。保留は
    // 維持し、交代の確定後の再試行 (synthesizeMegaIfPending) で
    // 正しい枠に出す
    let megaPlate = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
    if let occ = lastSlots[megaPlate], !sameSpeciesFamily(occ.speciesEn, baseEn) {
        return
    }
    emitLog("|detailschange|\(slot): \(baseEn)|\(megaEn)")
    var megaLine = "|-mega|\(slot): \(baseEn)|\(baseEn)"
    if let stoneJa = pendingMegaStone[side] { megaLine += "|\(itemJa2En[stoneJa] ?? stoneJa)" }
    emitLog(megaLine)
    pendingMegaStone[side] = nil
    pendingMegaSpecies[side] = nil
}

// 反応保留中のメガフォルムを、保留中のストーンで一意に決める
func pendingMegaForme(side: String, baseEn: String) -> String? {
    var cands = speciesDict.filter { $0.en.hasPrefix(baseEn + "-Mega") }
    if cands.count > 1, let stoneJa = pendingMegaStone[side], let last = stoneJa.last {
        let filtered = cands.filter { $0.en.hasSuffix("-Mega-\(last)") }
        if filtered.count == 1 { cands = filtered }
    }
    guard cands.count == 1 else { return nil }
    return cands.first?.en
}

// メガ完了の文を取りこぼした場合の保険: 反応の文は拾えたのに完了の文だけ
// 落ちることがある (実例: 2026-11-20 vs Benn 戦のガブリアス)。
// 反応した時点でメガシンカ自体は確定しているため、その種族が次に技を
// 使う直前 (またはターン境界) に完了を補う
func synthesizeMegaIfPending(side: String, speciesEn: String) {
    guard pendingMegaSpecies[side] == speciesEn else { return }
    guard (monStates["\(side):\(speciesEn)"]?.megaSpecies ?? "").isEmpty else { return }
    guard let me = pendingMegaForme(side: side, baseEn: speciesEn) else { return }
    completeMega(side: side, baseEn: speciesEn, megaEn: me)
}

// 天候・地形の開始が、保留中のメガフォルムのフィールド特性による
// ものなら、メガはその時点で完了しているはずなので、天候行より
// 先に完了を補う (実例: 2026-11-22 battle_20261122_051707、
// ターン1に ひでり の日照しが発生したのに、リザードンの
// detailschange がターン2へずれ込んだ)
func completePendingMegaForField(ability: String) {
    for side in ["p1", "p2"] {
        guard let baseEn = pendingMegaSpecies[side],
              let forme = pendingMegaForme(side: side, baseEn: baseEn),
              let pool = speciesAbilityMap[forme], pool.contains(ability),
              lastSwitchIn["\(side):\(baseEn)"] != nil else { continue }
        completeMega(side: side, baseEn: baseEn, megaEn: forme)
    }
}

// 繰り出しの記録 (天候・フィールド特性の帰属判定に使う)
func recordSwitchIn(side: String, slot: String, speciesEn: String) {
    lastSwitchIn["\(side):\(speciesEn)"] = (slot, Date())
    switchInTurn["\(side):\(speciesEn)"] = currentTurn
    fieldSeen[side, default: []].insert(speciesEn)
    // この交代が出所になって、地形の上書き保留が採用できることがある
    confirmHeldTerrainReplace()
    attributeFieldAbilities()
    // いかくの遡及帰属: プレート確定がメッセージより遅れ、攻撃 -1 の適用時に
    // 繰り出しが未記録だった場合は、記録したこの時点で特性行を出す
    // (実例: 2026-11-20 vs BigGuyMan 戦、ズルズキンの いかく が付かなかった)
    let key = "\(side):\(speciesEn)"
    if let sw = lastSwitchIn[key], intimidateDone[key] != sw.at,
       let pool = speciesAbilityMap[speciesEn], pool.contains("Intimidate") {
        let other = side == "p1" ? "p2" : "p1"
        let now = Date()
        // seq 一致まで要求すると、確定の遅れの間に他の文が処理された
        // 時点で恒常的に外れ、特性行が丸ごと落ちる (実例: 2026-11-22
        // battle_20261122_071457、特性行が 1 行も出なかった)。攻撃
        // 低下の記録が直近 20 秒以内にあれば帰属の根拠として十分
        let hasDrop = recentAtkDrops.contains { $0.key.hasPrefix("\(other):") && now.timeIntervalSince($0.value.at) < 20 }
        if hasDrop {
            intimidateDone[key] = sw.at
            emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Intimidate")  // 判明登録は applyEvent が行う
        }
    }
    // どくびしの吸収: 接地した どくタイプが場に出ると、その側の
    // どくびしは消える (実際の仕様)。タイプと特性プールから確定的に
    // 言える範囲でのみ導出し、ふゆう候補が未判明の種族・ふゆう判明・
    // ふうせん判明の場合は行わない (告知文の経路に任せる)
    if battleHazards[side]?["Toxic Spikes"] != nil,
       let types = pvSpeciesTypes[speciesEn], types.contains("Poison"), !types.contains("Flying") {
        let pool = speciesAbilityMap[speciesEn] ?? []
        var grounded = !pool.contains("Levitate")
        if !grounded {
            let abilityJa = side == "p1" ? (teamEntries[speciesEn]?["ability"] as? String) : revealedAbilities[speciesEn]
            if let abilityJa, abilityJa != "ふゆう" { grounded = true }
        }
        let itemJa = side == "p1" ? (teamEntries[speciesEn]?["item"] as? String) : revealedItems[speciesEn]
        if grounded && itemJa != "ふうせん" {
            emitHazard(side, "Toxic Spikes", start: false)
        }
    }
    // この種族宛てに保留していたランク変化行を、交代行の後に出す
    flushHeldBoosts(forKey: key, slot: slot)
    // 入場特性の効果として保留していた行も、この交代行の後に流す
    flushHeldEntryBoosts()
    // 交代前にシード消費を検知していた場合、かるわざ の発動をここで出す
    if pendingUnburden.remove(key) != nil { noteItemLost(slot: slot, side: side, speciesEn: speciesEn) }
}

var fieldSeen: [String: Set<String>] = ["p1": [], "p2": []]   // その対戦で場に出たことのある種族 (ターン判定の交代可否に使う)

// 場に出ていて生きている数 (プレート名の接頭辞と内部サイドで数える)
func aliveOnFieldCount(_ platePrefix: String, _ side: String) -> Int {
    var n = 0
    for (name, s) in lastSlots where name.hasPrefix(platePrefix) {
        if (monStates["\(side):\(s.speciesEn)"]?.hpPercent ?? s.hpPercent) > 0 { n += 1 }
    }
    return n
}

// 場が 1 体だけの側が「交代要員を残して交代待ち中」かどうか。
// 交代要員がいる間はコマンド選択に入らないため、ターン判定を進めてはいけない。
// 交代要員が尽きた側 (選出 4 体を出し切り控えも残っていない) は
// そのままコマンド選択に入るので、待ちではない。
func awaitingReplacement(_ platePrefix: String, _ side: String) -> Bool {
    if aliveOnFieldCount(platePrefix, side) >= 2 { return false }
    let seen = fieldSeen[side] ?? []
    if seen.count < 4 { return true }   // まだ場に出ていない選出枠が残っている
    let onField = Set(lastSlots.filter { $0.key.hasPrefix(platePrefix) }.map { $0.value.speciesEn })
    return seen.contains { !onField.contains($0) && (monStates["\(side):\($0)"]?.hpPercent ?? 0) > 0 }
}

// どちらかの側が、ひんし交代の要員待ち (場が 1 体で後任が未登録) か
// その側で「ひんしした枠が空いていて、後任がまだ登録されていない」
// 状態か。開幕 (場が揃う前) や、後任がもう残っていない終盤と区別する
// ため、ひんし枠があることと、後任の見込み (未確認の残り枠があるか、
// 体力のある控えがいる) の両方を条件にする
func sideAwaitingReplacement(_ prefix: String, _ side: String) -> Bool {
    if aliveOnFieldCount(prefix, side) >= 2 { return false }
    let slotNames = side == "p1" ? ["p1a", "p1b"] : ["p2a", "p2b"]
    if !slotNames.contains(where: { faintedSlots[$0] != nil }) { return false }
    let seen = fieldSeen[side] ?? []
    if seen.count < 4 { return true }
    let onField = Set(lastSlots.filter { $0.key.hasPrefix(prefix) }.values.map { $0.speciesEn })
    return seen.contains { !onField.contains($0) && (monStates["\(side):\($0)"]?.hpPercent ?? 0) > 0 }
}

func anyAwaitingReplacement() -> Bool {
    sideAwaitingReplacement("mine", "p1") || sideAwaitingReplacement("opp", "p2")
}

// key (変化を受ける側) の反対側で、入場効果の原因になる交代が
// 未確定 (プレート確定待ち、またはひんし交代の要員待ち) か
func entryEffectPending(key: String) -> Bool {
    let otherPrefix = key.hasPrefix("p1") ? "opp" : "mine"
    let otherSide = key.hasPrefix("p1") ? "p2" : "p1"
    return !pendingSwitchSpecies.filter({ $0.key.hasPrefix(otherPrefix) }).isEmpty
        || sideAwaitingReplacement(otherPrefix, otherSide)
        // 開幕は、相手の先発がプレートに読まれる前に特性の効果文が
        // 届くことがある。その間は入場効果が未確定として扱う
        // (実例: 2026-11-22 battle_20261122_091721、いかくの攻撃低下行が
        //  原因の交代行・特性行より先に出た)
        || (currentTurn <= 1 && (fieldSeen[otherSide]?.count ?? 0) < 2)
}
func clearTerrain(stale: Bool = false) {
    if logFieldTerrain.isEmpty { return }
    if stale {
        if debugMode { print("[field] ログ画面の古い地形終了文で現行の地形を消しませんでした: \(logFieldTerrain)") }
        return
    }
    let old = logFieldTerrain
    emitLog("|-fieldend|move: \(old) Terrain")  // 状態への反映は applyEvent が行う
}

// 技そのものが天候・フィールドを張る場合
// 設置物の開始/終了行はこの入口に一本化する。本文側の救済
// (salvageField) とクールダウンキーを共有し、二重に出さない
func emitHazard(_ side: String, _ hazard: String, start: Bool) {
    lastSideCondAt["\(side):\(hazard):\(start ? "start" : "end")"] = Date()
    emitLog("|-\(start ? "sidestart" : "sideend")|\(side)|move: \(hazard)")
}

func clearSideHazards(_ side: String) {
    guard let hz = battleHazards[side] else { return }
    for name in hz.keys.sorted() { emitHazard(side, name, start: false) }
}

func applyMoveField(_ mvJa: String, side: String) {
    // 技で天候・地形を張る場合は、その旨をターンで記録する (交代に
    // よる特性帰属のターン一致判定で、技が原因の開始を交代のせいに
    // しないため)
    if ["あめごい", "にほんばれ", "すなあらし", "ゆきげしき", "さむいギャグ",
        "エレキフィールド", "グラスフィールド", "ミストフィールド", "サイコフィールド"].contains(mvJa) {
        fieldSetByMoveTurn = currentTurn
    }
    // 前の技で確定しなかった設置・解除の保留は、次の技の時点で失効させる
    if let ph = pendingHazard, ph.seq < actionSeq { pendingHazard = nil }
    if let pr = pendingRemoval, pr.seq < actionSeq { pendingRemoval = nil }
    let foe = side == "p1" ? "p2" : "p1"
    switch mvJa {
    case "あめごい": setWeather("Rain", "Rain Dance")
    case "にほんばれ": setWeather("Sun", "Sunny Day")
    case "すなあらし": setWeather("Sand", "Sandstorm")
    case "ゆきげしき", "さむいギャグ": setWeather("Snow", "Snow")
    case "エレキフィールド": setTerrain("Electric")
    case "グラスフィールド": setTerrain("Grassy")
    case "ミストフィールド": setTerrain("Misty")
    case "サイコフィールド": setTerrain("Psychic")
    case "ワイドガード": emitLog("|-sidestart|\(side)|move: Wide Guard")
    // 設置物 (Showdown のサイドコンディションとして扱う)
    case "ステルスロック": emitHazard(foe, "Stealth Rock", start: true)
    case "まきびし": emitHazard(foe, "Spikes", start: true)
    case "どくびし": emitHazard(foe, "Toxic Spikes", start: true)
    case "がんせきアックス":
        // 追加効果の設置は当たった場合のみ。確定は emitLog 側の
        // ダメージ行フックと設置文の救済に任せ、ここでは保留だけ置く
        pendingHazard = (foe, "Stealth Rock", actionSeq)
    case "ねがいごと":
        // 回復は次のターンの終わりに使用側の枠へ届く。発生源の説明
        // (healExplained) が参照するため、使用ターンだけを記録する
        wishSetTurn[side] = currentTurn
    case "こうそくスピン", "キラースピン":
        pendingRemoval = (side, actionSeq)
    case "おかたづけ": clearSideHazards(side)
    case "きりばらい":
        // きりばらいは両側の設置物とフィールドを消す (第9世代仕様)
        clearSideHazards("p1"); clearSideHazards("p2")
        if !logFieldTerrain.isEmpty { emitLog("|-fieldend|move: \(logFieldTerrain) Terrain") }
    case "コートチェンジ":
        let mineHz = battleHazards["p1"] ?? [:], oppHz = battleHazards["p2"] ?? [:]
        clearSideHazards("p1"); clearSideHazards("p2")
        for (name, layers) in oppHz { for _ in 0..<layers { emitHazard("p1", name, start: true) } }
        for (name, layers) in mineHz { for _ in 0..<layers { emitHazard("p2", name, start: true) } }
    default: break
    }
}

// ランク変化の本文パターン (能力変化チップ・特性チップ等、種別を問わず拾う)
// 注意: ゲーム本文の動詞は漢字 (上がった/下がった) が正。以前は平仮名
// (あがった/さがった) だけで照合していたため、漢字で読めた文はすべて
// 素通りして |-message| に落ち、ランク変化が一切ダメ計に反映されなかった
// (実例: 2026-11-20 vs Mark 戦の いかく/ちいさくなる/たくわえる 全件)。
// 能力名はフリガナ+漢字の二重表記 (こうげき攻撃 等) で読めることがある。
// ランク変化文の文法上の主語を返す。能力変化の告知は 1 文 1 主語が
// 原則で、複合主語は「Aと Bの …」の形のときだけ現れる。画面端の
// プレート名や前後の文の断片が混入して無関係な種族名が文中にある
// 場合、その種族にまで変化を付けない (実例: 2026-11-21
// battle_20261121_155801、くだけるよろいの防御低下が、混入した
// イエッサンの名前のためにイエッサン♀にも付いた)
func boostSubjects(in t: String) -> [SpeciesEntry] {
    let found = findAllSpeciesJa(in: t).map { fieldAnchoredSpecies($0) }
    if found.count <= 1 { return found }
    // 最初の能力名より前が主語の領域
    let statWords = ["こうげき", "攻撃", "ぼうぎょ", "防御", "とくこう", "特攻", "とくぼう", "特防",
                     "すばやさ", "素早さ", "めいちゅう", "命中率", "かいひ", "回避率",
                     "コウゲキ", "ボウギョ", "トクコウ", "トクボウ", "スバヤサ", "メイチュウ", "カイヒ"]
    var cut = t.endIndex
    for w in statWords {
        if let r = t.range(of: w), r.lowerBound < cut { cut = r.lowerBound }
    }
    let region = normalize(String(t[..<cut]))
    let foldedRegion = foldDakuten(region)
    let inRegion = found.filter {
        region.contains(normalize($0.ja)) || foldedRegion.contains(foldDakuten(normalize($0.ja)))
    }
    // 複合主語 (「Aと Bの」) のときだけ、領域内の全員を対象にする。
    // 正規化で「と」は「ト」になるため両形を見る。種族名の一部
    // (ドラパルトの「ト」等) と誤認しないよう、2 つの名前の間に
    // 助詞がある場合だけ複合とみなす
    if inRegion.count >= 2 {
        var compound = false
        for i in 0..<(inRegion.count - 1) {
            let a = normalize(inRegion[i].ja), b = normalize(inRegion[i + 1].ja)
            guard let ra = region.range(of: a),
                  let rb = region.range(of: b, range: ra.upperBound..<region.endIndex) else { continue }
            let between = region[ra.upperBound..<rb.lowerBound]
            if between.contains("と") || between.contains("ト") { compound = true }
        }
        if compound { return inRegion }
    }
    // 単独主語: 主語領域に現れる最後の種族だけが文法上の主語
    if let last = inRegion.last { return [last] }
    return found
}

func checkBoostText(text: String, side: String, speciesEn: String, slot: String) {
    if text.contains("あがらない") || text.contains("さがらない") || text.contains("上がらない") || text.contains("下がらない") { return }
    // 小さい「っ」が通常の「つ」に崩れる OCR ゆれも拾う
    // (実例: 2026-11-20「とくぼう特防が上がつた！」が日本語のまま漏れた)
    let up = text.contains("あがった") || text.contains("上がった") || text.contains("あがつた") || text.contains("上がつた")
    let down = text.contains("さがった") || text.contains("下がった") || text.contains("さがつた") || text.contains("下がつた")
    guard up || down else { return }
    let key = "\(side):\(speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // ゲーム内表記は漢字 (攻撃/防御/特攻/特防/素早さ) が正。ひらがな表記も併記する
    // 「防が下がった」のように 2 文字目が落ちる OCR 崩れも拾う
    // (「攻が」「防が」は「攻撃が」「防御が」の部分文字列にはならないため誤爆しない)
    let stats: [(String, String)] = [("こうげき", "atk"), ("攻撃", "atk"), ("攻が", "atk"), ("ぼうぎょ", "def"), ("防御", "def"), ("防が", "def"), ("とくこう", "spa"), ("特攻", "spa"), ("とくぼう", "spd"), ("特防", "spd"), ("すばやさ", "spe"), ("素早さ", "spe"), ("めいちゅう", "acc"), ("命中率", "acc"), ("かいひ", "eva"), ("回避率", "eva"),
                                     ("コウゲキ", "atk"), ("ボウギョ", "def"), ("トクコウ", "spa"), ("トクボウ", "spd"), ("スバヤサ", "spe"), ("メイチュウ", "acc"), ("カイヒ", "eva")]
    // 「がくっと下がった」も 2 段階 (従来は ぐーんと しか見ておらず、がくっと
    // の低下が 1 段階として記録されていた。検証 R1 #32/#88 で検出。
    // がくっと 自体が「がくつと」に崩れた形も 2 段階とする: 検証 R2 #89/#91。
    // ぐーんと の長音が落ちた「ぐんと」も 2 段階とする: 検証 R4 #13/#45)
    var mag = (text.contains("ぐーんと") || text.contains("ぐんと") || text.contains("がくっと") || text.contains("がくつと")) ? 2 : 1
    // つぼをつく は必ず 2 段階上がる。上昇量の文の「ぐーんと」が
    // 読み落ちて 1 段階として記録されるのを、技の文脈で正す
    // (実例: 2026-11-22 battle_20261122_091721 ターン6)
    if up && mag == 1 && lastMoveName == "Acupressure" && Date().timeIntervalSince(lastMoveMsgAt) < 20 { mag = 2 }
    if text.contains("すべての") {
        for (_, code) in stats.prefix(5) { applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: code, delta: up ? mag : -mag) }
        return
    }
    // 文中に現れる能力はすべて適用する (たくわえる の 防御+特防 のように
    // 1 文で 2 つ上がる技があるため、最初の 1 つで打ち切らない)。
    // フリガナ+漢字の二重表記は同一コードとして 1 回だけ数える
    var applied = Set<String>()
    let foldedText = foldDakuten(text)
    for (ja, code) in stats where !applied.contains(code) {
        // 「攻が」「防が」の 1 字落ちフォールバックは「特攻が」「特防が」の
        // 部分文字列でもあるため、特攻/特防の文では使わない
        // (実例: 2026-11-20、サイコキネシスの特防低下に防御低下まで付いた)
        if ja == "攻が" && (text.contains("特攻が") || foldedText.contains("特攻か")) { continue }
        if ja == "防が" && (text.contains("特防が") || foldedText.contains("特防か")) { continue }
        // 濁点ゆれ (スパヤサ等) は両辺を畳んだ形でも照合する (検証 R1)
        guard text.contains(ja) || foldedText.contains(foldDakuten(ja)) else { continue }
        applied.insert(code)
        applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: code, delta: up ? mag : -mag)
    }
}

// ものまねハーブ/サイコアップ等: 対象のランク変化をそのままコピーする
func copyBoosts(fromKey: String, toKey: String, slot: String, speciesEn: String) {
    guard let src = monStates[fromKey]?.boosts else { return }
    if monStates[toKey] == nil { monStates[toKey] = MonState() }
    for stat in ["atk", "def", "spa", "spd", "spe", "acc", "eva"] {
        let target = src[stat] ?? 0
        let cur = monStates[toKey]?.boosts[stat] ?? 0
        if target == cur { continue }
        // 状態への反映は emitLog -> applyEvent が行う (差分行から目標値になる)
        let delta = target - cur
        if delta > 0 { emitLog("|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)") }
        else { emitLog("|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)") }
    }
}

func applyBoost(key: String, slot: String, speciesEn: String, stat: String, delta: Int, viaSalvage: Bool = false) {
    // 同じ文の OCR ゆれ違いの再読で二重に適用しない: 同じ行動・同じターン・
    // 4 秒以内の同一変化 (枠・能力・増減) は再読とみなして捨てる
    // (実例: アーマーキャノンの自己低下といかくの攻撃低下が 2 重に出た)。
    // 別の技による正当な再変化は |move| を挟むため行動番号が変わり、適用される
    let bk = "\(slot)|\(stat)|\(delta)"
    if let lb = lastBoostApply[bk], lb.seq == actionSeq && lb.turn == currentTurn && Date().timeIntervalSince(lb.at) < 4 { return }
    // 経路をまたぐ二重適用の防止: サルベージ層と正規経路が同じ出来事を
    // 別々に拾った場合、逆経路で 25 秒以内に記録済みの同一変化は捨てる
    // (emitItemOnce の 25 秒ウィンドウと同型)。同経路の再変化は対象外
    let pk = "\(key)|\(stat)|\(delta)"
    if let prev = boostPathAt[pk], prev.salvage != viaSalvage, Date().timeIntervalSince(prev.at) < 25 { return }
    lastBoostApply[bk] = (seq: actionSeq, turn: currentTurn, at: Date())
    boostPathAt[pk] = (at: Date(), salvage: viaSalvage)
    let cur = monStates[key]?.boosts[stat] ?? 0
    let nv = max(-6, min(6, cur + delta))
    if nv == cur { return }
    boostTouchedStats.insert("\(key)|\(stat)")
    if stat == "atk" && delta < 0 { recentAtkDrops[key] = (Date(), actionSeq) }
    let line = delta > 0 ? "|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)" : "|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)"
    // 状態への適用は発生時点で applyEvent が行う。行の表示は交代行の後まで
    // 保留することがあるため、追記時は再適用しない (applyNow: false)
    applyEvent(line)
    // 交代行がまだ出ていない種族のランク変化行は、交代行の後に出す
    // (実例: 2026-11-20 vs Vanille 戦、場に出る前の サイコシード 発動行が
    //  繰り出し行より先に出た)。状態への適用は即時に行い、行だけ保留する
    if !emittedSwitchKeys.contains(key) && (monStates[key]?.hpPercent ?? 100) > 0 {
        // 行は出さず変化だけ保留する。枠は交代確定の時点で付け直す
        // (読んだ時点では場にいないため slotFor が既定の a 枠を返し、
        //  実際の枠と食い違う。実例: 2026-11-20、オオニューラの
        //  サイコシード発動行が p1a で出た (実際は p1b))
        heldBoostLines[key, default: []].append((stat, delta, Date()))
    } else if stat == "atk" && delta < 0 && Date().timeIntervalSince(lastMoveMsgAt) > 3
                && entryEffectPending(key: key) {
        // 入場特性 (いかく) の効果とみられる攻撃低下が、原因側の
        // 交代確定より先に届いた場合は、行だけを保留して交代行の
        // 後に流す (状態への適用は上の applyEvent で済んでいる)。
        // 技の文が直近にある場合は技の効果なので保留しない
        // (実例: 2026-11-22 battle_20261122_050512、ボーマンダの
        //  いかくの低下行が交代行・特性行より前に並んだ)
        heldEntryBoosts.append((key: key, line: line, at: Date()))
    } else if heldEntryBoosts.contains(where: { $0.key == key }) && Date().timeIntervalSince(lastMoveMsgAt) > 3 {
        // 入場効果として保留中の個体の後続の変化 (いかくを受けた
        // かちき の特攻上昇など) も、原因の交代行が出るまで一緒に
        // 保留する (片方だけ先に出ると順序が崩れる。実例: 2026-11-22
        // battle_20261122_070237、ミロカロスの攻撃低下と特攻上昇が
        // キュウコンとムクホークの交代行より前に並んだ)
        heldEntryBoosts.append((key: key, line: line, at: Date()))
    } else {
        emitLog(line, applyNow: false)
    }
    // 地形シードの消費: 対応する地形が出ているとき、その地形のシードが
    // 上げる能力が +1 されたらシードを消費したとみなす (持ち物がその
    // シードだと分かっている場合のみ)。消費が確定すれば かるわざ の判定へ
    let seedFor: [String: (item: String, stat: String)] = ["Psychic": ("サイコシード", "spd"), "Misty": ("ミストシード", "spd"), "Electric": ("エレキシード", "def"), "Grassy": ("グラスシード", "def")]
    if delta == 1, let sd = seedFor[logFieldTerrain], sd.stat == stat {
        let sdSide = String(key.prefix(2))
        let knownItem = sdSide == "p1" ? (teamEntries[speciesEn]?["item"] as? String) : revealedItems[speciesEn]
        if knownItem == sd.item {
            if emittedSwitchKeys.contains(key) { noteItemLost(slot: slot, side: sdSide, speciesEn: speciesEn) }
            else { pendingUnburden.insert(key) }
        } else if !viaSalvage, knownItem == nil, sdSide == "p2", !itemLostActive.contains(key),
                  emittedSwitchKeys.contains(key) {
            // 持ち物が未判明の相手についても、地形シードの発動としか
            // 読めない上昇 (入場直後か、地形が張られた直後に起きて、
            // 本人の技による上昇ではない) は、そのシードを持って
            // いたことの判明として記録する。ゲーム内ではシードの
            // 発動が表示され、対戦ログ上も確定情報として扱われるが、
            // 従来は持ち物が判明済みの場合しか記録しておらず、推定へ
            // 判明情報が届かなかった (実例: 2026-11-22
            // battle_20261122_054802、イエッサンのサイコシードと
            // オオニューラのグラスシード)。自軍の持ち物は登録
            // データで判明しているため、対象は相手のみ
            let justEntered = lastSwitchIn[key].map { Date().timeIntervalSince($0.at) < 15 } ?? false
            let terrainFresh = Date().timeIntervalSince(fieldTerrainSetAt) < 15
            let ownMove = lastMoveLabel == "\(slot): \(speciesEn)" && Date().timeIntervalSince(lastMoveMsgAt) < 20
            if (justEntered || terrainFresh) && !ownMove {
                emitItemOnce(slot: slot, side: sdSide, speciesEn: speciesEn, itemJa: sd.item)
                noteItemLost(slot: slot, side: sdSide, speciesEn: speciesEn)
            }
        }
    }
}

// 保留中のランク変化行を出す (その種族の交代行が出たとき / 時間切れのとき)。
// 枠は出す時点で付け直す (保留した時点の枠は当てにならないため)
func boostLine(slot: String, speciesEn: String, stat: String, delta: Int) -> String {
    delta > 0 ? "|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)" : "|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)"
}

func flushHeldBoosts(forKey key: String, slot: String) {
    guard let arr = heldBoostLines.removeValue(forKey: key) else { return }
    let speciesEn = String(key.dropFirst(3))
    for h in arr { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta), applyNow: false) }
}

// 入場特性の効果として保留したランク変化行を流す。先に いかく の
// 帰属を試すことで、交代行 → 特性行 → 低下行 の順に並べる
func flushHeldEntryBoosts() {
    if heldEntryBoosts.isEmpty { return }
    let held = heldEntryBoosts
    heldEntryBoosts = []
    for ts in Set(held.map { String($0.key.prefix(2)) }) { attributeIntimidate(targetSide: ts) }
    for h in held { emitLog(h.line, applyNow: false) }
}

func flushHeldBoostsTimeout() {
    let cap: TimeInterval = anyAwaitingReplacement() ? 20 : 6
    if heldEntryBoosts.contains(where: { Date().timeIntervalSince($0.at) > cap }) { flushHeldEntryBoosts() }
    if heldBoostLines.isEmpty { return }
    let now = Date()
    for k in Array(heldBoostLines.keys) {
        guard let arr = heldBoostLines[k] else { continue }
        // 交代確定はアニメーションの都合で 1 ターン分遅れることがある
        // (実例: 2026-11-20、4 秒で時間切れになり交代行より先に出た)。
        // フィールド特性の帰属窓と同じ 30 秒まで待つ
        let ready = arr.filter { now.timeIntervalSince($0.at) > 30 }
        if ready.isEmpty { continue }
        let keep = arr.filter { now.timeIntervalSince($0.at) <= 30 }
        if keep.isEmpty { heldBoostLines[k] = nil } else { heldBoostLines[k] = keep }
        let speciesEn = String(k.dropFirst(3))
        let slot = slotFor(side: String(k.prefix(2)), speciesEn: speciesEn)
        for h in ready { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta), applyNow: false) }
    }
}

// 天候・フィールドの開始/終了の本文パターン。
// fromLogScreen=true の文は過去のエントリの再読であり得るため、setter 側で
// 現行の状態を上書きしない (setTerrain/setWeather の stale 引数を参照)
@discardableResult
func checkFieldText(text: String, fromLogScreen: Bool = false) -> Bool {
    // フィールドの終了文 (実機の文面は漢字混じり。OCR 崩れにも耐えるよう緩く照合する)
    if (text.contains("不思議") || text.contains("フィールド")) && (text.contains("なくな") || text.contains("消え") || text.contains("きえ") || text.contains("きれ")) { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("霧が") && text.contains("はれた") { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("電気が") && (text.contains("消えた") || text.contains("消え去った")) { clearTerrain(stale: fromLogScreen); return true }
    if text.contains("草が") && (text.contains("なくな") || text.contains("消え") || text.contains("きえ")) { clearTerrain(stale: fromLogScreen); return true }
    // トリックルーム (地形・天候とは別枠のフィールド効果)。開始文の
    // 濁点崩れ (ゆがめた -> ゆかめた) も拾う (実例: 2026-11-22
    // battle_20261122_071457、開始行が出ず告知文が未翻訳で残った)
    if text.contains("時空") && (foldDakuten(text).contains("ゆかめ") || text.contains("歪め")) {
        if !logTrickRoom { emitLog("|-fieldstart|move: Trick Room") }
        return true
    }
    if (text.contains("ゆがみ") || text.contains("時空")) && (text.contains("戻った") || text.contains("もどった")) {
        // 継続ターンの管理側が先に終了行を出していた場合 (logTrickRoom
        // が既に落ちている) も、文自体は消費する (実例: 2026-11-21
        // battle_20261121_233243、|-fieldend| の直後に同じ文が
        // |-message| として残り、二重に表示された)
        if logTrickRoom { emitLog("|-fieldend|move: Trick Room") }
        return true
    }
    // フィールドの開始文 (特性サージ系は種族名・特性名が出ず、この文だけが出る。
    // 「足下が不思議な感じになった」はサイコフィールド専用の文。
    // 「感じになった」はこの文にしか出ないため、足下・不思議が OCR 崩れ
    // しても拾う (実例: 2026-11-20「下か不態議な感じになった！」の漏れ)。
    // ただし「感じ+なった」だけでは広すぎるため、地形文らしい断片
    // (不思議/議/足下/下が/下か) の併存を必須にする)
    if text.contains("感じ") && text.contains("なった") && (text.contains("不思議") || text.contains("議") || text.contains("足下") || text.contains("下が") || text.contains("下か")) { setTerrain("Psychic", via: text, stale: fromLogScreen); return true }
    if text.contains("足下が") && text.contains("不思議な感じに") { setTerrain("Psychic", via: text, stale: fromLogScreen); return true }
    if (text.contains("足下に") || text.contains("足下が")) && text.contains("電気が") && text.contains("かけめぐ") { setTerrain("Electric", via: text, stale: fromLogScreen); return true }
    // 「おいしげ」はグラスフィールドの開始文にしか出ないため、それ
    // だけで拾う (実例: 2026-11-21 battle_20261121_233243、実文が
    // 「定下に草かおいしげった！」と崩れ、足下・草が の両アンカーが
    // 外れて開始行が欠落した)
    if text.contains("おいしげ") { setTerrain("Grassy", via: text, stale: fromLogScreen); return true }
    if (text.contains("足下に") || text.contains("足下が") || text.contains("足元")) && text.contains("草が") && (text.contains("生い茂") || text.contains("おいしげ") || text.contains("しげった") || text.contains("茂った")) { setTerrain("Grassy", via: text, stale: fromLogScreen); return true }
    if text.contains("足下が") && text.contains("霧に") && text.contains("包まれ") { setTerrain("Misty", via: text, stale: fromLogScreen); return true }
    // 天候の終了文 (晴れの実機文面は「日差しが元に戻った！」。
    // 『弱く』だけを条件にしていたため実機の文面では成立せず、晴れが
    // 解除されないまま残った。実例: 2026-11-21 battle_20261121_155801
    // 「ひざ日差しが元に戻った！」— 先頭に読みの重複が付いた崩れでも
    // 『戻った』で拾う)
    if (text.contains("日差し") || text.contains("ひざし")) && (text.contains("戻った") || text.contains("もどった") || text.contains("弱く")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("雨") && (text.contains("やんだ") || text.contains("止んだ") || text.contains("上がった")) { clearWeather(stale: fromLogScreen); return true }
    if (text.contains("あめ") && (text.contains("やんだ") || text.contains("おさまった"))) { clearWeather(stale: fromLogScreen); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("おさま") || text.contains("弱ま")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("雪") && (text.contains("やんだ") || text.contains("止んだ")) { clearWeather(stale: fromLogScreen); return true }
    if text.contains("ゆき") && text.contains("やんだ") { clearWeather(stale: fromLogScreen); return true }
    // 天候の開始文 (実機の文面: 「日差しが強くなった」「雨が降り始めた」等。
    // 従来は ひざし/あめ 等の平仮名だけで照合しており、漢字表記に一致せず
    // ひでり等の天候を拾えていなかった)
    if (text.contains("日差し") || text.contains("ひざし")) && text.contains("強く") { setWeather("Sun", "Sunny Day", via: text, stale: fromLogScreen); return true }
    if text.contains("雨") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Rain", "Rain Dance", via: text, stale: fromLogScreen); return true }
    if text.contains("あめ") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Rain", "Rain Dance", via: text, stale: fromLogScreen); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("吹き始") || text.contains("吹き荒") || text.contains("ふきあれ")) { setWeather("Sand", "Sandstorm", via: text, stale: fromLogScreen); return true }
    if text.contains("雪") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Snow", "Snow", via: text, stale: fromLogScreen); return true }
    if text.contains("ゆき") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Snow", "Snow", via: text, stale: fromLogScreen); return true }
    if text.contains("フィールド") && text.contains("ひろが") {
        for (ja, en) in [("エレキ", "Electric"), ("グラス", "Grassy"), ("ミスト", "Misty"), ("サイコ", "Psychic")] where text.contains(ja) {
            setTerrain(en, via: text, stale: fromLogScreen)
            return true
        }
    }
    return false
}

// 画面上部のフィールド状態バー (ログ画面ヘッダ・様子を見る等) から現在値を取得する。
// OCR で複数ボックスに割れても拾えるよう、帯のテキストを連結してから照合する。
// 上部バーの天候読みの保留状態 (誤読対策の連続確認用。scanFieldHeader 参照)
var headerWeatherPending: (ui: String, logName: String, count: Int, lastAt: Date) = (ui: "", logName: "", count: 0, lastAt: Date.distantPast)

func scanFieldHeader(_ boxes: [OcrBox]) {
    let joined = boxes.filter { $0.cy < 0.09 }.map { $0.text }.joined(separator: " ")
    if joined.isEmpty { return }
    for (ja, en) in [("グラスフィールド", "Grassy"), ("エレキフィールド", "Electric"), ("サイコフィールド", "Psychic"), ("ミストフィールド", "Misty")] where joined.contains(ja) {
        if logFieldTerrain != en {
            setTerrain(en)
            // バー読みが根拠の採用は、次回の切り分け用に根拠テキストごと残す
            debugCapture(kind: "header_terrain", key: "header_terrain:\(en)", rawText: joined,
                         detail: ["source": "scanFieldHeader", "text": joined])
        }
    }
    // 天候は、上部バーの一過性の誤読だけで幻の天候になった実例が続いた
    // ため (2026-11-20 の幻の晴れ、2026-11-21 battle_20261121_132153 の
    // 幻の雨。どちらも発生源のポケモンは場に出ていない)、バー読み単独
    // では即採用せず、10 秒以内に 2 回続けて同じ天候が読めたときだけ
    // 採用する。本物の天候表示は継続して画面に出るため 1 フレーム分
    // 遅れるだけで済み、告知文や特性・技からの採用は従来どおり即時。
    // 採用したときは根拠テキストをデバッグ情報に残し、次回は経路を
    // 特定できるようにする
    let hit: (ui: String, logName: String)?
    if joined.contains("にほんばれ") { hit = ("Sun", "Sunny Day") }
    else if joined.contains("すなあらし") { hit = ("Sand", "Sandstorm") }
    else if joined.contains("あめ") && joined.contains("状態") { hit = ("Rain", "Rain Dance") }
    else if joined.contains("ゆき") && joined.contains("状態") { hit = ("Snow", "Snow") }
    else { hit = nil }
    guard let hit else { return }
    if logFieldWeather == hit.ui {
        headerWeatherPending = (ui: "", logName: "", count: 0, lastAt: Date.distantPast)
        return
    }
    let now = Date()
    if headerWeatherPending.ui == hit.ui && now.timeIntervalSince(headerWeatherPending.lastAt) <= 10 {
        headerWeatherPending.count += 1
        headerWeatherPending.lastAt = now
    } else {
        headerWeatherPending = (ui: hit.ui, logName: hit.logName, count: 1, lastAt: now)
        return
    }
    if headerWeatherPending.count >= 2 {
        headerWeatherPending = (ui: "", logName: "", count: 0, lastAt: Date.distantPast)
        setWeather(hit.ui, hit.logName)
        debugCapture(kind: "header_weather", key: "header_weather:\(hit.ui)", rawText: joined,
                     detail: ["source": "scanFieldHeader", "text": joined])
    }
}

func scanFieldFromScreen(image: CGImage) {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 0.10)
    scanFieldHeader(boxes)
}
// チップ名は normalize (ひらがな→カタカナ変換) した形で照合する。
// 生の名前と比べると「ひんし」のような仮名チップが永遠に一致しないため。
let logChipByNorm: [String: String] = {
    var d: [String: String] = [:]
    for c in logChips where d[normalize(c)] == nil { d[normalize(c)] = c }
    return d
}()

func asciiDigits(_ s: String) -> String {
    var out = ""
    for ch in s {
        if let v = ch.unicodeScalars.first, (0xFF10...0xFF19).contains(v.value),
           let a = UnicodeScalar(v.value - 0xFEE0) {
            out.append(Character(a))
        } else {
            out.append(ch)
        }
    }
    return out
}

// 自分プレートの HP 表記 1ボックス分を解釈する。
// 実機 OCR (2026-11-20 の --debug 実測) では "145/145" が次のように化ける:
//   "1457145" (スラッシュが 7 に化ける), "177mzr" (スラッシュ以降が文字化け),
//   "145/145" (正常)。タイマー "06:29" を HP と誤認しないための除外も含む。
// knownMax: 判明済みの最大HP (対戦中の記録 or チーム登録の実数値)。現在値だけ
// 読めた場合に割合を復元するために使う。
func parseMineHPText(_ text: String, knownMax: Int?) -> (pct: Int, cur: Int, max: Int?)? {
    func pct(_ c: Int, _ m: Int) -> Int { max(0, min(100, Int((Double(c) / Double(m) * 100).rounded()))) }
    // 1) スラッシュ形式 (全角含む)。最大が小さいものは選出画面の「0/4」等の誤認
    //    防止のため除外するが、ヌケニンの 1/1 だけは例外として通す
    let slashed = text.replacingOccurrences(of: "／", with: "/")
    if let r = slashed.range(of: #"(\d+)\s*/\s*(\d+)"#, options: .regularExpression) {
        let parts = slashed[r].split(separator: "/").map { Int($0.trimmingCharacters(in: .whitespaces)) ?? -1 }
        if parts.count == 2 && (parts[1] >= 10 || parts[1] == 1) && parts[0] <= parts[1] {
            return (pct(parts[0], parts[1]), parts[0], parts[1])
        }
    }
    if text.contains(":") || text.contains("：") { return nil }  // 時刻・タイマー表示は HP ではない
    if text.contains("Lv") || text.contains("レベル") { return nil }  // レベル表記 (50) を現在値と誤認しない
    // 2) 数字が連結して読まれた場合: スラッシュ消失 (連結) と
    //    スラッシュの数字化 (1文字置換) の両方で、桁数のバランスする
    //    分割 (現在値/最大値) を探し、現在値が最大の候補を採る
    let digits = asciiDigits(text).filter { $0.isNumber && $0.isASCII }
    let rest = asciiDigits(text).filter { !($0.isNumber && $0.isASCII) && !$0.isWhitespace }
    if rest.isEmpty && (4...7).contains(digits.count) {
        let arr = Array(digits)
        var bestSplit: (Int, Int)? = nil
        func consider(_ c: Int, _ m: Int) {
            guard m >= 30 && m <= 500 && c <= m else { return }
            if bestSplit == nil || c > bestSplit!.0 { bestSplit = (c, m) }
        }
        for i in 1..<arr.count where abs(i - (arr.count - i)) <= 1 {
            if let c = Int(String(arr[..<i])), let m = Int(String(arr[i...])) { consider(c, m) }
        }
        for i in 1..<(arr.count - 1) where abs(i - (arr.count - 1 - i)) <= 1 {
            if let c = Int(String(arr[..<i])), let m = Int(String(arr[(i + 1)...])) { consider(c, m) }
        }
        if let (c, m) = bestSplit { return (pct(c, m), c, m) }
    }
    // 3) 区切りが空白・記号で読まれた数字ペア ("137 137", "137-137")
    let groups = numberGroups(text)
    if groups.count == 2 && groups[1] >= 30 && groups[0] >= 10 && groups[0] <= groups[1] && !text.contains("%") {
        return (pct(groups[0], groups[1]), groups[0], groups[1])
    }
    // 3b) スラッシュが最大値の先頭桁と融合して 1 文字に化けた場合
    // (例: "150m71" — "/1" が "m" になった読み)。ペアの後半が現在値
    // より小さい場合だけ、最大値の先頭桁を補って解釈する。既知の
    // 最大値と一致する補完を採り、既知値が無ければ成り立つ最小の
    // 補完を採る (実例: 2026-11-22 battle_20261122_071457、
    // ムクホークの 150/171 が読めず 65 秒間ヒットしなかった)
    if groups.count == 2 && groups[0] >= 10 && groups[1] >= 10 && groups[0] > groups[1] && !text.contains("%") {
        var place = 1
        for _ in 0..<String(groups[1]).count { place *= 10 }
        for p in 1...4 {
            let m = p * place + groups[1]
            if m >= groups[0] && m <= 500 && (knownMax == nil || m == knownMax) {
                return (pct(groups[0], m), groups[0], m)
            }
        }
    }
    // 4) 現在値だけ読めた場合: 判明済みの最大HP から割合を復元する
    // (1 桁の数字はカウントダウン等の UI 要素であることが多く、現在値とはみなさない。
    //  スラッシュ形式で読めた場合 (パターン 1) は 1 桁でも正規の読みとして通る)
    if groups.count == 1, let km = knownMax, km > 0, groups[0] >= 10 && groups[0] <= km {
        return (pct(groups[0], km), groups[0], km)
    }
    return nil
}

// 文字列中の数字グループを順に取り出す (例: "137 137" -> [137, 137])
func numberGroups(_ s: String) -> [Int] {
    var out: [Int] = []
    var cur = ""
    for ch in asciiDigits(s) {
        if ch.isNumber { cur.append(ch) }
        else if !cur.isEmpty { if let v = Int(cur) { out.append(v) }; cur = "" }
    }
    if !cur.isEmpty, let v = Int(cur) { out.append(v) }
    return out
}

// ログ画面のターン番号を探す (「ターン3」「3ターン」「ターン|3」の分割も拾う)
func detectLogTurn(_ boxes: [OcrBox]) -> Int? {
    let top = boxes.filter { $0.cy < 0.26 }
    for b in top {
        if let g = regexGroups(#"ターン\s*(\d+)"#, asciiDigits(b.text)), g.count >= 2, let n = Int(g[1]) { return n }
        if let g = regexGroups(#"(\d+)\s*ターン"#, asciiDigits(b.text)), g.count >= 2, let n = Int(g[1]) { return n }
    }
    for b in top where normalize(b.text).contains("ターン") {
        for o in top where o.text != b.text && abs(o.cy - b.cy) < 0.03 {
            let t = asciiDigits(o.text).trimmingCharacters(in: .whitespaces)
            if !t.isEmpty && t.allSatisfy({ $0.isNumber }), let n = Int(t) { return n }
        }
    }
    return nil
}

struct LogChipHit { let label: String; let index: Int; let box: OcrBox; let ownText: String }

// カテゴリチップを探す。完全一致のほか、チップと本文が 1 ボックスに
// 結合して読まれた場合 (先頭がチップ名) も拾う
func findLogChips(_ boxes: [OcrBox]) -> [LogChipHit] {
    var hits: [LogChipHit] = []
    for (i, b) in boxes.enumerated() {
        if b.x0 < 0.05 || b.x0 > 0.50 { continue }
        let nt = normalize(b.text)
        if let label = logChipByNorm[nt] {
            hits.append(LogChipHit(label: label, index: i, box: b, ownText: ""))
            continue
        }
        for (normLabel, label) in logChipByNorm where nt.hasPrefix(normLabel) && nt.count > normLabel.count {
            hits.append(LogChipHit(label: label, index: i, box: b, ownText: b.text))
            break
        }
    }
    return hits.sorted { $0.box.cy < $1.box.cy }
}

// エントリの左右 (相手=p2/自分=p1)。本文の「相手の」が最も確実で、
// 無ければチップ文字の外側 (チップ地色) の赤みで判定する
func logChipSide(_ buf: (data: [UInt8], w: Int, h: Int), _ chip: OcrBox, _ text: String) -> String {
    if text.contains("相手の") { return "p2" }
    if text.contains("味方") || text.contains("自分") { return "p1" }
    var diffs: [Int] = []
    for (fx, fy) in [(chip.x0 - 0.014, chip.cy), (chip.x1 + 0.014, chip.cy),
                     (chip.cx, chip.y0 - 0.012), (chip.cx, chip.y1 + 0.012)] {
        let px = min(buf.w - 1, max(0, Int(fx * Double(buf.w))))
        let py = min(buf.h - 1, max(0, Int(fy * Double(buf.h))))
        let i = (py * buf.w + px) * 4
        diffs.append(Int(buf.data[i]) - Int(buf.data[i + 2]))
    }
    diffs.sort()
    return diffs[diffs.count / 2] > 40 ? "p2" : "p1"
}

func parseLogScreen(image: CGImage) -> Bool {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    let chipHits = findLogChips(boxes)
    let turnFound = detectLogTurn(boxes)
    // ログ画面とみなす条件: ターン表示がある、またはチップが 3 件以上ある
    // (様子を見る等の画面で「特性」だけ拾って誤判定しないため)
    guard turnFound != nil || chipHits.count >= 3 else { return false }
    let tn = turnFound ?? max(currentTurn, 1)
    if debugMode {
        if debugMode { print("ログ画面診断: ターン=\(turnFound.map { "\($0)" } ?? "不明 (\(tn) として処理)") チップ=\(chipHits.count)件") }
    }
    if !logStarted || winLogged { startBattleLog() }
    scanFieldHeader(boxes)
    if tn > currentTurn {
        currentTurn = tn
        emitLog("|turn|\(tn)")
        recordTurnEvidence(turn: tn, path: "log_screen", image: image, extra: ["chips": chipHits.count])
    }
    let buf = makeFullBuffer(image)
    let chipIdx = Set(chipHits.map { $0.index })
    for (i, hit) in chipHits.enumerated() {
        let chip = hit.box
        let upper = chip.cy - 0.055
        let lower = i + 1 < chipHits.count ? (chip.cy + chipHits[i + 1].box.cy) / 2 : chip.cy + 0.11
        var texts = boxes.enumerated().filter { (j, b) in
            !chipIdx.contains(j) && b.x0 > chip.x0 + 0.01 && b.cy >= upper && b.cy < lower
        }.map { $0.element }
        .sorted { ($0.cy, $0.x0) < ($1.cy, $1.x0) }
        .map { $0.text }
        if !hit.ownText.isEmpty { texts.insert(hit.ownText, at: 0) }
        let joined = texts.joined(separator: " ")
        if joined.isEmpty {
            if debugMode { print("  [\(hit.label)] 本文が見つかりません") }
            continue
        }
        let key = "T\(tn)|\(hit.label)|\(normalize(joined))"
        if logSeenEntries.contains(key) { continue }
        logSeenEntries.insert(key)
        let side = logChipSide(buf, chip, joined)
        if debugMode { print("  [\(hit.label)] side=\(side) text=\(joined)") }
        translateLogEntry(chip: hit.label, text: joined, side: side, turn: tn)
    }
    return true
}

// MARK: - 対戦中のメッセージ文の監視
// 画面下部のメッセージウィンドウに出た文を毎フレーム読み、確定した文を
// Showdown 形式に翻訳してログへ流す。技・特性・持ち物の判明、天候/フィールド、
// 状態異常・ランク変化、ひんし、勝敗・降参はここで拾い、
// ゲーム内ログ画面の取り込みがその裏付けになる。
// 翻訳できない文も、文として完結していれば |-message| で残す (表示された文は全部ログ化する)。

var lastMsgNorm = ""
var lastMsgAt = Date.distantPast
var pendingMegaStone: [String: String] = [:]   // side -> 反応メッセージで判明したメガストーン (日本語)
var pendingMegaSpecies: [String: String] = [:]   // side -> 反応メッセージで判明したメガ前の種族 EN
var trainerMine = ""
var trainerOpp = ""

// 文中に現れる種族をすべて出現順に返す (繰り出し・いかく等の複数主語の文用)。
// 長い名前を優先し、重なった一致 (メガゲンガー中のゲンガー等) は除く。
func findAllSpeciesJa(in text: String) -> [SpeciesEntry] {
    let t = normalize(text)
    func scan(_ s: String, _ normOf: (SpeciesEntry) -> String) -> [SpeciesEntry] {
        var covered: [Range<String.Index>] = []
        var found: [(Range<String.Index>, SpeciesEntry)] = []
        for e in speciesDict.filter({ !$0.ja.isEmpty }).sorted(by: { $0.ja.count > $1.ja.count }) {
            let nj = normOf(e)
            var start = s.startIndex
            while start < s.endIndex, let r = s.range(of: nj, range: start..<s.endIndex) {
                if !covered.contains(where: { $0.lowerBound < r.upperBound && r.lowerBound < $0.upperBound }) {
                    found.append((r, e))
                    covered.append(r)
                }
                start = r.upperBound
            }
        }
        return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { $0.1 }
    }
    let exact = scan(t) { normalize($0.ja) }
    if !exact.isEmpty { return exact }
    // 濁点ゆれで全滅した場合だけ、両辺を畳んだ形で再照合する (検証 R2)。
    // foldDakuten は 1 文字→1 文字の置換なので範囲の位置は変わらない
    return scan(foldDakuten(t)) { foldDakuten(normalize($0.ja)) }
}

// 編集距離 (緩い種族名照合用)
func editDistance(_ a: [Character], _ b: [Character]) -> Int {
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }
    var prev = [Int](0...b.count)
    var cur = [Int](repeating: 0, count: b.count + 1)
    for i in 1...a.count {
        cur[0] = i
        for j in 1...b.count {
            let cost = a[i - 1] == b[j - 1] ? 0 : 1
            cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
        }
        swap(&prev, &cur)
    }
    return prev[b.count]
}

// 種族名の緩い照合: 完全一致が無いときだけ使う。OCR の 1〜2 文字崩れ
// (例: ミロカロス -> 三ロカロス) を、助詞 (ノ/ハ/ニ/ガ/ヲ) の直前にある
// 窓との編集距離で拾う。moveStart は正規化テキスト上で助詞の次の位置
// (= 技名の開始位置) で、崩れた名前でも技名を切り出せるよう返す。
// 候補はバイグラム共有で事前に絞る (インタプリタ実行でも重くしないため)。
func findSpeciesJaLoose(in text: String) -> (entry: SpeciesEntry, moveStart: Int)? {
    let chars = Array(normalize(text))
    if chars.count < 3 { return nil }
    let particles: Set<Character> = ["ノ", "ハ", "ニ", "ガ", "ヲ"]
    var textBigrams = Set<String>()
    var textChars = Set<Character>()
    for i in 0..<chars.count {
        textChars.insert(chars[i])
        if i + 1 < chars.count { textBigrams.insert(String([chars[i], chars[i + 1]])) }
    }
    var best: (entry: SpeciesEntry, dist: Int, len: Int, moveStart: Int)? = nil
    for e in speciesDict where !e.ja.isEmpty {
        let ja = Array(normalize(e.ja))
        let L = ja.count
        if L < 3 || L > chars.count { continue }
        if L >= 4 {
            var shares = false
            for i in 0..<(L - 1) where textBigrams.contains(String([ja[i], ja[i + 1]])) { shares = true; break }
            if !shares { continue }
        } else if ja.filter({ textChars.contains($0) }).count < 2 { continue }
        let maxDist = L <= 5 ? 1 : 2
        for start in 0..<chars.count {
            for wlen in [L - 1, L, L + 1] where wlen >= 2 && start + wlen <= chars.count {
                let after = start + wlen
                if after < chars.count && !particles.contains(chars[after]) { continue }
                let d = editDistance(Array(chars[start..<(start + wlen)]), ja)
                if d <= maxDist && (best == nil || d < best!.dist || (d == best!.dist && L > best!.len)) {
                    best = (e, d, L, after + 1)
                }
            }
        }
    }
    guard let b = best else { return nil }
    return (b.entry, b.moveStart)
}

// ランク変化らしい文か (能力名 + 上がった/下がった を含む)
// MARK: - サルベージ層 (部分救済)
// 翻訳に失敗した文でも、断片から確度の高い信号だけを拾って状態に反映する
// 共通処理。拾うのは: (1) 主語の種族が場の中で一意に定まるランク変化、
// (2) 種族に依存しない場の状態、(3) 対象が一意な状態異常、(4) 対象が
// 一意な持ち物の消費。種族が一意でない・方向や量が確定しないものは
// 推測で入れない。状態を更新した場合は対応するプロトコル行も出し、
// ログと state.json の内容を一致させる

// 救済の主語解決: 本文の種族名 (崩れは loose 照合まで) が場の 1 枠に
// 一意に対応するときだけ返す。同種族が両サイドにいる場合は定まらない
func salvageSubject(in t: String) -> (side: String, slot: String, speciesEn: String)? {
    let sp0 = findSpeciesJa(in: t) ?? findSpeciesJaLoose(in: t)?.entry
    guard let sp0 else { return nil }
    let sp = anchoredSpeciesForText(sp0, text: t)
    let hits = lastSlots.filter { $0.value.speciesEn == sp.en }
    guard hits.count == 1, let plate = hits.first else { return nil }
    let side = plate.key.hasPrefix("mine") ? "p1" : "p2"
    return (side, slotFor(side: side, speciesEn: sp.en), sp.en)
}

func salvageBoost(in t: String) -> Bool {
    // 否定文 (もう上がらない等) では発火しない
    if t.contains("上がらない") || t.contains("あがらない") || t.contains("下がらない") || t.contains("さがらない") { return false }
    let up = t.contains("上がった") || t.contains("上がつた") || t.contains("あがった") || t.contains("あがつた")
    let down = t.contains("下がった") || t.contains("下がつた") || t.contains("さがった") || t.contains("さがつた")
    guard up != down else { return false }  // 方向が確定しないものは入れない
    // 「目一杯上がった」は上限まで = 量が文から確定しないため入れない
    if t.contains("目一杯") || t.contains("めいっぱい") { return false }
    // 能力名 (特攻・特防を先に見る: 「特攻」は「攻撃」を含むため)
    let stats: [(String, String)] = [("特攻", "spa"), ("とくこう", "spa"), ("トクコウ", "spa"), ("特防", "spd"), ("とくぼう", "spd"), ("トクボウ", "spd"),
                                     ("攻撃", "atk"), ("こうげき", "atk"), ("コウゲキ", "atk"), ("防御", "def"), ("ぼうぎょ", "def"), ("ボウギョ", "def"),
                                     ("素早さ", "spe"), ("すばやさ", "spe"), ("スバヤサ", "spe"), ("命中率", "acc"), ("回避率", "eva")]
    // 濁点ゆれ (スパヤサ等) は両辺を畳んだ形でも照合する (検証 R1)
    let stat = stats.first(where: { t.contains($0.0) })?.1
        ?? stats.first(where: { foldDakuten(t).contains(foldDakuten($0.0)) })?.1
    guard let stat else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    var mag = 1
    if up && (t.contains("ぐーんと") || t.contains("ぐんと")) { mag = 2 }
    if down && (t.contains("がくっと") || t.contains("がくつと")) { mag = 2 }
    let key = "\(subj.side):\(subj.speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    applyBoost(key: key, slot: subj.slot, speciesEn: subj.speciesEn, stat: stat, delta: up ? mag : -mag, viaSalvage: true)
    return true
}

func salvageStatus(in t: String) -> Bool {
    // 状態異常の語 + 付与の手がかり (または回復の なおった) があり、対象が
    // 一意なときだけ、正規の状態処理に委ねる。checkStatusText は現在値と
    // 違うときだけ反映・出力するため、二重に効くことはない
    let hasCode = t.contains("もうどく") || t.contains("どく") || t.contains("やけど") || t.contains("まひ")
        || t.contains("ねむ") || t.contains("こおり") || t.contains("こおった")
    let cured = t.contains("なおった") || t.contains("なおつた")
    let cues = ["おかされた", "あびた", "なった", "なつた", "おった", "おつた", "ついた", "しまった", "しまつた", "ねむった", "ねむつた"]
    guard cured || (hasCode && cues.contains(where: { t.contains($0) })) else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    checkStatusText(text: t, side: subj.side, speciesEn: subj.speciesEn, slot: subj.slot)
    return true
}

func salvageItem(in t: String) -> Bool {
    guard t.contains("食べた") || t.contains("たべた") || t.contains("なくなった") || t.contains("失くなった")
        || t.contains("失った") || t.contains("うしなった") else { return false }
    // きのみ・シード類の名前が本文にあるか (正規化して itemDict の値と照合)
    let nt = normalize(t)
    // 濁点ゆれ (キーのみ→ギーのみ等) は両辺を畳んだ形でも照合する (検証 R2 #17)。
    // 長音落ちまで重なった場合 (サイコシード→サイゴシド) は ッ→ツ+長音落ち
    // まで畳む (検証 R8 #73)。この変換ではアイテム名は全件衝突しない
    let itemFold: (String) -> String = { foldDakuten($0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")).replacingOccurrences(of: "ー", with: "") }
    let itemJa = itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && nt.contains(normalize($0)) })
        ?? itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && foldDakuten(nt).contains(foldDakuten(normalize($0))) })
        ?? itemDict.values.first(where: { ($0.contains("のみ") || $0.contains("シード")) && itemFold(nt).contains(itemFold(normalize($0))) })
    guard let itemJa else { return false }
    guard let subj = salvageSubject(in: t) else { return false }
    let key = "\(subj.side):\(subj.speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    emitItemOnce(slot: subj.slot, side: subj.side, speciesEn: subj.speciesEn, itemJa: itemJa)  // 判明登録は applyEvent が行う
    noteItemLost(slot: subj.slot, side: subj.side, speciesEn: subj.speciesEn)
    return true
}

func salvageField(in t: String, fromLogScreen: Bool = false) -> Bool {
    // 天気・フィールドは正規の照合をそのまま使う (setter は冪等)
    if checkFieldText(text: t, fromLogScreen: fromLogScreen) { return true }
    // サイドコンディションの告知 (種族に依存しない)。開始/終了の語が
    // 明確な場合だけ反映し、重複は lastSideCondAt で抑える (正規経路と共有)
    let scSide = (t.contains("相手") || t.contains("あいて")) ? "p2" : "p1"
    // 設置物の告知。技の検出を取りこぼした場合の受け皿で、開始/終了が
    // 曖昧な文は出さずに消費だけする (本文を |-message| に残さない)
    if t.contains("とがった岩") || t.contains("まきびし") || t.contains("どくびし") {
        let hz = t.contains("とがった岩") ? "Stealth Rock" : (t.contains("どくびし") ? "Toxic Spikes" : "Spikes")
        let start = t.contains("漂") || t.contains("浮か") || t.contains("散らば") || t.contains("ばらまか")
        let end = t.contains("消え") || t.contains("なくな")
        if start != end {
            let k = "\(scSide):\(hz):\(start ? "start" : "end")"
            if Date().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = Date()
                emitLog("|-\(start ? "sidestart" : "sideend")|\(scSide)|move: \(hz)")
            }
        }
        return true
    }
    let conds: [(String, String)] = [("リフレクター", "Reflect"), ("ひかりのかべ", "Light Screen"), ("光の壁", "Light Screen"),
                                     ("オーロラベール", "Aurora Veil"), ("しろいきり", "Mist"), ("白い霧", "Mist"),
                                     ("しんぴのまもり", "Safeguard"), ("神秘の守り", "Safeguard"),
                                     ("追い風", "Tailwind"), ("おいかぜ", "Tailwind")]
    guard let cond = conds.first(where: { t.contains($0.0) }) else { return false }
    let start = t.contains("現れた") || t.contains("現れ") || t.contains("張った") || t.contains("張られた")
        || t.contains("包まれた") || t.contains("つつまれた") || t.contains("覆われた") || t.contains("吹き始") || t.contains("ふきはじ")
        || t.contains("強くなった")  // 壁の告知は「ひかりのかべで特殊に強くなった！」の形 (実例: 2026-11-20 vs Destrock 戦)
    let end = t.contains("消えた") || t.contains("なくなった") || t.contains("消え去った") || t.contains("はれた")
        || t.contains("止ん") || t.contains("やん") || t.contains("終わ")
    guard start != end else { return false }  // 開始か終了か確定しないものは入れない
    let k = "\(scSide):\(cond.1):\(start ? "start" : "end")"
    if Date().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
        lastSideCondAt[k] = Date()
        emitLog("|-\(start ? "sidestart" : "sideend")|\(scSide)|move: \(cond.1)")
    }
    return true
}

// 救済の入口。拾えた (または重複と分かった) 場合は true = 文を消費する。
// allowBoost=false は古いログエントリ用: ランク変化は実況経路に一本化する
// 方針 (translateLogEntry の末尾コメント参照) のため、古いエントリからは
// 適用しない
func salvageFromText(_ text: String, allowBoost: Bool = true, fromLogScreen: Bool = false) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    if salvageField(in: t, fromLogScreen: fromLogScreen) { return true }
    if allowBoost && salvageBoost(in: t) { return true }
    if salvageStatus(in: t) { return true }
    if salvageItem(in: t) { return true }
    return false
}

func isBoostShapedText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    guard t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった") || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた") else { return false }
    if t.contains("あがらない") || t.contains("さがらない") || t.contains("上がらない") || t.contains("下がらない") { return false }
    return ["攻撃", "こうげき", "防御", "ぼうぎょ", "攻が", "防が", "特攻", "とくこう", "特防", "とくぼう", "素早さ", "すばやさ", "命中率", "回避率", "すべての"].contains { t.contains($0) }
}

// 技告知文の断片か (種族名が欠けて解決できず、「〜の<技名の一部>！」だけが
// 残った OCR 崩れ)。技そのものは綺麗な読みで記録済みのはずで、断片側は
// 種族が特定できないため帰属もできない。生文として残さず消費する
// (実例: 2026-11-20 vs Gmoneys 戦「イトの【ーポイス！」)
func isMoveFragmentText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    // 記号と「の」は normalize で落ちる/化けるため、構造判定は生テキストで行う
    guard t.hasSuffix("！") || t.hasSuffix("!") else { return false }
    guard t.contains("の") && normalize(t).count <= 16 else { return false }
    if findSpeciesJa(in: t) != nil { return false }   // 解決できる文は通常経路に任せる
    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") || t.contains("効果は") || t.contains("回復") { return false }
    guard let tail = t.split(separator: "の").last.map(String.init) else { return false }
    // 技名は助詞を含まない短い名詞句。文の形 (助詞入り・長文) は対象外
    if tail.contains("は") || tail.contains("が") || tail.contains("を") || tail.contains("に") { return false }
    let cand = normalize(tail.trimmingCharacters(in: CharacterSet(charactersIn: "！!【】")))
    return cand.count >= 3 && cand.count <= 9
}

// 2 文の類似度 (最長共通部分列 / 短い方)。|-message| の OCR ゆれ重複の判定用
func textSimilarity(_ a: String, _ b: String) -> Double {
    let x = Array(a), y = Array(b)
    if x.isEmpty || y.isEmpty { return 0 }
    var prev = [Int](repeating: 0, count: y.count + 1)
    var cur = [Int](repeating: 0, count: y.count + 1)
    for i in 1...x.count {
        cur[0] = 0
        for j in 1...y.count {
            cur[j] = x[i - 1] == y[j - 1] ? prev[j - 1] + 1 : max(prev[j], cur[j - 1])
        }
        swap(&prev, &cur)
    }
    return Double(prev[y.count]) / Double(min(x.count, y.count))
}

// 特性の発動で天候・フィールドが変わるもの (日本語特性名 -> 反映処理)
func applyAbilityField(_ abJa: String) {
    switch abJa {
    case "あめふらし": setWeather("Rain", "Rain Dance")
    case "ひでり": setWeather("Sun", "Sunny Day")
    case "すなあらし": setWeather("Sand", "Sandstorm")
    case "ゆきふらし": setWeather("Snow", "Snow")
    case "エレキメイカー", "ハドロンエンジン": setTerrain("Electric")
    case "グラスメイカー": setTerrain("Grassy")
    case "ミストメイカー": setTerrain("Misty")
    case "サイコメイカー": setTerrain("Psychic")
    default: break
    }
}

// バトルメッセージ (画面下部の文) を Showdown ログ行に翻訳する。
// 文面パターンは実機動画 (2026-11-20 の2本) で確認したチャンピオンズの実表記に基づく:
//   繰り出し「<相手>は Aと Bを 繰り出した！」「ゆけっ！ A！ B！」
//   メガ反応「(相手の) Xの <ストーン>と <相手>の ゼンブイリングが 反応した！」
//   メガ完了「(相手の) Xは メガXに メガシンカした！」
//   技「(相手の) Xの <技>！」(「つかった」は付かない)
//   保護「Xは サイコフィールドに 守られている！」、効果「(相手の) Xに 効果は いまひとつだ」
//   状態「Xは 毒を あびた！」、状態ダメージ「Xは 毒の ダメージを受けた！」、急所「急所に 当たった！」
//   勝敗「<相手>との 勝負に 負けた！/勝った！」
// 技名の照合は「種族名の直後〜文末」の完全一致のみ (部分一致だと
// 「サイコフィールドに守られている」を技と誤認するため)。
// 技名の緩い照合: 完全一致しない候補を編集距離で照合し、最良が一意なときだけ採用する
// (実例: 「ハイパーポイス」→ ハイパーボイス)
func moveNameLoose(_ cand: String) -> String? {
    guard cand.count >= 3 else { return nil }
    let maxDist = cand.count <= 5 ? 1 : 2
    let ca = Array(cand)
    var bestKey: String? = nil
    var bestDist = Int.max
    var tie = false
    for key in moveNameOrig.keys {
        if abs(key.count - cand.count) > maxDist { continue }
        let d = levenshtein(Array(key), ca)
        if d > maxDist { continue }
        if d < bestDist { bestDist = d; bestKey = key; tie = false }
        else if d == bestDist { tie = true }
    }
    if let bk = bestKey, !tie { return moveNameOrig[bk] }
    // 第2パス: 濁点を畳んだ形同士の編集距離 (シザグロス→シザークロスのように
    // 長音落ち+濁点ゆれが重なると素の距離では届かない。検証 hard R7 #24)。
    // 技名は畳んでも全件衝突しないことを辞書で確認済み。同点は従来通り棄却
    let fc = Array(foldDakuten(cand))
    var fBestKey: String? = nil
    var fBestDist = Int.max
    var fTie = false
    for key in moveNameOrig.keys {
        let fk = foldDakuten(key)
        if abs(fk.count - fc.count) > maxDist { continue }
        let d = levenshtein(Array(fk), fc)
        if d > maxDist { continue }
        if d < fBestDist { fBestDist = d; fBestKey = key; fTie = false }
        else if d == fBestDist { fTie = true }
    }
    if let bk = fBestKey, !fTie { return moveNameOrig[bk] }
    // 第3パス: 長音も落として畳んだ形で照合する (ワンダルム→ワンダールーム
    // のような長音2連落ち対策。検証 最終監査 seed31 #54)。この変換でも
    // 技名は全件衝突しないことを辞書で確認済み。距離は 1 までに絞る
    let stripLong: (String) -> String = { $0.replacingOccurrences(of: "ー", with: "") }
    let dc = Array(stripLong(foldDakuten(cand)))
    var dBestKey: String? = nil
    var dBestDist = Int.max
    var dTie = false
    for key in moveNameOrig.keys {
        let dk = stripLong(foldDakuten(key))
        if abs(dk.count - dc.count) > 1 { continue }
        let d = levenshtein(Array(dk), dc)
        if d > 1 { continue }
        if d < dBestDist { dBestDist = d; dBestKey = key; dTie = false }
        else if d == dBestDist { dTie = true }
    }
    guard let bk = dBestKey, !dTie else { return nil }
    return moveNameOrig[bk]
}

// メガシンカ関連の文 (反応・完了) の側判定。明示の主語 (相手の/味方の)
// が最優先で、無い場合は保留中の反応記録と場の実態から決める。完了文や
// 反応文はログ画面などから再読されることがあり、再読の断片に「相手の」が
// 含まれないと、従来の「無ければ自分側」の判定では相手のメガシンカが
// 自分の枠に誤帰属する (実例: 2026-11-21 vs Toshiro 戦、相手の
// ムクホークの完了文の再読で p1a に幻のメガシンカが出た)
func megaTextSide(_ t: String, baseEn: String) -> String {
    if t.contains("相手の") || t.contains("あいての") { return "p2" }
    if t.contains("味方の") || t.contains("じぶんの") { return "p1" }
    let pend = ["p1", "p2"].filter { pendingMegaSpecies[$0] == baseEn }
    if pend.count == 1 { return pend[0] }
    let inMine = lastSlots["mineA"]?.speciesEn == baseEn || lastSlots["mineB"]?.speciesEn == baseEn
    let inOpp = lastSlots["oppA"]?.speciesEn == baseEn || lastSlots["oppB"]?.speciesEn == baseEn
    if inMine != inOpp { return inMine ? "p1" : "p2" }
    return "p1"
}

func translateBattleMessage(_ text: String) -> Bool {
    let before = battleLog.count
    // 急所の文はダメージ確定 (行の出力) より前に表示されるため、
    // その文のときだけ先行フラッシュを止めて帰属を pending 側に残す
    // (「急所」が OCR 崩れした文も同様に止める)
    let strippedText = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    if !strippedText.contains("急所") && !(strippedText.contains("所に") && (strippedText.contains("当たった") || strippedText.contains("たった")))
        && !strippedText.hasSuffix("に当たった！") && !strippedText.hasSuffix("に当たった!")
        && !strippedText.hasSuffix("にたった！") && !strippedText.hasSuffix("にたった!") { flushPendingDamage() }
    // 照合は空白を除いた形で行う (OCR のボックス分割で空白位置が揺れるため)
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    let nt = normalize(t)
    // ポケモンの詳細画面 (様子を見る) の文は対戦文ではない。画面内の
    // 設定ラベル「つよさの表示」は対戦文には現れないため、これを含む
    // 文は詳細画面の混入として消費だけする (実例: 2026-11-21
    // battle_20261121_234913、詳細画面の「特性 もうか / 持ち物
    // リザードナイトY / つよさの表示 オフ / 戻る」が対戦文の経路に
    // 入り、種族の誤認と既定枠への帰属が起きた)
    if t.contains("つよさの表示") { return true }
    // 勝敗: 「<相手>との 勝負に 負けた！/勝った！」
    // (実機ログでは「勝った」が「勝つた」と OCR 崩れしていたため、
    //  小さい「っ」を通常の「つ」に寄せた形でも判定する)
    let tw = t.replacingOccurrences(of: "っ", with: "つ").replacingOccurrences(of: "ッ", with: "ツ")
    if t.contains("勝負に") && (t.contains("負けた") || tw.contains("勝つた")) {
        if winLogged { return true }   // 同じ勝敗文の再読では出さない
        let won = tw.contains("勝つた")
        var oppName = trainerOpp
        if let r = t.range(of: "との") {
            let n = String(t[..<r.lowerBound])
            if !n.isEmpty && n.count <= 20 { oppName = n }
        }
        // 降参の文が拾えなかった場合の推定: 負けた側に「場に出て倒れて
        // いないポケモンがいる」か「場に出たのが 4 体未満」なら、倒し切って
        // の終了ではあり得ないため降参として扱う (実例: 2026-11-20
        // vs Zycloud 戦、相手に 3 体残して勝敗が確定した)
        if forfeitName == nil {
            let loserSide = won ? "p2" : "p1"
            let entered = fieldSeen[loserSide] ?? []
            let anyAlive = entered.contains { (monStates["\(loserSide):\($0)"]?.hpPercent ?? 100) > 0 }
            if anyAlive || entered.count < 4 {
                forfeitName = won ? (oppName.isEmpty ? "Opponent" : oppName) : (trainerMine.isEmpty ? "You" : trainerMine)
            }
        }
        emitPendingFaints()
        if won { emitLog("|win|\(trainerMine.isEmpty ? "p1" : trainerMine)") }
        else { emitLog("|win|\(oppName.isEmpty ? "p2" : oppName)") }
        if !oppName.isEmpty { trainerOpp = oppName }
        winLogged = true
        archiveCurrentBattle(final: true)
        return true
    }
    if t.contains("あきらめた") {
        if winLogged { return true }   // 同じ勝敗文の再読では出さない
        let oppGaveUp = t.contains("相手") || t.contains("あいて")
        forfeitName = oppGaveUp ? (trainerOpp.isEmpty ? "Opponent" : trainerOpp) : (trainerMine.isEmpty ? "You" : trainerMine)
        emitPendingFaints()
        emitLog("|win|\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        winLogged = true
        archiveCurrentBattle(final: true)
        return true
    }
    // 無操作による対戦終了: 「相手の操作がありませんでした！対戦を終了します！」
    // (実例: 2026-11-20 vs Foxy2905 戦。勝敗文が無いため従来は未保存のまま
    // 終わり、保存も送信もされなかった)。操作しなかった側の負けとして扱う。
    // OCR では文頭に「あいてそうさ」のような重なりゴミが付くことがあるため、
    // 「操作がありません」に部分一致で判定し、どちらの無操作かは
    // 相手/あいて・自分/じぶん の有無で分ける。判別できない場合も
    // 対戦終了として確定保存だけは行う (勝敗行は出さない)
    if t.contains("操作がありません") || (t.contains("対戦を終了します") && t.contains("操作")) {
        if winLogged { return true }
        let oppIdle = t.contains("相手") || t.contains("あいて")
        let mineIdle = t.contains("自分") || t.contains("じぶん")
        emitPendingFaints()
        if oppIdle && !mineIdle {
            forfeitName = trainerOpp.isEmpty ? "Opponent" : trainerOpp
            emitLog("|win|\(trainerMine.isEmpty ? "p1" : trainerMine)")
            winLogged = true
        } else if mineIdle && !oppIdle {
            forfeitName = trainerMine.isEmpty ? "You" : trainerMine
            emitLog("|win|\(trainerOpp.isEmpty ? "p2" : trainerOpp)")
            winLogged = true
        }
        archiveCurrentBattle(final: true)
        return true
    }
    // 急所: 「(相手の) Xの 急所に 当たった！」
    // 「急所」は OCR で「還所」「意所」等に崩れるため、「所に当たった」で
    // 判定する (実例: 2026-11-20 の対戦で 2 件とも日本語のまま漏れた)。
    // 対象は文中の種族名を優先する (範囲技では最後に被弾した枠と急所の
    // 対象が食い違うことがあるため)。種族が取れない場合だけ従来通り
    // 直近にダメージを受けた (受けつつある) 枠に付ける
    if (t.contains("急所に") || t.contains("所に") || t.hasSuffix("に当たった！") || t.hasSuffix("に当たった!") || t.hasSuffix("にたった！") || t.hasSuffix("にたった!") || t.hasSuffix("に当たつた！") || t.hasSuffix("にたつた！")) && (t.contains("当たった") || t.contains("たった") || t.contains("当たつた") || t.contains("たつた")) {
        var target = ""
        // 種族名が崩れている場合は緩い照合も試す (場にいる種族に限る)
        var critEntry = findSpeciesJa(in: t)
        if critEntry == nil, let loose = findSpeciesJaLoose(in: t) {
            let anch = fieldAnchoredSpecies(loose.entry)
            if lastSlots.values.contains(where: { $0.speciesEn == anch.en }) { critEntry = loose.entry }
        }
        if let csp = critEntry {
            let anch = fieldAnchoredSpecies(csp)
            let cside: String
            if t.contains("相手の") || t.contains("あいての") { cside = "p2" }
            else if t.contains("味方の") || t.contains("じぶんの") { cside = "p1" }
            else {
                let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
                let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
                cside = inOpp && !inMine ? "p2" : "p1"
            }
            target = "\(slotFor(side: cside, speciesEn: anch.en)): \(anch.en)"
        }
        if target.isEmpty {
            target = !lastPendingLabel.isEmpty ? lastPendingLabel
                : (Date().timeIntervalSince(lastDamageAt) < 6 ? lastDamageLabel : "")
        }
        // 同じ急所文の再読で二重に出さない (枠ごとに 6 秒あける)
        if !target.isEmpty && Date().timeIntervalSince(lastCritAt[target] ?? .distantPast) > 6 {
            lastCritAt[target] = Date()
            // 急所の告知文は被ダメ行より後に来るため、記録時点では
            // dmg イベントの crit が false のまま残る。対象の直近の
            // イベントを是正する (実例: 2026-11-22
            // battle_20261122_070237 ターン2、プロトコルには急所行が
            // あるのにイベントは crit=false だった)
            if let idx = battleEvents.lastIndex(where: { ev in
                ev.contains("\"k\":\"dmg\"") && ev.contains("\"def\":\"\(jsonEscape(target))\"")
                    && !ev.contains("\"atk\":\"\(jsonEscape(target))\"") && ev.contains("\"crit\":false")
            }) {
                battleEvents[idx] = battleEvents[idx].replacingOccurrences(of: "\"crit\":false", with: "\"crit\":true")
            }
            emitLog("|-crit|\(target)")
        }
        return true
    }
    // 技の失敗: 「しかし うまく決まらなかった！」。裸の |-fail| では
    // 誰の失敗か記録から復元できないため、直前の技の使用者を主体に
    // 付ける (この文は失敗した行動の直後にしか出ない。実例:
    // 2026-11-21 battle_20261121_230402 ターン5、帰属が逆に読めた)
    if t.contains("うまく決まらなかった") {
        if !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 8 {
            emitLog("|-fail|\(lastMoveLabel)")
        } else {
            emitLog("|-fail|")
        }
        return true
    }
    // メガシンカの反応 (ストーンと相手トレーナー名がここで判明する)。
    // ストーンは「<種族>の<ストーン>と」の構造から切り出して完全一致で照合する
    // (部分一致の最長マッチだとキーアイテム名などと競合しうるため)
    // 「反応した」は OCR で「受応した」と崩れることがある (実例:
    // 2026-11-20 vs leslie 戦。崩れた文は |-message| に漏れていた)
    // 「反応した」の「反」は OCR で 受/設 などにも崩れるため、「応した」
    // で拾う (実例: 2026-11-22 battle_20261122_050512、「設応した」と
    // 崩れて反応文として扱われず、メガ行にストーンが付かなかった)
    if t.contains("応した") && (t.contains("リングが") || t.contains("ナイト")) {
        // 「リングが」を含む形が基本だが、相手のメガでは末尾の語が
        // 読み落ちて「<種族>の<ストーン>と <相手>の 反応した！」だけが
        // 残ることがある (実例: 2026-11-21 battle_20261121_230402、
        // ライチュウのライチュウナイトX)。その場合は、ストーン名が
        // 辞書で引けた場合に限って反応文として扱い、引けない場合は
        // 消費せず後段 (証拠として |-message|) に委ねる
        var stoneResolved = false
        // 種族はまずストーン名から引く。ストーン名は種族名の途中までを
        // 含むことがあり (リザードナイトY に対する リザードン)、文中の
        // 種族名を素直に検索すると別の種族に誤認する (リザード =
        // Charmeleon。実例: 2026-11-21 battle_20261121_234913、
        // 場にいない Charmeleon の持ち物行が出た)。英語名は
        // 「<種族>ite (X/Y)」の形で機械的なため、そちらから引く
        var megaSp: SpeciesEntry? = nil
        var megaStoneJa: String? = nil
        if let sJa = findInDict(in: t, itemDict), sJa.contains("ナイト"), let sEn = itemJa2En[sJa] {
            megaStoneJa = sJa
            var baseEn = sEn
            for suf in ["ite X", "ite Y", "ite"] where baseEn.hasSuffix(suf) {
                baseEn = String(baseEn.dropLast(suf.count)); break
            }
            megaSp = speciesDict.first(where: { $0.en == baseEn })
        }
        if megaSp == nil { megaSp = findSpeciesJa(in: t) }
        if let sp = megaSp {
            let side = megaTextSide(t, baseEn: sp.en)
            // 完了済みのメガの反応文が再読された場合は、持ち物行や保留を
            // 出し直さない (実例: 2026-11-21 vs Toshiro 戦、終盤に
            // カメックスのストーン反応が再読され |-item| が漏れた)
            if let ms = monStates["\(side):\(sp.en)"]?.megaSpecies, !ms.isEmpty { return true }
            // 完了判定はファミリー単位でも行う: 名前側が崩れて別種族に
            // 解決された再読 (リザードン → リザード = Charmeleon) では
            // 解決先のキーに完了記録が無く素通りし、誤った種族の
            // 持ち物行が出る (実例: 2026-11-22 battle_20261122_051707)
            if monStates.contains(where: { $0.key.hasPrefix("\(side):") && sameSpeciesFamily(String($0.key.dropFirst(3)), sp.en) && !($0.value.megaSpecies ?? "").isEmpty }) { return true }
            if monStates["\(side):\(sp.en)"] == nil { monStates["\(side):\(sp.en)"] = MonState() }
            if let itJa = megaStoneJa {
                stoneResolved = true
                emitItemOnce(slot: slotFor(side: side, speciesEn: sp.en), side: side, speciesEn: sp.en, itemJa: itJa)
                pendingMegaStone[side] = itJa
                pendingMegaSpecies[side] = sp.en
            } else if let r = t.range(of: sp.ja + "の") {
                // ストーンの切り出しは生テキストで行う (正規化すると助詞の「と」と
                // 「〜ナイト」の「ト」が区別できなくなるため)
                let stoneCand = String(t[r.upperBound...].prefix(while: { $0 != "と" }))
                if let itJa = itemDict[normalize(stoneCand)] {
                    stoneResolved = true
                    // ストーンが特定できたら、種族は文中の名前ではなく
                    // ストーンから引き直す。名前側が崩れていると
                    // (リザードン → リザード)、誤った種族の持ち物行に
                    // なる (実例: 2026-11-22 battle_20261122_051707、
                    // Charmeleon の Charizardite Y 行)
                    var useSp = sp
                    var useSide = side
                    if let sEn = itemJa2En[itJa] {
                        var baseEn = sEn
                        for suf in ["ite X", "ite Y", "ite"] where baseEn.hasSuffix(suf) {
                            baseEn = String(baseEn.dropLast(suf.count)); break
                        }
                        if let stoneSp = speciesDict.first(where: { $0.en == baseEn }) {
                            useSp = stoneSp
                            useSide = megaTextSide(t, baseEn: stoneSp.en)
                        }
                    }
                    emitItemOnce(slot: slotFor(side: useSide, speciesEn: useSp.en), side: useSide, speciesEn: useSp.en, itemJa: itJa)
                    pendingMegaStone[useSide] = itJa
                    pendingMegaSpecies[useSide] = useSp.en
                }
            }
        }
        if stoneResolved || t.contains("リングが") { return true }
    }
    // メガシンカの完了: 状態をメガ種族に切り替える (キーはベース種族のまま。
    // プレートや技メッセージの名前表記はメガ後もベース名のため)
    if t.contains("メガシンカした") {
        let megaEntry = speciesDict.filter { $0.ja.hasPrefix("メガ") && nt.contains(normalize($0.ja)) }
            .max(by: { $0.ja.count < $1.ja.count })
        if let me = megaEntry {
            var baseEn = me.en
            if let r = baseEn.range(of: "-Mega") { baseEn = String(baseEn[..<r.lowerBound]) }
            let side = megaTextSide(t, baseEn: baseEn)
            completeMega(side: side, baseEn: baseEn, megaEn: me.en)
        }
        return true
    }
    // 繰り出し (相手): 場の左右はプレートが決めるため、ここでは登録だけ行う
    if t.contains("繰り出した") {
        if !logStarted || winLogged { startBattleLog() }
        if trainerOpp.isEmpty, let r = t.range(of: "は") {
            let name = String(t[..<r.lowerBound])
            if !name.isEmpty && name.count <= 20 { trainerOpp = name }
        }
        for e in findAllSpeciesJa(in: t) {
            if monStates["p2:\(e.en)"] == nil { monStates["p2:\(e.en)"] = MonState() }
        }
        return true
    }
    // 繰り出し (自分): 「ゆけっ！ A！ B！」の並び順 = 場の左右 (実機で確認)。
    // Vision は小さい「っ」を「つ」と読むことが多いため両方を拾う
    if t.contains("ゆけっ") || t.contains("ゆけつ") {
        if !logStarted || winLogged { startBattleLog() }
        // 先発の登録は対戦開始時だけ。途中交代の繰り出し文をここで処理すると
        // 「並び順 = 左右」の前提で誤った枠に |switch| を出してしまう
        // (実例: 2026-11-20、イエッサンの交代要員オオニューラが p1a に
        // 誤登録され、プレート確定の p1b と合わせて "Go! Sneasler!" が
        // 二重に出た)。途中交代はプレート側 (2 フレーム確定) が正しい
        // 枠で記録するため、文は消費するだけにする
        if lastSlots["mineA"] != nil && lastSlots["mineB"] != nil { return true }
        var found = findAllSpeciesJa(in: t)
        // 性別・リージョンフォルムは登録チームと突き合わせて確定させる
        found = found.map { e in
            let grp = formeGroup(e)
            if grp.count > 1 {
                let inTeam = grp.filter { teamEntries[$0.en] != nil }
                if inTeam.count == 1 { return inTeam[0] }
            }
            return e
        }
        for e in found.prefix(2) {
            if monStates["p1:\(e.en)"] == nil { monStates["p1:\(e.en)"] = MonState() }
            // 文が 1 体ずつ届く場合、並び順の決め打ちでは 2 体目が
            // 先発の枠 (mineA) へ重なり、誤った枠の交代行と、プレート
            // 確定時の二重の交代行を生む (実例: 2026-11-22
            // battle_20261122_091721、ブリジュラスが p1a に出て、
            // 先発の交代行が二重になった)。登録済みの種族は飛ばし、
            // 空いている枠の若い方へ割り当てる
            if lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en { continue }
            let plateName = lastSlots["mineA"] == nil ? "mineA" : "mineB"
            if lastSlots[plateName]?.speciesEn != e.en {
                let pct = monStates["p1:\(e.en)"]?.hpPercent ?? 100
                lastSlots[plateName] = SlotState(speciesEn: e.en, hpPercent: pct)
                lastEmittedPct[plateName] = pct
                var hp = monStates["p1:\(e.en)"]!.hpText
                if let st = monStates["p1:\(e.en)"]?.status, !st.isEmpty { hp += " \(st)" }
                emitLog("|switch|\(slotId(plateName)): \(e.en)|\(e.en)|\(hp)")
                recordSwitchIn(side: "p1", slot: slotId(plateName), speciesEn: e.en)
            }
        }
        return !found.isEmpty
    }
    // 天候・フィールドの開始/終了 (種族名が無くても拾う)。
    // 状態が変化した文はフィールドの告知として消費する
    // 天候・フィールドの告知文は、状態が変わらなかった (再読だった) 場合も消費する
    if checkFieldText(text: t) { return true }
    // あくびで眠気を誘った文 (対象は次のターン終了時に眠る)。文中で
    // 対象が特定できる場合は、効果の開始行 (|-start|) も記録する
    // (実例: 2026-11-22 battle_20261122_054802、あくびの効果行が
    // 一切なく、対象も特定できなかった)。特定できない場合は
    // 従来どおり消費だけする
    if (t.contains("眠気") || t.contains("ねむけ")) && (t.contains("誘った") || t.contains("誘つた") || t.contains("さそった") || t.contains("さそつた")) {
        if lastMoveName == "Yawn", let user = parseSlotSpecies(lastMoveLabel) {
            let targetPrefix = user.side == "p1" ? "opp" : "mine"
            let named = lastSlots.filter { plateName, s in
                plateName.hasPrefix(targetPrefix)
                    && (speciesDict.first { $0.en == s.speciesEn }.map { t.contains($0.ja) } ?? false)
            }
            if named.count == 1, let (plateName, s) = named.first {
                emitLog("|-start|\(slotId(plateName)): \(s.speciesEn)|move: Yawn")
            }
        }
        return true
    }
    // やどりぎのたねを植えつけた文 (吸収のダメージ/回復はプレート側で
    // 行が出るため、植えつけ自体は消費だけする)
    if t.contains("植えつけ") || t.contains("植え付け") { return true }
    // サイドコンディション (おいかぜ) の告知文: 種族名を含まないため、
    // 種族照合より前にここで処理する (実例: 2026-11-20 vs Zycloud 戦、
    // 「あいて相手にかぜおはし追い風が吹き始めた！」が日本語のまま漏れた)
    if t.contains("追い風") || t.contains("おいかぜ") {
        let scSide = (t.contains("相手") || t.contains("あいて")) ? "p2" : "p1"
        if t.contains("吹き始") || t.contains("ふきはじ") {
            let k = "\(scSide):Tailwind:start"
            if Date().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = Date()
                emitLog("|-sidestart|\(scSide)|move: Tailwind")
            }
            return true
        }
        if t.contains("止ん") || t.contains("やん") || t.contains("終わ") || t.contains("なくな") {
            let k = "\(scSide):Tailwind:end"
            if Date().timeIntervalSince(lastSideCondAt[k] ?? .distantPast) > 8 {
                lastSideCondAt[k] = Date()
                emitLog("|-sideend|\(scSide)|move: Tailwind")
            }
            return true
        }
    }
    // ワイドガードの持続告知: 「味方の周りを ワイドガードが
    // 守っている！」(種族名を含まない文)。設置は |-sidestart| で
    // 記録済みで、守られた対象は文から特定できないため消費だけする
    // (実例: 2026-11-21 battle_20261121_224409、崩れた再読が
    // 2 回 |-message| に残った)
    if t.contains("ワイドガード") && t.contains("守っている") { return true }
    // 効果の確認文・交代の指示文 (出来事そのものは別の行で記録済みのため、
    // 本文だけを |-message| に残さないよう消費する)
    // ワイドガードの文はここで消費しない (使用告知は後段の技使用として
    // |move| に、防御の確認文は種族固定後の |-activate| 分岐で処理する)。
    // 以前は確認文として一律に消費していたため使用告知まで巻き込まれ、
    // ワイドガードがログに一切出なかった
    // 「身を守った」もここで消費しない: まもるで防いだ際の確認文
    // (「<対象>は 攻撃から 身を守った！」) は、種族固定後の
    // |-activate| 分岐が記録するのが唯一の経路で、ここで消費すると
    // 防がれた技の解決行が残らなかった (実例: 2026-11-21
    // battle_20261121_224409、クチートのまもるに阻まれた
    // サイコキネシス)
    if !t.contains("ワイドガード") && (t.contains("手助けする") || t.contains("守られた") || t.contains("体勢に入った")
        || t.contains("戻れ") || t.contains("引っこめた") || t.contains("引っ込めた")
        || t.contains("引つこめた") || t.contains("引つ込めた")
        || t.contains("引っごめた") || t.contains("引つごめた")
        || (t.contains("引") && t.contains("こめた"))
        || t.contains("イリュージョンが解けた") || t.contains("イリュージョンがとけた")
        || (t.contains("ランク") && t.contains("級"))
        || ((t.contains("ゆけ") || t.contains("もどれ")) && findSpeciesJa(in: t) != nil)
        || t.contains("場所を入れ替えた")) {
        // 引っ込めた は OCR で「引つこめた」(っ->つ、込->こ) と崩れる
        // (実例: 2026-11-20 vs Ony 戦「Onyはコリランダーを引つこめた！」)
        // ラテン文字が混入する崩れ (「引Iっこめた」) もあるため、
        // 「引」と「こめた」の共起でも消費する (実例: 2026-11-20 vs leslie 戦)
        // 場所を入れ替えた はアリーバスイッチの結果文 (技そのものは |move| で記録済み)
        return true
    }
    // はたきおとすの持ち物喪失と、おみとおしの持ち物判明: どちらの文も
    // 主語は攻撃側・特性側で、持ち物の持ち主は文中に出るもう一方の種族
    // のため、通常の種族固定では持ち主を特定できない。「<持ち主>の
    // <持ち物>」の隣接した並びから持ち主と持ち物を切り出し、場の在席
    // から持ち主の側と枠を決めて記録する (実例: 2026-11-21 vs KAM 戦、
    // ハッサムのはたきおとすでイエッサン♀のゴツゴツメット喪失が、
    // おみとおしでサーナイトナイトの判明が、どちらもルールが無く
    // |-message| に落ちていた)
    if t.contains("はたき落とした") || t.contains("見通し") {
        var itemOwner: (item: String, owner: SpeciesEntry)? = nil
        if let it = findInDict(in: t, itemDict),
           let ow = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)の\(it)") }) {
            itemOwner = (it, ow)
        } else {
            // OCR 崩れ救済: 濁点・小書き仮名を畳んだ looseText 空間で
            // 持ち物名と「持ち主の持ち物」の並びを探す (実例:
            // 2026-11-21 battle_20261121_224409、ゴツゴツメットが
            // ゴッゴツメットに崩れて辞書照合できなかった)
            let lt = looseText(t)
            var bestIt: String? = nil
            for orig in itemDict.values {
                let lo = looseText(orig)
                if !lo.isEmpty && lt.contains(lo) && (bestIt == nil || orig.count > bestIt!.count) {
                    bestIt = orig
                }
            }
            if let it = bestIt,
               let ow = speciesDict.first(where: { !$0.ja.isEmpty && lt.contains(looseText("\($0.ja)の\(it)")) }) {
                itemOwner = (it, ow)
            }
        }
        if let (itJa, owner) = itemOwner {
            var anch = anchoredSpeciesForText(owner, text: t)
            // 名前表記は雌雄・フォルムで同一のため、場にいるフォルムへ寄せる
            if !lastSlots.values.contains(where: { $0.speciesEn == anch.en }),
               let onField = formeGroup(anch).first(where: { e in lastSlots.values.contains { $0.speciesEn == e.en } }) {
                anch = onField
            }
            let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
            let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
            var ownerSide: String? = nil
            if inMine != inOpp { ownerSide = inOpp ? "p2" : "p1" }
            else if let subj = findSpeciesJa(in: t), subj.en != anch.en {
                // 持ち主が場で定まらない場合は、主語 (攻撃側・特性側) の
                // 反対側とみなす
                let sInMine = lastSlots["mineA"]?.speciesEn == subj.en || lastSlots["mineB"]?.speciesEn == subj.en
                let sInOpp = lastSlots["oppA"]?.speciesEn == subj.en || lastSlots["oppB"]?.speciesEn == subj.en
                if sInMine != sInOpp { ownerSide = sInOpp ? "p1" : "p2" }
                else if t.contains("相手の") || t.contains("あいての") { ownerSide = "p1" }
            }
            if let oside = ownerSide {
                let oslot = slotFor(side: oside, speciesEn: anch.en)
                if monStates["\(oside):\(anch.en)"] == nil { monStates["\(oside):\(anch.en)"] = MonState() }
                emitItemOnce(slot: oslot, side: oside, speciesEn: anch.en, itemJa: itJa)
                if t.contains("はたき落とした") {
                    noteItemLost(slot: oslot, side: oside, speciesEn: anch.en)
                }
                // おみとおしの文は、主語 (特性の持ち主) の特性判明でもある。
                // 判明を記録すると、特性からフォルムを訂正する処理が
                // 必要に応じて働く (バクフーン → ヒスイの判別など)
                if t.contains("見通し"), let subj = findAllSpeciesJa(in: t).first(where: { $0.en != anch.en }) {
                    let sAnch = anchoredSpeciesForText(subj, text: t)
                    let sInMine = lastSlots["mineA"]?.speciesEn == sAnch.en || lastSlots["mineB"]?.speciesEn == sAnch.en
                    let sInOpp = lastSlots["oppA"]?.speciesEn == sAnch.en || lastSlots["oppB"]?.speciesEn == sAnch.en
                    let subjSide: String
                    if sInMine != sInOpp { subjSide = sInOpp ? "p2" : "p1" }
                    else { subjSide = oside == "p1" ? "p2" : "p1" }   // おみとおしは相手の道具を見るため、主語は持ち主の反対側
                    emitAbilityOnce(slot: slotFor(side: subjSide, speciesEn: sAnch.en), side: subjSide, speciesEn: sAnch.en, abilityEn: "Frisk")
                }
                return true
            }
        }
    }
    // はたきおとすの持ち物名が OCR 崩れで辞書照合できなかった場合の
    // 受け皿 (上の分岐は持ち物名が読めることが前提)。「<持ち主>の」
    // の隣接から持ち主を特定し、判明済みの持ち物で喪失を記録する。
    // 判明が無ければ喪失の事実だけを記録する (実例: 2026-11-21
    // battle_20261121_224409、ゴツゴツメットがゴッゴツメットに
    // 崩れて文が |-message| に残った)
    if t.contains("はたき落とした") {
        // 持ち主は「<種族>の」に続き、主語 (攻撃側) は「<種族>は」に続く
        if let owner = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)の") && !t.contains("\($0.ja)は") }) {
            var anch = anchoredSpeciesForText(owner, text: t)
            if !lastSlots.values.contains(where: { $0.speciesEn == anch.en }),
               let onField = formeGroup(anch).first(where: { e in lastSlots.values.contains { $0.speciesEn == e.en } }) {
                anch = onField
            }
            let inMine = lastSlots["mineA"]?.speciesEn == anch.en || lastSlots["mineB"]?.speciesEn == anch.en
            let inOpp = lastSlots["oppA"]?.speciesEn == anch.en || lastSlots["oppB"]?.speciesEn == anch.en
            var ownerSide: String? = nil
            if inMine != inOpp { ownerSide = inOpp ? "p2" : "p1" }
            else if let subj = speciesDict.first(where: { !$0.ja.isEmpty && t.contains("\($0.ja)は") }), subj.en != anch.en {
                let sInMine = lastSlots["mineA"]?.speciesEn == subj.en || lastSlots["mineB"]?.speciesEn == subj.en
                let sInOpp = lastSlots["oppA"]?.speciesEn == subj.en || lastSlots["oppB"]?.speciesEn == subj.en
                if sInMine != sInOpp { ownerSide = sInOpp ? "p1" : "p2" }
                else if t.contains("相手の") || t.contains("あいての") { ownerSide = "p1" }
            }
            if let oside = ownerSide {
                let oslot = slotFor(side: oside, speciesEn: anch.en)
                if monStates["\(oside):\(anch.en)"] == nil { monStates["\(oside):\(anch.en)"] = MonState() }
                let knownItem = oside == "p1" ? (teamEntries[anch.en]?["item"] as? String) : revealedItems[anch.en]
                if let knownItem { emitItemOnce(slot: oslot, side: oside, speciesEn: anch.en, itemJa: knownItem) }
                noteItemLost(slot: oslot, side: oside, speciesEn: anch.en)
                return true
            }
        }
    }
    var sp = findSpeciesJa(in: t)
    var looseMoveStart: Int? = nil
    if sp == nil, let l = findSpeciesJaLoose(in: t) {
        sp = l.entry
        looseMoveStart = l.moveStart
    }
    // フィールドに守られた文の断片 (種族名が欠けて解決できない場合):
    // 対象は特定できないが、フィールドの裏付けだけ取って消費する
    // (実例: 2026-11-20 vs Ony 戦「クスはサイコフィールドに守られている！」が
    //  日本語のまま漏れた。通常形は種族解決後の「守られている」分岐が処理する)
    if sp == nil && t.contains("守られている") {
        for (ja, en) in [("サイコフィールド", "Psychic"), ("エレキフィールド", "Electric"), ("グラスフィールド", "Grassy"), ("ミストフィールド", "Misty")] where t.contains(ja) {
            setTerrain(en, via: t)
            break
        }
        return true
    }
    // 回復の告知文の断片 (種族名が解決できない場合): 回復そのものは
    // プレート側で |-heal| を出すため、文は消費するだけにする
    // (実例: 2026-11-20「シャンデラのかいふく袱力か回復した！」等の漏れ)
    if sp == nil && t.contains("回復した") { return true }
    // ランク変化文の後半の断片 (主語が無く、上がった/下がっただけの
    // 文): 直前に覚えた断片 (主語+能力名) と結合して適用する
    // (実例: 2026-11-22 battle_20261122_091721 ターン4)
    if sp == nil, let frag = prevBoostFragment, Date().timeIntervalSince(frag.at) < 6,
       (t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
        || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた")) {
        checkBoostText(text: frag.text + t, side: frag.side, speciesEn: frag.speciesEn,
                       slot: slotFor(side: frag.side, speciesEn: frag.speciesEn))
        prevBoostFragment = nil
        return true
    }
    guard var sp else { return battleLog.count > before }
    // 緩い照合は場にいない種族を掴むことがある (実例: 2026-11-20 vs Mark 戦、
    // イエッサンの てだすけ の再読が サンド の てだすけ と誤記録された)。
    // プレートで場の種族が分かっているときは、緩い照合の結果 (フォルム違いを
    // 含む) が場にいなければ採用しない。完全一致の結果には適用しない
    if looseMoveStart != nil && !lastSlots.isEmpty {
        let onField = Set(lastSlots.values.map { $0.speciesEn })
        let grp = Set(formeGroup(sp).map { $0.en })
        if !onField.contains(sp.en) && onField.isDisjoint(with: grp) { return battleLog.count > before }
    }
    // フォルム表記を場の状態に寄せる (メッセージの名前は雌雄で同一のため、
    // 寄せないと技の判明などが基本フォルム側に記録されてしまう)。
    // 「相手の」の手がかりがある場合は相手側のフォルムを優先する
    sp = anchoredSpeciesForText(sp, text: t)
    // 左右: 「相手の」等の前置きを優先し、無ければ場のプレートから推定する。
    // ただし、その種族が片方の場にだけ実在する場合は場の側を正とする
    // (前置きの OCR 崩れや古い文の再処理で、自分のポケモンが「相手の」
    // として技・ひんしを二重に記録された実例: 2026-11-20 グレンアルマ)
    let inMine = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en
    let inOpp = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
    var side: String
    if t.contains("相手の") || t.contains("あいての") { side = "p2" }
    else if t.contains("味方の") || t.contains("じぶんの") { side = "p1" }
    else { side = inOpp && !inMine ? "p2" : "p1" }
    if inMine != inOpp { side = inOpp ? "p2" : "p1" }
    // オーラ特性の告知: 「(相手の) <種族>は <オーラ名>を 放っている！」
    // (フェアリーオーラ/ダークオーラ/オーラブレイク。場に出た直後に
    //  表示される)。従来はこの形の分岐自体が無く、読み重なりの崩れで
    //  帰属も決まらないまま |-message| に落ち、特性が最後まで記録
    //  されなかった (実例: 2026-11-21 battle_20261121_161334、
    //  「あいて相手のフラエッテははなフェアリーオーラを放っている！」)。
    //  オーラ名と「放って」の併存はこの告知にしか現れないため、
    //  崩れに強い部分一致で拾う
    if t.contains("放って") && (t.contains("オーラを") || t.contains("オーラブレイク")) {
        let auras: [(String, String)] = [("フェアリーオーラ", "Fairy Aura"), ("ダークオーラ", "Dark Aura"), ("オーラブレイク", "Aura Break")]
        if let aura = auras.first(where: { t.contains($0.0) }) {
            let aslot = slotFor(side: side, speciesEn: sp.en)
            emitAbilityOnce(slot: aslot, side: side, speciesEn: sp.en, abilityEn: aura.1)
            return true
        }
    }
    // 救済登録: 種族が確実に解決できた (緩い照合ではない) のに、その側の
    // 場にいない場合、その側の空き枠がちょうど 1 つだけなら、その枠へ
    // 繰り出しとして登録してから帰属させる。プレート未確定 (遮蔽・OCR
    // 失敗) でも、文という強い証拠から場の構成を復元し、後続の文が
    // 既定枠 (a 枠) へ誤帰属されるのを防ぐ (実例: 2026-11-21
    // battle_20261121_132153、イエッサン♀のプレートが全試合未確定で、
    // 文がすべて p1a のオオニューラに帰属した)。自軍はチーム登録、
    // 相手は選出同定の範囲と矛盾する場合は登録しない (範囲が未取得の
    // 場合は矛盾とみなさない)。フォルム違いは登録済みフォルムに寄せる
    if looseMoveStart == nil {
        let onSide = side == "p1" ? inMine : inOpp
        if !onSide {
            let allowed: Set<String> = side == "p1" ? Set(teamEntries.keys) : Set(oppTeamSeen)
            var candidate: SpeciesEntry? = nil
            if allowed.isEmpty || allowed.contains(sp.en) { candidate = sp }
            else if let sib = formeGroup(sp).first(where: { allowed.contains($0.en) }) { candidate = sib }
            if let cand = candidate {
                let names = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
                // 空き枠: プレート未登録の枠に加え、前任がひんし済みの
                // 枠も空きとみなす (ひんし済みの枠には交代要員しか
                // 入らないため、行き先は一意に決まる。実例: 2026-11-21
                // battle_20261121_230402、ひんししたイエッサン♀の枠が
                // 「占有中」のまま残り、エルフーンの交代が登録されず
                // アンコールが p1a へ誤帰属された)
                let empty = names.filter { name in
                    if lastSlots[name] == nil { return true }
                    return faintedSlots[slotId(name)] != nil && lastSlots[name]?.speciesEn != cand.en
                }
                if empty.count == 1 {
                    let plateName = empty[0]
                    let rslot = slotId(plateName)
                    // 再登場の場合は前回出場時の HP で入る (新規は満タン)
                    let rkey = "\(side):\(cand.en)"
                    let pct = monStates[rkey]?.hpPercent ?? 100
                    let hpText = monStates[rkey]?.hpText ?? "\(pct)/100"
                    lastSlots[plateName] = SlotState(speciesEn: cand.en, hpPercent: pct)
                    lastEmittedPct[plateName] = pct
                    faintedSlots.removeValue(forKey: rslot)
                    if side == "p2" { updateOppTeam() }
                    emitLog("|switch|\(rslot): \(cand.en)|\(cand.en)|\(hpText)")
                    recordSwitchIn(side: side, slot: rslot, speciesEn: cand.en)
                    print("[log] 文から場を復元しました: \(rslot) に \(cand.en) を繰り出しとして登録 (プレート未確定の救済)")
                    fflush(stdout)
                    sp = cand
                }
            }
        }
    }
    // デフォルト帰属の繰り返しの記録: 確実に解決できた種族が、その側の
    // 場におらず、救済登録 (空き枠が 1 つの場合) も発動しなかった場合、
    // 文は既定枠 (a 枠) へ無言で帰属される。交代の取りこぼしで枠状態が
    // 古いままだと、これが何ターンも続いて内部矛盾 (同じ枠から 2 つの
    // 技行) の原因になる (実例: 2026-11-21 battle_20261121_150535、
    // イエッサン♀への交代が取りこぼされ、エルフーンのままの p1a へ
    // 3 ターン帰属が続いた)。2 回目で証拠を残す。古い枠への自動登録は
    // しない (どちらの枠が古いか文だけでは判別できず、正しい占有者を
    // 消す危険があるため)
    if looseMoveStart == nil {
        let onSideNow = side == "p1"
            ? (lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en)
            : (lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en)
        if !onSideNow {
            let ckey = "\(side)|\(sp.en)"
            defaultAttribCount[ckey, default: 0] += 1
            if defaultAttribCount[ckey] == 2 {
                let names = side == "p1" ? ["mineA", "mineB"] : ["oppA", "oppB"]
                print("[log] 場にいない種族の文が繰り返し既定枠へ帰属されています: \(sp.en) (\(side)) — 現在の枠状態: \(names.map { "\($0)=\(lastSlots[$0]?.speciesEn ?? "（空き）")" }.joined(separator: ", "))")
                fflush(stdout)
                debugCapture(kind: "default_attribution", key: "default_attribution:\(side):\(sp.en)", rawText: t,
                             detail: ["species": sp.en, "side": side, "count": 2, "turn": currentTurn,
                                      "slots": names.map { lastSlots[$0]?.speciesEn ?? "" }, "text": t])
            }
        }
    }
    let slot = slotFor(side: side, speciesEn: sp.en)
    let key = "\(side):\(sp.en)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // ゴツゴツメット: 接触技で攻撃した側が受ける反動ダメージの予告。
    // ダメージ行に [from] item: Rocky Helmet を付けるため記録だけする
    // (人間可読ログ側の -damage 描画でも発生源として表示する)
    if t.contains("ゴツゴツメット") && t.contains("ダメージを受けた") {
        pendingStatusFrom[key] = ("item: Rocky Helmet", Date())
        return true
    }
    // 状態異常などのダメージ予告: ダメージ行に [from] を付けるため記録だけする
    if t.contains("ダメージを受けた") {
        for (ja, code) in [("毒", "psn"), ("やけど", "brn"), ("砂嵐", "sandstorm"), ("あられ", "hail")] where t.contains(ja) {
            pendingStatusFrom[key] = (code, Date())
            break
        }
        return true
    }
    // 天候チップの告知文 (実機文面は「すなあらしが Xを 襲う！」。
    // OCR では「すな砂あらし」と混ざって読まれることがある)
    if t.contains("襲う") || t.contains("おそう") {
        if t.contains("砂あらし") || t.contains("すなあらし") || t.contains("砂嵐") {
            pendingStatusFrom[key] = ("sandstorm", Date())
            return true
        }
        if t.contains("あられ") {
            pendingStatusFrom[key] = ("hail", Date())
            return true
        }
    }
    // 相性: 「(相手の) <対象>に 効果は いまひとつだ/バツグンだ/ないようだ」
    // (同じ文の再読で二重に出さないよう、枠+種別で 3 秒間抑止する)
    // OCR 崩れ (バツグン -> バッグン) に耐えるよう、小さい ッ/っ を寄せた形でも判定する
    let tk = t.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")
    // 「バツグン」が平仮名 (ばつぐん) で読まれた場合は正規化形でも判定する (検証 R1 #66)
    let ntk = nt.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")
    // バツグン自体の濁点ゆれ (パツグン/バツクン等) は畳んだ形でも判定する (検証 R3)。
    // 平仮名読み (ばつくん) は正規化形を畳んだものとも照合する (検証 vhard R9)
    let ftk = foldDakuten(tk)
    let kind = tk.contains("いまひとつ") ? "resisted" : (tk.contains("バツグン") || ntk.contains("バツグン") || ftk.contains("ハツクン") || foldDakuten(ntk).contains("ハツクン")) ? "supereffective" : tk.contains("ないようだ") ? "immune" : ""
    // 「効果は」が OCR で丸ごと脱落した文 (実例: 2026-11-21
    // battle_20261121_144858「伹手ユキメノコにパツグンだ！」) でも、
    // 末尾の相性語から種別が確定し、文が「だ」で終わる形なら同じ
    // 分岐で消費する。バツグン/いまひとつ/ないようだ は対戦中の
    // 告知ではこの文にしか現れないため、誤爆の心配は小さい
    if t.contains("効果は") || (!kind.isEmpty && (t.hasSuffix("だ！") || t.hasSuffix("だ!") || t.hasSuffix("だ"))) {
        if !kind.isEmpty {
            let ekey = "\(slot)|\(kind)"
            if let at = lastEffectAt[ekey], Date().timeIntervalSince(at) < 3 { return true }
            lastEffectAt[ekey] = Date()
            var effLabel = "\(slot): \(sp.en)"
            // 同じ技の解決中に、同じ対象へ別の相性の行が来たら、それは
            // 同じ技で被ダメして相性行がまだ無い別の対象の分とみなして
            // 付け替える (1 つの技が同じ対象に resisted と
            // supereffective の両方になることはない。実例: 2026-11-21
            // battle_20261121_234913、ねっぷうの相性 2 行が両方とも
            // フシギバナに付き、ガブリアスの分が消えた)。付け替え先が
            // 無い矛盾した行は出さない
            if let prevKind = effectBySeq[actionSeq]?[effLabel], prevKind != kind {
                if let other = (damagedBySeq[actionSeq] ?? []).first(where: { $0 != effLabel && effectBySeq[actionSeq]?[$0] == nil }) {
                    effLabel = other
                } else {
                    return true
                }
            }
            effectBySeq[actionSeq, default: [:]][effLabel] = kind
            emitLog("|-\(kind)|\(effLabel)")
            return true
        }
    }
    // フィールドに守られた (優先度技の無効化): フィールド状態の裏付けにもなる
    if t.contains("守られている") {
        for (ja, en) in [("サイコフィールド", "Psychic"), ("エレキフィールド", "Electric"), ("グラスフィールド", "Grassy"), ("ミストフィールド", "Misty")] where t.contains(ja) {
            setTerrain(en, via: t)
            emitLog("|-activate|\(slot): \(sp.en)|move: \(en) Terrain")
            return true
        }
        return true
    }
    // ミス: 「<対象>には 当たらなかった！」(使用者は直近の |move| の枠)
    if t.contains("当たらなかった") {
        if !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 8 {
            // 外れの対象 (枠と種族) が場の記録と矛盾する場合は行を
            // 出さない (実例: 2026-11-22 battle_20261122_071457、
            // 場に出ていないガオガエンが p2a の外れ対象になった)。
            // 交代直後でプレート未確定の間は、交代記録の枠と一致
            // すれば通す
            let missPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            let missTracked = lastSlots[missPn]?.speciesEn
            let missConsistent = (missTracked.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[missPn] == sp.en
                || lastSwitchIn["\(side):\(sp.en)"]?.slot == slot
            if missConsistent {
                emitLog("|-miss|\(lastMoveLabel)|\(slot): \(sp.en)")
            } else {
                debugCapture(kind: "move_guard", key: "miss_target:\(slot):\(sp.en):\(currentTurn)", rawText: t,
                             detail: ["reason": "miss_target_inconsistent", "slot": slot, "species": sp.en, "tracked": missTracked ?? "", "turn": currentTurn])
            }
        }
        return true
    }
    // どくびしの吸収: 「<種族>は どくびしを 吸収した！」。接地した
    // どくタイプが場に出た際の告知で、その側の どくびしが消える。
    // 交代記録からの導出 (recordSwitchIn) が主経路で、こちらは
    // 文面が取れた場合の経路 (二重に出ても sideend は冪等)
    if t.contains("どくびし") && t.contains("吸収") {
        emitHazard(side, "Toxic Spikes", start: false)
        return true
    }
    // ワイドガードで守られた: 「<対象>は ワイドガードで 守られた！」
    // (まもられた の表記も拾う)。文中の ワイドガード を技の使用と
    // 誤読しないよう、技使用の解析より前にここで処理する
    if t.contains("ワイドガード") && (t.contains("守られ") || t.contains("まもられ")) {
        let pk = slot + "|wideguard"
        if let at = lastSingleActAt[pk], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = Date()
        emitLog("|-activate|\(slot): \(sp.en)|move: Wide Guard")
        return true
    }
    // アンコールの効果: 「<対象>は アンコールを受けた！」。対象への
    // 効果行 (|-start|) として記録する。技の使用の解析より前に処理
    // しないと、文中の「アンコール」が対象自身の技使用として誤読
    // される (実例: 2026-11-21 battle_20261121_230402、エルフーンの
    // アンコールを受けたオオニューラに |move|Encore が付いた)
    if t.contains("アンコール") && t.contains("受けた") {
        emitLog("|-start|\(slot): \(sp.en)|move: Encore")
        return true
    }
    // 技の使用: 「(相手の) <種族>の <技>！」— <技> は種族名の直後から文末までと完全一致
    // 「たおれた」を含む文は技の告知ではあり得ない (ひんし文を技と誤読する
    // 事故の防止。検証 R5: カイリキーのひんし文から かいりき を誤検出)
    if (t.hasSuffix("！") || t.hasSuffix("!")) && !t.contains("たおれた") && !foldDakuten(t).contains("たおれた") {
        var cand: String? = nil
        // 長音落ちまで畳んだ変換 (種族名・技名とも全件衝突なしを確認済み)
        let deepFold: (String) -> String = { foldDakuten($0.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")).replacingOccurrences(of: "ー", with: "") }
        if let r = nt.range(of: normalize(sp.ja + "の")) {
            cand = String(nt[r.upperBound...])
        } else if let r = foldDakuten(nt).range(of: foldDakuten(normalize(sp.ja + "の"))) {
            // 種族名が濁点ゆれで解決された場合 (アヤシシ→アヤシジ等) は、
            // 畳んだ形で位置を求めて元の文から切り出す (検証 R3 #35)
            let fnt = foldDakuten(nt)
            let off = fnt.distance(from: fnt.startIndex, to: r.upperBound)
            cand = String(nt[nt.index(nt.startIndex, offsetBy: off)...])
        } else if let r = deepFold(nt).range(of: deepFold(normalize(sp.ja + "の"))) {
            // 種族名の長音落ちまで重なった場合 (サーナイト→サナイト) は
            // 変換空間で切り出し、そのまま渡す (moveNameLoose 第3パスが
            // 同じ空間で照合する。検証 最終監査 seed32 vhard:
            // かみなりパンチ→かみなり の誤読対策)
            cand = String(deepFold(nt)[r.upperBound...])
        } else if let ms = looseMoveStart {
            // 種族名が OCR で崩れている場合は、緩い照合で得た位置から切り出す
            let chars = Array(nt)
            if ms <= chars.count { cand = String(chars[ms...]) }
        }
        var mvJaFound: String? = nil
        if let cand {
            let c = cand.trimmingCharacters(in: CharacterSet(charactersIn: "！!"))
            mvJaFound = moveNameOrig[c] ?? moveNameLoose(c)
        }
        if mvJaFound == nil {
            // 種族名直後の切り出しに失敗した場合は、文中の技名を直接探す
            // (実例: 「あいてペンドラーの相手のつるぎのまい！」のように
            //  前置きが二重に化けた文でも、技名そのものは無事なことが多い。
            //  誤爆を避けるため、場にいる種族の文だけを対象にする)
            let onField = lastSlots.values.contains { $0.speciesEn == sp.en }
                || formeGroup(sp).contains { g in lastSlots.values.contains { $0.speciesEn == g.en } }
            if onField {
                // 種族名そのものと重なる技名は拾わない (カイリキー vs かいりき
                // のような種族名=技名の衝突。検証 R5 で検出)。技名は種族名の
                // 出現位置より後ろにあるものだけを候補にする
                var spEnd = 0
                if let r = nt.range(of: normalize(sp.ja)) {
                    spEnd = nt.distance(from: nt.startIndex, to: r.upperBound)
                } else if let r = foldDakuten(nt).range(of: foldDakuten(normalize(sp.ja))) {
                    let fnt = foldDakuten(nt)
                    spEnd = fnt.distance(from: fnt.startIndex, to: r.upperBound)
                }
                let hit = moveNameOrig.keys.filter { key in
                    guard let kr = nt.range(of: key) else { return false }
                    return nt.distance(from: nt.startIndex, to: kr.lowerBound) >= spEnd
                }.max(by: { $0.count < $1.count })
                if let hit { mvJaFound = moveNameOrig[hit] }
            }
            if mvJaFound == nil && onField, let lr = nt.range(of: "ノ", options: .backwards) {
                // 最後の「の」以降を技名候補として緩く照合する (濁点・半濁点の
                // OCR ゆれ対策。実例: 「あいて相手のゾロアークのハイパーポイス！」
                // = ハイパーボイス が日本語のまま漏れた、2026-11-20 vs Foxy2905 戦)
                // ※ nt は正規化済みで「の」は「ノ」になっている。従来は「の」で
                // 探していたためこのフォールバックは一度も発火していなかった
                // (検証 R3 で検出)
                let tail = String(nt[lr.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "！!"))
                if tail.count >= 3 { mvJaFound = moveNameLoose(tail) }
            }
        }
        if let mvJa = mvJaFound {
                let moveEn = moveJa2En[mvJa] ?? mvJa
                // 同じ文が OCR ゆれ違いで二重に処理されても |move| は 1 回だけ。
                // さらにターン内では同じ枠の同じ技は 1 回だけにする (古い文の
                // 再処理で同じターンの技が繰り返し出た実例: 2026-11-20、
                // ひんし後のグレンアルマの アーマーキャノン 等の再演ブロック)
                let sig = slot + "|" + moveEn + "|t" + String(currentTurn)
                if lastMoveSigAt[sig] != nil {
                    // 同じ枠の同じ技が同じターン番号ですでに出ている場合でも、
                    // その後に技行が 2 件以上進み 10 秒以上経っていて、その枠が
                    // この区間ですでに技を使っているなら、ターン境界の検出が
                    // 遅れている次ターンの技とみなして通す (ターン行は
                    // emitLog のガードが先に出す)。ログ画面の再読のような
                    // 近接した再処理は従来どおり落とす (実例: 2026-11-22
                    // battle_20261122_091721、こだわりスカーフのニョロトノの
                    // だくりゅう が境界検出より先に届いて重複として落ち、
                    // 被ダメ行だけが前のターンに付いた)
                    let moverLabel = "\(slot): \(sp.en)"
                    let advanced = actionSeq - (lastMoveSigSeq[sig] ?? 0) >= 2
                    let waited = Date().timeIntervalSince(lastMoveSigAt[sig]!) >= 10
                    if !(movesSinceTurnLine.contains(moverLabel) && advanced && waited) { return true }
                }
                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                lastMoveSigAt[sig] = Date()
                lastMoveSigAt[slot + "|" + moveEn] = Date()
                lastMoveSigSeq[sig] = actionSeq
                lastMoveLabel = "\(slot): \(sp.en)"
                lastMoveMsgAt = Date()
                lastMoveName = moveEn
                synthesizeMegaIfPending(side: side, speciesEn: sp.en)
                emitLog("|move|\(slot): \(sp.en)|\(moveEn)")
                lastMoveSeq = actionSeq
                applyMoveField(mvJa, side: side)  // 判明登録は |move| 行の applyEvent が行う
                return true
        }
    }
    // シンプルビームの特性変化: 「<種族>は たんじゅんになった！」を
    // 特性の変化として構造化する (実例: 2026-11-22
    // battle_20261122_091721、効果文が未翻訳のまま残り、特性変化の
    // 行が無かった)
    if t.contains("たんじゅんになった") || t.contains("たんじゅんになつた")
        || foldDakuten(t).contains("たんしゆんになった") {
        if let e = findAllSpeciesJa(in: t).first(where: { cand in lastSlots.values.contains { $0.speciesEn == cand.en } }) {
            let bSide = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en ? "p2" : "p1"
            emitLog("|-ability|\(slotFor(side: bSide, speciesEn: e.en)): \(e.en)|Simple")
        }
        return true
    }
    // エレクトロショットの吸収文: 「<種族>は 電気を 吸収した！」は
    // 雨天時の即時発射の告知で、技行と特攻上昇行は別の文から出るため、
    // 文は消費だけする (実例: 2026-11-22 battle_20261122_091721、
    // 2 回とも未翻訳として残った)
    if t.contains("電気を吸収した") || t.contains("電気を吸収し") {
        return true
    }
    // まもる成功: 「<対象>は 攻撃から 身を守った！」(守つた の OCR 崩れも拾う)
    // activate 行は、同じターンにその枠の まもる の技行がある場合だけ
    // 出す。技行なしの activate は、過去ターンの確認文の再読 (ログ画面
    // 等) が作る偽の記録になる (実例: 2026-11-21
    // battle_20261121_234913 ターン2、技行のない Protect の activate)
    if t.contains("身を守った") || t.contains("身を守つた") || t.contains("守りの入った")
        || (t.contains("体勢") && t.contains("守り") && t.contains("入った")) {
        let pk = slot + "|protect"
        if let at = lastSingleActAt[pk], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = Date()
        if protectMoveTurn[slot] == currentTurn {
            emitLog("|-activate|\(slot): \(sp.en)|move: Protect")
        }
        return true
    }
    // 状態異常で動けない (行動失敗。実例: 2026-11-20 の対戦で
    // 「イエツサンは 体がしびれて 動けない！」が日本語のまま漏れた)
    // 「動けない」の 動 が 勤 に崩れる OCR ゆれも拾う (実例: 2026-11-22
    // battle_20261122_070237、「凍ってしまって勤けない！」が行動不能行と
    // 併記で日本語のまま残った)
    let cantVerb = t.contains("動けない") || t.contains("勤けない")
    let cantCode = (t.contains("しびれて") && cantVerb) ? "par"
        : (t.contains("凍って") && cantVerb) ? "frz"
        : (t.contains("ひるんで") && t.contains("だせない")) ? "flinch"
        : (t.contains("眠っている") || t.contains("ねむっている")) ? "slp" : ""
    if !cantCode.isEmpty {
        let cantKey = slot + "|cant"
        if let at = lastSingleActAt[cantKey], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[cantKey] = Date()
        emitLog("|-cant|\(slot): \(sp.en)|\(cantCode)")
        return true
    }
    // このゆびとまれの効果 (OCR ゆれで二重に処理されても 1 回だけ出す)
    if t.contains("注目の的に") && t.contains("なった") {
        if let at = lastSingleActAt[slot], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[slot] = Date()
        emitLog("|-singleactivate|\(slot): \(sp.en)|move: Follow Me")
        return true
    }
    // 特性の表示: 「<種族>の<特性>」の隣接形だけを拾う (文中の偶然の一致を避ける)
    for (norm, orig) in abilityDict where !norm.isEmpty {
        if nt.contains(normalize(sp.ja + "の") + norm) {
            emitAbilityOnce(slot: slot, side: side, speciesEn: sp.en, abilityEn: abilityJa2En[orig] ?? orig)
            applyAbilityField(orig)
            break
        }
    }
    // きあいのタスキで もちこたえた: 持ち物の判明として記録し、専用行を出す
    // (実例: 2026-11-20 vs Zycloud 戦、グライオンのタスキ発動が日本語のまま漏れた)
    if t.contains("もちこたえた") {
        let sk = slot + "|sash"
        if let at = lastSingleActAt[sk], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[sk] = Date()
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "きあいのタスキ")
        emitLog("|-activate|\(slot): \(sp.en)|item: Focus Sash")
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // いのちのたまの反動 (実機文面は「いのちのたまの 効果で 命が少し削られた」。
    // OCR 崩れで「いのち命が少し削られた」と読まれることがある)。
    // 判明の帰属は「直近に技を使った枠」と一致する場合だけに限る: 種族名の
    // 誤読で無関係なポケモンに判明が付いた実例がある (2026-11-20、エーフィの
    // 反動がカメックス/イエッサンに付いた)。反動は使用者自身にしか起きない
    if t.contains("命が少し削られた") || (t.contains("削られた") && t.contains("いのち")) {
        if lastMoveLabel == "\(slot): \(sp.en)" && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
            emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "いのちのたま")
        }
        return true
    }
    // タイプ軽減きのみの発動 (「<対象>へのダメージを オッカのみが弱めた！」。
    // 実例: 2026-11-20、クレッフィのオッカのみ文が日本語のまま漏れた)
    if t.contains("弱めた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // だっしゅつボタンで戻っていく (交代そのものはプレート側で記録する)
    // 「だつしゅつポタン」のような二重ゆれは、正規化 (カナ統一) してから
    // ッ→ツ+濁点畳みにした形でも判定する (検証 hard R7 #90。素の文で畳むと
    // 前半ひらがな/後半カタカナで割れて一致しないため、正規化を先に掛ける)
    let ejFold = foldDakuten(normalize(t).replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ"))
    if t.contains("だっしゅつボタン") || t.contains("しゅつボタン") || (t.contains("だっしゅつ") && t.contains("ボダン")) || (t.contains("ボタン") && (t.contains("戻って") || t.contains("もどって"))) || ejFold.contains("タツシュツホタン") {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "だっしゅつボタン")
        return true
    }
    // 交代技で戻っていく文 (すてゼリフ等: 「<種族>は<相手>の元へ
    // 戻っていく！」)。交代そのものはプレート側で記録するため、
    // ここでは消費だけする。OCR 崩れ (戻→買、場所→完) でも拾う
    // (実例: 2026-11-22 battle_20261122_051707、ターン2の正しい
    //  文面とターン3の崩れた文がどちらも |-message| に残った)
    if (t.contains("戻ってい") || t.contains("買ってい") || t.contains("どってい"))
        && (t.contains("元へ") || t.contains("完へ") || t.contains("場所") || t.contains("もと")) {
        // 戻ることが確定しているため、後任の交代はプレート 1 回の
        // 読みで確定してよい (通常の 2 回確認だと、相手の交代行や
        // ターン終了時の回復行が先に出て順序がずれる。実例:
        // 2026-11-22 battle_20261122_054802 ターン4)
        pivotReturnAt[side] = Date()
        return true
    }
    // せんせいのツメの発動 (実例: 2026-11-20 の対戦で「キュウコンは
    // せんせいのツメで 行動が はやくなった！」が日本語のまま漏れた)
    if t.contains("せんせいのツメ") || t.contains("せんせいのつめ") {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "せんせいのツメ")
        return true
    }
    // 道具を手に入れた (トリック等で相手の道具が移った場合の判明。
    // 実例: 2026-11-20 vs Gmoneys 戦「イエッサンはこだわりスカーフを
    // 手に入れた！」が日本語のまま漏れ、道具も判明しなかった)
    if t.contains("手に入れた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        return true
    }
    // トリック等の道具交換そのもの (「おたがいの道具を入れ替えた」。
    // 道具 は OCR で「道負」と崩れる。交換自体は消費し、移った道具は
    // 直後の「手に入れた」文で判明させる)
    if (t.contains("道具") || t.contains("道負")) && t.contains("入れ替えた") {
        return true
    }
    // 持ち物の判明: 発動・消費などの文脈があるときだけ拾う
    if t.contains("食べ") || t.contains("発動") || t.contains("なくなった") || t.contains("効果で"),
       let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        // 消費・喪失が伴う文脈なら かるわざ の判定へ (きのみを食べた /
        // 軽減きのみの発動 / 持ち物がなくなった)
        if t.contains("なくなった") || ((itemJa2En[itJa] ?? "").hasSuffix("Berry") && (t.contains("食べ") || t.contains("発動"))) {
            noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        }
    }
    // ふうせんが割れた (持ち物の判明と喪失を同時に記録する。割れた文には
    // 従来の判明分岐の手がかり (食べた/発動/なくなった) が無いため漏れていた。
    // 実例: 2026-11-21 vs Woxofyl 戦、ブリジュラスの文が日本語のまま漏れた)
    if t.contains("ふうせん") && (t.contains("割れた") || t.contains("われた")) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "ふうせん")
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // 身代わりの出現 (技行と消費 HP の行は別経路で出るため、ここでは
    // 開始行だけを出す。既に出ている場合は再読として消費だけする。
    // 実例: 2026-11-21 vs Woxofyl 戦、ゲンガーの出現文が日本語のまま漏れた)
    if t.contains("身代わり") && (t.contains("現れた") || t.contains("あらわれた")) {
        if !subActive.contains(key) { emitLog("|-start|\(slot): \(sp.en)|Substitute") }
        return true
    }
    // 身代わりが攻撃を受けた (身代わりへの被弾では本人の HP が動かないため
    // プレート側では行が出ず、この文が唯一の記録になる。
    // 実例: 2026-11-21 vs Woxofyl 戦、ゲンガーの身代わりへのシャドーボール)
    if t.contains("身代わり") && (t.contains("攻撃を受けた") || t.contains("攻撃をうけた")) {
        let pk = slot + "|subhit"
        if let at = lastSingleActAt[pk], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = Date()
        emitLog("|-activate|\(slot): \(sp.en)|move: Substitute")
        return true
    }
    // 回復の告知文: 回復そのものはプレート側で |-heal| を出すため消費のみ
    // (グラッシーフィールド等の回復文が OCR 崩れで漏れた実例: 2026-11-20
    // 「オオニューラのかいふく琳力が回復した！」。持ち物の判明はこの前段の
    // 持ち物分岐が先に処理する)
    if t.contains("回復した") { return true }
    // ひんし (プレート側で既に 0% になっている場合も文は消費する。
    // 消費しないと |-message| に化けて同じ文が残り続ける)。
    // 末尾の濁点ゆれ (たおれだ) も拾う (実例: 2026-11-22
    // battle_20261122_070237、ひんし文が faint 行と併記で残った)
    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        if (monStates[key]?.hpPercent ?? 0) > 0 {
            // 場の占有として記録されていない種族の ひんし文では、
            // 被ダメ行の合成も ひんし行も出さない。未登録のまま倒れた
            // 個体の文や枠解決の誤りで、無関係な枠の HP 基準
            // (lastEmittedPct) を 0 に潰し、後続の正しいプレート読み
            // まで棄却する事故になるため (実例: 2026-11-22
            // battle_20261122_071457、コータスの ひんし文が p1a に
            // 解決され、リキキリンの正しい 65% 読みが棄却された)。
            // 文自体は消費する
            let faintPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            let faintOccupant = lastSlots[faintPn]?.speciesEn
            let faintIsOccupant = (faintOccupant.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[faintPn] == sp.en
            if !faintIsOccupant {
                debugCapture(kind: "faint_guard", key: "faint_guard:untracked:\(slot):\(sp.en)", rawText: t,
                             detail: ["reason": "faint_text_untracked", "slot": slot, "species": sp.en, "occupant": faintOccupant ?? "", "turn": currentTurn])
                return true
            }
            // プレートで 0% を読む前に倒れた場合 (ひんしアニメーションで
            // プレートがすぐ消える等)、被ダメ行もここで補う
            // (実例: 2026-11-20、イエッサンとオオニューラの ひんし に
            //  被ダメ行が付かなかった)
            let pn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
            if !pn.isEmpty && (lastEmittedPct[pn] ?? 1) > 0 {
                heldLine[pn] = nil
                let fhp = monStates[key]?.hpMax.map { "0/\($0)" } ?? "0/100"
                _ = emitDamageLine(plateName: pn, slot: slot, key: key, speciesEn: sp.en,
                                   fromPct: lastEmittedPct[pn] ?? (monStates[key]?.hpPercent ?? 100),
                                   toPct: 0, hpText: fhp, force: true)
            }
            // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
            deferFaint(slot: slot, speciesEn: sp.en)
        }
        return true
    }
    checkStatusText(text: t, side: side, speciesEn: sp.en, slot: slot)
    // サイコアップ: 「<使用者>は <対象>の 能力変化を コピーした！」
    // (文中に上がった/下がったが無いため、ランク変化の照合では拾えない)
    if t.contains("能力変化") && (t.contains("コピー") || t.contains("コビー")) {
        let subjects = findAllSpeciesJa(in: t)
        if subjects.count >= 2 {
            let copier = subjects[0], target = subjects[1]
            let cInOpp = lastSlots["oppA"]?.speciesEn == copier.en || lastSlots["oppB"]?.speciesEn == copier.en
            let cInMine = lastSlots["mineA"]?.speciesEn == copier.en || lastSlots["mineB"]?.speciesEn == copier.en || teamEntries[copier.en] != nil
            let cSide = cInOpp && !cInMine ? "p2" : "p1"
            let tInOpp = lastSlots["oppA"]?.speciesEn == target.en || lastSlots["oppB"]?.speciesEn == target.en
            let tInMine = lastSlots["mineA"]?.speciesEn == target.en || lastSlots["mineB"]?.speciesEn == target.en || teamEntries[target.en] != nil
            let tSide = tInOpp && !tInMine ? "p2" : "p1"
            copyBoosts(fromKey: "\(tSide):\(target.en)", toKey: "\(cSide):\(copier.en)",
                       slot: slotFor(side: cSide, speciesEn: copier.en), speciesEn: copier.en)
        }
        return true
    }
    // たくわえるの蓄積数文: 「<種族>は Nつ たくわえた！」は技が成功
    // した証拠。技告知文を取りこぼした場合は、ここから技行を補う
    // (実例: 2026-11-22 battle_20261122_091721 ターン2、告知文が
    // 断片化して技行が無く、上昇行だけが残った)。既にこの区間で
    // その枠の技行がある場合は消費だけする
    if t.contains("たくわえた") {
        if let e = findAllSpeciesJa(in: t).first {
            let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
            let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
            if inOpp || inMine {
                let mSide = inOpp && !inMine ? "p2" : "p1"
                let mSlot = slotFor(side: mSide, speciesEn: e.en)
                let mLabel = "\(mSlot): \(e.en)"
                if !movesSinceTurnLine.contains(mLabel) {
                    lastMoveSigAt["\(mSlot)|Stockpile|t\(currentTurn)"] = Date()
                    lastMoveSigAt["\(mSlot)|Stockpile"] = Date()
                    lastMoveSigSeq["\(mSlot)|Stockpile|t\(currentTurn)"] = actionSeq
                    lastMoveLabel = mLabel
                    lastMoveMsgAt = Date()
                    lastMoveName = "Stockpile"
                    emitLog("|move|\(mLabel)|Stockpile")
                    lastMoveSeq = actionSeq
                    applyMoveField("たくわえる", side: mSide)
                }
            }
        }
        return true
    }
    // ランク変化文の断片 (主語と能力名だけが先に届き、上がった/
    // 下がったが次の読みに分かれた文) を覚えておく。方向の文が主語
    // なしで届いたら、断片と結合して適用する (実例: 2026-11-22
    // battle_20261122_091721 ターン4、たくわえる の「防御特防が」と
    // 「ぐーんと上がった！」が別々の読みに分かれ、上昇行が丸ごと落ちた)
    if !(t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
         || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた")) {
        let statWords = ["攻撃", "防御", "特攻", "特防", "素早さ", "命中率", "回避率",
                         "こうげき", "ぼうぎょ", "とくこう", "とくぼう", "すばやさ"]
        if statWords.contains(where: { t.contains($0) }) {
            let subs = boostSubjects(in: t)
            if subs.count == 1 {
                let e = subs[0]
                let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en
                let fSide = (t.contains("相手の") || t.contains("あいての")) && inOpp ? "p2" : (inOpp && !inMine ? "p2" : "p1")
                prevBoostFragment = (text: t, speciesEn: e.en, side: fSide, at: Date())
            }
        }
    }
    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する
    // 動詞は漢字表記 (上がった/下がった) も対象にする。小さい「っ」が「つ」に
    // 崩れた形もここで拾う (checkBoostText 自体は対応済みだが、この入口の
    // 判定に無かったため崩れた文が正規経路に入れなかった。検証 R1 で検出)
    if t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった")
        || t.contains("あがつた") || t.contains("さがつた") || t.contains("上がつた") || t.contains("下がつた") {
        // 主語を場のフォルムに寄せる (イエッサン -> イエッサンF 等)。寄せないと
        // 枠が特定できず、二重適用防止のキーが他方と衝突して変化が丸ごと落ちる
        // (実例: 2026-11-20 vs BigGuyMan 戦、いかくのイエッサン分が消えた)。
        // さらに文法上の主語だけに絞る (boostSubjects): 文中に紛れた
        // 無関係な種族名への重複付与を防ぐ
        let subjects = boostSubjects(in: t)
        // ランク変化の側の決定: 文中の側マーカー (相手の/味方の) を
        // 最優先し、両側の場に同種族がいる場合は直前の技の使用者と
        // 一致する側を優先する (自分の技による自己変化は使用者に付く。
        // 実例: 2026-11-21 battle_20261121_234913、げんしのちからの
        // 全能力上昇が、両軍にいるリザードンのうち対象ではなく
        // 使用者ではない自軍側へ付いた)
        func resolvedBoostSide(_ e: SpeciesEntry) -> String {
            let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
            let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en || teamEntries[e.en] != nil
            if (t.contains("相手の") || t.contains("あいての")) && inOpp { return "p2" }
            if t.contains("味方の") && inMine { return "p1" }
            if inOpp && inMine && lastMoveLabel.hasSuffix(": \(e.en)")
                && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
                return lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }
            return inOpp && !inMine ? "p2" : "p1"
        }
        // いかくの帰属はランク変化の行より先に [特性] 行を出すため、適用前に行う
        if (t.contains("さがった") || t.contains("下がった") || t.contains("さがつた") || t.contains("下がつた")) && (t.contains("攻撃") || t.contains("こうげき") || t.contains("コウゲキ")) && !t.contains("ぐーんと") {
            var targetSides = Set<String>()
            if subjects.count >= 2 {
                for e in subjects {
                    let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                    let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en || teamEntries[e.en] != nil
                    targetSides.insert(inOpp && !inMine ? "p2" : "p1")
                }
            } else {
                targetSides.insert(side)
            }
            for ts in targetSides { attributeIntimidate(targetSide: ts) }
        }
        if subjects.count >= 2 {
            for e in subjects {
                let sSide = resolvedBoostSide(e)
                checkBoostText(text: t, side: sSide, speciesEn: e.en, slot: slotFor(side: sSide, speciesEn: e.en))
            }
        } else if subjects.count == 1, subjects[0].en != sp.en {
            // 文法上の主語が、照合で先に掴んだ種族 (混入した名前等) と
            // 食い違う場合は、主語の方へ適用する
            let e = subjects[0]
            let sSide = resolvedBoostSide(e)
            checkBoostText(text: t, side: sSide, speciesEn: e.en, slot: slotFor(side: sSide, speciesEn: e.en))
        } else {
            // 通常経路はアンカーの側を使う。ただし両側の場に同種族が
            // いて、直前の技の使用者がその種族の場合は、使用者の側を
            // 優先する (自己変化の帰属。アンカーは側マーカーが落ちた
            // 文では自軍に寄るため)
            var sSide = side
            let inOppF = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
            let inMineF = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en
            if inOppF && inMineF && lastMoveLabel.hasSuffix(": \(sp.en)")
                && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
                sSide = lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }
            checkBoostText(text: t, side: sSide, speciesEn: sp.en, slot: slotFor(side: sSide, speciesEn: sp.en))
        }
        // 適用した変化の行が保留中でも、この文は消費済みとして扱う
        if battleLog.count > before || heldBoostLines.values.contains(where: { !$0.isEmpty }) { return true }
    }
    return battleLog.count > before
}

// 重複ボックスを落とす。Vision が同じ文字を単語ボックスと行ボックスの
// 両方で返すことがあり (実例: 2026-11-22 battle_20261122_050512 の
// メガ発表文で「相手の」が二重になった)、結合すると語が重複する。
// より大きなボックスに矩形ごと内包され、そのテキストにも含まれる
// ボックスだけを重複として除く
func dedupeContainedBoxes(_ boxes: [OcrBox]) -> [OcrBox] {
    return boxes.filter { a in
        !boxes.contains { b in
            b.text.contains(a.text) && !a.text.isEmpty
                && a.x0 >= b.x0 - 0.01 && a.x1 <= b.x1 + 0.01
                && a.y0 >= b.y0 - 0.01 && a.y1 <= b.y1 + 0.01
                && (b.x1 - b.x0) * (b.y1 - b.y0) > (a.x1 - a.x0) * (a.y1 - a.y0)
        }
    }
}

// ルビ (ふりがな) のボックスを落とす。ゲーム内メッセージでは漢字の
// 上に小さなルビが表示され (例: 味方→みかた、周り→まわ、守→まも)、
// 位置順に結合するとルビが本文へ混入して文が崩れる (実例:
// 2026-11-21 battle_20261121_224409 のワイドガード持続告知)。
// ルビは本文より明らかに小さく、本文の字の直上に重なるため、
// その 2 条件がそろう小さいボックスだけを除く。本文が行単位の
// ボックスで返る場合は行ボックスがルビ帯まで含むため、その場合は
// 行ボックスの上部に内包される小ボックスをルビとする (実例:
// 2026-11-22 battle_20261122_050512 のメガ発表文)
func dropRubyBoxes(_ boxes: [OcrBox]) -> [OcrBox] {
    let heights = boxes.map { $0.y1 - $0.y0 }.sorted()
    guard !heights.isEmpty else { return boxes }
    let med = heights[heights.count / 2]
    if med <= 0 { return boxes }
    return boxes.filter { b in
        let h = b.y1 - b.y0
        if h >= 0.62 * med { return true }
        let isRuby = boxes.contains { o in
            let oh = o.y1 - o.y0
            return oh >= 0.8 * med && o.x0 < b.x1 && b.x0 < o.x1
                && (abs(o.y0 - b.y1) <= 0.02
                    || (b.y0 >= o.y0 - 0.005 && b.y1 <= o.y0 + 0.55 * oh))
        }
        return !isRuby
    }
}

func watchBattleMessage(image: CGImage, platesVisible: Bool) {
    let boxes = ocrBoxes(image, x0: 0, y0: 0.66, x1: 1, y1: 1)
    // プレートが見えているとき、その文字だけをメッセージから除く。
    // 以前は「cy>0.82 かつ cx<0.47」を一律に除いており、被弾時の単体プレート
    // 表示中はメッセージ 2 行目 (「毒を あびた！」等) まで消えてしまい、
    // 状態異常や急所が一切拾えなかった (実機動画で確認)。
    // 実測: メッセージ行は cy≈0.79/0.86。コマンド時のプレートは名前 ≈0.90 /
    // HP ≈0.95、単体表示時は名前 ≈0.84 / HP ≈0.88 に上がる。
    let activeJa = Set(lastSlots.values.compactMap { s in speciesDict.first { $0.en == s.speciesEn }?.ja })
    let filteredBoxes = boxes.filter { b in
        guard platesVisible else { return true }
        if b.cy > 0.90 && b.cx < 0.30 { return false }   // コマンド時のプレート文字
        if b.cy > 0.82 && b.cx < 0.30 {                   // 単体プレートの残り文字
            let digits = asciiDigits(b.text).replacingOccurrences(of: " ", with: "")
            if digits.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil { return false }
            if activeJa.contains(b.text) { return false }
        }
        return true
    }
    let msgBoxes = dropRubyBoxes(dedupeContainedBoxes(filteredBoxes)).sorted { ($0.cy, $0.x0) < ($1.cy, $1.x0) }
    let text = msgBoxes.map { $0.text }.joined(separator: "")
    let norm = normalize(text)
    if norm.count < 4 { return }
    // 同一文の再処理は 4 秒間だけ抑止する (表示は最長でも約3秒のため。
    // 毒ダメージのように同じ文が後で再表示されたら、それは新しい出来事)
    let now = Date()
    if norm == lastMsgNorm && now.timeIntervalSince(lastMsgAt) < 4 { return }
    // コマンド選択中の文 (「〜は どうする？」等) はイベントではない
    if text.contains("どうする") || text.contains("選んでください") || text.contains("選ばれました") { lastMsgNorm = norm; lastMsgAt = now; return }
    if translateBattleMessage(text) {
        lastMsgNorm = norm; lastMsgAt = now
    } else if salvageFromText(text) {
        // サルベージ層: 翻訳に失敗した文から、確度の高い信号だけを拾って
        // 状態に反映した (拾えた場合も、重複と分かった場合も消費する)
        lastMsgNorm = norm; lastMsgAt = now
    } else if isBoostShapedText(text) {
        // ランク変化の形をした文で、サルベージでも帰属できなかったものは
        // 生文として残さない (帰属できない以上、推測で状態には入れない)
        // (実例: 2026-11-20 vs BigGuyMan 戦の いかく 複合文)
        lastMsgNorm = norm; lastMsgAt = now
    } else if isMoveFragmentText(text) {
        // 技告知文の断片 (種族名が欠けた OCR 崩れ) も生文として残さない
        lastMsgNorm = norm; lastMsgAt = now
    } else if text.hasSuffix("！") || text.hasSuffix("。") || text.hasSuffix("？") || text.hasSuffix("ました") {
        // 翻訳できない文も、完結した文ならそのまま残す。
        // ただし直前の |-message| と似た文は OCR ゆれの再読として 1 件にまとめる
        if Date().timeIntervalSince(lastFallbackAt) < 6 && textSimilarity(norm, lastFallbackText) >= 0.6 {
            lastMsgNorm = norm; lastMsgAt = now
        } else {
            emitLog("|-message|\(text)")
            debugCapture(kind: "untranslated", key: norm, rawText: text,
                         detail: ["boxes": msgBoxes.map { $0.text },
                                  "moveLoose": moveNameLoose(text) ?? NSNull(),
                                  "speciesLoose": findSpeciesJa(in: text)?.en ?? NSNull()],
                         image: image)
            lastFallbackText = norm; lastFallbackAt = now
            lastMsgNorm = norm; lastMsgAt = now
        }
    }
    flushHeldBoostsTimeout()
    emitPendingFaints()
}

// MARK: - 選出画面での相手チーム同定 (タイプアイコン + モデル照合)
// 方式: 相手パネルのタイプアイコンを分類 → チャンピオンズ実装種族をタイプで絞る →
// パネル内の 3D モデルを HOME 画像の特徴量 (dHash・色分布・形) と候補内だけで照合。
// タイプで一意に決まる枠と、照合の差が決定的な枠はそのまま登録。際どい枠は
// 1 位を仮置きする (候補一覧はターミナルにのみ出す。UI には候補表示しない)。
// でんき は当初テンプレート未収録で、黄色バッジが かくとう/いわ 等へ
// 誤分類され続けていた (ヒートロトム→ウインディ(ヒスイ) 等、タイプで
// 確定してしまう事故の原因)。テンプレート追加に加え、バッジ色の中央値が
// 黄色優位なら でんき と確定する色判定を pvClassifyIcon に入れている
// (黄色は全タイプ中で唯一。白い稲妻グリフとのコントラストが低く、
// グリフ照合だけでは色項の近いタイプに負けるため)。アイコンが
// 読めないタイプは「不明」として候補を広げる (誤判定より安全側)。

var previewHandled = false
var previewFrames = 0
var previewAttempts = 0                    // この選出セッションでの同定試行回数
var previewBestTeam: [String?] = []        // 試行をまたいでマージした最良の同定結果
var previewTeamWritten = false             // このセッションで oppReset 付きの初回書き込みをしたか
// 複数フレーム投票 (第1段 (a)): 枠ごとに種族への票と最良スコアを蓄積し、
// 2 フレームで一致した種族 (またはタイプで確定した種族) をその枠の
// 「確定」としてロックする。従来の「後勝ち」マージでは、確定度の高い
// 結果が後の不安定な照合で上書きされうるため、確定した枠は以後
// 別の種族に置き換えない。未確定の枠は票の多い順 (同数なら最良
// スコアの小さい順) の暫定 1 位を表示する。
var previewVotes: [[String: Int]] = []          // 枠ごとの種族別投票数
var previewVoteScore: [[String: Double]] = []   // 枠ごとの種族別ベストスコア
var previewLocked: [String?] = []               // 枠ごとの確定種族 (nil = 未確定)
// 見せ合い同定の証拠: 同定のたびに最新のフレームと枠情報を保持し、
// 試合が始まったらその試合のデバッグ同梱として書き出す (runOnce 参照)。
// 実フレームが残らないと系統的な誤認の原因を後から特定できないため
// (実例: 2026-11-20 の vs Ryzz 戦 2 試合、6 枠中 4 枠が同一の誤認)
var previewEvidenceImage: CGImage? = nil        // 最後に同定を試みたフレーム
var previewEvidenceSlots: [PvSlotInfo] = []     // そのフレームの枠ごとの同定情報
var previewEvidenceTeam: [String?] = []         // その時点のマージ済み同定結果
var previewEvidenceVotes: [[[String: Any]]] = []  // その時点のマージ票数 (枠ごと・種族ごと)
var previewEvidenceAt: Date? = nil
// 見せ合い画面の最終フレーム (同定が走らなかった・失敗した試合でも
// 画面自体は証拠として残すための保持。preview_id の全試合保証用)
var previewLastImage: CGImage? = nil
var previewLastImageAt: Date? = nil
var previewIdWritten = false                    // この試合で preview_id を書き出したか
// マッチング画面の表示用 (ユーザーがターミナルで状態を把握するため。
// 表示専用で、ログ構築には一切影響しない)
var matchingActive = false
var matchingSince: Date? = nil
var matchingLastPrintAt: Date? = nil
// 見せ合い後に一瞬映る相手のランク/レートの読み取り結果。記録側
// (UI以外チャットの管轄) がトレーナー名と一緒に state.json /
// 対戦ログへ記録するための受け渡し変数 (同チャットとの合意形式:
// 読めなければ "" のまま。初期化は記録側が resetLogState で行う)
var oppRating = ""
var oppRank = ""
var oppRankRecorded = false   // この対戦で opp_rank の証拠を記録済みか
// タイプ関門の緩和 (第1段 (b)): タイプで絞った候補内の最良スコアが
// この値より悪い場合は、アイコンの読み違いとみなして全種族へ候補を
// 広げて再照合する。閾値は tests/preview_eval.py --calibrate の測定で
// 較正した (正しいプールの最良スコア p90 ≈ 0.10、誤ったプールの
// 最良スコア中央値 ≈ 0.39。同定率は閾値 0.35 で正解時 86% /
// 読み違い時 54%、0.25 で 86% / 75% と、0.25 が最もバランスが良い)。
let pvSoftGateScore = 0.25
// 見せ合い画面には現れないフォルム (対戦中の変化でのみ現れる)。
// 見せ合いの同定候補から除外する。メガが素の見せ合い枠として選ばれ、
// ヘッダーに入る事故の防止 (2026-11-21 battle_20261121_145658 で
// Meowstic-M-Mega がヘッダーに入った)。loadPvData で構築する
var pvBattleOnlyFormes: Set<String> = []
// 全種族へ広げた再照合を採用する条件: 広げた先の最良が元の最良より
// この値以上良いこと。実フレーム (2026-11-21、ユーザー提供の見せ合い
// 画面) では、正しいプールのスコアがゲーム内モデルと HOME 参照の
// ポーズ差で 0.4 前後まで悪化し、従来の 0.03 では性別違い等の
// 無関係な種族への飛び移りが起きた (例: ゴリランダー♂の枠で
// ロトムやツアリーナが上位に来る)。0.20 に広げても代理測定の
// 読み違い救済率は下がらないことを tests/preview_eval.py で確認済み
let pvExpandMargin = 0.20
// アイコン分類で 1 位と 2 位の距離差がこれ未満なら分類は近接として
// 扱い、両タイプのプールを統合する (距離逆転でプールが誤固定される
// 事故の防止。実例: 2026-11-21 battle_20261121_233243 枠3、
// Grass アイコンが Bug=0.167 / Grass=0.205 と逆転し Rillaboom の
// 枠が Pinsir 単独プールになった)
let pvIconAmbigDelta = 0.05
// パネルのレイアウト幅と高さの比 (実フレーム4件で実測: エンジ色幅が
// 健全な全画面フレームでは高さの約2.5〜2.6倍)。アイコン・性別の
// サンプリング幅は、エンジ色の実測幅がこれを下回る場合に高さから
// 推定した幅を使う (ウィンドウ表示等の縮小フレームではエンジ色の
// 本体がレイアウト幅より狭く取れ、第2アイコンがパネル外に出る。
// 2026-11-21 preview_test_20261121_171741 で確認)
let pvPanelAspect = 2.6
// 選出同定 1 枠分の結果 (投票・マージ用)
struct PvSlotInfo {
    var pick: String? = nil        // このフレームで割り当てた種族
    var score: Double = 9          // 割り当て種族の照合スコア (小さいほど良い)
    var decisive: Bool = false     // タイプで確定 (かつ照合でも裏付けあり)
    var expanded: Bool = false     // タイプ関門を広げて再照合した結果か
    var types: [String] = []              // その枠で読み取ったタイプアイコン
    var candidates: [(String, Double)] = []  // その枠の候補上位 (種族, スコア)
    var gender: String = ""               // 読み取った性別マーク ("M" / "F" / "" = 不明)
    var panel: [Int] = []                 // 検出パネル矩形 [x, y, w, h] (証跡用)
    var iconDiag: [String] = []           // アイコン分類の診断文字列 (証跡用)
    var genderCounts: [Int] = []          // 性別読みの生カウント [赤, 青] (証跡用)
}
var pvSpeciesTypes: [String: [String]] = [:]
var pvSpeciesGender: [String: [String]] = [:]   // 種族 → なりうる性別 ("M"/"F"/"N")
var pvFeatures: [String: (hash: [UInt8], hue: [Double], aspect: Double, density: Double)] = [:]
// 実フレームテンプレート: 正解が確定した見せ合い画像から抽出した特徴。
// preview_features.json の各エントリの "templates" に同梱される
// (build_frame_templates.py が登録する)。種族のスコアは本参照と
// テンプレート群の最小を取る (pvBestScore)
var pvTemplateFeatures: [String: [(hash: [UInt8], hue: [Double], aspect: Double, density: Double, gender: String)]] = [:]
var pvTypeIcons: [String: (rgb: [Double], glyph: [Double])] = [:]
var pvDataLoaded = false

func pvJa(_ en: String) -> String { speciesDict.first { $0.en == en }?.ja ?? en }

func pvNumArray(_ v: Any?) -> [Double] {
    (v as? [Any])?.map { ($0 as? NSNumber)?.doubleValue ?? 0 } ?? []
}

func loadPreviewData() {
    let dir = scriptDir.appendingPathComponent("data")
    guard let tdata = try? Data(contentsOf: dir.appendingPathComponent("species_types.json")),
          let tobj = try? JSONSerialization.jsonObject(with: tdata) as? [String: Any],
          let fdata = try? Data(contentsOf: dir.appendingPathComponent("preview_features.json")),
          let fobj = try? JSONSerialization.jsonObject(with: fdata) as? [String: Any],
          let idata = try? Data(contentsOf: dir.appendingPathComponent("type_icons.json")),
          let iobj = try? JSONSerialization.jsonObject(with: idata) as? [String: Any] else {
        fputs("選出同定データが読めません (data/species_types.json 等)\n", stderr)
        return
    }
    for (name, v) in tobj {
        if let d = v as? [String: Any], let ts = d["types"] as? [String] { pvSpeciesTypes[name] = ts }
        // 性別は species_types.json の "gender" に同梱されている
        // (別ファイルにすると Mac 側の同期リストに載らず届かないため)
        if let d = v as? [String: Any], let gs = d["gender"] as? [String] { pvSpeciesGender[name] = gs }
    }
    // 見せ合い画面に現れないフォルム (メガ進化と対戦中だけの姿) は
    // 同定候補から外す。名前の末尾で判定できるメガに、名前だけでは
    // 区別できない対戦中フォルムを明示で加える。-Mega-Z は当初
    // 末尾ルールに無く、Absol/Garchomp/Lucario の Z メガ3種が候補に
    // 漏れていた (2026-11-21 preview_test で確認)
    pvBattleOnlyFormes = Set(pvSpeciesTypes.keys.filter {
        $0.hasSuffix("-Mega") || $0.hasSuffix("-Mega-X") || $0.hasSuffix("-Mega-Y")
            || $0.hasSuffix("-Mega-Z")
    }).union(["Greninja-Bond", "Palafin-Hero", "Mimikyu-Busted", "Morpeko-Hangry"]
        .filter { pvSpeciesTypes[$0] != nil })
    for (name, v) in fobj {
        guard let d = v as? [String: Any], let hex = d["hash"] as? String else { continue }
        var bytes: [UInt8] = []
        var idx = hex.startIndex
        while idx < hex.endIndex {
            let nxt = hex.index(idx, offsetBy: 2)
            if let b = UInt8(hex[idx..<nxt], radix: 16) { bytes.append(b) }
            idx = nxt
        }
        pvFeatures[name] = (bytes, pvNumArray(d["hue"]),
                            (d["aspect"] as? NSNumber)?.doubleValue ?? 1,
                            (d["density"] as? NSNumber)?.doubleValue ?? 0)
        if let tlist = d["templates"] as? [[String: Any]] {
            var tpls: [(hash: [UInt8], hue: [Double], aspect: Double, density: Double, gender: String)] = []
            for t in tlist {
                guard let thex = t["hash"] as? String else { continue }
                var tbytes: [UInt8] = []
                var tidx = thex.startIndex
                while tidx < thex.endIndex {
                    let tnxt = thex.index(tidx, offsetBy: 2)
                    if let b = UInt8(thex[tidx..<tnxt], radix: 16) { tbytes.append(b) }
                    tidx = tnxt
                }
                tpls.append((tbytes, pvNumArray(t["hue"]),
                             (t["aspect"] as? NSNumber)?.doubleValue ?? 1,
                             (t["density"] as? NSNumber)?.doubleValue ?? 0,
                             t["gender"] as? String ?? ""))
            }
            if !tpls.isEmpty { pvTemplateFeatures[name] = tpls }
        }
    }
    for (name, v) in iobj {
        if let d = v as? [String: Any] { pvTypeIcons[name] = (pvNumArray(d["rgb"]), pvNumArray(d["glyph"])) }
    }
    pvDataLoaded = !pvSpeciesTypes.isEmpty && !pvFeatures.isEmpty && !pvTypeIcons.isEmpty
}

// フル解像度のピクセルバッファ (行0 = 画像の上端、RGBA)
// コンテキストが作れない画像 (0 サイズ・壊れた取り込み結果) では
// 強制アンラップで落とさず、空バッファ (0, 0) を返して呼び出し側に
// 「絵が無い」として扱わせる
func makeFullBuffer(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = image.width, h = image.height
    if w <= 0 || h <= 0 { return ([], 0, 0) }
    var data = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return ([], 0, 0) }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // 実機 (2026-11-20 の選出画面デバッグ) で、この描画結果は上下反転して
    // いることが判明した: 検出パネルの y が実画像の鏡像位置と全 6 件一致し、
    // アイコンもモデルも裏返しのまま照合されていた (選出同定がゴースト
    // 単色になる等の原因)。描画方法に依存しないよう、最後に行順を反転
    // して「0 行目 = 画像の上端」に統一する。
    var flipped = [UInt8](repeating: 0, count: data.count)
    let rowBytes = w * 4
    for y in 0..<h {
        let srcRow = (h - 1 - y) * rowBytes
        flipped.replaceSubrange(y * rowBytes..<((y + 1) * rowBytes),
                                with: data[srcRow..<(srcRow + rowBytes)])
    }
    return (flipped, w, h)
}

func pvGray(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.299 * r + 0.587 * g + 0.114 * b }

func pvPearson(_ a: [Double], _ b: [Double]) -> Double {
    let n = min(a.count, b.count)
    if n == 0 { return 0 }
    let ma = a.prefix(n).reduce(0, +) / Double(n)
    let mb = b.prefix(n).reduce(0, +) / Double(n)
    var num = 0.0, da = 0.0, db = 0.0
    for i in 0..<n {
        let xa = a[i] - ma, xb = b[i] - mb
        num += xa * xb; da += xa * xa; db += xb * xb
    }
    if da == 0 || db == 0 { return 0 }
    return num / sqrt(da * db)
}

// バイリニアリサイズ (cv2.INTER_LINEAR 相当)。参照特徴
// (preview_features.json) は生成時にバイリニア縮小で作られており、
// モデル照合のハッシュはこの方式に合わせないと、同一画像同士でも
// ハミング距離が 70〜90 ビット開いて照合が大きく鈍る (2026-11-21 に
// tests/preview_eval.py の再現検証で確認。面積平均では 68〜90 ビット、
// バイリニアでは 1〜4 ビット)。アイコンのグリフ照合は従来の面積平均の
// まま (テンプレート抽出時の方式が異なるため pvResizeGray を使う)。
func pvResizeBilinear(_ src: [Double], _ sw: Int, _ sh: Int, _ dw: Int, _ dh: Int) -> [Double] {
    var out = [Double](repeating: 0, count: dw * dh)
    for dy in 0..<dh {
        let fy = (Double(dy) + 0.5) * Double(sh) / Double(dh) - 0.5
        let y0 = Int(floor(fy))
        let wy = fy - Double(y0)
        let ya = max(0, min(y0, sh - 1)), yb = max(0, min(y0 + 1, sh - 1))
        for dx in 0..<dw {
            let fx = (Double(dx) + 0.5) * Double(sw) / Double(dw) - 0.5
            let x0 = Int(floor(fx))
            let wx = fx - Double(x0)
            let xa = max(0, min(x0, sw - 1)), xb = max(0, min(x0 + 1, sw - 1))
            let top = src[ya * sw + xa] * (1 - wx) + src[ya * sw + xb] * wx
            let bot = src[yb * sw + xa] * (1 - wx) + src[yb * sw + xb] * wx
            out[dy * dw + dx] = top * (1 - wy) + bot * wy
        }
    }
    return out
}

// 面積平均リサイズ (cv2.INTER_AREA 相当)
func pvResizeGray(_ src: [Double], _ sw: Int, _ sh: Int, _ dw: Int, _ dh: Int) -> [Double] {
    var out = [Double](repeating: 0, count: dw * dh)
    for dy in 0..<dh {
        let y0 = Double(dy) * Double(sh) / Double(dh)
        let y1 = Double(dy + 1) * Double(sh) / Double(dh)
        for dx in 0..<dw {
            let x0 = Double(dx) * Double(sw) / Double(dw)
            let x1 = Double(dx + 1) * Double(sw) / Double(dw)
            var sum = 0.0
            var yy = Int(y0)
            while yy < Int(ceil(y1)) && yy < sh {
                let wy = min(y1, Double(yy + 1)) - max(y0, Double(yy))
                var xx = Int(x0)
                while xx < Int(ceil(x1)) && xx < sw {
                    let wx = min(x1, Double(xx + 1)) - max(x0, Double(xx))
                    sum += src[yy * sw + xx] * wx * wy
                    xx += 1
                }
                yy += 1
            }
            out[dy * dw + dx] = sum / ((x1 - x0) * (y1 - y0))
        }
    }
    return out
}

// 相手パネル (エンジ色の帯) を検出。6 枚取れなければ固定位置にフォールバック。
// 座標はすべて実測ベース: 行グループは右寄りの帯で探し、各パネルの左右端は
// エンジ色の列分布から測って 6 枚の中央値でそろえる (背景の同色要素で
// 1 枚だけ端が伸びても全体は崩れない)。アイコン位置もパネル相対で決めるため、
// 取り込みフレーム側のずれ・拡大縮小があっても追従できる。
func pvDetectPanels(_ buf: (data: [UInt8], w: Int, h: Int)) -> [(x: Int, y: Int, w: Int, h: Int, cropW: Int)] {
    let W = buf.w, H = buf.h
    func isMaroon(_ x: Int, _ y: Int) -> Bool {
        let i = (y * W + x) * 4
        let r = Int(buf.data[i]), g = Int(buf.data[i + 1]), b = Int(buf.data[i + 2])
        return r > 90 && r - g > 45 && r - b > 15
    }
    let xs = Int(0.55 * Double(W)), xe = Int(0.995 * Double(W))
    var groups: [(Int, Int)] = []
    var start: Int? = nil
    var last = 0
    var rowCounts: [Int] = []
    rowCounts.reserveCapacity(H)
    for y in 0..<H {
        var cnt = 0
        var x = xs
        while x < xe {
            if isMaroon(x, y) { cnt += 1 }
            x += 2
        }
        rowCounts.append(cnt)
        if cnt > (xe - xs) / 20 {
            if start == nil { start = y }
            last = y
        } else if let s = start, y - last > 4 {
            groups.append((s, last)); start = nil
        }
    }
    if let s = start { groups.append((s, last)) }
    var raw = groups.filter { $0.1 - $0.0 >= Int(0.05 * Double(H)) }
    // 異常に背の高い帯は、隣り合うパネル同士がエフェクト等で
    // つながったものとして、内部で最もエンジ色の少ない行で分割する
    // (炎エフェクトが走査範囲に入ると、パネル間の隙間の行でも
    // 閾値を超え、2 枚のパネルが 1 本の帯に融合することがある。
    // 2026-11-21 preview_test_20261121_180739 で確認)
    for _ in 0..<3 {
        if raw.count < 2 { break }
        let hs = raw.map { $0.1 - $0.0 + 1 }.sorted()
        let med = hs[hs.count / 2]
        guard let tall = raw.max(by: { ($0.1 - $0.0) < ($1.1 - $1.0) }),
              Double(tall.1 - tall.0 + 1) > 1.6 * Double(med) else { break }
        let lo = tall.0 + (tall.1 - tall.0) / 5
        let hi = tall.1 - (tall.1 - tall.0) / 5
        if hi <= lo { break }
        var splitRow = lo
        for y in lo...hi where rowCounts[y] < rowCounts[splitRow] { splitRow = y }
        raw.removeAll { $0.0 == tall.0 && $0.1 == tall.1 }
        raw.append((tall.0, splitRow))
        raw.append((splitRow + 1, tall.1))
        raw = raw.filter { $0.1 - $0.0 >= Int(0.05 * Double(H)) }.sorted { $0.0 < $1.0 }
    }
    if raw.count > 6 {
        // 帯が 7 本以上ある場合は、等間隔のグリッドに最もよく合い、
        // かつ高さがそろった 6 本を残す。コストは間隔の分散 + 高さ
        // 偏差の二乗和。余分な帯はグリッドの延長上に来ることも
        // あるため (上下どちらの型も実例あり)、間隔だけでも高さ
        // だけでも決め手にならない (実例: 2026-11-22
        // battle_20261122_070237 の上部の帯、2026-11-21 Jose /
        // benn_test1 の下部の帯)
        let hs = raw.map { $0.1 - $0.0 + 1 }.sorted()
        let med = hs[hs.count / 2]
        var bestCombo: [Int]? = nil
        var bestKey: Double? = nil
        var idx = [0, 1, 2, 3, 4, 5]
        let n = raw.count
        while true {
            let ys = idx.map { Double(raw[$0].0) }
            let diffs = (1..<6).map { ys[$0] - ys[$0 - 1] }
            let mean = diffs.reduce(0, +) / 5.0
            let variance = diffs.reduce(0.0) { $0 + ($1 - mean) * ($1 - mean) }
            let hdevSq = idx.reduce(0.0) { let d = Double(raw[$1].1 - raw[$1].0 + 1 - med); return $0 + d * d }
            let key = variance + hdevSq
            if bestKey == nil || key < bestKey! { bestKey = key; bestCombo = idx }
            var i = 5
            while i >= 0 && idx[i] == n - 6 + i { i -= 1 }
            if i < 0 { break }
            idx[i] += 1
            if i + 1 < 6 { for j in (i + 1)..<6 { idx[j] = idx[j - 1] + 1 } }
        }
        if let combo = bestCombo { raw = combo.map { raw[$0] } }
    }
    if raw.count == 6 {
        // 各パネルの左右端を列分布 (行の半分超がエンジ色の列) から測る
        var x0s: [Int] = [], x1s: [Int] = []
        for (gy0, gy1) in raw {
            let need = (gy1 - gy0 + 1) / 2
            var lo: Int? = nil, hi: Int? = nil
            for x in xs..<xe {
                var c = 0
                for y in gy0...gy1 where isMaroon(x, y) { c += 1 }
                if c > need { if lo == nil { lo = x }; hi = x }
            }
            if let lo, let hi { x0s.append(lo); x1s.append(hi) }
        }
        if x0s.count == 6 {
            let mx0 = x0s.sorted()[3], mx1 = x1s.sorted()[3]
            let maroonW = mx1 - mx0 + 1
            let hs = raw.map { $0.1 - $0.0 + 1 }.sorted()
            let medH = hs[3]
            // 採用条件はレイアウト形状で判定する (エンジ色幅そのものは
            // 縮小フレームで過小に出るため、幅の絶対範囲では判定しない):
            // 帯の高さが揃っていること、左端とサンプリング幅が
            // 全画面〜縮小表示の範囲に収まること
            let uniform = raw.allSatisfy {
                abs(Double($0.1 - $0.0 + 1) - Double(medH)) <= 0.35 * Double(medH)
            }
            // サンプリング幅: エンジ色幅と、高さから推定したレイアウト
            // 幅の大きい方。モデル切り出し幅 (cropW) は従来どおり
            // エンジ色幅を使う (較正済みの切り出しを変えないため)
            let sampleW = max(maroonW, Int((Double(medH) * pvPanelAspect).rounded()))
            if uniform
                && mx0 >= Int(0.50 * Double(W)) && mx0 <= Int(0.92 * Double(W))
                && sampleW >= Int(0.08 * Double(W)) && sampleW <= Int(0.30 * Double(W)) {
                return raw.map { (x: mx0, y: $0.0, w: sampleW, h: $0.1 - $0.0 + 1, cropW: maroonW) }
            }
        }
        let pw = Int(0.154 * Double(W)), px = Int(0.811 * Double(W))
        return raw.map { (x: px, y: $0.0, w: pw, h: $0.1 - $0.0 + 1, cropW: pw) }
    }
    let pw = Int(0.154 * Double(W)), px = Int(0.811 * Double(W))
    return [0.180, 0.279, 0.378, 0.473, 0.576, 0.670].map {
        (x: px, y: Int($0 * Double(H)), w: pw, h: Int(0.094 * Double(H)), cropW: pw)
    }
}

// タイプアイコン 1 セルを分類。(種族タイプ名, アイコンが存在したか, 診断文字列)
func pvClassifyIcon(_ buf: (data: [UInt8], w: Int, h: Int), _ x0in: Int, _ y0in: Int, _ s: Int) -> (String?, Bool, String, Double, String?, Double) {
    let x0 = max(0, min(x0in, buf.w - s)), y0 = max(0, min(y0in, buf.h - s))
    var gray: [Double] = []
    var pix: [(Double, Double, Double)] = []
    gray.reserveCapacity(s * s); pix.reserveCapacity(s * s)
    for yy in 0..<s {
        for xx in 0..<s {
            let i = ((y0 + yy) * buf.w + (x0 + xx)) * 4
            let r = Double(buf.data[i]), g = Double(buf.data[i + 1]), b = Double(buf.data[i + 2])
            gray.append(pvGray(r, g, b))
            pix.append((r, g, b))
        }
    }
    let mean = gray.reduce(0, +) / Double(gray.count)
    let std = sqrt(gray.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(gray.count))
    if std <= 30 { return (nil, false, String(format: "std=%.1f (アイコンなし)", std), 999, nil, 999) }
    let kept = pix.filter { ($0.0 + $0.1 + $0.2) / 3 < 210 }
    let src = kept.isEmpty ? pix : kept
    func med(_ arr: [Double]) -> Double {
        let st = arr.sorted()
        if st.isEmpty { return 0 }
        return st.count % 2 == 1 ? st[st.count / 2] : (st[st.count / 2 - 1] + st[st.count / 2]) / 2
    }
    let rgb = [med(src.map { $0.0 }), med(src.map { $0.1 }), med(src.map { $0.2 })]
    // でんき色判定: 黄色バッジは全タイプ中で唯一で、 kept 画素の中央値が
    // 黄色優位 (= 窓の過半がバッジ色) なら でんき と確定する。グリフ
    // (白い稲妻) と地色 (黄) の輝度差が小さいため、グリフ照合では
    // かくとう/いわ 等の色の近いタイプに誤分類されていた (実害:
    // ヒートロトムが ほのお/いわ=ウインディ(ヒスイ) で確定)。
    // 他タイプの実測中央値はこの範囲に入らない (かくとうは G=127、
    // むしは R=145、フェアリー/こおりは B が高い)。
    if rgb[0] >= 195 && rgb[1] >= 145 && rgb[2] <= 135
        && rgb[0] - rgb[2] >= 110 && rgb[1] - rgb[2] >= 50 && rgb[0] >= rgb[1] - 10 {
        let cd = sqrt((rgb[0] - 247) * (rgb[0] - 247)
                    + (rgb[1] - 197) * (rgb[1] - 197)
                    + (rgb[2] - 28) * (rgb[2] - 28)) / 441.7
        return ("Electric", true,
                String(format: "std=%.1f rgb=[%.0f,%.0f,%.0f] Electric(黄色判定)", std, rgb[0], rgb[1], rgb[2]),
                0.05 + cd * 0.3, nil, 999)
    }
    let grid = pvResizeGray(gray, s, s, 12, 12)
    var scored: [(String, Double)] = []
    for (t, tp) in pvTypeIcons where tp.rgb.count >= 3 && tp.glyph.count == 144 {
        let corr = pvPearson(grid, tp.glyph)
        let cd = sqrt((rgb[0] - tp.rgb[0]) * (rgb[0] - tp.rgb[0])
                    + (rgb[1] - tp.rgb[1]) * (rgb[1] - tp.rgb[1])
                    + (rgb[2] - tp.rgb[2]) * (rgb[2] - tp.rgb[2])) / 441.7
        scored.append((t, ((1 - corr) / 2) * 0.7 + cd * 0.3))
    }
    scored.sort { $0.1 < $1.1 }
    let best = scored.first?.0
    let bs = scored.first?.1 ?? Double.greatestFiniteMagnitude
    let top3 = scored.prefix(3).map { String(format: "%@=%.3f", $0.0, $0.1) }.joined(separator: " ")
    let diag = String(format: "std=%.1f rgb=[%.0f,%.0f,%.0f] %@", std, rgb[0], rgb[1], rgb[2], top3)
    // 2 位との距離差 (近接判定用)。分類が成立しない場合は曖昧さなし
    var alt: String? = nil
    var gap = 999.0
    if bs < 0.42 && scored.count > 1 {
        alt = scored[1].0
        gap = scored[1].1 - bs
    }
    return (bs < 0.42 ? best : nil, true, diag, bs, alt, gap)
}

// アイコン 1 枠分: 基準位置の近傍 (3x3) を探索し、最もスコアの良い窓を
// 採用する。パネルの縦横比はウィンドウ形状で変わるため、固定オフセット
// だけではアイコンから外れることがある (実機で確認)。
// ただし「有無」は中心窓だけで判定する: 実機フレームでは有るアイコンは
// 中心でも std 60+、無い枠は中心 std 13 以下と大きく離れている。一方、
// 探索窓は隣のアイコンや 3D モデルの端を拾って「無い枠にタイプを
// 発明」しうる (単タイプが複合と誤読され、候補が 1 種に確定して
// しまう事故の経路)。中心で無ければ探索しない。
func pvClassifyIconSearch(_ buf: (data: [UInt8], w: Int, h: Int), _ x0: Int, _ y0: Int, _ s: Int) -> (String?, Bool, String, Double, String?, Double) {
    let center = pvClassifyIcon(buf, x0, y0, s)
    if !center.1 { return center }
    var best = center
    for dy in [-s / 5, 0, s / 5] {
        for dx in [-s / 6, 0, s / 6] {
            let r = pvClassifyIcon(buf, x0 + dx, y0 + dy, s)
            if r.3 < best.3 { best = r }
        }
    }
    return best
}

// パネル右下の性別マーク (♂=青 / ♀=赤の丸) を読む。位置は実フレーム
// で実測 (中心はパネル相対 x=0.716, y=0.75、2026-11-21)。マークの
// 円は鮮やかな単色で、窓内の該当色ピクセル数が反対色の 2 倍未満の
// 場合は判定しない。読めない場合は nil を返す (性別なしの種族は
// マーク自体が出ないため、「読めない = 性別なし」とは扱わない)
func pvReadGender(_ buf: (data: [UInt8], w: Int, h: Int), _ panel: (x: Int, y: Int, w: Int, h: Int)) -> (String?, Int, Int) {
    let cx = panel.x + Int(0.716 * Double(panel.w))
    let cy = panel.y + Int(0.75 * Double(panel.h))
    let half = Int(0.08 * Double(panel.w))
    if half <= 0 || buf.w <= 0 { return (nil, 0, 0) }
    var red = 0, blue = 0
    for yy in (cy - half)..<(cy + half) {
        if yy < 0 || yy >= buf.h { continue }
        for xx in (cx - half)..<(cx + half) {
            if xx < 0 || xx >= buf.w { continue }
            let i = (yy * buf.w + xx) * 4
            let r = Int(buf.data[i]), g = Int(buf.data[i + 1]), b = Int(buf.data[i + 2])
            if r > 180 && g < 110 && b < 110 { red += 1 }
            if b > 150 && r < 110 && b - r > 60 { blue += 1 }
        }
    }
    let best = max(red, blue)
    if best < 25 || best < 2 * min(red, blue) { return (nil, red, blue) }
    return (red > blue ? "F" : "M", red, blue)
}

// パネル左側の 3D モデルを背景色との差分で切り出し、特徴量を取る
func pvFeaturesWithBg(_ buf: (data: [UInt8], w: Int, h: Int), _ panel: (x: Int, y: Int, w: Int, h: Int),
                      _ bg: (Int, Int, Int))
    -> (hash: [UInt8], hue: [Double], aspect: Double, density: Double, cover: Double, widthRatio: Double)? {
    let cw = Int(0.52 * Double(panel.w)), ch = panel.h
    if cw <= 0 || ch <= 0 { return nil }
    var mask = [Bool](repeating: false, count: cw * ch)
    for yy in 0..<ch {
        for xx in 0..<cw {
            let i = ((panel.y + yy) * buf.w + (panel.x + xx)) * 4
            let d = abs(Int(buf.data[i]) - bg.0) + abs(Int(buf.data[i + 1]) - bg.1) + abs(Int(buf.data[i + 2]) - bg.2)
            if d > 90 { mask[yy * cw + xx] = true }
        }
    }
    // 最大の連結成分 (8 近傍)
    var label = [Int32](repeating: -1, count: cw * ch)
    var areas: [Int] = []
    var boxes: [(Int, Int, Int, Int)] = []
    for s0 in 0..<(cw * ch) where mask[s0] && label[s0] < 0 {
        let cur = Int32(areas.count)
        var stack = [s0]
        label[s0] = cur
        var area = 0, minx = cw, miny = ch, maxx = -1, maxy = -1
        while let p = stack.popLast() {
            area += 1
            let px = p % cw, py = p / cw
            minx = min(minx, px); maxx = max(maxx, px); miny = min(miny, py); maxy = max(maxy, py)
            for dy in -1...1 {
                for dx in -1...1 {
                    if dx == 0 && dy == 0 { continue }
                    let nx = px + dx, ny = py + dy
                    if nx < 0 || ny < 0 || nx >= cw || ny >= ch { continue }
                    let np = ny * cw + nx
                    if mask[np] && label[np] < 0 { label[np] = cur; stack.append(np) }
                }
            }
        }
        areas.append(area)
        boxes.append((minx, miny, maxx, maxy))
    }
    guard let bi2 = areas.indices.max(by: { areas[$0] < areas[$1] }), areas[bi2] >= 20 else { return nil }
    let (minx, miny, maxx, maxy) = boxes[bi2]
    let sw = maxx - minx + 1, sh = maxy - miny + 1
    var gray = [Double](repeating: 128, count: sw * sh)
    var hue = [Double](repeating: 0, count: 24)
    var cnt = 0
    for yy in 0..<sh {
        for xx in 0..<sw {
            let cx = minx + xx, cy = miny + yy
            if label[cy * cw + cx] != Int32(bi2) { continue }
            cnt += 1
            let i = ((panel.y + cy) * buf.w + (panel.x + cx)) * 4
            let r = Double(buf.data[i]), g = Double(buf.data[i + 1]), b = Double(buf.data[i + 2])
            gray[yy * sw + xx] = pvGray(r, g, b)
            let mx = max(r, g, b), mn = min(r, g, b)
            var hdeg = 0.0
            if mx != mn {
                let d = mx - mn
                if mx == r {
                    var t = ((g - b) / d).truncatingRemainder(dividingBy: 6)
                    if t < 0 { t += 6 }
                    hdeg = 60 * t
                } else if mx == g {
                    hdeg = 60 * ((b - r) / d + 2)
                } else {
                    hdeg = 60 * ((r - g) / d + 4)
                }
            }
            hue[min(23, Int(hdeg / 15))] += 1
        }
    }
    if cnt == 0 { return nil }
    for i in 0..<24 { hue[i] /= Double(cnt) }
    let small = pvResizeBilinear(gray, sw, sh, 17, 16)
    var hash = [UInt8](repeating: 0, count: 32)
    for yy in 0..<16 {
        for xx in 0..<16 {
            if small[yy * 17 + xx + 1] > small[yy * 17 + xx] {
                let bit = yy * 16 + xx
                hash[bit / 8] |= UInt8(0x80 >> (bit % 8))
            }
        }
    }
    return (hash, hue, Double(sw) / Double(sh), Double(areas[bi2]) / Double(sw * sh),
            Double(areas[bi2]) / Double(cw * ch), Double(sw) / Double(cw))
}

// パネルのモデル特徴。背景色はまず従来の 1 点サンプルで推定するが、
// サンプル点がパネル上端の暗い帯などに当たると背景推定が外れ、
// パネル全体が前景化して特徴が壊れる (実例: 2026-11-21
// battle_20261121_153443 の枠4〜6。正解種族のスコアが 0.6 前後に
// 悪化し、全種族展開で誤同定した)。最大成分が切り出し幅の 98%
// 以上か面積の 6 割以上を占める場合は推定失敗とみなし、切り出し
// 内の最頻色 (パネル地の色) を背景として抽出をやり直す。やり直し
// ても失敗の場合は特徴なしとする
func pvModelFeatures(_ buf: (data: [UInt8], w: Int, h: Int), _ panel: (x: Int, y: Int, w: Int, h: Int))
    -> (hash: [UInt8], hue: [Double], aspect: Double, density: Double)? {
    let cw = Int(0.52 * Double(panel.w))
    if cw <= 0 || panel.h <= 0 { return nil }
    let bgx = max(0, min(panel.x + Int(0.55 * Double(panel.w)), buf.w - 1))
    let bgy = max(0, min(panel.y + 4, buf.h - 1))
    let bi = (bgy * buf.w + bgx) * 4
    let bgPoint = (Int(buf.data[bi]), Int(buf.data[bi + 1]), Int(buf.data[bi + 2]))
    func strip(_ f: (hash: [UInt8], hue: [Double], aspect: Double, density: Double, cover: Double, widthRatio: Double)?)
        -> (hash: [UInt8], hue: [Double], aspect: Double, density: Double)? {
        guard let f = f else { return nil }
        return (f.hash, f.hue, f.aspect, f.density)
    }
    let first = pvFeaturesWithBg(buf, panel, bgPoint)
    if let f = first, f.widthRatio < 0.98, f.cover < 0.60 { return strip(f) }
    // 背景推定のやり直し: 切り出し領域の最頻色ビン (32 刻み) の平均色
    var binCount: [Int: Int] = [:]
    var binSum: [Int: (Int, Int, Int)] = [:]
    for yy in 0..<panel.h {
        for xx in 0..<cw {
            let i = ((panel.y + yy) * buf.w + (panel.x + xx)) * 4
            let r = Int(buf.data[i]), g = Int(buf.data[i + 1]), b = Int(buf.data[i + 2])
            let key = (r / 32) * 64 + (g / 32) * 8 + (b / 32)
            binCount[key, default: 0] += 1
            let s = binSum[key] ?? (0, 0, 0)
            binSum[key] = (s.0 + r, s.1 + g, s.2 + b)
        }
    }
    guard let bestKey = binCount.max(by: { $0.value < $1.value })?.key,
          let s = binSum[bestKey], let c = binCount[bestKey], c > 0 else { return strip(first) }
    let bgMode = (s.0 / c, s.1 / c, s.2 / c)
    let second = pvFeaturesWithBg(buf, panel, bgMode)
    if let f = second, f.widthRatio >= 0.98, f.cover >= 0.60 { return nil }
    return strip(second) ?? strip(first)
}

func pvScore(_ f: (hash: [UInt8], hue: [Double], aspect: Double, density: Double),
             _ ref: (hash: [UInt8], hue: [Double], aspect: Double, density: Double)) -> Double {
    var diff = 0
    for i in 0..<min(f.hash.count, ref.hash.count) { diff += (f.hash[i] ^ ref.hash[i]).nonzeroBitCount }
    let hd = Double(diff) / 256.0
    let hc = pvPearson(f.hue, ref.hue)
    return hd - 0.35 * hc + 0.15 * abs(log(f.aspect / ref.aspect)) + 0.25 * abs(f.density - ref.density)
}

// 姿・色に実質的な性別差がある種族 (フォルム自体が雌雄を表す
// Meowstic / Indeedee / Basculegion 等は除く)。これらの種族でのみ、
// テンプレートの性別で絞り込む
let pvGenderDimorphic: Set<String> = ["Hippowdon", "Pyroar", "Pikachu", "Scizor", "Heracross", "Weavile"]

// 種族のスコア: 本参照と実フレームテンプレート群の最小スコア。
// 性別による絞り込みは、性別差のある種族で雌雄両方のテンプレートが
// あるときだけ行う (性別差の無い種族では、個体の性別タグは見た目と
// 無関係なため絞り込まない)
func pvBestScore(_ f: (hash: [UInt8], hue: [Double], aspect: Double, density: Double),
                 _ name: String, _ gender: String?) -> Double? {
    var best = pvFeatures[name].map { pvScore(f, $0) }
    var tpls = pvTemplateFeatures[name] ?? []
    if let gender, pvGenderDimorphic.contains(name) {
        let genders = Set(tpls.map { $0.gender }.filter { !$0.isEmpty })
        if genders.contains(gender) && genders.count >= 2 {
            tpls = tpls.filter { $0.gender.isEmpty || $0.gender == gender }
        }
    }
    for t in tpls {
        let s = pvScore(f, (t.hash, t.hue, t.aspect, t.density))
        if best == nil || s < best! { best = s }
    }
    return best
}

// 選出画面 1 枚から相手チームを推定する。何も分からなければ nil
// 第1段 (b) タイプ関門の緩和: タイプで絞った候補内の照合スコアが
// 全体的に悪い (最良でも pvSoftGateScore 超) 場合は、アイコンを
// 読み違えたとみなして全種族へ候補を広げて再照合する。タイプの
// 組み合わせ自体が実在しない場合も同じ扱いにする。タイプで 1 種に
// 定まる「確定」枠も、照合スコアが悪い場合は確定扱いを取り消して
// 再照合する (読み違いアイコンによる誤確定の防止)。
func identifyPreview(image: CGImage) -> (team: [String?], notes: [String], slots: [PvSlotInfo])? {
    let buf = makeFullBuffer(image)
    let panels = pvDetectPanels(buf)
    var anyInfo = false
    // 枠ごとの候補リスト (種族, 照合スコア)。スコアは小さいほど良い
    var slotRanked: [[(String, Double)]] = []
    var slotDecisive: [Bool] = []
    var slotPoolCount: [Int] = []
    var slotMargin: [Double] = []
    var slotExpanded: [Bool] = []
    var slotTypes: [[String]] = []
    var slotGender: [String] = []
    var slotPanels: [[Int]] = []
    var slotIconDiags: [[String]] = []
    var slotGenderCounts: [[Int]] = []
    // 全種族への再照合 (候補を広げたランキングを返す)。性別が読めて
    // いれば、その性別になりえない種族は広げた先でも除外する
    func rankedAll(_ f: (hash: [UInt8], hue: [Double], aspect: Double, density: Double), _ gender: String?) -> [(String, Double)] {
        var all = pvFeatures.keys.filter { !pvBattleOnlyFormes.contains($0) }
            .compactMap { n -> (String, Double)? in pvBestScore(f, n, gender).map { (n, $0) } }
            .sorted { $0.1 < $1.1 }
        if let gender {
            let filtered = all.filter { pvSpeciesGender[$0.0]?.contains(gender) ?? true }
            if !filtered.isEmpty { all = filtered }
        }
        return all
    }
    for panel in panels {
        let (gender, gRed, gBlue) = pvReadGender(buf, (x: panel.x, y: panel.y, w: panel.w, h: panel.h))
        slotGender.append(gender ?? "")
        slotGenderCounts.append([gRed, gBlue])
        slotPanels.append([panel.x, panel.y, panel.w, panel.h])
        var types: [String] = []
        var iconCands: [[String]] = []
        var iconDiags: [String] = []
        var unknownPresent = false
        // アイコン位置はパネル相対 (2026-11-20 の実機フレームで再実測:
        // アイコン中心は slot1 x=0.70w, slot2 x=0.89w, y=0.25h、一辺 0.403h。
        // 単タイプは右側の枠に表示される)。左上 = 中心 - 一辺/2 を基準に
        // 近傍探索で微調整する
        let iconS = Int(0.403 * Double(panel.h))
        for slot in 0..<2 {
            let ix = panel.x + Int((slot == 0 ? 0.620 : 0.810) * Double(panel.w))
            let iy = panel.y + Int(0.050 * Double(panel.h))
            let (t, present, diag, _, alt, gap) = pvClassifyIconSearch(buf, ix, iy, iconS)
            iconDiags.append(diag)
            if let t {
                types.append(t)
                var cands = [t]
                // 1 位と 2 位が近接している場合は分類を確定とみなさず、
                // 両タイプを候補に残してプールを統合する
                if let alt, gap < pvIconAmbigDelta { cands.append(alt) }
                iconCands.append(cands)
            } else if present { unknownPresent = true }
        }
        slotIconDiags.append(iconDiags)
        slotTypes.append(types)
        var pool: [String] = []
        if !iconCands.isEmpty {
            var combos: [Set<String>] = [[]]
            for cands in iconCands {
                combos = combos.flatMap { base in cands.map { base.union([$0]) } }
            }
            if unknownPresent {
                pool = pvSpeciesTypes.filter { sp in combos.contains { Set(sp.value).isSuperset(of: $0) } }.map { $0.key }
            } else {
                pool = pvSpeciesTypes.filter { combos.contains(Set($0.value)) }.map { $0.key }
            }
        }
        // 見せ合い画面に現れないフォルム (メガ等) は候補から外す
        pool = pool.filter { !pvBattleOnlyFormes.contains($0) }
        var expanded = false
        if pool.isEmpty && !types.isEmpty {
            // 読み取れたタイプの組み合わせを持つ種族が存在しない =
            // アイコンの読み違いが確実。全種族で再照合する
            pool = Array(pvFeatures.keys)
            expanded = true
        }
        if let gender {
            // 性別マークが読めた枠では、その性別になりえない種族を
            // 候補から外す (例: ♂の枠に♀のみのツアリーナは来ない)。
            // 絞って空になる場合はデータ不整合を疑い、絞り込みをしない
            let filtered = pool.filter { pvSpeciesGender[$0]?.contains(gender) ?? true }
            if !filtered.isEmpty { pool = filtered }
        }
        if pool.isEmpty {
            slotRanked.append([]); slotDecisive.append(false); slotPoolCount.append(0); slotMargin.append(0); slotExpanded.append(false)
            continue
        }
        anyInfo = true
        guard let f = pvModelFeatures(buf, (x: panel.x, y: panel.y, w: panel.cropW, h: panel.h)) else {
            // モデル特徴が取れない場合: タイプで 1 種に定まれば従来どおり
            // 確定として扱い、それ以外は判定できない
            if pool.count == 1 && !expanded {
                slotRanked.append([(pool[0], 0)]); slotDecisive.append(true); slotPoolCount.append(1); slotMargin.append(9); slotExpanded.append(false)
            } else {
                slotRanked.append([]); slotDecisive.append(false); slotPoolCount.append(pool.count); slotMargin.append(0); slotExpanded.append(expanded)
            }
            continue
        }
        var ranked = pool.compactMap { n -> (String, Double)? in
            pvBestScore(f, n, gender).map { (n, $0) }
        }.sorted { $0.1 < $1.1 }
        if ranked.isEmpty {
            slotRanked.append([]); slotDecisive.append(false); slotPoolCount.append(pool.count); slotMargin.append(0); slotExpanded.append(expanded)
            continue
        }
        var decisive = false
        if pool.count == 1 && !expanded {
            // タイプで 1 種に定まる枠でも、照合スコアが悪ければ確定に
            // しない (誤ったアイコン読みで別種族が一意に定まる事故の
            // 防止)。スコアが良ければ確定として扱う。スコアが悪くても
            // 全種族展開では上書きしない (小プール保護: 単独プールは
            // タイプ+性別の消去法の答えとして残す)
            if ranked[0].1 <= pvSoftGateScore {
                decisive = true
            }
        } else if ranked[0].1 > pvSoftGateScore && pool.count > 2 {
            // 関門の緩和: 候補内の照合が全体的に悪い場合は候補を広げる。
            // 広げた先の最良が元の最良より明確に良い場合だけ採用する。
            // ただしプールが 2 件以下の枠は広げない: 消去法の答えを
            // 無関係な種族がスコアだけで上書きする事故が続いたため
            // (実例: 2026-11-21 battle_20261121_161334 枠1 Sneasler が
            // プール1位から Alcremie に、枠4 Basculegion が単独プール
            // から Pincurchin に、それぞれ展開で上書きされた)
            let all = rankedAll(f, gender)
            if let top = all.first, top.1 < ranked[0].1 - pvExpandMargin {
                // タイプ読みと 1 つも重ならない展開先は、テンプレート級
                // (負値) の一致のときだけ採用する。タイプが正しく
                // 読めている枠で、無関係な種族の偶然の低スコアに
                // プールを捨てさせる事故の防止 (実例: 2026-11-22
                // battle_20261122_071457 枠5、Steel/Ghost と正しく
                // 読めていたのに Scrafty (0.032) が採用された)
                let topTypes = pvSpeciesTypes[top.0] ?? []
                let overlaps = !types.isEmpty && !Set(topTypes).isDisjoint(with: Set(types))
                if overlaps || top.1 < 0 {
                    ranked = all; expanded = true
                }
            }
        }
        slotRanked.append(ranked); slotDecisive.append(decisive); slotExpanded.append(expanded)
        slotPoolCount.append(expanded ? pvFeatures.count : pool.count)
        slotMargin.append(ranked.count > 1 ? ranked[1].1 - ranked[0].1 : 1.0)
    }
    // 同じ種族が 2 枠に出ることはないため、重複しないよう割り当てる。
    // 確定枠 → マージンの大きい順に、各枠の最上位の「未使用」候補を採る
    // (従来は枠ごとに独立に 1 位を採っており、同種族が重複登録されていた)
    var used = Set<String>()
    var team: [String?] = Array(repeating: nil, count: panels.count)
    var slots: [PvSlotInfo] = Array(repeating: PvSlotInfo(), count: panels.count)
    for i in panels.indices {
        slots[i].types = slotTypes[i]
        slots[i].candidates = Array(slotRanked[i].prefix(3))
        slots[i].gender = slotGender[i]
        slots[i].panel = slotPanels[i]
        slots[i].iconDiag = slotIconDiags[i]
        slots[i].genderCounts = slotGenderCounts[i]
    }
    var noteByIdx: [Int: String] = [:]
    var order = panels.indices.filter { !slotRanked[$0].isEmpty }
    order.sort { a, b in
        if slotDecisive[a] != slotDecisive[b] { return slotDecisive[a] }
        return slotMargin[a] > slotMargin[b]
    }
    for i in order {
        let ranked = slotRanked[i]
        guard let pickCand = ranked.first(where: { !used.contains($0.0) }) else {
            noteByIdx[i] = "選出\(i + 1): 候補が他の枠と重複し判定できませんでした"
            continue
        }
        used.insert(pickCand.0)
        team[i] = pickCand.0
        // 証跡フィールド (panel / iconDiag / genderCounts) を保持するため、
        // PvSlotInfo を作り直さず既存の枠へ項目だけを書き込む
        // (作り直すと証跡が空になる。2026-11-21 preview_test_20261121_204955 で確認)
        slots[i].pick = pickCand.0
        slots[i].score = pickCand.1
        slots[i].decisive = slotDecisive[i]
        slots[i].expanded = slotExpanded[i]
        let rank = ranked.firstIndex(where: { $0.0 == pickCand.0 }) ?? 0
        if slotDecisive[i] {
            noteByIdx[i] = "選出\(i + 1): \(pvJa(pickCand.0)) (タイプで確定)"
        } else if slotExpanded[i] {
            let cands = ranked.prefix(5).map { pvJa($0.0) }.joined(separator: " / ")
            noteByIdx[i] = "選出\(i + 1): \(pvJa(pickCand.0)) (タイプ再照合で仮置き — 候補: \(cands))"
        } else if slotPoolCount[i] <= 2 && slotMargin[i] >= 0.05 && rank == 0 {
            noteByIdx[i] = "選出\(i + 1): \(pvJa(pickCand.0)) (モデル照合で推定)"
        } else {
            let cands = ranked.prefix(5).map { pvJa($0.0) }.joined(separator: " / ")
            noteByIdx[i] = "選出\(i + 1): \(pvJa(pickCand.0)) (仮置き — 候補: \(cands))" + (rank > 0 ? " ※重複回避で第\(rank + 1)候補を採用" : "")
        }
    }
    var notes: [String] = []
    for i in panels.indices {
        notes.append(noteByIdx[i] ?? "選出\(i + 1): 読み取れませんでした")
    }
    return anyInfo ? (team, notes, slots) : nil
}

// MARK: - プレート位置の自動検出
// 固定領域は QuickTime ウィンドウのタイトルバーやレターボックス (黒帯) でずれるため、
// 全画面OCRのテキスト位置からプレート (名前+近くのHP表記) を探す方式を主とし、
// 見つからないプレートだけ従来の固定領域で補う。

// バトルプレートの名前右に出る性別アイコンの色を判定する。
// 実測 (実機フレーム2枚): 名前中心から x +0.08〜0.11 の小さなパッチで
// ♀ は R-B ≥ +70 かつ R ≥ 130、♂ は R-B ≤ -85 かつ B ≥ 150。
// 性別なしプレートの濃紺の端部 (B が低い) は ♂ と誤認しない。
func plateGender(buf: (data: [UInt8], w: Int, h: Int), nameCx: Double, nameCy: Double) -> String? {
    func patch(_ cx: Double, _ cy: Double) -> (r: Double, g: Double, b: Double)? {
        let cxp = Int(cx * Double(buf.w)), cyp = Int(cy * Double(buf.h))
        let half = max(2, buf.w / 250)
        var rs = 0.0, gs = 0.0, bs = 0.0, n = 0
        for yy in (cyp - half)...(cyp + half) {
            for xx in (cxp - half)...(cxp + half) {
                if xx < 0 || yy < 0 || xx >= buf.w || yy >= buf.h { continue }
                let i = (yy * buf.w + xx) * 4
                rs += Double(buf.data[i]); gs += Double(buf.data[i + 1]); bs += Double(buf.data[i + 2]); n += 1
            }
        }
        if n == 0 { return nil }
        return (rs / Double(n), gs / Double(n), bs / Double(n))
    }
    var isF = false, isM = false
    for dx in [0.08, 0.09, 0.10, 0.11] {
        guard let p = patch(nameCx + dx, nameCy) else { continue }
        if p.r - p.b >= 70 && p.r >= 130 { isF = true }
        if p.r - p.b <= -85 && p.b >= 150 { isM = true }
    }
    if isF { return "F" }
    if isM { return "M" }
    return nil
}

func locatePlates(image: CGImage) -> [String: SlotState] {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    var cands: [(entry: SpeciesEntry, box: OcrBox)] = []
    for b in boxes {
        if let sp = matchSpecies(texts: [b.text]) { cands.append((entry: sp, box: b)) }
    }
    // 性別フォルムを持つ候補がいれば、プレートの性別アイコン判定用にバッファを用意する
    let plateBuf: (data: [UInt8], w: Int, h: Int)? =
        cands.contains { formeGroup($0.entry).contains { $0.en.hasSuffix("-F") || $0.en.hasSuffix("-M") } }
        ? makeFullBuffer(image) : nil
    // HP 表記は「最初に見つかったもの」ではなく「名前ボックスに最も近いもの」を選ぶ。
    // 隣のプレートの HP が探索範囲 (dx 0.21) に入るため、最初マッチ方式だと
    // 左右両方に隣の HP% が写る事故が起きる。確保済みの HP ボックスは再利用しない。
    func hpNear(_ b: OcrBox, mine: Bool, claimed: inout Set<String>, knownMax: Int?) -> (pct: Int, cur: Int?, max: Int?)? {
        var best: (score: Double, pct: Int, cur: Int?, max: Int?, key: String, key2: String?)? = nil
        // 自分プレートは HP 数値が名前の右下に離れて表示されるため探索範囲を広げる
        let maxDx = mine ? 0.27 : 0.21
        let maxDy = mine ? 0.17 : 0.11
        for t in boxes {
            let dx = abs(t.cx - b.cx), dy = abs(t.cy - b.cy)
            if dx > maxDx || dy > maxDy { continue }
            let key = "\(Int(t.cx * 1000))_\(Int(t.cy * 1000))"
            if claimed.contains(key) { continue }
            var val: (pct: Int, cur: Int?, max: Int?)? = nil
            var key2: String? = nil
            if mine {
                if let hp = parseMineHPText(t.text, knownMax: knownMax) {
                    // 最大値が既知と違う読みは、隣のプレートの HP を拾っている
                    // (例: イエッサンにカメックスの 145/156 が付く) ので採用しない
                    if let km = knownMax, let mx = hp.max, mx != km {
                        // 採用しない
                    } else {
                        val = (hp.pct, hp.cur, hp.max)
                    }
                }
                if val == nil {
                    // スラッシュがバー図形で文字として読めない場合: 同じ行に並んだ
                    // 2 つの数字ボックス (現在値・最大値) のペアとして拾う
                    let digits = asciiDigits(t.text).trimmingCharacters(in: .whitespaces)
                    if !digits.isEmpty && digits.allSatisfy({ $0.isNumber }), let cur = Int(digits) {
                        for u in boxes {
                            if u.cx <= t.cx || u.cx - t.cx > 0.10 || abs(u.cy - t.cy) > 0.02 { continue }
                            let ukey = "\(Int(u.cx * 1000))_\(Int(u.cy * 1000))"
                            if claimed.contains(ukey) { continue }
                            let ud = asciiDigits(u.text).trimmingCharacters(in: .whitespaces)
                            if !ud.isEmpty && ud.allSatisfy({ $0.isNumber }), let mx = Int(ud),
                               mx >= 10 && cur >= 10 && cur <= mx && (knownMax == nil || mx == knownMax) {
                                val = (max(0, min(100, Int((Double(cur) / Double(mx) * 100).rounded()))), cur, mx)
                                key2 = ukey
                                break
                            }
                        }
                    }
                }
            } else if let r = t.text.range(of: #"(\d{1,3})\s*%"#, options: .regularExpression) {
                if let v = Int(t.text[r].filter { $0.isNumber }) { val = (max(0, min(100, v)), nil, nil) }
            }
            if let val {
                let score = dx + dy
                if best == nil || score < best!.score { best = (score, val.pct, val.cur, val.max, key, key2) }
            }
        }
        guard let best else { return nil }
        claimed.insert(best.key)
        if let k2 = best.key2 { claimed.insert(k2) }
        return (best.pct, best.cur, best.max)
    }
    func pick(_ list: [(entry: SpeciesEntry, box: OcrBox)], mine: Bool) -> [(second: Bool, state: SlotState)] {
        var out: [(second: Bool, state: SlotState, cx: Double)] = []
        var used: [(Double, Double)] = []
        var claimed = Set<String>()
        for c in list {
            if used.contains(where: { abs($0.0 - c.box.cx) < 0.06 && abs($0.1 - c.box.cy) < 0.05 }) { continue }
            // 性別フォルムの解決: プレートの名前は雌雄で同一なので、
            // 登録が性別フォルムそのものなら登録を最優先し、それ以外は
            // プレートの性別アイコンを優先する (古い登録が基本フォルムのまま
            // 残っていると実機の性別と食い違うため)。最後に登録で補完する。
            // (UI は state.json の種族名と完全一致でしか場のポケモンを対応付け
            //  ないため、ここで Indeedee-F 等に直しておく必要がある)
            var en = c.entry.en
            let grp = formeGroup(c.entry)
            if grp.count > 1 && grp.contains(where: { $0.en.hasSuffix("-F") || $0.en.hasSuffix("-M") }) {
                var resolved = false
                if mine {
                    let inTeam = grp.filter { teamEntries[$0.en] != nil }
                    if inTeam.count == 1 && (inTeam[0].en.hasSuffix("-F") || inTeam[0].en.hasSuffix("-M")) {
                        en = inTeam[0].en
                        resolved = true
                    }
                }
                if !resolved, let buf = plateBuf,
                   let g = plateGender(buf: buf, nameCx: c.box.cx, nameCy: c.box.cy) {
                    if g == "F", let f = grp.first(where: { $0.en.hasSuffix("-F") }) { en = f.en; resolved = true }
                    if g == "M" {
                        if let m = grp.first(where: { $0.en.hasSuffix("-M") }) { en = m.en; resolved = true }
                        else if let base = grp.first(where: { !$0.en.hasSuffix("-F") && !$0.en.hasSuffix("-M") }) { en = base.en; resolved = true }
                    }
                }
                if !resolved && mine {
                    let inTeam = grp.filter { teamEntries[$0.en] != nil }
                    if inTeam.count == 1 { en = inTeam[0].en }
                }
            }
            // 相手プレートは、選出同定の登録に同グループが 1 件だけなら
            // そちらを正とする (性別サンプルの揺れで雌雄フォルムを
            // 行き来するのを防ぐ)
            if !mine {
                let inPreview = grp.filter { oppTeamSeen.contains($0.en) }
                if inPreview.count == 1 { en = inPreview[0].en }
            }
            // 自軍プレートの種族は登録チーム (フォルム違い含む) のいずれかで
            // なければならない (演出中の誤読で無関係な種族が紛れ込むのを防ぐ)
            if mine && !teamEntries.isEmpty && !grp.contains(where: { teamEntries[$0.en] != nil }) { continue }
            // 最大HP の既知値: チーム登録の実数値を最優先し (プレート誤読で
            // 固定されることがない)、無ければ対戦中の記録を使う
            var knownMax: Int? = nil
            if mine {
                for m in grp {
                    if let h = (teamEntries[m.en]?["stats"] as? [String: Int])?["hp"] { knownMax = h; break }
                }
                if knownMax == nil { knownMax = monStates["p1:\\(en)"]?.hpMax }
            }
            guard let hp = hpNear(c.box, mine: mine, claimed: &claimed, knownMax: knownMax) else { continue }
            used.append((c.box.cx, c.box.cy))
            out.append((false, SlotState(speciesEn: en, hpPercent: hp.pct, hpCur: hp.cur, hpMax: hp.max), c.box.cx))
            if out.count == 2 { break }
        }
        if out.count == 2 {
            return [(false, out[0].state), (true, out[1].state)]
        }
        if out.count == 1 {
            // 1 体だけ見えているフレーム (被弾時の単体表示など): 前フレームの
            // 左右どちらの種族かで枠を決め、無ければ名前の左右位置で決める。
            // (従来は常時 A 枠に入れており、B 枠の被弾が A 枠の交代として
            //  記録される事故があった)
            let o = out[0]
            let aKey = mine ? "mineA" : "oppA"
            let bKey = mine ? "mineB" : "oppB"
            var second: Bool? = nil
            if lastSlots[bKey]?.speciesEn == o.state.speciesEn && lastSlots[aKey]?.speciesEn != o.state.speciesEn { second = true }
            else if lastSlots[aKey]?.speciesEn == o.state.speciesEn && lastSlots[bKey]?.speciesEn != o.state.speciesEn { second = false }
            if second == nil { second = o.cx > (mine ? 0.225 : 0.79) }
            return [(second!, o.state)]
        }
        return []
    }
    var hits: [String: SlotState] = [:]
    for o in pick(cands.filter { $0.box.cy < 0.34 && $0.box.cx > 0.44 }.sorted { $0.box.cx < $1.box.cx }, mine: false) {
        hits[o.second ? "oppB" : "oppA"] = o.state
    }
    for m in pick(cands.filter { $0.box.cy > 0.66 && $0.box.cx < 0.54 }.sorted { $0.box.cx < $1.box.cx }, mine: true) {
        hits[m.second ? "mineB" : "mineA"] = m.state
    }
    // HP バーの画素長 (改善計画フェーズ2の第2系統): ヒットした枠について、
    // プレート固定位置のバー帯から充填率を測り、数字 OCR と併記できる
    // 形で持つ。状態の決定には使わない (照合と証拠記録のためだけの計測)
    if !hits.isEmpty {
        let buf = plateBuf ?? makeFullBuffer(image)
        if buf.w > 0 {
            for (slot, st) in hits {
                if let bar = hpBarFraction(buf: buf, slot: slot) {
                    var s2 = st
                    s2.hpBarPct = bar
                    hits[slot] = s2
                    // 計測値そのものを生観測アーカイブに残す: 不一致の
                    // 証拠記録だけでは「計測が動いていたか」を後から
                    // 検証できないため (2026-11-22 battle_20261122_
                    // 103530 で、到着物から動作確認できなかった)
                    let plate = hpBarPlateRect(slot)
                    recordObservation(pass: "hpbar",
                                      region: [plate.0, plate.1, plate.2, plate.3],
                                      boxes: [(text: "\(slot):\(bar)", x0: plate.0, y0: plate.1,
                                               x1: plate.2, y1: plate.3, conf: 1.0)])
                }
            }
        }
    }
    return hits
}

// プレートの固定位置 (バー計測の基準)
func hpBarPlateRect(_ slot: String) -> (Double, Double, Double, Double) {
    switch slot {
    case "mineA": return (0.012, 0.855, 0.238, 0.972)
    case "mineB": return (0.218, 0.850, 0.442, 0.972)
    case "oppA": return (0.560, 0.025, 0.780, 0.135)
    default: return (0.762, 0.025, 0.988, 0.135)
    }
}

// HP バーの充填率を画素から測る (フェーズ2の第2系統)。バーは全枠共通の
// プレート内レイアウト (左 35% から幅 56%、高さ 55%〜72% の帯) にあり、
// 充填色 (緑・黄・赤) の右端位置から割合を出す。右端は実測で数% 低く
// 出るため +3 の補正を入れる。バー帯が見つからない場合は nil
func hpBarFraction(buf: (data: [UInt8], w: Int, h: Int), slot: String) -> Int? {
    let plate = hpBarPlateRect(slot)
    let W = buf.w, H = buf.h
    let bx0 = Int((plate.0 + 0.35 * (plate.2 - plate.0)) * Double(W))
    let bw = Int(0.56 * (plate.2 - plate.0) * Double(W))
    let by0 = Int((plate.1 + 0.55 * (plate.3 - plate.1)) * Double(H))
    let by1 = Int((plate.1 + 0.72 * (plate.3 - plate.1)) * Double(H))
    guard bw > 20, by1 > by0, bx0 >= 0, bx0 + bw <= W, by0 >= 0, by1 <= H else { return nil }
    func isFill(_ x: Int, _ y: Int) -> Bool {
        let i = (y * W + x) * 4
        let r = Int(buf.data[i]), g = Int(buf.data[i + 1]), b = Int(buf.data[i + 2])
        return (g > 140 && g - r > 55 && g - b > 35)
            || (r > 170 && g > 140 && b < 130)
            || (r > 140 && r - g > 55 && r - b > 35)
    }
    var fracs: [Double] = []
    for y in by0..<by1 {
        var first = -1, last = -1
        for x in 0..<bw where isFill(bx0 + x, y) {
            if first < 0 { first = x }
            last = x
        }
        // 充填はバーの左端から始まるはずの行だけを使う (横にいる
        // ポケモンの体色などを拾った行を除く)
        if first >= 0 && first <= 8 && last >= 8 { fracs.append(Double(last + 1) / Double(bw)) }
    }
    guard fracs.count >= 2 else { return nil }
    fracs.sort()
    let med = fracs[fracs.count / 2]
    return max(0, min(100, Int((med * 100 + 3).rounded())))
}

var inBattle = false
var emptyBattleFrames = 0   // プレートが見えないフレームの連続数 (対戦終了の判定用)

// 選出画面の検出 (「選出してください」「選出完了」などの文言を探す)
// 毎フレームの検出は高速 OCR (.fast) で行う: 全画面の .accurate OCR は
// 1 回で数秒かかることがあり、同定開始がその分遅れていた。トレーナー名
// だけは精度が要るため、2 フレーム目以降に 1 回だけ .accurate で取り直す
var previewLastFrame = false
var lastPreviewSeenAt = Date.distantPast   // 選出画面を最後に見た時刻 (同定のやり直し判定)

// 開始前の画面状態の遷移記録 (late_start の証拠用)。見せ合いを取り
// こぼした際、従来は「画面が覆われていたか裏画面だった」という推定
// の注記しか残らず、実際に何が起きたかを後から区別できなかった
// (実例: 2026-11-22 battle_20261122_050512)。取得失敗・暗転・マッ
// チング・見せ合いの遷移だけを時刻付きで残し、late_start の記録に
// 添付する
let readerStartedAt = Date()
var preStartEvents: [(Date, String)] = []
func notePreStartEvent(_ s: String) {
    if preStartEvents.last?.1 == s { return }
    let now = Date()
    preStartEvents.append((now, s))
    preStartEvents.removeAll { now.timeIntervalSince($0.0) > 300 }
    if preStartEvents.count > 40 { preStartEvents.removeFirst(preStartEvents.count - 40) }
}
var previewDetectCount = 0                 // この選出セッションで検出したフレーム数
var previewNamesAccurateDone = false       // トレーナー名の .accurate 取り直し済みか
func pvExtractTrainers(_ boxes: [OcrBox]) {
    let bad = ["バトル", "選出", "ダブル", "カジュアル", "ランク", "マスター", "ください"]
    for b in boxes where b.cy > 0.11 && b.cy < 0.20 {
        let t = b.text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty || t.count > 14 || bad.contains(where: { t.contains($0) }) { continue }
        if t.allSatisfy({ $0.isNumber || ":： ".contains($0) }) { continue }
        if b.cx < 0.32 { trainerMine = t }
        if b.cx > 0.70 { trainerOpp = t }
    }
}
// マッチング画面 (対戦相手の検索中) の検出。実機の文言は
// 「マッチング待機中…」(2026-11-21 にユーザーが撮影した実画面で確認。
// 紫色のダイアログ中央に黄色いアイコンと白文字、下に「キャンセル」
// ボタン)。当初はシリーズ標準の推測文言だけだったため実戦で
// 検出できていなかった。文言の OCR が崩れた場合に備え、ダイアログの
// 紫色 + 「キャンセル」ボタンの併存でも検出する
let matchingPhrases = ["マッチング待機中",
                       "対戦相手を探しています", "対戦相手をさがしています",
                       "対戦相手を探して", "相手を探しています",
                       "マッチング中", "マッチングしています"]
// マッチング待機ダイアログの紫色が画面中央に大きく広がっているか。
// 実画面の実測: ダイアログ色は (92,88,202)〜(117,106,217) の縦グラデ
func matchingDialogPresent(_ image: CGImage) -> Bool {
    let buf = makeFullBuffer(image)
    var hits = 0, total = 0
    for fy in [0.38, 0.44, 0.50, 0.58] {
        for fx in [0.20, 0.30, 0.40, 0.60, 0.70, 0.80] {
            let x = Int(fx * Double(buf.w)), y = Int(fy * Double(buf.h))
            let i = (y * buf.w + x) * 4
            let r = Int(buf.data[i]), g = Int(buf.data[i + 1]), b = Int(buf.data[i + 2])
            total += 1
            if b > r && r > g && b >= 110 && r >= 70 { hits += 1 }
        }
    }
    return total > 0 && hits * 4 >= total * 3   // 24 点中 18 点以上
}
func detectMatching(image: CGImage) -> Bool {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    if boxes.contains(where: { b in matchingPhrases.contains { b.text.contains($0) } }) {
        return true
    }
    // 文言が読めなくても、紫ダイアログ + キャンセルボタンで検出する
    if boxes.contains(where: { $0.text.contains("キャンセル") }) {
        return matchingDialogPresent(image)
    }
    return false
}

// マッチング状態のターミナル表示 (開始時に 1 回、継続中は 15 秒ごと)。
// 見せ合い画面に移ったらマッチング成立として表示を終える
func updateMatchingDisplay(image: CGImage) {
    if previewLastFrame {
        if matchingActive {
            matchingActive = false
            matchingSince = nil
            print("[matching] 対戦相手が見つかりました")
            fflush(stdout)
        }
        return
    }
    if detectMatching(image: image) {
        let now = Date()
        notePreStartEvent("matching_seen")
        if !matchingActive {
            matchingActive = true
            matchingSince = now
            matchingLastPrintAt = now
            print("[matching] マッチング中… (対戦相手を探しています)")
            fflush(stdout)
        } else if let lp = matchingLastPrintAt, now.timeIntervalSince(lp) >= 15 {
            matchingLastPrintAt = now
            let sec = Int(now.timeIntervalSince(matchingSince ?? now))
            print("[matching] マッチング中… (\(sec) 秒経過)")
            fflush(stdout)
        }
    } else if matchingActive {
        matchingActive = false
        matchingSince = nil
        print("[matching] マッチング画面を離れました")
        fflush(stdout)
    }
}

// 見せ合い後に一瞬映る相手のランク/レート表示の読み取り。ランク名は
// 6 級の正式名称で照合し、両トレーナー分が映る場合は相手側 (右半分)
// を優先する。レートは「レート」を含む表記を優先し、無ければランク
// 表示と同じ行の 3〜4 桁数値を拾う (タイマー表記は対象外)
let rankNameList = ["チャンピオン級", "マスターボール級", "ハイパーボール級",
                    "スーパーボール級", "モンスターボール級", "ビギナー級"]
func scanOpponentRank(image: CGImage) {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    var rankHit: (name: String, box: OcrBox)? = nil
    for b in boxes {
        guard let r = rankNameList.first(where: { b.text.contains($0) }) else { continue }
        if rankHit == nil || (b.cx > 0.5 && rankHit!.box.cx <= 0.5) { rankHit = (r, b) }
    }
    guard let hit = rankHit else { return }
    var rate: Int? = nil
    for b in boxes where b.text.contains("レート") {
        let digits = b.text.filter { $0.isNumber }
        if let v = Int(digits), (100...9999).contains(v) { rate = v; break }
    }
    if rate == nil {
        for b in boxes {
            let t = b.text.trimmingCharacters(in: .whitespaces)
            guard t.count >= 3, t.count <= 4, t.allSatisfy({ $0.isNumber }),
                  abs(b.cy - hit.box.cy) <= 0.07, abs(b.cx - hit.box.cx) <= 0.35,
                  let v = Int(t), (500...3999).contains(v) else { continue }
            rate = v
            break
        }
    }
    oppRank = hit.name
    oppRating = rate.map { String($0) } ?? ""
    let rateSuffix = rate.map { " (レート \($0))" } ?? ""
    print("[rank] 相手のランクを読み取りました: \(hit.name)\(rateSuffix)")
    fflush(stdout)
    if !oppRankRecorded {
        oppRankRecorded = true
        debugCapture(kind: "opp_rank", key: "opp_rank", rawText: "",
                     detail: ["rank": hit.name, "rate": rate ?? -1,
                              "trainer": trainerOpp, "readerBuild": readerBuild],
                     image: image)
    }
}

func detectPreview(image: CGImage) -> Bool {
    // .fast は実機で Vision 内部がクラッシュしたため使わない (build 1013 で
    // 導入、1023 の縮小対策でも直らず、.accurate に戻した)。経緯は ocrBoxes 参照
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    let isP = boxes.contains { $0.text.contains("選出") }
    // 新しい選出画面に入ったら前試合のトレーナー名を消し、今試合分を取り直す
    // (自分の名前は左上、相手は右上。勝敗ログの |win| に使う)
    if isP && !previewLastFrame { trainerMine = ""; trainerOpp = "" }
    previewLastFrame = isP
    if isP {
        previewDetectCount += 1
        pvExtractTrainers(boxes)
        if previewDetectCount >= 2 && !previewNamesAccurateDone {
            previewNamesAccurateDone = true
            pvExtractTrainers(ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1))
        }
    } else {
        previewDetectCount = 0
        previewNamesAccurateDone = false
    }
    return isP
}

var lastBuildCheckAt = Date.distantPast

// ディスク上の reader.swift のビルド番号 (実行中のものと違えば更新が届いている)
func diskReaderBuild() -> String? {
    let url = scriptDir.appendingPathComponent("reader.swift")
    guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
    guard let r = text.range(of: "let readerBuild = \"") else { return nil }
    let rest = text[r.upperBound...]
    guard let end = rest.firstIndex(of: "\"") else { return nil }
    return String(rest[..<end])
}

// reader が起動時に読み込むファイル一式 (本体 + data/*.json)。
// これらは起動時にしか読まれないため、同期で差し替わった場合は
// 再起動しないと反映されない
func watchedFiles() -> [URL] {
    let names = ["names_index.json", "log_names.json", "species_abilities.json",
                 "species_moves.json", "regulation.json", "species_types.json",
                 "preview_features.json", "type_icons.json", "names_ja.json",
                 "items_ja.json", "base_stats.json"]
    return [scriptDir.appendingPathComponent("reader.swift")]
        + names.map { scriptDir.appendingPathComponent("data/\($0)") }
}

// ファイル群の内容指紋 (FNV-1a 64bit)。ファイル名と内容、読めない
// (存在しない) ことも含める
func fingerprintFiles(_ urls: [URL]) -> String {
    var h: UInt64 = 0xcbf29ce484222325
    func mix(_ byte: UInt8) { h = (h ^ UInt64(byte)) &* 0x100000001b3 }
    for url in urls {
        for byte in url.lastPathComponent.utf8 { mix(byte) }
        mix(0xff)
        if let data = try? Data(contentsOf: url) {
            for byte in data { mix(byte) }
        } else {
            mix(0xee)
        }
        mix(0xfe)
    }
    return String(h, radix: 16)
}

let startupFingerprint = fingerprintFiles(watchedFiles())

// 新しいリーダーやデータが同期で届いていたら、選出画面のうち
// (同定が始まる前) に終了コード 42 で抜ける。起動スクリプト側が
// そのコードを見て再起動する。
// 対戦中は絶対に再起動しない (対戦状態が消えてしまうため)
func maybeRestartForUpdate() {
    if previewHandled { return }
    if Date().timeIntervalSince(lastBuildCheckAt) < 5 { return }
    lastBuildCheckAt = Date()
    guard fingerprintFiles(watchedFiles()) != startupFingerprint else { return }
    let disk = diskReaderBuild() ?? "?"
    print("[sync] reader.swift または data ファイルの更新 (\(disk)) が届いたため再起動します")
    fflush(stdout)
    exit(42)
}

func runOnce(image: CGImage) {
    obsFrameSeq += 1   // 生観測アーカイブのフレーム参照 (通し番号)
    // 空フレーム (暗転・消灯・切断) はどの判定にも流さず待機する。
    // 対戦終了カウンタ (emptyBattleFrames) や選出の試行回数も進めない
    if isBlankFrame(image) { noteBlankFrame(true); return }
    noteBlankFrame(false)
    debugUpdateRing(image)
    // 選出画面はプレート判定より先に判定する。
    // (選出画面の自軍パネルや「0/4」表示をプレートと誤検出しないため)
    let wasPreviewFrame = previewLastFrame
    if detectPreview(image: image) {
        previewFrames += 1
        notePreStartEvent("preview_seen")
        let sinceLastPreview = Date().timeIntervalSince(lastPreviewSeenAt)
        lastPreviewSeenAt = Date()
        // 見せ合い画面の最終フレームを保持する (同定の成否によらず、
        // 試合開始時に preview_id として書き出すための全試合保証)
        previewLastImage = image
        previewLastImageAt = Date()
        if !wasPreviewFrame {
            // 新しい見せ合い画面の出現: preview_id の書き出しを再武装する
            previewIdWritten = false
            // 前の対戦のランク/レート読み取りも引き継がない
            oppRank = ""
            oppRating = ""
            oppRankRecorded = false
            // 前の見せ合いから 1.5 秒以上画面が消えていたら、別の選出
            // セッションとみなして同定をやり直す。従来のリセット条件
            // (対戦終了 / 対戦中 / 最終目撃から 10 秒超) では、相手の
            // 切断やキャンセルの後に短時間で再マッチした場合に同定済み
            // フラグが残り、前の相手のチームが次の対戦のヘッダーに
            // なる事故があった (2026-11-21 battle_20261121_145658)
            if sinceLastPreview >= 1.5, previewHandled || !previewBestTeam.isEmpty {
                previewHandled = false
                previewAttempts = 0
                previewBestTeam = []
                previewVotes = []
                previewVoteScore = []
                previewLocked = []
                previewTeamWritten = false
                print("[preview] 見せ合い画面の再出現を検出したため、選出セッションをリセットして同定をやり直します")
                fflush(stdout)
            }
        }
        maybeRestartForUpdate()
        // 同定は 1 フレーム目から試みる (従来は出現アニメーション待ちで
        // 2 フレーム目まで始めず、全画面 OCR 2 回分 = 数秒遅れていた)。
        // 分かった枠から state.json に反映し、未確定の枠が残れば次の
        // フレームで試行し直す (最大 4 回)。6 枠そろった場合はアニメー
        // ション明けのフレームでもう 1 回確認してから確定とする
        if !previewHandled {
            previewAttempts += 1
            let hadState = !oppTeamSeen.isEmpty || lastSlots["oppA"] != nil || lastSlots["oppB"] != nil
            lastSlots["oppA"] = nil
            lastSlots["oppB"] = nil
            if pvDataLoaded, let r = identifyPreview(image: image) {
                // 試行をまたいでマージする: 従来の「後勝ち」をやめ、
                // 枠ごとに投票で決める (第1段 (a))。2 フレームで一致
                // した種族、またはタイプで確定した種族はその枠に
                // ロックし、後の試行では置き換えない。未確定の枠は
                // 票数 → 最良スコアの順で暫定 1 位を出す。一度埋まった
                // 枠が空に戻らない点は従来どおり
                if previewBestTeam.count != r.team.count {
                    previewBestTeam = Array(repeating: nil, count: r.team.count)
                    previewVotes = Array(repeating: [:], count: r.team.count)
                    previewVoteScore = Array(repeating: [:], count: r.team.count)
                    previewLocked = Array(repeating: nil, count: r.team.count)
                }
                for i in r.team.indices {
                    guard let pick = r.team[i] else { continue }
                    previewVotes[i][pick, default: 0] += 1
                    let sc = r.slots[i].score
                    if sc < (previewVoteScore[i][pick] ?? Double.greatestFiniteMagnitude) {
                        previewVoteScore[i][pick] = sc
                    }
                    if previewLocked[i] == nil
                        && (r.slots[i].decisive || previewVotes[i][pick, default: 0] >= 2) {
                        previewLocked[i] = pick
                    }
                }
                // マージ時のタイプ拒否: ロック・暫定 1 位の種族が、
                // 最新の試行で読み取れたタイプと 1 つも重ならない場合、
                // その種族は最新の読みとは両立しないため、ロックを
                // 外し暫定 1 位の選出からも外す (最新の試行自身の pick
                // は対象にしない)。初期試行の誤りがロックで固定され、
                // 後の正しい読みで覆せない事故の防止 (実例: 2026-11-21
                // battle_20261121_161334 枠6、Psychic の Espathra が
                // 最終試行の Grass 読みを押し切った)
                var vetoed: [Set<String>] = Array(repeating: [], count: r.team.count)
                for i in r.team.indices {
                    let lt = r.slots[i].types
                    guard !lt.isEmpty else { continue }
                    for sp in previewVotes[i].keys where sp != r.team[i] {
                        if Set(pvSpeciesTypes[sp] ?? []).isDisjoint(with: Set(lt)) {
                            vetoed[i].insert(sp)
                        }
                    }
                    if let locked = previewLocked[i], vetoed[i].contains(locked) {
                        previewLocked[i] = nil
                    }
                }
                let incumbents = previewBestTeam
                for i in r.team.indices {
                    if let locked = previewLocked[i] {
                        previewBestTeam[i] = locked
                    } else if !previewVotes[i].isEmpty {
                        // 暫定 1 位: 票数が多い順、同数なら最良スコアが
                        // 小さい順、それも同点なら種族名順 (フレーム間で
                        // 表示が揺れないよう決定的に選ぶ)
                        let leader = previewVotes[i].keys.filter { !vetoed[i].contains($0) }.sorted { a, b in
                            let ca = previewVotes[i][a, default: 0], cb = previewVotes[i][b, default: 0]
                            if ca != cb { return ca > cb }
                            let sa = previewVoteScore[i][a] ?? 9, sb = previewVoteScore[i][b] ?? 9
                            if sa != sb { return sa < sb }
                            return a < b
                        }.first
                        if let leader {
                            // 同点なら現行を維持する: 挑戦側の票数が
                            // 現行の種族と同数なら、スコアの僅差では
                            // 入れ替えない。幾何の崩れた 1 回の試行が
                            // 正しかった前回の結果を上書きする事故の
                            // 防止 (実例: 2026-11-22
                            // battle_20261122_070237、枠ずれした試行が
                            // 同点・スコア勝ちで以後の枠をずらした)
                            if let inc = incumbents[i], inc != leader, !vetoed[i].contains(inc),
                               previewVotes[i][inc, default: 0] >= previewVotes[i][leader, default: 0] {
                                previewBestTeam[i] = inc
                            } else {
                                previewBestTeam[i] = leader
                            }
                        }
                    }
                }
                // マージ結果の重複排除: 同じ種族が複数枠に立つことは
                // ありえないため、主張の強い枠 (ロック済み → 票数 →
                // スコア) が先に確保し、譲った枠は未使用の次点候補、
                // 無ければ未使用の現行へ落とす。どちらも無ければ
                // 空にする (誤った重複より空枠の方が後の試行で
                // 直せる)
                var claimed = Set<String>()
                let claimOrder = r.team.indices.sorted { a, b in
                    let la = previewLocked[a] != nil, lb = previewLocked[b] != nil
                    if la != lb { return la }
                    let ca = previewBestTeam[a].map { previewVotes[a][$0, default: 0] } ?? 0
                    let cb = previewBestTeam[b].map { previewVotes[b][$0, default: 0] } ?? 0
                    if ca != cb { return ca > cb }
                    let sa = previewBestTeam[a].map { previewVoteScore[a][$0] ?? 9 } ?? 9
                    let sb = previewBestTeam[b].map { previewVoteScore[b][$0] ?? 9 } ?? 9
                    if sa != sb { return sa < sb }
                    return a < b
                }
                for i in claimOrder {
                    guard let cur = previewBestTeam[i] else { continue }
                    if !claimed.contains(cur) { claimed.insert(cur); continue }
                    let alts = previewVotes[i].keys.filter { !vetoed[i].contains($0) && !claimed.contains($0) }.sorted { a, b in
                        let ca = previewVotes[i][a, default: 0], cb = previewVotes[i][b, default: 0]
                        if ca != cb { return ca > cb }
                        let sa = previewVoteScore[i][a] ?? 9, sb = previewVoteScore[i][b] ?? 9
                        if sa != sb { return sa < sb }
                        return a < b
                    }
                    var replacement: String? = alts.first
                    if replacement == nil, let inc = incumbents[i], !claimed.contains(inc), !vetoed[i].contains(inc) {
                        replacement = inc
                    }
                    previewBestTeam[i] = replacement
                    if let replacement { claimed.insert(replacement) }
                }
                let filled = previewBestTeam.compactMap { $0 }
                oppTeamSeen = filled
                // 同定の証拠を保持する (試合開始後にデバッグ同梱で書き出す)
                previewEvidenceImage = image
                previewEvidenceSlots = r.slots
                previewEvidenceTeam = previewBestTeam
                // マージの票数も証拠に残す: 単フレームの pick と最終
                // チームが食い違う場合に、どの試行でどう覆ったかを
                // 後から追えるようにする (2026-11-22 battle_20261122_
                // 075240 の共有で、訂正過程が見えないことが判明)
                previewEvidenceVotes = previewVotes.indices.map { i in
                    previewVotes[i].map { (sp, v) in
                        ["species": sp, "votes": v,
                         "best": ((previewVoteScore[i][sp] ?? 9) * 1000).rounded() / 1000] as [String: Any]
                    }.sorted { ($0["votes"] as? Int ?? 0) > ($1["votes"] as? Int ?? 0) }
                }
                previewEvidenceAt = Date()
                oppUnconfirmed = Set(filled)  // 全枠が推定 = 未確認 (実物で差し替え可)
                var obj: [String: Any] = [:]
                obj["mine"] = [Any]()
                obj["opps"] = [Any]()
                obj["field"] = [String: Any]()
                if !previewTeamWritten { obj["oppReset"] = true }
                obj["oppPreview"] = true
                obj["oppTeam"] = previewBestTeam.map { $0 as Any? ?? NSNull() }
                // 対戦中に割り込んだ書き出しでは、現在の試合 ID と
                // events の蓄積全件を併せる。対戦中に観測されうる
                // state.json が常に完全なイベント列を持つようにする
                // ための手当てで、同定や oppReset の意味付け自体には
                // 触れない (battle_20261122_051707 の切り分けを受けて)
                let snapInBattle = logStarted && !winLogged && !battleArchiveId.isEmpty
                if snapInBattle {
                    obj["battle"] = battleArchiveId
                    obj["events"] = battleEventsObjects()
                }
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8), json != lastWritten {
                    lastWritten = json
                    try? json.write(to: outURL, atomically: true, encoding: .utf8)
                    noteStateWrite(shape: "preview", json: json, eventsCount: snapInBattle ? battleEvents.count : 0)
                }
                previewTeamWritten = true
                notePreStartEvent("preview_identified")
                if (filled.count >= 6 && previewAttempts >= 2) || previewAttempts >= 4 {
                    previewHandled = true
                    // ログの開始 (ヘッダーのスナップショット) は、同定が
                    // 確定したこの時点で行う。初回の試行で開始すると
                    // ヘッダーが最も未熟なマージで固定されてしまう
                    // (実例: 2026-11-21 battle_20261121_161334、ヘッダーと
                    //  preview_id の team が食い違った)。確定前に画面が
                    //  切り替わった場合は、繰り出し文・プレート・ログ
                    //  画面等の従来経路がその時点の最良マージで開始する
                    if !logStarted || winLogged { startBattleLog() }
                }
            } else if previewAttempts >= 4 {
                // 4 回試みても何も同定できなかった: 従来通りリセットする。
                // 部分的にでも同定できていれば、その結果は保持する
                previewHandled = true
                if previewBestTeam.isEmpty {
                    oppTeamSeen = []
                    oppUnconfirmed = []
                    resetLogState()
                    if hadState {
                        // 対戦中のリセット書き出しでも、試合 ID と
                        // events の蓄積全件を併せる (選出形の書き出し
                        // と同じ手当て)
                        let snapInBattle = logStarted && !winLogged && !battleArchiveId.isEmpty
                        var json = "{\"mine\": [], \"opps\": [], \"oppTeam\": [], \"oppReset\": true, \"field\": {}}"
                        if snapInBattle {
                            let obj: [String: Any] = ["mine": [Any](), "opps": [Any](), "oppTeam": [Any](), "oppReset": true, "field": [String: Any](), "battle": battleArchiveId, "events": battleEventsObjects()]
                            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                               let s = String(data: data, encoding: .utf8) {
                                json = s
                            }
                        }
                        if json != lastWritten {
                            lastWritten = json
                            try? json.write(to: outURL, atomically: true, encoding: .utf8)
                            noteStateWrite(shape: "reset", json: json, eventsCount: snapInBattle ? battleEvents.count : 0)
                        }

                    }
                }
            }
        }
        inBattle = false
        return
    }
    // 選出の同定は 1 セッションに 1 回だけ: 選出 -> 読込 -> 選出 のように
    // 非選出フレームを挟んで同定がやり直されると、ヘッダーが 2 重に出る
    // (実例: 2026-11-20 vs Benn 戦)。対戦が始まった/終わった、または
    // 選出画面から 10 秒以上離れたら次の同定を許可する
    if winLogged || inBattle || Date().timeIntervalSince(lastPreviewSeenAt) > 10 {
        previewHandled = false
        previewFrames = 0
        previewAttempts = 0
        previewBestTeam = []
        previewVotes = []
        previewVoteScore = []
        previewLocked = []
        previewTeamWritten = false
        // 同定の証拠 (previewEvidence*) はここでは消さない: 選出確定から
        // 対戦開始 (プレート出現) までは読み込み・入場演出で 10 秒を
        // 超えることが多く、このリセットで消すと試合開始時の書き出し
        // (preview_id) がほぼ常に行われなくなっていた (実例:
        // 2026-11-21 battle_20261121_144858、証拠が残らず誤認先を
        // 特定できなかった)。証拠は次の同定で上書きされ、書き出し側も
        // 保持から 10 分以内に限っているため、残しても実害は小さい
    }
    // マッチング画面の表示 (対戦中は対象外。表示専用でログには影響しない)
    if !inBattle { updateMatchingDisplay(image: image) }
    // 見せ合い後の相手ランク/レート: 選出が確定してから対戦開始までの
    // 短い窓だけを監視する (表示は一瞬しか出ないため)
    if previewHandled, !inBattle, oppRank.isEmpty,
       Date().timeIntervalSince(lastPreviewSeenAt) < 30 {
        scanOpponentRank(image: image)
    }
    // ゲーム内ログ画面が開いていれば、そちらのエントリをログに取り込む
    if parseLogScreen(image: image) {
        inBattle = true
        emptyBattleFrames = 0
        writeState()
        return
    }
    var hits = locatePlates(image: image)
    if hits.count < 4 {
        for plate in plates where hits[plate.name] == nil {
            if let s = parsePlate(image: image, plate: plate) { hits[plate.name] = s }
        }
    }
    if hits.isEmpty {
        // プレートが無い画面 (マッチング・演出・メニュー等) は
        // エラーにせず静かに待つ (最後の状態を保持)。
        // 対戦中はプレートが隠れる演出・メッセージ表示中こそログの本番なので、
        // メッセージ監視はここでも続ける (以前はプレートのあるフレームでしか
        // 監視しておらず、技や特性の文をほぼ拾えていなかった)。
        // 30フレーム (約15秒) プレートが戻らなければ対戦終了とみなす。
        // 対戦開始直後 (選出で startBattleLog 済み・プレート未出) も監視する:
        // 繰り出し・フィールド開始・いかく等の冒頭の文はプレート初出より前に
        // 表示されるため、勝敗未確定で最終イベントから 2 分以内なら対象とする。
        let watching = inBattle || (logStarted && !winLogged && Date().timeIntervalSince(lastLogEventAt) < 120)
        if watching {
            emptyBattleFrames += 1
            watchBattleMessage(image: image, platesVisible: false)
            scanFieldFromScreen(image: image)
            writeState()
            // 安全網: 勝敗文を取りこぼしたまま対戦が終わると (相手の無操作
            // 終了・切断など)、次の対戦開始か reader 再起動まで保存されず
            // 「保存も送信もされない」状態になる (実例: 2026-11-20 vs
            // Foxy2905 戦)。プレートが消えて 45 秒イベントが無ければ
            // 未確定の下書きとして保存する。確定保存ではないので
            // battleArchived は立てず、勝敗が確定すれば final 版が正になる
            if logStarted && !battleArchived && !battleLog.isEmpty && !winLogged
                && emptyBattleFrames > 30
                && Date().timeIntervalSince(lastLogEventAt) > 45
                && battleLog.count != lastArchiveSnapshotCount {
                archiveBattleLogs(final: false, protocolLines: battleLog, displayLines: displayLog,
                                  id: battleArchiveId.isEmpty ? battleStamp() : battleArchiveId)
                lastArchiveSnapshotCount = battleLog.count
            }
            if emptyBattleFrames > 30 { inBattle = false; emptyBattleFrames = 0 }
        }
        return
    }
    emptyBattleFrames = 0
    inBattle = true
    processPlates(hits)
    // plate_stale 監視: 確定済みの枠だけ長くヒットが無い場合、その時点の
    // フレームと、その枠の固定領域の生 OCR を証拠として残す。他の枠が
    // 読めている (= プレートが見えるフレームが来ている) のに特定の枠
    // だけ読めない状態を、名前側か HP 側かまで切り分けるため (実例:
    // 2026-11-21 battle_20261121_150535 で mineB の交代が 2 ターン分
    // 取りこぼされたが、コマンドフェーズのフレームが残らず原因を
    // 特定できなかった)。ひんしの枠は対象外 (交代待ちで当然読めない)
    if logStarted && !winLogged {
        let now = Date()
        let hitSlots = Set(hits.keys)
        let partnerOf = ["mineA": "mineB", "mineB": "mineA", "oppA": "oppB", "oppB": "oppA"]
        for (slot, info) in lastSlots
        where !info.speciesEn.isEmpty && faintedSlots[slot] == nil {
            if hitSlots.contains(slot) {
                slotLastHitAt[slot] = now
                plateStaleOtherHits[slot] = 0
            } else if let last = slotLastHitAt[slot] {
                // 他枠ヒットは、同じ側の相方枠のヒットだけを数える。
                // 相手側のプレートだけが見える場面 (メガシンカ演出等で
                // 自軍プレートが画面に出ていない) では相方もヒット
                // しないため、その間の無ヒットは証拠にならない
                if let partner = partnerOf[slot], hitSlots.contains(partner) {
                    plateStaleOtherHits[slot, default: 0] += 1
                }
                if now.timeIntervalSince(last) >= 60,
                   (plateStaleOtherHits[slot] ?? 0) >= 4 {
                    var regionTexts: [String] = []
                    if let p = plates.first(where: { $0.name == slot }) {
                        regionTexts = ocrBoxes(image, x0: p.x0, y0: p.y0, x1: p.x1, y1: p.y1).map { $0.text }
                    }
                    // 可視性ゲート: 固定領域からテキストが何も返らない
                    // 場合はプレート自体が画面に出ていない場面なので
                    // 記録しない (実例: 2026-11-21 battle_20261121_161334
                    // ターン1、メガシンカ演出中に regionTexts が空の
                    // まま誤発火した)。プレートが見えているのに読めて
                    // いない場合だけを証拠にする。キーは枠+種族で、
                    // 占有種族が変われば再武装する (同試合の誤発火が
                    // 後続の本物の stale を塞いだ実例も同試合)
                    if !regionTexts.isEmpty {
                        debugCapture(kind: "plate_stale", key: "plate_stale:\(slot):\(info.speciesEn)", rawText: "",
                                     detail: ["slot": slot, "species": info.speciesEn,
                                              "secondsSinceHit": Int(now.timeIntervalSince(last)),
                                              "partnerHitFrames": plateStaleOtherHits[slot] ?? 0,
                                              "pendingSpecies": pendingSwitchSpecies[slot] ?? "",
                                              "pendingCount": pendingSwitchCount[slot] ?? 0,
                                              "regionTexts": regionTexts,
                                              "readerBuild": readerBuild],
                                     image: image)
                        slotLastHitAt[slot] = now
                        plateStaleOtherHits[slot] = 0
                    }
                }
            } else {
                slotLastHitAt[slot] = now
            }
        }
    }
    // 見せ合い同定の証拠の書き出し: 保持しておいた見せ合いフレームと
    // 枠ごとの同定情報を、この試合のデバッグ同梱として 1 回だけ残す。
    // 試合開始 (プレート出現) の時点で書き出すため、試合 ID との対応が
    // 保たれ、既存の配信経路でそのまま届く。同定の証拠が無い試合でも
    // 見せ合い画面の最終フレームを書き出す (全試合保証)
    // 同定の証拠が無い試合 (同定が走らなかった・失敗した) でも、
    // 見せ合い画面の最終フレームだけは残す (全試合保証。ユーザーの
    // 常設指示 2026-11-21)。同定の有無は detail の identified で示す
    let evImage = previewEvidenceImage ?? previewLastImage
    let evAt = previewEvidenceImage != nil ? previewEvidenceAt : previewLastImageAt
    if !previewIdWritten, let evImage, let evAt,
       Date().timeIntervalSince(evAt) <= 600 {
        previewIdWritten = true
        let slotDetails: [[String: Any]] = previewEvidenceSlots.map { s in
            ["pick": s.pick ?? "", "score": (s.score * 1000).rounded() / 1000,
             "decisive": s.decisive, "expanded": s.expanded, "types": s.types, "gender": s.gender,
             "candidates": s.candidates.map { [$0.0, ($0.1 * 1000).rounded() / 1000] as [Any] },
             "panel": s.panel, "iconDiag": s.iconDiag, "genderCounts": s.genderCounts]
        }
        debugCapture(kind: "preview_id", key: "preview_id", rawText: "",
                     detail: ["team": previewEvidenceTeam.map { $0 ?? "" },
                              "slots": slotDetails, "readerBuild": readerBuild,
                              "votes": previewEvidenceVotes,
                              "identified": previewEvidenceImage != nil],
                     image: evImage)
    }
    // プレート未確定の記録: 相方の枠は確定しているのに片方の枠だけが、
    // 最初の枠確定から 25 秒以上たっても一度も確定しない場合はプレート
    // 検出側の異常として、その時点の全画面を試合中 1 回だけデバッグ情報
    // に残す (実例: 2026-11-21 battle_20261121_132153、イエッサン♀の
    // プレートが試合を通じて未確定で、てだすけ等の文の帰属が既定枠に
    // 流れ続けた。従来のデバッグ情報にはプレート側の証拠が残らず、
    // 原因の切り分けができなかった)
    if firstSlotConfirmedAt == nil && !lastSlots.isEmpty { firstSlotConfirmedAt = Date() }
    if logStarted && !winLogged, let t0 = firstSlotConfirmedAt,
       Date().timeIntervalSince(t0) >= 25 {
        let missing = ["mineA", "mineB", "oppA", "oppB"].filter { name in
            guard lastSlots[name] == nil else { return false }
            let partner = String(name.dropLast()) + (name.hasSuffix("A") ? "B" : "A")
            return lastSlots[partner] != nil
        }
        if !missing.isEmpty {
            debugCapture(kind: "plate_missing", key: "plate_missing", rawText: "",
                         detail: ["missingSlots": missing,
                                  "confirmedSlots": lastSlots.keys.sorted(),
                                  "note": "slot never confirmed 25s after first slot confirmation"],
                         image: image)
        }
    }
    // 全プレートが見える = コマンド選択フェーズ。その開始をターンの区切りにする
    // (行動のログ行が出るたびに commandPhaseSeen は emitLog 側で解除される)
    // ターンの区切りは「場に出ている全員のプレートが揃った」ことを条件にする。
    // 以前は 4 枚固定だったため、どちらかが残り 1 体になると (プレート 3 枚)
    // ターンが永遠に進まなくなった (実例: 2026-11-20 vs Mark 戦 Turn 9 以降)。
    // ただし交代要員が残っている側が 1 体のときは交代待ちの最中なので進めない
    // (awaitingReplacement)。ひんしのプレートが 0% のまま残って表示される
    // 画面では、その枠は「いる」数から除外する。
    // 4 枚揃う通常時は従来通り確定済み (settle) で即時に、保険として
    // 生読み 6 フレーム (約3秒) 連続でも進める。残数不足のときは
    // 行動の合間の一瞬の揃いと区別するため、生読み 6 フレーム連続を必須にする
    let presentHits = hits.filter { !($0.value.hpPercent == 0 && lastSlots[$0.key]?.speciesEn == $0.value.speciesEn) }
    let expectedPlates = aliveOnFieldCount("mine", "p1") + aliveOnFieldCount("opp", "p2")
    let awaiting = awaitingReplacement("mine", "p1") || awaitingReplacement("opp", "p2")
    let platesReady = logStarted && !commandPhaseSeen && !awaiting && expectedPlates >= 2 && presentHits.count == expectedPlates
    let allSettled = presentHits.allSatisfy { lastSlots[$0.key]?.speciesEn == $0.value.speciesEn }
    if platesReady { turnRawFrames += 1 } else { turnRawFrames = 0 }
    if platesReady && ((expectedPlates >= 4 && allSettled) || turnRawFrames >= 6) {
        commandPhaseSeen = true
        flushPendingDamage(force: true)
        emitPendingFaints()
        for sd in ["p1", "p2"] { if let spEn = pendingMegaSpecies[sd] { synthesizeMegaIfPending(side: sd, speciesEn: spEn) } }
        if suppressNextDetectorTurn {
            // 構造ガードがこのラウンドのターン行を既に出しているため、
            // 判定側の出力は抑止する (同じラウンドのターン行を二重に
            // 出さない)。証拠記録は判定の発火自体の記録なので従来どおり行う
            suppressNextDetectorTurn = false
            if debugMode { print("[reader] ターン判定の出力を抑止しました (構造ガードが |turn|\(currentTurn) を出力済み)") }
            fflush(stdout)
        } else {
            currentTurn += 1
            emitLog("|turn|\(currentTurn)")
        }
        recordTurnEvidence(turn: currentTurn,
                           path: (expectedPlates >= 4 && allSettled) ? "plates_settled" : "raw_frames",
                           image: image,
                           extra: ["expectedPlates": expectedPlates, "presentHits": presentHits.count, "turnRawFrames": turnRawFrames])
    }
    watchBattleMessage(image: image, platesVisible: true)
    updateOppTeam()
    writeState()
}

// MARK: - デバッグ (--debug): 取り込んだフレームとOCR全文を保存・表示する

func savePNG(_ image: CGImage, to url: URL) {
    let rep = NSBitmapImageRep(cgImage: image)
    if let data = rep.representation(using: .png, properties: [:]) { try? data.write(to: url) }
}

let readerBuild = "20261122_1105"

func runDebug(image: CGImage) {
    let dir = scriptDir.appendingPathComponent("debug")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let frameURL = dir.appendingPathComponent("frame.png")
    savePNG(image, to: frameURL)
    print("reader build: \(readerBuild)")
    print("フレーム: \(image.width)x\(image.height) -> \(frameURL.path)")
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    print("OCR全文 (\(boxes.count)件):")
    for b in boxes { print(String(format: "  [%.2f, %.2f] %@", b.cx, b.cy, b.text)) }
    let hits = locatePlates(image: image)
    print("プレート判定:")
    for plate in plates {
        if let s = hits[plate.name] { print("  \(plate.name): \(s.speciesEn) HP \(s.hpPercent)%") }
        else if let s = parsePlate(image: image, plate: plate) { print("  \(plate.name): (固定領域で検出) \(s.speciesEn) HP \(s.hpPercent)%") }
        else { print("  \(plate.name): 検出できず") }
    }
    // 自分プレート候補エリア (左下) の OCR をそのまま出す (HP数値がどう読めているか確認用)
    print("自分側エリア (cy>0.66, cx<0.54) の OCR:")
    for b in boxes where b.cy > 0.66 && b.cx < 0.54 {
        print(String(format: "  [%.2f, %.2f] %@", b.cx, b.cy, b.text))
    }
    // メッセージ監視の診断: 下部ストリップの結合テキストと翻訳可否
    let msgBoxesAll = ocrBoxes(image, x0: 0, y0: 0.66, x1: 1, y1: 1)
    let msgJoined = msgBoxesAll.sorted { ($0.cy, $0.x0) < ($1.cy, $1.x0) }.map { $0.text }.joined(separator: "")
    print("メッセージ領域の結合テキスト: \(msgJoined.isEmpty ? "(なし)" : msgJoined)")
    if !msgJoined.isEmpty {
        if let sp = findSpeciesJa(in: msgJoined) { print("  種族名: \(sp.ja) を検出") }
        let msgT = msgJoined.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
        if msgT.hasSuffix("！"), let sp = findSpeciesJa(in: msgT),
           let r = normalize(msgT).range(of: normalize(sp.ja + "の")) {
            let cand = String(normalize(msgT)[r.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: "！!"))
            if let mv = moveNameOrig[cand] { print("  技として翻訳される想定: \(mv)") }
        }
    }
    // 選出画面なら同定の途中経過も出す (パネル実測値とアイコン分類のスコア)
    if boxes.contains(where: { $0.text.contains("選出") }) {
        print("選出同定の診断:")
        if pvDataLoaded {
            let buf = makeFullBuffer(image)
            let panels = pvDetectPanels(buf)
            for (idx, panel) in panels.enumerated() {
                print("  パネル\(idx + 1): x=\(panel.x) y=\(panel.y) w=\(panel.w) h=\(panel.h)")
                let iconS = Int(0.403 * Double(panel.h))
                for slot in 0..<2 {
                    let ix = panel.x + Int((slot == 0 ? 0.620 : 0.810) * Double(panel.w))
                    let iy = panel.y + Int(0.050 * Double(panel.h))
                    let (t, present, diag, _, _, _) = pvClassifyIconSearch(buf, ix, iy, iconS)
                    print("    スロット\(slot + 1) @(\(ix),\(iy)) \(diag) -> \(t ?? (present ? "不明" : "なし"))")
                }
            }
            if let r = identifyPreview(image: image) {
                for n in r.notes { print("  \(n)") }
            } else {
                print("  同定できませんでした")
            }
        } else {
            print("  同定データが読み込めていません")
        }
    }
    // ログ画面なら解析の途中経過も出す (ターン検出・チップ・本文・side 判定)
    if boxes.contains(where: { $0.text.contains("ログ") || $0.text.contains("ターン") }) || !findLogChips(boxes).isEmpty {
        print("ログ画面の診断:")
        if parseLogScreen(image: image) {
            print("  (取り込めたエントリは上のログ行として表示されています)")
        } else {
            print("  ログ画面と判定できませんでした (ターン表示なし・チップ不足)")
        }
    }
    fflush(stdout)
}

// MARK: - チーム登録モード (--team)
// 「様子を見る」の 能力タブ (技・特性・持ち物) と ステータス タブ (能力値6つ) を映すと、
// 左のパーティ一覧で選択中の1体を特定して my_team.json に蓄積する。UI が起動時に読み込み、
// 能力値から SP・性格を逆算して自チームとして自動登録する。

let teamURL = scriptDir.appendingPathComponent("my_team.json")
var moveNameSet = Set<String>()       // 正規化した技名 (names_ja.json から)
var moveNameOrig: [String: String] = [:] // 正規化 -> 元表記

func loadMoveDict() {
    let url = scriptDir.appendingPathComponent("data/names_ja.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let moves = obj["moves"] as? [String: String] else { return }
    for (_, ja) in moves {
        let n = normalize(ja)
        if !n.isEmpty { moveNameSet.insert(n); moveNameOrig[n] = ja }
    }
}

struct OcrBox { let text: String; let cx, cy, x0, y0, x1, y1: Double; let conf: Double } // 座標は左上原点の割合

func ocrBoxes(_ image: CGImage, x0: Double, y0: Double, x1: Double, y1: Double, fast: Bool = false) -> [OcrBox] {
    // Vision のテキスト検出 (.fast) は実機でフレームワーク内部が
    // クラッシュした (2026-11-20、build 1013 で選出検出を .fast 化した
    // 直後から起動時に再現。CRDetectorOutputMaps の Array index out of
    // range で、try? では防げない)。build 1023 で「.fast 時は長辺
    // 1600px に縮小してから渡す」対策を入れたが直らなかったため、
    // .fast 自体をやめて全て .accurate に戻した (build 1028)。
    // fast 引数は将来の再検証用に残すが、現在の呼び出し元は使わない。
    // 極端に小さい画像を渡さないガードだけは保険として残す。
    if image.width < 50 || image.height < 50 { return [] }
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = fast ? .fast : .accurate
    req.recognitionLanguages = ["ja-JP", "en-US"]
    req.usesLanguageCorrection = false
    req.regionOfInterest = CGRect(x: x0, y: 1.0 - y1, width: x1 - x0, height: y1 - y0)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([req])
    let found = (req.results ?? []).compactMap { obs -> OcrBox? in
        guard let cand = obs.topCandidates(1).first else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return OcrBox(text: cand.string, cx: Double(b.midX), cy: 1.0 - Double(b.midY),
                      x0: Double(b.minX), y0: 1.0 - Double(b.maxY), x1: Double(b.maxX), y1: 1.0 - Double(b.minY),
                      conf: Double(cand.confidence))
    }
    recordObservation(pass: "boxes", region: [x0, y0, x1, y1],
                      boxes: found.map { (text: $0.text, x0: $0.x0, y0: $0.y0, x1: $0.x1, y1: $0.y1, conf: $0.conf) })
    return found
}

// 画像を小さなピクセルバッファにして色を拾う (行0 = 画像の上端になるよう反転して描く)
func makePixelBuffer(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = 232, h = 152
    var data = [UInt8](repeating: 0, count: w * h * 4)
    guard let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return ([], 0, 0) }
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    // 実機 (2026-11-20 の選出画面デバッグ) で、この描画結果は上下反転して
    // いることが判明した: 検出パネルの y が実画像の鏡像位置と全 6 件一致し、
    // アイコンもモデルも裏返しのまま照合されていた (選出同定がゴースト
    // 単色になる等の原因)。描画方法に依存しないよう、最後に行順を反転
    // して「0 行目 = 画像の上端」に統一する。
    var flipped = [UInt8](repeating: 0, count: data.count)
    let rowBytes = w * 4
    for y in 0..<h {
        let srcRow = (h - 1 - y) * rowBytes
        flipped.replaceSubrange(y * rowBytes..<((y + 1) * rowBytes),
                                with: data[srcRow..<(srcRow + rowBytes)])
    }
    return (flipped, w, h)
}

func pixelAt(_ buf: (data: [UInt8], w: Int, h: Int), fx: Double, fy: Double) -> (r: Int, g: Int, b: Int) {
    if buf.w <= 0 || buf.h <= 0 { return (0, 0, 0) }
    let x = min(buf.w - 1, max(0, Int(fx * Double(buf.w))))
    let y = min(buf.h - 1, max(0, Int(fy * Double(buf.h))))
    let i = (y * buf.w + x) * 4
    if i < 0 || i + 2 >= buf.data.count { return (0, 0, 0) }
    return (Int(buf.data[i]), Int(buf.data[i + 1]), Int(buf.data[i + 2]))
}

// 左のパーティ一覧 (6行) のうち選択中 (黄緑ハイライト) の行を返す
let partyRowCentersY = [0.262, 0.364, 0.464, 0.558, 0.679, 0.776]
func selectedPartyRow(_ image: CGImage) -> Int? {
    let buf = makePixelBuffer(image)
    var best: (row: Int, score: Int)? = nil
    for (i, cy) in partyRowCentersY.enumerated() {
        let p = pixelAt(buf, fx: 0.10, fy: cy)
        let score = p.g - p.b // 選択行は黄緑 (緑が青より強い)、非選択行は紫 (青が強い)
        if best == nil || score > best!.score { best = (i, score) }
    }
    if let b = best, b.score > 40 { return b.row }
    return nil
}

func selectedSpecies(_ image: CGImage) -> SpeciesEntry? {
    guard let row = selectedPartyRow(image) else { return nil }
    let cy = partyRowCentersY[row]
    let texts = ocrBoxes(image, x0: 0.04, y0: cy - 0.034, x1: 0.22, y1: cy + 0.034).map { $0.text }
    return matchSpecies(texts: texts)
}

// パネル内のラベルと同じ行・右側にあるテキストを拾う
func valueRightOf(_ boxes: [OcrBox], label: String) -> String? {
    guard let li = boxes.firstIndex(where: { normalize($0.text).contains(label) }) else { return nil }
    let lab = boxes[li]
    let cands = boxes.enumerated().filter { $0.offset != li && abs($0.element.cy - lab.cy) < 0.026 && $0.element.x0 > lab.x0 + 0.01 }
    return cands.sorted { $0.element.x0 < $1.element.x0 }.first?.element.text
}

var teamOrder: [String] = []
var teamEntries: [String: [String: Any]] = [:]
var lastTeamSignature = ""
// チーム名は my_team.json の先頭に {"teamName": "..."} の番兵エントリとして
// 保持する (2026-11-20、ユーザーのチーム名「やなぎ_グロチャレ２」設定に伴う
// 形式追加)。配列形式のままなので、番兵を読み飛ばす既存の読み手 (UI の
// loadMyTeam は species の無いエントリを除外する) は無変更で動き続ける
var teamName = ""
// 対応レギュレーション名も番兵エントリの "regulation" キーで保持する
// (2026-11-20 追加。「やなぎ_グロチャレ２」は "M-C")
var teamRegulation = ""
// 直近の captureTeamScreen で画面から特定できた種族 (EN) の一覧。
// 撮影ボタンの応答で UI 側に返し、反映確認に使わせる
var lastCaptureSpecies: [String] = []

func loadTeamFile() {
    guard let data = try? Data(contentsOf: teamURL),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
    for e in arr {
        if let tn = e["teamName"] as? String { teamName = tn }
        if let rg = e["regulation"] as? String { teamRegulation = rg }
        if let sp = e["species"] as? String { teamEntries[sp] = e; teamOrder.append(sp) }
    }
}

func writeTeamFile() {
    // --team で再登録してもチーム名・レギュレーションが消えないよう、
    // 番兵を引き継いで先頭に書く
    var sentinel: [String: Any] = [:]
    if !teamName.isEmpty { sentinel["teamName"] = teamName }
    if !teamRegulation.isEmpty { sentinel["regulation"] = teamRegulation }
    var arr: [[String: Any]] = sentinel.isEmpty ? [] : [sentinel]
    arr += teamOrder.map { teamEntries[$0]! }
    guard let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: teamURL, options: .atomic)
}

func runTeamOnce(image: CGImage) {
    if isBlankFrame(image) { noteBlankFrame(true); return }
    noteBlankFrame(false)
    guard let sp = selectedSpecies(image) else {
        print("チーム登録: 選択中のポケモンが特定できません (様子を見る画面ですか？)")
        return
    }
    let boxes = ocrBoxes(image, x0: 0.315, y0: 0.125, x1: 0.77, y1: 0.84)
    var entry: [String: Any] = teamEntries[sp.en] ?? ["species": sp.en]
    var got: [String] = []
    var sigParts: [String] = [sp.en]
    // 能力タブ: 特性・持ち物・技
    if boxes.contains(where: { normalize($0.text).contains("特性") }) {
        if let ab = valueRightOf(boxes, label: "特性") { entry["ability"] = ab; got.append("特性"); sigParts.append(ab) }
        if let it = valueRightOf(boxes, label: "持ち物") { entry["item"] = it; got.append("持ち物"); sigParts.append(it) }
        let mv = boxes.filter { moveNameSet.contains(normalize($0.text)) }
            .sorted { $0.cy < $1.cy }.map { moveNameOrig[normalize($0.text)] ?? $0.text }
        if !mv.isEmpty { entry["moves"] = Array(mv.prefix(4)); got.append("技\(mv.count)"); sigParts.append(mv.joined(separator: ",")) }
    }
    // ステータスタブ: ラベルと同じ行の数字
    let labelVariants: [(String, [String])] = [
        ("hp", ["HP"]), ("atk", ["こうげき", "攻撃"]), ("def", ["ぼうぎょ", "防御"]),
        ("spa", ["とくこう", "特攻"]), ("spd", ["とくぼう", "特防"]), ("spe", ["すばやさ", "素早さ"]),
    ]
    var stats: [String: Int] = [:]
    for (key, variants) in labelVariants {
        guard let lab = boxes.first(where: { b in variants.contains { normalize(b.text).contains(normalize($0)) } }) else { continue }
        let nums = boxes.filter { b in
            let t = b.text.trimmingCharacters(in: .whitespaces)
            return !t.isEmpty && t.allSatisfy { $0.isNumber } && abs(b.cy - lab.cy) < 0.024 && b.x0 > lab.x0
        }
        if let n = nums.sorted(by: { $0.x0 < $1.x0 }).first, let v = Int(n.text.trimmingCharacters(in: .whitespaces)) { stats[key] = v }
    }
    if stats.count == 6 { entry["stats"] = stats; got.append("能力値"); sigParts.append("\(stats)") }
    if got.isEmpty {
        print("チーム登録: \(sp.ja) — 能力タブでもステータスタブでもない画面です")
        return
    }
    teamEntries[sp.en] = entry
    if !teamOrder.contains(sp.en) { teamOrder.append(sp.en) }
    writeTeamFile()
    let sig = sigParts.joined(separator: "|")
    if sig != lastTeamSignature {
        lastTeamSignature = sig
        print("チーム登録: \(sp.ja) (\(got.joined(separator: "・"))) — 登録済み \(teamOrder.count)/6")
        fflush(stdout)
    }
}

// MARK: - チーム画面 (6体一覧) の取り込み
// チーム確認画面は6体のカードが 2列×3行 で並ぶ。能力タブ = 技・特性・持ち物、
// ステータスタブ = 能力値と SP。UI の撮影ボタン (HTTP) からも呼ばれる。

var abilityDict: [String: String] = [:] // 正規化 -> 元表記
var itemDict: [String: String] = [:]

func loadRoleDicts() {
    if let data = try? Data(contentsOf: scriptDir.appendingPathComponent("data/names_ja.json")),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let abs = obj["abilities"] as? [String: String] {
        for (_, ja) in abs { abilityDict[normalize(ja)] = ja }
    }
    if let data = try? Data(contentsOf: scriptDir.appendingPathComponent("data/items_ja.json")),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
        for (ja, _) in obj { itemDict[normalize(ja)] = ja }
    }
}

func fuzzyScore(_ text: String, in dict: [String: String]) -> (String, Double)? {
    let t = normalize(text)
    if t.isEmpty { return nil }
    if let v = dict[t] { return (v, 1.0) }
    let ta = Array(looseText(t))
    var best: (String, Double)? = nil
    for (k, v) in dict {
        let ka = Array(looseText(k))
        if abs(ta.count - ka.count) > 3 { continue }
        let d = levenshtein(ta, ka)
        let s = 1.0 - Double(d) / Double(max(ta.count, ka.count))
        if s >= 0.72 && (best == nil || s > best!.1) { best = (v, s) }
    }
    return best
}

func fuzzyFind(_ text: String, in dict: [String: String]) -> String? {
    fuzzyScore(text, in: dict)?.0
}

let cardXs = [0.097, 0.515]
let cardYs = [0.290, 0.461, 0.633]
let cardW = 0.388
let cardH = 0.148

// 表示名 (括弧書きのフォルム表記を除いた日本語名) が同じフォルム違いの候補群。
// 例: イエッサン -> [Indeedee, Indeedee-F]、キュウコン -> [Ninetales, Ninetales-Alola]
// フォルム違いの種族名を、登録済みチーム側の表記に寄せる。
// 名前 OCR や性別サンプルは読みごとにフォルムが揺れるため、同グループの
// 登録が 1 件だけならそちらを正とする (例: イエッサンとその雌フォルム、
// イダイトウとその雌フォルム)。相手側の登録は選出同定の結果を使う
func anchoredSpecies(_ e: SpeciesEntry, mine: Bool) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count <= 1 { return e }
    let registered = mine ? grp.filter { teamEntries[$0.en] != nil } : grp.filter { oppTeamSeen.contains($0.en) }
    return registered.count == 1 ? registered[0] : e
}

// メッセージ中の種族名を、場に出ている個体の表記に寄せる
func fieldAnchoredSpecies(_ e: SpeciesEntry) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count <= 1 { return e }
    for key in ["mineA", "mineB", "oppA", "oppB"] {
        if let s = lastSlots[key], let m = grp.first(where: { $0.en == s.speciesEn }) { return m }
    }
    let m = anchoredSpecies(e, mine: true)
    if m.en != e.en { return m }
    return anchoredSpecies(e, mine: false)
}

// 文の左右の手がかり (「相手の」) がある場合は、その側の場のフォルムを
// 優先して寄せる。同ーフォルム違いが両軍にいる場合 (自分のイエッサン♀と
// 相手のイエッサン♂等)、無条件の場走査では自分の側が先に当たってしまい、
// 相手のひんしが自分のポケモンに誤帰属する (検証 最終監査 seed31 #43)
func anchoredSpeciesForText(_ e: SpeciesEntry, text: String) -> SpeciesEntry {
    let grp = formeGroup(e)
    if grp.count > 1 {
        let oppFirst = text.contains("相手の") || text.contains("あいての")
        let order = oppFirst ? ["oppA", "oppB", "mineA", "mineB"] : ["mineA", "mineB", "oppA", "oppB"]
        for key in order {
            if let s = lastSlots[key], let m = grp.first(where: { $0.en == s.speciesEn }) { return m }
        }
    }
    return fieldAnchoredSpecies(e)
}

func formeGroup(_ e: SpeciesEntry) -> [SpeciesEntry] {
    func disp(_ ja: String) -> String {
        var s = ja
        while let r = s.range(of: "（[^）]*）", options: .regularExpression) { s.removeSubrange(r) }
        while let r = s.range(of: "\\([^)]*\\)", options: .regularExpression) { s.removeSubrange(r) }
        return normalize(s)
    }
    let d = disp(e.ja)
    let g = speciesDict.filter { disp($0.ja) == d }
    return g.isEmpty ? [e] : g
}

// カードの性別アイコン (名前の右) の色で性別を判別する。
// 実測 (2266×1488 のスクリーンショット18枚分): ♂ は R-B ≈ -140、♀ は ≈ +145。
// 能力画面・ステータス画面のどちらでもアイコンは同じ位置に出る。
// キャプチャの微妙な位置ずれに耐えるため、中心と上下左右の5点で測って中央値を取る。
func cardGender(buf: (data: [UInt8], w: Int, h: Int), cardX: Double, cardY: Double) -> String? {
    func patchDiff(_ fx: Double, _ fy: Double) -> Double? {
        let cx = Int((cardX + fx * cardW) * Double(buf.w))
        let cy = Int((cardY + fy * cardH) * Double(buf.h))
        let half = max(3, buf.w / 200)
        var rSum = 0.0, bSum = 0.0, n = 0
        for yy in (cy - half)...(cy + half) {
            for xx in (cx - half)...(cx + half) {
                if xx < 0 || yy < 0 || xx >= buf.w || yy >= buf.h { continue }
                let i = (yy * buf.w + xx) * 4
                rSum += Double(buf.data[i]); bSum += Double(buf.data[i + 2]); n += 1
            }
        }
        if n == 0 { return nil }
        return rSum / Double(n) - bSum / Double(n)
    }
    let samples = [(0.44, 0.13), (0.425, 0.13), (0.455, 0.13), (0.44, 0.105), (0.44, 0.155)].compactMap { patchDiff($0.0, $0.1) }
    if samples.isEmpty { return nil }
    let med = samples.sorted()[samples.count / 2]
    if med > 60 { return "F" }
    if med < -60 { return "M" }
    return nil
}

// 性別アイコンから性別フォルムを選ぶ (決まらなければ nil)
func pickByGender(_ group: [SpeciesEntry], _ gender: String?) -> SpeciesEntry? {
    guard let g = gender else { return nil }
    if g == "F" { return group.first { $0.en.hasSuffix("-F") } }
    return group.first { $0.en.hasSuffix("-M") } ?? group.first { !$0.en.hasSuffix("-F") }
}

// 能力画面で読めた情報 (性別・特性・技) からフォルムを判別する。
// 優先順位: 性別フォルム同士は性別アイコン → 特性プール → 習得技。
// リージョンフォルム等は特性プールが異なることが多く (例: キュウコンの
// 「ゆきふらし」はアローラだけ)、特性プールが完全一致する組 (ロトム等) は
// フォルム専用技 (例: ロトムの「オーバーヒート」はヒートだけ) で判別する。
func resolveForme(_ group: [SpeciesEntry], gender: String?, abilityJa: String?, movesJa: [String], fallback: SpeciesEntry) -> SpeciesEntry {
    var cands = group
    // 1) 性別軸: -F/-M フォルムを含むグループでは性別で反対側を除外する
    if let g = gender, cands.contains(where: { $0.en.hasSuffix("-F") || $0.en.hasSuffix("-M") }) {
        if g == "F" {
            if let f = cands.first(where: { $0.en.hasSuffix("-F") }) { return f }
            cands = cands.filter { !$0.en.hasSuffix("-M") }
        } else {
            if let m = cands.first(where: { $0.en.hasSuffix("-M") }) { return m }
            cands = cands.filter { !$0.en.hasSuffix("-F") }
        }
        if cands.count == 1 { return cands[0] }
    }
    // 2) 特性で絞り込む
    if let ja = abilityJa {
        let en = abilityJa2En[ja] ?? abilityJa2En.first(where: { normalize($0.key) == normalize(ja) })?.value
        if let en {
            let f = cands.filter { speciesAbilityMap[$0.en]?.contains(en) == true }
            if !f.isEmpty { cands = f }
            if cands.count == 1 { return cands[0] }
        }
    }
    // 3) 技で絞り込む: その技を覚える候補が1つだけなら確定。
    //    技データが無い (空の) 候補は「不明」として候補に残す。
    for ja in movesJa {
        guard let en = moveJa2En[ja] ?? moveJa2En.first(where: { normalize($0.key) == normalize(ja) })?.value else { continue }
        let learners = cands.filter { sp in
            guard let list = speciesMoveMap[sp.en], !list.isEmpty else { return true }
            return list.contains(en)
        }
        if learners.count == 1 { return learners[0] }
        if !learners.isEmpty && learners.count < cands.count { cands = learners }
        if cands.count == 1 { return cands[0] }
    }
    return cands.first { $0.en == fallback.en } ?? cands[0]
}

var baseStatsMap: [String: [Int]] = [:]
var baseStatsLoaded = false
func loadBaseStats() {
    if baseStatsLoaded { return }
    baseStatsLoaded = true
    let url = scriptDir.appendingPathComponent("data/base_stats.json")
    guard let data = try? Data(contentsOf: url),
          let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
    for (name, v) in obj {
        if let arr = v as? [Int], arr.count == 6 { baseStatsMap[name] = arr }
    }
}

// 性格 25 種の補正先/元の能力インデックス (1=atk, 2=def, 3=spa, 4=spd, 5=spe)
let natureTable: [(up: Int?, down: Int?)] = [
    (nil, nil), (1, 2), (1, 5), (1, 3), (1, 4),
    (2, 1), (nil, nil), (2, 5), (2, 3), (2, 4),
    (5, 1), (5, 2), (nil, nil), (5, 3), (5, 4),
    (3, 1), (3, 2), (3, 5), (nil, nil), (3, 4),
    (4, 1), (4, 2), (4, 5), (4, 3), (nil, nil),
]

// 種族値・SP・性格から Lv50 (IV31) の実数値を計算する (Champions の計算式)
func expectedStats(base: [Int], sp: [String: Int], speciesEn: String, up: Int?, down: Int?) -> [Int] {
    let keys = ["hp", "atk", "def", "spa", "spd", "spe"]
    var out: [Int] = []
    for i in 0..<6 {
        let ev = (sp[keys[i]] ?? 0) * 8
        let core = (2 * base[i] + 31 + ev / 4) * 50 / 100
        if i == 0 {
            out.append(speciesEn == "Shedinja" ? 1 : core + 60)
        } else {
            var v = core + 5
            if up == i { v = v * 11 / 10 } else if down == i { v = v * 9 / 10 }
            out.append(v)
        }
    }
    return out
}

// 実数値 + SP が、その種族値で再現できるか (完全一致、または
// 1 項目だけの補正で一致するか)。ステータス画面のフォルム判別用:
// 画面には特性が出ないため、種族値の整合が判別材料になる
func statsFitForme(base: [Int], stats: [String: Int], spHint: [String: Int], speciesEn: String) -> Bool {
    let keys = ["hp", "atk", "def", "spa", "spd", "spe"]
    let read = keys.map { stats[$0] ?? -1 }
    var corrections = Set<String>()
    for nt in natureTable {
        let exp = expectedStats(base: base, sp: spHint, speciesEn: speciesEn, up: nt.up, down: nt.down)
        if exp == read { return true }
        let diffs = (0..<6).filter { exp[$0] != read[$0] }
        if diffs.count == 1 { corrections.insert(keys[diffs[0]]) }
    }
    return corrections.count == 1
}

func captureTeamScreen(image: CGImage, tab: String) -> Int {
    if isBlankFrame(image) { noteBlankFrame(true); return 0 }
    noteBlankFrame(false)
    var updated = 0
    var screenSpecies: [String] = []
    let teamBuf = makeFullBuffer(image)
    for row in 0..<3 {
        for col in 0..<2 {
            let x0 = cardXs[col], y0 = cardYs[row]
            let boxes = ocrBoxes(image, x0: x0, y0: y0, x1: x0 + cardW, y1: y0 + cardH)
            if boxes.isEmpty { continue }
            var sp: SpeciesEntry? = nil
            for b in boxes { if let m = matchSpecies(texts: [b.text]) { sp = m; break } }
            guard let matched = sp else {
                diagPrint("  カード[\(row * 2 + col + 1)]: 種族名を読み取れませんでした")
                continue
            }
            let group = formeGroup(matched)
            let gender = group.count > 1 ? cardGender(buf: teamBuf, cardX: x0, cardY: y0) : nil
            var species = pickByGender(group, gender) ?? matched
            if species.en != matched.en { diagPrint("  フォルム判別: \(matched.ja) (性別 \(gender ?? "?")) -> \(species.en)") }
            var entry: [String: Any] = teamEntries[species.en] ?? ["species": species.en]
            if tab == "status" {
                let labelVariants: [(String, [String])] = [
                    ("hp", ["HP"]), ("atk", ["こうげき", "攻撃"]), ("def", ["ぼうぎょ", "防御"]),
                    ("spa", ["とくこう", "特攻"]), ("spd", ["とくぼう", "特防"]), ("spe", ["すばやさ", "素早さ"]),
                ]
                var stats: [String: Int] = [:]
                var spHint: [String: Int] = [:]
                // 行バンド (cy の近いボックスの集まり) ごとに、テキストの出現順に
                // 「ラベル → 最初の数字 = 実数値、次の数字 = SP」と割り当てる。
                // ラベルと実数値が同じ OCR ボックスに含まれるケース
                // (例: 「とくこう 175」) でも正しく割り当てられる。
                let sortedBoxes = boxes.sorted { $0.cy < $1.cy }
                var bands: [[OcrBox]] = []
                for b in sortedBoxes {
                    if let last = bands.last, let first = last.first, abs(b.cy - first.cy) <= 0.016 {
                        bands[bands.count - 1].append(b)
                    } else { bands.append([b]) }
                }
                let numRe = try! NSRegularExpression(pattern: "\\d+")
                for band in bands {
                    var currentKey: String? = nil
                    var nums: [Int] = []
                    func flush() {
                        if let k = currentKey {
                            if let v = nums.first { stats[k] = v }
                            if nums.count > 1 && nums[1] <= 32 { spHint[k] = nums[1] }
                        }
                        nums = []
                    }
                    for b in band.sorted(by: { $0.x0 < $1.x0 }) {
                        let ns = b.text as NSString
                        var events: [(pos: Int, label: String?, num: Int?)] = []
                        for (key, variants) in labelVariants {
                            for v in variants {
                                let r = ns.range(of: v)
                                if r.location != NSNotFound { events.append((r.location, key, nil)) }
                            }
                        }
                        if events.isEmpty {
                            // 濁点落ちなどで原文一致しない場合は loose 判定でラベル扱い
                            let lt = looseText(b.text)
                            for (key, variants) in labelVariants where variants.contains(where: { lt.contains(looseText($0)) }) {
                                events.append((0, key, nil))
                                break
                            }
                        }
                        for m in numRe.matches(in: b.text, range: NSRange(location: 0, length: ns.length)) {
                            if let v = Int(ns.substring(with: m.range)) { events.append((m.range.location, nil, v)) }
                        }
                        for e in events.sorted(by: { $0.pos < $1.pos }) {
                            if let k = e.label { flush(); currentKey = k }
                            else if let v = e.num { nums.append(v) }
                        }
                    }
                    flush()
                }
                // フォルム判別 (ステータス): 実数値 + SP が再現できる
                // フォルムがグループ内で 1 つだけなら、そのフォルムと
                // して登録する。ステータス画面には特性が無いため、
                // 種族値の整合が唯一の判別材料になる (実例: 2026-11-22、
                // キュウコンのステータス撮影が原種として登録され、
                // 実数値が原種の種族値と整合せず丸ごと弾かれた。
                // アローラ種族値では性格・SP 込みで完全一致する)
                if group.count > 1 && stats.count == 6 && spHint.count == 6 {
                    loadBaseStats()
                    let fits = group.filter { g in
                        guard let b = baseStatsMap[g.en] else { return false }
                        return statsFitForme(base: b, stats: stats, spHint: spHint, speciesEn: g.en)
                    }
                    if fits.count == 1, let f = fits.first, f.en != species.en {
                        diagPrint("  フォルム判別(ステータス): \(species.ja) -> \(f.en)")
                        if let existing = teamEntries[f.en] {
                            var merged = existing
                            for (k, v) in entry { merged[k] = v }  // 今回読んだ値を優先
                            entry = merged
                        }
                        teamEntries.removeValue(forKey: species.en)
                        teamOrder.removeAll { $0 == species.en }
                        species = f
                    }
                }
                // SP が 6 項目とも読めた場合は、実数値が「種族値 + SP + 性格」で
                // 再現できるか検証する。ステータス画面の 1 桁誤読 (例: HP 162 を
                // 161 と読む) は範囲チェック (20...999) をすり抜けて登録され、
                // 対戦中のプレート読み (登録値と違う最大 HP を弾く) まで汚染する
                // ため、ここで弾く/直す (2026-11-20 グレンアルマ HP 161 誤登録の教訓)
                var statsRejected = false
                if spHint.count == 6 && stats.count == 6 {
                    loadBaseStats()
                    if let base = baseStatsMap[species.en] {
                        let keys = ["hp", "atk", "def", "spa", "spd", "spe"]
                        let read = keys.map { stats[$0] ?? -1 }
                        var matched = false
                        var corrections = Set<String>()
                        for nt in natureTable {
                            let exp = expectedStats(base: base, sp: spHint, speciesEn: species.en, up: nt.up, down: nt.down)
                            if exp == read { matched = true; break }
                            let diffs = (0..<6).filter { exp[$0] != read[$0] }
                            if diffs.count == 1 { corrections.insert("\(keys[diffs[0]])=\(exp[diffs[0]])") }
                        }
                        if !matched {
                            if corrections.count == 1, let c = corrections.first {
                                let kv = c.split(separator: "=")
                                let k = String(kv[0])
                                let v = Int(kv[1]) ?? 0
                                diagPrint("  [\(species.ja)] 実数値の誤読を補正: \(k) \(stats[k] ?? -1) -> \(v) (SP から再計算)")
                                stats[k] = v
                            } else {
                                statsRejected = true
                                diagPrint("  [\(species.ja)] 実数値が SP と整合しないため登録を見送りました: \(stats) / SP \(spHint) — ステータス画面をもう一度撮影してください")
                            }
                        }
                    }
                }
                // 読めた項目は部分的にでも反映する (既存の登録値とマージ)。
                // ただし Lv50 の実数値としてありえない値 (例: とくこう 8) は誤読として除外する。
                let invalid = stats.filter { $0.value < 20 || $0.value > 999 }
                let validStats = statsRejected ? [String: Int]() : stats.filter { $0.value >= 20 && $0.value <= 999 }
                if !validStats.isEmpty {
                    var merged = (entry["stats"] as? [String: Int]) ?? [:]
                    for (k, v) in validStats { merged[k] = v }
                    entry["stats"] = merged
                    if spHint.count == 6 { entry["spHint"] = spHint }
                    updated += 1
                    var note: [String] = []
                    let missing = labelVariants.map { $0.0 }.filter { validStats[$0] == nil && invalid[$0] == nil }
                    if !missing.isEmpty { note.append("未読: \(missing.joined(separator: ","))") }
                    if !invalid.isEmpty { note.append("誤読として除外: \(invalid.map { "\($0.key)=\($0.value)" }.joined(separator: ","))") }
                    diagPrint("  [\(species.ja)] ステータス登録: \(validStats)\(note.isEmpty ? "" : " (\(note.joined(separator: " / ")))")")
                } else {
                    diagPrint("  [\(species.ja)] ステータスを読めませんでした")
                }
            } else {
                // カード内は左列 = 特性・持ち物、右列 = 技。列で候補を分けないと
                // 持ち物「サイコシード」が技「サイコシフト」に誤マッチし、
                // 本物の4技目が押し出される (2026-11-20 の誤検出報告)。
                var moves: [(cy: Double, name: String, exact: Bool)] = []
                var got = false
                var readAbilityJa: String? = nil
                for b in boxes {
                    if normalize(b.text) == normalize(species.ja) { continue }
                    let nt = normalize(b.text)
                    if nt.isEmpty { continue }
                    if (b.cx - x0) / cardW > 0.50 {
                        // 右列: 技のみ。特性・持ち物と完全一致する語は技にしない
                        if abilityDict[nt] != nil || itemDict[nt] != nil { continue }
                        if let mv = moveNameOrig[nt] {
                            moves.append((b.cy, mv, true))
                            diagPrint("    技候補(右列): 「\(b.text)」-> \(mv)")
                        } else if let (mv, sc) = fuzzyScore(b.text, in: moveNameOrig), sc >= 0.80 {
                            moves.append((b.cy, mv, false))
                            diagPrint("    技候補(右列・あいまい \(String(format: "%.2f", sc))): 「\(b.text)」-> \(mv)")
                        } else {
                            diagPrint("    技候補なし(右列): 「\(b.text)」")
                        }
                    } else {
                        // 左列: 特性・持ち物のうちスコアの高い方
                        let abF = fuzzyScore(b.text, in: abilityDict)
                        let itF = fuzzyScore(b.text, in: itemDict)
                        if let a = abF, itF == nil || a.1 >= itF!.1 {
                            entry["ability"] = a.0; got = true; readAbilityJa = a.0
                            diagPrint("    特性候補(左列): 「\(b.text)」-> \(a.0)")
                        } else if let i2 = itF {
                            entry["item"] = i2.0; got = true
                            diagPrint("    持ち物候補(左列): 「\(b.text)」-> \(i2.0)")
                        }
                    }
                }
                // 重複を除き cy 順。5件以上ある場合は完全一致を優先して4件に絞る
                var seen = Set<String>()
                var uniq: [(cy: Double, name: String, exact: Bool)] = []
                for m in moves.sorted(by: { $0.cy < $1.cy }) where !seen.contains(m.name) {
                    seen.insert(m.name); uniq.append(m)
                }
                if uniq.count > 4 {
                    uniq = Array(uniq.sorted { ($0.exact ? 0 : 1, $0.cy) < ($1.exact ? 0 : 1, $1.cy) }.prefix(4))
                        .sorted { $0.cy < $1.cy }
                }
                var readMovesJa: [String] = []
                if !uniq.isEmpty { entry["moves"] = uniq.map { $0.name }; got = true; readMovesJa = uniq.map { $0.name } }
                // 性別・特性・技からフォルムを確定する。これにより能力画面の
                // 撮影だけでも性別違い・リージョン違い等を判別できる。
                if group.count > 1 {
                    let r = resolveForme(group, gender: gender, abilityJa: readAbilityJa, movesJa: readMovesJa, fallback: species)
                    if r.en != species.en {
                        diagPrint("  フォルム判別(能力): \(species.ja) -> \(r.en)")
                        if let existing = teamEntries[r.en] {
                            var merged = existing
                            for (k, v) in entry { merged[k] = v }  // 今回読んだ値を優先
                            entry = merged
                        }
                        teamEntries.removeValue(forKey: species.en)
                        teamOrder.removeAll { $0 == species.en }
                        species = r
                    }
                }
                if got {
                    updated += 1
                    diagPrint("  [\(species.ja)] 能力登録: 技\(entry["moves"] != nil ? "あり" : "なし") / 特性\(entry["ability"] != nil ? "あり" : "なし") / 持ち物\(entry["item"] != nil ? "あり" : "なし")")
                } else {
                    diagPrint("  [\(species.ja)] 能力を読めませんでした")
                }
            }
            entry["species"] = species.en
            teamEntries[species.en] = entry
            if !teamOrder.contains(species.en) { teamOrder.append(species.en) }
            screenSpecies.append(species.en)
        }
    }
    // 1画面分 (5体以上) 読めたら、その画面の6体を「現在のチーム」とし、
    // 以前のチームの残りは登録から外す (能力→ステータスの順の取り込みでは同じ6体なのでデータは残る)
    var pruned = false
    if screenSpecies.count >= 5 {
        let keep = Set(screenSpecies)
        if teamOrder.count != screenSpecies.count || !teamOrder.allSatisfy({ keep.contains($0) }) {
            teamEntries = teamEntries.filter { keep.contains($0.key) }
            teamOrder = screenSpecies
            pruned = true
        }
    } else if screenSpecies.count >= 2 {
        // 部分的にしか読めなかった場合も、読めた分は画面の並び順に
        // 揃えて書く (読めなかった分は従来の相対順のまま後ろに残す)。
        // 検出順のまま末尾へ追加されると、UI のアイコン列の並びが
        // 画面とずれる (実例: 2026-11-22、4 番目のキュウコンが
        // 最後尾に並んだ)
        let onScreen = Set(screenSpecies)
        let rest = teamOrder.filter { !onScreen.contains($0) }
        if teamOrder != screenSpecies + rest {
            teamOrder = screenSpecies + rest
            pruned = true
        }
    }
    if updated > 0 || pruned { writeTeamFile() }
    lastCaptureSpecies = screenSpecies
    return updated
}

// 画面が「チーム確認画面 (6体一覧)」かどうかを、カード位置に種族名が
// 読めるカードの数で判定する。対戦画面など別画面のまま撮影ボタンが押された
// 場合に、場のポケモンを誤って登録してしまう事故を防ぐための事前ガード
// (captureTeamScreen は読めた内容をその場でマージしてしまうため、
//  書き込み前にここで弾く)
func teamScreenCardCount(image: CGImage) -> Int {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    var found = 0
    for row in 0..<3 {
        for col in 0..<2 {
            let x0 = cardXs[col], y0 = cardYs[row]
            let inCard = boxes.filter { b in
                b.cx >= x0 && b.cx < x0 + cardW && b.cy >= y0 && b.cy < y0 + cardH
            }
            if inCard.contains(where: { matchSpecies(texts: [$0.text]) != nil }) { found += 1 }
        }
    }
    return found
}

// MARK: - 撮影ボタンの HTTP 受付 (UI から localhost:8899/capture?tab=ability|status)

// 見せ合いテスト用の一発同定 (テスト用 .sh から localhost:8899/previewtest)。
// 対戦の流れとは独立に、その時点の画面で identifyPreview を 1 回だけ
// 実行し、撮影画像と結果を logs/preview_test_<日時>.jpg/.json に残す。
// 投票・選出セッション・ログ状態には一切触れない。結果 JSON は
// ログ分析チャットでの精度分析用に、枠ごとの候補・タイプ・スコアを
// 含む (preview_id の証拠と同じ形)
func handlePreviewTestRequest() -> String {
    guard let img = captureQuickTime() else {
        return "{\"ok\":false,\"error\":\"QuickTime の画面を取得できませんでした\"}"
    }
    if isBlankFrame(img) {
        return "{\"ok\":false,\"error\":\"画面が暗い/真っ黒です（iPad の画面が消えていないか確認してください）\"}"
    }
    let result = identifyPreview(image: img)
    let base = "preview_test_\(battleStamp())"
    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
    var imageFile = ""
    if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
       (try? data.write(to: logsDirURL.appendingPathComponent(base + ".jpg"))) != nil {
        imageFile = base + ".jpg"
    }
    let slotDetails: [[String: Any]] = (result?.slots ?? []).map { s in
        ["pick": s.pick ?? "", "score": (s.score * 1000).rounded() / 1000,
         "decisive": s.decisive, "expanded": s.expanded, "types": s.types, "gender": s.gender,
         "candidates": s.candidates.map { [$0.0, ($0.1 * 1000).rounded() / 1000] as [Any] },
         "panel": s.panel, "iconDiag": s.iconDiag, "genderCounts": s.genderCounts]
    }
    var oppTeam: [String] = (result?.team ?? []).map { $0 ?? "" }
    while oppTeam.count < 6 { oppTeam.append("") }
    let mineLine = (trainerMine.isEmpty ? "Your team:" : "\(trainerMine)'s team:") + " " + teamOrder.joined(separator: " / ")
    let oppLine = (trainerOpp.isEmpty ? "Opponent" : trainerOpp) + "'s team: " + oppTeam.map { $0.isEmpty ? "?" : $0 }.joined(separator: " / ")
    let f = ISO8601DateFormatter()
    f.timeZone = TimeZone(identifier: "Asia/Tokyo")
    f.formatOptions = [.withInternetDateTime]
    let ev: [String: Any] = ["kind": "preview_test", "at": f.string(from: Date()), "readerBuild": readerBuild,
                             "trainerMine": trainerMine, "trainerOpp": trainerOpp,
                             "mine": teamOrder, "oppTeam": oppTeam, "slots": slotDetails,
                             "identified": result != nil, "lines": [mineLine, oppLine],
                             "jpg": imageFile, "json": base + ".json"]
    if let data = try? JSONSerialization.data(withJSONObject: ev, options: [.prettyPrinted, .sortedKeys]) {
        try? data.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)
    }
    print("[preview-test] 見せ合いテストを保存しました: logs/\(base) (同定: \(result != nil ? "実施" : "失敗"))")
    print(mineLine)
    print(oppLine)
    fflush(stdout)
    let respObj: [String: Any] = ["ok": true, "lines": [mineLine, oppLine],
                                  "jpg": imageFile, "json": base + ".json", "slots": slotDetails]
    if let data = try? JSONSerialization.data(withJSONObject: respObj, options: []),
       let s = String(data: data, encoding: .utf8) { return s }
    return "{\"ok\":false,\"error\":\"結果の作成に失敗しました\"}"
}

var captureListener: NWListener? = nil

func startCaptureServer() {
    guard let port = NWEndpoint.Port(rawValue: 8899) else { return }
    guard let listener = try? NWListener(using: .tcp, on: port) else { return }
    listener.newConnectionHandler = { conn in
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            if let d = data, let s = String(data: d, encoding: .utf8), s.contains("previewtest") {
                let body = handlePreviewTestRequest()
                let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                return
            }
            var tab = "ability"
            if let d = data, let s = String(data: d, encoding: .utf8), s.contains("tab=status") { tab = "status" }
            var body = "{\"ok\":false,\"error\":\"QuickTime の画面を取得できませんでした\"}"
            if let img = captureQuickTime() {
                if isBlankFrame(img) {
                    body = "{\"ok\":false,\"error\":\"画面が暗い/真っ黒です（iPad の画面が消えていないか確認してください）\"}"
                    let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
                    conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
                    return
                }
                let cards = teamScreenCardCount(image: img)
                if cards < 4 {
                    // チーム確認画面ではない画面 (対戦画面など) のまま押された。
                    // 部分的に読めても登録には使わず、画面違いとして返す
                    print("[撮影] チーム確認画面と判定できませんでした (カード検出 \(cards)/6) — 登録は行っていません")
                    fflush(stdout)
                    body = "{\"ok\":false,\"error\":\"チーム確認画面（6体一覧の能力/ステータス表示）を表示してから撮影してください（カード検出 \(cards)/6）\"}"
                } else {
                    let n = captureTeamScreen(image: img, tab: tab)
                    if n > 0 {
                        let spJson = lastCaptureSpecies.map { "\"\($0)\"" }.joined(separator: ",")
                        let spJa = lastCaptureSpecies.map { pvJa($0) }.joined(separator: "・")
                        print("[撮影] \(tab == "status" ? "ステータス" : "能力")画面を取り込みました (更新 \(n) 件): \(spJa)")
                        fflush(stdout)
                        body = "{\"ok\":true,\"registered\":\(teamOrder.count),\"species\":[\(spJson)],\"message\":\"取り込みました（登録 \(teamOrder.count)/6）\"}"
                    } else {
                        print("[撮影] チーム画面を読み取れませんでした (カード検出 \(cards)/6)")
                        fflush(stdout)
                        body = "{\"ok\":false,\"error\":\"チーム画面を読み取れませんでした\"}"
                    }
                }
            }
            let resp = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nAccess-Control-Allow-Origin: *\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n" + body
            conn.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in conn.cancel() })
        }
    }
    listener.start(queue: .global())
    captureListener = listener
}

// MARK: - メイン

loadDict()
loadMoveDict()
loadRoleDicts()
loadTeamFile()
loadPreviewData()
loadLogNames()
loadSpeciesAbilities()
loadSpeciesMoves()
let args = CommandLine.arguments
let once = args.contains("--once")
let teamMode = args.contains("--team")
var teamScreenTab: String? = nil
if let i = args.firstIndex(of: "--team-screen"), i + 1 < args.count { teamScreenTab = args[i + 1] }
var intervalSec = 0.5
if let i = args.firstIndex(of: "--interval"), i + 1 < args.count { intervalSec = Double(args[i + 1]) ?? 0.5 }
debugMode = args.contains("--debug")
teamDiag = teamScreenTab != nil

if let i = args.firstIndex(of: "--image"), i + 1 < args.count {
    guard let img = loadImage(path: args[i + 1]) else {
        fputs("画像が読めません: \(args[i + 1])\n", stderr)
        exit(1)
    }
    if args.contains("--debug") { runDebug(image: img); exit(0) }
    if teamMode { runTeamOnce(image: img) }
    else if let tab = teamScreenTab {
        let n = captureTeamScreen(image: img, tab: tab)
        print("チーム画面取り込み (\(tab)): \(n) 件のカードを処理 — 登録済み \(teamOrder.count)/6")
    }
    else { runOnce(image: img) }
    exit(0)
}

if args.contains("--debug") {
    if let win = findQuickTimeWindow() {
        print("QuickTime ウィンドウ: \(Int(win.bounds.width))x\(Int(win.bounds.height))")
    } else {
        print("QuickTime ウィンドウが見つかりません")
    }
    if let img = captureQuickTime() { runDebug(image: img) }
    exit(0)
}

if let tab = teamScreenTab {
    if let img = captureQuickTime() {
        let n = captureTeamScreen(image: img, tab: tab)
        print("チーム画面取り込み (\(tab)): \(n) 件のカードを処理 — 登録済み \(teamOrder.count)/6")
    } else {
        print("QuickTime の画面を取得できませんでした")
    }
    exit(0)
}

// 前回セッションが強制終了していた場合、残留した試合ログを先に救済する
// (この後の処理で battle.log が上書きされる前に logs/ へ逃がす)
salvageLeftoverLogs()
cleanupOldDebugShots()

startCaptureServer()
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
}
