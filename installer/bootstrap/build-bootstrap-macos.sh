#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
dist="$root/installer/dist-universal"
stage="$(mktemp -d "${TMPDIR:-/tmp}/SkuBootstrap.XXXXXX")"
trap 'rm -rf "$stage"' EXIT HUP INT TERM

mkdir -p "$dist" "$stage/Sku Installer Setup"
/usr/bin/ditto "$root/installer/bootstrap/Install-SkuUpdater.command" "$stage/Sku Installer Setup/Install Sku Updater.command"
chmod 755 "$stage/Sku Installer Setup/Install Sku Updater.command"
rm -f "$dist/Install-SkuUpdater-macOS.zip"
/usr/bin/ditto -c -k --norsrc --keepParent "$stage/Sku Installer Setup" "$dist/Install-SkuUpdater-macOS.zip"
/usr/bin/ditto "$root/installer/bootstrap/Install-SkuUpdater.ps1" "$dist/Install-SkuUpdater.ps1"
/usr/bin/ditto "$root/installer/shared/addon-catalog.json" "$dist/addon-catalog.json"
/usr/bin/ditto "$root/installer/shared/installer-channel.json" "$dist/installer-channel.json"

printf '%s\n' "$dist"
