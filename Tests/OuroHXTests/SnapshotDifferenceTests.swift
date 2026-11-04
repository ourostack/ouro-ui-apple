import CoreGraphics
@testable import OuroHXTesting
import Testing

/// A snapshot differs where a pixel visibly changes, not where a colour rounds one level differently between
/// renders (which a pushed colour, found by bisection, can).
@MainActor @Suite struct SnapshotDifferenceTests {
    private func image(_ value: UInt8, size: Int = 10) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: size * size * 4)
        for i in stride(from: 0, to: bytes.count, by: 4) { bytes[i] = value; bytes[i + 1] = value; bytes[i + 2] = value; bytes[i + 3] = 255 }
        let context = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    @Test func roundingNoiseIsNotADifference() {
        #expect(OuroSnapshot.difference(image(200), image(201)) == 0)
        #expect(OuroSnapshot.difference(image(200), image(202)) == 0)
    }

    @Test func aVisibleChangeIs() {
        #expect(OuroSnapshot.difference(image(200), image(203)) == 1)
        #expect(OuroSnapshot.difference(image(200), image(200, size: 11)) == 1)
    }
}
