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

func captureQuickTime() -> CGImage? {
    guard let win = findQuickTimeWindow() else {
        if debugMode && lastCaptureOK { print("QuickTime Player のウィンドウが見つかりません。iPadを表示した状態で再試行してください。") }
        lastCaptureOK = false
        return nil
    }
    let tmp = NSTemporaryDirectory() + "champions_capture.png"
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    p.arguments = ["-l", "\(win.id)", "-o", "-x", tmp]
    try? p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0,
          let img = NSImage(contentsOfFile: tmp),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        if debugMode && lastCaptureOK { print("画面の取り込みに失敗しました (画面収録の権限を確認してください)。") }
        lastCaptureOK = false
        return nil
    }
    lastCaptureOK = true
    return cg
}

func loadImage(path: String) -> CGImage? {
    guard let img = NSImage(contentsOfFile: path) else { return nil }
    return img.cgImage(forProposedRect: nil, context: nil, hints: nil)
}

// MARK: - OCR

func ocr(_ image: CGImage, plate: Plate) -> [String] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ja-JP", "en-US"]
    req.usesLanguageCorrection = false
    // Vision の regionOfInterest は左下原点・正規化座標
    req.regionOfInterest = CGRect(x: plate.x0, y: 1.0 - plate.y1, width: plate.x1 - plate.x0, height: plate.y1 - plate.y0)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([req])
    return (req.results ?? []).compactMap { $0.topCandidates(1).first?.string }
}

// MARK: - パース

struct SlotState { var speciesEn: String; var hpPercent: Int; var hpCur: Int? = nil; var hpMax: Int? = nil }
var lastSlots: [String: SlotState] = [:]
var lastWritten = ""
// 相手の6体コレクション: 対戦中にプレートで読み取れた相手種族を登場順に蓄積する (見せ合い画面には名前テキストが無いため)
var oppTeamSeen: [String] = []
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

func writeState() {
    // state.json はバトルログ由来の状態 (monStates) から生成する
    func slotJSON(_ key: String) -> String? {
        guard let s = lastSlots[key] else { return nil }
        let side = key.hasPrefix("mine") ? "p1" : "p2"
        let st = monStates["\(side):\(s.speciesEn)"]
        var e = "{\"species\": \"\(jsonEscape(s.speciesEn))\", \"curHPPercent\": \(st?.hpPercent ?? s.hpPercent)"
        if let st, !st.status.isEmpty { e += ", \"status\": \"\(st.status)\"" }
        if unburdenActive.contains("\(side):\(s.speciesEn)") { e += ", \"unburden\": true" }
        if let st, !st.megaSpecies.isEmpty { e += ", \"mega\": true, \"megaSpecies\": \"\(jsonEscape(st.megaSpecies))\"" }
        if let st, !st.boosts.isEmpty {
            let bs = ["atk", "def", "spa", "spd", "spe"].compactMap { k -> String? in
                guard let v = st.boosts[k], v != 0 else { return nil }
                return "\"\(k)\": \(v)"
            }
            if !bs.isEmpty { e += ", \"boosts\": {\(bs.joined(separator: ", "))}" }
        }
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
    // 終了したはずの天候・フィールドが残り続けるため
    let field = "{\"terrain\": \"\(logFieldTerrain)\", \"weather\": \"\(logFieldWeather)\"}"
    let trainer = trainerOpp.isEmpty ? "" : ", \"oppTrainer\": \"\(jsonEscape(trainerOpp))\""
    let eventsJson = ", \"events\": [\(battleEvents.joined(separator: ", "))]"
    let json = "{\"mine\": [\(mine.joined(separator: ", "))], \"opps\": [\(opps.joined(separator: ", "))]\(team)\(revJson)\(trainer)\(eventsJson), \"field\": \(field)}"
    if json == lastWritten { return }
    lastWritten = json
    try? json.write(to: outURL, atomically: true, encoding: .utf8)
}

// MARK: - バトルログ (Showdown プロトコル形式)
// 画面から観測した出来事を Showdown のバトルログ形式で蓄積する。
// ターミナルにはこのログだけを表示し、battle.log にも保存する。
// ダメ計への反映 (state.json) は、このログ由来の状態から生成する。

let battleLogURL = scriptDir.appendingPathComponent("battle.log")
var battleLog: [String] = []
var logStarted = false
var currentTurn = 0
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
var pendingStatusFrom: [String: (code: String, at: Date)] = [:]  // "p1:Species" -> 状態異常ダメージの帰属
var lastDamageLabel = ""                          // 直近にダメージを受けた枠 (急所の帰属先)
var lastDamageAt = Date.distantPast
var lastPendingLabel = ""                         // 確定待ちダメージの枠 (急所はダメージ行より先に表示される)
var pendingSwitchSpecies: [String: String] = [:]  // プレート名 -> 確定待ちの交代先種族
var pendingSwitchCount: [String: Int] = [:]       // 同じ種族が連続で見えた回数
var actionSeq = 0                                  // |move| / |turn| の通し番号 (行動の区切り)
var lastDamageSeq: [String: Int] = [:]             // プレート名 -> ダメージ行を出した行動番号
var lastDamageTurn: [String: Int] = [:]            // プレート名 -> ダメージ行を出したターン番号
var lastDamageDir: [String: Int] = [:]             // プレート名 -> 最後に出した行の向き (-1: ダメージ / +1: 回復)
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
var lastSingleActAt: [String: Date] = [:]         // 枠 -> |-singleactivate| を出した時刻
var lastAbilityEmit: [String: Date] = [:]         // "side:種族:特性" -> |-ability| を出した時刻 (二重出力の抑止)
var turnRawFrames = 0                             // プレート生読みで 4 枚見えた連続フレーム数 (ターン誤発火の保険)
var lastMoveLabel = ""                            // 直近の |move| の使用者ラベル (ミスの帰属用)
var lastMoveName = ""                             // 直近の |move| の技名 (EN, 推定イベント用)
var lastMoveSeq = -1                              // 直近の |move| が出た actionSeq
var battleEvents: [String] = []                   // 推定エンジン用イベント (JSON 断片の配列)
var lastExactHp: [String: [Int]] = [:]            // key -> [現在HP, 最大HP] (自軍の正確な数値の追跡)
var lastMoveMsgAt = Date.distantPast
var lastFallbackText = ""                         // 直近の |-message| の正規化文 (OCR ゆれの重複防止)
var fieldWeatherSetAt = Date.distantPast          // 天候が張られた時刻 (特性の帰属判定用)
var fieldTerrainSetAt = Date.distantPast          // フィールドが張られた時刻
var lastSwitchIn: [String: (slot: String, at: Date)] = [:]  // "side:Species" -> 場に出た枠と時刻
var fieldAbilityDone: [String: Date] = [:]        // "side:Species" -> 特性帰属済みの繰り出し時刻
var intimidateDone: [String: Date] = [:]          // "side:Species" -> いかく帰属済みの繰り出し時刻
var lastBoostApply: [String: (seq: Int, turn: Int, at: Date)] = [:]  // "slot|stat|delta" -> 最終適用 (再読での二重適用防止)
var emittedSwitchKeys: Set<String> = []            // |switch| を出した "side:Species" (ランク変化行の保留判定)
var pendingUnburden: Set<String> = []              // 交代行が出る前にシード消費を検知した種族 (かるわざ発動を交代行の後に出す)
var unburdenActive: Set<String> = []               // かるわざ発動中 (state.json の unburden フラグ用。交代で解除)
var heldBoostLines: [String: [(stat: String, delta: Int, at: Date)]] = [:]  // 交代行より先に届いたランク変化の保留 (枠は出す時点で付け直す)
var recentAtkDrops: [String: (at: Date, seq: Int)] = [:]  // "side:Species" -> 攻撃 -1 の適用 (いかく遡及帰属用)
var lastEffectAt: [String: Date] = [:]            // 相性行の二重出力防止 ("slot|kind")
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
        return ["\(mine) and \(oppName) joined", "Format:", "[Gen 9 Champions] VGC 2026 Reg \(regulationDisplay())", "Rated battle",
                "Species Clause: Limit one of each Pokémon", "Item Clause: Limit 1 of each item",
                trainerMine.isEmpty ? "Your team:" : "\(trainerMine)'s team:", renderPokeP1.joined(separator: " / "),
                "\(oppName)'s team:", renderPokeP2.joined(separator: " / "), "",
                "Battle started between \(mine) and \(oppName)!", ""]
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
    case "-activate":
        guard f.count >= 4 else { return [] }
        let (_, side, species) = renderLabelParts(f[2])
        if f[3].contains("Focus Sash") { return ["(\(renderPrefix(side))\(species) held on thanks to its Focus Sash!)"] }
        if f[3].contains("Protect") { return ["\(renderPrefix(side))\(species) protected itself!"] }
        return []
    case "-sidestart", "-sideend":
        guard f.count >= 4 else { return [] }
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

func emitLog(_ line: String) {
    if line.hasPrefix("|move|") || line.hasPrefix("|turn|") { actionSeq += 1 }
    battleLog.append(line)
    // 推定エンジン用イベント (技の使用順)
    if line.hasPrefix("|move|") {
        let f = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        if f.count >= 4 && battleEvents.count < 600 {
            battleEvents.append("{\"k\":\"mv\",\"turn\":\(currentTurn),\"label\":\"\(jsonEscape(f[2]))\",\"move\":\"\(jsonEscape(f[3]))\"}")
        }
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
    for l in out {
        displayLog.append(l)
        print(l)
    }
    fflush(stdout)
    try? (displayLog.joined(separator: "\n") + "\n").write(to: battleLogURL, atomically: true, encoding: .utf8)
    // 行動が起きたらコマンド選択フェーズは終わっている (ターン数えのリセット)
    if line.hasPrefix("|move|") || line.hasPrefix("|switch|") || line.hasPrefix("|faint|") {
        commandPhaseSeen = false
    }
    lastLogEventAt = Date()
}

func resetLogState() {
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
    lastMoveSigAt = [:]
    lastSingleActAt = [:]
    battleEvents = []
    lastExactHp = [:]
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
    lastEffectAt = [:]
    pendingSwitchSpecies = [:]; pendingSwitchCount = [:]
    lastDamageSeq = [:]; lastDamageTurn = [:]; lastDamageDir = [:]; lastCritAt = [:]; actionSeq = 0
    heldLine = [:]; pendingFaints = []; faintedSlots = [:]; grassyHealTurn = [:]; lastSideCondAt = [:]
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
    logStarted = false
    lastSlots = [:]
}

func startBattleLog() {
    resetLogState()
    battleLog = []
    emitLog("|gametype|doubles")
    for sp in teamOrder { emitLog("|poke|p1|\(sp)") }
    for sp in oppTeamSeen { emitLog("|poke|p2|\(sp)") }
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
    let abilityJa = side == "p1" ? (teamEntries[speciesEn]?["ability"] as? String) : revealedAbilities[speciesEn]
    guard abilityJa == "かるわざ" else { return }
    unburdenActive.insert("\(side):\(speciesEn)")
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
    let knownItem = revealedItems[speciesEn] ?? (teamEntries[speciesEn]?["item"] as? String)
    if fromPct <= 50 && (20...30).contains(delta) {
        if knownItem == nil || knownItem == "オボンのみ" { return ("item: Sitrus Berry", "オボンのみ") }
        return nil
    }
    if (3...8).contains(delta) {
        let abilityJa = revealedAbilities[speciesEn] ?? (teamEntries[speciesEn]?["ability"] as? String)
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
    var effFrom = fromPct
    var dirBase = fromPct
    if let h = heldLine[plateName], h.seq == actionSeq, h.turn == currentTurn { dirBase = h.toPct }
    let dir = toPct < dirBase ? -1 : 1
    if !force && toPct != 0 && actionSeq > 0 {
        if let h = heldLine[plateName], h.seq == actionSeq && h.turn == currentTurn, h.dir != dir {
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
    heldLine[plateName] = nil
    lastDamageSeq[plateName] = actionSeq
    lastDamageTurn[plateName] = currentTurn
    lastDamageDir[plateName] = dir
    lastEmittedPct[plateName] = toPct
    if lastPendingLabel == "\(slot): \(speciesEn)" { lastPendingLabel = "" }
    if toPct < effFrom {
        lastDamageLabel = "\(slot): \(speciesEn)"
        lastDamageAt = Date()
        var line = "|-damage|\(slot): \(speciesEn)|\(hpText)"
        if let pf = pendingStatusFrom[key], Date().timeIntervalSince(pf.at) < 5 {
            line += "|[from] \(pf.code)"
            pendingStatusFrom[key] = nil
        }
        emitLog(line)
        recordDamageEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, hpText: hpText)
    } else if toPct > effFrom {
        // 回復の発生源 (オボンのみ/たべのこし/グラッシーフィールド) が
        // 推定できれば [from] を付け、持ち物なら判明としても記録する
        let src = healSource(plateName: plateName, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct)
        if let itemJa = src?.itemJa {
            let srcSide = key.hasPrefix("p2") ? "p2" : "p1"
            emitItemOnce(slot: slot, side: srcSide, speciesEn: speciesEn, itemJa: itemJa)
            if srcSide == "p2" { revealedItems[speciesEn] = itemJa }
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
    guard battleEvents.count < 600 else { return }
    guard !lastMoveLabel.isEmpty, actionSeq - lastMoveSeq <= 1,
          Date().timeIntervalSince(lastMoveMsgAt) < 8 else { return }
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
    if defSide == "p1", let pe = prevExact, let ce = exact, pe[0] > ce[0] {
        ev += ",\"amt\":\(pe[0] - ce[0]),\"max\":\(ce[1])"
    } else {
        ev += ",\"pct\":\(fromPct - toPct)"
    }
    ev += "}"
    battleEvents.append(ev)
}

// 確定待ちのダメージをすべて吐き出す (新しいメッセージやターンの開始前に呼ぶ)。
// 値が現れてから 1.2 秒経っていないプレートは、HP バーの段階アニメーション
// 途中かもしれないため force でない限り吐かない (途中値で吐くと 1 発の被弾が
// 53%+20% のように 2 行に割れる。実例: 2026-11-20 の複数対戦)
func flushPendingDamage(force: Bool = false) {
    for plate in plates {
        guard let pend = pendingDamagePct[plate.name], let s = lastSlots[plate.name] else { continue }
        if !force, let since = pendingDamageSince[plate.name], Date().timeIntervalSince(since) < 1.2 { continue }
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
func processPlates(_ hits: [String: SlotState]) {
    if !logStarted { startBattleLog() }
    // 保留中のランク変化行: 交代行が来なくても 4 秒経ったら出す
    flushHeldBoostsTimeout()
    // 遅延中のひんし行: 文が来なくても 1.5 秒経ったら出す
    if !pendingFaints.isEmpty {
        let now = Date()
        let ready = pendingFaints.filter { now.timeIntervalSince($0.at) > 1.5 }
        if !ready.isEmpty {
            pendingFaints.removeAll { now.timeIntervalSince($0.at) > 1.5 }
            for f in ready {
                if !faintStillValid(f) { continue }
                faintedSlots[f.slot] = f.speciesEn
                emitLog("|faint|\(f.slot): \(f.speciesEn)")
            }
        }
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
            }
            if (pendingSwitchCount[plate.name] ?? 0) >= 2 {
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                // 交代要員を選んでいる間は、控え一覧画面のバーが場のプレートと
                // して読めて、生きている枠にまで交代行が出ることがある
                // (実例: 2026-11-20、グレンアルマの交代要員選択中に
                //  オオニューラが p1a に出現し、直後にサーナイトの交代行も
                //  重複した)。ひんしの枠への交代 (交代要員そのもの) は通す
                let prefix = plate.name.hasPrefix("mine") ? "mine" : "opp"
                let replacementBusy = faintedSlots[slot] == nil
                    && faintedSlots.keys.contains { $0.hasPrefix(side) } && awaitingReplacement(prefix, side)
                if !replacementBusy {
                    if let p = prev {
                        monStates["\(side):\(p.speciesEn)"]?.boosts = [:]  // 交代でランク変化はリセット
                        unburdenActive.remove("\(side):\(p.speciesEn)")  // かるわざも交代で解除
                    }
                    // 入場時点の HP と前回出場時の HP の差は、交代で入った
                    // 直後に受けた技 (や さいせいさいぼう の回復) の分。
                    // 交代行の HP に吸収されて被ダメ行が出ないため、後で補う
                    let prevPct = monStates[key]?.hpPercent ?? 100
                    pendingDamagePct[plate.name] = nil
                    heldLine[plate.name] = nil
                    lastEmittedPct[plate.name] = s.hpPercent
                    monStates[key]?.hpPercent = s.hpPercent
                    monStates[key]?.hpText = hpTextFor(s)
                    var hp = monStates[key]!.hpText
                    if let st = monStates[key]?.status, !st.isEmpty { hp += " \(st)" }
                    emitLog("|switch|\(slot): \(s.speciesEn)|\(s.speciesEn)|\(hp)")
                    recordSwitchIn(side: side, slot: slot, speciesEn: s.speciesEn)
                    if s.hpPercent != prevPct {
                        _ = emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: prevPct, toPct: s.hpPercent, hpText: hpTextFor(s), force: true)
                    }
                    faintedSlots.removeValue(forKey: slot)
                    // 0% で登場した (交代直後に技を受けて倒れた等) 場合は
                    // ひんし行を補う
                    if s.hpPercent == 0 { deferFaint(slot: slot, speciesEn: s.speciesEn) }
                    lastSlots[plate.name] = s
                }
            }
        } else {
            pendingSwitchSpecies[plate.name] = nil
            pendingSwitchCount[plate.name] = nil
            // ひんし確定済みの枠は、交代が確定するまでプレート読みを無視する
            // (交代要員選択画面で満タンのバーが読めて「全回復」行が出たり、
            //  0% に戻って ひんし行が二重に出たりした実例: 2026-11-20)
            if faintedSlots[slot] == s.speciesEn { continue }
            // 状態 (state.json) は即時更新し、ログ行だけ確定待ちにする
            monStates[key]?.hpPercent = s.hpPercent
            monStates[key]?.hpText = hpTextFor(s)
            let emitted = lastEmittedPct[plate.name] ?? s.hpPercent
            if s.hpPercent == emitted {
                pendingDamagePct[plate.name] = nil
                pendingDamageCount[plate.name] = nil
            } else if s.hpPercent == 0 {
                // 0% (ひんし) は即時
                pendingDamagePct[plate.name] = nil
                pendingDamageCount[plate.name] = nil
                emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                               fromPct: emitted, toPct: s.hpPercent, hpText: monStates[key]!.hpText)
            } else if pendingDamagePct[plate.name] == s.hpPercent {
                // 同じ値が 3 回続き、かつ現れてから 1.2 秒経った = アニメーションが
                // 落ち着いた (段階アニメーションは途中で 1 秒近く止まることが
                // あり、回数だけでは途中値を確定してしまうため時間でも見る)
                let n = (pendingDamageCount[plate.name] ?? 1) + 1
                let stable = Date().timeIntervalSince(pendingDamageSince[plate.name] ?? .distantPast) >= 1.2
                if n >= 3 && stable {
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
    if text.contains("なおった") {
        if let cur = monStates[key]?.status, !cur.isEmpty {
            monStates[key]?.status = ""
            emitLog("|-curestatus|\(slot): \(speciesEn)|\(cur)")
        }
        return
    }
    let cues = ["おかされた", "あびた", "なった", "おった", "ついた", "しまった", "ねむった"]
    guard cues.contains(where: { text.contains($0) }) else { return }
    var code: String? = nil
    if text.contains("もうどく") { code = "tox" }
    else if text.contains("どく") { code = "psn" }
    else if text.contains("やけど") { code = "brn" }
    else if text.contains("まひ") { code = "par" }
    else if text.contains("ねむ") { code = "slp" }
    else if text.contains("こおり") || text.contains("こおった") { code = "frz" }
    if let code, monStates[key]?.status != code {
        monStates[key]?.status = code
        emitLog("|-status|\(slot): \(speciesEn)|\(code)")
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
    switch chip {
    case "技":
        if let mvJa = findInDict(in: text, moveNameOrig) {
            // 実況メッセージ側で記録済みの (枠・技・ターン) は二重に出さない
            // (実例: 2026-11-20、まもる が実況とログ画面の両方から出た)
            let moveEn = moveJa2En[mvJa] ?? mvJa
            let sig = slot + "|" + moveEn + "|t" + String(turn)
            if lastMoveSigAt[sig] != nil { break }
            lastMoveSigAt[sig] = Date()
            emitLog("|move|\(slot): \(sp.en)|\(moveEn)")
            applyMoveField(mvJa)
            if side == "p2" && !(revealedMoves[sp.en]?.contains(mvJa) ?? false) {
                revealedMoves[sp.en, default: []].append(mvJa)
            }
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
                if np > cur && np - cur > 55 { break }
                monStates[key]?.hpPercent = np
                monStates[key]?.hpText = hpText
                if np < cur { emitLog("|-damage|\(slot): \(sp.en)|\(hpText)") }
                else { emitLog("|-heal|\(slot): \(sp.en)|\(hpText)") }
                if np == 0 { emitLog("|faint|\(slot): \(sp.en)") }
            }
        }
    case "ひんし":
        if (monStates[key]?.hpPercent ?? 0) > 0 {
            monStates[key]?.hpPercent = 0
            emitLog("|faint|\(slot): \(sp.en)")
        }
    case "持ち物":
        if let itJa = findInDict(in: text, itemDict) {
            emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
            if side == "p2" { revealedItems[sp.en] = itJa }
        }
    case "特性":
        if let abJa = findInDict(in: text, abilityDict) {
            emitLog("|-ability|\(slot): \(sp.en)|\(abilityJa2En[abJa] ?? abJa)")
            if side == "p2" { revealedAbilities[sp.en] = abJa }
        }
    default:
        break
    }
    checkStatusText(text: text, side: side, speciesEn: sp.en, slot: slot)
    // ランク変化はここでは適用しない: 実況メッセージで取り込み済みの変化が
    // ログ画面のエントリから二重に適用されてしまうため (ログが 2 重に出る
    // 原因の 1 つ)。ランク変化の取り込みは実況メッセージ経路に一本化する
    checkFieldText(text: text)
}

// 天候・フィールドの setter (ログ行は変化したときだけ出す)
func setWeather(_ ui: String, _ logName: String) {
    if logFieldWeather == ui { return }
    logFieldWeather = ui
    fieldWeatherSetAt = Date()
    emitLog("|-weather|\(logName)")
    attributeFieldAbilities()
}
func clearWeather() {
    if logFieldWeather.isEmpty { return }
    logFieldWeather = ""
    emitLog("|-weather|none")
}
func setTerrain(_ ui: String) {
    if logFieldTerrain == ui { return }
    logFieldTerrain = ui
    fieldTerrainSetAt = Date()
    emitLog("|-fieldstart|move: \(ui) Terrain")
    attributeFieldAbilities()
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
        emitAbilityOnce(slot: sw.slot, side: other, speciesEn: en, abilityEn: "Intimidate")
        if other == "p2" { revealedAbilities[en] = abilityJa2En.first { $0.value == "Intimidate" }?.key ?? "Intimidate" }
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
        if matched {
            fieldAbilityDone[key] = sw.at
            emitAbilityOnce(slot: sw.slot, side: side, speciesEn: en, abilityEn: ab)
            if side == "p2" { revealedAbilities[en] = abilityJa2En.first { $0.value == ab }?.key ?? ab }
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
    monStates[key]?.megaSpecies = megaEn
    let slot = slotFor(side: side, speciesEn: baseEn)
    emitLog("|detailschange|\(slot): \(baseEn)|\(megaEn)")
    var megaLine = "|-mega|\(slot): \(baseEn)|\(baseEn)"
    if let stoneJa = pendingMegaStone[side] { megaLine += "|\(itemJa2En[stoneJa] ?? stoneJa)" }
    emitLog(megaLine)
    pendingMegaStone[side] = nil
    pendingMegaSpecies[side] = nil
}

// メガ完了の文を取りこぼした場合の保険: 反応の文は拾えたのに完了の文だけ
// 落ちることがある (実例: 2026-11-20 vs Benn 戦のガブリアス)。
// 反応した時点でメガシンカ自体は確定しているため、その種族が次に技を
// 使う直前 (またはターン境界) に完了を補う
func synthesizeMegaIfPending(side: String, speciesEn: String) {
    guard pendingMegaSpecies[side] == speciesEn else { return }
    guard (monStates["\(side):\(speciesEn)"]?.megaSpecies ?? "").isEmpty else { return }
    var cands = speciesDict.filter { $0.en.hasPrefix(speciesEn + "-Mega") }
    if cands.count > 1, let stoneJa = pendingMegaStone[side], let last = stoneJa.last {
        let filtered = cands.filter { $0.en.hasSuffix("-Mega-\(last)") }
        if filtered.count == 1 { cands = filtered }
    }
    guard cands.count == 1, let me = cands.first else { return }
    completeMega(side: side, baseEn: speciesEn, megaEn: me.en)
}

// 繰り出しの記録 (天候・フィールド特性の帰属判定に使う)
func recordSwitchIn(side: String, slot: String, speciesEn: String) {
    lastSwitchIn["\(side):\(speciesEn)"] = (slot, Date())
    fieldSeen[side, default: []].insert(speciesEn)
    attributeFieldAbilities()
    // いかくの遡及帰属: プレート確定がメッセージより遅れ、攻撃 -1 の適用時に
    // 繰り出しが未記録だった場合は、記録したこの時点で特性行を出す
    // (実例: 2026-11-20 vs BigGuyMan 戦、ズルズキンの いかく が付かなかった)
    let key = "\(side):\(speciesEn)"
    if let sw = lastSwitchIn[key], intimidateDone[key] != sw.at,
       let pool = speciesAbilityMap[speciesEn], pool.contains("Intimidate") {
        let other = side == "p1" ? "p2" : "p1"
        let now = Date()
        let hasDrop = recentAtkDrops.contains { $0.key.hasPrefix("\(other):") && $0.value.seq == actionSeq && now.timeIntervalSince($0.value.at) < 12 }
        if hasDrop {
            intimidateDone[key] = sw.at
            emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: "Intimidate")
            if side == "p2" { revealedAbilities[speciesEn] = abilityJa2En.first { $0.value == "Intimidate" }?.key ?? "Intimidate" }
        }
    }
    // この種族宛てに保留していたランク変化行を、交代行の後に出す
    flushHeldBoosts(forKey: key, slot: slot)
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
func clearTerrain() {
    if logFieldTerrain.isEmpty { return }
    let old = logFieldTerrain
    logFieldTerrain = ""
    emitLog("|-fieldend|move: \(old) Terrain")
}

// 技そのものが天候・フィールドを張る場合
func applyMoveField(_ mvJa: String) {
    switch mvJa {
    case "あめごい": setWeather("Rain", "Rain Dance")
    case "にほんばれ": setWeather("Sun", "Sunny Day")
    case "すなあらし": setWeather("Sand", "Sandstorm")
    case "ゆきげしき", "さむいギャグ": setWeather("Snow", "Snow")
    case "エレキフィールド": setTerrain("Electric")
    case "グラスフィールド": setTerrain("Grassy")
    case "ミストフィールド": setTerrain("Misty")
    case "サイコフィールド": setTerrain("Psychic")
    default: break
    }
}

// ランク変化の本文パターン (能力変化チップ・特性チップ等、種別を問わず拾う)
// 注意: ゲーム本文の動詞は漢字 (上がった/下がった) が正。以前は平仮名
// (あがった/さがった) だけで照合していたため、漢字で読めた文はすべて
// 素通りして |-message| に落ち、ランク変化が一切ダメ計に反映されなかった
// (実例: 2026-11-20 vs Mark 戦の いかく/ちいさくなる/たくわえる 全件)。
// 能力名はフリガナ+漢字の二重表記 (こうげき攻撃 等) で読めることがある。
func checkBoostText(text: String, side: String, speciesEn: String, slot: String) {
    if text.contains("あがらない") || text.contains("さがらない") || text.contains("上がらない") || text.contains("下がらない") { return }
    let up = text.contains("あがった") || text.contains("上がった")
    let down = text.contains("さがった") || text.contains("下がった")
    guard up || down else { return }
    let key = "\(side):\(speciesEn)"
    if monStates[key] == nil { monStates[key] = MonState() }
    // ゲーム内表記は漢字 (攻撃/防御/特攻/特防/素早さ) が正。ひらがな表記も併記する
    // 「防が下がった」のように 2 文字目が落ちる OCR 崩れも拾う
    // (「攻が」「防が」は「攻撃が」「防御が」の部分文字列にはならないため誤爆しない)
    let stats: [(String, String)] = [("こうげき", "atk"), ("攻撃", "atk"), ("攻が", "atk"), ("ぼうぎょ", "def"), ("防御", "def"), ("防が", "def"), ("とくこう", "spa"), ("特攻", "spa"), ("とくぼう", "spd"), ("特防", "spd"), ("すばやさ", "spe"), ("素早さ", "spe"), ("めいちゅう", "acc"), ("命中率", "acc"), ("かいひ", "eva"), ("回避率", "eva")]
    let mag = text.contains("ぐーんと") ? 2 : 1
    if text.contains("すべての") {
        for (_, code) in stats.prefix(5) { applyBoost(key: key, slot: slot, speciesEn: speciesEn, stat: code, delta: up ? mag : -mag) }
        return
    }
    // 文中に現れる能力はすべて適用する (たくわえる の 防御+特防 のように
    // 1 文で 2 つ上がる技があるため、最初の 1 つで打ち切らない)。
    // フリガナ+漢字の二重表記は同一コードとして 1 回だけ数える
    var applied = Set<String>()
    for (ja, code) in stats where !applied.contains(code) {
        // 「攻が」「防が」の 1 字落ちフォールバックは「特攻が」「特防が」の
        // 部分文字列でもあるため、特攻/特防の文では使わない
        // (実例: 2026-11-20、サイコキネシスの特防低下に防御低下まで付いた)
        if ja == "攻が" && text.contains("特攻が") { continue }
        if ja == "防が" && text.contains("特防が") { continue }
        guard text.contains(ja) else { continue }
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
        monStates[toKey]?.boosts[stat] = target
        let delta = target - cur
        if delta > 0 { emitLog("|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)") }
        else { emitLog("|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)") }
    }
}

func applyBoost(key: String, slot: String, speciesEn: String, stat: String, delta: Int) {
    // 同じ文の OCR ゆれ違いの再読で二重に適用しない: 同じ行動・同じターン・
    // 4 秒以内の同一変化 (枠・能力・増減) は再読とみなして捨てる
    // (実例: アーマーキャノンの自己低下といかくの攻撃低下が 2 重に出た)。
    // 別の技による正当な再変化は |move| を挟むため行動番号が変わり、適用される
    let bk = "\(slot)|\(stat)|\(delta)"
    if let lb = lastBoostApply[bk], lb.seq == actionSeq && lb.turn == currentTurn && Date().timeIntervalSince(lb.at) < 4 { return }
    lastBoostApply[bk] = (seq: actionSeq, turn: currentTurn, at: Date())
    let cur = monStates[key]?.boosts[stat] ?? 0
    let nv = max(-6, min(6, cur + delta))
    if nv == cur { return }
    monStates[key]?.boosts[stat] = nv
    if stat == "atk" && delta < 0 { recentAtkDrops[key] = (Date(), actionSeq) }
    let line = delta > 0 ? "|-boost|\(slot): \(speciesEn)|\(stat)|\(delta)" : "|-unboost|\(slot): \(speciesEn)|\(stat)|\(-delta)"
    // 交代行がまだ出ていない種族のランク変化行は、交代行の後に出す
    // (実例: 2026-11-20 vs Vanille 戦、場に出る前の サイコシード 発動行が
    //  繰り出し行より先に出た)。状態への適用は即時に行い、行だけ保留する
    if !emittedSwitchKeys.contains(key) && (monStates[key]?.hpPercent ?? 100) > 0 {
        // 行は出さず変化だけ保留する。枠は交代確定の時点で付け直す
        // (読んだ時点では場にいないため slotFor が既定の a 枠を返し、
        //  実際の枠と食い違う。実例: 2026-11-20、オオニューラの
        //  サイコシード発動行が p1a で出た (実際は p1b))
        heldBoostLines[key, default: []].append((stat, delta, Date()))
    } else {
        emitLog(line)
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
    for h in arr { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta)) }
}

func flushHeldBoostsTimeout() {
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
        for h in ready { emitLog(boostLine(slot: slot, speciesEn: speciesEn, stat: h.stat, delta: h.delta)) }
    }
}

// 天候・フィールドの開始/終了の本文パターン
@discardableResult
func checkFieldText(text: String) -> Bool {
    // フィールドの終了文 (実機の文面は漢字混じり。OCR 崩れにも耐えるよう緩く照合する)
    if (text.contains("不思議") || text.contains("フィールド")) && (text.contains("なくな") || text.contains("消え") || text.contains("きえ") || text.contains("きれ")) { clearTerrain(); return true }
    if text.contains("霧が") && text.contains("はれた") { clearTerrain(); return true }
    if text.contains("電気が") && text.contains("消えた") { clearTerrain(); return true }
    if text.contains("草が") && (text.contains("なくなった") || text.contains("消え") || text.contains("きえ")) { clearTerrain(); return true }
    // トリックルーム (地形・天候とは別枠のフィールド効果)
    if text.contains("時空") && (text.contains("ゆがめ") || text.contains("歪め")) {
        if !logTrickRoom { logTrickRoom = true; emitLog("|-fieldstart|move: Trick Room") }
        return true
    }
    if logTrickRoom && (text.contains("ゆがみ") || text.contains("時空")) && (text.contains("戻った") || text.contains("もどった")) {
        logTrickRoom = false
        emitLog("|-fieldend|move: Trick Room")
        return true
    }
    // フィールドの開始文 (特性サージ系は種族名・特性名が出ず、この文だけが出る。
    // 「足下が不思議な感じになった」はサイコフィールド専用の文。
    // 「感じになった」はこの文にしか出ないため、足下・不思議が OCR 崩れ
    // しても拾う (実例: 2026-11-20「下か不態議な感じになった！」の漏れ))
    if text.contains("感じ") && text.contains("なった") { setTerrain("Psychic"); return true }
    if text.contains("足下が") && text.contains("不思議な感じに") { setTerrain("Psychic"); return true }
    if (text.contains("足下に") || text.contains("足下が")) && text.contains("電気が") && text.contains("かけめぐ") { setTerrain("Electric"); return true }
    if (text.contains("足下に") || text.contains("足下が") || text.contains("足元")) && text.contains("草が") && (text.contains("生い茂") || text.contains("おいしげ") || text.contains("しげった") || text.contains("茂った")) { setTerrain("Grassy"); return true }
    if text.contains("足下が") && text.contains("霧に") && text.contains("包まれ") { setTerrain("Misty"); return true }
    // 天候の終了文
    if (text.contains("日差し") || text.contains("ひざし")) && text.contains("弱く") { clearWeather(); return true }
    if text.contains("雨") && (text.contains("やんだ") || text.contains("止んだ") || text.contains("上がった")) { clearWeather(); return true }
    if (text.contains("あめ") && (text.contains("やんだ") || text.contains("おさまった"))) { clearWeather(); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("おさま") || text.contains("弱ま")) { clearWeather(); return true }
    if text.contains("雪") && (text.contains("やんだ") || text.contains("止んだ")) { clearWeather(); return true }
    if text.contains("ゆき") && text.contains("やんだ") { clearWeather(); return true }
    // 天候の開始文 (実機の文面: 「日差しが強くなった」「雨が降り始めた」等。
    // 従来は ひざし/あめ 等の平仮名だけで照合しており、漢字表記に一致せず
    // ひでり等の天候を拾えていなかった)
    if (text.contains("日差し") || text.contains("ひざし")) && text.contains("強く") { setWeather("Sun", "Sunny Day"); return true }
    if text.contains("雨") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Rain", "Rain Dance"); return true }
    if text.contains("あめ") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Rain", "Rain Dance"); return true }
    if (text.contains("砂あらし") || text.contains("すなあらし")) && (text.contains("吹き始") || text.contains("吹き荒") || text.contains("ふきあれ")) { setWeather("Sand", "Sandstorm"); return true }
    if text.contains("雪") && (text.contains("降り始") || text.contains("降ってき")) { setWeather("Snow", "Snow"); return true }
    if text.contains("ゆき") && (text.contains("ふりはじめ") || text.contains("ふってき")) { setWeather("Snow", "Snow"); return true }
    if text.contains("フィールド") && text.contains("ひろが") {
        for (ja, en) in [("エレキ", "Electric"), ("グラス", "Grassy"), ("ミスト", "Misty"), ("サイコ", "Psychic")] where text.contains(ja) {
            setTerrain(en)
            return true
        }
    }
    return false
}

// 画面上部のフィールド状態バー (ログ画面ヘッダ・様子を見る等) から現在値を取得する。
// OCR で複数ボックスに割れても拾えるよう、帯のテキストを連結してから照合する。
func scanFieldHeader(_ boxes: [OcrBox]) {
    let joined = boxes.filter { $0.cy < 0.09 }.map { $0.text }.joined(separator: " ")
    if joined.isEmpty { return }
    for (ja, en) in [("グラスフィールド", "Grassy"), ("エレキフィールド", "Electric"), ("サイコフィールド", "Psychic"), ("ミストフィールド", "Misty")] where joined.contains(ja) {
        setTerrain(en)
    }
    if joined.contains("にほんばれ") { setWeather("Sun", "Sunny Day") }
    else if joined.contains("すなあらし") { setWeather("Sand", "Sandstorm") }
    else if joined.contains("あめ") && joined.contains("状態") { setWeather("Rain", "Rain Dance") }
    else if joined.contains("ゆき") && joined.contains("状態") { setWeather("Snow", "Snow") }
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
        print("ログ画面診断: ターン=\(turnFound.map { "\($0)" } ?? "不明 (\(tn) として処理)") チップ=\(chipHits.count)件")
    }
    if !logStarted { startBattleLog() }
    scanFieldHeader(boxes)
    if tn > currentTurn {
        currentTurn = tn
        emitLog("|turn|\(tn)")
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
    var covered: [Range<String.Index>] = []
    var found: [(Range<String.Index>, SpeciesEntry)] = []
    for e in speciesDict.filter({ !$0.ja.isEmpty }).sorted(by: { $0.ja.count > $1.ja.count }) {
        let nj = normalize(e.ja)
        var start = t.startIndex
        while start < t.endIndex, let r = t.range(of: nj, range: start..<t.endIndex) {
            if !covered.contains(where: { $0.lowerBound < r.upperBound && r.lowerBound < $0.upperBound }) {
                found.append((r, e))
                covered.append(r)
            }
            start = r.upperBound
        }
    }
    return found.sorted { $0.0.lowerBound < $1.0.lowerBound }.map { $0.1 }
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
func isBoostShapedText(_ text: String) -> Bool {
    let t = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    guard t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった") else { return false }
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
    if t.contains("たおれた") || t.contains("効果は") || t.contains("回復") { return false }
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
    guard let bk = bestKey, !tie else { return nil }
    return moveNameOrig[bk]
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
        return true
    }
    if t.contains("あきらめた") {
        if winLogged { return true }   // 同じ勝敗文の再読では出さない
        let oppGaveUp = t.contains("相手") || t.contains("あいて")
        forfeitName = oppGaveUp ? (trainerOpp.isEmpty ? "Opponent" : trainerOpp) : (trainerMine.isEmpty ? "You" : trainerMine)
        emitPendingFaints()
        emitLog("|win|\(oppGaveUp ? (trainerMine.isEmpty ? "p1" : trainerMine) : (trainerOpp.isEmpty ? "p2" : trainerOpp))")
        winLogged = true
        return true
    }
    // 急所: 「(相手の) Xの 急所に 当たった！」
    // 「急所」は OCR で「還所」「意所」等に崩れるため、「所に当たった」で
    // 判定する (実例: 2026-11-20 の対戦で 2 件とも日本語のまま漏れた)。
    // 対象は文中の種族名を優先する (範囲技では最後に被弾した枠と急所の
    // 対象が食い違うことがあるため)。種族が取れない場合だけ従来通り
    // 直近にダメージを受けた (受けつつある) 枠に付ける
    if (t.contains("急所に") || t.contains("所に") || t.hasSuffix("に当たった！") || t.hasSuffix("に当たった!") || t.hasSuffix("にたった！") || t.hasSuffix("にたった!")) && (t.contains("当たった") || t.contains("たった")) {
        var target = ""
        if let csp = findSpeciesJa(in: t) {
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
            emitLog("|-crit|\(target)")
        }
        return true
    }
    // 技の失敗: 「しかし うまく決まらなかった！」
    if t.contains("うまく決まらなかった") {
        emitLog("|-fail|")
        return true
    }
    // メガシンカの反応 (ストーンと相手トレーナー名がここで判明する)。
    // ストーンは「<種族>の<ストーン>と」の構造から切り出して完全一致で照合する
    // (部分一致の最長マッチだとキーアイテム名などと競合しうるため)
    if t.contains("反応した") && t.contains("リングが") {
        if let sp = findSpeciesJa(in: t) {
            let side = (t.contains("相手の") || t.contains("あいての")) ? "p2" : "p1"
            if monStates["\(side):\(sp.en)"] == nil { monStates["\(side):\(sp.en)"] = MonState() }
            // ストーンの切り出しは生テキストで行う (正規化すると助詞の「と」と
            // 「〜ナイト」の「ト」が区別できなくなるため)
            if let r = t.range(of: sp.ja + "の") {
                let stoneCand = String(t[r.upperBound...].prefix(while: { $0 != "と" }))
                if let itJa = itemDict[normalize(stoneCand)] {
                    emitItemOnce(slot: slotFor(side: side, speciesEn: sp.en), side: side, speciesEn: sp.en, itemJa: itJa)
                    if side == "p2" { revealedItems[sp.en] = itJa }
                    pendingMegaStone[side] = itJa
                    pendingMegaSpecies[side] = sp.en
                }
            }
        }
        return true
    }
    // メガシンカの完了: 状態をメガ種族に切り替える (キーはベース種族のまま。
    // プレートや技メッセージの名前表記はメガ後もベース名のため)
    if t.contains("メガシンカした") {
        let megaEntry = speciesDict.filter { $0.ja.hasPrefix("メガ") && nt.contains(normalize($0.ja)) }
            .max(by: { $0.ja.count < $1.ja.count })
        if let me = megaEntry {
            let side = (t.contains("相手の") || t.contains("あいての")) ? "p2" : "p1"
            var baseEn = me.en
            if let r = baseEn.range(of: "-Mega") { baseEn = String(baseEn[..<r.lowerBound]) }
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
        for (i, e) in found.prefix(2).enumerated() {
            let plateName = i == 0 ? "mineA" : "mineB"
            if monStates["p1:\(e.en)"] == nil { monStates["p1:\(e.en)"] = MonState() }
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
    // あくびで眠気を誘った文 (対象は次のターン終了時に眠る。眠気そのものは
    // 状態として持たないため、漏らさず消費だけする)
    if (t.contains("眠気") || t.contains("ねむけ")) && (t.contains("誘った") || t.contains("誘つた") || t.contains("さそった") || t.contains("さそつた")) { return true }
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
    // 効果の確認文・交代の指示文 (出来事そのものは別の行で記録済みのため、
    // 本文だけを |-message| に残さないよう消費する)
    if t.contains("手助けする") || t.contains("ワイドガード") || t.contains("守られた") || t.contains("身を守った") || t.contains("体勢に入った")
        || t.contains("戻れ") || t.contains("引っこめた") || t.contains("引っ込めた")
        || t.contains("引つこめた") || t.contains("引つ込めた")
        || t.contains("引っごめた") || t.contains("引つごめた")
        || t.contains("場所を入れ替えた") {
        // 引っ込めた は OCR で「引つこめた」(っ->つ、込->こ) と崩れる
        // (実例: 2026-11-20 vs Ony 戦「Onyはコリランダーを引つこめた！」)
        // 場所を入れ替えた はアリーバスイッチの結果文 (技そのものは |move| で記録済み)
        return true
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
            setTerrain(en)
            break
        }
        return true
    }
    // 回復の告知文の断片 (種族名が解決できない場合): 回復そのものは
    // プレート側で |-heal| を出すため、文は消費するだけにする
    // (実例: 2026-11-20「シャンデラのかいふく袱力か回復した！」等の漏れ)
    if sp == nil && t.contains("回復した") { return true }
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
    // 寄せないと技の判明などが基本フォルム側に記録されてしまう)
    sp = fieldAnchoredSpecies(sp)
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
    let slot = slotFor(side: side, speciesEn: sp.en)
    let key = "\(side):\(sp.en)"
    if monStates[key] == nil { monStates[key] = MonState() }
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
    if t.contains("効果は") {
        // OCR 崩れ (バツグン -> バッグン) に耐えるよう、小さい ッ/っ を寄せた形でも判定する
        let tk = t.replacingOccurrences(of: "ッ", with: "ツ").replacingOccurrences(of: "っ", with: "つ")
        let kind = tk.contains("いまひとつ") ? "resisted" : tk.contains("バツグン") ? "supereffective" : tk.contains("ないようだ") ? "immune" : ""
        if !kind.isEmpty {
            let ekey = "\(slot)|\(kind)"
            if let at = lastEffectAt[ekey], Date().timeIntervalSince(at) < 3 { return true }
            lastEffectAt[ekey] = Date()
            emitLog("|-\(kind)|\(slot): \(sp.en)")
            return true
        }
    }
    // フィールドに守られた (優先度技の無効化): フィールド状態の裏付けにもなる
    if t.contains("守られている") {
        for (ja, en) in [("サイコフィールド", "Psychic"), ("エレキフィールド", "Electric"), ("グラスフィールド", "Grassy"), ("ミストフィールド", "Misty")] where t.contains(ja) {
            setTerrain(en)
            emitLog("|-activate|\(slot): \(sp.en)|move: \(en) Terrain")
            return true
        }
        return true
    }
    // ミス: 「<対象>には 当たらなかった！」(使用者は直近の |move| の枠)
    if t.contains("当たらなかった") {
        if !lastMoveLabel.isEmpty && Date().timeIntervalSince(lastMoveMsgAt) < 8 {
            emitLog("|-miss|\(lastMoveLabel)|\(slot): \(sp.en)")
        }
        return true
    }
    // 技の使用: 「(相手の) <種族>の <技>！」— <技> は種族名の直後から文末までと完全一致
    if t.hasSuffix("！") || t.hasSuffix("!") {
        var cand: String? = nil
        if let r = nt.range(of: normalize(sp.ja + "の")) {
            cand = String(nt[r.upperBound...])
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
            if onField, let hit = moveNameOrig.keys.filter({ nt.contains($0) }).max(by: { $0.count < $1.count }) {
                mvJaFound = moveNameOrig[hit]
            }
        }
        if let mvJa = mvJaFound {
                let moveEn = moveJa2En[mvJa] ?? mvJa
                // 同じ文が OCR ゆれ違いで二重に処理されても |move| は 1 回だけ。
                // さらにターン内では同じ枠の同じ技は 1 回だけにする (古い文の
                // 再処理で同じターンの技が繰り返し出た実例: 2026-11-20、
                // ひんし後のグレンアルマの アーマーキャノン 等の再演ブロック)
                let sig = slot + "|" + moveEn + "|t" + String(currentTurn)
                if lastMoveSigAt[sig] != nil { return true }
                if let at = lastMoveSigAt[slot + "|" + moveEn], Date().timeIntervalSince(at) < 6 { return true }
                lastMoveSigAt[sig] = Date()
                lastMoveSigAt[slot + "|" + moveEn] = Date()
                lastMoveLabel = "\(slot): \(sp.en)"
                lastMoveMsgAt = Date()
                lastMoveName = moveEn
                synthesizeMegaIfPending(side: side, speciesEn: sp.en)
                emitLog("|move|\(slot): \(sp.en)|\(moveEn)")
                lastMoveSeq = actionSeq
                applyMoveField(mvJa)
                if side == "p2" && !(revealedMoves[sp.en]?.contains(mvJa) ?? false) {
                    revealedMoves[sp.en, default: []].append(mvJa)
                }
                return true
        }
    }
    // まもる成功: 「<対象>は 攻撃から 身を守った！」(守つた の OCR 崩れも拾う)
    if t.contains("身を守った") || t.contains("身を守つた") || t.contains("守りの入った")
        || (t.contains("体勢") && t.contains("守り") && t.contains("入った")) {
        let pk = slot + "|protect"
        if let at = lastSingleActAt[pk], Date().timeIntervalSince(at) < 6 { return true }
        lastSingleActAt[pk] = Date()
        emitLog("|-activate|\(slot): \(sp.en)|move: Protect")
        return true
    }
    // 状態異常で動けない (行動失敗。実例: 2026-11-20 の対戦で
    // 「イエツサンは 体がしびれて 動けない！」が日本語のまま漏れた)
    let cantCode = (t.contains("しびれて") && t.contains("動けない")) ? "par"
        : (t.contains("凍って") && t.contains("動けない")) ? "frz"
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
            if side == "p2" { revealedAbilities[sp.en] = orig }
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
        if side == "p2" { revealedItems[sp.en] = "きあいのタスキ" }
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
            if side == "p2" { revealedItems[sp.en] = "いのちのたま" }
        }
        return true
    }
    // タイプ軽減きのみの発動 (「<対象>へのダメージを オッカのみが弱めた！」。
    // 実例: 2026-11-20、クレッフィのオッカのみ文が日本語のまま漏れた)
    if t.contains("弱めた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        if side == "p2" { revealedItems[sp.en] = itJa }
        noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        return true
    }
    // だっしゅつボタンで戻っていく (交代そのものはプレート側で記録する)
    if t.contains("だっしゅつボタン") || t.contains("しゅつボタン") || (t.contains("ボタン") && t.contains("戻って")) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "だっしゅつボタン")
        if side == "p2" { revealedItems[sp.en] = "だっしゅつボタン" }
        return true
    }
    // せんせいのツメの発動 (実例: 2026-11-20 の対戦で「キュウコンは
    // せんせいのツメで 行動が はやくなった！」が日本語のまま漏れた)
    if t.contains("せんせいのツメ") || t.contains("せんせいのつめ") {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: "せんせいのツメ")
        if side == "p2" { revealedItems[sp.en] = "せんせいのツメ" }
        return true
    }
    // 道具を手に入れた (トリック等で相手の道具が移った場合の判明。
    // 実例: 2026-11-20 vs Gmoneys 戦「イエッサンはこだわりスカーフを
    // 手に入れた！」が日本語のまま漏れ、道具も判明しなかった)
    if t.contains("手に入れた"), let itJa = findInDict(in: t, itemDict) {
        emitItemOnce(slot: slot, side: side, speciesEn: sp.en, itemJa: itJa)
        if side == "p2" { revealedItems[sp.en] = itJa }
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
        if side == "p2" { revealedItems[sp.en] = itJa }
        // 消費・喪失が伴う文脈なら かるわざ の判定へ (きのみを食べた /
        // 軽減きのみの発動 / 持ち物がなくなった)
        if t.contains("なくなった") || ((itemJa2En[itJa] ?? "").hasSuffix("Berry") && (t.contains("食べ") || t.contains("発動"))) {
            noteItemLost(slot: slot, side: side, speciesEn: sp.en)
        }
    }
    // 回復の告知文: 回復そのものはプレート側で |-heal| を出すため消費のみ
    // (グラッシーフィールド等の回復文が OCR 崩れで漏れた実例: 2026-11-20
    // 「オオニューラのかいふく琳力が回復した！」。持ち物の判明はこの前段の
    // 持ち物分岐が先に処理する)
    if t.contains("回復した") { return true }
    // ひんし (プレート側で既に 0% になっている場合も文は消費する。
    // 消費しないと |-message| に化けて同じ文が残り続ける)
    if t.contains("たおれた") {
        if (monStates[key]?.hpPercent ?? 0) > 0 {
            monStates[key]?.hpPercent = 0
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
    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する
    // 動詞は漢字表記 (上がった/下がった) も対象にする
    if t.contains("あがった") || t.contains("さがった") || t.contains("上がった") || t.contains("下がった") {
        // 主語を場のフォルムに寄せる (イエッサン -> イエッサンF 等)。寄せないと
        // 枠が特定できず、二重適用防止のキーが他方と衝突して変化が丸ごと落ちる
        // (実例: 2026-11-20 vs BigGuyMan 戦、いかくのイエッサン分が消えた)
        let subjects = findAllSpeciesJa(in: t).map { fieldAnchoredSpecies($0) }
        // いかくの帰属はランク変化の行より先に [特性] 行を出すため、適用前に行う
        if (t.contains("さがった") || t.contains("下がった")) && (t.contains("攻撃") || t.contains("こうげき")) && !t.contains("ぐーんと") {
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
                let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en || teamEntries[e.en] != nil
                let sSide = inOpp && !inMine ? "p2" : "p1"
                checkBoostText(text: t, side: sSide, speciesEn: e.en, slot: slotFor(side: sSide, speciesEn: e.en))
            }
        } else {
            checkBoostText(text: t, side: side, speciesEn: sp.en, slot: slot)
        }
        // 適用した変化の行が保留中でも、この文は消費済みとして扱う
        if battleLog.count > before || heldBoostLines.values.contains(where: { !$0.isEmpty }) { return true }
    }
    return battleLog.count > before
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
    let msgBoxes = boxes.filter { b in
        guard platesVisible else { return true }
        if b.cy > 0.90 && b.cx < 0.30 { return false }   // コマンド時のプレート文字
        if b.cy > 0.82 && b.cx < 0.30 {                   // 単体プレートの残り文字
            let digits = asciiDigits(b.text).replacingOccurrences(of: " ", with: "")
            if digits.range(of: #"^\d+/\d+$"#, options: .regularExpression) != nil { return false }
            if activeJa.contains(b.text) { return false }
        }
        return true
    }.sorted { ($0.cy, $0.x0) < ($1.cy, $1.x0) }
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
    } else if isBoostShapedText(text) {
        // ランク変化の文は構造化された経路でのみ扱う。再読で適用が抑止されて
        // 翻訳関数が false を返した場合に、生文がそのまま漏れるのを防ぐ
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
var pvSpeciesTypes: [String: [String]] = [:]
var pvFeatures: [String: (hash: [UInt8], hue: [Double], aspect: Double, density: Double)] = [:]
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
    }
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
    }
    for (name, v) in iobj {
        if let d = v as? [String: Any] { pvTypeIcons[name] = (pvNumArray(d["rgb"]), pvNumArray(d["glyph"])) }
    }
    pvDataLoaded = !pvSpeciesTypes.isEmpty && !pvFeatures.isEmpty && !pvTypeIcons.isEmpty
}

// フル解像度のピクセルバッファ (行0 = 画像の上端、RGBA)
func makeFullBuffer(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = image.width, h = image.height
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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
func pvDetectPanels(_ buf: (data: [UInt8], w: Int, h: Int)) -> [(x: Int, y: Int, w: Int, h: Int)] {
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
    for y in 0..<H {
        var cnt = 0
        var x = xs
        while x < xe {
            if isMaroon(x, y) { cnt += 1 }
            x += 2
        }
        if cnt > (xe - xs) / 20 {
            if start == nil { start = y }
            last = y
        } else if let s = start, y - last > 4 {
            groups.append((s, last)); start = nil
        }
    }
    if let s = start { groups.append((s, last)) }
    let raw = groups.filter { $0.1 - $0.0 >= Int(0.05 * Double(H)) }
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
            let mw = mx1 - mx0 + 1
            // 実測値が想定範囲内のときだけ採用する
            if mw >= Int(0.10 * Double(W)) && mw <= Int(0.22 * Double(W))
                && mx0 >= Int(0.55 * Double(W)) && mx0 <= Int(0.90 * Double(W)) {
                return raw.map { (x: mx0, y: $0.0, w: mw, h: $0.1 - $0.0 + 1) }
            }
        }
        let pw = Int(0.154 * Double(W)), px = Int(0.811 * Double(W))
        return raw.map { (x: px, y: $0.0, w: pw, h: $0.1 - $0.0 + 1) }
    }
    let pw = Int(0.154 * Double(W)), px = Int(0.811 * Double(W))
    return [0.180, 0.279, 0.378, 0.473, 0.576, 0.670].map {
        (x: px, y: Int($0 * Double(H)), w: pw, h: Int(0.094 * Double(H)))
    }
}

// タイプアイコン 1 セルを分類。(種族タイプ名, アイコンが存在したか, 診断文字列)
func pvClassifyIcon(_ buf: (data: [UInt8], w: Int, h: Int), _ x0in: Int, _ y0in: Int, _ s: Int) -> (String?, Bool, String, Double) {
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
    if std <= 30 { return (nil, false, String(format: "std=%.1f (アイコンなし)", std), 999) }
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
                0.05 + cd * 0.3)
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
    return (bs < 0.42 ? best : nil, true, diag, bs)
}

// アイコン 1 枠分: 基準位置の近傍 (3x3) を探索し、最もスコアの良い窓を
// 採用する。パネルの縦横比はウィンドウ形状で変わるため、固定オフセット
// だけではアイコンから外れることがある (実機で確認)。
// ただし「有無」は中心窓だけで判定する: 実機フレームでは有るアイコンは
// 中心でも std 60+、無い枠は中心 std 13 以下と大きく離れている。一方、
// 探索窓は隣のアイコンや 3D モデルの端を拾って「無い枠にタイプを
// 発明」しうる (単タイプが複合と誤読され、候補が 1 種に確定して
// しまう事故の経路)。中心で無ければ探索しない。
func pvClassifyIconSearch(_ buf: (data: [UInt8], w: Int, h: Int), _ x0: Int, _ y0: Int, _ s: Int) -> (String?, Bool, String) {
    let center = pvClassifyIcon(buf, x0, y0, s)
    if !center.1 { return (center.0, center.1, center.2) }
    var best: (String?, Bool, String, Double)? = nil
    for dy in [-s / 5, 0, s / 5] {
        for dx in [-s / 6, 0, s / 6] {
            let r = pvClassifyIcon(buf, x0 + dx, y0 + dy, s)
            if best == nil || r.3 < best!.3 { best = r }
        }
    }
    return (best!.0, best!.1, best!.2)
}

// パネル左側の 3D モデルを背景色との差分で切り出し、特徴量を取る
func pvModelFeatures(_ buf: (data: [UInt8], w: Int, h: Int), _ panel: (x: Int, y: Int, w: Int, h: Int))
    -> (hash: [UInt8], hue: [Double], aspect: Double, density: Double)? {
    let cw = Int(0.52 * Double(panel.w)), ch = panel.h
    if cw <= 0 || ch <= 0 { return nil }
    let bgx = max(0, min(panel.x + Int(0.55 * Double(panel.w)), buf.w - 1))
    let bgy = max(0, min(panel.y + 4, buf.h - 1))
    let bi = (bgy * buf.w + bgx) * 4
    let bg = (Int(buf.data[bi]), Int(buf.data[bi + 1]), Int(buf.data[bi + 2]))
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
    let small = pvResizeGray(gray, sw, sh, 17, 16)
    var hash = [UInt8](repeating: 0, count: 32)
    for yy in 0..<16 {
        for xx in 0..<16 {
            if small[yy * 17 + xx + 1] > small[yy * 17 + xx] {
                let bit = yy * 16 + xx
                hash[bit / 8] |= UInt8(0x80 >> (bit % 8))
            }
        }
    }
    return (hash, hue, Double(sw) / Double(sh), Double(areas[bi2]) / Double(sw * sh))
}

func pvScore(_ f: (hash: [UInt8], hue: [Double], aspect: Double, density: Double),
             _ ref: (hash: [UInt8], hue: [Double], aspect: Double, density: Double)) -> Double {
    var diff = 0
    for i in 0..<min(f.hash.count, ref.hash.count) { diff += (f.hash[i] ^ ref.hash[i]).nonzeroBitCount }
    let hd = Double(diff) / 256.0
    let hc = pvPearson(f.hue, ref.hue)
    return hd - 0.35 * hc + 0.15 * abs(log(f.aspect / ref.aspect)) + 0.25 * abs(f.density - ref.density)
}

// 選出画面 1 枚から相手チームを推定する。何も分からなければ nil
func identifyPreview(image: CGImage) -> (team: [String?], notes: [String])? {
    let buf = makeFullBuffer(image)
    let panels = pvDetectPanels(buf)
    var anyInfo = false
    // 枠ごとの候補リスト (種族, 照合スコア)。スコアは小さいほど良い
    var slotRanked: [[(String, Double)]] = []
    var slotDecisive: [Bool] = []
    var slotPoolCount: [Int] = []
    var slotMargin: [Double] = []
    for panel in panels {
        var types: [String] = []
        var unknownPresent = false
        // アイコン位置はパネル相対 (2026-11-20 の実機フレームで再実測:
        // アイコン中心は slot1 x=0.70w, slot2 x=0.89w, y=0.25h、一辺 0.403h。
        // 単タイプは右側の枠に表示される)。左上 = 中心 - 一辺/2 を基準に
        // 近傍探索で微調整する
        let iconS = Int(0.403 * Double(panel.h))
        for slot in 0..<2 {
            let ix = panel.x + Int((slot == 0 ? 0.620 : 0.810) * Double(panel.w))
            let iy = panel.y + Int(0.050 * Double(panel.h))
            let (t, present, _) = pvClassifyIconSearch(buf, ix, iy, iconS)
            if let t { types.append(t) } else if present { unknownPresent = true }
        }
        var pool: [String] = []
        if types.count == 2 {
            pool = pvSpeciesTypes.filter { Set($0.value) == Set(types) }.map { $0.key }
        } else if types.count == 1 {
            if unknownPresent {
                pool = pvSpeciesTypes.filter { $0.value.contains(types[0]) }.map { $0.key }
            } else {
                pool = pvSpeciesTypes.filter { $0.value == types }.map { $0.key }
            }
        }
        if pool.isEmpty {
            slotRanked.append([]); slotDecisive.append(false); slotPoolCount.append(0); slotMargin.append(0)
            continue
        }
        anyInfo = true
        slotPoolCount.append(pool.count)
        if pool.count == 1 {
            slotRanked.append([(pool[0], 0)]); slotDecisive.append(true); slotMargin.append(9)
            continue
        }
        guard let f = pvModelFeatures(buf, panel) else {
            slotRanked.append([]); slotDecisive.append(false); slotMargin.append(0)
            continue
        }
        let ranked = pool.compactMap { n -> (String, Double)? in
            pvFeatures[n].map { (n, pvScore(f, $0)) }
        }.sorted { $0.1 < $1.1 }
        if ranked.isEmpty {
            slotRanked.append([]); slotDecisive.append(false); slotMargin.append(0)
            continue
        }
        slotRanked.append(ranked); slotDecisive.append(false)
        slotMargin.append(ranked.count > 1 ? ranked[1].1 - ranked[0].1 : 1.0)
    }
    // 同じ種族が 2 枠に出ることはないため、重複しないよう割り当てる。
    // 確定枠 → マージンの大きい順に、各枠の最上位の「未使用」候補を採る
    // (従来は枠ごとに独立に 1 位を採っており、同種族が重複登録されていた)
    var used = Set<String>()
    var team: [String?] = Array(repeating: nil, count: panels.count)
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
        let rank = ranked.firstIndex(where: { $0.0 == pickCand.0 }) ?? 0
        if slotDecisive[i] {
            noteByIdx[i] = "選出\(i + 1): \(pvJa(pickCand.0)) (タイプで確定)"
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
    return anyInfo ? (team, notes) : nil
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
    return hits
}

var inBattle = false
var emptyBattleFrames = 0   // プレートが見えないフレームの連続数 (対戦終了の判定用)

// 選出画面の検出 (「選出してください」「選出完了」などの文言を探す)
var previewLastFrame = false
var lastPreviewSeenAt = Date.distantPast   // 選出画面を最後に見た時刻 (同定のやり直し判定)
func detectPreview(image: CGImage) -> Bool {
    let boxes = ocrBoxes(image, x0: 0, y0: 0, x1: 1, y1: 1)
    let isP = boxes.contains { $0.text.contains("選出") }
    // 新しい選出画面に入ったら前試合のトレーナー名を消し、今試合分を取り直す
    // (自分の名前は左上、相手は右上。勝敗ログの |win| に使う)
    if isP && !previewLastFrame { trainerMine = ""; trainerOpp = "" }
    previewLastFrame = isP
    if isP {
        let bad = ["バトル", "選出", "ダブル", "カジュアル", "ランク", "マスター", "ください"]
        for b in boxes where b.cy > 0.11 && b.cy < 0.20 {
            let t = b.text.trimmingCharacters(in: .whitespaces)
            if t.isEmpty || t.count > 14 || bad.contains(where: { t.contains($0) }) { continue }
            if t.allSatisfy({ $0.isNumber || ":： ".contains($0) }) { continue }
            if b.cx < 0.32 { trainerMine = t }
            if b.cx > 0.70 { trainerOpp = t }
        }
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

// 新しいリーダーが同期で届いていたら、選出画面のうち (同定が始まる前) に
// 終了コード 42 で抜ける。起動スクリプト側がそのコードを見て再起動する。
// 対戦中は絶対に再起動しない (対戦状態が消えてしまうため)
func maybeRestartForUpdate() {
    if previewHandled { return }
    if Date().timeIntervalSince(lastBuildCheckAt) < 5 { return }
    lastBuildCheckAt = Date()
    guard let disk = diskReaderBuild(), disk != readerBuild else { return }
    print("[sync] 新しいリーダー (\(disk)) が届いたため再起動します")
    fflush(stdout)
    exit(42)
}

func runOnce(image: CGImage) {
    // 選出画面はプレート判定より先に判定する。
    // (選出画面の自軍パネルや「0/4」表示をプレートと誤検出しないため)
    if detectPreview(image: image) {
        previewFrames += 1
        lastPreviewSeenAt = Date()
        maybeRestartForUpdate()
        // 出現アニメーションが落ち着く 2 フレーム目で同定する (1 回だけ)
        if previewFrames >= 2 && !previewHandled {
            previewHandled = true
            let hadState = !oppTeamSeen.isEmpty || lastSlots["oppA"] != nil || lastSlots["oppB"] != nil
            lastSlots["oppA"] = nil
            lastSlots["oppB"] = nil
            if pvDataLoaded, let r = identifyPreview(image: image) {
                // 選出段階で推定した相手チームを state.json に反映する
                oppTeamSeen = r.team.compactMap { $0 }
                oppUnconfirmed = Set(oppTeamSeen)  // 全枠が推定 = 未確認 (実物で差し替え可)
                startBattleLog()
                var obj: [String: Any] = [:]
                obj["mine"] = [Any]()
                obj["opps"] = [Any]()
                obj["field"] = [String: Any]()
                obj["oppReset"] = true
                obj["oppPreview"] = true
                obj["oppTeam"] = r.team.map { $0 as Any? ?? NSNull() }
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys]),
                   let json = String(data: data, encoding: .utf8), json != lastWritten {
                    lastWritten = json
                    try? json.write(to: outURL, atomically: true, encoding: .utf8)
                }

            } else {
                oppTeamSeen = []
                oppUnconfirmed = []
                resetLogState()
                if hadState {
                    let json = "{\"mine\": [], \"opps\": [], \"oppTeam\": [], \"oppReset\": true, \"field\": {}}"
                    if json != lastWritten {
                        lastWritten = json
                        try? json.write(to: outURL, atomically: true, encoding: .utf8)
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
            if emptyBattleFrames > 30 { inBattle = false; emptyBattleFrames = 0 }
        }
        return
    }
    emptyBattleFrames = 0
    inBattle = true
    processPlates(hits)
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
        currentTurn += 1
        emitLog("|turn|\(currentTurn)")
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

let readerBuild = "20261120_0959"

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
                    let (t, present, diag) = pvClassifyIconSearch(buf, ix, iy, iconS)
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

struct OcrBox { let text: String; let cx, cy, x0, y0, x1, y1: Double } // 座標は左上原点の割合

func ocrBoxes(_ image: CGImage, x0: Double, y0: Double, x1: Double, y1: Double) -> [OcrBox] {
    let req = VNRecognizeTextRequest()
    req.recognitionLevel = .accurate
    req.recognitionLanguages = ["ja-JP", "en-US"]
    req.usesLanguageCorrection = false
    req.regionOfInterest = CGRect(x: x0, y: 1.0 - y1, width: x1 - x0, height: y1 - y0)
    let handler = VNImageRequestHandler(cgImage: image, options: [:])
    try? handler.perform([req])
    return (req.results ?? []).compactMap { obs -> OcrBox? in
        guard let t = obs.topCandidates(1).first?.string else { return nil }
        let b = obs.boundingBox // 左下原点の正規化座標
        return OcrBox(text: t, cx: Double(b.midX), cy: 1.0 - Double(b.midY),
                      x0: Double(b.minX), y0: 1.0 - Double(b.maxY), x1: Double(b.maxX), y1: 1.0 - Double(b.minY))
    }
}

// 画像を小さなピクセルバッファにして色を拾う (行0 = 画像の上端になるよう反転して描く)
func makePixelBuffer(_ image: CGImage) -> (data: [UInt8], w: Int, h: Int) {
    let w = 232, h = 152
    var data = [UInt8](repeating: 0, count: w * h * 4)
    let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
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
    let x = min(buf.w - 1, max(0, Int(fx * Double(buf.w))))
    let y = min(buf.h - 1, max(0, Int(fy * Double(buf.h))))
    let i = (y * buf.w + x) * 4
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

func loadTeamFile() {
    guard let data = try? Data(contentsOf: teamURL),
          let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else { return }
    for e in arr {
        if let sp = e["species"] as? String { teamEntries[sp] = e; teamOrder.append(sp) }
    }
}

func writeTeamFile() {
    let arr = teamOrder.map { teamEntries[$0]! }
    guard let data = try? JSONSerialization.data(withJSONObject: arr, options: [.prettyPrinted, .sortedKeys]) else { return }
    try? data.write(to: teamURL, options: .atomic)
}

func runTeamOnce(image: CGImage) {
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

func captureTeamScreen(image: CGImage, tab: String) -> Int {
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
    }
    if updated > 0 || pruned { writeTeamFile() }
    return updated
}

// MARK: - 撮影ボタンの HTTP 受付 (UI から localhost:8899/capture?tab=ability|status)

var captureListener: NWListener? = nil

func startCaptureServer() {
    guard let port = NWEndpoint.Port(rawValue: 8899) else { return }
    guard let listener = try? NWListener(using: .tcp, on: port) else { return }
    listener.newConnectionHandler = { conn in
        conn.start(queue: .global())
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, _ in
            var tab = "ability"
            if let d = data, let s = String(data: d, encoding: .utf8), s.contains("tab=status") { tab = "status" }
            var body = "{\"ok\":false,\"error\":\"QuickTime の画面を取得できませんでした\"}"
            if let img = captureQuickTime() {
                let n = captureTeamScreen(image: img, tab: tab)
                if n > 0 {
                    body = "{\"ok\":true,\"registered\":\(teamOrder.count),\"message\":\"取り込みました（登録 \(teamOrder.count)/6）\"}"
                } else {
                    body = "{\"ok\":false,\"error\":\"チーム画面を読み取れませんでした\"}"
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

startCaptureServer()
if teamMode {
    print("チーム登録モード開始 (Ctrl+C で終了)。「様子を見る」で1体ずつ選び、能力タブとステータスタブをそれぞれ映してください。")
}
while true {
    if let img = captureQuickTime() {
        if teamMode { runTeamOnce(image: img) } else { runOnce(image: img) }
    }
    if once { break }
    Thread.sleep(forTimeInterval: intervalSec)
}
