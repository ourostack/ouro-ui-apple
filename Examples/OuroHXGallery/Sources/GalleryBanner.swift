import UserNotifications

/// `-banner 1`: the gallery asks to send notifications, then sends one that shows as a banner over the page a second
/// after it is allowed, as a system notification can arrive over a page while the accessibility audit reads it.
/// ComponentClaimTests' `testTheAuditWaitsOutASystemBanner` uses it; without the argument the gallery never asks.
@MainActor final class GalleryBanner: NSObject, UNUserNotificationCenterDelegate {
    private static var shared: GalleryBanner?

    static func start() {
        guard UserDefaults.standard.bool(forKey: "banner"), shared == nil else { return }
        let banner = GalleryBanner()
        shared = banner
        UNUserNotificationCenter.current().delegate = banner
        Task {
            let center = UNUserNotificationCenter.current()
            guard (try? await center.requestAuthorization(options: [.alert])) == true else { return }
            let content = UNMutableNotificationContent()
            content.title = "Gallery"
            content.body = "A banner over the page"
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "gallery.banner", content: content, trigger: trigger))
        }
    }

    /// Shown as a banner while the gallery is in front, where an app's own notifications otherwise stay silent.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner]
    }
}
