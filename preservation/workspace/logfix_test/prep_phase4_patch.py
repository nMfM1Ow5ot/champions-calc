#!/usr/bin/env python3
# Phase 4 (turn side): dual-channel turn numbers.
# P1: turn-0 guard fires only on |move| lines (the proven 091721 +1 cause)
# P2: lastRoundEventAt + quiet gate on the detector's instant path
# P3: log-screen channel as a cross-check with turn_disagree evidence
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

rep("P1 turn-0 guard move-only",
    "            if currentTurn == 0 && !roundEventSeen { guardN = 1 }\n",
    """            // ターン0 (開幕区間) でターン行を生むのは技行の初出だけに
            // する: 入場効果のラウンド行 (いかくの低下行・設置行など)
            // はターン開始の証拠にならない。これらで |turn|1 を先に
            // 出すと、正規のコマンドフェーズ検出が第1ターンを 2 に
            // 進めて以後全ターンが +1 になる (実例: 2026-11-22
            // battle_20261122_091721、debug02 の挿入が発端。フェーズ4)
            if currentTurn == 0 && !roundEventSeen && mover != nil { guardN = 1 }
""")

rep("P2a lastRoundEventAt global",
    "var suppressNextDetectorTurn = false\n",
    "var suppressNextDetectorTurn = false\n"
    "var lastRoundEventAt: Date? = nil                 // 最後にラウンド行を出した時刻 (ターン検出の静穏判定用、フェーズ4)\n")

rep("P2b lastRoundEventAt set",
    "            roundEventSeen = true\n",
    "            roundEventSeen = true\n            lastRoundEventAt = Date()\n")

rep("P2c detector quiet gate",
    "    if platesReady && ((expectedPlates >= 4 && allSettled) || turnRawFrames >= 6) {\n",
    """    // 即時経路 (プレート確定) は、最後のラウンド行から 2.5 秒以上の
    // 静穏も条件にする: 解決フェーズの合間の一瞬の揃いで誤発火すると
    // ターン番号が通しでずれる (フェーズ4)。生フレーム経路は 6 フレーム
    // 連続の揃い自体が時間の裏付けになるため従来どおり
    let turnQuietOK = lastRoundEventAt.map { Date().timeIntervalSince($0) >= 2.5 } ?? true
    if platesReady && ((expectedPlates >= 4 && allSettled && turnQuietOK) || turnRawFrames >= 6) {
""")

rep("P3 log screen cross-check",
    """    if tn > currentTurn {
        currentTurn = tn
        emitLog("|turn|\\(tn)")
        recordTurnEvidence(turn: tn, path: "log_screen", image: image, extra: ["chips": chipHits.count])
    }
""",
    """    if tn > currentTurn {
        // 文面系統が数え上げより先行 = コマンドフェーズの取りこぼし。
        // 回復として追随し、不一致は証拠に残す (フェーズ4: 二系統照合)
        debugCapture(kind: "turn_disagree", key: "turn_disagree:\\(tn):\\(currentTurn)", rawText: "",
                     detail: ["textTurn": tn, "countTurn": currentTurn, "direction": "count_behind", "chips": chipHits.count],
                     image: image)
        currentTurn = tn
        emitLog("|turn|\\(tn)")
        recordTurnEvidence(turn: tn, path: "log_screen", image: image, extra: ["chips": chipHits.count])
    } else if tn < currentTurn && !(tn == currentTurn - 1 && !roundEventSeen) {
        // 数え上げが文面より先行している疑い。出力済みの行は変えられ
        // ないため番号は戻さず、証拠だけ残す。コマンドフェーズ中に
        // 見出しがまだ無いだけの遅れ (tn == currentTurn - 1 かつ
        // 今ターン未行動) は正常として記録しない
        debugCapture(kind: "turn_disagree", key: "turn_disagree:\\(tn):\\(currentTurn)", rawText: "",
                     detail: ["textTurn": tn, "countTurn": currentTurn, "direction": "count_ahead", "chips": chipHits.count],
                     image: image)
    }
""")

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
