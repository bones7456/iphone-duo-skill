#!/usr/bin/env bash
# Static audit for iPhone Duo risks in an iOS project.
#   scripts/audit_duo.sh <project-dir>
# Prints each pattern with file:line hits. A hit is a prompt to review, not proof of a bug.
set -u
ROOT="${1:-.}"
cd "$ROOT" || exit 1

# Swift + ObjC sources, skipping build output, dependencies and vendored code
FILES=$(find . \( -path ./build -o -path ./DerivedData -o -path ./Pods -o -path ./Carthage \
                 -o -path '*/.build' -o -path '*/SourcePackages' -o -path './.git' \) -prune -o \
            \( -name '*.swift' -o -name '*.m' -o -name '*.mm' \) -print)
[ -z "$FILES" ] && { echo "no Swift/ObjC sources under $ROOT"; exit 1; }

total=0
check() {   # check <severity> <title> <why> <regex>
  local sev="$1" title="$2" why="$3" re="$4"
  local hits
  hits=$(echo "$FILES" | xargs grep -nE "$re" 2>/dev/null | grep -vE '^\S+:[0-9]+:\s*//')
  if [ -n "$hits" ]; then
    local n; n=$(echo "$hits" | wc -l | tr -d ' ')
    total=$((total + n))
    printf '\n[%s] %s  (%s hit%s)\n    why: %s\n' "$sev" "$title" "$n" "$([ "$n" = 1 ] || echo s)" "$why"
    echo "$hits" | sed 's/^/    /' | head -40
  fi
}

check HIGH "NavigationView" \
  "Regular width on both Duo displays turns it into sidebar+detail: the whole screen ends up in a narrow left column. Use NavigationStack." \
  '\bNavigationView\b'
check HIGH "UIScreen.main / stored UIScreen" \
  "Size from the view/window/scene instead; fold/unfold resizes the window live." \
  'UIScreen\.main|UIScreen\.screens'
check HIGH "UIWindow(frame:)" \
  "Create windows from scenes: UIWindow(windowScene:)." \
  'UIWindow\(frame:'
check MED "Orientation-based layout" \
  "Compare actual width/height instead; orientation doesn't describe the window on Duo." \
  'UIDevice\.current\.orientation|statusBarOrientation|\binterfaceOrientation\b'
check MED "Orientation lock / forced rotation" \
  "Portrait locks were ignored on the Duo inner display; every screen must lay out in ~951x669 pt landscape." \
  'supportedInterfaceOrientations|requestGeometryUpdate|UISupportedInterfaceOrientations'
check MED "Idiom checks" \
  "Choose layout by available space, not .phone/.pad." \
  'userInterfaceIdiom|\.pad\b.*idiom|idiom.*\.pad\b'
check MED "Regular width treated as iPad" \
  "Duo reports regular width; don't map size class to device." \
  'horizontalSizeClass\s*==\s*\.regular|\.regular\s*==\s*horizontalSizeClass'
check MED "Hard-coded device sizes" \
  "Device lists / exact heights won't match Duo (~669x951 inner, 466x678 outer pt)." \
  '(bounds|frame|size)\.(height|width)\s*==\s*[0-9]{3}|iPhone ?1[0-9] ?Pro|deviceModel|utsname'
check MED "NavigationSplitView" \
  "Its sidebar renders Color.primary fills with vibrancy (custom-drawn cells turn gray); for a sidebar with custom drawing prefer one NavigationStack with an HStack of two columns. See pitfall 5." \
  'NavigationSplitView'
check MED "Height-relative sizing" \
  "Sizing content from a scroll container's height moves with the collapsing large title / keyboard and looped the layout (main thread at 100%). Size from width; equalize columns with fixedSize. See pitfall 1." \
  'containerRelativeFrame\(\.vertical|containerRelativeFrame\(\[\.horizontal, \.vertical\]|containerRelativeFrame\(\[\.vertical'
check LOW "onGeometryChange / GeometryReader driving layout" \
  "Fine if it measures a host whose size doesn't depend on the branch it selects; a loop if it measures the content it switches. Check each. See pitfall 1." \
  'onGeometryChange\(for:'
check LOW "Aspect-fill media" \
  "Can crop heavily on the ~1.42 aspect inner display; consider fit or a focal point." \
  'scaleAspectFill|contentMode:\s*\.fill|scaledToFill'
check LOW "Pinned section headers" \
  "On 27.1 the top strip above a pinned header is uncovered (no top nav bar); see pitfall 5." \
  'pinnedViews:'
check LOW "Single size read at launch" \
  "Size-dependent layout must re-run on resize (layoutSubviews / viewWillTransition / GeometryReader)." \
  'viewDidLoad\(\)[^}]*bounds|didFinishLaunching[^}]*bounds'

echo
if [ "$total" -eq 0 ]; then
  echo "No risky patterns found. Still run the simulator matrix: layout stretch and safe-area gaps only show visually."
else
  echo "$total hit(s). Review HIGH first. Then check visually on the Duo simulator (inner display, both orientations)."
fi
