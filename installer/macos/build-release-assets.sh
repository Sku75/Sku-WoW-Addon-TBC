#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
app="$root/installer/macos/build/Sku Installer.app"
dist="$root/installer/dist-universal"
archive="$dist/Sku-Installer-macOS.zip"
metadata="$dist/installer-version-macos.txt"

"$root/installer/macos/build.sh"
mkdir -p "$dist"
rm -f "$archive" "$metadata"
/usr/bin/ditto -c -k --norsrc --keepParent "$app" "$archive"

if [ -n "${MACOS_NOTARY_PROFILE:-}" ]; then
  [ "${MACOS_CODESIGN_IDENTITY:--}" != "-" ] || {
    printf '%s\n' 'MACOS_NOTARY_PROFILE erfordert eine Developer-ID in MACOS_CODESIGN_IDENTITY.' >&2
    exit 1
  }
  /usr/bin/xcrun notarytool submit "$archive" --keychain-profile "$MACOS_NOTARY_PROFILE" --wait
  /usr/bin/xcrun stapler staple "$app"
  /usr/bin/xcrun stapler validate "$app"
  rm -f "$archive"
  /usr/bin/ditto -c -k --norsrc --keepParent "$app" "$archive"
  /usr/sbin/spctl --assess --type execute "$app"
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
sha="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print tolower($1)}')"
printf 'version=%s\nsha256=%s\n' "$version" "$sha" > "$metadata"

"$root/installer/bootstrap/build-bootstrap-macos.sh" >/dev/null
printf '%s\n' "$dist"
