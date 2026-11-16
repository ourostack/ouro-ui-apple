@_spi(OuroMotionClock) import OuroHX
import SwiftUI

/// Launch arguments pick what to show, so screenshots and UI tests need no taps: `-theme abyss -page pairs`,
/// `-page sheet -open 1` (opens the sheet, or sends the sample toasts), `-scheme dark`, `-banner 1` (``GalleryBanner``).
@main
struct GalleryApp: App {
    init() { GalleryBanner.start() }

    var body: some Scene {
        WindowGroup {
            GalleryScreen(
                theme: OuroThemeName(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .pearl,
                page: GalleryPage(named: UserDefaults.standard.string(forKey: "page") ?? "") ?? .colors
            )
            .preferredColorScheme(UserDefaults.standard.string(forKey: "scheme") == "dark" ? .dark : UserDefaults.standard.string(forKey: "scheme") == "light" ? .light : nil)
        }
    }
}

/// A page of the gallery: one of its own (colours, pairs, feel), or a component's, which registers itself
/// (``GalleryComponentPage``).
enum GalleryPage: Hashable, Identifiable {
    case colors, pairs, feel
    case component(String)

    /// Every page, in the menu's order: the gallery's own, then the components' by title.
    @MainActor static var all: [GalleryPage] { [.colors, .pairs, .feel] + GalleryComponentPage.all.map { .component($0.page) } }

    var id: String {
        switch self {
        case .colors: "colors"
        case .pairs: "pairs"
        case .feel: "feel"
        case .component(let page): page
        }
    }

    /// The page `-page <name>` opens, or nil.
    @MainActor init?(named name: String) {
        switch name.lowercased() {
        case "colors", "colours": self = .colors
        case "pairs": self = .pairs
        case "feel": self = .feel
        default:
            guard let page = GalleryComponentPage.named(name) else { return nil }
            self = .component(page.page)
        }
    }

    @MainActor var title: String {
        switch self {
        case .colors: "Colours"
        case .pairs: "Pairs"
        case .feel: "Feel"
        case .component(let page): GalleryComponentPage.named(page)?.title ?? page
        }
    }
}

struct GalleryScreen: View {
    @State var theme: OuroThemeName
    @State var page: GalleryPage
    @StateObject private var probe = FrameProbe()

    var body: some View {
        // As an app would: the fold reader around the pages, so a sheet held as a tabletop rests below the fold
        // (FoldPostureTests, on an iPhone Duo).
        OuroFoldReader { posture, _ in
            ThemedPage(theme: theme, page: $page, pickTheme: { theme = $0 })
                .modifier(FoldPane(posture: posture))
                .overlay { if FoldProbe.isOn { GeometryReader { FoldProbe(posture: posture, origin: $0.frame(in: .global).origin) } } }
        }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if FrameProbe.isOn { FrameProbeControls(probe: probe) }
            }
            .overlay(alignment: .bottomLeading) { if let clock = GalleryClock.shared { ClockCount(clock: clock) } }
            .ouroToaster()
            .ouroTheme(theme)
            .task {
                // With `-demo` too, the probe times the demo on its own: it starts a second after the page appears,
                // past launch's own first frames and half a second before the demo's first move, and shows its result
                // in the "probe" element for MotionTests (and prints it for the capture scripts).
                // Without a demo, `-probeSeconds` alone times a window for a test's own gesture, `-probeDelay` seconds
                // in. Either way nothing queries the app while it measures: an XCUITest query takes the main thread.
                let defaults = UserDefaults.standard
                guard FrameProbe.isOn, defaults.string(forKey: "demo") != nil || defaults.double(forKey: "probeSeconds") > 0 else { return }
                // With `-warm 1`, after the demo's unmeasured first play; with no demo there is nothing to wait for.
                while !DemoWarmup.done, defaults.string(forKey: "demo") != nil { try? await Task.sleep(for: .milliseconds(50)) }
                try? await Task.sleep(for: .seconds(defaults.object(forKey: "probeDelay") == nil ? 1 : defaults.double(forKey: "probeDelay")))
                probe.start()
                try? await Task.sleep(for: .seconds(max(6, UserDefaults.standard.double(forKey: "probeSeconds"))))
                probe.stop()
                print("PROBE \(probe.summary) \(probe.hitchLog)")
            }
    }
}

private struct ThemedPage: View {
    let theme: OuroThemeName
    @Binding var page: GalleryPage
    let pickTheme: (OuroThemeName) -> Void
    @Environment(\.ouroColors) private var colors
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                // A menu Picker's own button draws about 34 points tall, under the 44 the gallery proves, so the page
                // picker is a Menu with a 44-point label.
                Menu {
                    Picker("Page", selection: $page) {
                        ForEach(GalleryPage.all) { Text($0.title).tag($0) }
                    }
                } label: {
                    Label(page.title, systemImage: "chevron.up.chevron.down")
                        .labelStyle(TrailingIconLabel())
                        .font(.body.weight(.semibold))
                        .foregroundStyle(colors.foreground)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Page, \(page.title)")
                .accessibilityIdentifier("gallery.page")
                switch page {
                case .colors: ColorGrid()
                case .pairs: PairList()
                case .feel: FeelPage()
                case .component(let name): GalleryComponentPage.named(name)?.content
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        // `-anchor bottom` opens a page scrolled to its end, so captures can show what sits below the fold.
        .defaultScrollAnchor(UserDefaults.standard.string(forKey: "anchor") == "bottom" ? .bottom : .top)
        .background(colors.background.ignoresSafeArea())
        .foregroundStyle(colors.foreground)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Menu {
                ForEach(OuroThemeName.allCases, id: \.self) { name in
                    Button(name.rawValue.capitalized) { pickTheme(name) }
                }
            } label: {
                Text(theme.rawValue.capitalized)
                    .font(.largeTitle.bold())
                    .foregroundStyle(colors.foreground)
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("gallery.theme")
            Text("\(scheme == .dark ? "Dark" : "Light")\(contrast == .increased ? ", increased contrast" : "") · ouro-ui-core v0.14.0")
                .font(.subheadline)
                .foregroundStyle(colors.mutedForeground)
        }
        .padding(.top, 8)
    }
}

/// Every colour token, as a chip with its name.
private struct ColorGrid: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(Tokens.all(colors), id: \.name) { token in
                VStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: theme.radius(.sm))
                        .fill(token.color)
                        .overlay(RoundedRectangle(cornerRadius: theme.radius(.sm)).strokeBorder(colors.border, lineWidth: 1))
                        .frame(height: 30)
                    Text(token.name)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(colors.mutedForeground)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

/// Text on its surface, with the WCAG ratio, plus the radius scale.
private struct PairList: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Tokens.pairs(colors), id: \.name) { pair in
                let ratio = OuroColor.contrastRatio(pair.text, pair.surface)
                HStack {
                    Text(pair.name).font(.callout.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f:1", ratio)).font(.callout.monospacedDigit())
                }
                .foregroundStyle(pair.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(pair.surface, in: .rect(cornerRadius: theme.radius(.md)))
            }
            Text("Radii").font(.headline).padding(.top, 8)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(OuroRadius.allCases, id: \.self) { step in
                    VStack(spacing: 3) {
                        UnevenRoundedRectangle(topLeadingRadius: theme.radius(step))
                            .fill(colors.primary)
                            .frame(width: 38, height: 38)
                        Text(step.rawValue).font(.caption2.monospaced()).foregroundStyle(colors.mutedForeground)
                    }
                }
            }
        }
    }
}

/// Motion and haptics: tap things.
private struct FeelPage: View {
    @Environment(\.ouroColors) private var colors
    @Environment(\.ouroTheme) private var theme
    @State private var lit = false
    @State private var checked: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                lit.toggle()
            } label: {
                Text(lit ? "Boing, but politely" : "Press me")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(colors.primaryForeground)
                    .background(colors.primary, in: .rect(cornerRadius: theme.radius(.lg)))
            }
            .buttonStyle(.ouroPress)
            .ouroHaptic(.turned, trigger: lit)
            Circle()
                .fill(colors.accentForeground)
                .frame(width: 24, height: 24)
                .offset(x: lit ? 280 : 0)
                .ouroAnimation(.spring, value: lit)
            Text("Moments").font(.headline)
            ForEach(OuroHaptics.table, id: \.name) { moment in
                Button {
                    if checked.contains(moment.name) { checked.remove(moment.name) } else { checked.insert(moment.name) }
                    OuroHaptics.play(moment)
                } label: {
                    HStack {
                        Image(systemName: checked.contains(moment.name) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(colors.primary)
                        Text(moment.name)
                        Spacer()
                        Text(moment.feedback.label).font(.caption).foregroundStyle(colors.mutedForeground)
                    }
                }
                .buttonStyle(.ouroPress)
            }
        }
    }
}

enum Tokens {
    struct Token { let name: String; let color: Color }
    struct Pair { let name: String; let text: Color; let surface: Color }

    static func all(_ c: OuroColors) -> [Token] {
        Mirror(reflecting: c).children.compactMap { child in
            (child.value as? Color).map { Token(name: child.label ?? "?", color: $0) }
        }
    }

    static func pairs(_ c: OuroColors) -> [Pair] {
        [
            Pair(name: "foreground", text: c.foreground, surface: c.background),
            Pair(name: "mutedForeground", text: c.mutedForeground, surface: c.background),
            Pair(name: "cardForeground", text: c.cardForeground, surface: c.card),
            Pair(name: "primaryForeground", text: c.primaryForeground, surface: c.primary),
            Pair(name: "secondaryForeground", text: c.secondaryForeground, surface: c.secondary),
            Pair(name: "accentForeground", text: c.accentForeground, surface: c.accent),
            Pair(name: "destructiveForeground", text: c.destructiveForeground, surface: c.destructive),
            Pair(name: "successForeground", text: c.successForeground, surface: c.success),
            Pair(name: "warningForeground", text: c.warningForeground, surface: c.warning),
            Pair(name: "sidebarForeground", text: c.sidebarForeground, surface: c.sidebar),
            Pair(name: "sidebarPrimaryForeground", text: c.sidebarPrimaryForeground, surface: c.sidebarPrimary),
        ]
    }
}

/// Title first, then the icon, the way a menu Picker draws its current value.
struct TrailingIconLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.title
            configuration.icon.imageScale(.small)
        }
    }
}

/// `-clock 1`: OuroHX's motion and the demos run on a clock the UI test moves one tick at a time, by posting the Darwin
/// notification `name`, and the screen shows the count (`gallery.clock`). A Feel film then samples every tick, stamped
/// with the app's time, so a busy runner reaches the same verdicts as an idle one (#33). Each tick moves OuroHX's
/// ``OuroMotionClock`` and runs whatever the demo set for it in the same main-queue turn, so a change and the count
/// that shows it reach the screen together.
/// Not main-actor code: Darwin notifications may arrive on any thread, so the callback hops to the main queue itself.
private let galleryClockTicked: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { MainActor.assumeIsolated { GalleryClock.shared?.tick() } }
}

@MainActor @Observable final class GalleryClock {
    static let shared: GalleryClock? = UserDefaults.standard.bool(forKey: "clock") ? GalleryClock() : nil
    static let name = "bot.ouro.hx.gallery.tick"
    /// Seconds per tick.
    static let seconds = 0.05
    private(set) var ticks = 0
    /// Whether a demo has set its steps: the count shows only then, so the test's first tick never comes before them.
    private(set) var armed = false
    @ObservationIgnored private let motion = OuroMotionClock()
    @ObservationIgnored private var due: [(tick: Int, run: @MainActor () -> Void)] = []

    private init() {
        OuroMotion.clock = motion
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                        galleryClockTicked, Self.name as CFString, nil, .deliverImmediately)
    }

    /// Runs `run` `seconds` of this clock from now.
    func after(_ seconds: Double, _ run: @escaping @MainActor () -> Void) {
        due.append((ticks + Int((seconds / Self.seconds).rounded()), run))
        armed = true
    }

    fileprivate func tick() {
        ticks += 1
        motion.advance(by: Self.seconds)
        let now = due.filter { $0.tick <= ticks }
        due.removeAll { $0.tick <= ticks }
        for item in now { item.run() }
    }
}

/// The clock's count, in a view of its own so a tick redraws only it, shown once a demo is armed.
private struct ClockCount: View {
    let clock: GalleryClock
    var body: some View {
        if clock.armed { Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("gallery.clock") }
    }
}

/// `-foldProbe 1`: the posture the fold reader gives, as an element FoldPostureTests reads: "tabletop, fold 371 to
/// 419", the fold band in screen points.
struct FoldProbe: View {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "foldProbe") }
    let posture: OuroFoldPosture
    /// Where the reader's space starts on screen, so the band is reported in the coordinates XCUITest's frames use.
    let origin: CGPoint

    var described: String {
        switch posture {
        case .single: "single"
        case .closed: "closed"
        case .tabletop(let split): "tabletop, fold \(Int(origin.y + split.fold.minY)) to \(Int(origin.y + split.fold.maxY))"
        case .book(let split): "book, fold \(Int(origin.x + split.fold.minX)) to \(Int(origin.x + split.fold.maxX))"
        }
    }

    var body: some View {
        Text(described).font(.caption2).opacity(0.01)
            .accessibilityIdentifier("fold.posture")
    }
}

/// `-foldPane 1`: the page in one pane, as an app places a component beside the fold: a book's leading page, or a
/// tabletop's lower half. Other postures keep the whole screen.
struct FoldPane: ViewModifier {
    static var isOn: Bool { UserDefaults.standard.bool(forKey: "foldPane") }
    let posture: OuroFoldPosture

    func body(content: Content) -> some View {
        if Self.isOn, let pane = posture.book?.first ?? posture.tabletop?.second {
            content
                .frame(width: pane.width, height: pane.height)
                .padding(.leading, pane.minX)
                .padding(.top, pane.minY)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        } else {
            content
        }
    }
}
