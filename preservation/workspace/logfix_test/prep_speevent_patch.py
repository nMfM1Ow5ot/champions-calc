#!/usr/bin/env python3
# reader.swift: speed-order evidence for pre-move KOs (spe events).
# Log-analysis chat instruction (user's explicit instruction),
# battle_20261122_181745 T1: Archaludon's Steel Beam KO'd Mega
# Gardevoir before it moved; no mv pair could be built, so the
# Scarf-proving order evidence never reached the estimator.
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

rep("call site",
    """        if let fromCode { line += "|[from] \\(fromCode)" }
        emitLog(line)
        recordDamageEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, hpText: hpText)""",
    """        if let fromCode { line += "|[from] \\(fromCode)" }
        emitLog(line)
        recordDamageEvent(slot: slot, key: key, speciesEn: speciesEn, fromPct: effFrom, toPct: toPct, hpText: hpText,
                          directMove: fromCode == nil)""")

rep("signature",
    """func recordDamageEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String) {""",
    """func recordDamageEvent(slot: String, key: String, speciesEn: String, fromPct: Int, toPct: Int, hpText: String, directMove: Bool = false) {""")

rep("spe emission",
    """    if let idx = supersedeIdx {
        battleEvents[idx] = ev
    } else {
        battleEvents.append(ev)
        lastDmgEventPrevExact[key] = prevExact ?? []
    }
}""",
    """    if let idx = supersedeIdx {
        battleEvents[idx] = ev
    } else {
        battleEvents.append(ev)
        lastDmgEventPrevExact[key] = prevExact ?? []
    }
    // 行動前に倒れた個体への先行証拠 (spe イベント): この被ダメが
    // 技による直接の KO で、倒れた側がそのターンまだ技も交代も
    // していない場合、攻撃側がその個体より先に行動したことが
    // 確定する。実行された技同士のペア (mv イベント) からは構造的
    // に作れない行動順証拠のため、専用の形で残す。推定側はこれを
    // mv ペアと同種の行動順の観測として扱う。適格性の残り (倒れた
    // 側が優先度技を選んでいた可能性、KO 技自体の優先度) は技
    // データを持つ推定側の判定に委ね、ここでは事実だけを記録する
    // (実例: 2026-11-22 battle_20261122_181745 ターン 1、
    // Archaludon の Steel Beam で行動前の Mega Gardevoir が倒れ、
    // こだわりスカーフ確定の証拠が生成されなかった)
    if directMove, toPct == 0, battleEvents.count < 600 {
        let fastLabel = lastMoveLabel
        let slowLabel = "\\(slot): \\(speciesEn)"
        let slowMoved = battleEvents.contains {
            $0.contains("\\"k\\":\\"mv\\"") && $0.contains("\\"turn\\":\\(currentTurn)")
                && $0.contains("\\"label\\":\\"\\(jsonEscape(slowLabel))\\"")
        }
        var slowEntered = false
        let turnIdx = battleLog.lastIndex(of: "|turn|\\(currentTurn)")
            ?? battleLog.lastIndex(where: { $0.hasPrefix("|turn|") })
        if let tIdx = turnIdx {
            for l in battleLog[(tIdx + 1)...]
            where l.hasPrefix("|switch|\\(slowLabel)|") || l.hasPrefix("|drag|\\(slowLabel)|") {
                slowEntered = true
                break
            }
        }
        if !slowMoved && !slowEntered {
            var sev = "{\\"k\\":\\"spe\\",\\"turn\\":\\(currentTurn),\\"fast\\":\\"\\(jsonEscape(fastLabel))\\",\\"slow\\":\\"\\(jsonEscape(slowLabel))\\",\\"move\\":\\"\\(jsonEscape(lastMoveName))\\""
            sev += ",\\"fastB\\":\\(boostsJson(atkKey)),\\"slowB\\":\\(boostsJson(key))"
            sev += ",\\"fastMega\\":\\"\\(jsonEscape(monStates[atkKey]?.megaSpecies ?? ""))\\",\\"slowMega\\":\\"\\(jsonEscape(monStates[key]?.megaSpecies ?? ""))\\""
            sev += "}"
            if let idx = battleEvents.lastIndex(where: {
                $0.contains("\\"k\\":\\"spe\\"") && $0.contains("\\"turn\\":\\(currentTurn)")
                    && $0.contains("\\"slow\\":\\"\\(jsonEscape(slowLabel))\\"")
            }) {
                battleEvents[idx] = sev
            } else {
                battleEvents.append(sev)
            }
        }
    }
}""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
