#!/usr/bin/env bash
# Build the iOS app for the Simulator, install it and launch it.
#   tools/run_ios_sim.sh                       build + run
#   tools/run_ios_sim.sh 'wheresme://play?c=WM1-…'   build + run, then open that deep link
#   SKIP_BUILD=1 tools/run_ios_sim.sh '<link>'      reuse the last build (just reinstall + open)
#   SIM="iPhone 16 Pro" tools/run_ios_sim.sh       pick the device (default: first available iPhone)
# Godot 4.7's simulator template is x86_64, so the app runs under Rosetta.
# Opening a link on a running Simulator by hand: xcrun simctl openurl booted '<link>'
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
NAME="WheresMe"
OUT="build/ios_sim"
BUNDLE="com.caboodle.app"
LINK="${1:-}"

if [[ -z "${SKIP_BUILD:-}" ]]; then
  tools/build_ios_native.sh
  rm -rf "$OUT" && mkdir -p "$OUT"
  touch build/.gdignore
  "$GODOT" --headless --path . --import >/dev/null
  "$GODOT" --headless --path . --export-debug "iOS" "$OUT/$NAME.ipa"
  xcodebuild build -project "$OUT/$NAME.xcodeproj" -scheme "$NAME" -configuration Debug \
    -sdk iphonesimulator -destination "generic/platform=iOS Simulator" -derivedDataPath "$OUT/dd" \
    ARCHS=x86_64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO -quiet
fi
APP="$(find "$OUT/dd/Build/Products" -maxdepth 2 -name "$NAME.app" | head -1)"
[[ -d "$APP" ]] || { echo "No simulator build at $OUT; run without SKIP_BUILD." >&2; exit 1; }

SIM="${SIM:-$(xcrun simctl list devices available | sed -n 's/^ *\(iPhone[^(]*\) (.*/\1/p' | head -1 | sed 's/ *$//')}"
xcrun simctl boot "$SIM" 2>/dev/null || true
open -a Simulator
xcrun simctl install "$SIM" "$APP"
xcrun simctl launch "$SIM" "$BUNDLE"
if [[ -n "$LINK" ]]; then
  sleep 4
  xcrun simctl openurl "$SIM" "$LINK"
fi
