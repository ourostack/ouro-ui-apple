public import OuroHX
public import SwiftUI

/// Loads an `Image` component's picture. The default is `AsyncImage`; a host (or a test) can supply its own, such as
/// an app's image cache.
public typealias A2UIImageLoader = @MainActor @Sendable (URL) -> Image?

extension EnvironmentValues {
    /// The image loader ``A2UISurface`` uses; nil uses `AsyncImage`.
    @Entry public var a2uiImageLoader: A2UIImageLoader? = nil
}

/// A resolved A2UI surface drawn with Ouro HX: web's `a2ui-surface`. Every button is one of the app's declared actions
/// and pressing it follows its consent class: read and write send the action at once, consequential opens a sheet
/// built from the declaration and sends only when the person confirms, and person-only hands the person to the app's
/// own screen and never sends one.
///
/// ```swift
/// switch A2UI.resolve(messages, catalog: catalog) {
/// case .success(let surfaces):
///     if let (id, node?) = surfaces.first {
///         A2UISurface(node, surfaceId: id) { action in send(action) } onHandoff: { action, how in open(action) }
///     }
/// case .failure(let p): reply(p.problems)   // A2UI's error format, so the agent can correct itself
/// }
/// ```
public struct A2UISurface: View {
    let node: A2UINode
    let surfaceId: String
    let onAction: @MainActor (A2UIJSON) -> Void
    let onHandoff: @MainActor (_ action: String, _ how: String) -> Void
    let now: @MainActor () -> Date

    /// - Parameters:
    ///   - node: the surface's root, from ``A2UI/resolve(_:catalog:)-(A2UIJSON,_)``.
    ///   - surfaceId: the surface's id, which each action message names.
    ///   - now: the clock for each action message's timestamp.
    ///   - onAction: receives the A2UI `action` message (``A2UI/actionMessage(surfaceId:button:timestamp:confirmed:)``).
    ///   - onHandoff: a person-only button: take the person to the action's own screen; `how` is the declaration's.
    public init(_ node: A2UINode, surfaceId: String, now: @escaping @MainActor () -> Date = { Date() },
                onAction: @escaping @MainActor (A2UIJSON) -> Void,
                onHandoff: @escaping @MainActor (_ action: String, _ how: String) -> Void) {
        self.node = node
        self.surfaceId = surfaceId
        self.onAction = onAction
        self.onHandoff = onHandoff
        self.now = now
    }

    public var body: some View {
        A2UINodeView(node: node, context: A2UIPressContext(surfaceId: surfaceId, onAction: onAction, onHandoff: onHandoff, now: now))
    }
}

struct A2UIPressContext {
    let surfaceId: String
    let onAction: @MainActor (A2UIJSON) -> Void
    let onHandoff: @MainActor (String, String) -> Void
    let now: @MainActor () -> Date

    @MainActor func send(_ button: A2UINode, confirmed: Bool) {
        let stamp = ISO8601DateFormatter().string(from: now())
        if let m = A2UI.actionMessage(surfaceId: surfaceId, button: button, timestamp: stamp, confirmed: confirmed) { onAction(m) }
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
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, it in
                    GridRow {
                        Text(it["term"]?.string ?? "").foregroundStyle(colors.mutedForeground)
                        Text(it["detail"]?.string ?? "").foregroundStyle(colors.foreground)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        case "Separator":
            Rectangle().fill(colors.border).frame(height: 1).frame(maxWidth: .infinity).accessibilityHidden(true)
        case "Alert":
            OuroBanner(node.text("title"), description: node.props["text"]?.string, tone: A2UIMetrics.tone(node.text("tone")))
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
            A2UIConfirmFields(fields: node.props["confirm"]?["fields"]?.array ?? [])
        } footer: {
            OuroButton(node.text("label"), fullWidth: true) {
                confirming = false
                context.send(node, confirmed: true)
            }
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
