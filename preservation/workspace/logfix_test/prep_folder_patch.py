#!/usr/bin/env python3
# reader.swift patch: per-battle folders under logs/. Every file of
# one battle goes into logs/battle_<id>/; preview tests into
# logs/preview_test_<stamp>/. Readers check the folder first and
# the legacy flat layout second. User instruction via the
# comprehensive chat, 2026-11-23.
import re, sys, datetime

PATH = "/home/hatch/workspace/champions_calc/reader.swift"
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

# F1: helper next to logsDirURL
rep('''let logsDirURL = scriptDir.appendingPathComponent("logs")''',
    '''let logsDirURL = scriptDir.appendingPathComponent("logs")

// 1 試合分のファイルは logs/battle_<id>/ フォルダにまとめる
// (2026-11-23、ユーザーの指示)。フォルダを作って返す
func battleDirURL(_ id: String) -> URL {
    let dir = logsDirURL.appendingPathComponent("battle_\\(id)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}''',
    "F1 helper")

# F2: obs writer
rep('''    let url = logsDirURL.appendingPathComponent("battle_\\(battleArchiveId)_obs.jsonl")''',
    '''    let url = battleDirURL(battleArchiveId).appendingPathComponent("battle_\\(battleArchiveId)_obs.jsonl")''',
    "F2 obs")

# F3: paddle writer
rep('''    let url = logsDirURL.appendingPathComponent("battle_\\(paddleBattleKey)_paddle.jsonl")''',
    '''    let url = battleDirURL(paddleBattleKey).appendingPathComponent("battle_\\(paddleBattleKey)_paddle.jsonl")''',
    "F3 paddle")

# F4: states resume read (folder first, legacy flat second)
rep('''            let url = scriptDir.appendingPathComponent("logs/battle_\\(key)_states.json")
            if let data = try? Data(contentsOf: url),''',
    '''            let url = battleDirURL(key).appendingPathComponent("battle_\\(key)_states.json")
            let legacy = scriptDir.appendingPathComponent("logs/battle_\\(key)_states.json")
            if let data = (try? Data(contentsOf: url)) ?? (try? Data(contentsOf: legacy)),''',
    "F4 states read")

# F5: states write
rep('''    let dir = scriptDir.appendingPathComponent("logs")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: nil)
    try? data.write(to: dir.appendingPathComponent("battle_\\(key)_states.json"))''',
    '''    try? data.write(to: battleDirURL(key).appendingPathComponent("battle_\\(key)_states.json"))''',
    "F5 states write")

# F6: frame_skipped evidence
rep('''        let base = String(format: "battle_%@_debug%02d", battleArchiveId, seqNo)
        try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
        if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? data.write(to: logsDirURL.appendingPathComponent(base + ".jpg"))''',
    '''        let base = String(format: "battle_%@_debug%02d", battleArchiveId, seqNo)
        let dir = battleDirURL(battleArchiveId)
        if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]) {
            try? data.write(to: dir.appendingPathComponent(base + ".jpg"))''',
    "F6a skipped jpg")
rep('''                try? d.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)''',
    '''                try? d.write(to: dir.appendingPathComponent(base + ".json"), options: .atomic)''',
    "F6b skipped json")

# F7: archiveBattleLogs writes into the battle folder
rep('''    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
    let base = "battle_\\(id)_\\(final ? "final" : "interrupted")"
    let protoText = completed.protocolLines.joined(separator: "\\n") + "\\n"
    let dispText = completed.displayLines.joined(separator: "\\n") + "\\n"
    try? protoText.write(to: logsDirURL.appendingPathComponent(base + "_protocol.log"), atomically: true, encoding: .utf8)
    try? dispText.write(to: logsDirURL.appendingPathComponent(base + ".log"), atomically: true, encoding: .utf8)''',
    '''    let dir = battleDirURL(id)
    let base = "battle_\\(id)_\\(final ? "final" : "interrupted")"
    let protoText = completed.protocolLines.joined(separator: "\\n") + "\\n"
    let dispText = completed.displayLines.joined(separator: "\\n") + "\\n"
    try? protoText.write(to: dir.appendingPathComponent(base + "_protocol.log"), atomically: true, encoding: .utf8)
    try? dispText.write(to: dir.appendingPathComponent(base + ".log"), atomically: true, encoding: .utf8)''',
    "F7 archive writes")
rep('''        print("[log] 試合ログを保存しました: logs/\\(base).log / logs/\\(base)_protocol.log")''',
    '''        print("[log] 試合ログを保存しました: logs/battle_\\(id)/\\(base).log / logs/battle_\\(id)/\\(base)_protocol.log")''',
    "F7b archive message")

# F8: stale-draft removal looks in the folder and the legacy layout
rep('''        for suffix in ["_interrupted.log", "_interrupted_protocol.log"] {
            try? FileManager.default.removeItem(at: logsDirURL.appendingPathComponent("battle_\\(id)\\(suffix)"))
        }''',
    '''        for suffix in ["_interrupted.log", "_interrupted_protocol.log"] {
            try? FileManager.default.removeItem(at: battleDirURL(id).appendingPathComponent("battle_\\(id)\\(suffix)"))
            try? FileManager.default.removeItem(at: logsDirURL.appendingPathComponent("battle_\\(id)\\(suffix)"))
        }''',
    "F8 stale removal")

# F9: debugCapture writes into the battle folder
rep('''    let base = String(format: "battle_%@_debug%02d", id, seq)
    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)''',
    '''    let base = String(format: "battle_%@_debug%02d", id, seq)
    let dir = battleDirURL(id)''',
    "F9a debug dir")
rep('''        let url = logsDirURL.appendingPathComponent(base + ".jpg")''',
    '''        let url = dir.appendingPathComponent(base + ".jpg")''',
    "F9b debug jpg")
rep('''        try? data.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)
    }
    if debugMode { print("[debug] デバッグ情報を保存しました: logs/\\(base) (\\(kind))") }''',
    '''        try? data.write(to: dir.appendingPathComponent(base + ".json"), options: .atomic)
    }
    if debugMode { print("[debug] デバッグ情報を保存しました: logs/battle_\\(id)/\\(base) (\\(kind))") }''',
    "F9c debug json + message")

# F10: 14-day cleanup walks the per-battle folders too
rep('''    for name in names where name.contains("_debug") {
        let url = logsDirURL.appendingPathComponent(name)
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date, mtime < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }''',
    '''    var targets: [URL] = []
    for name in names {
        let url = logsDirURL.appendingPathComponent(name)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
            if let subs = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                for sub in subs where sub.contains("_debug") { targets.append(url.appendingPathComponent(sub)) }
            }
        } else if name.contains("_debug") {
            targets.append(url)
        }
    }
    for url in targets {
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let mtime = attrs[.modificationDate] as? Date, mtime < cutoff {
            try? FileManager.default.removeItem(at: url)
        }
    }''',
    "F10 cleanup walk")

# F11: salvage checks look in the folder and the legacy layout
rep('''    if FileManager.default.fileExists(atPath: logsDirURL.appendingPathComponent("battle_\\(stamp)_final_protocol.log").path) {
        return
    }''',
    '''    if FileManager.default.fileExists(atPath: battleDirURL(stamp).appendingPathComponent("battle_\\(stamp)_final_protocol.log").path)
        || FileManager.default.fileExists(atPath: logsDirURL.appendingPathComponent("battle_\\(stamp)_final_protocol.log").path) {
        return
    }''',
    "F11a salvage final check")
rep('''    if let names = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) {
        for name in names where name.hasSuffix("_protocol.log") {
            if let saved = try? String(contentsOf: logsDirURL.appendingPathComponent(name), encoding: .utf8), saved == proto {
                return
            }
        }
    }''',
    '''    var scanDirs: [URL] = [logsDirURL]
    if let rootNames = try? FileManager.default.contentsOfDirectory(atPath: logsDirURL.path) {
        for name in rootNames {
            let u = logsDirURL.appendingPathComponent(name)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue { scanDirs.append(u) }
        }
    }
    for dir in scanDirs {
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for name in names where name.hasSuffix("_protocol.log") {
                if let saved = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8), saved == proto {
                    return
                }
            }
        }
    }''',
    "F11b salvage dedupe scan")

# F12: preview test files go into their own folder
rep('''    let base = "preview_test_\\(battleStamp())"
    try? FileManager.default.createDirectory(at: logsDirURL, withIntermediateDirectories: true)
    var imageFile = ""
    if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
       (try? data.write(to: logsDirURL.appendingPathComponent(base + ".jpg"))) != nil {''',
    '''    let base = "preview_test_\\(battleStamp())"
    let dir = logsDirURL.appendingPathComponent(base)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    var imageFile = ""
    if let data = NSBitmapImageRep(cgImage: img).representation(using: .jpeg, properties: [.compressionFactor: 0.7]),
       (try? data.write(to: dir.appendingPathComponent(base + ".jpg"))) != nil {''',
    "F12a preview jpg")
rep('''        try? data.write(to: logsDirURL.appendingPathComponent(base + ".json"), options: .atomic)
    }
    print("[preview-test] 見せ合いテストを保存しました: logs/\\(base) (同定: \\(result != nil ? "実施" : "失敗"))")''',
    '''        try? data.write(to: dir.appendingPathComponent(base + ".json"), options: .atomic)
    }
    print("[preview-test] 見せ合いテストを保存しました: logs/\\(base)/ (同定: \\(result != nil ? "実施" : "失敗"))")''',
    "F12b preview json + message")

# F13: build stamp
stamp = datetime.datetime.now(datetime.timezone(datetime.timedelta(hours=9))).strftime("%Y%m%d_%H%M")
src2, cnt = re.subn(r'let readerBuild = "\d{8}_\d{4}"', f'let readerBuild = "{stamp}"', src, count=1)
if cnt != 1:
    print("ABORT stamp")
    sys.exit(1)
src = src2
print(f"OK F13 stamp -> {stamp}")

if src == orig:
    print("ABORT: no changes")
    sys.exit(1)
open(PATH, "w", encoding="utf-8").write(src)
print("WROTE", PATH)
