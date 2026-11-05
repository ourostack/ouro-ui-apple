# Taste rubric: what still needs a human-quality eye

Run Ouro Feel first. Every genre in [README.md](README.md) has a deterministic check; a taste review that re-tests one
of them by hand is wasted. This list is what the checks cannot judge. Review on a device where it says so, and say in
the review which device or simulator you used, cold or warm, and which observations are inference.

## Before you start

- [ ] The Feel checks for this build ran and passed, cold (`scripts/ouro-feel-cold.sh`), and you have their reports.
- [ ] You know what the app is for and who the screen serves; judge against that, not against a generic app.

## Motion character (a device, ProMotion if you can)

- [ ] Springs feel physical: a quick flick goes far, a slow drag stays close, nothing overshoots like rubber.
- [ ] Interrupting a motion (tap or drag mid-flight) turns it around from where it is, not from where it started.
- [ ] Motion tells you where things came from and went; a sheet rises from what opened it, a back swipe reveals what
      is behind.
- [ ] Durations feel deliberate. Feel measures settle time; only a person can say whether 0.4 s feels lazy here.
- [ ] Reduce Motion still feels designed (crossfades, not jumps).

## Touch and haptics (a device)

- [ ] Each haptic means something and matches its weight: a selection tick, a success, a warning. None for nothing.
- [ ] Targets feel generous for thumbs, especially at the screen's bottom corners and in landscape.
- [ ] Press states answer at once; a control never feels dead for a beat.

## Visual craft

- [ ] Type has a hierarchy you can read at a glance; Dynamic Type at the largest size still looks composed.
- [ ] Spacing has a rhythm; edges and baselines line up; nothing looks nudged.
- [ ] Light, dark and Increase Contrast each look intended, not inverted.
- [ ] Empty, loading and error states have the same care as the full state.
- [ ] No unnecessary cards: content sits in the open unless it really is a separate object.

## Platform fit

- [ ] It feels like an Apple app: system controls where people expect them, standard gestures doing standard things.
- [ ] Words are plain, short and in the app's voice; buttons say what they do.
- [ ] iPad, landscape and any foldable posture are designed layouts, not stretched phones.

## Surprise and delight

- [ ] Something made you smile, and it would still be welcome the hundredth time.
- [ ] Nothing feels like a template; the app has a point of view.

## Writing it up

For each item that fails, give the screen, what you did, what you expected, and a screenshot or short film. Mark
anything you reasoned rather than saw as inference. If a failure is a genre Feel covers (a jump, a missing way back),
add a Feel check that catches it before you file it; the check, not the review, should catch it next time.
