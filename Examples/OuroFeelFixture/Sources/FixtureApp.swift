import SwiftUI

/// One page per genre of jank. `-page <name>` picks it; `-bug 1` turns on its known bug. The UI tests prove each
/// Ouro Feel check fails with the bug and passes without it.
@main
struct FixtureApp: App {
    var body: some Scene {
        WindowGroup {
            switch UserDefaults.standard.string(forKey: "page") ?? "nav" {
            case "window": WindowPage()
            case "taps": TapsPage()
            case "motion": MotionPage()
            case "place": PlacePage()
            case "overlay": OverlayPage()
            case "push": PushPage()
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

/// Tap landing. The bugs: an invisible strip over the switch's trailing end swallows taps, and the switch ignores
/// taps for a quarter second after each change (taps while it animates are lost). Paced taps come 0.6 s apart, so
/// only rapid taps meet the lock; a longer lock could swallow a paced tap on a slow runner and hide the rapid result.
struct TapsPage: View {
    @State private var on = false
    @State private var lockedUntil = Date.distantPast
    var body: some View {
        HStack {
            Text("Page Numbers").accessibilityIdentifier("taps.title")
            Spacer()
            Toggle("Page Numbers", isOn: Binding(get: { on }, set: { value in
                if bug && Date() < lockedUntil { return }
                on = value
                lockedUntil = Date().addingTimeInterval(0.25)
            }))
                .labelsHidden()
                .accessibilityIdentifier("taps.toggle")
                .overlay(alignment: .trailing) {
                    if bug { Color.white.opacity(0.001).frame(width: 22).onTapGesture {} }
                }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 100)
    }
}

/// Settle, jumps, double draws, chrome and snaps. `-autoplay N` seconds (default 2) after Play is tapped the card travels
/// down (so the motion runs while the test is free to sample). The bug: it snaps there with no transition, a ghost copy stays behind for a
/// second, both bars show at once for a second, and the card jumps 40 points 2 s after it landed (so it also settles late).
struct MotionPage: View {
    @State private var down = false
    @State private var nudge: CGFloat = 0
    @State private var ghost = false
    @State private var fullBar = true
    @State private var compactBar = false

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                if fullBar { bar("Kitchen", id: "bar.full", height: 96) }
                if compactBar { bar("Kitchen", id: "bar.compact", height: 52) }
                Spacer()
            }
            if ghost { card.offset(y: 200).accessibilityIdentifier("motion.ghost") }
            card.offset(y: (down ? 520 : 200) + nudge).accessibilityIdentifier("motion.card")
            Button("Play") { Task { await play() } }
                .accessibilityIdentifier("motion.play")
                .offset(y: 700)
        }
    }

    /// Starts `-autoplay` seconds (default 2) after the Play tap, so the motion runs after XCUITest's idle wait for
    /// the tap ends, however long launching took.
    func play() async {
            try? await Task.sleep(for: .seconds(UserDefaults.standard.double(forKey: "autoplay").nonZero ?? 2))
            if bug {
                ghost = true
                down = true
                compactBar = true
                try? await Task.sleep(for: .seconds(1))
                ghost = false
                fullBar = false
                try? await Task.sleep(for: .seconds(1))
                nudge = 40
            } else {
                withAnimation(.easeInOut(duration: 0.8)) { down = true }
                withAnimation(.easeInOut(duration: 0.15)) { fullBar = false; compactBar = true }
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

extension Double {
    var nonZero: Double? { self == 0 ? nil : self }
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
                Menu {
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
