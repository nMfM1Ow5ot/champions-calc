#!/usr/bin/env python3
# battle_20261122_160927 fix round (log-analysis chat request):
# F1: noteBattleMaxRead hardening (once-only adoption, |delta| <= 36 gate,
#     readMax below observed current HP rejected)
# F2: HP bar veto in processPlates (stable branch + 0% branch)
# F3: sourceless-drop hold in emitDamageLine (symmetric with heal side)
# F4: send-out text evidence for the opponent's 繰り出した branch
# F5: parsePlate fallback rejects reads whose max is below the observed
#     current HP (max fragment reads)
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

# ---- F1: noteBattleMaxRead ----
rep("F1 noteBattleMaxRead gates",
    """func noteBattleMaxRead(speciesEn: String, readMax: Int, registeredMax: Int?) {
    if battleMaxOverride[speciesEn] == readMax { return }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }
""",
    """func noteBattleMaxRead(speciesEn: String, readMax: Int, registeredMax: Int?) {
    // 採用は各種族・試合ごとに 1 回限り: 最初の採用で登録側の取り違えは
    // 正せるが、それ以降も読みに追随すると、同じ誤読 (数字融合) の
    // 繰り返しで誤った最大へ際限なく乗り換えてしまう (実例:
    // 2026-11-22 battle_20261122_160927、171 の正しい採用の後に
    // 271 の融合読みが上書き採用された)
    if battleMaxOverride[speciesEn] != nil { return }
    if let reg = registeredMax, reg == readMax { battleMaxCandidate[speciesEn] = nil; return }
    // 候補として数える前の妥当性ゲート: 信頼値から 36 を超えて離れた
    // 読みは、努力値の振り幅 (最大でも 32) では説明できず、数字融合
    // (171 -> 271、177 -> 371) の疑いが強いため候補にしない。また、
    // その種族で既に観測した現在 HP より小さい最大はあり得ない
    if let reg = registeredMax, reg > 0, abs(readMax - reg) > 36 { return }
    if let curText = monStates["p1:\\(speciesEn)"]?.hpText,
       let cur = Int(curText.split(separator: "/").first ?? ""), readMax < cur { return }
""")

# ---- F2a: barVetoHold global (next to battleMaxCandidate decl) ----
rep("F2a barVetoHold global",
    "var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数\n",
    "var battleMaxCandidate: [String: (max: Int, count: Int)] = [:]  // 種族 -> 採用候補の最大 HP と観測回数\n"
    "var barVetoHold: [String: (pct: Int, turn: Int)] = [:]        // プレート -> バー拒否で保留した数字読みとそのターン\n")

# ---- F2b: stable-branch bar veto ----
rep("F2b stable branch veto",
    """                if n >= 3 && stable {
                    // 安定した時点でもバー計測と数字 OCR が食い違う場合は
                    // 系統間の不一致として証拠に残す (フェーズ2)
""",
    """                if n >= 3 && stable {
                    // バー計測が数字読みの低下を強く否定する場合は行を
                    // 出さない (フェーズ2 段階2の採用判定: バー拒否)。
                    // 数字が 8 ポイント以上下がったと言うのに、バーの
                    // 画素長が確定値の 5 ポイント以内に留まるなら、
                    // 数字側 (隣枠の混入や数字融合) の誤読と判断する。
                    // 次ターンも同じ値で食い違いが続けば、数字側を
                    // 状態訂正として静かに取り込む (実例: 2026-11-22
                    // battle_20261122_160927、Sneasler の被ダメ幻行
                    // 3 件はいずれもバーが 95% 以上を維持していた)
                    if let bar = s.hpBarPct, s.hpPercent < emitted,
                       emitted - s.hpPercent >= 8, bar >= emitted - 5 {
                        if let held = barVetoHold[plate.name], held.pct == s.hpPercent, held.turn < currentTurn {
                            barVetoHold[plate.name] = nil
                            lastEmittedPct[plate.name] = s.hpPercent
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\\(plate.name):\\(s.hpPercent):\\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_adopted", "readerBuild": readerBuild])
                        } else {
                            barVetoHold[plate.name] = (pct: s.hpPercent, turn: currentTurn)
                            debugCapture(kind: "hp_disagree", key: "hp_disagree:\\(plate.name):\\(s.hpPercent):\\(bar)", rawText: "",
                                         detail: ["slot": slot, "species": s.speciesEn, "ocrPct": s.hpPercent,
                                                  "barPct": bar, "logPct": emitted, "turn": currentTurn,
                                                  "reason": "bar_veto_drop", "readerBuild": readerBuild])
                        }
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                    } else {
                    // 安定した時点でもバー計測と数字 OCR が食い違う場合は
                    // 系統間の不一致として証拠に残す (フェーズ2)
""")
# close the added else: the emit block's closing needs one more brace.
rep("F2b close else",
    """                    } else {
                        // 同一行動内の段階値として保留 (値は保持する)
                        pendingDamageCount[plate.name] = 3
                    }
                } else {
                    pendingDamageCount[plate.name] = n
                }
""",
    """                    } else {
                        // 同一行動内の段階値として保留 (値は保持する)
                        pendingDamageCount[plate.name] = 3
                    }
                    }
                } else {
                    pendingDamageCount[plate.name] = n
                }
""")

# ---- F2c: 0% branch bar veto ----
rep("F2c zero branch veto",
    """                    } else if n >= 2 {
                        pendingDamagePct[plate.name] = nil
                        pendingDamageCount[plate.name] = nil
                        pendingDamageSince[plate.name] = nil
                        pendingReturnCount[plate.name] = nil
                        emitDamageLine(plateName: plate.name, slot: slot, key: key, speciesEn: s.speciesEn,
                                       fromPct: emitted, toPct: 0, hpText: monStates[key]!.hpText)
                    } else {
""",
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
                    } else {
""")

# ---- F3: sourceless-drop hold in emitDamageLine ----
rep("F3 sourceless drop hold",
    """        if let fromCode { line += "|[from] \\(fromCode)" }
""",
    """        // 出所の無い低下の保留: 分類できず (fromCode なし)、自分自身の
        // 技でもなく、直近 8 秒に他の個体の技も無く、この行動で既に
        // 被ダメ行が出てもいない低下は、プレート誤読 (隣枠の混入・数字
        // 融合) の疑いとして行を出さずに保留する。回復側は発生源なし
        // の行を出さないのに、被ダメ側だけ素通りする非対称の解消
        // (実例: 2026-11-22 battle_20261122_160927、技の対象でない
        // サーナイトへの 150/167、眠っている間の Sneasler 17/171)。
        // 天候等の小さい経過ダメージ (7 ポイント以下) は対象外。
        // 保留した値は冒頭の解消規則で、持続すれば次ターンに状態
        // 訂正として取り込まれる
        if fromCode == nil, effFrom - toPct > 7 {
            let selfLabel = "\\(slot): \\(speciesEn)"
            let recentOtherMove = !lastMoveLabel.isEmpty && lastMoveLabel != selfLabel
                && Date().timeIntervalSince(lastMoveMsgAt) < 8
            let alreadyDamaged = (damagedBySeq[actionSeq] ?? []).contains(selfLabel)
            if !recentOtherMove && !alreadyDamaged {
                suspectJump[plateName] = (toPct: toPct, turn: currentTurn)
                lastEmittedPct[plateName] = effFrom
                debugCapture(kind: "hp_drop_suspect", key: "hp_drop_suspect|\\(plateName)", rawText: "",
                             detail: ["slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "reason": "sourceless_drop"])
                if debugMode { print("[reader] 出所の無い低下を誤読の疑いとして保留しました: \\(slot): \\(speciesEn) \\(effFrom)% -> \\(toPct)%") }
                fflush(stdout)
                return true
            }
        }
        if let fromCode { line += "|[from] \\(fromCode)" }
""")

# ---- F4: send-out text evidence in the opponent send-out branch ----
rep("F4 kuridashita evidence",
    """        for e in findAllSpeciesJa(in: t) {
            if monStates["p2:\\(e.en)"] == nil { monStates["p2:\\(e.en)"] = MonState() }
        }
        return true
    }
""",
    """        for e in findAllSpeciesJa(in: t) {
            if monStates["p2:\\(e.en)"] == nil { monStates["p2:\\(e.en)"] = MonState() }
            // 途中交代の繰り出し文も文証拠として残す: フェーズ3の文
            // 証拠は ゆけっ 形式だけが対象で、相手の交代が「繰り出した」
            // 形式だとプレート回復後の確定加速が働かなかった (実例:
            // 2026-11-22 battle_20261122_160927、ゴリランダーの交代文
            // からプレート確定まで約 35 秒かかり、従属行が次の
            // セグメントへずれた)
            if logStarted, oppTeamSeen.contains(e.en),
               lastSlots["oppA"]?.speciesEn != e.en, lastSlots["oppB"]?.speciesEn != e.en {
                sendOutTextSeen["p2"] = (species: e.en, at: Date())
            }
        }
        return true
    }
""")

# ---- F5: parsePlate fallback max-fragment rejection ----
rep("F5 parsePlate fallback fragment",
    """            for t in texts + [joined] {
                if let r = parseMineHPText(t, knownMax: nil) {
                    hp = r.pct; hpCur = r.cur; hpMax = r.max
                    if let mx = r.max { noteBattleMaxRead(speciesEn: sp.en, readMax: mx, registeredMax: knownMax) }
                    break
                }
            }
""",
    """            for t in texts + [joined] {
                if let r = parseMineHPText(t, knownMax: nil) {
                    // 読みの最大値が、その種族で既に観測した現在 HP より
                    // 小さい読みはあり得ない (最大値の断片読み。実例:
                    // 2026-11-22 battle_20261122_160927、145 -> 45)。
                    // 現在値の記録がある場合はその読み自体を捨てる
                    if let mx = r.max, let curText = monStates["p1:\\(sp.en)"]?.hpText,
                       let cur = Int(curText.split(separator: "/").first ?? ""), mx < cur { continue }
                    hp = r.pct; hpCur = r.cur; hpMax = r.max
                    if let mx = r.max { noteBattleMaxRead(speciesEn: sp.en, readMax: mx, registeredMax: knownMax) }
                    break
                }
            }
""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
