#!/usr/bin/env python3
# reader.swift: append a standalone crit event when a crit text is
# confirmed (option (i), user instruction via the log chat
# 2026-11-22). The in-place patch stays for unconsumed copies; the
# appended event is the path that reaches index-wise consumers.
import sys

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
src = open(PATH, encoding="utf-8").read()

OLD = """            if let idx = battleEvents.lastIndex(where: { ev in
                ev.contains("\\"k\\":\\"dmg\\"") && ev.contains("\\"def\\":\\"\\(jsonEscape(target))\\"")
                    && !ev.contains("\\"atk\\":\\"\\(jsonEscape(target))\\"") && ev.contains("\\"crit\\":false")
            }) {
                battleEvents[idx] = battleEvents[idx].replacingOccurrences(of: "\\"crit\\":false", with: "\\"crit\\":true")
            }
            emitLog("|-crit|\\(target)")"""

NEW = """            var critAtkJson = jsonEscape(lastMoveLabel)
            var critMoveJson = jsonEscape(lastMoveName)
            if let idx = battleEvents.lastIndex(where: { ev in
                ev.contains("\\"k\\":\\"dmg\\"") && ev.contains("\\"def\\":\\"\\(jsonEscape(target))\\"")
                    && !ev.contains("\\"atk\\":\\"\\(jsonEscape(target))\\"")
            }) {
                let ev = battleEvents[idx]
                if let r = ev.range(of: "\\"atk\\":\\""), let e = ev[r.upperBound...].firstIndex(of: "\\"") {
                    critAtkJson = String(ev[r.upperBound..<e])
                }
                if let r = ev.range(of: "\\"move\\":\\""), let e = ev[r.upperBound...].firstIndex(of: "\\"") {
                    critMoveJson = String(ev[r.upperBound..<e])
                }
                if ev.contains("\\"crit\\":false") {
                    battleEvents[idx] = ev.replacingOccurrences(of: "\\"crit\\":false", with: "\\"crit\\":true")
                }
            }
            // 急所の確定は独立イベントとしても末尾へ追加する。是正は
            // 既に消費された写しには届かない (UI はイベント列を
            // インデックス単位で一度だけ消費する) ため、後付けで
            // 証拠を届ける経路が要る (実例: 2026-11-22
            // battle_20261122_201011、急所 2 件とも消費済みで是正が
            // 届かず、エンジンに急所が伝わらなかった)
            if battleEvents.count < 600 {
                battleEvents.append("{\\"k\\":\\"crit\\",\\"turn\\":\\(currentTurn),\\"atk\\":\\"\\(critAtkJson)\\",\\"def\\":\\"\\(jsonEscape(target))\\",\\"move\\":\\"\\(critMoveJson)\\"}")
            }
            emitLog("|-crit|\\(target)")"""

c = src.count(OLD)
if c != 1:
    print(f"ABORT: anchor count = {c} (expected 1)")
    sys.exit(1)
src = src.replace(OLD, NEW, 1)
open(PATH, "w", encoding="utf-8").write(src)
print("OK: crit event append")
