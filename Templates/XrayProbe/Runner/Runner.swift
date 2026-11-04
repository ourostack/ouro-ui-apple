import SwiftUI

/// The host UI tests need, on iOS and macOS. The X-ray launches the app under test, not this one.
@main struct XrayProbeRunner: App {
    var body: some Scene { WindowGroup { Text("ouro-ax-xray probe runner") } }
}
