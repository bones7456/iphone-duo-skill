# SwiftUI patterns for iPhone Duo (tested)

All patterns switch on **measured width**, so a regular iPhone keeps its exact previous layout.
Adjust the constants (700 pt threshold, 560 pt column) to the app's design.

## Contents
1. Readable single column for scroll pages
2. Two columns on a wide + short canvas
3. Readable List / Form
4. List → detail: one NavigationStack, two columns
5. Covering the top strip above a pinned header
6. Wide layout inside a ScrollView without feedback loops (host-measured width, equal-height columns)

---

## 1. Readable single column for scroll pages

A container that fills the screen when content is short, scrolls when tall, passes the available
size down, and optionally caps the content width (centered).

```swift
struct FittingScrollView<Content: View>: View {
    var maxContentWidth: CGFloat? = nil
    @ViewBuilder var content: (CGSize) -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content(proxy.size)
                    .frame(maxWidth: maxContentWidth ?? .infinity)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

// usage
FittingScrollView(maxContentWidth: 560) { _ in … }
```

## 2. Two columns on a wide + short canvas

Unfolded-landscape inner display is ~951×669 pt (27.1 SDK, edge-to-edge; ~820–850 pt usable beside
the right rail). A single column there means giant buttons and a short canvas that hides secondary
content; split it.

Here the GeometryReader wraps the ScrollView (it measures the *host*), so switching branches can't
change the measured size. Don't move the measurement onto the content you switch — see section 6.

```swift
FittingScrollView { size in
    if size.width >= 700 && size.width > size.height {
        HStack(alignment: .center, spacing: 56) {
            hero(availableHeight: size.height).frame(maxWidth: .infinity)
            actions(showSecondary: size.height >= 480).frame(maxWidth: 460)
        }
        .padding(.horizontal, 32)
    } else {
        VStack(spacing: 0) { /* original single-column layout, unchanged */ }
            .padding(.horizontal)
            .frame(maxWidth: 560)
    }
}
```
Refactor the original body into `hero(...)` and `actions(...)` subviews first so both branches
share them; keep the single-column branch byte-for-byte equivalent to the old layout.

## 3. Readable List / Form

```swift
/// Wide canvas: center List/Form in a ~560 pt column. Narrow: no modification at all.
/// contentMargins keeps the scroll indicator at the edge and the large title in place.
struct ReadableListWidth: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        Group {
            if width >= 700 {
                content.contentMargins(.horizontal, (width - 560) / 2, for: .scrollContent)
            } else {
                content
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
extension View { func readableListWidth() -> some View { modifier(ReadableListWidth()) } }

Form { … }
    .readableListWidth()          // before .scrollContentBackground / .background
```

## 4. List → detail: one NavigationStack, two columns

Tested alternatives and why they lost:
- `HStack` of two `NavigationStack`s: each embedded stack gets the window's whole trailing
  safe-area inset (~100 pt for Duo's right-side rail) → a 100 pt empty band on the left column.
- `NavigationSplitView`: the sidebar renders semantic-color fills (`Color.primary`) with vibrancy,
  so custom drawing (calendar cells, badges) turns gray; `.listStyle(.insetGrouped)` doesn't help.
  Fine for a plain text sidebar — notes for that case are at the end of this section.

```swift
struct HistoryView: View {
    @State private var width: CGFloat = 0
    @State private var selected: Item.ID?
    @State private var path: [Item.ID] = []
    private var isWide: Bool { width >= 700 }

    var body: some View {
        Group {
            if isWide {
                NavigationStack {                       // ONE stack → one trailing inset, for the whole HStack
                    HStack(spacing: 0) {
                        ItemList(onOpen: { selected = $0 }, selection: selected)
                            // beside a divider the list gets no trailing inset of its own
                            .contentMargins(.trailing, 16, for: .scrollContent)
                            .frame(width: 380)
                        Rectangle().fill(.separator).frame(width: 1).ignoresSafeArea(edges: .bottom)
                        Group {
                            if let selected {
                                ItemDetail(id: selected, embedded: true)   // embedded: sets no navigationTitle
                                    .id(selected)                          // fresh state per row
                            } else {
                                ContentUnavailableView("Pick an item", systemImage: "list.bullet")
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onAppear { if selected == nil { selected = items.first?.id } }
            } else {
                NavigationStack(path: $path) {          // original push navigation, unchanged
                    ItemList(onOpen: { path.append($0) }, selection: nil)
                        .navigationDestination(for: Item.ID.self) { ItemDetail(id: $0) }
                }
            }
        }
        // Measures the tab's root container, whose size doesn't depend on which branch is shown.
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
```
In the list: `selection == nil` → `NavigationLink` as before; non-nil → `Button { onOpen(item.id) }`
with `.buttonStyle(.plain)` and a selected-row `listRowBackground`. Paywalled/locked rows keep their
existing behavior. Extra decorations for the wide layout should be opt-in flags so the narrow row
renders exactly as before.

If you do use `NavigationSplitView` (plain sidebar): `columnVisibility: .constant(.all)`,
`.navigationSplitViewStyle(.balanced)` (not `.prominentDetail`, which floats + dims), and put
`.navigationSplitViewColumnWidth(...)` **after** `.toolbar(removing: .sidebarToggle)` or it's ignored.

## 5. Covering the top strip above a pinned header

```swift
ScrollView {
    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) { … }
}
.overlay(alignment: .top) {
    if isHeaderPinned {                                   // track via an anchor's onAppear/onDisappear
        Color.clear.frame(height: 0)
            .background(HeaderBackground.ignoresSafeArea(edges: .top))
    }
}
```
Putting `.ignoresSafeArea` on the pinned header itself does nothing — content inside a ScrollView
doesn't get safe-area insets. The overlay sits outside the scroll content, so it can extend into
the top safe area. On iPhone that strip is under the navigation bar and stays invisible.

## 6. Wide layout inside a ScrollView without feedback loops

Both of these hung the main thread at 100 % CPU (spinner still spinning, so it looked like a slow
network): (a) `onGeometryChange` on the content you switch, driving `if width >= 760 {HStack} else
{VStack}`; (b) sizing a card from the ScrollView's height (`containerRelativeFrame(.vertical)` or a
measured height) — that height moves with the collapsing large title and the keyboard.

Measure the **host ScrollView's width only** and hand it down:

```swift
struct HostWidthKey: EnvironmentKey { static let defaultValue: CGFloat = 0 }
extension EnvironmentValues {
    var hostWidth: CGFloat {
        get { self[HostWidthKey.self] }
        set { self[HostWidthKey.self] = newValue }
    }
}

private struct MeasuresHostWidth: ViewModifier {
    @State private var width: CGFloat = 0
    func body(content: Content) -> some View {
        content
            .environment(\.hostWidth, width)
            // Width only: it doesn't change with scrolling, title collapse or the keyboard.
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}
extension View { func measuresHostWidth() -> some View { modifier(MeasuresHostWidth()) } }

// Host:
ScrollView {
    SolveView(puzzle: puzzle).padding(16)
}
.measuresHostWidth()          // on the ScrollView, never on SolveView

// Content:
struct SolveView: View {
    @Environment(\.hostWidth) private var hostWidth
    private var contentWidth: CGFloat { hostWidth - 32 }      // minus the host's padding
    private var isWide: Bool { contentWidth >= 760 }
    private var leftWidth: CGFloat { min(440, contentWidth * 0.45) }

    var body: some View {
        if isWide {
            HStack(alignment: .top, spacing: 24) {
                PuzzleCard(stackedImageSide: min(210, leftWidth - 48 - 24 - 120))  // sized from width
                    .frame(width: leftWidth)
                VStack(spacing: 24) { stage }                       // editor / result
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // HStack takes its tallest child; the right column stretches to at least the left
            // card's height, a longer result just runs on. No measured heights anywhere.
            .fixedSize(horizontal: false, vertical: true)
        } else {
            VStack(spacing: 24) { PuzzleCard(stackedImageSide: nil); stage }   // unchanged iPhone layout
                .frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
    }
}
```
**Sticky left column.** When the right column is much longer (a result), the left card scrolls away
and leaves the left half empty. Pin it with a render-time offset — `visualEffect` doesn't take part
in layout, so reading geometry there can't loop. The row height it clamps to is measured into
state that only the effect reads:

```swift
@State private var rowHeight: CGFloat = 0

HStack(alignment: .top, spacing: 24) {
    PuzzleCard(...)
        .frame(width: leftWidth)
        .visualEffect { [rowHeight] content, proxy in
            let frame = proxy.frame(in: .scrollView)
            let lift = max(0, 16 - frame.minY)                 // keep 16 pt from the viewport top
            return content.offset(y: min(lift, max(0, rowHeight - frame.height)))
        }
    VStack(spacing: 24) { stage }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
}
.fixedSize(horizontal: false, vertical: true)
.onGeometryChange(for: CGFloat.self) { $0.size.height } action: { rowHeight = $0 }   // rendering only
```

Inside the right column, let one flexible element absorb the extra height in the wide layout only:
`TextEditor(...).frame(minHeight: 150, maxHeight: isWide ? .infinity : nil)` and the editor card
`.frame(maxHeight: isWide ? .infinity : nil, alignment: .top)` before its background.

Verify: unfold, run the real flow to the longest state, scroll it, then
`ps -o %cpu -p $(pgrep -f '<App>.app/<App>$')` should read ~0 when idle.

