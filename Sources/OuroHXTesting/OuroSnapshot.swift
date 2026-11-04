public import CoreGraphics
public import Foundation
public import OuroHX
public import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// Renders SwiftUI views to PNG with `ImageRenderer` and compares them with recorded references, in light, dark and
/// increased contrast. No XCTest, so it works under Swift Testing and XCTest alike.
@MainActor
public enum OuroSnapshot {
    public enum Appearance: String, CaseIterable, Sendable {
        case light, dark, increasedContrast

        public var scheme: ColorScheme { self == .dark ? .dark : .light }
        public var contrast: ColorSchemeContrast { self == .increasedContrast ? .increased : .standard }
    }

    public enum Result: Equatable, Sendable {
        /// No reference existed, so this render became it.
        case recorded
        case matched
        /// The share of pixels that differ (0 to 1). The render is saved beside the reference as `<name>.actual.png`.
        case differs(fraction: Double)
        /// No reference, and `OURO_SNAPSHOT_RECORD=never` (set it in CI) forbids recording one. Saved as `.actual.png`.
        case missingReference
    }

    /// Pixels per point in every render, so snapshots match across Macs and simulators.
    public static let scale: CGFloat = 2

    /// Set `OURO_SNAPSHOT_RECORD=1` to overwrite references.
    public static var recording: Bool { ProcessInfo.processInfo.environment["OURO_SNAPSHOT_RECORD"] == "1" }
    /// Set `OURO_SNAPSHOT_RECORD=never` in CI so a missing reference fails instead of quietly being recorded.
    public static var neverRecord: Bool { ProcessInfo.processInfo.environment["OURO_SNAPSHOT_RECORD"] == "never" }

    public static func render(_ view: some View, size: CGSize? = nil, appearance: Appearance = .light) -> CGImage? {
        let content = view
            .frame(width: size?.width, height: size?.height)
            .environment(\.colorScheme, appearance.scheme)
            // `_colorSchemeContrast` is SwiftUI's underscored setter (the public key is read-only); previews use it too.
            .environment(\._colorSchemeContrast, appearance.contrast)
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.cgImage
    }

    public static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Compares a render with `<directory>/<name>.png`, recording it when there is none (or when ``recording``).
    /// `tolerance` is the share of pixels allowed to differ.
    public static func verify(_ view: some View, named name: String, in directory: URL, size: CGSize? = nil, appearance: Appearance = .light, tolerance: Double = 0) throws -> Result {
        guard let image = render(view, size: size, appearance: appearance), let data = png(image) else { throw RenderFailed(name: name) }
        let reference = directory.appendingPathComponent("\(name).png")
        guard !recording, FileManager.default.fileExists(atPath: reference.path),
              let source = CGImageSourceCreateWithURL(reference as CFURL, nil),
              let recorded = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            if neverRecord && !recording {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try data.write(to: directory.appendingPathComponent("\(name).actual.png"), options: .atomic)
                return .missingReference
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try data.write(to: reference, options: .atomic)
            return .recorded
        }
        let fraction = difference(image, recorded)
        if fraction <= tolerance { return .matched }
        try data.write(to: directory.appendingPathComponent("\(name).actual.png"), options: .atomic)
        return .differs(fraction: fraction)
    }

    public struct RenderFailed: Error, CustomStringConvertible {
        public let name: String
        public var description: String { "\(name): ImageRenderer returned no image" }
    }

    /// One pixel's colour, for checks like "the card is the card colour".
    public static func pixel(of image: CGImage, x: Int, y: Int) -> Color.Resolved? {
        guard let bytes = rgba(image), x >= 0, y >= 0, x < image.width, y < image.height else { return nil }
        let i = (y * image.width + x) * 4
        let a = Float(bytes[i + 3]) / 255
        guard a > 0 else { return Color.Resolved(red: 0, green: 0, blue: 0, opacity: 0) }
        // Un-premultiply.
        return Color.Resolved(colorSpace: .sRGB, red: Float(bytes[i]) / 255 / a, green: Float(bytes[i + 1]) / 255 / a, blue: Float(bytes[i + 2]) / 255 / a, opacity: a)
    }

    static func rgba(_ image: CGImage) -> [UInt8]? {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return bytes
    }

    /// A channel may move this many levels (of 255) without the pixel counting as changed: renders round a computed
    /// colour, such as one pushed to a contrast by bisection, one level differently from run to run.
    static let channelNoise = 2

    static func difference(_ a: CGImage, _ b: CGImage) -> Double {
        guard a.width == b.width, a.height == b.height, let pa = rgba(a), let pb = rgba(b) else { return 1 }
        var differing = 0
        for i in stride(from: 0, to: pa.count, by: 4)
        where (0..<4).contains(where: { abs(Int(pa[i + $0]) - Int(pb[i + $0])) > channelNoise }) { differing += 1 }
        return Double(differing) / Double(a.width * a.height)
    }
}
