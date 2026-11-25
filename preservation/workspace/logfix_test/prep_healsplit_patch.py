#!/usr/bin/env python3
# reader.swift: split a Sitrus-classified heal that also contains a
# Grassy Terrain heal into two lines (battle_20261122_201011 T7,
# user instruction via the log chat 2026-11-22; video-verified
# 46->96 Sitrus then 96->108 terrain, recorded as one +62 line).
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

OLD = """        var line = "|-heal|\\(slot): \\(speciesEn)|\\(hpText)"
        if let src { line += "|[from] \\(src.label)" }
        emitLog(line)"""

NEW = """        // オボンと分類された回復にグラッシーフィールドの回復が
        // 合算されている場合は 2 行に分ける。オボンの回復 (+最大の
        // 1/4) を超えた分が地形の回復量 (最大の 1/16) に一致し、
        // このターンの地形回復がまだ記録されていない場合に限る
        // (実例: 2026-11-22 battle_20261122_201011 ターン7、
        // 46 -> 96 (オボン) -> 108 (地形) の 2 イベントが +62 の
        // 1 行に合算された。動画の静定値で分離確認済み)
        var splitMidText: String? = nil
        if src?.label == "item: Sitrus Berry",
           logFieldTerrain == "Grassy Terrain" || logFieldTerrainJa == "グラッシーフィールド",
           grassyHealTurn[plateName] != currentTurn {
            let hpParts = hpText.split(separator: "/")
            if hpParts.count == 2,
               let curU = Int(hpParts[0].trimmingCharacters(in: .whitespaces)),
               let maxU = Int(hpParts[1].trimmingCharacters(in: .whitespaces)), maxU > 0 {
                let fromU = Int((Double(effFrom) / 100.0 * Double(maxU)).rounded())
                let berryAmt = maxU / 4
                let terrainAmt = curU - fromU - berryAmt
                let expectT = maxU / 16
                let tol = maxU == 100 ? 3 : 2
                if terrainAmt > 0 && abs(terrainAmt - expectT) <= tol {
                    splitMidText = "\\(fromU + berryAmt)/\\(maxU)"
                }
            }
        }
        if let mid = splitMidText {
            emitLog("|-heal|\\(slot): \\(speciesEn)|\\(mid)|[from] item: Sitrus Berry")
            emitLog("|-heal|\\(slot): \\(speciesEn)|\\(hpText)|[from] Grassy Terrain")
            grassyHealTurn[plateName] = currentTurn
        } else {
            var line = "|-heal|\\(slot): \\(speciesEn)|\\(hpText)"
            if let src { line += "|[from] \\(src.label)" }
            emitLog(line)
        }"""

c = src.count(OLD)
if c != 1:
    print(f"ABORT: anchor count = {c} (expected 1)")
    sys.exit(1)
src = src.replace(OLD, NEW, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: heal split")
