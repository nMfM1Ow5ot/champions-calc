import Foundation

struct CaptureInputOptions {
    enum Mode: String { case quicktime, obs }
    let mode: Mode
    let obsName: String
    let probe: Bool
    static func parse(_ args: [String]) -> CaptureInputOptions? {
        var mode: Mode = .quicktime, name = "OBS Virtual Camera", probe = false
        var seen = Set<String>(), i = 0
        while i < args.count {
            let key = args[i]
            if ["--capture", "--obs-camera-name", "--obs-camera-probe"].contains(key) {
                guard seen.insert(key).inserted else { return nil }
                if key == "--obs-camera-probe" { probe = true; i += 1; continue }
                guard i+1 < args.count, !args[i+1].hasPrefix("--") else { return nil }
                let value = args[i+1]
                if key == "--capture" {
                    guard let m = Mode(rawValue:value) else { return nil }; mode = m
                } else {
                    guard !value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return nil }; name = value
                }
                i += 2
            } else { i += 1 }
        }
        guard mode == .obs || (!probe && !seen.contains("--obs-camera-name")) else { return nil }
        return CaptureInputOptions(mode:mode,obsName:name,probe:probe)
    }
    func deviceIndex(_ names: [String]) -> Int? {
        let matches = names.indices.filter { names[$0].caseInsensitiveCompare(obsName) == .orderedSame }
        return matches.count == 1 ? matches[0] : nil
    }
}

struct CaptureFrameStamp {
    let generation: UInt64
    let sequence: UInt64
    let uptime: Double
    func usable(generation g: UInt64, after seq: UInt64, now: Double, maxAge: Double = 1) -> Bool {
        generation == g && sequence > seq && now >= uptime && now-uptime <= maxAge
    }
}
