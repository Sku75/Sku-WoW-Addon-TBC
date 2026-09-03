#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
APP="$BUILD/Sku Installer.app"
SIGN_IDENTITY="${MACOS_CODESIGN_IDENTITY:--}"
ARCH_FLAGS=(-arch arm64 -arch x86_64)

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/de.lproj" "$APP/Contents/Resources/en.lproj" "$APP/Contents/Resources/fr.lproj"
/usr/bin/clang -fobjc-arc -fmodules \
  "${ARCH_FLAGS[@]}" \
  -fmodules-cache-path="${TMPDIR:-/tmp}/sku-installer-clang-cache" \
  -mmacosx-version-min=10.15 -framework Cocoa \
  "$ROOT/Sources/SkuInstaller/main.m" -o "$APP/Contents/MacOS/SkuInstaller"
/usr/bin/clang -fobjc-arc -fmodules \
  "${ARCH_FLAGS[@]}" \
  -fmodules-cache-path="${TMPDIR:-/tmp}/sku-installer-clang-cache" \
  -mmacosx-version-min=10.15 -framework Foundation -framework Vision -framework CoreGraphics -framework ImageIO \
  "$ROOT/Sources/SkuLoginSense/main.m" -o "$APP/Contents/Resources/SkuLoginSense"
/usr/bin/ditto "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/ditto "$ROOT/Resources/SkuInstaller.command" "$APP/Contents/Resources/SkuInstaller.command"
/usr/bin/ditto "$ROOT/Resources/SkuLoginTool.lua" "$APP/Contents/Resources/SkuLoginTool.lua"
/usr/bin/ditto "$ROOT/Resources/StartSkuLoginTool.applescript" "$APP/Contents/Resources/StartSkuLoginTool.applescript"
/usr/bin/ditto "$ROOT/../shared/addon-catalog.json" "$APP/Contents/Resources/addon-catalog.json"
/usr/bin/ditto "$ROOT/../shared/installer-channel.json" "$APP/Contents/Resources/installer-channel.json"
/bin/chmod 755 "$APP/Contents/MacOS/SkuInstaller" "$APP/Contents/Resources/SkuInstaller.command" "$APP/Contents/Resources/SkuLoginSense"
if [ "$SIGN_IDENTITY" = "-" ]; then
  /usr/bin/codesign --force --deep --sign - "$APP"
else
  /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/Resources/SkuLoginSense"
  /usr/bin/codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
fi
/usr/bin/codesign --verify --deep --strict "$APP"
printf '%s\n' "$APP"
