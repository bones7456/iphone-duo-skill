# SwiftUI patterns for iPhone Duo (tested)

All patterns switch on **measured width**, so a regular iPhone keeps its exact previous layout.
Adjust the constants (700 pt threshold, 560 pt column) to the app's design.

## Contents
1. Readable single column for scroll pages
2. Two columns on a wide + short canvas
3. Readable List / Form
4. List → detail with NavigationSplitView
5. Covering the top strip above a pinned header

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

Unfolded-landscape inner display is ~890×626 pt. A single column there means giant buttons and a
short canvas that hides secondary content; split it.

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

## 4. List → detail with NavigationSplitView

Do **not** hand-build this from an HStack of two NavigationStacks: each stack receives the whole
window's trailing safe-area inset (~100 pt for Duo's right-side rail), so the left column shows a
100 pt empty band on its right.

```swift
struct HistoryView: View {
    @State private var selected: Item?

    var body: some View {
        GeometryReader { geo in
            if geo.size.width >= 700 {
                NavigationSplitView(columnVisibility: .constant(.all)) {
                    ItemList(selection: $selected)                 // rows set `selected` instead of pushing
                        .toolbar(removing: .sidebarToggle)
                        .navigationSplitViewColumnWidth(360)        // MUST come after .toolbar(removing:)
                } detail: {
                    NavigationStack {
                        if let selected {
                            ItemDetail(item: selected).id(selected.id)   // fresh state per row
                        } else {
                            EmptyStateView()
                        }
                    }
                }
                .navigationSplitViewStyle(.balanced)               // not .prominentDetail (overlays + dims)
            } else {
                NavigationStack { ItemList(selection: nil) }       // original push navigation, unchanged
            }
        }
    }
}
```
In the list: `selection == nil` → `NavigationLink` as before; non-nil → `Button { selection = item }`
with a selected-row highlight. On appear and when the data changes, select the first row if
nothing (or a deleted item) is selected. Paywalled/locked rows keep their existing behavior.
Extra row decorations for the wide layout (e.g., a score badge) should be opt-in flags so the
narrow row renders exactly as before; overlay them in a corner rather than adding a trailing
column, or they squeeze the row's text.

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
