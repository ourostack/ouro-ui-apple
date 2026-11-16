import UserNotifications

/// Not main-actor code: Darwin notifications may arrive on any thread, so the callback hops to the main queue itself.
private let galleryBannerAsked: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { MainActor.assumeIsolated { GalleryBanner.send() } }
}

/// `-banner 1`: the gallery asks to send notifications, and sends one, shown as a banner over the page, each time the UI
/// test posts the Darwin notification `name`, as a system notification can arrive over a page while the accessibility
/// audit reads it. ComponentClaimTests' `testTheAuditWaitsOutASystemBanner` uses it; without the argument the gallery
/// never asks.
@MainActor final class GalleryBanner: NSObject, UNUserNotificationCenterDelegate {
    static let name = "bot.ouro.hx.gallery.banner"
    private static var shared: GalleryBanner?

    static func start() {
        guard UserDefaults.standard.bool(forKey: "banner"), shared == nil else { return }
        let banner = GalleryBanner()
        shared = banner
        UNUserNotificationCenter.current().delegate = banner
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(banner).toOpaque(),
                                        galleryBannerAsked, name as CFString, nil, .deliverImmediately)
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) }
    }

    static func send() {
        guard shared != nil else { return }
        Task.detached {
            // The test asks once it has tapped Allow; the answer can take a moment to be recorded.
            let center = UNUserNotificationCenter.current()
            var tries = 0
            while await center.notificationSettings().authorizationStatus != .authorized, tries < 40 {
                tries += 1
                try? await Task.sleep(for: .milliseconds(250))
            }
            let content = UNMutableNotificationContent()
            content.title = "Gallery"
            content.body = "A banner over the page"
            try? await center.add(UNNotificationRequest(identifier: "gallery.banner", content: content, trigger: nil))
        }
    }

    /// Shown as a banner while the gallery is in front, where an app's own notifications otherwise stay silent.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner]
    }
}
