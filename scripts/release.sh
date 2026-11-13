#!/bin/bash
# Builds the downloadable release: a universal, Developer ID-signed, notarized
# "dist/Loophole-<version>.dmg" that opens on any Mac without Gatekeeper warnings.
#
#   --skip-notarize   package without notarizing (to try the packaging; not for distribution)
#
# Requirements:
#   - A "Developer ID Application" certificate in your keychain (SIGN_IDENTITY overrides auto-detection).
#   - Notary credentials, one of:
#       NOTARY_PROFILE   a keychain profile made once with
#                        `xcrun notarytool store-credentials loophole-notary` (the default name), or
#       NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER   an App Store Connect API key (.p8 path, key ID,
#                        issuer ID) — what the GitHub workflow uses.
#   VERSION            overrides the version number in Support/Info.plist
set -euo pipefail

cd "$(dirname "$0")/.."

NOTARIZE=1
[[ "${1:-}" == "--skip-notarize" ]] && NOTARIZE=0

VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Support/Info.plist)}"
APP="dist/Loophole.app"
DMG="dist/Loophole-$VERSION.dmg"

if [[ -z "${SIGN_IDENTITY:-}" ]]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
if [[ -z "$SIGN_IDENTITY" ]]; then
    echo "No \"Developer ID Application\" certificate found in the keychain." >&2
    echo "Create one in Xcode → Settings → Accounts → Manage Certificates, or set SIGN_IDENTITY." >&2
    exit 1
fi

if [[ -n "${NOTARY_KEY:-}" ]]; then
    NOTARY_AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
else
    NOTARY_AUTH=(--keychain-profile "${NOTARY_PROFILE:-loophole-notary}")
fi

# Submits a file to Apple's notary service and fails unless it is accepted.
notarize() {
    local output
    output="$(xcrun notarytool submit "$1" "${NOTARY_AUTH[@]}" --wait 2>&1)" || { echo "$output" >&2; exit 1; }
    echo "$output" | tail -3
    echo "$output" | grep -q "status: Accepted" || { echo "Notarization of $1 was not accepted." >&2; exit 1; }
}

SIGN_IDENTITY="$SIGN_IDENTITY" VERSION="$VERSION" scripts/build-app.sh --universal

if [[ $NOTARIZE == 1 ]]; then
    # Notarize the app itself and staple the ticket, so it also passes Gatekeeper offline.
    ZIP="dist/Loophole.zip"
    ditto -c -k --keepParent "$APP" "$ZIP"
    notarize "$ZIP"
    rm "$ZIP"
    xcrun stapler staple "$APP"
fi

# The classic disk image: the app next to a shortcut to /Applications.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f "$DMG"
hdiutil create -quiet -volname "Loophole" -srcfolder "$STAGE" -format UDZO "$DMG"

if [[ "$SIGN_IDENTITY" != "-" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi
if [[ $NOTARIZE == 1 ]]; then
    notarize "$DMG"
    xcrun stapler staple "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
fi

echo "Release image: $DMG"
