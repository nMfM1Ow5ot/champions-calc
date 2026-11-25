#!/usr/bin/env python3
# Harness update for the manual-start state reset round: FUNCS
# addition and T164 tests.
import sys

PATH = "/home/hatch/workspace/logfix_test/make_harness.py"
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

rep("'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment',",
    "'applyFlagControl', 'flagPhase', 'flagModeName', 'flagStateFragment', 'writeManualStartResetState',",
    "FUNCS")

TESTS = '''// ===== T164 (manual start state.json reset) =====
func stateJson164() -> [String: Any]? {
    guard let data = try? Data(contentsOf: outURL),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
    return obj
}
func clearState164() {
    try? FileManager.default.removeItem(at: outURL)
    lastWritten = ""
}
// a: 手動開始の時点で初期化した形が書き出される (applyFlagControl 経由)
resetAll()
clearState164()
logStarted = false
flagControlAdopted = true
flagStartSeqSeen = 0
flagEndSeqSeen = 0
previewTeamWritten = false
oppTeamSeen = []
applyFlagControl(mode: "manual", startSeq: 1, endSeq: 0)
if let obj = stateJson164() {
    check("T164a manual start writes the reset shape", (obj["oppReset"] as? Bool) == true && (obj["mine"] as? [Any])?.count == 0 && (obj["opps"] as? [Any])?.count == 0 && (obj["oppTeam"] as? [Any])?.count == 0 && (obj["battlePhase"] as? String) == "inBattle" && (obj["flagMode"] as? String) == "manual" && (obj["events"] as? [Any])?.count == 0 && (obj["battle"] as? String) == battleArchiveId)
} else {
    check("T164a manual start writes the reset shape", false)
}
// b: 同定済みの新しい試合の oppTeam と mineTeam は保持される
resetAll()
clearState164()
previewTeamWritten = true
oppTeamSeen = ["Milotic", "Staraptor", "Tyranitar", "Sinistcha", "Excadrill", "Gholdengo"]
minePreviewTeam = ["Venusaur", nil, nil, nil, nil, nil]
minePreviewDetails = [["species": "Venusaur"], [:], [:], [:], [:], [:]]
battleArchiveId = "20261123_120000"
writeManualStartResetState()
if let obj = stateJson164() {
    let team = (obj["oppTeam"] as? [Any])?.map { ($0 as? String) ?? "?" } ?? []
    let mineTeam = obj["mineTeam"] as? [Any] ?? []
    check("T164b identified teams are preserved", team == ["Milotic", "Staraptor", "Tyranitar", "Sinistcha", "Excadrill", "Gholdengo"] && mineTeam.count == 6 && (obj["oppReset"] as? Bool) == true)
} else {
    check("T164b identified teams are preserved", false)
}
// c: 自動モードの開始では初期化書き出しは起きない (既存の流れは不変)
resetAll()
clearState164()
flagControlAdopted = true
flagStartSeqSeen = 0
flagEndSeqSeen = 0
previewTeamWritten = false
applyFlagControl(mode: "auto", startSeq: 1, endSeq: 0)
check("T164c auto start writes no reset state", stateJson164() == nil)

'''
ANCHOR = '''out(failures == 0 ? "ALL PASS" : "\\(failures) FAILURES")'''
n = src.count(ANCHOR)
if n != 1:
    print(f"ABORT tests anchor: count = {n}")
    sys.exit(1)
src = src.replace(ANCHOR, TESTS + ANCHOR)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
