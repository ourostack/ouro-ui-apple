import Foundation
@testable import OuroA2UI
@testable import OuroHX
import OuroHXTesting
import SwiftUI
import Testing

/// `A2UISurface` draws every catalog component that has an Ouro HX component with that public component, so an agent's
/// card and an app's card can't drift apart (docs/decisions/2026-11-14-apple-1-0.md, "Claims"). Each check draws the
/// node through the surface and the public component on its own, with the same arguments, and the two images must match
/// pixel for pixel. A private view standing in for the component draws differently and fails.
///
/// A new catalog component fails `everyCatalogComponentIsAccountedFor` until it's added to one of the two lists below;
/// a new public component whose name matches a catalog component fails `aPublicComponentOfTheSameNameIsTheOneDrawn`
/// until the surface draws it and its check is added here.
///
/// Serialized: drawn in parallel, the same badge twice came out different (seen once locally, 2026-11-14).
@Suite(.serialized) @MainActor struct PublicComponentTests {
    /// The catalog components Ouro HX has a public component for, and that component's type name. `Alert` is web's
    /// name for what Ouro HX calls a banner, `Select` is one choice from a short list, which Ouro HX draws as a segmented
    /// control, and `ActionButton` is a button bound to a declared action.
    static let drawnWith: [String: String] = [
        "Card": "OuroCard",
        "Badge": "OuroBadge",
        "DescriptionList": "OuroDescriptionList",
        "Separator": "OuroSeparator",
        "Alert": "OuroBanner",
        "TextField": "OuroTextField",
        "Checkbox": "OuroCheckbox",
        "Select": "OuroSegmentedControl",
        "ActionButton": "OuroButton",
    ]

    /// The catalog components Ouro HX has no component for in 1.0, drawn with SwiftUI's own views (`VStack`, `Text`)
    /// or a small layout. When one of these gains a public component, it moves to `drawnWith`.
    static let noComponentYet: Set<String> = ["Stack", "Heading", "Text", "Image", "List"]

    static var catalog: [String] { A2UI.components.map(\.0) + ["ActionButton"] }

    /// Every public SwiftUI view type in Ouro HX, read from its source files.
    static func publicViews() throws -> Set<String> {
        let root = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources/OuroHX").standardized
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let pattern = try Regex(#"public struct (Ouro\w+)(?:<[^>]*>)?[^{]*:\s*View\b"#)
        var names: Set<String> = []
        for case let file as URL in files where file.pathExtension == "swift" {
            for match in try String(contentsOf: file, encoding: .utf8).matches(of: pattern) {
                if let name = match.output[1].substring { names.insert(String(name)) }
            }
        }
        return names
    }

    @Test func everyCatalogComponentIsAccountedFor() {
        for name in Self.catalog {
            #expect((Self.drawnWith[name] != nil) != Self.noComponentYet.contains(name), "\(name) is in neither list, or in both")
        }
        #expect(Set(Self.drawnWith.keys).union(Self.noComponentYet) == Set(Self.catalog), "a listed component is not in the catalog")
    }

    @Test func aPublicComponentOfTheSameNameIsTheOneDrawn() throws {
        let views = try Self.publicViews()
        #expect(views.contains("OuroCard") && views.contains("OuroButton"), "read no public views from Sources/OuroHX")
        for name in Self.catalog where views.contains("Ouro\(name)") {
            #expect(Self.drawnWith[name] == "Ouro\(name)", "Ouro HX has Ouro\(name), so the surface must draw \(name) with it")
        }
        for type in Self.drawnWith.values {
            #expect(views.contains(type), "\(type) is not a public view in Ouro HX")
        }
    }

    // MARK: Each drawn component matches its public component

    static func node(_ component: String, _ props: A2UIObject = [:], _ children: [A2UINode] = []) -> A2UINode {
        A2UINode(id: component.lowercased(), component: component, props: props, children: children)
    }

    func image(_ view: some View) throws -> Data {
        let framed = view.padding(16).frame(width: 390, alignment: .top).ouroTheme(.pearl)
        return try #require(OuroSnapshot.render(framed, size: nil).flatMap(OuroSnapshot.png))
    }

    func surface(_ node: A2UINode, data: A2UIJSON = .object(A2UIObject())) throws -> Data {
        try image(ComposedSurface(node, data: data, onPress: { _ in }, onHandoff: { _, _ in }))
    }

    static let answers: A2UIJSON = .object(["servings": .number(4), "vegetarian": .bool(true), "oven": .string("Fan")])

    @Test func card() throws {
        let child = Self.node("Separator")
        #expect(try surface(Self.node("Card", [:], [child])) == image(OuroCard(size: .sm) { OuroSeparator() }))
    }

    @Test(arguments: ["neutral", "info", "success", "warning", "danger"])
    func badge(tone: String) throws {
        let node = Self.node("Badge", ["text": .string("Vegetarian"), "tone": .string(tone)])
        #expect(try surface(node) == image(OuroBadge("Vegetarian", tone: A2UIMetrics.tone(tone), variant: .solid)))
    }

    @Test func descriptionList() throws {
        let items: [A2UIJSON] = [.object(["term": .string("Time"), "detail": .string("25 min")]), .object(["term": .string("Serves"), "detail": .string("4")])]
        let drawn = try surface(Self.node("DescriptionList", ["items": .array(items)]))
        #expect(drawn == (try image(OuroDescriptionList([OuroDescriptionItem("Time", "25 min"), OuroDescriptionItem("Serves", "4")]))))
    }

    @Test func separator() throws {
        #expect(try surface(Self.node("Separator")) == image(OuroSeparator()))
    }

    @Test(arguments: ["neutral", "info", "success", "warning", "danger"])
    func alert(tone: String) throws {
        let node = Self.node("Alert", ["title": .string("Offline"), "text": .string("Changes sync when you're back."), "tone": .string(tone)])
        #expect(try surface(node) == image(OuroBanner("Offline", description: "Changes sync when you're back.", tone: A2UIMetrics.tone(tone))))
    }

    @Test(arguments: ["primary", "secondary"])
    func actionButton(emphasis: String) throws {
        let node = Self.node("ActionButton", ["label": .string("Save recipe"), "press": .string("run"), "emphasis": .string(emphasis)])
        let primary = emphasis == "primary"
        let expected = OuroButton("Save recipe", tone: primary ? .primary : .secondary, variant: primary ? .solid : .outline, fullWidth: true) {}
        #expect(try surface(node) == image(expected))
    }

    /// `ImageRenderer` draws a text field's frame, label and hint but not its text, so the text the field shows is
    /// checked through its binding (`ComposedFieldsTests.aTextFieldShowsTheDataAndWritesWhatIsTyped`).
    @Test func textField() throws {
        let node = Self.node("TextField", ["label": .string("Servings"), "value": .string("/servings"), "hint": .string("How many people you're cooking for."),
                                           "type": .string("number"), "multiline": .bool(false)])
        let drawn = try surface(node, data: Self.answers)
        #expect(drawn == (try image(OuroTextField("Servings", text: .constant("4"), description: "How many people you're cooking for."))))
    }

    @Test func checkbox() throws {
        let node = Self.node("Checkbox", ["label": .string("Make it vegetarian"), "value": .string("/vegetarian")])
        let drawn = try surface(node, data: Self.answers)
        #expect(drawn == (try image(OuroCheckbox("Make it vegetarian", isOn: .constant(true)))))
        #expect(drawn != (try surface(node)), "an empty data model leaves it unticked")
    }

    @Test func select() throws {
        let node = Self.node("Select", ["label": .string("Oven"), "value": .string("/oven"), "options": .array(["Fan", "Conventional", "Grill"].map { .string($0) })])
        let drawn = try surface(node, data: Self.answers)
        let items = ["Fan", "Conventional", "Grill"].map { OuroSegment($0, value: $0) }
        #expect(drawn == (try image(OuroSegmentedControl("Oven", selection: .constant("Fan"), fullWidth: true, items: items))))
        #expect(drawn != (try image(OuroSegmentedControl("Oven", selection: .constant("Grill"), fullWidth: true, items: items))))
    }

    /// The check can fail: a private view that looks close to the component draws differently.
    @Test func aStandInDrawsDifferently() throws {
        let standIn = Text("Vegetarian").font(.caption.weight(.semibold)).padding(.horizontal, 8).padding(.vertical, 2)
            .background(Capsule().fill(Color.secondary))
        let node = Self.node("Badge", ["text": .string("Vegetarian"), "tone": .string("neutral")])
        #expect(try surface(node) != image(standIn))
    }
}
