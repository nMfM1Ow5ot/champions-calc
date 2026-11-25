#!/usr/bin/env python3
# reader.swift: battle_20261122_181745 fix round (log-analysis chat
# instruction). F1 bar disagreement in the 0% branch (veto >= 25,
# hold 11-24) + mine zero-text denominator; F2 recoil moves
# (Steel Beam etc.); F3 faint-text subject from the "name + wa"
# grammar; F4 revival of a poisoned faint baseline (fainted-slot
# revive + occupant rebase); F5 archive-header switch max rewrite
# for adopted maxima; F6 no damage line at full HP; F8 Perish Song
# count/announcement texts consumed.
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

def rep(name, old, new, cnt=1):
    global src
    c = src.count(old)
    if c != cnt:
        print(f"ABORT: {name}: anchor count = {c} (expected {cnt})")
        sys.exit(1)
    src = src.replace(old, new, 1)
    print(f"OK: {name}")

# ---- F2: recoil / self-damage moves ----
rep("F2 recoilMoves",
    """let recoilMoves: Set<String> = ["Double-Edge", "Take Down", "Submission", "Volt Tackle",
                                "Flare Blitz", "Brave Bird", "Wood Hammer", "Head Smash",
                                "Wild Charge", "Head Charge", "Struggle"]""",
    """let recoilMoves: Set<String> = ["Double-Edge", "Take Down", "Submission", "Volt Tackle",
                                "Flare Blitz", "Brave Bird", "Wood Hammer", "Head Smash",
                                "Wild Charge", "Head Charge", "Struggle", "Wave Crash",
                                "Steel Beam", "Mind Blown", "Chloroblast"]""")

# ---- F4 globals + reset ----
rep("F4 globals",
    """var barVetoHold: [String: (pct: Int, turn: Int)] = [:]        // プレート -> バー拒否で保留した数字読みとそのターン""",
    """var barVetoHold: [String: (pct: Int, turn: Int)] = [:]        // プレート -> バー拒否で保留した数字読みとそのターン
var faintReviveCount: [String: Int] = [:]                     // プレート -> ひんし確定枠で生存読みが続いた回数
var faintReviveSince: [String: Date] = [:]                    // プレート -> その生存読みの初出""")

rep("F4 reset",
    """pendingReturnCount = [:]; barVetoHold = [:]""",
    """pendingReturnCount = [:]; barVetoHold = [:]; faintReviveCount = [:]; faintReviveSince = [:]""")

# ---- F5: archive header switch max rewrite ----
rep("F5 header rewrite",
    """    if !realMax.isEmpty {
        proto = proto.map { l in
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, f[1] == "switch", f[4] == "100/100", let mx = realMax[f[2]] else { return l }
            var g = f
            g[4] = "\\(mx)/\\(mx)"
            return g.joined(separator: "|")
        }
    }""",
    """    if !realMax.isEmpty {
        proto = proto.map { l in
            let f = l.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 5, f[1] == "switch", let mx = realMax[f[2]] else { return l }
            // 満タンで登場した交代行は、後続の行で判明した実数の最大値に
            // 揃える。対象は % 表記 (100/100) の場合と、最大値の採用前に
            // 登録値で出た場合 (157/157 のまま残り、後続は /171 で処理
            // されて 1 つのプロトコル内で表記が割れた。実例: 2026-11-22
            // battle_20261122_181745、Sneasler)
            let parts = f[4].split(separator: "/")
            guard parts.count == 2, let cur = Int(parts[0]), let oldMax = Int(parts[1]),
                  cur == oldMax, mx != oldMax else { return l }
            var g = f
            g[4] = "\\(mx)/\\(mx)"
            return g.joined(separator: "|")
        }
    }""")

# ---- F6: no damage line without an actual drop ----
rep("F6 full-hp guard",
    """        lastDamageLabel = "\\(slot): \\(speciesEn)"
        lastDamageAt = Date()
        var line = "|-damage|\\(slot): \\(speciesEn)|\\(hpText)\"""",
    """        // 低下していない値への被ダメ行はあり得ない。開幕のプレート
        // 確定時に % 基準 (100) と実数表記がずれて、満タンの被ダメ行
        // が出た実例への対策 (実例: 2026-11-22
        // battle_20261122_181745、ターン 1 冒頭の 145/145・161/161)
        if toPct >= effFrom { return true }
        lastDamageLabel = "\\(slot): \\(speciesEn)"
        lastDamageAt = Date()
        var line = "|-damage|\\(slot): \\(speciesEn)|\\(hpText)\"""")

# ---- F4a: revive a fainted slot that keeps reading alive ----
rep("F4a fainted revive",
    """            // ひんし確定済みの枠は、交代が確定するまでプレート読みを無視する
            // (交代要員選択画面で満タンのバーが読めて「全回復」行が出たり、
            //  0% に戻って ひんし行が二重に出たりした実例: 2026-11-20)
            if faintedSlots[slot] == s.speciesEn { continue }""",
    """            // ひんし確定済みの枠は、交代が確定するまでプレート読みを無視する
            // (交代要員選択画面で満タンのバーが読めて「全回復」行が出たり、
            //  0% に戻って ひんし行が二重に出たりした実例: 2026-11-20)。
            // ただし生存読みが安定して続く場合は、ひんし自体が誤読
            // だったとして取り消す (実例: 2026-11-22
            // battle_20261122_181745、ターン 2 の幻のひんし。バーは
            // 42% を示していた)。条件は 20% 以上の読みが 3 回・
            // 1.5 秒以上続き、ひんし行から 3 秒以上経っていること
            if faintedSlots[slot] == s.speciesEn {
                var revived = false
                if s.hpPercent >= 20,
                   Date().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                    let rc = (faintReviveCount[plate.name] ?? 0) + 1
                    faintReviveCount[plate.name] = rc
                    if faintReviveSince[plate.name] == nil { faintReviveSince[plate.name] = Date() }
                    if rc >= 3, Date().timeIntervalSince(faintReviveSince[plate.name] ?? .distantFuture) >= 1.5 {
                        faintedSlots.removeValue(forKey: slot)
                        faintReviveCount[plate.name] = nil
                        faintReviveSince[plate.name] = nil
                        lastEmittedPct[plate.name] = s.hpPercent
                        debugCapture(kind: "faint_guard", key: "faint_revived:\\(slot):\\(s.speciesEn)", rawText: "",
                                     detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
                        revived = true
                    }
                } else {
                    faintReviveCount[plate.name] = nil
                    faintReviveSince[plate.name] = nil
                }
                if !revived { continue }
            }""")

# ---- F4b: rebase a poisoned zero baseline in the occupant branch ----
rep("F4b occupant rebase",
    """            monStates[key]?.hpPercent = s.hpPercent
            monStates[key]?.hpText = hpTextFor(s)
            let emitted = lastEmittedPct[plate.name] ?? s.hpPercent""",
    """            monStates[key]?.hpPercent = s.hpPercent
            monStates[key]?.hpText = hpTextFor(s)
            // 排出基準が 0 のまま生存読みが届いた場合は、過去のひんし
            // 記録が誤りだったとして基準を現在値へ戻す。0 のままだと
            // 回復が無言で飲み込まれ、本物のひんし (被ダメ行の合成
            // 条件・ひんし文の確定条件) まで成立しなくなる (実例:
            // 2026-11-22 battle_20261122_181745、ターン 2 の幻の
            // ひんしがターン 7 の ほろびのうた の ひんしを消した)
            if s.hpPercent >= 20, (lastEmittedPct[plate.name] ?? -1) == 0,
               pendingFaints.allSatisfy({ $0.slot != slot }),
               Date().timeIntervalSince(lastDamageTime[plate.name] ?? .distantPast) > 3.0 {
                lastEmittedPct[plate.name] = s.hpPercent
                debugCapture(kind: "faint_guard", key: "faint_revived:\\(slot):\\(s.speciesEn)", rawText: "",
                             detail: ["reason": "revived_baseline", "slot": slot, "species": s.speciesEn, "pct": s.hpPercent, "turn": currentTurn, "readerBuild": readerBuild])
            }
            let emitted = lastEmittedPct[plate.name] ?? s.hpPercent""")

# ---- F1 + F7: 0% branch bar disagreement + mine zero text ----
rep("F1 zero branch",
    """                    } else if n >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                        // バーが半分以上残っているのに数字だけ 0% を言う
                        // 場合は、数字側の誤読として ひんしにしない
                        // (バー拒否、フェーズ2 段階2)
                        if let bar = s.hpBarPct, bar >= 50 {
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\\(plate.name):0:\\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": 0,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_zero", "readerBuild": readerBuild])
                        } else {
                            emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: emitted, toPct: 0, hpText: monStates[key]!.hpText)
                        }
                    } else {""",
    """                    } else if n >= 2 {
                        // バー計測が 0% 読みと明確に食い違う場合は
                        // ひんしにしない。バーが 25% 以上残っていれば
                        // 誤読として棄却し、11〜24% では判断を保留して
                        // 次の読みで再判定する (実例: 2026-11-22
                        // battle_20261122_181745、Sneasler のバーが
                        // 42% を示していたのに 0% 読みで幻のひんし行が
                        // 出て、記録全体が連鎖的に崩れた。従来の棄却
                        // 条件はバー 50% 以上で、この値に届かなかった)
                        if let bar = s.hpBarPct, bar >= 25 {
                            pendingDamagePct[plate.name] = nil
                            pendingDamageCount[plate.name] = nil
                            pendingDamageSince[plate.name] = nil
                            pendingReturnCount[plate.name] = nil
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\\(plate.name):0:\\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": 0,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_zero", "readerBuild": readerBuild])
                        } else if let bar = s.hpBarPct, bar > 10 {
                            pendingDamageCount[plate.name] = n
                        } else {
                            pendingDamagePct[plate.name] = nil
                            pendingDamageCount[plate.name] = nil
                            pendingDamageSince[plate.name] = nil
                            pendingReturnCount[plate.name] = nil
                            // 自軍の 0% 行の分母は、判明している実数の
                            // 最大値で統一する (% 読みしかない場合に
                            // 0/100 へ切り替わって表記が割れた実例:
                            // 同バトル、Gardevoir の 35/145 → 0/100)
                            var zeroText = monStates[key]!.hpText
                            if plate.name.hasPrefix("mine"), s.hpCur == nil,
                               let e0 = speciesDict.first(where: { $0.en == s.speciesEn }),
                               let km = battleKnownMax(speciesEn: s.speciesEn, grp: formeGroup(e0)) {
                                zeroText = "0/\\(km)"
                            }
                            emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                           fromPct: emitted, toPct: 0, hpText: zeroText)
                        }
                    } else {""")

# ---- F8: Perish Song texts consumed ----
rep("F8 perish consume",
    """    if t.contains("回復した") { return true }""",
    """    if t.contains("回復した") { return true }
    // ほろびのうたのカウント文と告知文は、場の状態として別途持たない
    // ため消費のみ (表記ゆれ: 滅び/減び、分割読み「ぼろ滅び」「ほろ
    // 滅び」を含む。実例: 2026-11-22 battle_20261122_181745、
    // カウント文が |-message| として漏れた)
    let squashedMsg = t.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "　", with: "")
    if squashedMsg.contains("カウントが") && (squashedMsg.contains("滅び") || squashedMsg.contains("減び")) { return true }
    if squashedMsg.contains("ほろびのうたを") && squashedMsg.contains("滅びてしまう") { return true }""")

# ---- F3: faint subject from the name+wa grammar ----
rep("F3 faint grammar",
    """    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        // 場の占有として記録されていない種族の ひんし文では、""",
    """    if t.contains("たおれた") || foldDakuten(t).contains("たおれた") {
        // ひんし文の主語は「種族名+は」の形で決める。文にプレートの
        // 文字など他の種族名が混ざると、本文全体の種族解決 (sp:
        // 辞書順の最初の一致) が無関係な種族になり、占有でないとして
        // 文が捨てられる (実例: 2026-11-22 battle_20261122_181745、
        // Archaludon の ひんし文に オオニューラ のプレート文字が
        // 混ざり、主語が Sneasler と解決された)
        var faintSp = sp
        var faintSlot = slot
        var faintKey = key
        let foldedMsg = foldDakuten(t)
        for cand in findAllSpeciesJa(in: t) where cand.en != sp.en {
            var isSubject = false
            for hay in [t, foldedMsg] {
                var pos = hay.startIndex
                while let r = hay.range(of: cand.ja, range: pos..<hay.endIndex) {
                    if hay[r.upperBound...].hasPrefix("は") { isSubject = true; break }
                    pos = r.upperBound
                }
                if isSubject { break }
            }
            if isSubject {
                faintSp = cand
                let fside = slot.hasPrefix("p1") ? "p1" : "p2"
                faintSlot = slotFor(side: fside, speciesEn: cand.en)
                faintKey = "\\(fside):\\(cand.en)"
                break
            }
        }
        // 場の占有として記録されていない種族の ひんし文では、""")

rep("F3 branch body",
    """        let faintPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][slot] ?? ""
        let faintOccupant = lastSlots[faintPn]?.speciesEn
        let faintIsOccupant = (faintOccupant.map { sameSpeciesFamily($0, sp.en) } ?? false)
            || pendingSwitchSpecies[faintPn] == sp.en
        if !faintIsOccupant {
            debugCapture(kind: "faint_guard", key: "faint_guard:untracked:\\(slot):\\(sp.en)", rawText: t,
                         detail: ["reason": "faint_text_untracked", "slot": slot, "species": sp.en, "occupant": faintOccupant ?? "", "turn": currentTurn])
            return true
        }""",
    """        let faintPn = ["p1a": "mineA", "p1b": "mineB", "p2a": "oppA", "p2b": "oppB"][faintSlot] ?? ""
        let faintOccupant = lastSlots[faintPn]?.speciesEn
        let faintIsOccupant = (faintOccupant.map { sameSpeciesFamily($0, faintSp.en) } ?? false)
            || pendingSwitchSpecies[faintPn] == faintSp.en
        if !faintIsOccupant {
            debugCapture(kind: "faint_guard", key: "faint_guard:untracked:\\(faintSlot):\\(faintSp.en)", rawText: t,
                         detail: ["reason": "faint_text_untracked", "slot": faintSlot, "species": faintSp.en, "occupant": faintOccupant ?? "", "turn": currentTurn])
            return true
        }""")

rep("F3 branch tail",
    """        if !faintPn.isEmpty && (lastEmittedPct[faintPn] ?? 1) > 0 {
            heldLine[faintPn] = nil
            let fhp = monStates[key]?.hpMax.map { "0/\\($0)" } ?? "0/100"
            _ = emitDamageLine(plateName: faintPn, slot: slot, key: key, speciesEn: sp.en,
                               fromPct: lastEmittedPct[faintPn] ?? (monStates[key]?.hpPercent ?? 100),
                               toPct: 0, hpText: fhp, force: true)
        }
        // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
        deferFaint(slot: slot, speciesEn: sp.en)
        return true""",
    """        if !faintPn.isEmpty && (lastEmittedPct[faintPn] ?? 1) > 0 {
            heldLine[faintPn] = nil
            let fhp = monStates[faintKey]?.hpMax.map { "0/\\($0)" } ?? "0/100"
            _ = emitDamageLine(plateName: faintPn, slot: faintSlot, key: faintKey, speciesEn: faintSp.en,
                               fromPct: lastEmittedPct[faintPn] ?? (monStates[faintKey]?.hpPercent ?? 100),
                               toPct: 0, hpText: fhp, force: true)
        }
        // HP 0 への反映は被ダメ行 (と後続の ひんし行) の applyEvent が行う
        deferFaint(slot: faintSlot, speciesEn: faintSp.en)
        return true""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
