import AVFoundation
import CoreImage
import CoreVideo
import AppKit

// Only constructed when OBS capture is requested. No microphone or default-camera fallback.
final class OBSFrameSource: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    static let shared = OBSFrameSource()
    private let control = DispatchQueue(label:"champions.obs.control", qos:.utility)
    private let callbacks = DispatchQueue(label:"champions.obs.samples", qos:.userInitiated)
    private let lock = NSLock()
    private let context = CIContext()
    private var session: AVCaptureSession? // control queue only
    private var active: AVCaptureVideoDataOutput? // lock protected
    private var generation: UInt64 = 0, sequence: UInt64 = 0, consumed: UInt64 = 0
    private var latest: (CaptureFrameStamp, CVPixelBuffer)?
    private var lastAttempt = -Double.infinity
    private var pending = false, requested = false, stopped = false
    private var status = "OBS camera not started"
    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    private func setStatus(_ s: String) { lock.lock(); status=s; lock.unlock() }
    private func getStatus() -> String { lock.lock(); defer { lock.unlock() }; return status }
    private func ensure(_ options: CaptureInputOptions) {
        guard Bundle.main.object(forInfoDictionaryKey:"NSCameraUsageDescription") is String else {
            setStatus("OBS mode requires the compiled camera-permission app bundle"); return
        }
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: break
        case .notDetermined:
            lock.lock(); let ask = !requested && !stopped; requested=true; status="Camera permission pending"; lock.unlock()
            if ask { AVCaptureDevice.requestAccess(for:.video) { [weak self] allowed in
                self?.setStatus(allowed ? "Camera permission granted" : "Camera permission denied")
            } }
            return
        case .denied, .restricted: setStatus("Camera permission denied or restricted"); return
        @unknown default: setStatus("Unknown camera authorization"); return
        }
        lock.lock()
        let t = now(), stale = latest.map { t-$0.0.uptime > 4 } ?? true
        guard !stopped, !pending, stale, t-lastAttempt >= 3 else { lock.unlock(); return }
        pending=true; lastAttempt=t; status="Opening OBS camera"; lock.unlock()
        control.async { [self] in configure(options) }
    }
    private func configure(_ options: CaptureInputOptions) {
        defer { lock.lock(); pending=false; lastAttempt=now(); lock.unlock() }
        lock.lock(); active=nil; latest=nil; generation &+= 1; let cancelled=stopped; lock.unlock()
        if let old = session { old.stopRunning(); session=nil }
        guard !cancelled else { return }
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            devices=AVCaptureDevice.DiscoverySession(deviceTypes:[.external], mediaType:.video, position:.unspecified).devices
        } else {
            devices=AVCaptureDevice.DiscoverySession(deviceTypes:[.externalUnknown], mediaType:.video, position:.unspecified).devices
        }
        guard let i=options.deviceIndex(devices.map { $0.localizedName }) else {
            setStatus("Configured OBS camera missing or ambiguous; start OBS Virtual Camera"); return
        }
        do {
            let input=try AVCaptureDeviceInput(device:devices[i])
            let s=AVCaptureSession(), out=AVCaptureVideoDataOutput()
            out.alwaysDiscardsLateVideoFrames=true
            out.videoSettings=[kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
            s.beginConfiguration()
            if s.canSetSessionPreset(.inputPriority) { s.sessionPreset = .inputPriority }
            guard s.canAddInput(input), s.canAddOutput(out) else {
                s.commitConfiguration(); setStatus("OBS session input/output unavailable"); return
            }
            s.addInput(input); s.addOutput(out); s.commitConfiguration()
            out.setSampleBufferDelegate(self, queue:callbacks)
            lock.lock(); active=out; lock.unlock()
            session=s
            s.startRunning() // potentially blocking; never on the reader capture loop
            if !s.isRunning { setStatus("OBS session did not start") }
        } catch { setStatus("OBS camera input could not be opened") }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let buffer=CMSampleBufferGetImageBuffer(sampleBuffer),
              (50...4096).contains(CVPixelBufferGetWidth(buffer)),
              (50...4096).contains(CVPixelBufferGetHeight(buffer)) else { return }
        lock.lock(); defer { lock.unlock() }
        guard let a=active, output === a, !stopped else { return }
        sequence &+= 1
        latest=(CaptureFrameStamp(generation:generation,sequence:sequence,uptime:now()),buffer)
        status="Receiving OBS frames"
    }
    private func take() -> CVPixelBuffer? {
        lock.lock(); defer { lock.unlock() }
        guard let (stamp,buffer)=latest, !stopped,
              stamp.usable(generation:generation,after:consumed,now:now()) else { return nil }
        consumed=stamp.sequence
        return buffer
    }
    // Called by the existing single producer or a single-shot mode; no shared path on failure.
    func writePNG(_ path: String, options: CaptureInputOptions, timeout: Double = 5) -> String? {
        let deadline=now()+timeout
        repeat {
            ensure(options)
            let auth=AVCaptureDevice.authorizationStatus(for:.video)
            if auth == .denied || auth == .restricted || Bundle.main.object(forInfoDictionaryKey:"NSCameraUsageDescription") == nil { return getStatus() }
            if auth == .authorized, let b=take() {
                let im=CIImage(cvPixelBuffer:b)
                guard let rgb=CGColorSpace(name:CGColorSpace.sRGB),
                      let cg=context.createCGImage(im,from:im.extent,format:.RGBA8,colorSpace:rgb),
                      let png=NSBitmapImageRep(cgImage:cg).representation(using:.png,properties:[:]) else { return "OBS frame conversion failed" }
                do { try png.write(to:URL(fileURLWithPath:path),options:.atomic); return nil }
                catch { return "OBS PNG write failed" }
            }
            Thread.sleep(forTimeInterval:0.025)
        } while now()<deadline
        return "OBS fresh frame timeout: " + getStatus()
    }
    func shutdown() -> Bool {
        lock.lock(); stopped=true; active=nil; latest=nil; lock.unlock()
        let done=DispatchSemaphore(value:0)
        control.async { [self] in session?.stopRunning(); session=nil; done.signal() }
        return done.wait(timeout:.now()+3) == .success
    }
}
