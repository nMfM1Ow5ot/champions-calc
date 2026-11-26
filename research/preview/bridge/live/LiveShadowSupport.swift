// Research-only. Concatenate into the same file as the pinned PreviewShadowBridge.
import Foundation

struct ShadowSnapshot {
    let data: Data
    let key: String
    let ageMS: Double
}

// Read-only snapshots. No changes to the producer's files or ring directory.
struct ShadowRingReader {
    let root: URL
    let since: Date
    private let limit = 16 * 1024 * 1024
    private func info(_ url: URL) -> (Date, Int, UInt64)? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              a[.type] as? FileAttributeType == .typeRegular,
              let t = a[.modificationDate] as? Date,
              let n = a[.size] as? NSNumber, n.intValue > 32, n.intValue <= limit,
              let inode = a[.systemFileNumber] as? NSNumber else { return nil }
        return (t, n.intValue, inode.uint64Value)
    }
    private func read(_ url: URL) -> Data? {
        guard let f = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? f.close() }
        return try? f.read(upToCount: limit + 1)
    }
    func newest(seen: Set<String>) -> (String, ShadowSnapshot?) {
        guard let dir = try? FileManager.default.attributesOfItem(atPath: root.path),
              dir[.type] as? FileAttributeType == .typeDirectory else { return ("ring_missing", nil) }
        let candidates = (0..<24).compactMap { i -> (URL, Date, Int, UInt64)? in
            let u = root.appendingPathComponent(String(format: "frame_%02d.png", i))
            guard let a = info(u), a.0 >= since else { return nil }
            return (u, a.0, a.1, a.2)
        }
        guard let x = candidates.max(by: { $0.1 == $1.1 ? $0.0.path < $1.0.path : $0.1 < $1.1 }) else { return ("no_fresh_frame", nil) }
        let k = "\(x.0.lastPathComponent):\(x.1.timeIntervalSince1970):\(x.2):\(x.3)"
        if seen.contains(k) { return ("duplicate_snapshot", nil) }
        guard let a = read(x.0), let b = read(x.0), a == b, a.count == x.2,
              let y = info(x.0), y.0 == x.1, y.1 == x.2, y.2 == x.3 else { return ("unstable_snapshot", nil) }
        let signature: [UInt8] = [137,80,78,71,13,10,26,10]
        let end: [UInt8] = [0,0,0,0,73,69,78,68,174,66,96,130]
        guard a.prefix(8).elementsEqual(signature), a.suffix(12).elementsEqual(end) else { return ("incomplete_png", nil) }
        let w = a[16..<20].reduce(0) { $0*256+Int($1) }, h = a[20..<24].reduce(0) { $0*256+Int($1) }
        guard (50...4096).contains(w), (50...4096).contains(h) else { return ("invalid_dimensions", nil) }
        return ("snapshot", ShadowSnapshot(data:a,key:k,ageMS:Date().timeIntervalSince(x.1)*1000))
    }
}

final class ShadowTrialRecords: @unchecked Sendable {
    private let lock = NSLock()
    private var rows: [Int: [String: Any]] = [:]
    func set(_ i: Int, _ fields: [String: Any]) {
        lock.lock(); defer { lock.unlock() }
        rows[i, default: [:]].merge(fields) { _, new in new }
    }
    func all() -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return rows.keys.sorted().compactMap { rows[$0] }
    }
}

extension PreviewShadowBridge {
    // Retain the actual child Process across failure paths that clear child.
    func trialWarmup() -> (Bool, Process?) {
        queue.sync {
            let ok = start()
            let owned = child
            if !ok { stop() }
            return (ok, owned)
        }
    }
    func trialOffer(png: Data, frame: Int, legacy: [String?],
                    completion: @escaping @Sendable ([String: Any]?, Double) -> Void) -> String {
        lock.lock()
        if disabled { lock.unlock(); return "disabled" }
        if busy { lock.unlock(); return "busy" }
        busy = true; lock.unlock()
        let began = ProcessInfo.processInfo.systemUptime
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            let ans = exchange(png, legacy: legacy, frame: frame)
            completion(ans, (ProcessInfo.processInfo.systemUptime - began) * 1000)
        }
        return "submitted"
    }
    // Only stop the child owned by this trial. Never touch the production reader.
    func trialFinish(owned: Process?) -> Bool {
        queue.sync {
            stop()
            let deadline = ProcessInfo.processInfo.systemUptime + 3
            while owned?.isRunning == true && ProcessInfo.processInfo.systemUptime < deadline {
                Thread.sleep(forTimeInterval: 0.025)
            }
            guard owned?.isRunning != true else { return false }
            if let r = root {
                do { try FileManager.default.removeItem(at: r) } catch { return false }
            }
            return true
        }
    }
}
