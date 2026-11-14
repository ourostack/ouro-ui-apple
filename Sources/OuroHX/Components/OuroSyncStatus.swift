public import SwiftUI

/// Where a person's changes are, as on web: `saved` once they reached the server, `saving` while they travel,
/// `offline` while they wait on this device, `error` when the server refused them.
public enum OuroSyncState: String, CaseIterable, Sendable {
    case saved, saving, offline, error

    /// Offline and error are problems: they show Retry and are spoken.
    public var isProblem: Bool { self == .offline || self == .error }

    /// The SF Symbol for the state, each its own shape so the state never rests on colour.
    public var systemImage: String {
        switch self {
        case .saved: "checkmark"
        case .saving: "arrow.trianglehead.2.clockwise"
        case .offline: "icloud.slash"
        case .error: "exclamationmark.circle"
        }
    }
}

/// The words for each state, web's `SyncStatusLabels`, for apps in other languages or to say what is saved.
public struct OuroSyncStatusLabels: Sendable, Equatable {
    public var saved: String
    public var saving: String
    public var offline: String
    public var error: String
    public var retry: String

    public init(
        saved: String = "Saved",
        saving: String = "Saving…",
        offline: String = "Offline: changes are kept on this device",
        error: String = "Not saved: the server refused the changes",
        retry: String = "Retry"
    ) {
        self.saved = saved
        self.saving = saving
        self.offline = offline
        self.error = error
        self.retry = retry
    }

    public func words(_ state: OuroSyncState) -> String {
        switch state {
        case .saved: saved
        case .saving: saving
        case .offline: offline
        case .error: error
        }
    }
}

/// The resolved colours of a sync status line, web's mixes: saved and saving in the muted foreground mixed 12% toward
/// the foreground, offline in the warning colour 30% toward it, error in the destructive colour 20% toward it, each
/// at 5:1 on the page (7:1 under increased contrast); core claim `contrast.text`.
public struct OuroSyncStatusPalette: Sendable {
    public var quiet: Color.Resolved
    public var offline: Color.Resolved
    public var error: Color.Resolved
    public var retry: Color.Resolved

    public init(style: OuroHXStyle) {
        let c = style.colors
        let page = OuroInk.r(c.background)
        let fg = OuroInk.r(c.foreground)
        quiet = OuroInk.readable(OuroColor.mix(OuroInk.r(c.mutedForeground), fg, 0.12), on: page, style)
        offline = OuroInk.readable(OuroColor.mix(OuroInk.r(c.warning), fg, 0.3), on: page, style)
        error = OuroInk.readable(OuroColor.mix(OuroInk.r(c.destructive), fg, 0.2), on: page, style)
        retry = OuroInk.readable(fg, on: page, style)
    }

    public func color(_ state: OuroSyncState) -> Color.Resolved {
        switch state {
        case .saved, .saving: quiet
        case .offline: offline
        case .error: error
        }
    }
}

/// Metrics every ``OuroSyncStatus`` shares, as data.
public enum OuroSyncStatusMetrics {
    /// Web waits 1.5 seconds before speaking a problem, so it follows what the control that caused it says.
    public static let speakDelay: Duration = .milliseconds(1500)

    /// What VoiceOver hears when the state changes: a problem when it starts, and saved again once one clears. Every
    /// other save is silent, so a person typing isn't narrated.
    public static func announcement(from old: OuroSyncState, to new: OuroSyncState, labels: OuroSyncStatusLabels) -> String? {
        if new.isProblem && new != old { return labels.words(new) }
        if new == .saved && old.isProblem { return labels.saved }
        return nil
    }

    /// Whether the saving arrows turn: never under Reduce Motion.
    public static func spins(_ state: OuroSyncState, reduceMotion: Bool) -> Bool { state == .saving && !reduceMotion }
}

/// Ouro HX's sync status: one line that says where a person's changes are (saved, saving, offline or not saved),
/// with Retry while there is a problem, web's `SyncStatus`.
///
/// ```swift
/// OuroSyncStatus(store.isOnline ? (store.pending ? .saving : .saved) : .offline) { store.flush() }
/// ```
///
/// Each state has its own symbol and colour. VoiceOver hears it only when a problem starts and when it clears, so
/// every save is not narrated. The line keeps the size of its longest state, so a change never moves the page. Use a
/// toast to confirm one action, and an ``OuroBanner`` for a problem that blocks the page.
public struct OuroSyncStatus: View {
    let state: OuroSyncState
    let labels: OuroSyncStatusLabels
    let onRetry: (() -> Void)?
    @State private var spoken: OuroSyncState?
    @Environment(\.ouroTheme) private var theme
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(_ state: OuroSyncState, labels: OuroSyncStatusLabels = OuroSyncStatusLabels(), onRetry: (() -> Void)? = nil) {
        self.state = state
        self.labels = labels
        self.onRetry = onRetry
    }

    public var body: some View {
        let palette = OuroSyncStatusPalette(style: OuroHXStyle(theme: theme, scheme: scheme, contrast: contrast))
        ZStack(alignment: .leading) {
            // Every state laid out, unseen, so the line keeps its longest state's size.
            ForEach(OuroSyncState.allCases, id: \.self) { s in
                line(s, palette).hidden().accessibilityHidden(true)
            }
            line(state, palette)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .font(.subheadline)
        .task(id: state) {
            let old = spoken ?? state
            spoken = state
            guard let words = OuroSyncStatusMetrics.announcement(from: old, to: state, labels: labels) else { return }
            if state.isProblem { try? await Task.sleep(for: OuroSyncStatusMetrics.speakDelay) }
            guard !Task.isCancelled else { return }
            OuroAnnounce.post(words, priority: .default)
        }
    }

    private func line(_ s: OuroSyncState, _ palette: OuroSyncStatusPalette) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: s.systemImage)
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: OuroSyncStatusMetrics.spins(s, reduceMotion: reduceMotion))
                .accessibilityHidden(true)
            Text(labels.words(s))
                .fixedSize(horizontal: false, vertical: true)
            if let onRetry, s.isProblem {
                Button(action: onRetry) {
                    Text(labels.retry)
                        .fontWeight(.medium)
                        .underline()
                        .foregroundStyle(Color(palette.retry))
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .foregroundStyle(Color(palette.color(s)))
    }
}
