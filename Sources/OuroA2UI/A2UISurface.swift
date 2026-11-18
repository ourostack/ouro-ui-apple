public import OuroHX
public import SwiftUI

/// Loads an `Image` component's picture. The default is `AsyncImage`; a host (or a test) can supply its own, such as
/// an app's image cache.
public typealias A2UIImageLoader = @MainActor @Sendable (URL) -> Image?

extension EnvironmentValues {
    /// The image loader ``A2UISurface`` uses; nil uses `AsyncImage`.
    @Entry public var a2uiImageLoader: A2UIImageLoader? = nil
}

/// A resolved A2UI surface drawn with Ouro HX: web's `a2ui-surface`. It is the A2UI entry point to
/// ``ComposedSurface``, which draws the tree and keeps its data model; this view only wraps each press in A2UI's
/// `action` message. Every button is one of the app's declared actions and pressing it follows its consent class: read
/// and write send the action at once, consequential opens a sheet built from the declaration and sends only when the
/// person confirms, and person-only hands the person to the app's own screen and never sends one. A button bound to a
/// field the person fills in sends what they entered.
///
/// ```swift
/// switch A2UI.resolveSurfaces(messages, catalog: catalog) {
/// case .success(let surfaces):
///     if let surface = surfaces.first {
///         A2UISurface(surface) { action in send(action) } onHandoff: { action, how in open(action) }
///     }
/// case .failure(let p): reply(p.problems)   // A2UI's error format, so the agent can correct itself
/// }
/// ```
public struct A2UISurface: View {
    let node: A2UINode?
    let surfaceId: String
    let data: A2UIJSON
    let onAction: @MainActor (A2UIJSON) -> Void
    let onHandoff: @MainActor (_ action: String, _ how: String) -> Void
    let now: @MainActor () -> Date

    /// - Parameters:
    ///   - node: the surface's root, from ``A2UI/resolve(_:catalog:label:)-(A2UIJSON,_,_)``.
    ///   - surfaceId: the surface's id, which each action message names.
    ///   - data: the surface's data model, which its fields start from (``A2UIResolvedSurface/data``).
    ///   - now: the clock for each action message's timestamp.
    ///   - onAction: receives the A2UI `action` message (``A2UI/actionMessage(surfaceId:press:timestamp:)``).
    ///   - onHandoff: a person-only button: take the person to the action's own screen; `how` is the declaration's.
    public init(_ node: A2UINode, surfaceId: String, data: A2UIJSON, now: @escaping @MainActor () -> Date = { Date() },
                onAction: @escaping @MainActor (A2UIJSON) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.node = node
        self.surfaceId = surfaceId
        self.data = data
        self.onAction = onAction
        self.onHandoff = onHandoff
        self.now = now
    }

    /// A surface with no fields, or whose fields start empty: its data model is `{}`. Use
    /// ``init(_:now:onAction:onHandoff:)`` with a surface from ``A2UI/resolveSurfaces(_:catalog:label:)`` to start its
    /// fields from its data model.
    public init(_ node: A2UINode, surfaceId: String, now: @escaping @MainActor () -> Date = { Date() },
                onAction: @escaping @MainActor (A2UIJSON) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.init(node, surfaceId: surfaceId, data: .object(A2UIObject()), now: now, onAction: onAction, onHandoff: onHandoff)
    }

    /// A surface from ``A2UI/resolveSurfaces(_:catalog:label:)``: its tree, its id and its data model. A surface with
    /// no root yet draws nothing.
    public init(_ surface: A2UIResolvedSurface, now: @escaping @MainActor () -> Date = { Date() },
                onAction: @escaping @MainActor (A2UIJSON) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.node = surface.node
        self.surfaceId = surface.id
        self.data = surface.data
        self.onAction = onAction
        self.onHandoff = onHandoff
        self.now = now
    }

    public var body: some View {
        if let node {
            ComposedSurface(node, data: data, onPress: { press in
                onAction(A2UI.actionMessage(surfaceId: surfaceId, press: press, timestamp: ISO8601DateFormatter().string(from: now())))
            }, onHandoff: onHandoff)
        }
    }
}

/// How a drawn button reaches the app, a press or a handoff, and the data model the fields write. Knows no format.
struct A2UIPressContext {
    /// The data model the surface was given.
    let data: A2UIJSON
    /// The person's answers, by pointer, in the order they gave them.
    let answers: Binding<A2UIObject>
    let onPress: @MainActor (PersonPress) -> Void
    let onHandoff: @MainActor (String, String) -> Void

    /// The data model as the person's answers leave it.
    var current: A2UIJSON { Self.answered(data, answers.wrappedValue) }

    static func answered(_ data: A2UIJSON, _ answers: A2UIObject) -> A2UIJSON {
        answers.pairs.reduce(data) { A2UI.set($0, $1.0, $1.1) }
    }

    /// A press, with the person's answers read from the data model.
    @MainActor func send(_ button: A2UINode, confirmed: Bool) {
        if let press = PersonPress.of(button, confirmed: confirmed, data: current) { onPress(press) }
    }

    /// What the data model holds at a field's pointer; setting it records the person's answer there, and setting nil
    /// (or null) leaves the data model without one.
    func value(at pointer: String) -> Binding<A2UIJSON?> {
        let (data, answers) = (data, answers)
        return Binding(get: { A2UI.get(Self.answered(data, answers.wrappedValue), pointer) }, set: { value in
            var given = answers.wrappedValue
            given[pointer] = nil
            given[pointer] = value ?? .null
            answers.wrappedValue = given
        })
    }
}

struct A2UINodeView: View {
    let node: A2UINode
    let context: A2UIPressContext
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        content.modifier(A2UILabel(label: node.props["@label"]?.string))
    }

    @ViewBuilder private var content: some View {
        switch node.component {
        case "Card":
            // Ouro HX's card, small, at the 16 points this surface drew before. Web's is medium with its first Image as
            // edge-to-edge media; that waits for OuroCard's media slot.
            OuroCard(size: .sm) { kids }
        case "Stack":
            let gap = A2UIMetrics.gap(node.text("gap"))
            if node.text("direction") == "horizontal" {
                A2UIFlow(spacing: gap) { kids }
            } else {
                VStack(alignment: .leading, spacing: gap) { kids }.frame(maxWidth: .infinity, alignment: .leading)
            }
        case "Heading":
            Text(node.text("text"))
                .font(A2UIMetrics.headingFont(level: Int(node.props["level"]?.number ?? 2)))
                .foregroundStyle(colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
        case "Text":
            Text(node.text("text"))
                .font(.body)
                .foregroundStyle(node.text("tone") == "muted" ? colors.mutedForeground : colors.foreground)
                .fixedSize(horizontal: false, vertical: true)
        case "Image":
            A2UIImageView(url: node.text("url"), description: node.text("description"), aspect: node.text("aspect"))
        case "Badge":
            A2UIMetrics.badge(text: node.text("text"), tone: node.text("tone"))
        case "List":
            let items = node.props["items"]?.array?.compactMap(\.string) ?? []
            let ordered = node.props["ordered"] == .bool(true)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(ordered ? "\(i + 1)." : "•").foregroundStyle(colors.mutedForeground).accessibilityHidden(true)
                        Text(item).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        case "DescriptionList":
            let items = node.props["items"]?.array ?? []
            OuroDescriptionList(items.map { OuroDescriptionItem($0["term"]?.string ?? "", $0["detail"]?.string ?? "") })
        case "Separator":
            OuroSeparator()
        case "Alert":
            OuroBanner(node.text("title"), description: node.props["text"]?.string, tone: A2UIMetrics.tone(node.text("tone")))
        case "TextField":
            A2UITextField(node: node, value: context.value(at: node.text("value")))
        case "Checkbox":
            OuroCheckbox(node.text("label"), isOn: A2UIFields.bool(context.value(at: node.text("value"))), description: A2UIFields.hint(node))
        case "Select":
            A2UISelect(node: node, value: context.value(at: node.text("value")))
        case "ActionButton":
            A2UIActionButton(node: node, context: context)
        default:
            EmptyView()
        }
    }

    @ViewBuilder private var kids: some View {
        ForEach(Array(node.children.enumerated()), id: \.offset) { _, child in
            A2UINodeView(node: child, context: context)
        }
    }
}

private struct A2UILabel: ViewModifier {
    let label: String?
    func body(content: Content) -> some View {
        if let label { content.accessibilityLabel(label) } else { content }
    }
}

/// How the catalog's small enums map to Ouro HX.
public enum A2UIMetrics {
    /// A `Stack`'s gap in points: web's `gap-0`, `gap-2`, `gap-4` and `gap-6`.
    public static func gap(_ step: String) -> CGFloat {
        switch step {
        case "none": 0
        case "small": 8
        case "large": 24
        default: 16
        }
    }

    public static func headingFont(level: Int) -> Font {
        switch level {
        case 1: .title2.weight(.semibold)
        case 3: .headline
        default: .title3.weight(.semibold)
        }
    }

    /// An `Alert`'s or a `Badge`'s tone as Ouro HX's.
    public static func tone(_ tone: String) -> OuroTone {
        switch tone {
        case "success": .success
        case "warning": .warning
        case "danger": .destructive
        case "info": .primary
        default: .secondary
        }
    }

    /// A catalog `Badge` as Ouro HX's ``OuroBadge``: solid in its tone, as web's `A2UISurface` draws its `Badge`.
    public static func badge(text: String, tone: String) -> OuroBadge {
        OuroBadge(text, tone: Self.tone(tone), variant: .solid)
    }

    public static func aspect(_ aspect: String) -> CGFloat {
        switch aspect {
        case "square": 1
        case "portrait": 3.0 / 4.0
        case "wide": 21.0 / 9.0
        default: 4.0 / 3.0
        }
    }
}

struct A2UIImageView: View {
    let url: String
    let description: String
    let aspect: String
    @Environment(\.a2uiImageLoader) private var loader
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        Rectangle()
            .fill(colors.muted)
            .aspectRatio(A2UIMetrics.aspect(aspect), contentMode: .fit)
            .overlay { picture }
            .clipShape(RoundedRectangle(cornerRadius: theme.radius(.lg), style: .continuous))
            .accessibilityElement()
            .accessibilityLabel(description)
            .accessibilityAddTraits(.isImage)
    }

    @ViewBuilder private var picture: some View {
        if let u = URL(string: url) {
            if let loader {
                if let image = loader(u) { image.resizable().scaledToFill() }
            } else {
                AsyncImage(url: u) { $0.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
    }
}

/// An `ActionButton`: its label is the declaration's, and pressing it follows the consent class.
struct A2UIActionButton: View {
    let node: A2UINode
    let context: A2UIPressContext
    @State private var confirming = false

    /// The rows the confirm sheet shows: what the press will send, the agent's input with the person's answers in the
    /// fields bound to theirs.
    static func confirmRows(_ node: A2UINode, data: A2UIJSON) -> [A2UIJSON] {
        ComposedTree.resolveButton(node, data: data).props["confirm"]?["fields"]?.array ?? []
    }

    var body: some View {
        let press = A2UIPress(rawValue: node.text("press")) ?? .run
        let primary = node.text("emphasis") == "primary"
        OuroButton(node.text("label"), tone: primary ? .primary : .secondary, variant: primary ? .solid : .outline, fullWidth: true) {
            switch press {
            case .run: context.send(node, confirmed: false)
            case .confirm: confirming = true
            case .handoff: context.onHandoff(node.text("action"), node.text("handoff"))
            }
        }
        .accessibilityHint(press == .handoff ? node.text("handoff") : "")
        .ouroSheet(isPresented: $confirming, title: node.props["confirm"]?["title"]?.string ?? node.text("label"),
                   description: node.props["confirm"]?["description"]?.string) {
            A2UIConfirmFields(fields: Self.confirmRows(node, data: context.current))
        } footer: {
            OuroButton(node.text("label"), fullWidth: true) {
                confirming = false
                context.send(node, confirmed: true)
            }
        }
    }
}

/// How the catalog's fields read and write the data model.
enum A2UIFields {
    /// A field's `hint`, or nil when it has none.
    static func hint(_ node: A2UINode) -> String? {
        node.props["hint"]?.string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// A checkbox is ticked only when the data holds `true`, and writes `true` or `false`.
    static func bool(_ value: Binding<A2UIJSON?>) -> Binding<Bool> {
        Binding(get: { value.wrappedValue == .bool(true) }, set: { value.wrappedValue = .bool($0) })
    }

    /// What a field writes for what the person typed: the text itself, or for a number field the number, and null
    /// (which leaves the data model without it) when the field is empty or isn't a number. A number's decimal mark is a
    /// point, or the locale's comma; a comma that groups thousands ("1,000") isn't a number, so it is never read as 1.
    static func answer(_ typed: String, number: Bool, decimalSeparator: String? = Locale.current.decimalSeparator) -> A2UIJSON {
        guard number else { return .string(typed) }
        var t = typed.trimmingCharacters(in: .whitespaces)
        if decimalSeparator == ",", !t.contains("."), t.filter({ $0 == "," }).count == 1 { t = t.replacingOccurrences(of: ",", with: ".") }
        guard !t.isEmpty, t.unicodeScalars.allSatisfy({ "0123456789.-+eE".unicodeScalars.contains($0) }),
              let n = Double(t), n.isFinite else { return .null }
        return .number(n)
    }
}

/// A catalog `TextField` as Ouro HX's ``OuroTextField``: it shows what the data holds at its `value` and writes what
/// the person types there, a number for `type: number`.
struct A2UITextField: View {
    let node: A2UINode
    let value: Binding<A2UIJSON?>
    /// What the person typed, kept while it says the same as the data: a number field's "4." or "" shows as typed.
    @State private var typed: String?

    /// The text the field shows and edits: what the person typed, else what the data holds; typing writes the answer.
    static func text(_ value: Binding<A2UIJSON?>, typed: Binding<String?>, number: Bool) -> Binding<String> {
        Binding(get: { typed.wrappedValue ?? A2UI.text(value.wrappedValue) }, set: { t in
            typed.wrappedValue = t
            value.wrappedValue = A2UIFields.answer(t, number: number)
        })
    }

    var body: some View {
        let number = node.text("type") == "number"
        let typed = $typed
        OuroTextField(node.text("label"), text: Self.text(value, typed: typed, number: number), description: A2UIFields.hint(node))
            .composedInput(multiline: node.props["multiline"] == .bool(true), number: number)
            .onChange(of: value.wrappedValue) { _, stored in
                if let t = typed.wrappedValue, A2UIFields.answer(t, number: number) != (stored ?? .null) { typed.wrappedValue = nil }
            }
    }
}

/// A catalog `Select` as Ouro HX's ``OuroSegmentedControl``, the control for one choice from a short list: it shows
/// the option the data holds at its `value` pressed, and writes the chosen option's text there.
struct A2UISelect: View {
    let node: A2UINode
    let value: Binding<A2UIJSON?>
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        var seen = Set<String>()
        let options = (node.props["options"]?.array ?? []).compactMap(\.string).filter { seen.insert($0).inserted }
        let selection = Binding<String>(get: { A2UI.text(value.wrappedValue) }, set: { value.wrappedValue = .string($0) })
        let control = OuroSegmentedControl(node.text("label"), selection: selection, fullWidth: true, items: options.map { OuroSegment($0, value: $0) })
        if let hint = A2UIFields.hint(node) {
            VStack(alignment: .leading, spacing: 6) {
                control
                // The hint as OuroTextField draws its description, raised to read on the page.
                Text(hint)
                    .font(.footnote)
                    .foregroundStyle(Color(OuroTextFieldPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast)).description))
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            control
        }
    }
}

/// What the agent prepared, each field's label beside its value, as the person confirms it. An id shows its name,
/// with the id small beside it.
public struct A2UIConfirmFields: View {
    let fields: [A2UIJSON]
    @Environment(\.ouroColors) private var colors

    public init(fields: [A2UIJSON]) { self.fields = fields }

    /// A row as VoiceOver reads it: the label, the value, then the id the value replaced.
    static func spoken(_ f: A2UIJSON) -> String {
        [f["label"]?.string, f["value"]?.string, f["raw"]?.string].compactMap { $0 }.joined(separator: ", ")
    }

    public var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(Array(fields.enumerated()), id: \.offset) { _, f in
                GridRow {
                    Text(f["label"]?.string ?? "").foregroundStyle(colors.mutedForeground)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(f["value"]?.string ?? "").foregroundStyle(colors.foreground)
                        if let raw = f["raw"]?.string { Text(raw).font(.caption).foregroundStyle(colors.mutedForeground) }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Self.spoken(f))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A row that wraps, for a horizontal `Stack`.
struct A2UIFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews)
        return CGSize(width: rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews) {
            var x = bounds.minX
            for i in row.items {
                let s = subviews[i].sizeThatFits(.unspecified)
                subviews[i].place(at: CGPoint(x: x, y: y + (row.height - s.height) / 2), proposal: ProposedViewSize(s))
                x += s.width + spacing
            }
            y += row.height + spacing
        }
    }

    private func arrange(width: CGFloat, _ subviews: Subviews) -> [(items: [Int], width: CGFloat, height: CGFloat)] {
        var rows: [(items: [Int], width: CGFloat, height: CGFloat)] = []
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if let last = rows.last, last.width + spacing + s.width <= width {
                rows[rows.count - 1] = (last.items + [i], last.width + spacing + s.width, max(last.height, s.height))
            } else {
                rows.append(([i], s.width, s.height))
            }
        }
        return rows
    }
}
