import UIKit
import XCTest

/// A plain md button ("Save recipe", no icon, not full width) shot in Pearl and Cookbook, light and dark, for a
/// side-by-side with web's button in the same themes. Each shot is the button with 8 points around it, at the
/// simulator's scale, attached as `button-shape-<theme>-<scheme>`. Pearl's corner is its 18pt squircle; Cookbook's is
/// a squircle capsule, core's 9999px control radius capped at half the height. The corner itself is pinned in
/// ComponentTests (`cookbooksPrimaryButtonIsACapsule`); this test only shoots it.
@MainActor
final class ButtonShapeShotsTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    func testAPlainButtonInEachTheme() throws {
        for theme in ["pearl", "cookbook"] {
            for scheme in ["light", "dark"] { try shoot(theme: theme, scheme: scheme) }
        }
    }

    private func shoot(theme: String, scheme: String) throws {
        let app = XCUIApplication()
        app.launchArguments = ["-theme", theme, "-page", "buttons", "-open", "0", "-scheme", scheme, "-demo", "shape"]
        app.launch()
        defer { app.terminate() }
        let button = app.buttons["button.shape"]
        XCTAssertTrue(button.waitForExistence(timeout: 30), "\(theme) \(scheme): no plain button")
        let frame = button.frame
        // Native's md button is 50pt tall, against web's 44px: a deliberate difference (the one-book brief).
        XCTAssertEqual(frame.height, 50, accuracy: 0.5, "\(theme) \(scheme): the md button's height")
        let shot = app.screenshot()
        let image = shot.image
        let scale = image.scale
        let crop = frame.insetBy(dx: -8, dy: -8)
        let pixels = CGRect(x: crop.minX * scale, y: crop.minY * scale, width: crop.width * scale, height: crop.height * scale)
        let cropped = try XCTUnwrap(image.cgImage?.cropping(to: pixels), "\(theme) \(scheme): the crop fell outside the screen")
        let attachment = XCTAttachment(image: UIImage(cgImage: cropped, scale: scale, orientation: .up))
        attachment.name = "button-shape-\(theme)-\(scheme)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
