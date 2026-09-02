#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
catalog="$root/installer/shared/addon-catalog.json"
channel="$root/installer/shared/installer-channel.json"
mac_bootstrap="$root/installer/bootstrap/Install-SkuUpdater.command"
windows_bootstrap="$root/installer/bootstrap/Install-SkuUpdater.ps1"
page="$root/docs/installer-download.html"

python3 -m json.tool "$catalog" >/dev/null
python3 -m json.tool "$channel" >/dev/null
bash -n "$mac_bootstrap"

python3 - "$catalog" "$channel" <<'PY'
import json
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
channel = json.load(open(sys.argv[2], encoding="utf-8"))
assert catalog["schemaVersion"] == 1
assert channel["schemaVersion"] == 1
assert set(channel["platforms"]) == {"windows-x64", "macos-universal"}
assert catalog["mainAddon"]["key"] == "Sku"
assert set(catalog["inventory"]["hiddenPackages"]) == {"!BugGrabber", "BugSack", "GTFO"}
assert len(catalog["managedAnniversaryAddons"]) == 4
PY

grep -Fq 'Install-SkuUpdater.ps1' "$page"
grep -Fq 'Install-SkuUpdater-macOS.zip' "$page"
grep -Fq 'installer-version.txt' "$windows_bootstrap"
grep -Fq 'installer-version-macos.txt' "$mac_bootstrap"

printf '%s\n' 'Universal installer tests passed.'
