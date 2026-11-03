import SwiftUI

/// The host iOS UI tests need. The X-ray launches the app under test, not this one.
@main struct XrayProbeRunner: App {
    var body: some Scene { WindowGroup { Text("ouro-ax-xray probe runner") } }
}
