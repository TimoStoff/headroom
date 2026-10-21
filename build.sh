#!/bin/bash
# Builds Headroom.app as a universal (Apple Silicon + Intel) binary.
#   ./build.sh            build build/Headroom.app
#   ./build.sh install    build, copy to /Applications and (re)launch
#   ./build.sh dmg        build and package build/Headroom-<version>.dmg
#
# Signing (optional; without it the app gets an ad-hoc signature):
#   SIGN_ID          Developer ID Application identity (name or SHA-1) to sign the app and DMG with
# Notarizing the DMG (needs SIGN_ID), either:
#   NOTARY_PROFILE   a profile saved with `xcrun notarytool store-credentials`, or
#   NOTARY_KEY, NOTARY_KEY_ID, NOTARY_ISSUER   an App Store Connect API key (.p8 path, key id, issuer id)
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)

# Build each architecture separately and merge with lipo: `--arch a --arch b` needs Xcode's XCBuild,
# which the command line tools alone do not include. Each slice gets its own scratch path, since newer
# SwiftPM reports the same bin path for every triple.
SLICES=()
for ARCH in arm64 x86_64; do
    OPTS=(-c release --triple "$ARCH-apple-macosx14.0" --scratch-path ".build/$ARCH")
    swift build "${OPTS[@]}"
    SLICES+=("$(swift build "${OPTS[@]}" --show-bin-path)/Headroom")
done
BIN=.build/Headroom-universal
lipo -create "${SLICES[@]}" -output "$BIN"

APP=build/Headroom.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Headroom"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
if [ -n "${SIGN_ID:-}" ]; then
    # Notarization requires the hardened runtime and a secure timestamp.
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    codesign --force --sign - "$APP"
fi
echo "Built $APP ($VERSION, $(lipo -archs "$APP/Contents/MacOS/Headroom"))"

case "${1:-}" in
install)
    pkill -x Headroom 2>/dev/null || true
    sleep 0.5
    rm -rf /Applications/Headroom.app
    cp -R "$APP" /Applications/
    open /Applications/Headroom.app
    echo "Installed and launched /Applications/Headroom.app"
    ;;
dmg)
    DMG="build/Headroom-$VERSION.dmg"
    STAGE=build/dmg
    rm -rf "$STAGE" "$DMG"
    mkdir -p "$STAGE"
    cp -R "$APP" "$STAGE/"
    ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "Headroom $VERSION" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
    rm -rf "$STAGE"
    echo "Packaged $DMG ($(du -h "$DMG" | cut -f1))"

    [ -n "${SIGN_ID:-}" ] || exit 0
    codesign --force --timestamp --sign "$SIGN_ID" "$DMG"
    if [ -n "${NOTARY_PROFILE:-}" ]; then
        AUTH=(--keychain-profile "$NOTARY_PROFILE")
    elif [ -n "${NOTARY_KEY:-}" ]; then
        AUTH=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
    else
        echo "Signed $DMG (not notarized: no NOTARY_PROFILE or NOTARY_KEY)"
        exit 0
    fi
    # The ticket also covers the app inside, so Gatekeeper accepts it without a network check.
    xcrun notarytool submit "$DMG" "${AUTH[@]}" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG"
    echo "Notarized $DMG"
    ;;
esac
