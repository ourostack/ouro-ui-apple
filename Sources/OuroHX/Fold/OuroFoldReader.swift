public import SwiftUI

/// Reads the fold and the hinge and hands the content its posture. On an OS before 27.1, or a screen with no fold,
/// the posture is `.single`. From Gatefold's `FoldReader` and `HingeObserver`.
///
/// ```swift
/// OuroFoldReader { posture, hinge in
///     switch posture {
///     case .tabletop(let split): StepAbove(split.first); ControlsBelow(split.second)
///     default: OnePage()
///     }
/// }
/// ```
public struct OuroFoldReader<Content: View>: View {
    private let rules: OuroFoldPosture.Rules
    private let content: (OuroFoldPosture, OuroHinge) -> Content
    @State private var hinge: OuroHinge = .none

    public init(rules: OuroFoldPosture.Rules = .standard, @ViewBuilder content: @escaping (OuroFoldPosture, OuroHinge) -> Content) {
        self.rules = rules
        self.content = content
    }

    public var body: some View {
        GeometryReader { proxy in
            content(OuroFoldPosture.resolve(size: proxy.size, hinge: hinge, regions: Self.divisions(in: proxy), rules: rules), hinge)
        }
        .ouroHinge($hinge)
    }

    /// The `.division` regions, inactive ones included, in the proxy's coordinates.
    public static func divisions(in proxy: GeometryProxy) -> [OuroFoldRegion] {
        if #available(iOS 27.1, macOS 27.1, *) {
            return proxy.reservedRegions(kind: .division, options: .includeInactive).map { OuroFoldRegion(frame: $0.frame, isActive: $0.isActive) }
        }
        return []
    }
}

private struct OuroHingeObserver: ViewModifier {
    @Binding var hinge: OuroHinge

    func body(content: Content) -> some View {
        if #available(iOS 27.1, macOS 27.1, *) {
            content.onHingeChange { _, new in
                guard let h = new.hinge else { hinge = .none; return }
                switch h.status {
                case .closed: hinge = .closed
                case .fullyOpen: hinge = .fullyOpen
                default: hinge = .partiallyOpen(angleDegrees: h.angle.degrees)
                }
            }
        } else {
            content
        }
    }
}

extension View {
    /// Keeps `hinge` up to date with the device's hinge (iOS 27.1); `.none` elsewhere.
    public func ouroHinge(_ hinge: Binding<OuroHinge>) -> some View { modifier(OuroHingeObserver(hinge: hinge)) }
}
