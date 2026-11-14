#!/usr/bin/env bash
# Build native/ios/WMNative.m (share sheet + deep links) into
# native/ios/build/WMNative.xcframework (device + simulator), which
# addons/wm_ios_native links into iOS exports. Run before exporting iOS from
# the editor; tools/publish_testflight.sh and tools/run_ios_sim.sh run it.
set -euo pipefail
cd "$(dirname "$0")/.."
SRC=native/ios/WMNative.m
OUT=native/ios/build
MIN_IOS=15.0
rm -rf "$OUT" && mkdir -p "$OUT/device" "$OUT/sim"

compile() { # sdk, dir, target triples...
  local sdk=$1 dir=$2; shift 2
  local objs=()
  for t in "$@"; do
    xcrun -sdk "$sdk" clang -target "$t" -fobjc-arc -fmodules -O2 -c "$SRC" -o "$OUT/$dir/WMNative-$t.o"
    objs+=("$OUT/$dir/WMNative-$t.o")
  done
  xcrun -sdk "$sdk" libtool -static -o "$OUT/$dir/libwmnative.a" "${objs[@]}"
}
compile iphoneos device "arm64-apple-ios$MIN_IOS"
# Godot 4.7's simulator template is x86_64 only (Rosetta); keep arm64 too for later templates.
compile iphonesimulator sim "arm64-apple-ios$MIN_IOS-simulator" "x86_64-apple-ios$MIN_IOS-simulator"

xcodebuild -create-xcframework \
  -library "$OUT/device/libwmnative.a" -library "$OUT/sim/libwmnative.a" \
  -output "$OUT/WMNative.xcframework" >/dev/null
echo "Built $OUT/WMNative.xcframework"
