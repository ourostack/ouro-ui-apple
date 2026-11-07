public import SwiftUI
import os

/// A button in a toast, such as Undo. Pressing it runs `handler`, then dismisses the toast.
public struct OuroToastAction: Sendable {
    /// A short verb: "Undo", "View".
    public var label: String
    public var handler: @MainActor @Sendable () -> Void

    public init(_ label: String, handler: @escaping @MainActor @Sendable () -> Void) {
        self.label = label
        self.handler = handler
    }
}

/// How long a toast stays once it shows.
public enum OuroToastDuration: Sendable, Equatable {
    /// Five seconds, or until dismissed when the toast has an action (core claim `toast.action-stays`).
    case automatic
    /// This many seconds; 0 keeps it until it is dismissed, as on web.
    case seconds(Double)
    /// Until the person or the app dismisses it.
    case untilDismissed
}

/// A short message at the top of the screen that VoiceOver reads once and that dismisses itself: web's `toast`.
/// Send one with the ``OuroToaster`` in the environment, after `.ouroToaster()` at the app's root:
///
/// ```swift
/// @Environment(\.ouroToast) private var toast
/// toast("Recipe saved", tone: .success)
/// toast("Recipe deleted", action: OuroToastAction("Undo") { restore() })
/// ```
public struct OuroToast: Identifiable, Sendable {
    public var id: String
    public var message: String
    public var description: String?
    public var tone: OuroTone
    public var action: OuroToastAction?
    public var duration: OuroToastDuration
    /// An SF Symbol to lead with, in place of its tone's (a secondary toast has none of its own).
    public var systemImage: String?
    /// New for every toast made, so one that replaces another under the same `id` is a new showing: VoiceOver hears
    /// it and its countdown starts over.
    public let showing = UUID()

    public init(_ message: String, description: String? = nil, tone: OuroTone = .secondary, systemImage: String? = nil, action: OuroToastAction? = nil, duration: OuroToastDuration = .automatic, id: String? = nil) {
        self.id = id ?? UUID().uuidString
        self.systemImage = systemImage
        self.message = message
        self.description = description
        self.tone = tone
        self.action = action
        self.duration = duration
    }

    /// How long it stays once it shows, in seconds, or nil to stay until dismissed. A toast with an action stays
    /// unless it was given a duration, so a timed Undo never runs out before a VoiceOver or Switch Control user
    /// reaches it (WCAG 2.2.1).
    public var seconds: Double? {
        switch duration {
        case .automatic: action == nil ? OuroToastMetrics.defaultSeconds : nil
        case let .seconds(s): s > 0 && s.isFinite ? s : nil
        case .untilDismissed: nil
        }
    }

    /// The symbol it leads with: its own, or its tone's.
    public var symbol: String? { systemImage ?? tone.systemImage(for: .toast) }

    /// What VoiceOver says when it shows: the message, then the description.
    public var announcement: String { OuroBannerMetrics.announcement(title: message, description: description) }
}

/// The toasts showing and waiting, as a value. Up to three show at once; later ones wait their turn, a destructive
/// toast ahead of the others; a toast with the id of one already here replaces it in place. Web's Toaster rules.
public struct OuroToastQueue: Sendable {
    public private(set) var visible: [OuroToast] = []
    public private(set) var waiting: [OuroToast] = []
    /// How many show at once: ``OuroToastMetrics/maximumVisible(accessibilitySize:)``. Lowering it sends the newest
    /// back to the front of the waiting line; raising it brings waiting toasts in.
    public var limit = OuroToastMetrics.maximumVisible(accessibilitySize: false) {
        didSet {
            limit = max(1, limit)
            while visible.count > limit { waiting.insert(visible.removeLast(), at: 0) }
            refill()
        }
    }

    public init() {}

    public mutating func show(_ toast: OuroToast) {
        if let i = visible.firstIndex(where: { $0.id == toast.id }) { visible[i] = toast; return }
        if let i = waiting.firstIndex(where: { $0.id == toast.id }) { waiting[i] = toast; return }
        if visible.count < limit { visible.append(toast); return }
        if toast.tone == .destructive, let i = waiting.firstIndex(where: { $0.tone != .destructive }) {
            waiting.insert(toast, at: i)
        } else {
            waiting.append(toast)
        }
    }

    /// Dismisses one toast by id, or every toast when `id` is nil. A waiting toast dismissed by id never shows.
    public mutating func dismiss(_ id: String? = nil) {
        guard let id else { visible = []; waiting = []; return }
        waiting.removeAll { $0.id == id }
        visible.removeAll { $0.id == id }
        refill()
    }

    private mutating func refill() {
        while visible.count < limit, !waiting.isEmpty { visible.append(waiting.removeFirst()) }
    }
}

/// The resolved colours of a toast as seen: the popover surface, its words and icon at 5:1 (7:1 under increased
/// contrast).
public struct OuroToastPalette: Sendable {
    public var message: Color.Resolved
    public var description: Color.Resolved
    public var icon: Color.Resolved
    public var surface: Color.Resolved
    /// The outline: the theme's border, raised under increased contrast as a banner's is.
    public var border: Color.Resolved
    /// The action's words: the theme's primary (destructive on a destructive toast), readable on the surface.
    public var action: Color.Resolved
    /// The hairline before the action.
    public var divider: Color.Resolved
    /// Whether the words may take the system's vibrant styles on glass: only where those read on this surface (see
    /// ``vibrantReads(on:scheme:contrast:)``). Otherwise the toast is solid, in these colours.
    public var vibrant: Bool

    /// Whether the system's label colours, which follow the colour scheme and not the theme, read on `surface`: its
    /// primary label (black in light, white in dark) at 7:1, headroom for the fainter secondary. A custom theme with
    /// a dark popover in light mode fails, and its toast goes solid.
    public static func vibrantReads(on surface: Color.Resolved, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Bool {
        let label = scheme == .dark ? Color.Resolved(red: 1, green: 1, blue: 1) : Color.Resolved(red: 0, green: 0, blue: 0)
        return OuroColor.contrastRatio(label, surface) >= 7
    }

    public init(tone: OuroTone, style: OuroHXStyle) {
        let c = style.colors
        surface = OuroInk.r(c.popover)
        border = OuroColor.push(OuroInk.r(c.border), against: surface, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
        message = OuroInk.readable(OuroInk.r(c.popoverForeground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
        icon = OuroInk.readable(tone == .secondary ? OuroInk.r(c.popoverForeground) : OuroInk.r(tone.fill(c).fill), on: surface, style)
        // 7:1 in every mode: inside the glass, vibrancy lightens tinted words.
        action = OuroColor.push(OuroInk.r(tone == .destructive ? c.destructive : c.primary), against: surface, to: OuroColor.increasedTextContrast)
        vibrant = style.contrast != .increased && Self.vibrantReads(on: surface, scheme: style.scheme, contrast: style.contrast)
        divider = OuroColor.push(OuroInk.r(c.border), against: surface, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1.2)
    }
}

/// Metrics and motion every toast shares, as data.
public enum OuroToastMetrics {
    /// How much of its own surface tints a toast's glass on iOS 27, whose glass lifts what is under it toward white.
    public static let glassSurfaceTint = 0.6
    /// Whether a toast's description on glass takes the theme's colour rather than the system's vibrant secondary
    /// style: from iOS 27, where that style read below 5:1 on the toast's surface.
    public static var themedDescriptionOnGlass: Bool {
        if #available(iOS 27, macOS 27, visionOS 27, *) { return true }
        return false
    }
    /// How long a toast without an action stays: five seconds, as on web.
    public static let defaultSeconds = 5.0
    /// How many show at once: three, as on web, or one at the accessibility text sizes, where a toast can be a third
    /// of the screen tall and a stack would hide the page.
    public static func maximumVisible(accessibilitySize: Bool) -> Int { accessibilitySize ? 1 : 3 }
    /// How long `toast` counts down before it goes, or nil when it waits: while `held` (VoiceOver or Switch Control
    /// is on it, or a pointer is over it, as web pauses on focus and hover) and when it has no time limit.
    public static func countdown(for toast: OuroToast, held: Bool) -> Double? {
        held ? nil : toast.seconds
    }

    /// The dismiss and action buttons' target, in points.
    public static let dismissTarget: CGFloat = 44

    /// Toasts drop in from the top, where the system's own notices appear, or crossfade under Reduce Motion.
    public static func appearance(reduceMotion: Bool) -> OuroAppearance {
        .choose(.drop, reduceMotion: reduceMotion)
    }

    /// How a toast arrives: on the `enter` spring, falling from above while growing from 92%; or a crossfade.
    /// Livelier than other arrivals, so the landing visibly overshoots and settles, as the system's own notices do.
    public static func arrival(reduceMotion: Bool) -> OuroMotion.Step {
        reduceMotion ? OuroMotion.step(.enter, reduceMotion: true) : .spring(visualDuration: 0.5, bounce: 0.32)
    }
    /// The scale a toast shrinks to as it leaves, so it recedes rather than slides off.
    public static let departureScale = 0.96
    /// How a toast leaves: on the quick `exit` spring, back up the way it came; or a crossfade.
    public static func departure(reduceMotion: Bool) -> OuroMotion.Step { OuroMotion.step(.exit, reduceMotion: reduceMotion) }

    /// A shadow: its opacity of black, blur radius and drop, in points.
    public struct Shadow: Sendable, Equatable {
        public var opacity: Double
        public var radius: CGFloat
        public var y: CGFloat
    }
    /// The stack's one shadow, under the front toast: light, as Apple's notices cast, not a web card's halo.
    public static let shadow = Shadow(opacity: 0.12, radius: 20, y: 6)
    /// The hairline every toast is edged with, in its words' colour at ``edgeOpacity(scheme:)``: a light toast on a light
    /// page doesn't lean on its shadow alone.
    public static let edgeWidth: CGFloat = 0.5
    public static func edgeOpacity(scheme: ColorScheme) -> Double { scheme == .dark ? 0.12 : 0.08 }
    /// The largest text size a toast's icon grows to: a step short of the largest, so it never outweighs the words.
    public static let largestIconSize = DynamicTypeSize.accessibility3

    /// How long a toast's words take to fade out as it tucks, or in as it comes to the front: quick, so they are gone
    /// before its plate slides under the toast arriving and two sets of words never share a place.
    static let wordsFadeSeconds = 0.1
    static var wordsFade: Animation { OuroMotion.clocked(.easeOut(duration: wordsFadeSeconds), on: OuroMotion.clock) }

    /// The size a toast tucked behind a newer one takes: the newer one's, or its own until the newer one is measured,
    /// so it never collapses to nothing for an arrival's first frames.
    static func tuckedSize(front: CGSize?, own: CGSize?) -> CGSize? { front ?? own }

    /// Whether a toast's first measurement resizes the plates tucked behind it: the front toast's, with others behind
    /// it. That change is animated with the arrival, never applied bare.
    static func resizesTuckedOnMeasure(depth: Int, count: Int, measured: Bool) -> Bool {
        depth == 0 && count > 1 && !measured
    }

    /// How strongly a toast's hairline edge and the theme's border show.
    public struct Outline: Equatable, Sendable {
        public var edge: Double
        public var border: Double
    }

    /// A tucked toast has only the hairline, so a stack reads as one toast with depth rather than outlined cards; the
    /// front one has the theme's border when solid, the hairline on glass.
    public static func outline(solid: Bool, tucked: Bool, edge: Double) -> Outline {
        if tucked { return Outline(edge: edge, border: 0) }
        return solid ? Outline(edge: 0, border: 1) : Outline(edge: edge, border: 0)
    }

    /// Whether a toast casts ``shadow``: only the front one, so tucked toasts never add theirs into a grey band.
    public static func castsShadow(tucked: Bool) -> Bool { !tucked }
    /// How far a toast's shadow reaches past its edge: its blur plus its drop.
    public static let shadowReach: CGFloat = shadow.radius + shadow.y
    /// The accessibility identifier of the region the toasts show in, for UI tests.
    public static let regionIdentifier = "ouro.toasts"
    /// The accessibility identifier of each toast, which `OuroHXTesting`'s audit measures as the toast's own.
    public static let toastIdentifier = "ouro.toast"
    /// A toast's height on one line: 56 points.
    public static let height: CGFloat = 56
    /// The scale a toast grows from as it arrives.
    public static let arrivalScale = 0.92
    /// The corner radius: a capsule on one line, a rounded rectangle when the words wrap.
    public static let cornerRadius: CGFloat = 26
    /// The widest a toast grows, below the accessibility text sizes.
    public static let maximumWidth: CGFloat = 420
    /// How far a toast is dragged up (or flung) before it goes; below that it springs back.
    public static let dismissDistance: CGFloat = 30
    /// How much of a downward drag a toast follows: a rubber band, as there is nowhere for it to go.
    public static let rubberBand: CGFloat = 0.3

    /// Where a toast sits in the stack, `depth` toasts behind the newest. Collapsed, older toasts tuck behind the
    /// newest, peeking out 12 then 22 points below it, 95% then 90% the size, on glass over an opaque plate shaded 4%
    /// then 8% toward the words' colour (so the page never shows through a peek), with their words hidden; expanded (VoiceOver or Switch Control
    /// running, or the stack tapped open) they list down the screen, `above` points of newer toasts over each. Under
    /// Reduce Motion nothing is scaled, and the host moves toasts to their places without animating them there.
    public static func placement(depth: Int, expanded: Bool, above: CGFloat, reduceMotion: Bool = false) -> (offset: CGFloat, scale: Double, shade: Double, showsWords: Bool) {
        if expanded || depth == 0 { return (depth == 0 ? 0 : above + CGFloat(depth) * stackSpacing, 1, 0, true) }
        let peek = tuck + CGFloat(depth - 1) * (tuck - 2)
        return (peek, reduceMotion ? 1 : 1 - 0.05 * Double(depth), 0.04 * Double(depth), false)
    }

    /// The gap between expanded toasts.
    public static let stackSpacing: CGFloat = 8
    /// How far the first older toast peeks out below the one in front, collapsed; the next peeks 10 points more.
    public static let tuck: CGFloat = 12

    /// Where a drag of `translation` points (negative is up) leaves the toast: following the finger up, and only a
    /// third of the way down.
    public static func dragOffset(_ translation: CGFloat) -> CGFloat {
        translation < 0 ? translation : translation * rubberBand
    }

    /// Whether letting go of a drag dismisses the toast: dragged far enough up, or flung up.
    public static func dragDismisses(translation: CGFloat, predictedEnd: CGFloat) -> Bool {
        translation < -dismissDistance || predictedEnd < -dismissDistance * 3
    }
}

/// Sends toasts: `@Environment(\.ouroToast) private var toast`, then `toast("Saved")`. `.ouroToaster()` at the app's
/// root installs a working one; without it, sending a toast logs the fix and shows nothing.
public struct OuroToaster: Sendable {
    /// Whether an `.ouroToaster()` above this view will show the toasts.
    public let isInstalled: Bool
    private let send: @MainActor @Sendable (OuroToast) -> Void
    private let remove: @MainActor @Sendable (String?) -> Void

    init(isInstalled: Bool, send: @escaping @MainActor @Sendable (OuroToast) -> Void, remove: @escaping @MainActor @Sendable (String?) -> Void) {
        self.isInstalled = isInstalled
        self.send = send
        self.remove = remove
    }

    static let missing = OuroToaster(
        isInstalled: false,
        send: { toast in
            Logger(subsystem: "bot.ouro.hx", category: "OuroToast").fault("OuroToast \"\(toast.message, privacy: .public)\" was not shown: no .ouroToaster() above the view that sent it. Fix: add .ouroToaster() to your app's root view; if it is on the sending view itself, send from a child view instead.")
        },
        remove: { _ in }
    )

    /// Shows a toast, and returns its id for ``dismiss(_:)``.
    @MainActor @discardableResult
    public func callAsFunction(_ message: String, description: String? = nil, tone: OuroTone = .secondary, systemImage: String? = nil, action: OuroToastAction? = nil, duration: OuroToastDuration = .automatic, id: String? = nil) -> String {
        show(OuroToast(message, description: description, tone: tone, systemImage: systemImage, action: action, duration: duration, id: id))
    }

    /// Shows a toast you built, and returns its id.
    @MainActor @discardableResult
    public func show(_ toast: OuroToast) -> String {
        send(toast)
        return toast.id
    }

    /// Dismisses one toast by id, or all of them.
    @MainActor
    public func dismiss(_ id: String? = nil) { remove(id) }
}

extension EnvironmentValues {
    /// Sends toasts to the nearest `.ouroToaster()`.
    @Entry public var ouroToast: OuroToaster = .missing
}

extension View {
    /// Shows the toasts sent with `@Environment(\.ouroToast)` from anywhere below: put it once at the app's root,
    /// inside `.ouroTheme(_:)`. Toasts drop in at the top as Liquid Glass capsules (a material before iOS 26), up to
    /// three tucked behind one another (one at the accessibility text sizes; listed out while VoiceOver or Switch
    /// Control runs, or when the stack is tapped). VoiceOver hears each once (a destructive one at once, the others
    /// when it is free), a toast plays its tone's haptic as it arrives, a swipe up dismisses one, and each has a
    /// 44-point dismiss button named `closeLabel`. `label` names the region for VoiceOver, and `showAllLabel` names
    /// the region's action that lays a stack out, for Voice Control and Full Keyboard Access.
    public func ouroToaster(label: String = "Notifications", closeLabel: String = "Dismiss", showAllLabel: String = "Show all") -> some View {
        modifier(OuroToasterModifier(label: label, closeLabel: closeLabel, showAllLabel: showAllLabel))
    }
}

@MainActor @Observable
final class OuroToastModel {
    var queue = OuroToastQueue()
    /// The open sheets, oldest first. The newest hosts the toasts; with none open, the root does.
    private var sheets: [UUID] = []

    /// Showings already announced, and when each counting one goes. A toast that moves to another host (a sheet
    /// opening or closing) is drawn afresh there, so these live here rather than in the view.
    @ObservationIgnored private var heard: Set<UUID> = []
    @ObservationIgnored private var deadlines: [UUID: Date] = [:]

    func enter(_ sheet: UUID) { sheets.append(sheet) }
    func leave(_ sheet: UUID) { sheets.removeAll { $0 == sheet } }
    /// Whether `host` (a sheet, or nil for the root) draws the toasts.
    func hosts(_ host: UUID?) -> Bool { sheets.last == host }

    /// True the first time a showing is drawn anywhere: the moment to announce it and play its haptic.
    func arrives(_ showing: UUID) -> Bool { heard.insert(showing).inserted }

    /// Seconds left before `toast` goes, or nil while it waits. Held, it waits, and the time starts over afterwards.
    func remaining(for toast: OuroToast, held: Bool, now: Date = .now) -> Double? {
        guard let seconds = OuroToastMetrics.countdown(for: toast, held: held) else {
            deadlines[toast.showing] = nil
            return nil
        }
        let deadline = deadlines[toast.showing] ?? now.addingTimeInterval(seconds)
        deadlines[toast.showing] = deadline
        return max(0, deadline.timeIntervalSince(now))
    }

    /// Changes how many show at once. A toast sent back to wait forgets it was heard and its time, so it shows
    /// afresh when its turn comes.
    func setLimit(_ limit: Int) {
        queue.limit = limit
        for toast in queue.waiting {
            heard.remove(toast.showing)
            deadlines[toast.showing] = nil
        }
    }

    func dismiss(_ id: String?) {
        queue.dismiss(id)
        let live = Set((queue.visible + queue.waiting).map(\.showing))
        heard.formIntersection(live)
        deadlines = deadlines.filter { live.contains($0.key) }
    }
}

extension EnvironmentValues {
    @Entry var ouroToastModel: OuroToastModel? = nil
    @Entry var ouroToasterLabels = OuroToasterLabels(label: "Notifications", closeLabel: "Dismiss", showAllLabel: "Show all")
}

struct OuroToasterLabels: Sendable {
    var label: String
    var closeLabel: String
    var showAllLabel: String
}

/// Draws the toasts where this view is when it is the newest host: the root, or an open sheet.
struct OuroToastHost: ViewModifier {
    var isRoot = false
    @Environment(\.ouroToastModel) private var model
    @Environment(\.ouroToast) private var toaster
    @Environment(\.ouroToasterLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.isPresented) private var isPresented
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.accessibilitySwitchControlEnabled) private var switchControl
    @State private var id = UUID()
    @State private var sizes: [String: CGSize] = [:]
    @State private var expandedByHand = false

    func body(content: Content) -> some View {
        if let model {
            content
                .overlay(alignment: .top) {
                    if model.hosts(isRoot ? nil : id) {
                        let visible = model.queue.visible
                        let expanded = expandedByHand || voiceOver || switchControl
                        ZStack(alignment: .top) {
                            ForEach(Array(visible.enumerated()), id: \.element.id) { index, toast in
                                let depth = visible.count - 1 - index
                                let above = visible[(index + 1)...].reduce(CGFloat(0)) { $0 + (sizes[$1.id]?.height ?? OuroToastMetrics.height) }
                                let place = OuroToastMetrics.placement(depth: depth, expanded: expanded, above: above, reduceMotion: reduceMotion)
                                let front = visible.last.flatMap { sizes[$0.id] }
                                OuroToastView(toast: toast, closeLabel: labels.closeLabel, showsWords: place.showsWords, tucked: place.showsWords ? nil : OuroToastMetrics.tuckedSize(front: front, own: sizes[toast.id]), shade: place.shade) { toaster.dismiss(toast.id) }
                                    .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
                                        guard place.showsWords else { return }
                                        // The front toast's first size resizes the plates tucked behind it, so it
                                        // lands on the arrival's spring: set bare, it snapped in one frame and dropped
                                        // it (W8 round 7).
                                        if OuroToastMetrics.resizesTuckedOnMeasure(depth: depth, count: visible.count, measured: sizes[toast.id] != nil) {
                                            withAnimation(OuroToastMetrics.arrival(reduceMotion: reduceMotion).animation) { sizes[toast.id] = size }
                                        } else {
                                            sizes[toast.id] = size
                                        }
                                    }
                                    // A tucked toast can't be dragged or tapped unseen; a tap on the front one opens
                                    // the stack.
                                    .allowsHitTesting(place.showsWords)
                                    .scaleEffect(place.scale, anchor: .bottom)
                                    .offset(y: place.offset)
                                    .zIndex(Double(index))
                                    .transaction { if reduceMotion { $0.animation = nil } }
                                    // A tucked toast, behind the one in front, just fades as the stack empties: three
                                    // glass toasts rising out together dropped a frame (W8 round 6).
                                    .transition(place.showsWords ? OuroToastMetrics.appearance(reduceMotion: reduceMotion).transition : .opacity)
                            }
                        }
                        // Tapping a collapsed stack's words lays it out; its buttons take their own taps first. It tucks
                        // back once it empties.
                        // Off once open, so the words aren't offered as tap targets (the audit read them as too small).
                        .gesture(TapGesture().onEnded { showAll(count: visible.count) }, isEnabled: !expanded)
                        .animation(OuroMotion.animation(.layout, reduceMotion: reduceMotion), value: expanded)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                        .frame(maxWidth: typeSize.isAccessibilitySize ? .infinity : OuroToastMetrics.maximumWidth + 32)
                        // The region is the stack's own width, not the screen's, so the audit's toast footprint is too.
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(labels.label)
                        .accessibilityIdentifier(OuroToastMetrics.regionIdentifier)
                        .accessibilityAction(named: Text(labels.showAllLabel)) { showAll(count: visible.count) }
                        .frame(maxWidth: .infinity)
                        .onChange(of: visible.isEmpty) { _, empty in if empty { expandedByHand = false } }
                        .onChange(of: visible.map(\.id)) { _, ids in sizes = sizes.filter { ids.contains($0.key) } }
                    }
                }
                .onAppear { if !isRoot { model.enter(id) } }
                // A sheet hands the toasts back as it starts to close, so one sent on its way out shows at the root.
                .onChange(of: isPresented) { _, now in if !isRoot, !now { model.leave(id) } }
                .onDisappear { if !isRoot { model.leave(id) } }
                .onChange(of: typeSize.isAccessibilitySize, initial: true) { _, large in
                    if isRoot { model.setLimit(OuroToastMetrics.maximumVisible(accessibilitySize: large)) }
                }
        } else {
            content
        }
    }

    private func showAll(count: Int) {
        guard count > 1, !expandedByHand else { return }
        withAnimation(OuroMotion.animation(.layout, reduceMotion: reduceMotion)) { expandedByHand = true }
    }
}

private struct OuroToasterModifier: ViewModifier {
    let label: String
    let closeLabel: String
    let showAllLabel: String
    @State private var model = OuroToastModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let model = model
        let reduceMotion = reduceMotion
        let toaster = OuroToaster(
            isInstalled: true,
            send: { toast in withAnimation(OuroToastMetrics.arrival(reduceMotion: reduceMotion).animation) { model.queue.show(toast) } },
            remove: { id in withAnimation(OuroToastMetrics.departure(reduceMotion: reduceMotion).animation) { model.dismiss(id) } }
        )
        content
            .modifier(OuroToastHost(isRoot: true))
            .environment(\.ouroToast, toaster)
            .environment(\.ouroToastModel, model)
            .environment(\.ouroToasterLabels, OuroToasterLabels(label: label, closeLabel: closeLabel, showAllLabel: showAllLabel))
    }
}

struct OuroToastView: View {
    let toast: OuroToast
    let closeLabel: String
    /// False for a toast tucked behind a newer one: its surface peeks out, its words and buttons are hidden.
    var showsWords = true
    /// The size of the toast in front, when this one is tucked behind it.
    var tucked: CGSize? = nil
    /// How far its surface is shaded toward its words' colour: deeper the further back it is tucked.
    var shade: Double = 0
    /// Off only in snapshot tests: `ImageRenderer` draws nothing inside a view with `accessibilityFocused`.
    var tracksFocus = true
    /// Off only in snapshot tests: `ImageRenderer` draws nothing for glass or a material, so the toast draws its solid
    /// surface (the one for Increase Contrast and Reduce Transparency) there.
    var rendersGlass = true
    let dismiss: @MainActor () -> Void
    @Environment(\.ouroToastModel) private var model
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.dynamicTypeSize) private var typeSize
    /// Where the finger has the toast. A plain state, not a gesture state, so a toast flung away leaves from where it
    /// was let go rather than snapping back first.
    @State private var drag: CGFloat = 0
    /// Resets by itself when the system cancels the drag (a call, a sheet), so a cancelled drag can't hold the
    /// countdown for good.
    @GestureState private var dragging = false
    @State private var leaving = false
    /// VoiceOver or Switch Control on any part of the toast, which holds its countdown.
    @AccessibilityFocusState private var focus: Part?
    @State private var hovering = false
    @State private var landed = false

    enum Part: Hashable { case words, action, dismiss }

    private struct Held: ViewModifier {
        let focus: AccessibilityFocusState<Part?>.Binding
        let part: Part
        let on: Bool
        func body(content: Content) -> some View {
            if on { content.accessibilityFocused(focus, equals: part) } else { content }
        }
    }

    private struct Countdown: Hashable {
        let showing: UUID
        let held: Bool
    }

    private var held: Bool { focus != nil || hovering || dragging }

    var body: some View {
        let p = OuroToastPalette(tone: toast.tone, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        let shape = RoundedRectangle(cornerRadius: OuroToastMetrics.cornerRadius, style: .continuous)
        let large = typeSize.isAccessibilitySize
        // So is one whose theme's surface the system's vibrant words would not read on. A tucked toast stays on its
        // glass: the opaque plate under it already keeps the page from showing through, and switching to solid as it
        // tucked dropped a frame on arrivals, even on a frame of its own (W8 round 6).
        let solid = contrast == .increased || reduceTransparency || !rendersGlass || !p.vibrant
        // On glass the words take the system's vibrant label styles, which read on the opaque surface under it (the
        // gallery's accessibility audit measures them in light and dark); solid, the theme's colours, made readable on
        // that surface. Theme colours inside the glass cost a dropped frame on every departure (W8 frame captures).
        let message: AnyShapeStyle = solid ? AnyShapeStyle(Color(p.message)) : AnyShapeStyle(.primary)
        // iOS 27's vibrant secondary style read below 5:1 on the toast's surface, so there the description takes the
        // theme's own colour, made readable on that surface, on glass too.
        let themedDescription = solid || OuroToastMetrics.themedDescriptionOnGlass
        let secondary: AnyShapeStyle = themedDescription ? AnyShapeStyle(Color(p.description)) : AnyShapeStyle(.secondary)
        // A tucked toast draws only its surface: no words or buttons exist for VoiceOver, the audit or a stray tap to
        // find (hiding them still left them in iOS 26's accessibility tree, scaled below 44 points).
        // Tucking, the words fade out as the plate moves back rather than vanishing first, so no plate is ever blank.
        ZStack(alignment: .top) {
        if showsWords {
        HStack(alignment: large ? .top : .center, spacing: 10) {
            // The icon sits on the message's first line, not between the message and description.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let name = toast.symbol {
                    Image(systemName: name)
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(Color(p.icon))
                        // It grows with the words, a step short of the largest sizes so it never outweighs them.
                        .dynamicTypeSize(...OuroToastMetrics.largestIconSize)
                        // It bounces once as the toast lands, on the frame its haptic plays.
                        .symbolEffect(.bounce, value: landed)
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(toast.message)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(message)
                            .fixedSize(horizontal: false, vertical: true)
                        if let description = toast.description {
                            Text(description)
                                .font(.footnote)
                                .foregroundStyle(secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: large ? .infinity : nil, alignment: .leading)
                    .accessibilityElement(children: .combine)
                    .modifier(Held(focus: $focus, part: .words, on: tracksFocus))
                    // At the accessibility sizes the action goes under the words, so neither has to squeeze.
                    if large, let action = toast.action { actionButton(action, palette: p).modifier(Held(focus: $focus, part: .action, on: tracksFocus)) }
                }
            }
            if !large, let action = toast.action {
                // A hairline, then the action as tinted words: no button inside the capsule.
                Rectangle()
                    .fill(Color(p.divider))
                    .frame(width: 1, height: 22)
                    .accessibilityHidden(true)
                actionButton(action, palette: p).fixedSize().modifier(Held(focus: $focus, part: .action, on: tracksFocus))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .dynamicTypeSize(...OuroToastMetrics.largestIconSize)
                    .foregroundStyle(secondary)
                    // At least 44 points, and more as the mark grows, so it is never clipped at the largest sizes.
                    .frame(minWidth: OuroToastMetrics.dismissTarget, minHeight: OuroToastMetrics.dismissTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.ouroPress)
            .accessibilityLabel(closeLabel)
            .modifier(Held(focus: $focus, part: .dismiss, on: tracksFocus))
            .padding(.trailing, -10)
        }
        .padding(.leading, 16)
        .padding(.trailing, 10)
        .padding(.vertical, 6)
        .frame(minHeight: OuroToastMetrics.height)
        // The words fade in 0.1 s on their own clock, out as a toast tucks and in as it comes to the front, before its
        // plate has moved far, so two sets of words never share a place (taste round 6). At the accessibility sizes
        // one toast shows and nothing tucks, so they keep the plain fade: the quick one, as the stack of three
        // there became one, left words the accessibility audit read as clipped, though none were on screen.
        .transition(large ? .opacity : .opacity.animation(OuroToastMetrics.wordsFade))
        } else {
            Color.clear.frame(minHeight: OuroToastMetrics.height).accessibilityHidden(true)
        }
        }
        // Tucked behind a newer toast, it takes that toast's size, so its edge peeks out evenly below it.
        .frame(width: tucked?.width, height: tucked?.height, alignment: .top)
        .clipped()
        // It hugs its words, up to the stack's width; at the accessibility sizes it spans it.
        .frame(maxWidth: large ? .infinity : nil)
        .modifier(ToastSurface(shape: shape, palette: p, solid: solid, casts: OuroToastMetrics.castsShadow(tucked: tucked != nil), tucked: tucked != nil, shade: shade, edge: OuroToastMetrics.edgeOpacity(scheme: scheme), rendersGlass: rendersGlass))
        .offset(y: drag)
        .opacity(reduceMotion ? 1 - min(0.7, abs(drag) / 90) : 1)
        .gesture(
            DragGesture(minimumDistance: 8)
                .updating($dragging) { _, state, _ in state = true }
                .onChanged { value in
                    drag = OuroToastMetrics.dragOffset(value.translation.height)
                }
                .onEnded { value in
                    if OuroToastMetrics.dragDismisses(translation: value.translation.height, predictedEnd: value.predictedEndTranslation.height) {
                        leaving = true
                        dismiss()
                    }
                }
        )
        // Let go short of dismissing, or cancelled: it springs back.
        .onChange(of: dragging) { _, now in
            guard !now, !leaving, drag != 0 else { return }
            withAnimation(OuroMotion.animation(.settle, reduceMotion: reduceMotion)) { drag = 0 }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(OuroToastMetrics.toastIdentifier)
        .onHover { hovering = $0 }
        .task(id: toast.showing) {
            // Once per showing, even when a sheet opening or closing draws it again in another place.
            guard model?.arrives(toast.showing) ?? true else { return }
            OuroAnnounce.post(toast.announcement, priority: toast.tone.announcementPriority(for: .toast))
            if let moment = toast.tone.haptic { OuroHaptics.play(moment) }
            if !reduceMotion { landed.toggle() }
        }
        // Runs again for a new showing, and whenever someone arrives on or leaves the toast.
        .task(id: Countdown(showing: toast.showing, held: held)) {
            let held = held
            guard let seconds = model?.remaining(for: toast, held: held) ?? OuroToastMetrics.countdown(for: toast, held: held) else { return }
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { dismiss() }
        }
    }

    /// The action as tinted, semibold words with a 44-point target, as the system's own Undo is.
    private func actionButton(_ action: OuroToastAction, palette p: OuroToastPalette) -> some View {
        Button {
            action.handler()
            dismiss()
        } label: {
            Text(action.label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(p.action))
                .fixedSize(horizontal: false, vertical: true)
                // Its target stays clear of the hairline before it, so the audit measures the words alone.
                .padding(.horizontal, 6)
                .frame(minWidth: OuroToastMetrics.dismissTarget, minHeight: OuroToastMetrics.dismissTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.ouroPress)
    }
}

/// A toast's surface: Liquid Glass from iOS 26, a thick material with a hairline before it, and the theme's opaque
/// popover colour with an outline under increased contrast or Reduce Transparency, where the words must not depend
/// on what is behind them.
private struct ToastSurface: ViewModifier {
    let shape: RoundedRectangle
    let palette: OuroToastPalette
    let solid: Bool
    /// Whether it casts the stack's shadow: the front toast only.
    let casts: Bool
    /// Whether it is tucked behind a newer toast.
    let tucked: Bool
    /// How far it is shaded toward its words' colour (tucked), and how strongly its hairline edge shows.
    let shade: Double
    let edge: Double
    /// Off only in snapshot tests, where `ImageRenderer` draws nothing inside any glass effect, `.identity` included.
    /// It never changes while a toast shows.
    let rendersGlass: Bool

    func body(content: Content) -> some View {
        let s = OuroToastMetrics.shadow
        let shadow = Color.black.opacity(casts ? s.opacity : 0)
        // One structure whether glass or solid, so a toast tucking (and going solid) keeps its identity and its words
        // fade out with the move; switching branches here replaced the toast and left a blank plate for a few frames.
        if rendersGlass, #available(iOS 26, macOS 26, visionOS 26, *) {
            // Glass over the theme's opaque surface: the glass gives the edge light and depth, and the surface keeps the
            // page's words from reading through, so the toast's words hold 5:1 over any page (`contrast.text`; at 55%
            // and 85% the accessibility audit still measured the page through it). That fill also casts the shadow.
            // Solid (Increase Contrast, Reduce Transparency, tucked): no glass, and an edge.
            content
                .glassEffect(solid ? .identity : Self.glass(tint: Color(palette.surface)), in: shape)
                .background(plate(shadow, s))
                .overlay(outline(solid: solid))
        } else {
            content
                .background(plate(shadow, s))
                .overlay(outline(solid: true))
        }
    }

    /// The regular glass; on iOS 27, whose glass lifts what is under it toward white (a dark toast's description fell
    /// below 5:1), tinted with the toast's own surface so it stays near it.
    @available(iOS 26, macOS 26, visionOS 26, *)
    private static func glass(tint: Color) -> Glass {
        if #available(iOS 27, macOS 27, visionOS 27, *) { return .regular.tint(tint.opacity(OuroToastMetrics.glassSurfaceTint)) }
        return .regular
    }

    /// The opaque surface, shaded when tucked, casting the stack's shadow.
    private func plate(_ shadow: Color, _ s: OuroToastMetrics.Shadow) -> some View {
        shape.fill(Color(palette.surface))
            .overlay(shape.fill(Color(palette.message).opacity(shade)))
            .shadow(color: shadow, radius: s.radius, y: s.y)
    }

    /// The theme's border when solid (raised under increased contrast); on glass, a hairline in the words' colour.
    private func outline(solid: Bool) -> some View {
        let o = OuroToastMetrics.outline(solid: solid, tucked: tucked, edge: edge)
        return ZStack {
            shape.strokeBorder(Color(palette.message).opacity(o.edge), lineWidth: OuroToastMetrics.edgeWidth)
            shape.strokeBorder(Color(palette.border).opacity(o.border), lineWidth: 1)
        }
    }
}
