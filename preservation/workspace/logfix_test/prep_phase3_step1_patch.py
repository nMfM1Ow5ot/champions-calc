#!/usr/bin/env python3
# Phase 3 step 1: switch candidates as intervals (evidence store).
# pendingSwitchSpecies/Count/Since remain as the "leader view" for all
# existing readers; pendingSwitchCandidates keeps per-species evidence
# (count / firstSeen / lastSeen) so alternating reads no longer reset it.
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

# ---------------------------------------------------------------- G1: global
rep("G1 candidates global",
    "var pendingSwitchSince: [String: Date] = [:]",
    "var pendingSwitchSince: [String: Date] = [:]\n"
    "var pendingSwitchCandidates: [String: [String: (count: Int, firstSeen: Date, lastSeen: Date)]] = [:]  // プレート名 -> 候補種族 -> 交代候補の証拠 (フェーズ3: 区間管理。pendingSwitch* はそのリーダー表示)")

# ---------------------------------------------------------------- G2: reset
rep("G2 reset",
    "    pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]\n",
    "    pendingSwitchSpecies = [:]; pendingSwitchCount = [:]; pendingSwitchSince = [:]; pendingSwitchCandidates = [:]\n")

# ---------------------------------------------------------------- G3: candidate update in the species-change branch
rep("G3 candidate update",
    """            if pendingSwitchSpecies[plate.name] == s.speciesEn {
                pendingSwitchCount[plate.name] = (pendingSwitchCount[plate.name] ?? 1) + 1
            } else {
                pendingSwitchSpecies[plate.name] = s.speciesEn
                pendingSwitchCount[plate.name] = 1
                pendingSwitchSince[plate.name] = Date()
            }
""",
    """            // 交代候補は区間で管理する (フェーズ3): 候補ごとの証拠
            // (回数・初出・最終観測) を保持し、別候補や占有者が間に
            // 読まれても証拠は消えない。最終観測から 3 秒を超えた候補は
            // 期限切れとして落とす。pendingSwitch* は現在のリーダー
            // 候補の表示として同期する (既存の読み手はそのまま使う)
            let psNow = Date()
            var psCands = pendingSwitchCandidates[plate.name] ?? [:]
            psCands = psCands.filter { psNow.timeIntervalSince($0.value.lastSeen) <= 3 }
            var psCand = psCands[s.speciesEn] ?? (count: 0, firstSeen: psNow, lastSeen: psNow)
            psCand.count += 1
            psCand.lastSeen = psNow
            psCands[s.speciesEn] = psCand
            pendingSwitchCandidates[plate.name] = psCands
            pendingSwitchSpecies[plate.name] = s.speciesEn
            pendingSwitchCount[plate.name] = psCand.count
            pendingSwitchSince[plate.name] = psCand.firstSeen
""")

# ---------------------------------------------------------------- G4: clear the store where the leader is cleared (confirm / guard-drop)
rep("G4 clear on resolve",
    """                let pendingSwitchAge = pendingSwitchSince[plate.name].map { Date().timeIntervalSince($0) } ?? 0
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
""",
    """                let pendingSwitchAge = pendingSwitchSince[plate.name].map { Date().timeIntervalSince($0) } ?? 0
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
                pendingSwitchCandidates[plate.name] = nil
""")

# ---------------------------------------------------------------- G5: slot-swap clears
rep("G5 slot swap clear",
    "            pendingSwitchSpecies[p] = nil; pendingSwitchCount[p] = nil; pendingSwitchSince[p] = nil\n",
    "            pendingSwitchSpecies[p] = nil; pendingSwitchCount[p] = nil; pendingSwitchSince[p] = nil; pendingSwitchCandidates[p] = nil\n")

# ---------------------------------------------------------------- G6: occupant re-read = expiry maintenance, not a wipe
rep("G6 occupant expiry",
    """        } else {
            pendingSwitchSpecies[plate.name] = nil
            pendingSwitchCount[plate.name] = nil
            pendingSwitchSince[plate.name] = nil
""",
    """        } else {
            // 占有者の再読みでは交代候補を即消去しない (フェーズ3):
            // 候補は最終観測からの期限 (3 秒) で自然に落ち、リーダーが
            // 期限切れになったら残りの最新候補へ表示を引き継ぐ
            let occNow = Date()
            if var occCands = pendingSwitchCandidates[plate.name] {
                occCands = occCands.filter { occNow.timeIntervalSince($0.value.lastSeen) <= 3 }
                pendingSwitchCandidates[plate.name] = occCands.isEmpty ? nil : occCands
                if occCands.isEmpty {
                    pendingSwitchSpecies[plate.name] = nil
                    pendingSwitchCount[plate.name] = nil
                    pendingSwitchSince[plate.name] = nil
                } else if let cur = pendingSwitchSpecies[plate.name], occCands[cur] == nil,
                          let lead = occCands.max(by: { $0.value.lastSeen < $1.value.lastSeen }) {
                    pendingSwitchSpecies[plate.name] = lead.key
                    pendingSwitchCount[plate.name] = lead.value.count
                    pendingSwitchSince[plate.name] = lead.value.firstSeen
                }
            } else {
                pendingSwitchSpecies[plate.name] = nil
                pendingSwitchCount[plate.name] = nil
                pendingSwitchSince[plate.name] = nil
            }
""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
