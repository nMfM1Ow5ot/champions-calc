// Diagnostic executable entrypoint; the original reader main is removed by the builder.
import ImageIO
import CryptoKit

func trialMain() -> Int32 {
    let args = CommandLine.arguments
    guard args.count == 4, args[1] == "--read-only-live-trial",
          let seconds = Double(args[2]), (10...120).contains(seconds),
          let maxFrames = Int(args[3]), (1...100).contains(maxFrames) else { return 2 }
    guard scriptDir.lastPathComponent.hasPrefix("pv16-live-trial."),
          let attrs = try? FileManager.default.attributesOfItem(atPath: scriptDir.path),
          let mode = attrs[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else { return 2 }
    // Only load the frozen four read-only dictionaries. No battle/team/log startup.
    loadDict(); loadPreviewData()
    guard pvDataLoaded, !speciesDict.isEmpty else { return 3 }
    let bridge = PreviewShadowBridge()
    let warmStart = ProcessInfo.processInfo.systemUptime
    let (ready, owned) = bridge.trialWarmup()
    let warmMS = (ProcessInfo.processInfo.systemUptime - warmStart) * 1000
    guard ready else { _ = bridge.trialFinish(owned:owned); return 4 }
    let records = ShadowTrialRecords()
    let started = Date(), mono = ProcessInfo.processInfo.systemUptime
    let ring = ShadowRingReader(root: captureRingDir, since: started)
    var seen = Set<String>(), polls: [String: Int] = [:], frames = 0
    Swift.print("LIVE_TRIAL_READY: read-only ring; no production loop; sampling starts now")
    fflush(stdout)
    while frames < maxFrames && ProcessInfo.processInfo.systemUptime - mono < seconds {
        let (status, snap) = ring.newest(seen: seen)
        polls[status, default: 0] += 1
        guard let s = snap else { Thread.sleep(forTimeInterval: 0.5); continue }
        seen.insert(s.key)
        guard let src = CGImageSourceCreateWithData(s.data as CFData, nil),
              CGImageSourceGetStatus(src) == .statusComplete,
              let decoded = NSImage(data:s.data),
              let im = decoded.cgImage(forProposedRect:nil,context:nil,hints:nil) else {
            polls["decode_failed", default: 0] += 1; Thread.sleep(forTimeInterval: 0.5); continue
        }
        frames += 1
        let frame = frames, begin = ProcessInfo.processInfo.systemUptime
        let digest = SHA256.hash(data:s.data).map { String(format:"%02x",$0) }.joined()
        // Same OCR predicate as detectPreview; intentionally no stateful trainer extraction/voting.
        let oldGate = ocrBoxes(im, x0:0, y0:0, x1:1, y1:1).contains { $0.text.contains("選出") }
        let gateMS = (ProcessInfo.processInfo.systemUptime - begin)*1000
        let old = oldGate ? identifyPreview(image:im) : nil
        let oldMS = (ProcessInfo.processInfo.systemUptime - begin)*1000 - gateMS
        let names = old?.team ?? []
        records.set(frame, ["frame":frame,"frame_sha256":digest,"width":im.width,"height":im.height,
                            "snapshot_age_ms":s.ageMS,"legacy_gate":oldGate,"legacy_gate_ms":gateMS,
                            "legacy_rank_ms":oldMS,"legacy_names":names.map { $0 as Any? ?? NSNull() },
                            "new_status":"submitted","accepted":false])
        let offer = bridge.trialOffer(png:s.data,frame:frame,legacy:names) { result, ms in
            var fields: [String:Any] = ["new_exchange_ms":ms,"new_status":"bridge_failure"]
            if let a = result, a["frame_sha256"] as? String == digest, a["accepted"] as? Bool == false,
               a["scene_authenticated"] as? Bool == false, let st = a["status"] as? String {
                fields["new_status"] = st; fields["new_result"] = a
            } else if result != nil { fields["new_status"] = "integrity_failure" }
            records.set(frame,fields)
        }
        if offer != "submitted" { records.set(frame,["new_status":offer]) }
        Thread.sleep(forTimeInterval:0.5)
    }
    let cleanup = bridge.trialFinish(owned:owned)
    let stateNames = ["state.json","battle.log","battle_protocol.log","my_team.json","logs"]
    let absent = stateNames.allSatisfy { !FileManager.default.fileExists(atPath:scriptDir.appendingPathComponent($0).path) }
    let result: [String:Any] = ["schema":"pv16-live-trial-v1","scope":"read_only_ring_per_frame",
        "warmup_ms":warmMS,"sampling_elapsed_ms":(ProcessInfo.processInfo.systemUptime-mono)*1000,
        "polls":polls,"frames":records.all(),"worker_cleaned":cleanup,"state_paths_absent":absent,
        "accepted":false]
    do {
        let data = try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys])
        try data.write(to:scriptDir.appendingPathComponent("private-pairs.json"),options:.atomic)
    } catch { return 5 }
    Swift.print("LIVE_TRIAL_CAPTURE_COMPLETE: \(frames) snapshots; worker_cleaned=\(cleanup); trial_state_paths_absent=\(absent)")
    fflush(stdout)
    return cleanup && absent && frames>0 ? 0 : 6
}
exit(trialMain())
