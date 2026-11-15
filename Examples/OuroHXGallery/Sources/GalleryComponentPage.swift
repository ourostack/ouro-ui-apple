import SwiftUI

/// A component's page in the gallery. Each page is a subclass in its own file under `Pages/`, which names the page and
/// draws it; the gallery finds every subclass when it starts. So a new component adds one file and edits no shared
/// list, and two component pull requests never conflict over the gallery. Its UI tests register the same way
/// (`UITests/Pages/`, `GalleryPageClaims`), and `scripts/ui-shards.py check` fails when the two disagree.
class GalleryComponentPage: NSObject {
    /// What `-page` opens it by, and what the UI tests audit it as: lower case, one word.
    class var page: String { fatalError("\(self) must name its page") }
    /// Its name in the page menu.
    class var title: String { fatalError("\(self) must give its title") }
    /// Other words `-page` opens it by, such as the singular or a component it shows.
    class var aliases: [String] { [] }
    /// The page.
    @MainActor class var content: AnyView { fatalError("\(self) must draw its page") }

    /// Every component page, in the menu's order: by title.
    @MainActor static let all: [GalleryComponentPage.Type] = subclasses(of: GalleryComponentPage.self).sorted { $0.title < $1.title }

    /// The page `-page <name>` names, by its page or one of its aliases, in any case.
    @MainActor static func named(_ name: String) -> GalleryComponentPage.Type? {
        let name = name.lowercased()
        return all.first { $0.page == name || $0.aliases.contains(name) }
    }
}
