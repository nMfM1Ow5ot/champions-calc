// reader.swift を macOS のない環境 (Linux Swift) で型チェックするためのスタブ宣言。
// 実在の Apple フレームワーク API のうち reader.swift が使う部分だけを、
// コード側の使い方に合わせて最小限で宣言する。
// 実行時の挙動は再現しない (コンパイル可否の確認専用)。
import Foundation

// MARK: - Glibc/Darwin 由来 (Linux では Foundation 経由で見えないもの)
public struct FakeFILE { public init() {} }
public var stderr = FakeFILE()
public var stdout = FakeFILE()
public func fputs(_ s: String, _ f: FakeFILE) -> Int32 { 0 }
public func fflush(_ f: FakeFILE) -> Int32 { 0 }
public func exit(_ code: Int32) -> Never { fatalError("stub") }

// MARK: - CoreGraphics
public class CGImage {
    public var width: Int = 0
    public var height: Int = 0
    public init() {}
}
public class CGColorSpace { public init() {} }
public func CGColorSpaceCreateDeviceRGB() -> CGColorSpace { CGColorSpace() }
public enum CGImageAlphaInfo: UInt32 {
    case none, premultipliedLast, premultipliedFirst, last, first, noneSkipLast, noneSkipFirst, alphaOnly
}
public class CGContext {
    public init?(data: UnsafeMutableRawPointer?, width: Int, height: Int, bitsPerComponent: Int, bytesPerRow: Int, space: CGColorSpace, bitmapInfo: UInt32) {}
    public func translateBy(x: CGFloat, y: CGFloat) {}
    public func scaleBy(x: CGFloat, y: CGFloat) {}
    public func draw(_ image: CGImage, in rect: CGRect) {}
    public func makeImage() -> CGImage? { nil }
}
public typealias CGWindowID = UInt32
public struct CGWindowListOption: OptionSet {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }
    public static let optionOnScreenOnly = CGWindowListOption(rawValue: 1)
    public static let excludeDesktopElements = CGWindowListOption(rawValue: 2)
}
public let kCGNullWindowID: CGWindowID = 0
public let kCGWindowOwnerName = "kCGWindowOwnerName"
public let kCGWindowNumber = "kCGWindowNumber"
public let kCGWindowBounds = "kCGWindowBounds"
public func CGWindowListCopyWindowInfo(_ option: CGWindowListOption, _ windowID: CGWindowID) -> [[String: Any]]? { nil }

// MARK: - AppKit
public class NSImage {
    public init?(contentsOfFile path: String) {}
    public func cgImage(forProposedRect: UnsafeMutablePointer<CGRect>?, context: Any?, hints: [String: Any]?) -> CGImage? { nil }
}
public class NSBitmapImageRep {
    public enum FileType { case png, jpeg, tiff, gif, bmp }
    public init(cgImage: CGImage) {}
    public func representation(using type: FileType, properties: [String: Any]) -> Data? { nil }
}

// MARK: - Vision
public class VNRequest { public init() {} }
public enum VNRequestTextRecognitionLevel { case accurate, fast }
public class VNRecognizedText {
    public var string: String = ""
    public init() {}
}
public class VNRecognizedTextObservation {
    public var boundingBox: CGRect = .zero
    public init() {}
    public func topCandidates(_ maxCandidates: Int) -> [VNRecognizedText] { [] }
}
public class VNRecognizeTextRequest: VNRequest {
    public var recognitionLevel: VNRequestTextRecognitionLevel = .accurate
    public var recognitionLanguages: [String] = []
    public var usesLanguageCorrection: Bool = false
    public var regionOfInterest: CGRect = .zero
    public var results: [VNRecognizedTextObservation]? = nil
}
public class VNImageRequestHandler {
    public init(cgImage: CGImage, options: [String: Any]) {}
    public func perform(_ requests: [VNRequest]) throws {}
}

// MARK: - Network
public class NWParameters {
    public static var tcp: NWParameters { NWParameters() }
    public init() {}
}
public enum NWEndpoint {
    public struct Port {
        public let rawValue: UInt16
        public init?(rawValue: UInt16) { self.rawValue = rawValue }
    }
}
public class NWConnection {
    public enum SendCompletion { case contentProcessed((Error?) -> Void) }
    public init() {}
    public func start(queue: DispatchQueue) {}
    public func receive(minimumIncompleteLength: Int, maximumLength: Int, completion: @escaping (Data?, Any?, Bool, Error?) -> Void) {}
    public func send(content: Data?, completion: SendCompletion) {}
    public func cancel() {}
}
public class NWListener {
    public var newConnectionHandler: ((NWConnection) -> Void)? = nil
    public init(using params: NWParameters, on port: NWEndpoint.Port) throws {}
    public func start(queue: DispatchQueue) {}
    public func cancel() {}
}
