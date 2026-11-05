// A tiny pantry app's core, driven through Ouro Reins: a tab bar, a push stack and two screens. It shows the shape an
// app adopts (a view model that already exists, plus one `reinsNode` extension) and is what CI pipes `ls` and `do` into.
//
//   swift run ouro-reins-sample ls 'do openItem {"id":"flour"}' 'do toggleStocked' 'do goBack'
//   printf 'ls\ndo nope\n' | swift run ouro-reins-sample

import OuroReins

/// The view model as an app would already have it: plain state and the methods its buttons call.
@MainActor
final class Pantry {
    struct Item: Codable, Sendable { var id: String; var name: String; var stocked: Bool }

    enum Tab: String, CaseIterable { case pantry, settings }

    private(set) var items: [Item]
    private(set) var tab: Tab = .pantry
    private(set) var stack: [String] = []
    private(set) var showsEmpty = false

    init(items: [Item]) { self.items = items }

    func select(_ tab: Tab) { self.tab = tab }
    func open(_ id: String) throws {
        guard items.contains(where: { $0.id == id }) else { throw PantryError.noSuchItem(id) }
        stack.append(id)
    }
    func goBack() { _ = stack.popLast() }
    func toggleStocked(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].stocked.toggle()
    }
    func setShowsEmpty(_ value: Bool) { showsEmpty = value }

    enum PantryError: Error, CustomStringConvertible {
        case noSuchItem(String)
        var description: String { switch self { case .noSuchItem(let id): "no item \(id)" } }
    }
}

struct OpenItem: ReinsInput { let id: String }
struct ShowsEmpty: ReinsInput { let on: Bool }

/// The adoption: one extension, reading state the view model already has and calling the methods its buttons call.
extension Pantry: ReinsDrivable {
    var reinsNode: ReinsNode {
        .tabs(selected: tab.rawValue, tabs: Tab.allCases.map(\.rawValue), select: { [unowned self] in
            if let tab = Tab(rawValue: $0) { self.select(tab) }
        }, child: tab == .pantry ? pantryStack : settings)
    }

    private var pantryStack: ReinsNode {
        let top: ReinsNode
        if let id = stack.last, let item = items.first(where: { $0.id == id }) {
            top = ReinsNode("item", encoding: item, actions: [
                ReinsAction("toggleStocked", "Mark as stocked or out") { [unowned self] in self.toggleStocked(id) },
            ])
        } else {
            let shown = showsEmpty ? items : items.filter(\.stocked)
            top = ReinsNode("list", encoding: ["items": shown], actions: [
                ReinsAction("openItem", "Open an item", input: OpenItem.self) { [unowned self] in try self.open($0.id) },
            ])
        }
        return .stack(depth: stack.count, goBack: { [unowned self] in self.goBack() }, child: top)
    }

    private var settings: ReinsNode {
        ReinsNode("settings", state: ["showsEmpty": .bool(showsEmpty)], actions: [
            ReinsAction("setShowsEmpty", "Show items that are out", input: ShowsEmpty.self) { [unowned self] in self.setShowsEmpty($0.on) },
        ])
    }
}

let pantry = Pantry(items: [
    .init(id: "flour", name: "Flour", stocked: true),
    .init(id: "yeast", name: "Yeast", stocked: false),
])
await ReinsCommandLine.run(ReinsSession(pantry))
