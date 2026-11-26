// PV16-F isolated shadow bridge. Foundation only; no battle-state mutation.
final class PreviewShadowBridge: @unchecked Sendable {
    private let schema = "pv16-shadow-v1"
    private let queue = DispatchQueue(label: "pv16.shadow.serial", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private var disabled = false
    private var child: Process?
    private var root: URL?
    private let env: [String: String]
    init(environment: [String: String] = ProcessInfo.processInfo.environment) { env = environment }
    private func diag(_ text: String) {
        FileHandle.standardError.write(Data(("[pv16-shadow] " + text + "\n").utf8))
    }
    private func readObject(_ url: URL) -> [String: Any]? {
        guard let a = try? FileManager.default.attributesOfItem(atPath: url.path),
              let n = a[.size] as? NSNumber, n.intValue <= 65536,
              let d = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return obj
    }
    private func wait(_ url: URL, seconds: Double) -> [String: Any]? {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        repeat {
            if let x = readObject(url) { return x }
            if child?.isRunning != true { return nil }
            Thread.sleep(forTimeInterval: 0.025)
        } while ProcessInfo.processInfo.systemUptime < deadline
        return nil
    }
    private func stop() {
        if let p = child, p.isRunning { p.terminate() }
        child = nil
        lock.lock(); disabled = true; lock.unlock()
        if let r = root {
            for n in ["frame.png", "request.json", "response.json"] {
                try? FileManager.default.removeItem(at: r.appendingPathComponent(n))
            }
        }
    }
    private func start() -> Bool {
        if let p = child { return p.isRunning }
        let keys = ["PV16_SHADOW_PYTHON", "PV16_SHADOW_WORKER", "PV16_SHADOW_BUNDLE", "PV16_SHADOW_ARCHIVE"]
        let paths = keys.compactMap { env[$0] }
        guard paths.count == 4, paths.allSatisfy({ $0.hasPrefix("/") && FileManager.default.fileExists(atPath: $0) }) else { return false }
        let r = URL(fileURLWithPath: "/tmp", isDirectory: true).appendingPathComponent("pv16-shadow-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: r, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) } catch { return false }
        root = r
        let p = Process(); p.executableURL = URL(fileURLWithPath: paths[0])
        p.arguments = ["-B", "-s", paths[1], "--bundle", paths[2], "--archive", paths[3], "--spool", r.path, "--parent", String(ProcessInfo.processInfo.processIdentifier)]
        var clean = env; clean.removeValue(forKey: "PYTHONPATH"); clean.removeValue(forKey: "PYTHONHOME"); clean["PYTHONNOUSERSITE"] = "1"
        p.environment = clean; p.standardInput = FileHandle.nullDevice; p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        child = p
        guard let ready = wait(r.appendingPathComponent("ready.json"), seconds: 30), ready["schema"] as? String == schema, ready["accepted"] as? Bool == false else { return false }
        diag("private spool: " + r.path)
        return true
    }
    private func exchange(_ png: Data, legacy: [String?], frame: Int) -> [String: Any]? {
        guard png.count > 24, png.count <= 16*1024*1024, start(), let r = root else { stop(); return nil }
        let id = UUID().uuidString.lowercased(), response = r.appendingPathComponent("response.json")
        do {
            try? FileManager.default.removeItem(at: response)
            try png.write(to: r.appendingPathComponent("frame.png"), options: .atomic)
            let request = try JSONSerialization.data(withJSONObject: ["schema":schema,"id":id])
            try request.write(to: r.appendingPathComponent("request.json"), options: .atomic)
            guard var ans = wait(response, seconds: 3), ans["id"] as? String == id, ans["schema"] as? String == schema,
                  ans["accepted"] as? Bool == false, ans["scene_authenticated"] as? Bool == false,
                  ans["score_kind"] as? String == "joint25-dynamic-gallery-recovery-v2",
                  ans["bank_scope"] as? String == "all_historical_development",
                  let slots = ans["slots"] as? [Any], slots.count == 6,
                  let status = ans["status"] as? String, ["ranked","held","error"].contains(status) else { stop(); return nil }
            try? FileManager.default.removeItem(at: response)
            ans["legacy_names"] = legacy.map { $0 as Any? ?? NSNull() }; ans["frame"] = frame
            let data = try JSONSerialization.data(withJSONObject: ans, options: [.sortedKeys])
            try data.write(to: r.appendingPathComponent("latest.json"), options: .atomic)
            return ans
        } catch { stop(); return nil }
    }
    // Only one in-flight request. Drop busy frames; never delay the old recognizer.
    func submit(frame: Int, legacy: [String?], png: @escaping @Sendable () -> Data?) {
        lock.lock(); if busy || disabled { lock.unlock(); return }; busy = true; lock.unlock()
        queue.async { [self] in
            defer { lock.lock(); busy = false; lock.unlock() }
            guard let data = png() else { return }
            if exchange(data, legacy: legacy, frame: frame) == nil { diag("disabled after worker failure") }
        }
    }
    // Dedicated offline CLI. Not called from the battle loop.
    func probe(png: Data) -> [String: Any]? {
        queue.sync { defer { stop() }; return exchange(png, legacy: [], frame: 0) }
    }
}
