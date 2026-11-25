#!/usr/bin/env python3
# reader.swift patch for the battle_20261123_060833 fix round.
# E1 TR move-line synthesis in checkFieldText
# E2 fainted occupants excluded from boost-side evidence (3 sites)
# E3 isBoostShapedText garbled stat fragments
# E4 Supreme Overlord attribution (global + reset clear + branch + recordSwitchIn flush)
# E5 headerDistinctMargin + startBattleLog use
# E6 readerBuild stamp
import re, sys, datetime

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()
orig = src

def rep(old, new, tag):
    global src
    n = src.count(old)
    if n != 1:
        print(f"ABORT {tag}: anchor count = {n}")
        sys.exit(1)
    src = src.replace(old, new)
    print(f"OK {tag}")

# E1: TR synthesis
rep('''    if text.contains("時空") && (foldDakuten(text).contains("ゆかめ") || text.contains("歪め")) {
        if !logTrickRoom { emitLog("|-fieldstart|move: Trick Room") }
        return true
    }''',
    '''    if text.contains("時空") && (foldDakuten(text).contains("ゆかめ") || text.contains("歪め")) {
        if !logTrickRoom {
            // 告知行が落ちている場合、開始文の主語から技行を補う
            // (実例: 2026-11-23 battle_20261123_060833、告知文は obs に
            // クリーンに残っていたが技行だけが無く、開始行だけが残った。
            // 開始文は使用者が確定している証拠なので、現在の区間に同じ
            // 技行が無い場合に限り開始行の直前へ補う。告知が後から届いても
            // emitLog の同ラウンド再使用ガードが二重化を防ぐ)
            if !fromLogScreen, let tsp = findSpeciesJa(in: text) {
                let tside = (text.contains("相手の") || text.contains("あいての")) ? "p2" : "p1"
                let tslot = slotFor(side: tside, speciesEn: tsp.en)
                let tpn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][tslot] ?? ""
                if lastSlots[tpn]?.speciesEn.map({ sameSpeciesFamily($0, tsp.en) }) ?? false {
                    let tlabel = "\\(tslot): \\(tsp.en)"
                    let segStart = battleLog.lastIndex(where: { $0.hasPrefix("|turn|") }) ?? -1
                    if !battleLog[(segStart + 1)...].contains("|move|\\(tlabel)|Trick Room") {
                        emitLog("|move|\\(tlabel)|Trick Room")
                    }
                }
            }
            emitLog("|-fieldstart|move: Trick Room")
        }
        return true
    }''', "E1 TR synthesis")

# E2 site A: resolvedBoostSide
rep('''            let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
            let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en || teamEntries[e.en] != nil''',
    '''            // ひんし済みの同種族は場の証拠にしない (倒れた個体は
            // ランク変化を受けない。実例: 2026-11-23
            // battle_20261123_060833、倒れた相手のコータスが枠に
            // 残っていたため、自軍コータスへの いかく の低下が
            // 相手側へ誤帰属した)
            let inOpp = (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en) && !faintedSpecies.contains("p2:\\(e.en)")
            let inMine = (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en) && !faintedSpecies.contains("p1:\\(e.en)") || teamEntries[e.en] != nil''',
    "E2a resolvedBoostSide")

# E2 site B: intimidate pre-pass
rep('''                for e in subjects {
                    let inOpp = lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en
                    let inMine = lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en || teamEntries[e.en] != nil
                    targetSides.insert(inOpp && !inMine ? "p2" : "p1")
                }''',
    '''                for e in subjects {
                    let inOpp = (lastSlots["oppA"]?.speciesEn == e.en || lastSlots["oppB"]?.speciesEn == e.en) && !faintedSpecies.contains("p2:\\(e.en)")
                    let inMine = (lastSlots["mineA"]?.speciesEn == e.en || lastSlots["mineB"]?.speciesEn == e.en) && !faintedSpecies.contains("p1:\\(e.en)") || teamEntries[e.en] != nil
                    targetSides.insert(inOpp && !inMine ? "p2" : "p1")
                }''', "E2b intimidate prepass")

# E2 site C: single-subject path
rep('''            let inOppF = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
            let inMineF = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en''',
    '''            let inOppF = (lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en) && !faintedSpecies.contains("p2:\\(sp.en)")
            let inMineF = (lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en) && !faintedSpecies.contains("p1:\\(sp.en)")''',
    "E2c single path")

# E2d: applyBoost dedupe key is the mon key, not the slot (a subject
# resolved to the default slot must not collide with the slot's real
# occupant from the same text)
rep('''    let bk = "\\(slot)|\\(stat)|\\(delta)"''',
    '''    // 重複防止のキーは枠でなく個体キーにする (複合主語の文で、片方が
    // 既定枠に解決されると、実占有者とキーが衝突して変化が丸ごと
    // 落ちる。実例: 2026-11-23 battle_20261123_060833 の いかく)
    let bk = "\\(key)|\\(stat)|\\(delta)"''', "E2d applyBoost bk")

# E3: isBoostShapedText fragments
rep('''    return ["攻撃", "こうげき", "防御", "ぼうぎょ", "攻が", "防が", "特攻", "とくこう", "特防", "とくぼう", "素早さ", "すばやさ", "命中率", "回避率", "すべての"].contains { t.contains($0) }''',
    '''    // 「撃が」「御が」は漢字能力名の後半断片 (攻撃の「政撃」のような
    // 1 字化けでも形状として拾う。実例: 2026-11-23
    // battle_20261123_060833、「政撃が下がった！」が未変換で漏れた)
    return ["攻撃", "こうげき", "防御", "ぼうぎょ", "攻が", "防が", "撃が", "御が", "特攻", "とくこう", "特防", "とくぼう", "素早さ", "すばやさ", "命中率", "回避率", "すべての"].contains { t.contains($0) }''',
    "E3 boost shape")

# E4a: global
rep('''var critEventMarks: [String: (turn: Int, atk: String)] = [:]''',
    '''var critEventMarks: [String: (turn: Int, atk: String)] = [:]
var pendingAbilityReveal: [String: String] = [:]   // "側:種族EN" -> 特性EN。定型文から帰属したが枠が未確定の特性行の保留 (交代確定時に recordSwitchIn が流す)''',
    "E4a global")

# E4b: resetLogState clear
rep('''    critEventMarks = [:]''',
    '''    critEventMarks = [:]
    pendingAbilityReveal = [:]''', "E4b reset clear")

# E4c: branch before the boost section
rep('''    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する''',
    '''    // そうだいしょうの告知文: 「<種族>は 倒された仲間から 力を
    // もらった！」。特性名は帯文に出ず、バナーは画面上部のため、この
    // 定型文から帰属させる。語順が崩れた読み (実例: 2026-11-23
    // battle_20261123_060833、「ドドゲザンはもらった！仲間から
    // 倒された力を」) でも拾えるよう、断片の共存で判定する。交代の
    // 確定前で枠が定まらない間は保留し、recordSwitchIn で流す
    if t.contains("倒された") && t.contains("もらった"),
       let osp = findSpeciesJa(in: t),
       (speciesAbilityMap[osp.en]?.contains("Supreme Overlord") ?? false) {
        var oside = side
        if t.contains("相手の") || t.contains("あいての") { oside = "p2" }
        else if t.contains("味方の") { oside = "p1" }
        else if (fieldSeen["p2"]?.contains(osp.en) ?? false) && !(fieldSeen["p1"]?.contains(osp.en) ?? false) { oside = "p2" }
        let oslot = slotFor(side: oside, speciesEn: osp.en)
        let opn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][oslot] ?? ""
        if lastSlots[opn]?.speciesEn.map({ sameSpeciesFamily($0, osp.en) }) ?? false {
            emitAbilityOnce(slot: oslot, side: oside, speciesEn: osp.en, abilityEn: "Supreme Overlord")
        } else {
            pendingAbilityReveal["\\(oside):\\(osp.en)"] = "Supreme Overlord"
        }
        return true
    }
    // ランク変化: 主語が複数の文 (いかく「Aと Bの 攻撃が 下がった！」等) は全員に適用する''',
    "E4c overlord branch")

# E4d: recordSwitchIn flush
rep('''    fieldSeen[side, default: []].insert(speciesEn)''',
    '''    fieldSeen[side, default: []].insert(speciesEn)
    // 保留中の特性帰属 (交代確定前に定型文だけが届いた場合) を、
    // 交代行の直後に流す (実例: 2026-11-23 battle_20261123_060833、
    // そうだいしょうの文がプレート確定より先に届いた)
    if let pendingAbility = pendingAbilityReveal.removeValue(forKey: "\\(side):\\(speciesEn)") {
        emitAbilityOnce(slot: slot, side: side, speciesEn: speciesEn, abilityEn: pendingAbility)
    }''', "E4d switch flush")

# E5a: headerDistinctMargin before completeArchiveHeader
rep('''func completeArchiveHeader(''',
    '''// ヘッダー補正のマージン: 次点が同種族のフォルム違いだけの場合、
// その差は種族の誤同定の証拠にならないため、別種族の最良候補との
// 差を使う (実例: 2026-11-23 battle_20261123_060833、Aegislash の
// Shield/Blade 差 0.014 が最小になり、正しい項目が落ちた)。
// 別種族の候補が無い枠はマージンを持たない (補正で最後に選ばれる)
func headerDistinctMargin(ranked: [(String, Double)]) -> Double? {
    guard let pick = ranked.first else { return nil }
    guard let runner = ranked.dropFirst().first(where: { !sameSpeciesFamily($0.0, pick.0) }) else { return nil }
    return runner.1 - pick.1
}

func completeArchiveHeader(''', "E5a margin func")

# E5b: startBattleLog use
rep('''            if let runner = ranked.dropFirst().first {
                headerSlotMargins["p2:\\(pick.0)"] = runner.1 - pick.1
            }''',
    '''            if let margin = headerDistinctMargin(ranked: ranked) {
                headerSlotMargins["p2:\\(pick.0)"] = margin
            }''', "E5b margin use")

# E6: stamp
jst = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9)))
stamp = jst.strftime("%Y%m%d_%H%M")
src, n = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if n != 1:
    print("ABORT stamp")
    sys.exit(1)
print(f"OK E6 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
