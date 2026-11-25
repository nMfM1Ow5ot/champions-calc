#!/usr/bin/env python3
# reader.swift: battle_20261122_201011 fixes.
#  A. The post-faint suppression (185505) must not kill the fainted
#     mon's own still-owed KO damage line: when the KO drop was held
#     as a suspect first, the faint gets recorded before the held
#     line is released, and the suppression then erased the
#     100 -> 0 line itself (debug15/16). Exempt the case
#     toPct == 0 while the emitted baseline is still > 0.
#  B. healSource's Leftovers guess must not fire for a mon whose
#     item is already known to be consumed (itemLostActive): my
#     Incineroar's Grassy Terrain heal at T8 was attributed to
#     Leftovers after its Sitrus Berry had fired at T7 (applyEvent
#     records item reveals only for p2, so a p1 mon's own reveal
#     never reaches healSource's knownItem).
#  C. The miss-consistency guard also accepts this-turn switch-in
#     records and pending switch candidates on the target's side:
#     Rillaboom's T4 miss text was suppressed because the plate
#     occupant record still showed the previous mon.
#  D. The single-subject boost path must honor an explicit side
#     marker in the text over the mover-side heuristic: Parting
#     Shot's drops on the opposing Incineroar (same species as the
#     mover) were attributed to the mover itself.
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

# ---- A. post-faint exemption for the owed KO line ----
rep("A post-faint",
    """    if faintedSpecies.contains(key) {
        debugCapture(kind: "faint_guard", key: "post_faint_line:\\(key)", rawText: "",
                     detail: ["reason": "post_faint_suppressed", "slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "turn": currentTurn])
        return true
    }""",
    """    // ただし、その種族自身の「まだ出ていない ひんしに至る被ダメ行」
    // は抑制しない。被ダメが疑わしい跳びとして保留されている間に
    // ひんしが先に記録されると、保留解除後の行まで消えてしまい、
    // ひんし行だけが残る (実例: 2026-11-22 battle_20261122_201011、
    // ゴリランダーの 100 -> 0 が post_faint_suppressed で消えた)
    if faintedSpecies.contains(key),
       !(toPct == 0 && (lastEmittedPct[plateName] ?? effFrom) > 0) {
        debugCapture(kind: "faint_guard", key: "post_faint_line:\\(key)", rawText: "",
                     detail: ["reason": "post_faint_suppressed", "slot": slot, "species": speciesEn, "fromPct": effFrom, "toPct": toPct, "turn": currentTurn])
        return true
    }""")

# ---- B. no Leftovers guess for a consumed item ----
rep("B healSource",
    """        if logFieldTerrain == "Grassy" && grassyHealTurn[plateName] != currentTurn {
            grassyHealTurn[plateName] = currentTurn
            return ("Grassy Terrain", nil)
        }
        if knownItem == nil || knownItem == "たべのこし" { return ("item: Leftovers", "たべのこし") }
        return nil""",
    """        if logFieldTerrain == "Grassy" && grassyHealTurn[plateName] != currentTurn {
            grassyHealTurn[plateName] = currentTurn
            return ("Grassy Terrain", nil)
        }
        // 持ち物が消費済みと判明している個体に、たべのこし はあり
        // 得ない (実例: 2026-11-22 battle_20261122_201011、T7 に
        // オボンのみが発動した自軍ガオガエンのグラスフィールド
        // 回復が、T8 に たべのこし の判明行へ化けた。自軍の判明は
        // applyEvent が記録しないため knownItem が未判明のままに
        // なる経路の対策)
        if itemLostActive.contains(key) { return nil }
        if knownItem == nil || knownItem == "たべのこし" { return ("item: Leftovers", "たべのこし") }
        return nil""")

# ---- C. miss guard: this-turn switch-in / candidate evidence ----
rep("C miss guard",
    """            let missConsistent = (missTracked.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[missPn] == sp.en
                || lastSwitchIn["\\(side):\\(sp.en)"]?.slot == slot""",
    """            let missConsistent = (missTracked.map { sameSpeciesFamily($0, sp.en) } ?? false)
                || pendingSwitchSpecies[missPn] == sp.en
                || lastSwitchIn["\\(side):\\(sp.en)"]?.slot == slot
                // 交代直後でプレートの占有記録が追いついていない間は、
                // このターンの交代記録や交代候補の証拠でも通す
                // (実例: 2026-11-22 battle_20261122_201011、交代直後の
                // ゴリランダーへのミス文が、旧占有者の記録との不整合
                // として抑制された)
                || switchInTurn["\\(side):\\(sp.en)"] == currentTurn
                || (pendingSwitchCandidates[side == "p2" ? "oppA" : "mineA"]?[sp.en] != nil)
                || (pendingSwitchCandidates[side == "p2" ? "oppB" : "mineB"]?[sp.en] != nil)""")

# ---- D. explicit side marker beats the mover heuristic ----
rep("D boost side",
    """            var sSide = side
            let inOppF = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
            let inMineF = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en
            if inOppF && inMineF && lastMoveLabel.hasSuffix(": \\(sp.en)")
                && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
                sSide = lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }""",
    """            var sSide = side
            let inOppF = lastSlots["oppA"]?.speciesEn == sp.en || lastSlots["oppB"]?.speciesEn == sp.en
            let inMineF = lastSlots["mineA"]?.speciesEn == sp.en || lastSlots["mineB"]?.speciesEn == sp.en
            if (t.contains("相手の") || t.contains("あいての")) && inOppF {
                // 文中の明示の側マーカーは使用者の側の推定より優先する
                // (実例: 2026-11-22 battle_20261122_201011、すてゼリフ
                // の低下が、使用者と同種族の相手側ガオガエンに入る
                // ところ、使用者自身へ帰属した)
                sSide = "p2"
            } else if t.contains("味方の") && inMineF {
                sSide = "p1"
            } else if inOppF && inMineF && lastMoveLabel.hasSuffix(": \\(sp.en)")
                && Date().timeIntervalSince(lastMoveMsgAt) < 10 {
                sSide = lastMoveLabel.hasPrefix("p2") ? "p2" : "p1"
            }""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
