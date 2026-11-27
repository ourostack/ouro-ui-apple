/// The genres of jank Ouro Feel first checked, each with what good feels like. A check's ``FeelResult/check`` is its
/// genre's name, so a report groups by genre. This list is closed (a public enum gains no case without breaking the
/// apps that switch over it); every genre is also a ``FeelCheck``, and a check added since lives only there, under the
/// ``FeelPrinciple`` it holds (docs/ouro-feel/README.md, "Add a check").
///
/// Where they came from. The first ten are the genres Ari named (2026-11-05: "backwards nav must always be easy! we
/// must fix all these genres of jank"); flicker, stray input and navigation that fights you are the ones Gatefold
/// build 20 showed (Ari, 2026-11-07: "literally spazzes! and fucked my location with accidental navigation"); hitches
/// is a measure beside them. Gatefold build 39 widened inside the window to what you read (Ari, 2026-11-15: the running
/// header over the first line, the text column off the side, controls over the status bar).
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
        case .insideWindow: "Every control and what you read sits wholly inside the window, in every orientation and after turning the device and back; no header, bar or control covers the text or sits under the status bar."
        case .tapLanding: "One tap anywhere on a control works, every time, with no second try."
        case .doubleDraw: "Each piece of content is on screen once; nothing shows a ghost copy mid-transition."
        case .jumpAfterLanding: "Once something lands it stays put; nothing nudges it afterwards."
        case .chrome: "Bars and controls hand over in one beat: never two states at once, never a blank between them."
        case .snap: "Things that move travel there; nothing teleports across the screen."
        case .settleTime: "The screen comes to rest promptly after you act."
        case .placeStability: "Reopen, relaunch or turn the device and you are exactly where you were."
        case .flicker: "Each thing changes once on its way to where it ends; nothing flips back and forth before it settles, and with no input nothing changes at all."
        case .strayInput: "A stray tap (the middle, the top edge), an edge swipe that goes nowhere, a swipe across and back, dismissing a sheet or leaving the app never moves your place."
        case .navigationFight: "After you move, your place stays where you put it: no late restore, re-sent jump or sync landing moves it again."
        case .hitches: "Motion runs at the display's pace with no visible stall."
        }
    }

    /// The principle this genre holds.
    public var principle: FeelPrinciple {
        switch self {
        case .wayBack, .overlayDismissal, .tapLanding: .intent
        case .placeStability, .strayInput, .navigationFight: .place
        case .insideWindow: .canvas
        case .doubleDraw, .jumpAfterLanding, .chrome, .snap, .settleTime, .flicker, .hitches: .motion
        }
    }

    /// The calls that run this genre's checks, as a test writes them.
    public var calls: [String] {
        switch self {
        case .wayBack: ["feel.wayBack(from:follow:depth:)"]
        case .overlayDismissal: ["feel.overlays(_:)"]
        case .insideWindow: ["feel.insideWindow(poses:also:)", "feel.uncovered(by:content:within:poses:)"]
        case .tapLanding: ["feel.tapLanding(on:trials:spots:title:rowToggles:baseline:rapid:rapidBaseline:)", "feel.osBaseline(rapid:)"]
        case .doubleDraw: ["film.doubleDraws(of:)"]
        case .jumpAfterLanding: ["film.jumps(of:rest:limit:)", "feel.screenFilm(...).revealHolds(cover:until:)"]
        case .chrome: ["film.chrome(from:to:grace:)"]
        case .snap: ["film.snaps(of:distance:appearing:)"]
        case .settleTime: ["film.settles(_:within:)"]
        case .placeStability: ["feel.place(across:read:)"]
        case .flicker: ["film.flickers(of:within:changes:)", "feel.screenFilm(...).flickers(within:states:)", "feel.stillWhileIdle(for:watch:poses:)"]
        case .strayInput: ["feel.placeHeld(across:reads:between:read:)"]
        case .navigationFight: ["feel.placeFights(_:reads:hold:between:read:)"]
        case .hitches: ["FeelHitches.analyze(timestamps:refresh:)", "film.hitches()", "feel.measureHitches(in:)"]
        }
    }
}

/// One of the few promises every Ouro Feel check holds an app to. A principle is the reason; its checks are how it is
/// held, and the set under each grows whenever a report shows jank no check caught. A new check names the principle
/// it serves; a principle is added only when a report breaks a promise none of these make.
public struct FeelPrinciple: Hashable, Codable, Sendable {
    /// A short, stable name for code and data ("intent").
    public let id: String
    /// The principle, in a few words.
    public let name: String
    /// One line: the promise.
    public let promise: String

    public init(id: String, name: String, promise: String) {
        self.id = id
        self.name = name
        self.promise = promise
    }

    public static let intent = FeelPrinciple(
        id: "intent", name: "your intent is the unit",
        promise: "What you meant takes one go: one tap lands, one tap finishes what it started, and every way in has a way back out.")
    public static let place = FeelPrinciple(
        id: "place", name: "your place is yours",
        promise: "Where you are reading or working stays put through relaunches, turns, stray touches and late replies.")
    public static let canvas = FeelPrinciple(
        id: "canvas", name: "the content is the canvas",
        promise: "What you read fills its space and stays there: inside the window, still on every axis it doesn't scroll, and never covered or crowded out by chrome.")
    /// Posture changes re-lay out in place. From the Gatefold jank hunt, 2026-11-27 (ourostack/gatefold#646 to #650): a
    /// Duo held like a book laid out as tabletop, a layout outlived the posture that made it, and a turn lost the place.
    public static let posture = FeelPrinciple(
        id: "posture", name: "posture changes re-lay out in place",
        promise: "When the device turns, folds or unfolds, the screen lays out as if it had launched that way: nothing lingers from the old shape, nothing runs across the fold, and your place stays where it was.")
    public static let motion = FeelPrinciple(
        id: "motion", name: "motion and chrome never surprise",
        promise: "Nothing moves unbidden: things move once, on purpose, at the display's pace, and the screen only ever shows where it was or where it is going. No ghost, no jump, no snap, no flicker, no stall.")

    /// Every principle, in the order the guide gives them.
    public static let all: [FeelPrinciple] = [intent, place, canvas, posture, motion]

    /// This principle's checks, in ``FeelCheck/all`` order.
    public var checks: [FeelCheck] { FeelCheck.all.filter { $0.principle == self } }

    /// Principles are the same when their ids are, so rewording a promise never splits one in two.
    public static func == (a: FeelPrinciple, b: FeelPrinciple) -> Bool { a.id == b.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// One check Ouro Feel runs: its name (the ``FeelResult/check`` its reports carry), what good feels like, the
/// principle it holds and the calls that run it. The set is open: adding a check is a `static let` here, a line in
/// ``all`` and the rest of the guide's "Add a check", never a breaking change.
public struct FeelCheck: Hashable, Codable, Sendable {
    public let name: String
    public let good: String
    public let principle: FeelPrinciple
    public let calls: [String]

    public init(name: String, good: String, principle: FeelPrinciple, calls: [String]) {
        self.name = name
        self.good = good
        self.principle = principle
        self.calls = calls
    }

    public init(_ genre: FeelGenre) {
        self.init(name: genre.rawValue, good: genre.good, principle: genre.principle, calls: genre.calls)
    }

    /// Checks are the same when their names are (the name every report carries), whatever their wording.
    public static func == (a: FeelCheck, b: FeelCheck) -> Bool { a.name == b.name }
    public func hash(into hasher: inout Hasher) { hasher.combine(name) }

    /// Viewport holds still. From Gatefold, 2026-11-27: the reading page could be dragged sideways, cutting off the
    /// text's left edge (Ari: "being able to mess with viewport is very much something ouro feel should be catching").
    public static let viewportHolds = FeelCheck(
        name: "viewport holds still",
        good: "Nothing pans on an axis it doesn't scroll, and no content is wider or taller than its viewport on an axis that is fixed, in every pose.",
        principle: .canvas, calls: ["feel.viewportHolds(scrolling:poses:)"])

    /// Chrome floats over content. From Gatefold, 2026-11-27: a Liquid Glass "start from the beginning" pill shrank
    /// the reading area and hid its last lines, instead of floating over the text.
    public static let chromeFloats = FeelCheck(
        name: "chrome floats over content",
        good: "Glass and overlays float over the content: it runs underneath them, never shrinks or is cropped to make room, and its end can always be brought clear of them.",
        principle: .canvas, calls: ["feel.chromeFloats(_:over:content:toEnd:poses:)"])

    /// One action finishes the intent. From Gatefold, 2026-11-27: opening a book that was not downloaded downloaded
    /// it and stopped; it took a second tap to open.
    public static let finishesIntent = FeelCheck(
        name: "one action finishes the intent",
        good: "A tap that starts slow work (a download, a load, a sign-in) finishes what you asked for when the work is done; you never tap it twice.",
        principle: .intent, calls: ["feel.finishesIntent(_:opens:within:quiet:)", "feel.finishesIntent(_:named:within:quiet:done:)"])

    /// Content clears the fold. From Gatefold, 2026-11-27 (ourostack/gatefold#646): a Duo half-open like a book laid
    /// the page out as one column straight across the fold.
    public static let clearsTheFold = FeelCheck(
        name: "content clears the fold",
        good: "In every fold posture nothing you read runs across the fold, and a device held open like a book shows a page on each side of it.",
        principle: .posture, calls: ["feel.clearsTheFold(_:content:within:spread:posture:)", "feel.clearsTheFold(at:content:within:spread:posture:)"])

    /// A turn lays out like a fresh launch. From Gatefold, 2026-11-27 (ourostack/gatefold#647): opening a Duo flat
    /// after book posture kept the tabletop layout for 10 s and more.
    public static let laysOutFresh = FeelCheck(
        name: "a turn lays out like a fresh launch",
        good: "A few seconds after the device turns, folds or unfolds, the screen is laid out as a fresh launch in that posture lays it out: nothing lingers, nothing is missing.",
        principle: .posture, calls: ["feel.laysOutFresh(after:within:keys:reopen:)", "feel.laysOutFresh(named:within:keys:reopen:change:)"])

    /// Your place survives a turn. From Gatefold, 2026-11-27 (ourostack/gatefold#650): in scroll mode, a turn after a
    /// scroll went back to the previous turn's place.
    public static let placeSurvivesTurns = FeelCheck(
        name: "your place survives a turn",
        good: "After a turn, the first words on screen are within a line of the first words before it, however you scrolled since the last turn.",
        principle: .posture, calls: ["feel.placeSurvivesTurns(_:within:line:between:read:)"])

    /// What you asked for lands in clear view. From Gatefold, 2026-11-27 (ourostack/gatefold#652): a search hit landed
    /// under the "Back to where you were" pill.
    public static let landsInClearView = FeelCheck(
        name: "what you asked for lands in clear view",
        good: "A jump's target (a search hit, a linked passage, a chosen chapter) lands wholly inside the window and under no chrome.",
        principle: .canvas, calls: ["feel.landsInClearView(_:chrome:over:within:jump:)"])

    /// A notice gets out of the way. From Gatefold, 2026-11-27 (ourostack/gatefold#654): the re-sign-in notice
    /// covered the first line of every page, through page turns.
    public static let noticeGivesWay = FeelCheck(
        name: "a notice gets out of the way",
        good: "A banner or notice never stays over what you read: the content makes room for it, or it goes once you act or wait.",
        principle: .canvas, calls: ["feel.noticeGivesWay(_:content:within:after:then:)"])

    /// A jump lands on its own, on time. From Gatefold, 2026-11-27 (ourostack/gatefold#651): Contents, search and
    /// scrubber jumps held the old page for 4 to 8 s, and on the iPhone and the Duo's cover landed only at the next tap.
    public static let landsOnItsOwn = FeelCheck(
        name: "a jump lands on its own, on time",
        good: "A jump (a contents entry, a search hit, a scrubber drop) lands on its target within its budget, with no further tap.",
        principle: .intent, calls: ["feel.landsOnItsOwn(_:on:budget:within:nudge:)", "feel.landsOnItsOwn(named:budget:within:nudge:jump:landed:)"])

    /// Every target is big enough to hit. From the Gatefold jank hunt, 2026-11-27: the Duo's close button read 14 by
    /// 14 points.
    public static let targetsBigEnough = FeelCheck(
        name: "every target is big enough to hit",
        good: "Every button, link and tab is at least 44 by 44 points, so a tap lands where you aim.",
        principle: .intent, calls: ["feel.targetsBigEnough(minimum:ignoring:poses:)"])

    /// The screen shows only the before, the after or a veil. From Gatefold, 2026-11-27 (ourostack/gatefold#648,
    /// #649, #653): turns went through stretched, tiny and doubled frames, and a search jump drew a page that was
    /// neither the old one nor the target.
    public static let beforeAfterOrVeil = FeelCheck(
        name: "the screen shows only the before, the after or a veil",
        good: "Through a turn or a jump the screen rests only on the old view, the new one or a plain veil: never a stretched, squeezed, shrunken or blended picture, a band, or another page.",
        principle: .motion, calls: ["feel.screenFilm(...).beforeAfterOrVeil(veils:)"])

    /// Every check: the genres first, then each added since, in the order they came.
    public static let all: [FeelCheck] = FeelGenre.allCases.map(FeelCheck.init) + [
        viewportHolds, chromeFloats, finishesIntent,
        clearsTheFold, laysOutFresh, placeSurvivesTurns, landsInClearView, noticeGivesWay, landsOnItsOwn, targetsBigEnough,
        beforeAfterOrVeil,
    ]
}
