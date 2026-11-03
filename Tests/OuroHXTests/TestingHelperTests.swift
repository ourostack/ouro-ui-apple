import Foundation
import OuroDeviceHub
import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

private func scratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("ouro-hx-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite struct DeviceHubTests {
    let elements = [
        OuroDeviceHub.Element(role: "AXButton", description: "Open", help: "", frame: .zero),
        OuroDeviceHub.Element(role: "AXButton", description: "", help: "Partially Open", frame: .zero),
        OuroDeviceHub.Element(role: "AXStaticText", description: "Closed", help: "", frame: .zero),
    ]

    @Test func pressFindsByDescriptionOrHelpExactly() {
        #expect(OuroDeviceHub.match("Open", in: elements)?.description == "Open")
        #expect(OuroDeviceHub.match("Partially Open", in: elements)?.help == "Partially Open")
        #expect(OuroDeviceHub.match("open", in: elements) == nil)
    }

    @Test func dumpListsButtonsOnly() {
        #expect(OuroDeviceHub.dumpLines(elements) == ["Open |  | 0,0 0x0", " | Partially Open | 0,0 0x0"])
    }

    @Test func exitCodesStayTheAppsOwn() {
        #expect(OuroDeviceHub.Failure.noProcess.exitCode == 1)
        #expect(OuroDeviceHub.Failure.notFound("x").exitCode == 2)
        #expect(OuroDeviceHub.Failure.notTrusted.exitCode == 3)
        #expect(OuroDeviceHub.Failure.pressFailed("x", code: -25200).exitCode == 4)
    }
}

@Suite struct DuoRequestTests {
    @Test func requestsAreNumberedFilesAnsweredByDoneFiles() throws {
        let dir = try scratch()
        var channel = OuroDuoRequests(directory: dir)
        let first = try channel.write("Partially Open")
        #expect(first.request.lastPathComponent == "01.request")
        #expect(first.done.lastPathComponent == "01.done")
        #expect(try String(contentsOf: first.request, encoding: .utf8) == "Partially Open")
        #expect(try channel.write("Open").request.lastPathComponent == "02.request")
        #expect(OuroDuoRequests.pending(in: dir).map(\.text) == ["Partially Open", "Open"])
        try OuroDuoRequests.answer(first, "ok")
        #expect(OuroDuoRequests.pending(in: dir).map(\.text) == ["Open"])
        #expect(try OuroDuoRequests.outcome(of: first) == "ok")
    }

    @Test func theDirectoryComesFromTheEnvironment() throws {
        #expect(throws: OuroDuoRequests.MissingDirectory.self) { try OuroDuoRequests.directory(variable: "OURO_DUO_POSTURE_DIR", in: [:]) }
        #expect(try OuroDuoRequests.directory(variable: "OURO_DUO_POSTURE_DIR", in: ["OURO_DUO_POSTURE_DIR": "/tmp/duo"]).path == "/tmp/duo")
        #expect(OuroDuoRequests.defaultVariable == "OURO_DUO_POSTURE_DIR")
    }

    @Test func theDriverPressesPosturesAndRefusesTheRest() throws {
        let dir = try scratch()
        var channel = OuroDuoRequests(directory: dir)
        let open = try channel.write("Open")
        let odd = try channel.write("Fold In Half Twice")
        var pressed: [String] = []
        let handled = OuroDuoDriver.handlePending(in: dir) { pressed.append($0); return true }
        #expect(handled == 2)
        #expect(pressed == ["Open"])
        #expect(try OuroDuoRequests.outcome(of: open) == "ok")
        #expect(try OuroDuoRequests.outcome(of: odd).hasPrefix("unsupported"))
    }
}

@Suite @MainActor struct SnapshotTests {
    @Test func aSnapshotRecordsThenMatchesThenSpotsADifference() throws {
        let dir = try scratch()
        let swatch = { (color: Color) in color.frame(width: 20, height: 20) }
        #expect(try OuroSnapshot.verify(swatch(.red), named: "swatch", in: dir) == .recorded)
        #expect(try OuroSnapshot.verify(swatch(.red), named: "swatch", in: dir) == .matched)
        guard case let .differs(fraction) = try OuroSnapshot.verify(swatch(.blue), named: "swatch", in: dir) else {
            Issue.record("expected a difference"); return
        }
        #expect(fraction == 1)
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("swatch.actual.png").path))
    }

    /// Siri shows custom SwiftUI snippets; an HX view must render in every mode it can be shown in.
    @Test(arguments: [OuroSnapshot.Appearance.light, .dark, .increasedContrast])
    func aThemedSnippetRendersInEveryMode(appearance: OuroSnapshot.Appearance) throws {
        let snippet = SnippetProbe().ouroTheme(.pearl)
        let image = try #require(OuroSnapshot.render(snippet, size: CGSize(width: 320, height: 120), appearance: appearance))
        #expect(image.width == 320 * Int(OuroSnapshot.scale))
        let expected = OuroHXStyle(theme: OuroTokens.pearl, scheme: appearance.scheme, contrast: appearance.contrast).colors.card
        let pixel = try #require(OuroSnapshot.pixel(of: image, x: 8, y: image.height / 2))
        #expect(OuroColor.contrastRatio(pixel, expected.resolve(in: EnvironmentValues())) < 1.05)
    }
}

private struct SnippetProbe: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme
    var body: some View {
        RoundedRectangle(cornerRadius: theme.radius(.xl)).fill(colors.card)
            .overlay(Text("Added milk").foregroundStyle(colors.cardForeground))
    }
}
