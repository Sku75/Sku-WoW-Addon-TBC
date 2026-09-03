#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
catalog="$root/installer/shared/addon-catalog.json"
channel="$root/installer/shared/installer-channel.json"
mac_bootstrap="$root/installer/bootstrap/Install-SkuUpdater.command"
windows_bootstrap="$root/installer/bootstrap/Install-SkuUpdater.ps1"
page="$root/docs/index.html"

python3 -m json.tool "$catalog" >/dev/null
python3 -m json.tool "$channel" >/dev/null
bash -n "$mac_bootstrap"

python3 - "$catalog" "$channel" <<'PY'
import json
import sys

catalog = json.load(open(sys.argv[1], encoding="utf-8"))
channel = json.load(open(sys.argv[2], encoding="utf-8"))
assert catalog["schemaVersion"] == 2
assert channel["schemaVersion"] == 1
assert set(channel["platforms"]) == {"windows-x64", "macos-universal"}
assert catalog["mainAddon"]["key"] == "Sku"
# Since installer 5.0 the error/warning addons are MANAGED, not hidden.
assert catalog["inventory"]["hiddenPackages"] == []
entries = catalog["managedAnniversaryAddons"]
assert [e["prefKey"] for e in entries] == [
    "ManageQuestie", "ManageAtlasLoot", "ManageDetails", "ManagePawn",
    "ManageDBM", "ManageGTFO", "ManageBugSack",
]
# DBM is ONE entry bundling four release packages (BC and Vanilla raids are
# per-client); Pawn has one package per client; the BugSack pair two.
assert len([p for e in entries for p in e["packages"]]) == 12
for entry in entries:
    clients = set()
    for package in entry["packages"]:
        assert package["fallbackUrl"].startswith("https://")
        assert len(package["fallbackSha256"]) == 64
        assert package["requiredRoots"], package["key"]
        assert set(package["clients"]) <= {"anniversary", "era"}, package["key"]
        assert package["clients"], package["key"]
        clients.update(package["clients"])
    # Every entry serves BOTH managed clients (per-client packages included).
    assert clients == {"anniversary", "era"}, entry["prefKey"]
PY

# The download page carries one clearly labeled link per platform.
grep -Fq 'SkuInstaller.exe' "$page"
grep -Fq 'Install-SkuUpdater-macOS.zip' "$page"
grep -Fq 'Install-SkuUpdater-macOS.zip' "$root/docs/index-de.html"
grep -Fq 'Install-SkuUpdater-macOS.zip' "$root/docs/index-fr.html"
grep -Fq 'installer-version.txt' "$windows_bootstrap"
grep -Fq 'installer-version-macos.txt' "$mac_bootstrap"
grep -Fq 'CFBundleShortVersionString' "$mac_bootstrap"
grep -Fq 'build-release-assets.sh' "$root/.github/workflows/build-installers.yml"
grep -Fq 'installer-version-macos.txt' "$root/.github/workflows/build-installers.yml"

printf '%s\n' 'Universal installer tests passed.'
