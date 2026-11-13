#!/bin/bash
# Builds "dist/Loophole.app".
#
#   --install      also copy it to /Applications and launch it
#   --universal    build for both Apple silicon and Intel (default: this Mac's architecture)
#
# Environment:
#   SIGN_IDENTITY  code-signing identity. Default "-" (ad hoc), which is fine on your own Mac.
#                  A "Developer ID Application: …" identity also enables the hardened runtime,
#                  as notarization requires.
#   VERSION        overrides the version number in Support/Info.plist
set -euo pipefail

cd "$(dirname "$0")/.."

INSTALL=0
ARCH_FLAGS=()
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        --universal) ARCH_FLAGS=(--arch arm64 --arch x86_64) ;;
        *) echo "Unknown option: $arg" >&2; exit 2 ;;
    esac
done

APP="dist/Loophole.app"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)/Loophole"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Loophole"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/"

if [[ -n "${VERSION:-}" ]]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    codesign --force --sign - "$APP"
else
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $APP ($(lipo -archs "$APP/Contents/MacOS/Loophole"))"

if [[ $INSTALL == 1 ]]; then
    pkill -x Loophole 2>/dev/null || true
    rm -rf "/Applications/Loophole.app"
    cp -R "$APP" /Applications/
    # Launching straight after quitting the old copy occasionally fails; give it a second try.
    open "/Applications/Loophole.app" || { sleep 2; open "/Applications/Loophole.app"; }
    echo "Installed to /Applications and launched"
fi
