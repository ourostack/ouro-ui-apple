# Releasing

Releases are tags `vX.Y.Z` on `main`, published as GitHub releases.

1. Merge everything for the release through pull requests, and wait for `main`'s CI to pass, the billed `xcode-27`
   jobs included.
2. **Run the component claims on iOS 27, locally.** CI proves them on iOS 26 only: the free `macos-26` image has
   Xcode 26.6, whose newest simulator runtime is iOS 26.5, and the billed `xcode-27` runner is kept to builds and the
   X-ray (README, CI). iOS 27 is what people run, so this step is required. On a Mac with Xcode 27 and an iOS 27
   runtime, from a clean checkout of the commit you will tag:

   ```sh
   udid=$(xcrun simctl create ouro-hx-ios27 "iPhone 17 Pro" com.apple.CoreSimulator.SimRuntime.iOS-27-2)
   sh scripts/ios27-claims.sh "$udid" .build/ios27-claims-vX.Y.Z.txt
   xcrun simctl delete "$udid"
   ```

   Every claim must pass. A failure is a bug to fix before the tag, not something to rerun past.
3. Check the next free tag (`git ls-remote --tags origin`), then tag and publish:

   ```sh
   git tag -a vX.Y.Z -m "vX.Y.Z: <one line>" <commit>
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title vX.Y.Z --notes-file <notes> --verify-tag
   gh release upload vX.Y.Z .build/ios27-claims-vX.Y.Z.txt
   ```

   The log, attached to the release, names the commit, the Xcode and the runtime it ran on.
4. Wait for the release's CI to pass. A failure with no open issue is a bug: file it before anything is rerun.

When GitHub's free image ships Xcode 27 with an iOS 27 runtime, move this step into the gallery job on `macos-26`
and drop it from here.
