#if canImport(XCTest) && (os(iOS) || os(macOS) || os(visionOS))
import Foundation

/// Ways for a UI test to move an app's own clock on by one tick, for a film timed by the app
/// (``OuroFeel/film(_:steps:tick:clock:advance:stall:during:)``).
public enum FeelClock {
    /// Posts the Darwin notification `name`, which reaches the app across processes on the same device or simulator.
    /// The app observes it (`CFNotificationCenterGetDarwinNotifyCenter`) and takes one tick each time. The film posts
    /// again only once the app shows the last tick, so no post is lost to coalescing.
    public static func darwinNotification(_ name: String) -> () -> Void {
        {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                                 CFNotificationName(name as CFString), nil, nil, true)
        }
    }
}
#endif
