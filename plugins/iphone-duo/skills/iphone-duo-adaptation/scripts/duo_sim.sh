#!/usr/bin/env bash
# iPhone Duo simulator helper.
#   scripts/duo_sim.sh ensure                      # create (if missing) + boot "iPhone Duo", print UDID
#   scripts/duo_sim.sh build <x.xcodeproj|x.xcworkspace> <scheme> [derived-data-dir]
#                                                  # SIGNED simulator build for the Duo, prints the .app path
#   scripts/duo_sim.sh install <path/to/App.app>   # install into the booted Duo
#   scripts/duo_sim.sh launch <bundle-id> [args…]  # (re)launch the app with launch arguments
#   scripts/duo_sim.sh shot <out-prefix>           # screenshot both displays -> <prefix>_outer.png / _inner.png
#   scripts/duo_sim.sh record <file.mov> [display] # record a display (default 3 = inner); run in background
#   scripts/duo_sim.sh stop                        # stop a running `record` cleanly (SIGINT)
#   scripts/duo_sim.sh sheet <file.mov> <start-sec> [fps] [out.png]  # contact sheet to find a moment
#   scripts/duo_sim.sh hang <bundle-id>            # CPU of the running app; if busy, top app frames of a sample
#
# Notes (verified on Xcode 27.1 RC):
#   - Duo requires the iOS 27.1+ runtime; on 27.0 simctl says "Incompatible device".
#   - The viewer app is DeviceHub (Xcode.app/Contents/Applications/DeviceHub.app), not Simulator.app.
#   - Fold/unfold and rotation can only be changed in DeviceHub's UI; there is no simctl command.
#   - Default screenshot = outer display. The inner display had a different display ID (3 here);
#     this script probes IDs and classifies by pixel size. While unfolded the outer display is black.
#   - Builds must be signed: CODE_SIGNING_ALLOWED=NO strips entitlements (Sign in with Apple then
#     fails with ASAuthorizationError 1000). `build` signs ad hoc for the simulator.
#   - A hung app (wide-layout feedback loop) still shows a spinning ProgressView; `hang` tells you.
set -euo pipefail
NAME="iPhone Duo"
TYPE="com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"

udid() { xcrun simctl list devices | grep -E "^\s+$NAME \(" | grep -v unavailable | head -1 | grep -oE '[0-9A-F-]{36}' || true; }

case "${1:-}" in
  ensure)
    id=$(udid)
    if [ -z "$id" ]; then
      rt=$(xcrun simctl list runtimes | grep -oE 'com\.apple\.CoreSimulator\.SimRuntime\.iOS-2[7-9]-[1-9][0-9]*' | sort -V | tail -1)
      [ -z "$rt" ] && { echo "No iOS 27.1+ runtime. Run: xcodebuild -downloadPlatform iOS" >&2; exit 1; }
      id=$(xcrun simctl create "$NAME" "$TYPE" "$rt")
    fi
    xcrun simctl boot "$id" 2>/dev/null || true
    xcrun simctl bootstatus "$id" -b >/dev/null
    open -a "$(xcode-select -p)/../Applications/DeviceHub.app" 2>/dev/null || true
    echo "$id" ;;
  build)
    proj="$2"; scheme="$3"; dd="${4:-${TMPDIR:-/tmp}/duo-dd}"
    case "$proj" in *.xcworkspace) flag=-workspace ;; *) flag=-project ;; esac
    xcodebuild "$flag" "$proj" -scheme "$scheme" -destination "id=$(udid)" \
      -derivedDataPath "$dd" -allowProvisioningUpdates build 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" >&2
    find "$dd/Build/Products" -maxdepth 2 -name '*.app' -path '*iphonesimulator*' | head -1 ;;
  install)
    xcrun simctl install "$(udid)" "$2" ;;
  launch)
    id=$(udid); bid="$2"; shift 2
    xcrun simctl terminate "$id" "$bid" 2>/dev/null || true
    xcrun simctl launch "$id" "$bid" "$@" ;;
  shot)
    id=$(udid); prefix="$2"; found=0
    # Probing a display ID that does not exist can block ~1 min: stop once both are found, try 1-4 only
    for d in 1 2 3 4; do
      [ "$found" -ge 2 ] && break
      f=$(mktemp -t duo).png
      xcrun simctl io "$id" screenshot --display="$d" "$f" >/dev/null 2>&1 || continue
      dims=$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/{print $2}' | sort -n | tr '\n' 'x')
      case "$dims" in
        1398x2034x) mv "$f" "${prefix}_outer.png"; found=$((found+1)); echo "outer  display=$d -> ${prefix}_outer.png" ;;
        2007x2853x) mv "$f" "${prefix}_inner.png"; found=$((found+1)); echo "inner  display=$d -> ${prefix}_inner.png" ;;
        *) rm -f "$f" ;;
      esac
    done ;;
  record)
    xcrun simctl io "$(udid)" recordVideo --display="${3:-3}" --codec=h264 --force "$2" ;;
  stop)
    pkill -INT -f "simctl io .* recordVideo" && sleep 3 && echo "stopped" || echo "no recording running" ;;
  sheet)
    out="${5:-${2%.*}_sheet.png}"
    ffmpeg -v error -y -ss "$3" -i "$2" -vf "fps=${4:-1},scale=380:-1,tile=8x8" -frames:v 1 "$out" && echo "$out" ;;
  hang)
    pid=$(pgrep -f "/$(xcrun simctl listapps "$(udid)" 2>/dev/null | grep -A12 "\"$2\"" | sed -n 's/.*CFBundleExecutable = \(.*\);/\1/p' | head -1 | tr -d '"')\$" | head -1)
    [ -z "$pid" ] && { echo "app $2 not running"; exit 1; }
    cpu=$(ps -o %cpu= -p "$pid" | tr -d ' ')
    echo "pid $pid  cpu ${cpu}%"
    if [ "${cpu%.*}" -ge 50 ]; then
      f=$(mktemp -t duohang).txt
      sample "$pid" 2 -file "$f" >/dev/null 2>&1
      echo "busy — most frequent app frames (a body getter + a @State/onGeometryChange setter = layout feedback loop):"
      grep -E "\.debug\.dylib|in $(basename "$(ps -o comm= -p "$pid")")" "$f" | sed -E 's/^[ +!:|]*[0-9]+ //; s/\[0x[0-9a-f]+\]//' \
        | sort | uniq -c | sort -rn | head -15
    fi ;;
  *) sed -n '2,17p' "$0"; exit 1 ;;
esac
