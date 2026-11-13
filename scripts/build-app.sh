#!/bin/bash
# Builds "dist/Pi-hole Switcher.app". Pass --install to also copy it to /Applications and launch it.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="dist/Pi-hole Switcher.app"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/PiholeSwitcher"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PiholeSwitcher"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns Support/pi-hole-menubar.svg "$APP/Contents/Resources/"
codesign --force --sign - "$APP"

echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
    pkill -x PiholeSwitcher 2>/dev/null || true
    rm -rf "/Applications/Pi-hole Switcher.app"
    cp -R "$APP" /Applications/
    open "/Applications/Pi-hole Switcher.app"
    echo "Installed to /Applications and launched"
fi
