import Foundation
import ImageIO
@testable import OuroA2UI
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// Draws core's model-composed recipe card (`recipe-card-agent.json`) and its consequential button's confirmation
/// with Ouro HX. Every run checks both draw; with `OURO_A2UI_CAPTURE=<folder>` it also writes them there as PNGs, and
/// with `OURO_A2UI_IMAGE=<png>` the card shows that local file (such as web's synthetic picture, so the two captures
/// match) instead of the drawn one. Nothing touches the network.
@Suite @MainActor struct RenderTests {
    static let width: CGFloat = 390

    /// A synthetic picture for the card's Image: drawn shapes, no photograph and no network.
    static func syntheticOrzo() -> Image {
        let art = ZStack {
            LinearGradient(colors: [Color(red: 0.93, green: 0.78, blue: 0.45), Color(red: 0.78, green: 0.55, blue: 0.25)], startPoint: .topLeading, endPoint: .bottomTrailing)
            ForEach(0..<40, id: \.self) { i in
                Capsule().fill(Color(red: 0.98, green: 0.9, blue: 0.68)).frame(width: 18, height: 6)
                    .rotationEffect(.degrees(Double(i * 37 % 180)))
                    .offset(x: CGFloat((i * 53) % 300) - 150, y: CGFloat((i * 29) % 200) - 100)
            }
            ForEach(0..<14, id: \.self) { i in
                Circle().fill(Color(red: 0.45, green: 0.7, blue: 0.3)).frame(width: 12, height: 12)
                    .offset(x: CGFloat((i * 71) % 280) - 140, y: CGFloat((i * 43) % 180) - 90)
            }
            Circle().fill(Color(red: 0.98, green: 0.86, blue: 0.2)).frame(width: 70, height: 70).overlay(Circle().stroke(Color(red: 0.35, green: 0.25, blue: 0.1), lineWidth: 6)).offset(x: 90, y: -40)
        }
        .frame(width: 400, height: 300)
        .clipped()
        let cg = OuroSnapshot.render(art, size: CGSize(width: 400, height: 300))!
        return Image(decorative: cg, scale: 1)
    }

    static func card() throws -> A2UINode {
        let root = ConformanceTests.root
        let c = try A2UIJSON.parse(Data(contentsOf: root.appending(path: "cases/recipe-card-agent.json")))
        let catalog = try A2UICatalog(json: A2UIJSON.parse(Data(contentsOf: root.appending(path: "recipe.catalog.json"))))
        guard case .success(let surfaces) = A2UI.resolve(c["messages"]!, catalog: catalog), let node = surfaces.first?.1 else {
            throw A2UIProblems(problems: [])
        }
        return node
    }

    func capture(_ view: some View, _ name: String) throws {
        let image = try #require(OuroSnapshot.render(view, size: nil, appearance: .light))
        #expect(image.width > 0 && image.height > 0)
        if let dir = ProcessInfo.processInfo.environment["OURO_A2UI_CAPTURE"] {
            try OuroSnapshot.png(image)!.write(to: URL(filePath: dir).appending(path: "\(name).png"))
        }
    }

    @Test func recipeCard() throws {
        let node = try Self.card()
        let orzo = ProcessInfo.processInfo.environment["OURO_A2UI_IMAGE"]
            .flatMap { CGImageSourceCreateWithURL(URL(filePath: $0) as CFURL, nil) }
            .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            .map { Image(decorative: $0, scale: 1) } ?? Self.syntheticOrzo()
        let view = A2UISurface(node, surfaceId: "recipe-card", onAction: { _ in }, onHandoff: { _, _ in })
            .environment(\.a2uiImageLoader, { _ in orzo })
            .padding(16)
            .frame(width: Self.width, alignment: .top)
            .background(Color(OuroInk.r(OuroHXStyle(theme: OuroTokens.pearl, scheme: .light).colors.background)))
            .ouroTheme(.pearl)
        try capture(view, "recipe-card-light")
    }

    @Test func consequentialConfirmation() throws {
        let node = try Self.card()
        let share = try #require(node.flattened.first { $0.text("press") == "confirm" })
        let confirm = try #require(share.props["confirm"])
        let style = OuroHXStyle(theme: OuroTokens.pearl, scheme: .light)
        // ImageRenderer leaves a ScrollView's content out, and the sheet's body scrolls, so this capture draws the
        // fields in the actions row, above the button; the app shows them in the body.
        let view = OuroSheetBody(title: confirm["title"]?.string ?? "", description: confirm["description"]?.string, hideTitle: false, detents: nil, closeLabel: "Close", close: {}) {
            EmptyView()
        } footer: {
            VStack(spacing: 20) {
                A2UIConfirmFields(fields: confirm["fields"]?.array ?? [])
                OuroButton(share.text("label"), fullWidth: true) {}
            }
        }
        .padding(16)
        .frame(width: Self.width, height: 300, alignment: .top)
        .background(Color(OuroSheetPalette(style: style).surface))
        .ouroTheme(.pearl)
        try capture(view, "recipe-card-confirm-share-light")
    }
}

extension A2UINode {
    var flattened: [A2UINode] { [self] + children.flatMap(\.flattened) }
}
