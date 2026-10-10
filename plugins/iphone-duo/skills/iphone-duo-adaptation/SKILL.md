---
name: iphone-duo-adaptation
description: Adapt an existing iOS app (SwiftUI or UIKit) to iPhone Duo, Apple's foldable iPhone (outer 466×678 pt, inner ~669×951 pt edge-to-edge, both report regular width). Covers environment setup (Xcode 27.1, iOS 27.1 runtime, DeviceHub), a static audit of risky patterns, the layout bugs that actually show up on the inner display (NavigationView turning into a split view, orientation locks ignored, safe-area gaps, over-stretched controls, wide-layout feedback loops that hang the main thread, NavigationSplitView sidebars washing out colors) with tested fixes, how to design layouts that actually look good on the wide canvas, an agent-friendly simulator test loop (signed builds, launch arguments, screenshots and video of the right display, hang diagnosis), and App Store work (Duo screenshot sizes, April 2027 deadline, featuring nomination). Use this whenever the user mentions iPhone Duo, 折叠屏 / foldable iPhone, 内屏 / 外屏, DeviceHub, Xcode 27.1, "get my app ready for iPhone Duo", Duo screenshots, or asks why their app looks wrong (narrow column, black half, giant stretched buttons, frozen spinner after unfolding) on a large or wide iPhone canvas — even if they don't say "adaptation".
---

# iPhone Duo adaptation

A field guide distilled from adapting real shipping SwiftUI apps to iPhone Duo.
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
already live for Duo owners. And once the developer's Mac has Xcode 27.1, the *next* release gets
the edge-to-edge behaviour whether or not anyone touched the layout. Tell the user this early: it
changes how urgent the work is.

## Workflow

1. **Environment** — see "Setup". Needs Xcode 27.1 (macOS Tahoe 26.6+ on Apple silicon), the
   iOS 27.1 simulator runtime, and DeviceHub (the renamed Simulator app).
2. **Static audit** — run `scripts/audit_duo.sh <project-dir>`. Review each hit; most need a
   judgment call, not a blind rewrite. "No hits" does **not** mean the app looks fine — stretch,
   empty halves and ugliness only show visually.
3. **Make the app drivable without taps** before the first screenshot — see "Testing as an agent".
   A DEBUG launch argument that opens each top-level tab/screen saves many round trips.
4. **Look at every top-level screen** on the outer display, then ask the user to unfold (and later
   rotate) in DeviceHub. `scripts/duo_sim.sh shot` captures the right display.
5. **Fix and design** — work through "Pitfalls" in order of severity, then "Designing for the wide
   canvas". Templates are in `references/swiftui-patterns.md`.
6. **Run a real end-to-end flow on the unfolded device** (submit, result, animation, scroll the
   result) — static screenshots miss the worst bug class (pitfall 1). Check CPU after each.
7. **Regression-check the narrow layout** after every change (outer display or a normal iPhone).
   The bar is: nothing changes there. Gate every wide layout on *measured width*, not device type.
8. **App Store** — screenshots, nomination; see the last section.

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
- **Display IDs** *(verified)*: the default screenshot display (and `--display=1`/`primary`) is the
  outer display (1398×2034 / 2034×1398 px); the inner display was `--display=3`
  (2007×2853 / 2853×2007 px). **The outer display renders black while unfolded** — if the user
  sends you a 2034×1398 (or 1398×2034) all-black screenshot, they captured the outer display; take
  the inner one yourself with `scripts/duo_sim.sh shot`.
- **Window size**: with the 27.1 SDK the inner window was edge-to-edge, 951×669 pt landscape /
  669×951 portrait (2853×2007 px @3x) *(verified)*; the vertical tab/status rail on the right takes
  ~100 pt, leaving ~820–850 pt of content width in landscape. An earlier build observed 890×626.
  Never hard-code either — measure.
- **Build signed for the simulator** *(verified)*: `CODE_SIGNING_ALLOWED=NO` builds carry **no
  entitlements**, so Sign in with Apple fails silently (`ASAuthorizationError` 1000 in the log),
  and so does anything else entitlement-gated (iCloud, push, keychain groups…). Use
  `scripts/duo_sim.sh build <proj-or-workspace> <scheme>` (signed, `-allowProvisioningUpdates`,
  destination = the Duo's UDID). `codesign -d --entitlements` shows nothing for simulator builds;
  check with `strings <App>.app/<binary> | grep <entitlement-key>` instead.
- **A local backend may fail Sign in with Apple** (here `wrangler dev` couldn't fetch Apple's JWKS:
  "Expected 200 OK from the JSON Web Key Set") while Apple's sheet itself succeeds. To test signed-in
  flows locally, insert a test user + session row into the local DB and write the token into the
  app's stored defaults (`xcrun simctl spawn booted defaults write <bundle> <tokenKey> <token>`).
  A DEBUG-only launch argument for the API base URL lets the simulator talk to the local backend.
- **App Attest is unavailable in the simulator.** Flows that require an attestation (anonymous
  API calls, etc.) can't be exercised there; test them signed in, or ask the user before enabling
  any server-side bypass.

## Pitfalls, most severe first

### 1. Wide-layout feedback loops hang the main thread *(verified, severe)*
Symptom: after unfolding, or right after a result loads, the app freezes — **a spinner keeps
spinning** (it animates on the render server), so it looks like a slow network. Server logs show
the request succeeded. `ps` shows the app at ~100 % CPU; `sample <pid>` shows the same `body`
getters and an `onGeometryChange` / `@State` setter over and over.

What happened, inside a ScrollView (two hangs, same screen):
- Hang 1: the content measured **its own** width (`onGeometryChange` on the view → `@State width`
  → `if width >= 760 { HStack } else { VStack }`) **and** sized its left card with
  `containerRelativeFrame(.vertical)`. Moving the width measurement to the host ScrollView did
  **not** fix it —
- Hang 2: the card height still came from the host's measured **height**. That height moves with
  the **collapsing large title**, the keyboard and safe-area changes; a long result scrolls, the
  title collapses, the card resizes, the content scrolls… Removing every height dependency fixed it.

So the confirmed cause is **content height derived from a viewport height**. Measuring the content
you switch is the same feedback shape and is only safe while every branch fills the proposed width
(a `List`/`Form`/full-width stack) — measuring the host removes the question entirely.

**Rules:**
- Measure the **host** (the ScrollView / container), never the content you switch, and pass the
  value down through the environment (`measuresHostWidth()` in the patterns file).
- Measure **width only**. Width doesn't change with scrolling, title collapse or the keyboard.
- **Round it and ignore changes under 1 pt** *(verified, third hang)*: with a voice-result card on
  screen, the host's width crept 867.0 → 867.67 in sub-pixel steps under an animation; every tiny
  change re-rendered the page, which restarted the creep — 100 % CPU even though only width was
  measured. `$0.size.width.rounded()` plus `if abs(new - old) >= 1` breaks it whatever the source.
- Don't add measured state just for polish. A sticky column clamped to a measured row height was a
  second state to oscillate; the unclamped render-time offset (pattern 6) is enough when the row is
  last on the page and the card is shorter than the viewport.
- No custom wrapping `Layout` inside a `fixedSize` two-column row — a hand-rolled flow layout was
  the first suspect here; a horizontal `ScrollView { HStack }` is predictable.
- Never derive a content height from a measured viewport height. For side-by-side columns of equal
  height use `HStack { a; b.frame(maxHeight: .infinity) }.fixedSize(horizontal: false, vertical: true)`.
  Size images from width (`min(maxSide, columnWidth - padding - labelWidth)`), not from height.
- After any wide-layout change, run the real flow on the unfolded device, **scroll the longest
  screen**, and check `ps -o %cpu -p <pid>` stays ~0 when idle. `scripts/duo_sim.sh hang <bundle-id>`
  does the CPU check and summarises a `sample`.
- **Find the looping state, don't bisect views**: add `let _ = Self._printChanges()` at the top of the
  suspect view's `body`, launch with `xcrun simctl launch --console-pty booted <bundle>` and count
  the lines — "`_canvas changed` × 5487" names the culprit in one run. Then print the measured
  value itself to see *how* it oscillates. Removing cards one by one took four rebuilds and was wrong
  every time.

### 2. `NavigationView` becomes a split view — whole app squeezed into a sidebar *(verified, severe)*
Both Duo displays report **regular horizontal size class**. A SwiftUI `NavigationView` (default
style) then turns into sidebar + detail: the entire screen renders in a ~1/3-width column on the
left, the rest is black, and a sidebar toggle appears. iPad-compatibility mode never exposed this,
so iPhone-only apps that never thought about iPad are hit hardest.
**Fix:** replace every `NavigationView {` with `NavigationStack {` (iOS 16+). Simple
`NavigationLink { Destination() } label: {…}` links work unchanged; `NavigationLink(isActive:)`
and `navigationViewStyle` need review. Note BSD `sed` on macOS doesn't understand `\s` — use
`perl -pi -e 's/^(\s*)NavigationView \{/$1NavigationStack {/'`.

### 3. Portrait lock is ignored *(verified)*
`supportedInterfaceOrientations` / an AppDelegate orientation lock does not keep the inner display
portrait — unfolding gives a landscape window. Every screen must lay out in a short, wide window.
Code that forces landscape for one screen (`requestGeometryUpdate`) can't be relied on either.
Don't fight it; make layouts size-driven. Short-and-wide also breaks fixed vertical stacks
(onboarding pages with a 240 pt hero + text + bottom bar overflow 669 pt) — go side by side there.

### 4. Controls stretched across 800+ pt
Full-width buttons, cards and form rows look broken on the inner display. Capping the width
(~560 pt, centered) is the **minimum**, not the goal — see "Designing for the wide canvas".
- Scroll pages: cap the content column (`readableColumn()`).
- `List`/`Form`: use `contentMargins(.horizontal, …, for: .scrollContent)` rather than a frame,
  so the scroll indicator and large title stay put (`ReadableListWidth` in the patterns file).
- Gate on measured width; every iPhone is narrower than the cap, so the cap is a no-op there.

### 5. List → detail: `NavigationSplitView` has traps — prefer one stack with two columns *(verified)*
A master/detail layout on the inner display is a big win (tap a row, detail updates in place).
- **Never two hand-stacked `NavigationStack`s** in an `HStack`: each embedded stack gets the whole
  window's trailing safe-area inset (~100 pt for the right-side rail), so the left column loses
  100 pt on its right edge. `.ignoresSafeArea(edges: .trailing)` on it does nothing.
- **`NavigationSplitView`'s sidebar renders with vibrancy**: custom fills in semantic colors
  (`Color.primary`, `.primary.opacity(…)`) come out washed-out gray, and row backgrounds change.
  `.listStyle(.insetGrouped)` on the sidebar list does **not** fix it. If the sidebar is a plain
  text list that's fine; if it has custom drawing (a calendar grid, badges, charts) it breaks.
  If you do use it: `columnVisibility: .constant(.all)`, `.navigationSplitViewStyle(.balanced)`
  (`.prominentDetail` floats the sidebar over a dimmed detail), and put
  `.navigationSplitViewColumnWidth(...)` **after** `.toolbar(removing: .sidebarToggle)` or it is
  ignored (sidebar falls back to ~320 pt).
- **What worked best:** a single `NavigationStack { HStack(spacing: 0) { list.frame(width: 380);
  divider; detail } }`. One stack → one trailing inset, applied to the whole HStack, which is
  correct. The list beside a divider gets no trailing inset of its own — add
  `.contentMargins(.trailing, 16, for: .scrollContent)`. The embedded detail view must not set its
  own `navigationTitle` (it would replace the list's); give it an `embedded` flag.
- Keep the narrow path exactly as before (push navigation). Default-select a sensible row (most
  recent item); reselect when the selection disappears; rebuild the detail per selection with
  `.id(selection)` so scroll/editor state doesn't leak between rows. Mark the selection in the
  list (and in a calendar, if there is one).

### 6. Top strip shows scrolled content above pinned/sticky headers *(verified)*
With 27.1's vertical toolbars there's no navigation bar across the top, so the top safe-area strip
above a pinned section header (`LazyVStack(pinnedViews: [.sectionHeaders])`) is uncovered and rows
scroll visibly through it. `ignoresSafeArea` on the pinned header has no effect (scroll content
doesn't receive safe-area insets). **Fix:** an overlay on the ScrollView *outside* the content:
a zero-height view at `.top` whose background `.ignoresSafeArea(edges: .top)`, shown only while the
header is pinned. On iPhone the strip sits under the nav bar, so it's invisible there.

### 7. Everything in Apple's checklist (usually already fine in SwiftUI apps)
`UIScreen.main` for sizing, a single size read at launch (fold/unfold resizes the window live),
`UIDevice.current.orientation` / `interfaceOrientation` for layout, `userInterfaceIdiom` checks,
treating `horizontalSizeClass == .regular` as "iPad", hard-coded device heights, `scaleAspectFill`
heroes that crop on a 1.42 aspect ratio, `UIWindow(frame: UIScreen.main.bounds)`. The audit script
flags all of these.

### 8. Things to check on real hardware later
Microphone/camera position differs from slab iPhones — if the app tells users where to point the
phone or mic, re-verify that copy once hardware is available. Background audio across fold/unfold.

## Designing for the wide canvas

Users judge the unfolded layout on looks, not on "nothing is broken". A phone column centered on a
951 pt landscape canvas with empty halves was rejected as "not pretty" *(verified, user feedback)*.
For each **primary** screen, design a deliberate wide layout:

- **Split by role, not by squeezing**: the thing being looked at on the left (puzzle / photo /
  calendar / identity), the thing being done on the right (editor / result / detail / settings).
- **Balance the columns.** A short card next to a tall one leaves a dead corner. Make the
  columns equal height (`fixedSize` pattern, pitfall 1) and let a flexible element absorb the slack
  (a `TextEditor` with `maxHeight: .infinity`, the submit button pinned at the card's bottom).
- **Keep the left column in view.** With the result running on in the right column, the left
  card scrolled away and left the whole left half empty *(verified, user feedback)*. Make it
  sticky with a **render-time** offset (`visualEffect` reading `proxy.frame(in: .scrollView)`,
  clamped to the row height) — not layout, so it can't feed back (pattern 6).
- **Re-compose, don't just widen.** A 2-up image row that worked at 400 pt became tiny in a 380 pt
  side column; restacking it as rows (image beside the word, "vs" divider between) filled the
  column and made the images larger. Give the new arrangement its own opt-in parameter so the
  narrow rendering stays byte-for-byte identical.
- **Use the space for content the narrow layout hides**: stats, a selected-day detail, the
  account panel next to settings.
- Thresholds that worked: two columns at content width ≥ 760 (landscape inner only), list+detail
  at ≥ 700; inner portrait (~669 pt) stays single-column, capped at 560.
- Iterate with screenshots of each state (empty / editing / loading / result / signed-in) and show
  the user — expect at least one round of "still not pretty".

## Testing as an agent

- **You usually can't tap or type in the simulator.** Add DEBUG-only launch arguments read through
  `UserDefaults` (e.g. `-debugTab history`; `simctl launch <udid> <bundle> -debugTab history`), and
  flip stored flags with `xcrun simctl spawn booted defaults write <bundle> <key> -bool YES`
  (e.g. to show/skip onboarding). Leave typing, submitting and posture changes to the user with a
  short, concrete checklist.
- **Don't fabricate app data to reach a screen** (seeding fake results, mocking responses) unless
  the user agrees — they may want the real flow and its real animation. Ask first; offer a real
  path (sign in, use a test account, raise the account's quota) instead.
- **Animations**: record the right display while the user performs the flow —
  `scripts/duo_sim.sh record <file.mov>` (run in background; stop with `scripts/duo_sim.sh stop`),
  then `scripts/duo_sim.sh sheet <file.mov> <start-sec> [fps]` makes a contact sheet to find the
  moment, and a single full-size frame (`ffmpeg -ss … -frames:v 1`) to inspect it. Recordings may
  stop shortly after the last screen change, so the tail of an animation can be missing.
- **After every real flow**, check the app is idle (`scripts/duo_sim.sh hang <bundle-id>`).
- A whole-screen overlay above the `TabView` (confetti, toasts) covered the inner display and the
  vertical rail correctly *(verified)* — still check it once.

## Test matrix

For each top-level screen: outer display portrait · inner portrait · inner landscape ·
**every state** (empty, editing, loading, result, signed in/out) · **scroll the longest state** ·
**fold/unfold mid-flow** (recording, playback, a running timer, an open sheet, a half-written
answer) · a normal iPhone or the outer display (regression). Sheets present as centered form
sheets on the inner display, which is usually fine as-is.

## App Store

- **Screenshots** *(Apple's spec)*: outer 1398×2034 (or 2034×1398), inner 2007×2853 (or 2853×2007).
  Not required yet; **required for new submissions from April 2027**.
  - **API display type `APP_IPHONE_DUO`** — not in Apple's OpenAPI enum yet, but accepted. One set
    holds both displays. Uploading 5 inner-landscape 2853×2007 shots through the API (reserve
    `POST /v1/appScreenshots` → PUT each `uploadOperations` chunk → `PATCH uploaded:true` + md5)
    reached `assetDeliveryState: COMPLETE` and passed submission *(verified, Oct 2026)*.
  - A new App Store version **inherits the previous version's screenshot sets**; add only the Duo set.
  - Capture the right display (`--display=3` while unfolded), signed build, signed in if the
    screens need account data; long screens need the user to scroll — the sticky-column fix
    above was found exactly while capturing, so capture *before* the final build if you can. The ~1.42–1.46 aspect ratio
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
