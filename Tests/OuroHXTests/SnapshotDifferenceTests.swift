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

    /// A white 10x10 picture with ImageRenderer's yellow placeholder over its first `bar` rows, and a gray pixel at
    /// (9, 9) of `gray`.
    private func field(bar: Int, gray: UInt8 = 255) -> CGImage {
        let size = 10
        var bytes = [UInt8](repeating: 255, count: size * size * 4)
        for row in 0..<bar { for x in 0..<size { let i = (row * size + x) * 4; bytes[i + 1] = 204; bytes[i + 2] = 0 } }
        let last = (size * size - 1) * 4
        bytes[last] = gray; bytes[last + 1] = gray; bytes[last + 2] = gray
        let context = CGContext(data: &bytes, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return context.makeImage()!
    }

    /// The unrendered input's placeholder changes size between runs (#173): ignoring it, a taller bar is no difference,
    /// while a change anywhere else still is.
    @Test func anUnrenderedInputsPlaceholderCanBeIgnored() {
        #expect(OuroSnapshot.difference(field(bar: 3), field(bar: 5)) == 0.2)
        #expect(OuroSnapshot.difference(field(bar: 3), field(bar: 5), ignoringUnrenderedInput: true) == 0)
        #expect(OuroSnapshot.difference(field(bar: 3), field(bar: 5, gray: 100), ignoringUnrenderedInput: true) == 0.01)
        #expect(OuroSnapshot.difference(image(255), image(100), ignoringUnrenderedInput: true) == 1, "grays still count")
    }
}
