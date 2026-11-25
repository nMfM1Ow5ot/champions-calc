#!/usr/bin/env python3
# reader.swift: startup salvage fixes (user instruction via the
# comprehensive chat, battle_20261122_193243):
#  1. salvageLeftoverLogs re-saved battles that had ALREADY been
#     archived normally: its only duplicate guard compared the raw
#     leftover working file against the COMPLETED archive files
#     (header completion / HP unification applied), so any battle
#     whose archive differed from the raw text was salvaged again
#     at the next startup as battle_<id>_salvage_final. Recover the
#     battle id first and skip the salvage when a final archive for
#     that id already exists.
#  2. The startup salvage no longer prints the saved line
#     (archiveBattleLogs gains a quiet flag; the salvage caller
#     passes quiet: true). Normal battle-end archives still print.
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

# ---- 1. quiet flag on archiveBattleLogs ----
rep("signature",
    """func archiveBattleLogs(final: Bool, protocolLines: [String], displayLines: [String], id: String) {""",
    """func archiveBattleLogs(final: Bool, protocolLines: [String], displayLines: [String], id: String, quiet: Bool = false) {""")

rep("print gate",
    """    try? dispText.write(to: logsDirURL.appendingPathComponent(base + ".log"), atomically: true, encoding: .utf8)
    print("[log] 試合ログを保存しました: logs/\\(base).log / logs/\\(base)_protocol.log")
    fflush(stdout)""",
    """    try? dispText.write(to: logsDirURL.appendingPathComponent(base + ".log"), atomically: true, encoding: .utf8)
    if !quiet {
        print("[log] 試合ログを保存しました: logs/\\(base).log / logs/\\(base)_protocol.log")
        fflush(stdout)
    }""")

# ---- 2. salvage: id recovery first + final-archive existence guard ----
old_salvage = """    guard lines.count >= 5, lines.contains("|start") else { return }
    // 同じ内容が保存済みなら二重に作らない
    if let names = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) {
        for name in names where name.hasSuffix("_protocol.log") {
            if let saved = try? String(contentsOf: logsDirURL.appendingPathComponent(name), encoding: .utf8), saved == proto {
                return
            }
        }
    }
    var stamp = battleStamp()
    if let attrs = try? FileManager.default.attributesOfItem(atPath: protocolLogURL.path),
       let mtime = attrs[.modificationDate] as? Date {
        stamp = battleStamp(for: mtime)
    }
    // 元の試合 ID が残留 state.json から復元できれば、そちらを優先する。
    // デバッグ一式 (preview_id を含む) は元の試合 ID で保存されている
    // ため、更新日時のスタンプで救済すると serve.py 側で同じ試合として
    // 束ねられず、一式が備考ゲートに残り続けて届かなくなる
    if let raw = try? String(contentsOf: outURL, encoding: .utf8),
       let data = raw.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let bid = obj["battle"] as? String,
       bid.count == 15, bid.allSatisfy({ $0.isNumber || $0 == "_" }) {
        stamp = bid
    }
    let disp = (try? String(contentsOf: battleLogURL, encoding: .utf8)) ?? ""
    let dispLines = disp.isEmpty ? [] : disp.split(separator: "\\n").map(String.init)
    archiveBattleLogs(final: lines.contains(where: { $0.hasPrefix("|win|") }),
                      protocolLines: lines, displayLines: dispLines, id: stamp + "_salvage")"""

new_salvage = """    guard lines.count >= 5, lines.contains("|start") else { return }
    var stamp = battleStamp()
    if let attrs = try? FileManager.default.attributesOfItem(atPath: protocolLogURL.path),
       let mtime = attrs[.modificationDate] as? Date {
        stamp = battleStamp(for: mtime)
    }
    // 元の試合 ID が残留 state.json から復元できれば、そちらを優先する。
    // デバッグ一式 (preview_id を含む) は元の試合 ID で保存されている
    // ため、更新日時のスタンプで救済すると serve.py 側で同じ試合として
    // 束ねられず、一式が備考ゲートに残り続けて届かなくなる
    if let raw = try? String(contentsOf: outURL, encoding: .utf8),
       let data = raw.data(using: .utf8),
       let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let bid = obj["battle"] as? String,
       bid.count == 15, bid.allSatisfy({ $0.isNumber || $0 == "_" }) {
        stamp = bid
    }
    // その試合の確定版が既に保存済みなら、救済はしない。保存済み
    // ファイルはヘッダー補完や HP 表記の統一を経た内容で、残留した
    // 作業ファイル (未補完) とは一致しないため、内容の一致だけで
    // 判定すると通常どおり保存済みの試合まで二重に救済してしまう
    // (実例: 2026-11-22 battle_20261122_193243、次回起動時に
    // battle_..._salvage_final が改めて保存された)
    if FileManager.default.fileExists(atPath: logsDirURL.appendingPathComponent("battle_\\(stamp)_final_protocol.log").path) {
        return
    }
    // 同じ内容が保存済みなら二重に作らない
    if let names = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) {
        for name in names where name.hasSuffix("_protocol.log") {
            if let saved = try? String(contentsOf: logsDirURL.appendingPathComponent(name), encoding: .utf8), saved == proto {
                return
            }
        }
    }
    let disp = (try? String(contentsOf: battleLogURL, encoding: .utf8)) ?? ""
    let dispLines = disp.isEmpty ? [] : disp.split(separator: "\\n").map(String.init)
    archiveBattleLogs(final: lines.contains(where: { $0.hasPrefix("|win|") }),
                      protocolLines: lines, displayLines: dispLines, id: stamp + "_salvage", quiet: true)"""

rep("salvage reorder + guard", old_salvage, new_salvage)

open(PATH, "w", encoding="utf-8").write(src)
print("ALL EDITS APPLIED")
