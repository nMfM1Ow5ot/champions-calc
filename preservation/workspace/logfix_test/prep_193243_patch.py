#!/usr/bin/env python3
# reader.swift fixes for battle_20261122_193243:
#  A (chu2): the effectiveness branch missed the immune text form
#     "<target>には こうかは ないようだ…" (hiragana こうかは and a
#     trailing …), so Zap Cannon's no-effect result produced no
#     |-immune| line and fell into default attribution.
#  B (high-2): the recoil text ("反動による ダメージを受けた") was
#     consumed without recording a source, and the recoil's small
#     drop was then silently absorbed by the correction rule, so
#     Wood Hammer's recoil produced no damage line at all. Record
#     the pending source from the recoil text, and never silently
#     absorb a drop that has a pending source.
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

# ---- A: effectiveness branch entry condition ----
rep("A immune entry",
    """    if t.contains("効果は") || (!kind.isEmpty && (t.hasSuffix("だ！") || t.hasSuffix("だ!") || t.hasSuffix("だ"))) {""",
    """    if t.contains("効果は") || t.contains("こうかは") || (!kind.isEmpty && (t.hasSuffix("だ！") || t.hasSuffix("だ!") || t.hasSuffix("だ") || kind == "immune")) {""")

# ---- B1: recoil text records its source ----
rep("B1 recoil text",
    """    if t.contains("ダメージを受けた") {
        for (ja, code) in [("毒", "psn"), ("やけど", "brn"), ("砂嵐", "sandstorm"), ("あられ", "hail")] where t.contains(ja) {""",
    """    if t.contains("ダメージを受けた") {
        // 技の反動: 直前の技の使用者自身の文なら、発生源を控えて
        // 反動の低下行に [from] を付ける (実例: 2026-11-22
        // battle_20261122_193243、ウッドハンマーの反動文が消費
        // されるだけで、低下が訂正吸収されて行が残らなかった)
        if t.contains("反動"), lastMoveLabel == "\\(slot): \\(sp.en)", !lastMoveName.isEmpty {
            pendingStatusFrom[key] = ("move: \\(lastMoveName)", Date())
            return true
        }
        for (ja, code) in [("毒", "psn"), ("やけど", "brn"), ("砂嵐", "sandstorm"), ("あられ", "hail")] where t.contains(ja) {""")

# ---- B2: correction absorption yields to a pending source ----
rep("B2 correction guard",
    """        if toPct != 0, effFrom - toPct <= 3, let lt = prevDamageAt, Date().timeIntervalSince(lt) >= 10,
           prevDamageSeq != actionSeq, Date().timeIntervalSince(lastMoveMsgAt) >= 5 {""",
    """        if toPct != 0, effFrom - toPct <= 3, let lt = prevDamageAt, Date().timeIntervalSince(lt) >= 10,
           prevDamageSeq != actionSeq, Date().timeIntervalSince(lastMoveMsgAt) >= 5,
           pendingStatusFrom[key] == nil {""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
