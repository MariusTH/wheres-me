#!/usr/bin/env bash
# Export the web build and upload it to itch.io with butler.
#   tools/publish_itch.sh            export + push to parchnipp/wheres-me:html5
#   tools/publish_itch.sh --dry-run  export only, print the butler command
# Needs Godot 4.5.x with web export templates, and butler logged in once
# (`butler login`). On itch.io, set the upload's kind to "HTML" / "This file
# will be played in the browser"; the build is single-threaded, so
# SharedArrayBuffer support is not needed.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT="${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}"
TARGET="${ITCH_TARGET:-parchnipp/wheres-me:html5}"
VERSION="$(date +%Y.%m.%d-%H%M)"

rm -rf build/web && mkdir -p build/web
"$GODOT" --headless --path . --import >/dev/null
"$GODOT" --headless --path . --export-release "Web" build/web/index.html
if [[ "${1:-}" == "--dry-run" ]]; then
  echo "Exported to build/web. Would run: butler push build/web $TARGET --userversion $VERSION"
  exit 0
fi
butler push build/web "$TARGET" --userversion "$VERSION"
