public import SwiftUI
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// A moment that earns a haptic, by name, so every screen plays the same feedback for the same moment. From
/// Spoonjoy's `KitchenHapticMoment` and Gatefold's inline `sensoryFeedback` calls, which share these feedbacks.
public struct OuroHapticMoment: Hashable, Sendable {
    public enum Weight: String, Hashable, Sendable { case light, medium, heavy }

    public enum Feedback: Hashable, Sendable {
        case selection
        case impact(weight: Weight, intensity: Double)
        case success
        case warning
        case error
    }

    public var name: String
    public var feedback: Feedback

    public init(name: String, feedback: Feedback) {
        self.name = name
        self.feedback = feedback
    }

    /// A choice changed: a tab, a segment, a picker row.
    public static let selected = OuroHapticMoment(name: "selected", feedback: .selection)
    /// Something ticked off: an ingredient, a list item, a to-do.
    public static let checked = OuroHapticMoment(name: "checked", feedback: .selection)
    /// A stepper moved one step.
    public static let stepped = OuroHapticMoment(name: "stepped", feedback: .selection)
    /// A page or step turned.
    public static let turned = OuroHapticMoment(name: "turned", feedback: .impact(weight: .light, intensity: 0.7))
    /// Something began that runs on: a timer, a cook session, a download.
    public static let started = OuroHapticMoment(name: "started", feedback: .impact(weight: .medium, intensity: 1))
    /// Something finished well: a timer ran out, a book or recipe finished.
    public static let finished = OuroHapticMoment(name: "finished", feedback: .success)
    /// About to do something that can't be undone.
    public static let warned = OuroHapticMoment(name: "warned", feedback: .warning)
    /// It didn't work.
    public static let failed = OuroHapticMoment(name: "failed", feedback: .error)

    /// SwiftUI's feedback for this moment. Where the device has no haptics engine, SwiftUI plays nothing.
    public var sensoryFeedback: SensoryFeedback {
        switch feedback {
        case .selection: .selection
        case let .impact(weight, intensity):
            .impact(weight: weight == .light ? .light : weight == .medium ? .medium : .heavy, intensity: intensity)
        case .success: .success
        case .warning: .warning
        case .error: .error
        }
    }
}

public enum OuroHaptics {
    /// Every named moment, in the order the docs list them.
    public static let table: [OuroHapticMoment] = [.selected, .checked, .stepped, .turned, .started, .finished, .warned, .failed]

    /// Plays a moment now, for code outside a view (a timer firing). Returns false and does nothing where there is no
    /// haptics engine: a Mac, an iPad, the Simulator.
    @MainActor @discardableResult
    public static func play(_ moment: OuroHapticMoment) -> Bool {
        #if os(iOS)
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return false }
        switch moment.feedback {
        case .selection: UISelectionFeedbackGenerator().selectionChanged()
        case let .impact(weight, intensity):
            UIImpactFeedbackGenerator(style: weight == .light ? .light : weight == .medium ? .medium : .heavy).impactOccurred(intensity: intensity)
        case .success: UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .warning: UINotificationFeedbackGenerator().notificationOccurred(.warning)
        case .error: UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        return true
        #else
        return false
        #endif
    }
}

extension View {
    /// Plays a moment's haptic when `trigger` changes.
    public func ouroHaptic(_ moment: OuroHapticMoment, trigger: some Equatable) -> some View {
        sensoryFeedback(moment.sensoryFeedback, trigger: trigger)
    }

    /// Plays a moment's haptic when `trigger` changes and `condition` holds for the old and new values.
    public func ouroHaptic<T: Equatable>(_ moment: OuroHapticMoment, trigger: T, condition: @escaping (T, T) -> Bool) -> some View {
        sensoryFeedback(moment.sensoryFeedback, trigger: trigger, condition: condition)
    }
}
