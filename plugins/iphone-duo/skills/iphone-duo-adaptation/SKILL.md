---
name: iphone-duo-adaptation
description: Adapt an existing iOS app (SwiftUI or UIKit) to iPhone Duo, Apple's foldable iPhone (outer 466×678 pt, inner 626×890 pt, both report regular width). Covers environment setup (Xcode 27.1, iOS 27.1 runtime, DeviceHub), a static audit of risky patterns, the layout bugs that actually show up on the inner display (NavigationView turning into a split view, orientation locks ignored, safe-area gaps, over-stretched controls) with tested fixes, a simulator test matrix, and App Store work (Duo screenshot sizes, April 2027 deadline, featuring nomination). Use this whenever the user mentions iPhone Duo, 折叠屏 / foldable iPhone, 内屏 / 外屏, DeviceHub, Xcode 27.1, "get my app ready for iPhone Duo", Duo screenshots, or asks why their app looks wrong (narrow column, black half, giant stretched buttons) on a large or wide iPhone canvas — even if they don't say "adaptation".
---

# iPhone Duo adaptation

A field guide distilled from adapting a real shipping SwiftUI app to iPhone Duo.
Everything marked *(verified)* was observed on the iPhone Duo simulator (Xcode 27.1 RC 27A9275,
iOS 27.1 runtime, Oct 2026). Re-check facts against Apple's current docs before relying on dates or
sizes — this device and its tooling are new and may change.

## Why this matters even if the app "isn't changing"

Apple's compatibility table depends on the **SDK the binary was built with**:

| Built with | Inner display | Outer display |
|---|---|---|
| iOS 26 SDK or earlier | centered, empty space around, no resizing | left of status bar/camera |
| iOS 27 SDK (Xcode 27.0) | fills most of the inner display, **dynamic resizing on fold/unfold** | — |
| iOS 27.1 SDK (Xcode 27.1+) | edge-to-edge; **tab bars / toolbars become vertical on the right** | full display |

So an app already shipped with Xcode 27.0 is *already* resizable on Duo, and its layout bugs are
already live for Duo owners. Tell the user this early: it changes how urgent the work is.

## Workflow

1. **Environment** — see "Setup" below. Needs Xcode 27.1 (macOS Tahoe 26.6+ on Apple silicon),
   the iOS 27.1 simulator runtime, and DeviceHub (the renamed Simulator app).
2. **Static audit** — run `scripts/audit_duo.sh <project-dir>`. It greps for every pattern Apple
   lists plus the ones that bit us. Review each hit; most need a judgment call, not a blind rewrite.
3. **Run it on the Duo simulator** — `scripts/duo_sim.sh` creates/boots the device, installs the
   app and grabs screenshots of the right display. Look at every top-level screen on the outer
   display, then ask the user to unfold in DeviceHub and check the inner display.
4. **Fix** — work through "Pitfalls" in order of severity. Templates are in
   `references/swiftui-patterns.md`.
5. **Regression-check a normal iPhone** after every layout change. The bar is: nothing changes on
   iPhone. Gate every wide-canvas layout on *measured available width*, not on device type.
6. **App Store** — screenshots, nomination; see the last section.

## Setup

- **Xcode 27.1**: developer.apple.com/download/applications → "Xcode 27.1 Release Candidate"
  (needs the user's Apple Developer login — they download, you can do the rest). RC builds can be
  submitted to the App Store. Verify the .xip with `pkgutil --check-signature` before expanding.
  - Replacing `/Applications/Xcode.app` needs admin rights; moving the old one to the Trash via
    Finder (`osascript -e 'tell application "Finder" to delete (POSIX file "/Applications/Xcode.app" as alias)'`)
    prompts the user for their password and keeps a way back.
  - Then `xcodebuild -runFirstLaunch` and `xcodebuild -downloadPlatform iOS` (several GB).
  - Side effect *(verified)*: Xcode's "Recent Projects" list may be empty afterwards. Nothing is
    lost; reopening each project restores it.
- **DeviceHub** replaces Simulator.app: `/Applications/Xcode.app/Contents/Applications/DeviceHub.app`.
  `open -a Simulator` fails.
- **iPhone Duo only runs on the iOS 27.1 runtime** *(verified: creating it on 27.0 → "Incompatible device")*.
- **Fold/unfold and rotation have no `simctl` command.** Only DeviceHub's UI can change posture.
  If you can't click the UI yourself, ask the user to unfold/rotate and tell you when.
- **Screenshots of the inner display need `--display`** *(verified)*: the default (and
  `--display=1`/`primary`) is the outer display (1398×2034 / 2034×1398 px); the inner display was
  `--display=3` (2007×2853 / 2853×2007 px). The outer display renders black while unfolded.
  `scripts/duo_sim.sh shot` tries the IDs and picks by size.
- Synthetic taps in the simulator usually aren't available to the agent; drive screens with
  launch arguments the app already supports (debug deep links / `-Promo`-style flags) and leave
  interactive checks (tapping, scrolling, fold mid-flow) to the user with a concrete checklist.

## Pitfalls, most severe first

### 1. `NavigationView` becomes a split view — whole app squeezed into a sidebar *(verified, severe)*
Both Duo displays report **regular horizontal size class**. A SwiftUI `NavigationView` (default
style) then turns into sidebar + detail: the entire screen renders in a ~1/3-width column on the
left, the rest is black, and a sidebar toggle appears. iPad-compatibility mode never exposed this,
so iPhone-only apps that never thought about iPad are hit hardest.
**Fix:** replace every `NavigationView {` with `NavigationStack {` (iOS 16+). Simple
`NavigationLink { Destination() } label: {…}` links work unchanged; `NavigationLink(isActive:)`
and `navigationViewStyle` need review. Note BSD `sed` on macOS doesn't understand `\s` — use
`perl -pi -e 's/^(\s*)NavigationView \{/$1NavigationStack {/'`.

### 2. Portrait lock is ignored *(verified)*
`supportedInterfaceOrientations` / an AppDelegate orientation lock does not keep the inner display
portrait — the user unfolded and got a landscape 890×626 window. Every screen must lay out in a
short, wide window. Code that forces landscape for one screen (`requestGeometryUpdate`) can't be
relied on either. Don't fight it; make layouts size-driven.

### 3. Controls stretched across 800+ pt
Full-width buttons, cards and form rows look broken on the inner display. Two patterns, both gated
on measured width so iPhone stays identical:
- **Single column, capped width** (~560 pt, centered) for scroll pages, onboarding, forms.
- **Two columns** when the canvas is wide *and* short (width ≥ 700 and width > height): e.g. hero
  illustration left, actions right. In a single capped column, a short landscape canvas also hides
  secondary content you'd normally show — two columns brings it back.
- For `List`/`Form`, use `contentMargins(.horizontal, …, for: .scrollContent)` rather than a frame
  so the scroll indicator and large title stay put. See `ReadableListWidth` in the patterns file.

### 4. List → detail: use `NavigationSplitView`, never two hand-stacked `NavigationStack`s *(verified)*
A master/detail layout on the inner display is a big win (tap a row, detail updates; no
push-pop-push), and it's what Apple means by "a natural extension of iPad".
But building it as `HStack { NavigationStack {list}.frame(width:); NavigationStack {detail} }`
breaks: **each embedded navigation stack gets the whole window's trailing safe-area inset** (~100 pt
on Duo, for the vertical status/tab rail on the right), so the left column loses 100 pt on its right
edge even though it's nowhere near the rail. `.ignoresSafeArea(edges: .trailing)` on it does nothing.
**Fix:** `NavigationSplitView(columnVisibility: .constant(.all))` with `.navigationSplitViewStyle(.balanced)`.
- `.navigationSplitViewColumnWidth(...)` is **ignored if it comes before
  `.toolbar(removing: .sidebarToggle)`** (sidebar falls back to ~320 pt); put it after *(verified)*.
- `.prominentDetail` makes the sidebar float over a dimmed detail — not what you want here.
- Keep the narrow-width path exactly as before (push navigation); switch on measured width ≥ ~700.
- Default-select the first row; when the selected item is deleted, reselect.
- Rebuild the detail per selection (`.id(item.id)`) so scroll/playback state doesn't leak between rows.

### 5. Top strip shows scrolled content above pinned/sticky headers *(verified)*
With 27.1's vertical toolbars there's no navigation bar across the top, so the top safe-area strip
above a pinned section header (`LazyVStack(pinnedViews: [.sectionHeaders])`) is uncovered and rows
scroll visibly through it. `ignoresSafeArea` on the pinned header has no effect (scroll content
doesn't receive safe-area insets). **Fix:** an overlay on the ScrollView *outside* the content:
a zero-height view at `.top` whose background `.ignoresSafeArea(edges: .top)`, shown only while the
header is pinned. On iPhone the strip sits under the nav bar, so it's invisible there.

### 6. Everything in Apple's checklist (usually already fine in SwiftUI apps)
`UIScreen.main` for sizing, a single size read at launch (fold/unfold resizes the window live),
`UIDevice.current.orientation` / `interfaceOrientation` for layout, `userInterfaceIdiom` checks,
treating `horizontalSizeClass == .regular` as "iPad", hard-coded device heights, `scaleAspectFill`
heroes that crop on a 1.42 aspect ratio, `UIWindow(frame: UIScreen.main.bounds)`. The audit script
flags all of these. Size thresholds based on a GeometryReader's *available* height are fine.

### 7. Things to check on real hardware later
Microphone/camera position differs from slab iPhones — if the app tells users where to point the
phone or mic, re-verify that copy once hardware is available. Background audio across fold/unfold.

## Test matrix

For each top-level screen: outer display portrait · inner portrait (626×890) · inner landscape
(890×626) · **fold/unfold mid-flow** (recording, playback, a running timer, an open sheet) ·
a normal iPhone (regression). Sheets present as centered form sheets on the inner display, which
is usually fine as-is.

## App Store

- **Screenshots** *(Apple's spec)*: outer 1398×2034 (or 2034×1398), inner 2007×2853 (or 2853×2007).
  Not required yet; **required for new submissions from April 2027**. The ~1.42–1.46 aspect ratio
  is far from regular iPhones (~2.17), so existing marketing layouts need a new template, and the
  in-app screenshots should be captured on the Duo simulator.
- iOS 27 **product page header** (21:9) and search-results creative assets are shared with other
  devices; nothing Duo-specific beyond checking them in App Store Connect's preview tool.
- Apple explicitly invites **featuring nominations** for apps optimized for Duo "across all poses
  and orientations" — worth mentioning in the next nomination.
- Third-party spec sites disagreed with Apple on inner-display pixel sizes; trust
  developer.apple.com (screenshot specifications page).

## Sources
- https://developer.apple.com/news/?id=kkphp5qo (Prepare and submit your apps for iPhone Duo)
- https://developer.apple.com/iphone-duo/prepare/ (three steps; patterns; SDK compatibility table)
- https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications
