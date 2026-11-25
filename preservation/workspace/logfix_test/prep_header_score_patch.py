#!/usr/bin/env python3
# reader.swift: evidence-based header completion removal.
# completeArchiveHeader used to drop the LAST unused declared
# species when additions overflowed the 6 slots; in
# battle_20261122_185505 that dropped Kommo-o (correctly
# identified, best score 0.332) while keeping lower-scored
# misidentifications. Snapshot the preview vote scores at battle
# start and remove the lowest-scored unused species instead.
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

rep("global",
    """var headerOppTeam: [String] = []          // ログ開始時にヘッダーへ書いた相手6体 (開始時点の控え)""",
    """var headerOppTeam: [String] = []          // ログ開始時にヘッダーへ書いた相手6体 (開始時点の控え)
var headerIdScores: [String: Double] = [:]   // "p2:種族" -> 見せ合い同定のベストスコア (開始時点の控え。ヘッダー補完の削除候補の優先順位に使う)""")

rep("reset clears scores",
    """    headerOppTeam = []""",
    """    headerOppTeam = []
    headerIdScores = [:]""")

rep("snapshot at battle start",
    """    headerOppTeam = oppTeamSeen""",
    """    headerOppTeam = oppTeamSeen
    // 見せ合い同定の票スコアを試合開始時点のまま控える (証拠は
    // 次の試合の同定で上書きされるため、アーカイブ時点では使えない)
    headerIdScores = [:]
    for slotVotes in previewEvidenceVotes {
        for entry in slotVotes {
            if let sp = entry["species"] as? String, let best = entry["best"] as? Double {
                let k = "p2:\\(sp)"
                headerIdScores[k] = max(headerIdScores[k] ?? -1, best)
            }
        }
    }""")

rep("signature",
    """func completeArchiveHeader(protocolLines: [String], displayLines: [String]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {""",
    """func completeArchiveHeader(protocolLines: [String], displayLines: [String], idScores: [String: Double] = [:]) -> (protocolLines: [String], displayLines: [String], added: [String], removed: [String]) {""")

rep("removal by score",
    """            let removeCount = min(unused.count, declared.count + missing.count - 6)
            if removeCount > 0 {
                let removing = Array(unused.suffix(removeCount))""",
    """            let removeCount = min(unused.count, declared.count + missing.count - 6)
            if removeCount > 0 {
                // 削除候補は同定スコアの低い順に選ぶ (スコアが無い
                // 種族は最後尾扱い、同点は宣言の後ろのものから)。
                // 位置だけで末尾から落とすと、正しく同定された
                // 種族が誤同定より先に落ちる (実例: 2026-11-22
                // battle_20261122_185505、Kommo-o (スコア 0.332) が
                // 落ち、0.126 の Slowking-Galar が残った)
                let removing = Array(unused.enumerated().sorted { a, b in
                    let sa = idScores["\\(side):\\(a.element)"] ?? .infinity
                    let sb = idScores["\\(side):\\(b.element)"] ?? .infinity
                    if sa != sb { return sa < sb }
                    return a.offset > b.offset
                }.prefix(removeCount).map { $0.element })""")

rep("call site passes scores",
    """    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines)""",
    """    let completed = completeArchiveHeader(protocolLines: protocolLines, displayLines: displayLines, idScores: headerIdScores)""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
