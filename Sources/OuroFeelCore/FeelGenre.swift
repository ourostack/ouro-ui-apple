/// The genres of jank Ouro Feel checks, each with what good feels like. A check's ``FeelResult/check`` is its genre's
/// name, so a report groups by genre. The first ten are the genres Ari named (2026-11-05: "backwards nav must always be
/// easy! we must fix all these genres of jank"); flicker, stray input and navigation that fights you are the ones Gatefold
/// build 20 showed (Ari, 2026-11-07: "literally spazzes! and fucked my location with accidental navigation"); hitches is
/// a measure beside them.
public enum FeelGenre: String, CaseIterable, Codable, Sendable {
    case wayBack = "the way back"
    case overlayDismissal = "overlay dismissal"
    case insideWindow = "inside the window"
    case tapLanding = "tap landing"
    case doubleDraw = "double-draw"
    case jumpAfterLanding = "jump after landing"
    case chrome = "late or lingering chrome"
    case snap = "snap with no transition"
    case settleTime = "settle time"
    case placeStability = "place stability"
    case flicker
    case strayInput = "place kept through stray input"
    case navigationFight = "navigation that fights you"
    case hitches

    /// One line: what good feels like.
    public var good: String {
        switch self {
        case .wayBack: "Every screen you reach has a visible way back and a gesture back, and both return you where you were."
        case .overlayDismissal: "Every sidebar, popover and menu goes away with a tap outside it, and once you pick something in it."
        case .insideWindow: "Every control sits wholly inside the window, in every orientation and after turning the device and back."
        case .tapLanding: "One tap anywhere on a control works, every time, with no second try."
        case .doubleDraw: "Each piece of content is on screen once; nothing shows a ghost copy mid-transition."
        case .jumpAfterLanding: "Once something lands it stays put; nothing nudges it afterwards."
        case .chrome: "Bars and controls hand over in one beat: never two states at once, never a blank between them."
        case .snap: "Things that move travel there; nothing teleports across the screen."
        case .settleTime: "The screen comes to rest promptly after you act."
        case .placeStability: "Reopen, relaunch or turn the device and you are exactly where you were."
        case .flicker: "Each thing changes once on its way to where it ends; nothing flips back and forth before it settles."
        case .strayInput: "A stray tap, an edge swipe that goes nowhere, dismissing a sheet or leaving the app never moves your place."
        case .navigationFight: "After you move, your place stays where you put it: no late restore, re-sent jump or sync landing moves it again."
        case .hitches: "Motion runs at the display's pace with no visible stall."
        }
    }
}
