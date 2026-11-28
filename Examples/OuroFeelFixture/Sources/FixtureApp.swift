import OuroFeelRecorder
import SwiftUI
import UIKit.UIGestureRecognizerSubclass

/// One page per genre of jank. `-page <name>` picks it; `-bug 1` turns on its known bug. The UI tests prove each
/// Ouro Feel check fails with the bug and passes without it.
@main
struct FixtureApp: App {
    init() {
        OuroFeelRecorder.installIfRequested()
    }

    var body: some Scene {
        WindowGroup {
            switch UserDefaults.standard.string(forKey: "page") ?? "nav" {
            case "window": WindowPage()
            case "taps": TapsPage()
            case "motion": MotionPage()
            case "place": PlacePage()
            case "overlay": OverlayPage()
            case "push": PushPage()
            case "kitchen": KitchenPage()
            case "transition": TransitionPage()
            case "flicker": FlickerPage()
            case "screen-flicker": ScreenFlickerPage()
            case "reveal": RevealPage()
            case "reveal-shelf": RevealPage(shelf: true)
            case "reveal-reads": RevealByReadsPage()
            case "stray": StrayPage()
            case "fight": FightPage()
            case "keyboard": KeyboardPage()
            case "scroll-reader": ScrollReaderPage()
            case "cover": CoverPage()
            case "idle": IdlePage()
            case "viewport": ViewportPage()
            case "float": FloatPage(under: false)
            case "float-under": FloatPage(under: true)
            case "intent": IntentPage()
            case "fold": FoldPage()
            case "relayout": RelayoutPage()
            case "turn-place": TurnPlacePage()
            case "jump": JumpPage()
            case "hit": HitPage()
            case "notice": NoticePage()
            case "targets": TargetsPage()
            case "landing": LandingPage()
            case "turn-film": TurnFilmPage()
            default: NavPage()
            }
        }
    }
}

var bug: Bool { UserDefaults.standard.bool(forKey: "bug") }

/// Inside the window. The bug: the panel is pushed most of the way off the trailing edge, as Gatefold build 19's
/// portrait Fine-Tune panel was.
struct WindowPage: View {
    @State private var on = false
    var body: some View {
        ZStack {
            // A shelf with a "Reading Now" row, as Gatefold's: a horizontal ScrollView of covers inside a vertical
            // one. Covers past the side are a carousel's, in both builds (#67).
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Color.clear.frame(height: 340)
                    Text("Reading Now").font(.headline).padding(.horizontal)
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 16) {
                            ForEach(1...6, id: \.self) { i in
                                Button { } label: {
                                    RoundedRectangle(cornerRadius: 8).fill(.orange.opacity(0.4))
                                        .frame(width: 150, height: 220)
                                        .overlay(Text("Book \(i)"))
                                }
                                .accessibilityIdentifier("window.cover.\(i)")
                            }
                        }
                        .padding(.horizontal)
                    }
                }
            }
            panel
        }
    }

    private var panel: some View {
        GeometryReader { geo in
            VStack(alignment: .leading, spacing: 16) {
                Text("Fine-Tune").font(.headline)
                Toggle("Page Numbers", isOn: $on).accessibilityIdentifier("window.toggle")
                Button("Use as Default") {}.accessibilityIdentifier("window.default")
            }
            .padding()
            .frame(width: min(320, geo.size.width - 32))
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
            .offset(x: bug ? geo.size.width * 0.8 : 16, y: 120)
        }
    }
}

/// Tap landing. The bugs: an invisible strip over the control's trailing end swallows taps, and the control ignores a
/// tap that comes within a quarter second of its last change (taps while it animates are lost). The quarter second is
/// read from the touches' own timestamps, which keep XCUITest's spacing however late a busy app handles them: a double
/// tap's two touches always meet the lock, and paced taps (0.6 s apart and more) never do. The control is a plain
/// UIKit button, so the fixed build lands every tap and never leans on a system switch's animation timing (the iOS 26
/// simulator's own switch drops rapid taps).
struct TapsPage: View {
    @State private var on = false
    var body: some View {
        HStack {
            Text("Page Numbers").accessibilityIdentifier("taps.title")
            Spacer()
            TapsToggle(on: $on, locks: bug)
                .frame(width: 51, height: 31)
                .overlay(alignment: .trailing) {
                    if bug { Color.white.opacity(0.001).frame(width: 22).onTapGesture {} }
                }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 100)
    }
}

/// A two-state control that flips on every tap; with `locks`, it ignores a tap within 0.45 s (by touch timestamp) of
/// its last change.
struct TapsToggle: UIViewRepresentable {
    @Binding var on: Bool
    let locks: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .custom)
        button.layer.cornerRadius = 15.5
        button.accessibilityIdentifier = "taps.toggle"
        button.accessibilityLabel = "Page Numbers"
        button.accessibilityTraits = [.button, .toggleButton]
        button.addTarget(context.coordinator, action: #selector(Coordinator.tapped(_:event:)), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: UIButton, context: Context) {
        context.coordinator.parent = self
        button.backgroundColor = on ? .systemGreen : .systemGray4
        button.accessibilityValue = on ? "1" : "0"
    }

    @MainActor final class Coordinator: NSObject {
        var parent: TapsToggle
        var lastChange: TimeInterval = -.infinity
        init(_ parent: TapsToggle) { self.parent = parent }

        @objc func tapped(_ sender: UIButton, event: UIEvent) {
            let at = event.allTouches?.first?.timestamp ?? event.timestamp
            if parent.locks && at - lastChange < 0.45 { return }
            lastChange = at
            parent.on.toggle()
        }
    }
}

/// The app's own clock for the motion page: it moves only when the UI test posts the Darwin notification `name`, one
/// tick per post, and the page shows the count (`motion.clock`), so a film samples every tick however busy the machine.
/// Not main-actor code: Darwin notifications may arrive on any thread, so the callback hops to the main queue itself.
private let fixtureClockTicked: CFNotificationCallback = { _, _, _, _, _ in
    DispatchQueue.main.async { MainActor.assumeIsolated { FixtureClock.shared.ticks += 1 } }
}

@MainActor @Observable final class FixtureClock {
    static let shared = FixtureClock()
    static let name = "bot.ouro.feel.fixture.tick"
    /// Seconds per tick.
    static let tick = 0.1
    var ticks = 0

    private init() {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
                                        fixtureClockTicked,
                                        Self.name as CFString, nil, .deliverImmediately)
    }
}

/// Where everything on the motion page is, `elapsed` seconds of the app's clock after Play (negative before it). The
/// motion starts half a second after Play. Fixed: the card eases down over 0.8 s and the full bar hands over to the
/// compact one in a single tick. The bug: the card snaps down, a ghost copy stays behind for a second, both bars show at
/// once for that second, and the card jumps 40 points 2 s after it landed (so it also settles late).
struct MotionState: Equatable {
    var cardY: Double, ghost: Bool, fullBar: Bool, compactBar: Bool

    init(elapsed e: Double, bug: Bool) {
        let start = 0.5
        if bug {
            let on = e >= start
            cardY = on ? 520 + (e >= start + 2 ? 40 : 0) : 200
            ghost = on && e < start + 1
            fullBar = e < start + 1
            compactBar = on
        } else {
            let p = min(1, max(0, (e - start) / 0.8))
            let eased = p < 0.5 ? 2 * p * p : 1 - (2 - 2 * p) * (2 - 2 * p) / 2
            cardY = 200 + 320 * eased
            ghost = false
            fullBar = e < start + 0.15
            compactBar = e >= start + 0.15
        }
    }
}

/// Settle, jumps, double draws, chrome and snaps, on the app's own clock (``FixtureClock``): nothing moves until the
/// test advances it, so a slow machine films the same frames.
struct MotionPage: View {
    private let clock = FixtureClock.shared
    @State private var playedAt: Int?

    var body: some View {
        let elapsed = playedAt.map { Double(clock.ticks - $0) * FixtureClock.tick } ?? -1
        let state = MotionState(elapsed: elapsed, bug: bug)
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if state.fullBar { bar("Kitchen", id: "bar.full", height: 96) }
                if state.compactBar { bar("Kitchen", id: "bar.compact", height: 52) }
                Spacer()
            }
            if state.ghost { card.offset(y: 200).accessibilityIdentifier("motion.ghost") }
            card.offset(y: state.cardY).accessibilityIdentifier("motion.card")
            Button("Play") { playedAt = clock.ticks }
                .accessibilityIdentifier("motion.play")
                .offset(y: 700)
            Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("motion.clock")
                .offset(y: 760)
            // Marks that Play took, so the test knows the film starts on a playing page (#65).
            if playedAt != nil { Text(verbatim: "playing").font(.caption2).accessibilityIdentifier("motion.played").offset(y: 780) }
        }
    }

    var card: some View {
        Text("Pancakes")
            .font(.title2.bold())
            .frame(width: 240, height: 120)
            .background(.orange.opacity(0.3), in: RoundedRectangle(cornerRadius: 16))
    }

    func bar(_ title: String, id: String, height: CGFloat) -> some View {
        Text(title).font(.headline).frame(maxWidth: .infinity, minHeight: height).background(.bar)
            .accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
}

/// Place stability. The bug: the place lives only in memory, so a relaunch loses it.
struct PlacePage: View {
    @AppStorage("placeItem") private var saved = 1
    @State private var transient = 1
    init() {
        if UserDefaults.standard.bool(forKey: "resetPlace") { UserDefaults.standard.set(1, forKey: "placeItem") }
    }
    var body: some View {
        let item = bug ? transient : saved
        VStack(spacing: 24) {
            Text("Chapter \(item): \(String(repeating: "words ", count: item))").accessibilityIdentifier("place.text")
            Button("Next") { if bug { transient += 1 } else { saved += 1 } }.accessibilityIdentifier("place.next")
        }
        .padding()
    }
}

/// The way back. The bugs: the chef screen hides the system back button for its own, which also turns off the edge
/// swipe, so a swipe moves nothing (the walk cannot tell that from a touch that never arrived, and says so); the
/// Settings sheet refuses a pull down, so it follows the finger a little and settles back (no gesture back, a fail);
/// the cook screen (a full-screen cover) has a Close button and no swipe down.
/// The segmented picker and the Sort menu switch what the page shows; a walk that follows buttons must not take them
/// for screens without a way back, and must check that the menus it opens close. The Filter menu is the walk's
/// overlay bug: with `-bug 1` it never closes, neither on a pick nor on a tap outside. The Tags menu always closes,
/// so the bug build holds a stuck menu and a well-behaved one side by side. "More" expands in place, which is neither
/// a screen nor an overlay.
struct NavPage: View {
    @State private var settings = false
    @State private var cook = false
    @State private var shown = "All"
    @State private var order = "Newest"
    @State private var filtering = false
    @State private var filter = "Any time"
    @State private var tagging = false
    @State private var tag = "Any"
    var body: some View {
        NavigationStack {
            List {
                Picker("Show", selection: $shown) {
                    Text("All").tag("All")
                    Text("Mine").tag("Mine")
                }
                .pickerStyle(.segmented)
                // The whole row opens the menu, as a person expects (otherwise only the label text does).
                // A section header and a plain Text row first, as Gatefold's Account menu has: neither is a pick, so the
                // walk must pass over them to Newest (#68).
                Menu {
                    Section("Signed in as ada@example.com") {
                        Text("Store: Corner Market")
                    }
                    Button("Newest") { order = "Newest" }
                    Button("Oldest") { order = "Oldest" }
                } label: {
                    Text("Sort: \(order)").frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                NavigationLink("Pancakes") { Text("Pancakes recipe").navigationTitle("Pancakes") }
                    .accessibilityIdentifier("nav.recipe")
                NavigationLink("Chef Ada") { ChefPage() }.accessibilityIdentifier("nav.chef")
                // A row whose only key is its long label, as a recipe card that reads out its whole description: the
                // walk must find it by a label over XCUITest's 128-character query limit.
                NavigationLink("Focaccia, from the last of the cold-fermented pizza dough, baked at 450°F for twenty-five minutes in a nine-inch pan, dimpled with olive oil and flaky salt") {
                    Text("Focaccia recipe").navigationTitle("Focaccia")
                }
                Button("Filter: \(filter)") { filtering = true }.accessibilityIdentifier("nav.filter")
                Button("Tags: \(tag)") { tagging = true }.accessibilityIdentifier("nav.tags")
                Button("Settings") { settings = true }.accessibilityIdentifier("nav.settings")
                Button("Cook") { cook = true }.accessibilityIdentifier("nav.cook")
                // A change in place, not an overlay: its rows push the list down and stay until it is collapsed.
                DisclosureGroup("More") {
                    Text("Serves 4")
                    Text("Takes 20 minutes")
                }
                .accessibilityIdentifier("nav.more")
            }
            .navigationTitle("Recipes")
            .overlay {
                if filtering {
                    PopMenu(choices: ["Today", "This week", "Any time"], id: "filter", sticks: bug, open: $filtering) { filter = $0 }
                }
                if tagging {
                    PopMenu(choices: ["Quick", "Vegan"], id: "tags", sticks: false, open: $tagging) { tag = $0 }
                }
            }
            .sheet(isPresented: $settings) { SettingsSheet() }
            .fullScreenCover(isPresented: $cook) { CookCover() }
        }
    }
}

/// Kitchen's Tidy menu. A tap outside closes it. The bug: picking Sort by aisle leaves it open and shows an Undo toast at
/// the bottom of the screen, which is not the menu's and must not be taken for a submenu.
struct TidyMenu: View {
    @Binding var open: Bool
    @Binding var undo: Bool
    var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { open = false; undo = false }
            VStack(spacing: 0) {
                Button("Sort by aisle") { if bug { undo = true } else { open = false } }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("tidy.sort")
            }
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            if undo {
                VStack {
                    Spacer()
                    Button("Undo") { undo = false; open = false }
                        .padding()
                        .background(.regularMaterial, in: Capsule())
                        .accessibilityIdentifier("tidy.undo")
                }
                .padding(.bottom, 24)
            }
        }
    }
}

/// A small custom menu over the page. `sticks` is the bug: it never closes, neither on a pick nor on a tap outside.
struct PopMenu: View {
    let choices: [String]
    let id: String
    let sticks: Bool
    @Binding var open: Bool
    let pick: (String) -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { if !sticks { open = false } }
            VStack(spacing: 0) {
                ForEach(choices, id: \.self) { choice in
                    Button(choice) { pick(choice); if !sticks { open = false } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("\(id).\(choice)")
                }
            }
            .frame(width: 220)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
    }
}

struct ChefPage: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Text("Ada's recipes")
            .navigationTitle("Chef Ada")
            .navigationBarBackButtonHidden(bug)
            .toolbar {
                if bug {
                    ToolbarItem(placement: .topBarLeading) { Button("Back") { dismiss() } }
                }
            }
    }
}

struct SettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Text("Settings").toolbar { Button("Done") { dismiss() } }
        }
        .interactiveDismissDisabled(bug)
    }
}

struct CookCover: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 24) {
            Button("Close") { dismiss() }.accessibilityIdentifier("cook.close")
            Text("Step 1: whisk").font(.largeTitle)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .contentShape(Rectangle())
        .gesture(DragGesture().onEnded { value in
            if !bug && value.translation.height > 120 { dismiss() }
        })
    }
}

/// Overlay dismissal. The bug: the compact sidebar stays open after you pick a place in it.
struct OverlayPage: View {
    @State private var open = false
    @State private var place = "Inbox"
    var body: some View {
        ZStack(alignment: .leading) {
            VStack {
                Button("Menu") { open = true }.accessibilityIdentifier("overlay.open")
                Text(place).font(.largeTitle)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if open {
                Color.black.opacity(0.3).ignoresSafeArea().onTapGesture { open = false }
                    .accessibilityIdentifier("overlay.scrim")
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(["Inbox", "Saved", "Archive"], id: \.self) { name in
                        Button(name) {
                            place = name
                            if !bug { open = false }
                        }
                        .accessibilityIdentifier("overlay.\(name.lowercased())")
                    }
                    Spacer()
                }
                .padding(24)
                .frame(width: 260)
                .frame(maxHeight: .infinity)
                .background(Color(.systemBackground))
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("overlay.sidebar")
            }
        }
    }
}

/// A push the walk must not mistake for an overlay or a change in place, shaped like Spoonjoy's chef page: a tab bar the
/// pushed page's long content scrolls under, navigation bars with no title, and the Chefs screen's only other control
/// (a status banner's close button) on the pushed page too. The walk enters at Chefs, one push in, as Spoonjoy's does.
/// The bug: the profile hides its back button, so it has no way back; in both builds it is a screen, never an overlay.
struct PushPage: View {
    var body: some View {
        TabView {
            Tab("Kitchen", systemImage: "house") {
                // Titled but showing no title, so Chefs' back button says "Kitchen" and the profile's says "Back".
                NavigationStack {
                    NavigationLink("Chefs") { ChefsList() }
                        .accessibilityIdentifier("push.chefs")
                        .navigationTitle("Kitchen")
                        .toolbar(removing: .title)
                }
            }
            Tab("Recipes", systemImage: "book") { Text("Recipes") }
        }
    }
}

struct ChefsList: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                StatusBanner()
                Text("Chefs").font(.largeTitle)
                Text("1 chef")
                NavigationLink { ChefProfile() } label: {
                    Text("ada, Open kitchen profile").frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("push.chef")
            }
            .padding()
        }
    }
}

struct StatusBanner: View {
    var body: some View {
        HStack {
            Text("Showing saved kitchen")
            Button { } label: { Image(systemName: "xmark.circle") }.accessibilityLabel("Hide offline status")
        }
    }
}

struct ChefProfile: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("@ada").font(.largeTitle)
                StatusBanner()
                ForEach(1...14, id: \.self) { n in
                    Text("Recipe \(n), a long description of how it is cooked").frame(maxWidth: .infinity, minHeight: 80, alignment: .leading)
                }
            }
            .padding()
        }
        .navigationBarBackButtonHidden(bug)
    }
}

/// Shapes a walk once misread as missing ways back (Spoonjoy, 2026-11-07), none of them a bug, in either build: "See all"
/// switches to the Recipes tab (a tab's root, left by its tab button); a recipe opens with a zoom transition over a
/// full-bleed cover (its edge swipe does not start at the navigation bar's height); "Serves" opens a popover of a
/// stepper, which stays open to adjust; "More" is a menu whose first item opens a submenu.
struct KitchenPage: View {
    @State private var tab = "kitchen"
    @State private var serves = 2
    @State private var adjusting = false
    @State private var scale = 1.0
    @State private var recipes: [String] = []
    @State private var tidying = false
    @State private var undo = false
    @State private var heating = false
    @State private var heat = 0.5
    @State private var filtering = false
    @Namespace private var zoom
    var body: some View {
        TabView(selection: $tab) {
            Tab("Kitchen", systemImage: "house", value: "kitchen") {
                NavigationStack {
                    List {
                        NavigationLink {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 12) {
                                    Color.orange.frame(height: 360)
                                    Text("Tomato Toast").font(.largeTitle)
                                    Text("Salted tomato on hot toast")
                                }
                            }
                            .ignoresSafeArea(edges: .top)
                            .navigationTransition(.zoom(sourceID: "toast", in: zoom))
                        } label: {
                            Text("Tomato Toast").matchedTransitionSource(id: "toast", in: zoom)
                        }
                        .accessibilityIdentifier("kitchen.recipe")
                        Button("See all") { tab = "recipes" }.accessibilityIdentifier("kitchen.seeAll")
                        Button("Open in Recipes") { tab = "recipes"; recipes = ["toast"] }.accessibilityIdentifier("kitchen.openInRecipes")
                        Button("Heat") { heating = true }
                            .accessibilityIdentifier("kitchen.heat")
                            .popover(isPresented: $heating) {
                                VStack {
                                    Slider(value: $heat).accessibilityIdentifier("kitchen.heat.slider").frame(width: 200)
                                    Button("Apply") { if !bug { heating = false } }.accessibilityIdentifier("kitchen.heat.apply")
                                }
                                .padding()
                                .presentationCompactAdaptation(.popover)
                            }
                        Button("Tidy") { tidying = true }.accessibilityIdentifier("kitchen.tidy")
                        Button("Serves \(serves)") { adjusting = true }
                            .accessibilityIdentifier("kitchen.serves")
                            .popover(isPresented: $adjusting) {
                                Stepper("Serves \(serves)", value: $serves, in: 1...12)
                                    .accessibilityIdentifier("kitchen.serves.stepper")
                                    .padding()
                                    .presentationCompactAdaptation(.popover)
                            }
                    }
                    .navigationTitle("Kitchen")
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Menu {
                                Picker(selection: $scale) {
                                    ForEach([0.5, 1, 2], id: \.self) { Text("\($0, specifier: "%g")×").tag($0) }
                                } label: {
                                    Label("Scale", systemImage: "person.2")
                                }
                                .pickerStyle(.menu)
                                Button("Print", systemImage: "printer") { }
                            } label: {
                                Label("More", systemImage: "ellipsis")
                            }
                            .accessibilityIdentifier("kitchen.more")
                        }
                    }
                }
                // Over the whole stack, bar included, so a tap anywhere outside the menu closes it.
                .overlay {
                    if tidying { TidyMenu(open: $tidying, undo: $undo) }
                }
            }
            Tab("Recipes", systemImage: "book", value: "recipes") {
                NavigationStack(path: $recipes) {
                    Text("All recipes")
                        .navigationTitle("Recipes")
                        .navigationDestination(for: String.self) { _ in
                            // The bug hides the back button and puts a leading Filter button where it was, which
                            // changes the page when tapped but never leads back.
                            Text("Tomato Toast recipe").navigationTitle("Tomato Toast").navigationBarBackButtonHidden(bug)
                                .toolbar {
                                    if bug {
                                        ToolbarItem(placement: .topBarLeading) {
                                            Button("Filter") { filtering.toggle() }.accessibilityIdentifier("recipes.filter")
                                        }
                                    }
                                }
                                .overlay(alignment: .bottom) { if filtering { Text("Filtered").padding(.bottom, 120) } }
                        }
                }
            }
        }
    }
}

/// A push filmed inside the app, frame by frame (`OuroFeelRecorder`). The bug: the recipe is pushed with animations
/// off, so its page appears in one frame instead of sliding in. `-missTaps N` ignores the first N taps on Open, a tap
/// that doesn't take, so the test proves it notices one and taps again (#84).
struct TransitionPage: View {
    @State private var path: [String] = []
    @State private var missed = 0

    var body: some View {
        NavigationStack(path: $path) {
            List {
                Button("Tomato Toast") { open("Tomato Toast") }.accessibilityIdentifier("transition.open")
            }
            .navigationTitle("Recipes")
            .navigationDestination(for: String.self) { name in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Serves two, in ten minutes").accessibilityIdentifier("transition.title")
                        ForEach(1...6, id: \.self) { Text("Step \($0)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                }
                .navigationTitle(name)
            }
        }
    }

    private func open(_ name: String) {
        if missed < UserDefaults.standard.integer(forKey: "missTaps") { missed += 1; return }
        if bug {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) { path.append(name) }
        } else {
            path.append(name)
        }
    }
}

/// Flicker, on the app's own clock (``FixtureClock``). Three ticks after Play the page turns and a Saved badge shows.
/// Fixed: the words change once and the badge appears once. The bug, as Gatefold build 20 spazzed: the words turn,
/// turn back for a tick, then turn again, and the badge blinks on for one tick only.
struct FlickerPage: View {
    private let clock = FixtureClock.shared
    @State private var playedAt: Int?

    var body: some View {
        let k = playedAt.map { clock.ticks - $0 } ?? -1
        let page = bug ? (k == 3 || k >= 5 ? 2 : 1) : (k >= 3 ? 2 : 1)
        let badge = bug ? k == 4 : k >= 4
        VStack(spacing: 24) {
            if badge { Text("Saved").accessibilityIdentifier("flicker.badge") }
            Text("Page \(page)").font(.title).accessibilityIdentifier("flicker.words")
            Button("Play") { playedAt = clock.ticks }.accessibilityIdentifier("flicker.play")
            Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("flicker.clock")
            // Marks that Play took, so the test knows the film starts on a playing page (#86).
            if playedAt != nil { Text(verbatim: "playing").font(.caption2).accessibilityIdentifier("flicker.played") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Flicker of the whole screen, on the app's own clock (``FixtureClock``), with nothing named: the page is a picture no
/// element labels, as a web view's page is. Three ticks after Play it turns. Fixed: it turns once. The bug, as Gatefold
/// build 20's slip came and went on a folded Duo: it turns, goes back for three ticks, then turns again (three, so a
/// screenshot a tick late still sees each state rest).
struct ScreenFlickerPage: View {
    private let clock = FixtureClock.shared
    @State private var playedAt: Int?

    var body: some View {
        let k = playedAt.map { clock.ticks - $0 } ?? -1
        let turned = bug ? ((3...5).contains(k) || k >= 9) : k >= 3
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 12)
                .fill(turned ? Color.indigo : Color.orange)
                .overlay(Text(turned ? "2" : "1").font(.system(size: 120, weight: .bold)).foregroundStyle(.white))
                .frame(height: 360)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
            Button("Play") { playedAt = clock.ticks }.accessibilityIdentifier("screenflicker.play")
            Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("screenflicker.clock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The first page shown after an open is the one that stays, on the app's own clock (``FixtureClock``), judged from
/// pixels: the page is a picture no element labels. Open starts the open; the cover stays until the page shows. Fixed:
/// the cover holds until his page is placed, then shows it. The bug, as Gatefold build 20 relaunched on an iPad: the
/// cover goes at once onto another page, which four ticks later jumps to his.
///
/// With `shelf` (#73, item 4), the screen before Open is a shelf, which looks nothing like the cover: Open puts the cover
/// up, and it stays until the clock ticks. So the cover's picture must be taken while the cover is up, not before Open.
struct RevealPage: View {
    var shelf = false
    private let clock = FixtureClock.shared
    @State private var openedAt: Int?

    var body: some View {
        let k = openedAt.map { clock.ticks - $0 } ?? -1
        let shown: Int? = k < 0 ? nil : (bug ? (k < 3 ? nil : (k < 7 ? 1 : 2)) : (k < 7 ? nil : 2))
        let onShelf = shelf && openedAt == nil
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 12)
                .fill(onShelf ? Color.orange : shown == nil ? Color.black : (shown == 1 ? Color.teal : Color.purple))
                .overlay(Text(onShelf ? "Shelf" : shown.map { "Page \($0)" } ?? "").font(.system(size: 60, weight: .bold)).foregroundStyle(.white))
                .frame(height: 360)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
            Button("Open") { openedAt = clock.ticks }.accessibilityIdentifier("reveal.open")
            Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("reveal.clock")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The first page shown after an open, for an app with no clock of its own (#94): the same open as ``RevealPage``, run on
/// wall time as UIKit and reader engines do, filmed by XCUITest's reads. Fixed: the cover holds 1.5 s, then his page
/// shows. The bug: the cover goes after 1.5 s onto another page, which 2.5 s later jumps to his. Each state lasts long
/// enough for several reads on a loaded runner, where one read can take half a second (#169's first run saw a 0.3 s
/// cover never rest).
struct RevealByReadsPage: View {
    @State private var shown: Int?
    @State private var opened = false

    var body: some View {
        VStack(spacing: 24) {
            RoundedRectangle(cornerRadius: 12)
                .fill(shown == nil ? Color.black : (shown == 1 ? Color.teal : Color.purple))
                .overlay(Text(shown.map { "Page \($0)" } ?? "").font(.system(size: 60, weight: .bold)).foregroundStyle(.white))
                .frame(height: 360)
                .padding(.horizontal, 24)
                .accessibilityHidden(true)
            Button("Open") {
                guard !opened else { return }
                opened = true
                Task { @MainActor in
                    if bug {
                        try? await Task.sleep(for: .seconds(1.5)); shown = 1
                        try? await Task.sleep(for: .seconds(2.5)); shown = 2
                    } else {
                        try? await Task.sleep(for: .seconds(1.5)); shown = 2
                    }
                }
            }.accessibilityIdentifier("revealreads.open")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Place kept through stray input. A page you read, a Next button, and a Contents sheet. Fixed: a tap in the middle
/// shows or hides a top bar, and swiping the sheet away keeps the page. The bugs: a tap in the middle turns the page,
/// and swiping the sheet away goes back to page 1, as a stray touch moved Ari's place in Gatefold build 20.
struct StrayPage: View {
    @State private var page = 1
    @State private var bar = false
    @State private var contents = false

    var body: some View {
        ZStack {
            Color.white.opacity(0.001).contentShape(Rectangle())
                .onTapGesture { if bug { page += 1 } else { bar.toggle() } }
            Text("Page \(page)").font(.title).accessibilityIdentifier("stray.page").allowsHitTesting(false)
            VStack {
                if bar { Text("Reading").font(.headline).padding().accessibilityIdentifier("stray.bar") }
                Spacer()
                HStack(spacing: 40) {
                    Button("Contents") { contents = true }.accessibilityIdentifier("stray.contents")
                    Button("Next") { page += 1 }.accessibilityIdentifier("stray.next")
                }
                .padding(.bottom, 40)
            }
        }
        .sheet(isPresented: $contents, onDismiss: { if bug { page = 1 } }) {
            VStack {
                Text("Contents").font(.headline).padding().accessibilityIdentifier("stray.sheet")
                List(1...5, id: \.self) { Text("Chapter \($0)") }
            }
        }
    }
}

/// Navigation that fights you, on the app's own clock (``FixtureClock``). Next turns the page and a sync lands three
/// ticks later; Contents jumps to page 30 behind a veil that lifts three ticks later, and a tap on the right edge turns
/// the page. With `-cloud 1`, a cloud reply arrives three ticks after the page opens, with no input. Fixed: the sync
/// agrees with where you are, a tap under the veil is swallowed, and the cloud reply is offered, not applied. The bugs,
/// as in Gatefold build 20: the sync carries the place from before your move (a late restore), a tap under the veil is
/// queued and turns the page as the jump lands, and the cloud reply moves the page you are reading.
struct FightPage: View {
    private let clock = FixtureClock.shared
    @State private var page = 1
    @State private var pending: (at: Int, page: Int)?
    @State private var veilUntil: Int?
    @State private var queued = 0
    @State private var cloudAt: Int?
    @State private var offer: Int?

    var body: some View {
        ZStack {
            GeometryReader { geo in
                Color.white.opacity(0.001).contentShape(Rectangle())
                    .onTapGesture { at in
                        guard at.x > geo.size.width * 0.75 else { return }
                        if veilUntil != nil { if bug { queued += 1 } } else { page += 1 }
                    }
            }
            VStack(spacing: 24) {
                if veilUntil != nil {
                    Text("Opening").accessibilityIdentifier("fight.veil")
                    // Marks that the bug build queued a tap under the veil, so the test knows its edge tap took (#86).
                    if queued > 0 { Text(verbatim: "queued").font(.caption2).accessibilityIdentifier("fight.queued") }
                } else {
                    Text("Page \(page)").font(.title).accessibilityIdentifier("fight.page")
                }
                Button("Next") {
                    pending = (clock.ticks + 3, bug ? page : page + 1)
                    page += 1
                }
                .accessibilityIdentifier("fight.next")
                Button("Contents: page 30") { veilUntil = clock.ticks + 3 }.accessibilityIdentifier("fight.contents")
                if let offer { Button("Go to page \(offer)") { page = offer; self.offer = nil }.accessibilityIdentifier("fight.offer") }
                Text(verbatim: String(clock.ticks)).font(.caption2).accessibilityIdentifier("fight.clock")
            }
        }
        .onAppear { if UserDefaults.standard.bool(forKey: "cloud") { cloudAt = clock.ticks + 3 } }
        .onChange(of: clock.ticks) { _, now in
            if let p = pending, now >= p.at { page = p.page; pending = nil }
            if let v = veilUntil, now >= v { page = 30 + queued; queued = 0; veilUntil = nil }
            if let c = cloudAt, now >= c { if bug { page = 5 } else { offer = 5 }; cloudAt = nil }
        }
    }
}

/// A search field focused at launch, so the system keyboard is up while the walk runs: its keys (Emoji, Dictate, the
/// next-keyboard key) are not the app's, and the walk must follow none of them (#60). "Recipe" pushes a page with a
/// way back, so the walk has a screen of the app's own to check.
struct KeyboardPage: View {
    @State private var query = ""
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                TextField("Search", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .accessibilityIdentifier("keyboard.field")
                NavigationLink("Recipe") { Text("Tomato Toast").accessibilityIdentifier("keyboard.recipe.title") }
                    .accessibilityIdentifier("keyboard.recipe")
                Spacer()
            }
            .padding()
            .navigationTitle("Search")
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            focused = true
        }
    }
}

/// Place kept through stray input, in a reader that scrolls (as Gatefold's scroll mode, build 39). One chapter at a
/// time in a scroll view; a swipe to the left goes to the next chapter and one to the right comes back. The place
/// (`scroll.place`) is the chapter and the first line in view. It opens at line 20 of chapter 1. Fixed: a tap on the
/// status bar does nothing (`scrollsToTop` off), and coming back to a chapter returns to the line you left it at. The
/// bugs, as Ari found them: the status bar tap scrolls to the chapter's start, and coming back lands at the chapter's
/// end. A swipe is judged from its touches when the finger lifts (`SwipeAcross`).
struct ScrollReaderPage: View {
    @State private var place = ""
    var body: some View {
        ScrollReader(place: $place, bug: bug)
            .overlay(alignment: .bottomLeading) {
                Text(place).font(.caption).padding(8).background(.thinMaterial)
                    .accessibilityIdentifier("scroll.place").allowsHitTesting(false)
            }
    }
}

struct ScrollReader: UIViewRepresentable {
    @Binding var place: String
    let bug: Bool
    static let lines = 80
    static let lineHeight: CGFloat = 32

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> UIScrollView {
        let scroll = UIScrollView()
        scroll.accessibilityIdentifier = "scroll.reader"
        scroll.scrollsToTop = bug
        scroll.alwaysBounceHorizontal = false
        scroll.delegate = context.coordinator
        let stack = UIStackView()
        stack.axis = .vertical
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.frameLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.frameLayoutGuide.trailingAnchor, constant: -24),
            // Content exactly as wide as the view, so nothing scrolls sideways and a swipe across is only a swipe.
            scroll.contentLayoutGuide.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
        ])
        for _ in 0..<Self.lines {
            let label = UILabel()
            label.heightAnchor.constraint(equalToConstant: Self.lineHeight).isActive = true
            stack.addArrangedSubview(label)
        }
        context.coordinator.stack = stack
        let swipe = SwipeAcross { [weak scroll, coordinator = context.coordinator] direction in
            if let scroll { coordinator.swiped(direction, in: scroll) }
        }
        swipe.cancelsTouchesInView = false
        swipe.delegate = context.coordinator
        scroll.addGestureRecognizer(swipe)
        // After SwiftUI has built the view: setting the place binding while it builds may be dropped.
        DispatchQueue.main.async { context.coordinator.show(chapter: 1, in: scroll, line: 20) }
        return scroll
    }

    func updateUIView(_ scroll: UIScrollView, context: Context) { context.coordinator.parent = self }

    @MainActor final class Coordinator: NSObject, UIScrollViewDelegate, UIGestureRecognizerDelegate {
        var parent: ScrollReader
        weak var stack: UIStackView?
        var chapter = 1
        /// The line each chapter was left at, for the fixed build's way back.
        var left: [Int: Int] = [:]
        init(_ parent: ScrollReader) { self.parent = parent }

        func line(_ scroll: UIScrollView) -> Int { Int((scroll.contentOffset.y / ScrollReader.lineHeight).rounded(.down)) + 1 }

        func show(chapter: Int, in scroll: UIScrollView, line: Int) {
            self.chapter = chapter
            for (i, view) in (stack?.arrangedSubviews ?? []).enumerated() {
                (view as? UILabel)?.text = "Chapter \(chapter), line \(i + 1)"
            }
            scroll.layoutIfNeeded()
            let most = max(0, scroll.contentSize.height - scroll.bounds.height)
            scroll.contentOffset.y = min(most, CGFloat(line - 1) * ScrollReader.lineHeight)
            report(scroll)
        }

        func report(_ scroll: UIScrollView) {
            let place = "chapter \(chapter) line \(line(scroll))"
            if parent.place != place { parent.place = place }
        }

        func scrollViewDidScroll(_ scroll: UIScrollView) { report(scroll) }

        func swiped(_ direction: UISwipeGestureRecognizer.Direction, in scroll: UIScrollView) {
            let next = direction == .left ? chapter + 1 : chapter - 1
            guard next >= 1 else { return }
            left[chapter] = line(scroll)
            // The bug comes back to a chapter at its end; the fixed build to the line you left it at.
            let land = direction == .right ? (parent.bug ? ScrollReader.lines : left[next] ?? 1) : (left[next] ?? 1)
            show(chapter: next, in: scroll, line: land)
        }

        func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

/// A swipe across the reader, judged when the finger lifts: at least 50 points sideways and more sideways than up or
/// down, in the window's coordinates (the reader's own jump to another chapter mid-swipe moves the scroll view's). Not
/// a UISwipeGestureRecognizer: UIKit holds a recognizer's action until SpringBoard has decided the touch is not a
/// system gesture, and when SpringBoard is busy past the lift, as on a loaded CI runner, the recognizer ends and its
/// action is never sent, so the chapter turn was lost (#244). The touches themselves still arrive on time, so this
/// turns the chapter from them and never waits on SpringBoard.
final class SwipeAcross: UIGestureRecognizer {
    private let swiped: (UISwipeGestureRecognizer.Direction) -> Void
    private var start: CGPoint?

    init(_ swiped: @escaping (UISwipeGestureRecognizer.Direction) -> Void) {
        self.swiped = swiped
        super.init(target: nil, action: nil)
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        if start == nil { start = touches.first?.location(in: nil) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        if let start, let end = touches.first?.location(in: nil) {
            let dx = end.x - start.x, dy = end.y - start.y
            if abs(dx) >= 50 && abs(dx) > abs(dy) { swiped(dx < 0 ? .left : .right) }
        }
        state = .failed
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) { state = .failed }

    override func reset() { start = nil }
}

/// Covered content, and a text column inside the window. A running head over a column of lines and a Close button.
/// Fixed: the head and Close sit below the status bar and the column starts below them. The bugs, as Gatefold build 39
/// on the iPhone Duo: the head sits over the column's first line, Close sits under the status bar, and the column
/// slides most of the way past the window's side.
struct CoverPage: View {
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(1...12, id: \.self) { Text("Line \($0) of the page").accessibilityIdentifier("cover.line.\($0)") }
                }
                .padding(.horizontal, 24)
                .frame(width: geo.size.width, alignment: .leading)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("cover.column")
                .offset(x: bug ? geo.size.width * 0.6 : 0, y: bug ? 64 : 110)
                Text("Chapter One").font(.caption.bold())
                    .frame(maxWidth: .infinity, minHeight: 28)
                    .background(.background)
                    .accessibilityIdentifier("cover.head")
                    .offset(y: bug ? 56 : 64)
                if !bug {
                    Button("Close") {}.accessibilityIdentifier("cover.close").padding(.horizontal, 24).offset(y: 24)
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            // The bug's Close ignores the safe area and sits at the very top, under the status bar.
            if bug {
                Button("Close") {}.accessibilityIdentifier("cover.close").padding(.horizontal, 24).padding(.top, 6)
                    .ignoresSafeArea()
            }
        }
    }
}

/// Still while idle. A Close button and the status bar. Fixed: nothing changes with no input. The bug, as Gatefold's
/// reader on the open iPhone Duo (2026-11-15): with no touch, the status bar and Close take turns three times a
/// second, and Close jumps from one side to the other.
struct IdlePage: View {
    @State private var flip = false
    var body: some View {
        VStack {
            HStack {
                if !flip { Button("Close") {}.accessibilityIdentifier("idle.close") }
                Spacer()
                if flip { Button("Close") {}.accessibilityIdentifier("idle.close") }
            }
            .padding(24)
            Text("A page with nothing to do").accessibilityIdentifier("idle.page")
            Spacer()
        }
        .statusBarHidden(flip)
        .task {
            guard bug else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(330))
                flip.toggle()
            }
        }
    }
}

/// Viewport holds still. A page that scrolls up and down, with a shelf that scrolls sideways inside it, which a drag
/// across never judges. The bug, as Gatefold's reading page (2026-11-27): the page also scrolls sideways and its lines
/// run wider than the window, so a drag across pans the text and cuts off its leading edge.
struct ViewportPage: View {
    var body: some View {
        ScrollView(bug ? [.vertical, .horizontal] : .vertical) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Chapter One").font(.headline).accessibilityIdentifier("viewport.title")
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(1...6, id: \.self) { i in
                            Button {} label: {
                                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.orange.opacity(0.35))
                                    .frame(width: 140, height: 90)
                                    .overlay(Text("Shelf \(i)"))
                            }
                            .accessibilityIdentifier("viewport.shelf.\(i)")
                        }
                    }
                }
                .frame(height: 100)
                ForEach(1...30, id: \.self) { i in
                    Text("Line \(i) of a page that scrolls up and down, and never sideways")
                        .accessibilityIdentifier("viewport.line.\(i)")
                }
            }
            .padding(.horizontal, 24)
        }
        .accessibilityIdentifier("viewport.page")
    }
}

/// Chrome floats over content. A page of lines with a glass "Start from the beginning" pill over its foot, and room
/// at the end of the lines so the last one scrolls clear of it. The bug, as Gatefold's (2026-11-27): the pill sits
/// under the page in a stack, so the page shrinks to make room. With `under`, the other half of the bug: the pill
/// floats, but the lines end at the page's foot, so the last one can never be brought out from under it.
struct FloatPage: View {
    let under: Bool

    var body: some View {
        if bug && !under {
            VStack(spacing: 0) {
                lines
                pill.padding(.vertical, 12)
            }
        } else {
            lines
                .contentMargins(.bottom, bug ? 0 : 80, for: .scrollContent)
                .overlay(alignment: .bottom) { pill.padding(.bottom, 12) }
        }
    }

    private var lines: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(1...40, id: \.self) { Text("Line \($0) of the chapter").accessibilityIdentifier("float.line.\($0)") }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("float.page")
    }

    @ViewBuilder private var pill: some View {
        // The padding is inside the label, so the button's frame (what accessibility reports) is the whole pill.
        let button = Button {} label: {
            Text("Start from the beginning")
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
        }
        .accessibilityIdentifier("float.restart")
        if #available(iOS 26, *) {
            button.glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
        } else {
            button.background(.thinMaterial, in: Capsule(style: .continuous))
        }
    }
}

/// One action finishes the intent. A book that is not downloaded yet: a tap downloads it, its row counting up the
/// percent, and opens it. The bug, as Gatefold's (2026-11-27): the download finishes and the book stays shut until a
/// second tap.
struct IntentPage: View {
    @State private var downloaded = false
    @State private var progress: Double?
    @State private var open = false

    var body: some View {
        if open {
            VStack(spacing: 16) {
                Text("Call me Ishmael.").accessibilityIdentifier("intent.reader")
                Button("Close") { open = false }.accessibilityIdentifier("intent.close")
            }
        } else {
            VStack(spacing: 16) {
                Button(action: tap) {
                    HStack {
                        Text("Moby-Dick")
                        Spacer()
                        if let progress {
                            Text("\(Int((progress * 100).rounded()))%").monospacedDigit()
                        } else if !downloaded {
                            Image(systemName: "icloud.and.arrow.down").accessibilityLabel("Download")
                        }
                    }
                    .padding()
                }
                .accessibilityIdentifier("intent.book")
                if let progress { ProgressView(value: progress).accessibilityIdentifier("intent.progress") }
            }
            .padding(24)
        }
    }

    private func tap() {
        guard progress == nil else { return }
        if downloaded { open = true; return }
        Task { @MainActor in
            for step in 1...10 {
                progress = Double(step) / 10
                try? await Task.sleep(for: .milliseconds(200))
            }
            progress = nil
            downloaded = true
            if !bug { open = true }
        }
    }
}

// MARK: Gatefold's jank hunt, 2026-11-27 (ourostack/gatefold#646 to #654)

/// Words for a page, different on every line, so a line's words say where it is.
private func prose(_ n: Int, words: Int = 8) -> String {
    let pool = ["truth", "universally", "acknowledged", "single", "man", "possession", "good", "fortune", "want", "wife",
                "however", "little", "known", "feelings", "views", "neighbourhood", "minds", "surrounding", "families"]
    return ([("l\(n)")] + (1..<words).map { pool[(n * 7 + $0 * 3) % pool.count] }).joined(separator: " ")
}

/// Content clears the fold. A simulated fold runs top to bottom down the middle of the window, declared as the element
/// `ouro.fold`, as an app puts one over OuroHX's `OuroFoldRegion.frame`. Fixed: a page on each side of it. The bug, as
/// Gatefold#646: one column of text straight across it.
struct FoldPage: View {
    static let fold: CGFloat = 16

    var body: some View {
        ZStack {
            if bug {
                column(0..<12)
            } else {
                HStack(spacing: Self.fold + 24) {
                    column(0..<12)
                    column(12..<24)
                }
            }
            Rectangle().fill(.gray.opacity(0.35)).frame(width: Self.fold).frame(maxHeight: .infinity)
                .accessibilityElement().accessibilityLabel("Fold").accessibilityIdentifier("ouro.fold")
                .allowsHitTesting(false)
        }
        .padding(.horizontal, 12)
        .ignoresSafeArea(edges: .horizontal)
    }

    private func column(_ lines: Range<Int>) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(lines), id: \.self) { n in
                Text(prose(n, words: 14)).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 24)
    }
}

/// A turn lays out like a fresh launch. A page with a controls panel that belongs to portrait. Fixed: the panel follows
/// the window's shape. The bug, as Gatefold#647: the panel is decided once, at launch, so after a turn the old shape's
/// panel lingers (or the new one's is missing) until the app is launched again.
struct RelayoutPage: View {
    @State private var launchedPortrait: Bool?

    var body: some View {
        GeometryReader { geo in
            let portrait = geo.size.height > geo.size.width
            let panel = bug ? (launchedPortrait ?? portrait) : portrait
            VStack(spacing: 0) {
                Text(prose(1, words: 30)).padding(24).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .accessibilityElement(children: .combine).accessibilityIdentifier("relayout.page")
                if panel {
                    Text("Controls").frame(maxWidth: .infinity).frame(height: 160)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .accessibilityElement(children: .combine).accessibilityIdentifier("relayout.panel")
                }
            }
            .onAppear { if launchedPortrait == nil { launchedPortrait = portrait } }
        }
    }
}

/// Your place survives a turn. A scrolling page of lines, one text each. Fixed: a turn keeps the line at the top. The
/// bug, as Gatefold#650: the place is saved at the first turn only, so a turn after a scroll goes back to it. The page
/// runs under the status bar, as a SwiftUI scroll view does by default.
struct TurnPlacePage: View {
    @State private var top: Int?
    @State private var anchor: Int?

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<240, id: \.self) { n in
                        Text(prose(n)).lineLimit(1).frame(height: 32, alignment: .leading).id(n)
                    }
                }
                .scrollTargetLayout()
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollPosition(id: $top, anchor: .top)
            .accessibilityIdentifier("turn.page")
            .onChange(of: geo.size) {
                guard bug else { return }
                if let anchor { top = anchor } else { anchor = top ?? 0 }
            }
        }
    }
}

/// A jump lands on its own, on time. A page and a Contents button. Fixed: Contents lands on page 30 at once. The bug,
/// as Gatefold#651 on the Duo's cover: the jump waits, with the old page greyed, until the next tap on the page.
struct JumpPage: View {
    @State private var page = 1
    @State private var pending: Int?

    var body: some View {
        ZStack {
            Color.white.opacity(0.001).contentShape(Rectangle())
                .onTapGesture { if let pending { page = pending; self.pending = nil } }
            Text("Page \(page)").font(.largeTitle).opacity(pending == nil ? 1 : 0.4)
                .accessibilityIdentifier("jump.page").allowsHitTesting(false)
            VStack {
                Spacer()
                Button {
                    if bug { pending = 30 } else { page = 30 }
                } label: {
                    Text("Contents: page 30").padding(.horizontal, 20).padding(.vertical, 12)
                }
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .accessibilityIdentifier("jump.contents")
                .padding(.bottom, 40)
            }
        }
    }
}

/// What you asked for lands in clear view. A search result that jumps to a hit in a long page, with a "Back to where
/// you were" pill floating near the bottom. Fixed: the hit lands near the top. The bug, as Gatefold#652: it lands
/// under the pill.
struct HitPage: View {
    @State private var landed = false

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(0..<200, id: \.self) { n in
                            Text(n == 120 ? "the false account of his conduct" : prose(n)).lineLimit(1)
                                .frame(height: 30, alignment: .leading)
                                .accessibilityIdentifier(n == 120 ? "hit.target" : "").id(n)
                        }
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("hit.page")
                .overlay {
                    if landed {
                        Text("Back to where you were").padding(.horizontal, 20).padding(.vertical, 12)
                            .background(.thinMaterial, in: Capsule(style: .continuous))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("hit.back")
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.85)
                    } else {
                        Button {
                            landed = true
                            proxy.scrollTo(120, anchor: bug ? UnitPoint(x: 0.5, y: 0.85) : UnitPoint(x: 0.5, y: 0.2))
                        } label: {
                            Text("Search result: \"conduct\"").padding(.horizontal, 20).padding(.vertical, 12)
                        }
                        .background(.thinMaterial, in: Capsule(style: .continuous))
                        .accessibilityIdentifier("hit.result")
                        .position(x: geo.size.width / 2, y: geo.size.height * 0.5)
                    }
                }
            }
        }
    }
}

/// A notice gets out of the way. A page with a sign-in notice along its top. Fixed: the page makes room for it. The
/// bug, as Gatefold#654: it floats over the first line and stays there.
struct NoticePage: View {
    var body: some View {
        if bug {
            lines.overlay(alignment: .top) { notice }
        } else {
            lines.safeAreaInset(edge: .top) { notice }
        }
    }

    private var lines: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(0..<30, id: \.self) { Text(prose($0)) }
            }
            .padding(.horizontal, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("notice.page")
    }

    private var notice: some View {
        Text("Your place is waiting to reach your e-reader").font(.footnote).padding(12).frame(maxWidth: .infinity)
            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .combine).accessibilityIdentifier("notice.banner")
    }
}

/// Every target is big enough to hit. A reader's top bar with a close button. Fixed: the button's frame is 44 pt. The
/// bug, as the Duo's `reader.close` in the jank hunt: the button is its 14 pt glyph.
struct TargetsPage: View {
    var body: some View {
        VStack(spacing: 24) {
            HStack {
                Button {} label: {
                    Image(systemName: "xmark").resizable().frame(width: 14, height: 14)
                        .frame(width: bug ? 14 : 44, height: bug ? 14 : 44).contentShape(Rectangle())
                }
                .accessibilityLabel("Close").accessibilityIdentifier("targets.close")
                Spacer()
            }
            .padding(.horizontal, 16)
            Button {} label: { Text("Read").frame(maxWidth: .infinity).frame(height: 50) }
                .background(.thinMaterial, in: Capsule(style: .continuous))
                .accessibilityIdentifier("targets.read")
                .padding(.horizontal, 24)
            Spacer()
        }
    }
}

/// The screen shows only the before, the after or a veil, at a jump. Big pages that look nothing alike. Fixed: Jump
/// puts up a plain veil, then page 30. The bug: another page shows on the way to it, for 1.5 s (Gatefold#653 showed one
/// for about 0.2 s, too short for a screenshot film to catch).
struct LandingPage: View {
    @State private var shown = 1
    @State private var veil = false
    @State private var jumped = false

    var body: some View {
        ZStack {
            VStack(spacing: 24) {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(shown == 1 ? Color.teal : (shown == 30 ? Color.purple : Color.orange))
                    .overlay(Text("Page \(shown)").font(.system(size: 60, weight: .bold)).foregroundStyle(.white))
                    .frame(height: 420)
                    .padding(.horizontal, 24)
                    .accessibilityHidden(true)
                Button("Jump") {
                    guard !jumped else { return }
                    jumped = true
                    Task { @MainActor in
                        if bug {
                            shown = 17
                            try? await Task.sleep(for: .seconds(1.5))
                        } else {
                            veil = true
                            try? await Task.sleep(for: .seconds(1.5))
                            veil = false
                        }
                        shown = 30
                    }
                }
                .accessibilityIdentifier("landing.jump")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            if veil { Color(white: 0.5).ignoresSafeArea().accessibilityHidden(true) }
        }
    }
}

/// The screen shows only the before, the after or a veil, through a turn. Fixed: the page re-lays out with the turn.
/// The bug, as Gatefold#649 on the iPad: for 3 s after the turn, the page is drawn squeezed to half its width before
/// the new layout lands (long enough to outlast XCUITest's wait for the turn to be confirmed).
struct TurnFilmPage: View {
    @State private var squeezed = false

    var body: some View {
        GeometryReader { geo in
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.teal)
                .overlay(Text(geo.size.width > geo.size.height ? "Landscape" : "Portrait").font(.system(size: 48, weight: .bold))
                    .foregroundStyle(.white))
                .padding(24)
                .scaleEffect(x: squeezed ? 0.5 : 1, y: 1)
                .accessibilityHidden(true)
                .onChange(of: geo.size) {
                    guard bug else { return }
                    squeezed = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        squeezed = false
                    }
                }
        }
    }
}
