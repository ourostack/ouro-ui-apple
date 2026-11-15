import OuroHX
import SwiftUI

var opensAtLaunch: Bool { UserDefaults.standard.integer(forKey: "open") > 0 }

/// `-demo <name>` plays one transition by itself, for frame captures: it waits `lead` seconds, does `forth`, waits
/// `hold`, then does `back`.
var demo: String? { UserDefaults.standard.string(forKey: "demo") }

/// `-warm 1` plays a demo once before the probe starts, so the probe times what every play costs, not what only the
/// first one in a process does. On CI's GPU-less VM the first glass a process draws stalled 180 to 415 ms, every
/// launch; on a Mac's simulator it did not, and the host-video captures time that first play (W8 round 6).
@MainActor enum DemoWarmup {
    static var done = !UserDefaults.standard.bool(forKey: "warm")
}

@MainActor func play(_ name: String, lead: Double = 1.5, hold: Double = 2.5, forth: @escaping @MainActor () -> Void, back: @escaping @MainActor () -> Void) async {
    guard demo == name else { return }
    if !DemoWarmup.done {
        try? await Task.sleep(for: .seconds(lead))
        forth()
        try? await Task.sleep(for: .seconds(hold))
        back()
        try? await Task.sleep(for: .seconds(1.5))
        DemoWarmup.done = true
    }
    // `-repeat n` plays it n times, to tell a first-time cost from one paid every time.
    for _ in 0..<max(1, UserDefaults.standard.integer(forKey: "repeat")) {
        try? await Task.sleep(for: .seconds(lead))
        forth()
        try? await Task.sleep(for: .seconds(hold))
        back()
    }
}
