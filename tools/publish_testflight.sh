#!/usr/bin/env bash
# Build the iOS app and upload it to TestFlight (App Store Connect app
# "Where's Me?", Apple ID 6834707882, bundle com.caboodle.app).
#
#   tools/publish_testflight.sh              build, archive, upload
#   tools/publish_testflight.sh --no-upload  build, archive, export .ipa to build/ios/ipa
#
# Env overrides:
#   VERSION=1.0.1    marketing version (CFBundleShortVersionString), default from the iOS preset
#   BUILD=42         build number (CFBundleVersion), default: UTC timestamp (always increasing)
#   GODOT=/path      Godot 4.7 binary (needs the 4.7.2 iOS export templates)
#
# Signing/auth: automatic signing with team 5LMLNW3DV5. Either be signed in to
# that Apple ID in Xcode > Settings > Accounts, or use an App Store Connect API
# key (App Store Connect > Users and Access > Integrations > Keys):
#   ASC_KEY_ID=XXXXXXXXXX ASC_ISSUER_ID=xxxxxxxx-... ASC_KEY_PATH=~/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
set -euo pipefail
cd "$(dirname "$0")/.."

GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TEAM_ID="5LMLNW3DV5"
NAME="WheresMe"
OUT="build/ios"
ARCHIVE="$OUT/$NAME.xcarchive"
UPLOAD=1
[[ "${1:-}" == "--no-upload" ]] && UPLOAD=0
BUILD="${BUILD:-$(date -u +%Y%m%d%H%M)}"

AUTH=()
if [[ -n "${ASC_KEY_ID:-}" ]]; then
  : "${ASC_ISSUER_ID:?set ASC_ISSUER_ID with ASC_KEY_ID}" "${ASC_KEY_PATH:?set ASC_KEY_PATH with ASC_KEY_ID}"
  AUTH=(-authenticationKeyPath "${ASC_KEY_PATH/#\~/$HOME}" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

step() { printf '\n==> %s\n' "$*"; }

step "Building native glue (share sheet + deep links)"
tools/build_ios_native.sh

step "Exporting Xcode project from Godot"
rm -rf "$OUT" && mkdir -p "$OUT"
touch build/.gdignore  # keep Godot from scanning/importing build output
"$GODOT" --headless --path . --import >/dev/null
"$GODOT" --headless --path . --export-release "iOS" "$OUT/$NAME.ipa"
PROJECT="$OUT/$NAME.xcodeproj"
[[ -d "$PROJECT" ]] || { echo "Godot export did not produce $PROJECT" >&2; exit 1; }
grep -q WMNative "$PROJECT/project.pbxproj" || { echo "WMNative.xcframework is not linked (share sheet / deep links)." >&2; exit 1; }

# Info.plist reads these from build settings, so override them for xcodebuild.
SHORT="${VERSION:-$(sed -n 's/^application\/short_version="\(.*\)"/\1/p' export_presets.cfg | tail -1)}"
echo "Version $SHORT ($BUILD)"

step "Archiving"
xcodebuild archive \
  -project "$PROJECT" -scheme "$NAME" -configuration Release \
  -destination "generic/platform=iOS" -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" CODE_SIGN_STYLE=Automatic \
  CODE_SIGN_IDENTITY="Apple Development" PROVISIONING_PROFILE_SPECIFIER="" \
  MARKETING_VERSION="$SHORT" CURRENT_PROJECT_VERSION="$BUILD" \
  | { command -v xcpretty >/dev/null && xcpretty || cat; }

step "$([[ $UPLOAD == 1 ]] && echo "Uploading to App Store Connect / TestFlight" || echo "Exporting .ipa")"
cat > "$OUT/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>$([[ $UPLOAD == 1 ]] && echo upload || echo export)</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>signingStyle</key><string>automatic</string>
  <key>uploadSymbols</key><true/>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>testFlightInternalTestingOnly</key><false/>
</dict>
</plist>
EOF
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" -exportOptionsPlist "$OUT/ExportOptions.plist" -exportPath "$OUT/ipa" \
  -allowProvisioningUpdates ${AUTH[@]+"${AUTH[@]}"}

if [[ $UPLOAD == 1 ]]; then
  echo
  echo "Uploaded $SHORT ($BUILD). It shows up in TestFlight after processing (usually 5-15 min):"
  echo "https://appstoreconnect.apple.com/apps/6834707882/testflight/ios"
else
  echo "IPA: $OUT/ipa"
fi
