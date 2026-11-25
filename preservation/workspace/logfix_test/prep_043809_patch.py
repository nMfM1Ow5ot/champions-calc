import re, sys
PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
def rep(old, new, n=1):
    global src
    c = src.count(old)
    if c != n:
        print(f"ABORT count={c}: {old[:70]!r}"); sys.exit(1)
    src = src.replace(old, new)

m = re.search(r'let readerBuild = "\d{8}_\d{4}"', src)
src = src[:m.start()] + 'let readerBuild = "STAMP"' + src[m.end():]

# ---- 中1: suspect 解消の一致条件を ±3 に広げる ----
rep('''    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct && sj.toPct == 0 {''',
'''    if let sj = suspectJump[plateName] {
        if toPct == sj.toPct && sj.toPct == 0 {''')
rep('''        } else if toPct == sj.toPct {
            if currentTurn > sj.turn {''',
'''        } else if toPct != 0 && abs(toPct - sj.toPct) <= 3 {
            // 保留値の ±3 ポイント以内は、読みの揺れの範囲内として
            // 同じ低下の裏づけとみなす。完全一致に限ると、低 HP での
            // 揺れ (6% の保留後に 5% や 7% が安定する等) が「別の値」
            // として疑いを解き、post_suspect の再保留との往復で永久に
            // 採用されなくなる (実例: 2026-11-23
            // battle_20261123_043809、Dragonite の 54% -> 6% が最後まで
            // 取り込まれず、反動行が古い基準から記録された)
            if currentTurn > sj.turn {''')

# ---- 中2: 最大 HP 採用の時間間隔と取消し ----
rep('var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数',
    '''var battleMaxCandidate: [String: (max: Int, count: Int, firstAt: Date)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数・初出時刻
var battleMaxRevertCount: [String: Int] = [:]  // 種族 -> 採用後に登録値どおりの読みが続いた回数 (採用取消し用)''')
rep('''    if battleMaxOverride[speciesEn] != nil { return }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }''',
'''    if let ov = battleMaxOverride[speciesEn] {
        // 採用後に登録値どおりの読みが続けば、採用の方が誤読だった
        // として取り消す。登録はユーザーが確認した情報であり、離れる
        // 方向 (採用) は慎重に、戻る方向 (取消し) は速くする
        // (実例: 2026-11-23 battle_20261123_043809、Sylveon の最大が
        // 交代直後の誤読 219 で採用され、実値 193 の読みが続いても
        // 上書きが残り続けた)
        if let reg = registeredMax, ov != reg, readMax == reg {
            let n = (battleMaxRevertCount[speciesEn] ?? 0) + 1
            if n >= 3 {
                battleMaxOverride[speciesEn] = nil
                battleMaxRevertCount[speciesEn] = nil
                debugCapture(kind: "team_max_reverted", key: "team_max_reverted:\\(speciesEn)", rawText: "",
                             detail: ["species": speciesEn, "registeredMax": reg, "revertedMax": ov, "turn": currentTurn, "readerBuild": readerBuild])
            } else {
                battleMaxRevertCount[speciesEn] = n
            }
        } else if readMax == ov {
            battleMaxRevertCount[speciesEn] = nil
        }
        return
    }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }''')
rep('''    if battleMaxCandidate[speciesEn]?.max == readMax {
        let n = (battleMaxCandidate[speciesEn]?.count ?? 1) + 1
        if n >= 2 {
            battleMaxOverride[speciesEn] = readMax
            battleMaxCandidate[speciesEn] = nil
            debugCapture(kind: "team_max_mismatch", key: "team_max_mismatch:\\(speciesEn)", rawText: "",
                         detail: ["species": speciesEn, "registeredMax": registeredMax ?? -1, "readMax": readMax, "turn": currentTurn, "readerBuild": readerBuild])
        } else {
            battleMaxCandidate[speciesEn] = (max: readMax, count: n)
        }
    } else {
        battleMaxCandidate[speciesEn] = (max: readMax, count: 1)
    }''',
'''    if let cand = battleMaxCandidate[speciesEn], cand.max == readMax {
        let n = cand.count + 1
        // 採用は、候補の初出から 3 秒以上あいた観測での一致を条件と
        // する。交代直後などの短い窓では同じ誤読が連続して出るため、
        // 回数だけでは誤読のバーストを弾けない (実例: 2026-11-23
        // battle_20261123_043809、Sylveon の 219)
        if n >= 2 && sNow().timeIntervalSince(cand.firstAt) >= 3.0 {
            battleMaxOverride[speciesEn] = readMax
            battleMaxCandidate[speciesEn] = nil
            debugCapture(kind: "team_max_mismatch", key: "team_max_mismatch:\\(speciesEn)", rawText: "",
                         detail: ["species": speciesEn, "registeredMax": registeredMax ?? -1, "readMax": readMax, "turn": currentTurn, "readerBuild": readerBuild])
        } else {
            battleMaxCandidate[speciesEn] = (max: readMax, count: n, firstAt: cand.firstAt)
        }
    } else {
        battleMaxCandidate[speciesEn] = (max: readMax, count: 1, firstAt: sNow())
    }''')
rep('battleMaxOverride = [:]; battleMaxCandidate = [:];',
    'battleMaxOverride = [:]; battleMaxCandidate = [:]; battleMaxRevertCount = [:];')

# ---- 中3: 漢字「眠」を眠り判定に追加 (眠気は除く) ----
rep('''    else if text.contains("ねむ") { code = "slp" }''',
    '''    else if text.contains("ねむ") || (text.contains("眠") && !text.contains("眠気")) { code = "slp" }''')
rep('''    let hasCode = t.contains("もうどく") || t.contains("どく") || t.contains("やけど") || t.contains("まひ")
        || t.contains("ねむ") || t.contains("こおり") || t.contains("こおった")''',
'''    let hasCode = t.contains("もうどく") || t.contains("どく") || t.contains("やけど") || t.contains("まひ")
        || t.contains("ねむ") || (t.contains("眠") && !t.contains("眠気")) || t.contains("こおり") || t.contains("こおった")''')

# ---- 低2: Detect も Protect と同じ activate 照合の対象にする ----
rep('var protectMoveTurn: [String: Int] = [:]         // 枠 -> まもるを使ったターン (activate 行の照合用)',
    '''var protectMoveTurn: [String: Int] = [:]         // 枠 -> まもる系を使ったターン (activate 行の照合用)
var protectMoveName: [String: String] = [:]      // 枠 -> 使ったまもる系の技名 (Protect / Detect)''')
rep('''        if mf.count >= 4 && mf[3] == "Protect" {
            let pslot = mf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn }
        }''',
'''        if mf.count >= 4 && (mf[3] == "Protect" || mf[3] == "Detect") {
            let pslot = mf[2].split(separator: ":").first.map(String.init) ?? ""
            if !pslot.isEmpty { protectMoveTurn[pslot] = currentTurn; protectMoveName[pslot] = mf[3] }
        }''')
rep('''        if protectMoveTurn[slot] == currentTurn {
            emitLog("|-activate|\\(slot): \\(sp.en)|move: Protect")
        }''',
'''        if protectMoveTurn[slot] == currentTurn {
            emitLog("|-activate|\\(slot): \\(sp.en)|move: \\(protectMoveName[slot] ?? "Protect")")
        }''')
rep('''        if f[3].contains("Protect") { return ["\\(renderPrefix(side))\\(species) protected itself!"] }''',
    '''        if f[3].contains("Protect") || f[3].contains("Detect") { return ["\\(renderPrefix(side))\\(species) protected itself!"] }''')

open(PATH, "w", encoding="utf-8").write(src)
print("OK")
