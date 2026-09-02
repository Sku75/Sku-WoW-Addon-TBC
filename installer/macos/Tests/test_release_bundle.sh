#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Sku Installer.app"
DIST="$ROOT/../dist-universal"

test -d "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/lipo "$APP/Contents/MacOS/SkuInstaller" -verify_arch x86_64 arm64
/usr/bin/lipo "$APP/Contents/Resources/SkuLoginSense" -verify_arch x86_64 arm64

for resource in SkuInstaller.command SkuLoginTool.lua StartSkuLoginTool.applescript addon-catalog.json installer-channel.json; do
    test -f "$APP/Contents/Resources/$resource"
done

plist_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
backend_version="$(/usr/bin/sed -n 's/^APP_VERSION="\([^"]*\)"/\1/p' "$ROOT/Resources/SkuInstaller.command")"
test "$plist_version" = "$backend_version"

metadata_version="$(/usr/bin/awk -F= 'NR==1 && $1=="version" {print $2}' "$DIST/installer-version-macos.txt")"
metadata_sha="$(/usr/bin/awk -F= 'NR==2 && $1=="sha256" {print tolower($2)}' "$DIST/installer-version-macos.txt")"
archive_sha="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$DIST/Sku-Installer-macOS.zip" | /usr/bin/awk '{print tolower($1)}')"
test "$metadata_version" = "$plist_version"
test "$metadata_sha" = "$archive_sha"

printf '%s\n' 'macOS release bundle tests passed.'
