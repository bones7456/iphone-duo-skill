#!/usr/bin/env bash
# iPhone Duo simulator helper.
#   scripts/duo_sim.sh ensure                      # create (if missing) + boot "iPhone Duo", print UDID
#   scripts/duo_sim.sh install <path/to/App.app>   # install into the booted Duo
#   scripts/duo_sim.sh launch <bundle-id> [args…]  # (re)launch the app with launch arguments
#   scripts/duo_sim.sh shot <out-prefix>           # screenshot both displays -> <prefix>_outer.png / _inner.png
#
# Notes (verified on Xcode 27.1 RC):
#   - Duo requires the iOS 27.1+ runtime; on 27.0 simctl says "Incompatible device".
#   - The viewer app is DeviceHub (Xcode.app/Contents/Applications/DeviceHub.app), not Simulator.app.
#   - Fold/unfold and rotation can only be changed in DeviceHub's UI; there is no simctl command.
#   - Default screenshot = outer display. The inner display had a different display ID (3 here);
#     this script probes IDs and classifies by pixel size. While unfolded the outer display is black.
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
  *) sed -n '2,13p' "$0"; exit 1 ;;
esac
