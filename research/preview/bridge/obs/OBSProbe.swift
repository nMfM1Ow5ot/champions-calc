// Diagnostic-only entrypoint; called before the production main.
func runOBSCameraProbe(options: CaptureInputOptions) -> Int32 {
    let root=scriptDir
    guard root.lastPathComponent.hasPrefix("pv16-obs-probe."),
          let a=try? FileManager.default.attributesOfItem(atPath:root.path),
          let mode=a[.posixPermissions] as? NSNumber, mode.intValue & 0o077 == 0 else { return 2 }
    let dst=root.appendingPathComponent("obs-probe.png")
    guard !FileManager.default.fileExists(atPath:dst.path) else { return 2 }
    let source=OBSFrameSource.shared
    var rows=[[String:Any]](), firstError:String?=nil
    for i in 0..<6 {
        let t=ProcessInfo.processInfo.systemUptime
        if let reason=source.writePNG(dst.path,options:options,timeout:i==0 ? 30 : 5) {
            firstError=reason; break
        }
        guard let im=loadImage(path:dst.path) else { firstError="PNG decode failed"; break }
        rows.append(["sample":i+1,"width":im.width,"height":im.height,
                     "capture_ms":(ProcessInfo.processInfo.systemUptime-t)*1000])
        Thread.sleep(forTimeInterval:0.5)
    }
    let stopped=source.shutdown()
    let absent=["state.json","battle.log","battle_protocol.log","my_team.json","logs"].allSatisfy {
        !FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path)
    }
    let ok=rows.count==6 && firstError==nil && stopped && absent
    let report:[String:Any]=["schema":"pv16-obs-probe-v1","capture":"obs","samples":rows,
        "shutdown":stopped,"state_paths_absent":absent,"capture_pass":ok,"error":firstError as Any? ?? NSNull()]
    if let data=try? JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]) {
        Swift.print(String(decoding:data,as:UTF8.self))
    }
    return ok ? 0 : 4
}
