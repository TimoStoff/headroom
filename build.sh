#!/bin/bash
# Builds Headroom.app. Pass "install" to copy it to /Applications and (re)launch it.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
APP=build/Headroom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Headroom "$APP/Contents/MacOS/Headroom"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Headroom 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Headroom.app
    cp -R "$APP" /Applications/
    open /Applications/Headroom.app
    echo "Installed and launched /Applications/Headroom.app"
fi
