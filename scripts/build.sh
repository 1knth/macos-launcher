#!/bin/bash
# Builds build/Prism.app (release). Set PRISM_SIGNING_IDENTITY to sign with your own identity;
# a stable identity keeps Accessibility / Screen Recording grants across rebuilds.
set -euo pipefail
cd "$(dirname "$0")/.."
APP=build/Prism.app
if [[ ! -f Resources/Prism.icns || scripts/make-icon.swift -nt Resources/Prism.icns ]]; then
    mkdir -p build/Prism.iconset
    swift scripts/make-icon.swift Resources/Prism.png
    for size in 16 32 128 256 512; do
        sips -z "$size" "$size" Resources/Prism.png --out "build/Prism.iconset/icon_${size}x${size}.png" >/dev/null
        sips -z $((size * 2)) $((size * 2)) Resources/Prism.png --out "build/Prism.iconset/icon_${size}x${size}@2x.png" >/dev/null
    done
    iconutil -c icns build/Prism.iconset -o Resources/Prism.icns
fi
swift build -c release --product Prism
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Prism" "$APP/Contents/MacOS/Prism"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Prism.icns "$APP/Contents/Resources/Prism.icns"
# Default to the self-signed "Prism Local Signing" identity when it's in the keychain.
if [[ -z "${PRISM_SIGNING_IDENTITY:-}" ]] && security find-identity -p codesigning | grep -q '"Prism Local Signing"'; then
    PRISM_SIGNING_IDENTITY="Prism Local Signing"
fi
codesign --force --sign "${PRISM_SIGNING_IDENTITY:--}" --identifier app.local.prism "$APP"
echo "Built $APP"
