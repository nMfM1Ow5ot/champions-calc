#!/usr/bin/env python3
# reader.swift patch for the battle_20261123_062508 fix round.
# Aborts without writing if any anchor count != 1 (except the suspectJump
# tuple assignments, which are replaced as a counted batch).
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

# E1: suspectJump stores the held line's hpText
rep('''var suspectJump: [String: (toPct: Int, turn: Int)] = [:]''',
    '''var suspectJump: [String: (toPct: Int, turn: Int, hpText: String)] = [:]''',
    "E1 suspectJump type")

# E2: all suspectJump assignments gain hpText (all inside emitDamageLine)
n = src.count('''suspectJump[plateName] = (toPct: toPct, turn: currentTurn)''')
if n != 5:
    print(f"ABORT E2: assignment count = {n} (expected 5)")
    sys.exit(1)
src = src.replace('''suspectJump[plateName] = (toPct: toPct, turn: currentTurn)''',
                  '''suspectJump[plateName] = (toPct: toPct, turn: currentTurn, hpText: hpText)''')
print("OK E2 suspectJump assignments x5")

# E3: a further drop corroborates the held drop — emit it as its own line
rep('''        if sj.toPct < effFrom, sj.toPct != 0 { clearedDropSuspect = true }
        suspectJump[plateName] = nil
    }''',
    '''        // 保留した値より更に下がった場合は、保留分が実在した裏づけ
        // (HP は行動の解決中に下がり続ける)。保留分を独立した行と
        // して先に出し、現在の行は保留値から始めさせる。この場合は
        // 疑いが「実在した」として解けたので、未分類の再保留
        // (post_suspect) には回さない (実例: 2026-11-23
        // battle_20261123_062508、ねっぷうの被ダメが保留と再保留の
        // 往復で消え、残りが砂嵐の行に吸収された)
        if toPct < sj.toPct && sj.toPct < effFrom {
            emitLog("|-damage|\\(slot): \\(speciesEn)|\\(sj.hpText)")
            lastEmittedPct[plateName] = sj.toPct
            monStates[key]?.hpPercent = sj.toPct
            effFrom = sj.toPct
            suspectJump[plateName] = nil
        } else {
            if sj.toPct < effFrom, sj.toPct != 0 { clearedDropSuspect = true }
            suspectJump[plateName] = nil
        }
    }''',
    "E3 held segment emission")

# E4: rescale gate in processPlates — an implausible max means the ratio
# itself was fabricated; keep the previous value for this frame
rep('''           knownMax > 0, readMax != knownMax {
            s.hpCur = Int((Double(s.hpPercent) / 100.0 * Double(knownMax)).rounded())
            s.hpMax = knownMax
        }''',
    '''           knownMax > 0, readMax != knownMax {
            if abs(readMax - knownMax) > 36, let prevSlot = lastSlots[plate.name],
               prevSlot.speciesEn == s.speciesEn {
                // 既知の最大と大きく食い違う読みは、最大値の桁誤読
                // ではなく数字の連結等の化けで、割合自体が作られて
                // いる (実例: 2026-11-23 battle_20261123_062508、
                // 177/177 が「177277」と読まれ 64% の幽霊行が出た)。
                // このフレームの HP は読めなかったものとして前回
                // 値を保つ (最大値の採用ゲートと同じ 36 の閾値)
                let curBar = s.hpBarPct
                s = prevSlot
                s.hpBarPct = curBar
            } else {
                s.hpCur = Int((Double(s.hpPercent) / 100.0 * Double(knownMax)).rounded())
                s.hpMax = knownMax
            }
        }''',
    "E4 rescale gate")

# E5: same gate in parsePlate's relaxed fallback
rep('''                    if let mx = r.max, let curText = monStates["p1:\\(sp.en)"]?.hpText,
                       let cur = Int(curText.split(separator: "/").first ?? ""), mx < cur { continue }''',
    '''                    if let mx = r.max, let curText = monStates["p1:\\(sp.en)"]?.hpText,
                       let cur = Int(curText.split(separator: "/").first ?? ""), mx < cur { continue }
                    // 既知の最大と大きく食い違う最大値も、数字の連結
                    // 等の化けとして捨てる (同じ 36 の閾値。実例:
                    // 2026-11-23 battle_20261123_062508 の 177277)
                    if let km = knownMax, let mx = r.max, abs(mx - km) > 36 { continue }''',
    "E5 parsePlate gate")

# E6: faint-text denominator falls back to battleKnownMax
rep('''            let fhp = monStates[faintKey]?.hpMax.map { "0/\\($0)" } ?? "0/100"''',
    '''            // 分母は判明している実最大で統一する。monStates の
            // hpMax は登録済み種族では入らないため battleKnownMax
            // でも引く (プレート 0% 経路と同じ統一。実例:
            // 2026-11-23 battle_20261123_062508、コータスだけ
            // 0/100 になった)
            var fhp = monStates[faintKey]?.hpMax.map { "0/\\($0)" }
            if fhp == nil, let fe = speciesDict.first(where: { $0.en == faintSp.en }),
               let km = battleKnownMax(speciesEn: faintSp.en, grp: formeGroup(fe)) {
                fhp = "0/\\(km)"
            }
            let fhpText = fhp ?? "0/100"''',
    "E6a faint denominator")
rep('''                               toPct: 0, hpText: fhp, force: true)''',
    '''                               toPct: 0, hpText: fhpText, force: true)''',
    "E6b faint call")

# E7: miss dedupe (global + reset + branch guard)
rep('''var lastEffectAt: [String: Date] = [:]            // 相性行の二重出力防止 ("slot|kind")''',
    '''var lastEffectAt: [String: Date] = [:]            // 相性行の二重出力防止 ("slot|kind")
var lastMissKey = ""                              // 外れ行の重複抑止 (行動+使用者+対象)''',
    "E7a miss global")
rep('''    lastMoveLabel = ""
    lastMoveMsgAt = Date.distantPast''',
    '''    lastMoveLabel = ""
    lastMissKey = ""
    lastMoveBySlot = [:]
    lastMoveMsgAt = Date.distantPast''',
    "E7b reset clears")
rep('''            if missConsistent {
                emitLog("|-miss|\\(lastMoveLabel)|\\(slot): \\(sp.en)")
            } else {''',
    '''            if missConsistent {
                // 同じ外れ文の表記ゆれ再読で二重に出さない (行動+
                // 使用者+対象が同じものは 1 回だけ。実例:
                // 2026-11-23 battle_20261123_062508、リーフ
                // ストームの外れが 2 行出た)
                let missKey = "\\(actionSeq)|\\(lastMoveLabel)|\\(slot)"
                if missKey != lastMissKey {
                    lastMissKey = missKey
                    emitLog("|-miss|\\(lastMoveLabel)|\\(slot): \\(sp.en)")
                }
            } else {''',
    "E7c miss guard")

# E8: per-slot last move (declaration + applyEvent recording)
rep('''var lastMoveSeq = -1                              // 直近の |move| が出た actionSeq''',
    '''var lastMoveSeq = -1                              // 直近の |move| が出た actionSeq
var lastMoveBySlot: [String: (move: String, turn: Int)] = [:]  // 枠ごとの直近の技 (遅れて届く反動の帰属用)''',
    "E8a lastMoveBySlot global")
rep('''    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq
        // まもるの使用ターンを控える (activate 行の同ターン照合用)
        let mf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)''',
    '''    } else if line.hasPrefix("|move|") {
        lastMoveEmitSeq = actionSeq
        // まもるの使用ターンを控える (activate 行の同ターン照合用)
        let mf = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        // 枠ごとの直近の技も控える (反動行の処理が次の技の告知より
        // 遅れても帰属が外れないように。実例: 2026-11-23
        // battle_20261123_062508、ブレイブバードの反動)
        if mf.count >= 4 { lastMoveBySlot[mf[2]] = (move: mf[3], turn: currentTurn) }''',
    "E8b applyEvent record")

# E9: late recoil classification
rep('''                            fromCode = "item: Rocky Helmet"; selfClassified = true; break
                        }
                    }
                }
            }
        }''',
    '''                            fromCode = "item: Rocky Helmet"; selfClassified = true; break
                        }
                    }
                }
            }
            // 反動の遅延帰属: 反動行の処理が次の技の告知より遅れて
            // 直近の技が他者になっていても、本人がこのターンに使った
            // 技が反動技で、現在の行動の被ダメ対象に本人が含まれて
            // いなければ、反動として分類する (実例: 2026-11-23
            // battle_20261123_062508、ブレイブバードの反動が
            // ねっとうの技行の後に素のダメージ行として出た)
            if fromCode == nil, lastMoveLabel != "\\(slot): \\(speciesEn)",
               let own = lastMoveBySlot["\\(slot): \\(speciesEn)"], own.turn == currentTurn,
               recoilMoves.contains(own.move),
               !(damagedBySeq[actionSeq] ?? []).contains("\\(slot): \\(speciesEn)"),
               (1...50).contains(effFrom - toPct) {
                fromCode = "move: \\(own.move)"
                selfClassified = true
            }
        }''',
    "E9 late recoil")

# E10: sandstorm chip garble fragments
rep('''        if t.contains("砂あらし") || t.contains("すなあらし") || t.contains("砂嵐") {''',
    '''        if t.contains("砂あらし") || t.contains("すなあらし") || t.contains("砂嵐")
            || t.contains("砂あら") || t.contains("すなあら") {''',
    "E10 sandstorm garble")

# E11: build stamp
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK E11 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
