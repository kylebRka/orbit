#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
if [[ "$configuration" != release && "$configuration" != debug ]]; then
  echo "Usage: scripts/build.sh [release|debug]" >&2
  exit 1
fi
swift build -c "$configuration"
bin_dir="$(swift build -c "$configuration" --show-bin-path)"
app="dist/Orbit.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" .build/Orbit.iconset
cp "$bin_dir/Orbit" "$app/Contents/MacOS/Orbit"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift .build/Orbit.iconset
iconutil -c icns .build/Orbit.iconset -o "$app/Contents/Resources/AppIcon.icns"
cp .build/Orbit.iconset/icon_512x512@2x.png Resources/AppIcon.png
cp Resources/AppIcon.png "$app/Contents/Resources/AppIcon.png"
codesign --force --sign - --identifier app.orbit.converter "$app"
echo "Built $app"
