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

/// A short message at the bottom of the screen that VoiceOver reads once and that dismisses itself: web's `toast`.
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
    /// New for every toast made, so one that replaces another under the same `id` is a new showing: VoiceOver hears
    /// it and its countdown starts over.
    public let showing = UUID()

    public init(_ message: String, description: String? = nil, tone: OuroTone = .secondary, action: OuroToastAction? = nil, duration: OuroToastDuration = .automatic, id: String? = nil) {
        self.id = id ?? UUID().uuidString
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

    public init(tone: OuroTone, style: OuroHXStyle) {
        let c = style.colors
        surface = OuroInk.r(c.popover)
        border = OuroColor.push(OuroInk.r(c.border), against: surface, to: style.contrast == .increased ? OuroColor.increasedLineContrast : 1)
        message = OuroInk.readable(OuroInk.r(c.popoverForeground), on: surface, style)
        description = OuroInk.readable(OuroInk.r(c.mutedForeground), on: surface, style)
        icon = OuroInk.readable(tone == .secondary ? OuroInk.r(c.popoverForeground) : OuroInk.r(tone.fill(c).fill), on: surface, style)
    }
}

/// Metrics and motion every toast shares, as data.
public enum OuroToastMetrics {
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

    /// Toasts slide up from the bottom, or crossfade under Reduce Motion.
    public static func appearance(reduceMotion: Bool) -> OuroAppearance {
        .choose(.move(edge: .bottom), reduceMotion: reduceMotion)
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
            Logger(subsystem: "bot.ouro.hx", category: "OuroToast").fault("OuroToast \"\(toast.message, privacy: .public)\" was not shown. Fix: add .ouroToaster() to your app's root view.")
        },
        remove: { _ in }
    )

    /// Shows a toast, and returns its id for ``dismiss(_:)``.
    @MainActor @discardableResult
    public func callAsFunction(_ message: String, description: String? = nil, tone: OuroTone = .secondary, action: OuroToastAction? = nil, duration: OuroToastDuration = .automatic, id: String? = nil) -> String {
        show(OuroToast(message, description: description, tone: tone, action: action, duration: duration, id: id))
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
    /// inside `.ouroTheme(_:)`. Toasts stack at the bottom, up to three (one at the accessibility text sizes); VoiceOver hears each once (a destructive one at once,
    /// the others when it is free), a toast plays its tone's haptic, a swipe down dismisses one, and each has a
    /// 44-point dismiss button named `closeLabel`. `label` names the region for VoiceOver.
    public func ouroToaster(label: String = "Notifications", closeLabel: String = "Dismiss") -> some View {
        modifier(OuroToasterModifier(label: label, closeLabel: closeLabel))
    }
}

@MainActor @Observable
final class OuroToastModel {
    var queue = OuroToastQueue()
    /// The open sheets, oldest first. The newest hosts the toasts; with none open, the root does.
    private var sheets: [UUID] = []

    func enter(_ sheet: UUID) { sheets.append(sheet) }
    func leave(_ sheet: UUID) { sheets.removeAll { $0 == sheet } }
    /// Whether `host` (a sheet, or nil for the root) draws the toasts.
    func hosts(_ host: UUID?) -> Bool { sheets.last == host }
}

extension EnvironmentValues {
    @Entry var ouroToastModel: OuroToastModel? = nil
    @Entry var ouroToasterLabels = OuroToasterLabels(label: "Notifications", closeLabel: "Dismiss")
}

struct OuroToasterLabels: Sendable {
    var label: String
    var closeLabel: String
}

/// Draws the toasts where this view is when it is the newest host: the root, or an open sheet.
struct OuroToastHost: ViewModifier {
    var isRoot = false
    @Environment(\.ouroToastModel) private var model
    @Environment(\.ouroToast) private var toaster
    @Environment(\.ouroToasterLabels) private var labels
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var id = UUID()

    func body(content: Content) -> some View {
        if let model {
            content
                .overlay(alignment: .bottom) {
                    if model.hosts(isRoot ? nil : id) {
                        VStack(spacing: 8) {
                            ForEach(model.queue.visible) { toast in
                                OuroToastView(toast: toast, closeLabel: labels.closeLabel) { toaster.dismiss(toast.id) }
                                    .transition(OuroToastMetrics.appearance(reduceMotion: reduceMotion).transition)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                        .frame(maxWidth: 560)
                        .accessibilityElement(children: .contain)
                        .accessibilityLabel(labels.label)
                    }
                }
                .onAppear { if !isRoot { model.enter(id) } }
                .onDisappear { if !isRoot { model.leave(id) } }
                .onChange(of: typeSize.isAccessibilitySize, initial: true) { _, large in
                    if isRoot { model.queue.limit = OuroToastMetrics.maximumVisible(accessibilitySize: large) }
                }
        } else {
            content
        }
    }
}

private struct OuroToasterModifier: ViewModifier {
    let label: String
    let closeLabel: String
    @State private var model = OuroToastModel()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let model = model
        let reduceMotion = reduceMotion
        let toaster = OuroToaster(
            isInstalled: true,
            send: { toast in withAnimation(OuroToastMetrics.appearance(reduceMotion: reduceMotion).step(reduceMotion: reduceMotion).animation) { model.queue.show(toast) } },
            remove: { id in withAnimation(OuroToastMetrics.appearance(reduceMotion: reduceMotion).step(reduceMotion: reduceMotion).animation) { model.queue.dismiss(id) } }
        )
        content
            .modifier(OuroToastHost(isRoot: true))
            .environment(\.ouroToast, toaster)
            .environment(\.ouroToastModel, model)
            .environment(\.ouroToasterLabels, OuroToasterLabels(label: label, closeLabel: closeLabel))
    }
}

struct OuroToastView: View {
    let toast: OuroToast
    let closeLabel: String
    /// Off only in snapshot tests: `ImageRenderer` draws nothing inside a view with `accessibilityFocused`.
    var tracksFocus = true
    let dismiss: @MainActor () -> Void
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @GestureState private var drag: CGFloat = 0
    /// VoiceOver or Switch Control on any part of the toast, which holds its countdown.
    @AccessibilityFocusState private var focus: Part?
    @State private var hovering = false

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

    var body: some View {
        let p = OuroToastPalette(tone: toast.tone, style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        HStack(alignment: typeSize.isAccessibilitySize ? .top : .center, spacing: 10) {
            // The icon sits on the message's first line, as in a banner, not between the message and description.
            HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let name = toast.tone.systemImage(for: .toast) {
                Image(systemName: name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(p.icon))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(toast.message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color(p.message))
                    .fixedSize(horizontal: false, vertical: true)
                if let description = toast.description {
                    Text(description)
                        .font(.footnote)
                        .foregroundStyle(Color(p.description))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .modifier(Held(focus: $focus, part: .words, on: tracksFocus))
                // At the accessibility sizes the action goes under the words, so neither has to squeeze.
                if typeSize.isAccessibilitySize, let action = toast.action { actionButton(action).modifier(Held(focus: $focus, part: .action, on: tracksFocus)) }
            }
            }
            if !typeSize.isAccessibilitySize, let action = toast.action {
                actionButton(action).fixedSize().modifier(Held(focus: $focus, part: .action, on: tracksFocus))
            }
            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Color(p.message))
                    .frame(width: OuroToastMetrics.dismissTarget, height: OuroToastMetrics.dismissTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(closeLabel)
            .modifier(Held(focus: $focus, part: .dismiss, on: tracksFocus))
            .padding(.trailing, -8)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        // The shadow goes on the surface alone, and stays inside the 8-point gap above it (radius 10, 4 down, so 6
        // up). On the whole toast it shaded every glyph, and reaching the toast above it shaded that one's words; the
        // accessibility audit reads both as failed text contrast.
        .background {
            RoundedRectangle(cornerRadius: theme.radius(.xl), style: .continuous)
                .fill(Color(p.surface))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        }
        .overlay(RoundedRectangle(cornerRadius: theme.radius(.xl), style: .continuous).strokeBorder(Color(p.border), lineWidth: 1))
        .offset(y: reduceMotion ? 0 : max(0, drag))
        .opacity(reduceMotion ? 1 - min(0.6, max(0, drag) / 120) : 1)
        .gesture(
            DragGesture(minimumDistance: 12)
                .updating($drag) { value, state, _ in state = value.translation.height }
                .onEnded { value in if value.translation.height > 40 { dismiss() } }
        )
        .accessibilityElement(children: .contain)
        .onHover { hovering = $0 }
        .task(id: toast.showing) {
            OuroAnnounce.post(toast.announcement, priority: toast.tone.announcementPriority(for: .toast))
            if let moment = toast.tone.haptic { OuroHaptics.play(moment) }
        }
        // Restarts for a new showing, and whenever someone arrives on or leaves the toast.
        .task(id: Countdown(showing: toast.showing, held: focus != nil || hovering)) {
            guard let seconds = OuroToastMetrics.countdown(for: toast, held: focus != nil || hovering) else { return }
            try? await Task.sleep(for: .seconds(seconds))
            if !Task.isCancelled { dismiss() }
        }
    }

    private func actionButton(_ action: OuroToastAction) -> some View {
        OuroButton(action.label, tone: toast.tone == .destructive ? .destructive : .primary, variant: .soft, size: .sm) {
            action.handler()
            dismiss()
        }
    }
}
