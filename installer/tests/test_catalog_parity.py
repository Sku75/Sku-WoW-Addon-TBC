#!/usr/bin/env python3
"""Fail when platform updater definitions drift from the shared catalog."""

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
catalog = json.loads((ROOT / "installer/shared/addon-catalog.json").read_text())
windows_config = (ROOT / "installer/SkuInstaller/Config.cs").read_text()
windows_managed = (ROOT / "installer/SkuInstaller/ManagedAddons.cs").read_text(encoding="utf-8")
macos = (ROOT / "installer/macos/Resources/SkuInstaller.command").read_text(encoding="utf-8")
macos_app = (ROOT / "installer/macos/Sources/SkuInstaller/main.m").read_text(encoding="utf-8")

errors = []


def require(text, value, where):
    if value not in text:
        errors.append(f"{where}: missing shared catalog value {value!r}")


require(windows_config, catalog["repository"].split("/", 1)[0], "Windows Config.cs")
require(windows_config, catalog["repository"].split("/", 1)[1], "Windows Config.cs")
require(windows_config, catalog["companionTag"], "Windows Config.cs")

for section in ("companions", "languagePacks"):
    for package in catalog[section]:
        for value in (package["key"], package["asset"]):
            require(windows_config, value, "Windows Config.cs")

# Managed third-party addons: both platforms must carry every entry's pref key
# and every package's manifest key, source project, and pinned URL + SHA-256.
for entry in catalog["managedAnniversaryAddons"]:
    require(macos, entry["prefKey"], "macOS")
    require(macos_app, entry["prefKey"], "macOS app")
    require(windows_managed, entry["prefKey"], "Windows ManagedAddons.cs")
    require(windows_managed, entry["displayName"], "Windows ManagedAddons.cs")
    for package in entry["packages"]:
        for platform, text in (("macOS", macos), ("Windows ManagedAddons.cs", windows_managed)):
            require(text, package["key"], platform)
            if package.get("project"):
                require(text, package["project"], platform)
            require(text, package["fallbackUrl"], platform)
            require(text, package["fallbackSha256"], platform)
        if package.get("assetContains"):
            require(macos, package["assetContains"], "macOS")
        if package.get("assetTemplate"):
            require(windows_managed, package["assetTemplate"], "Windows ManagedAddons.cs")

# Pawn is the one entry that defaults OFF; both platforms encode that default.
defaults_off = [e["prefKey"] for e in catalog["managedAnniversaryAddons"]
                if not e.get("defaultEnabled", True)]
if defaults_off != ["ManagePawn"]:
    errors.append(f"catalog: unexpected default-off set {defaults_off!r}")
if 'case "$1" in ManagePawn) return 1 ;; esac' not in macos:
    errors.append("macOS: ManagePawn default-off missing in preference_enabled")
if "DefaultEnabled = false" not in windows_managed:
    errors.append("Windows ManagedAddons.cs: ManagePawn DefaultEnabled = false missing")

for folder in catalog["inventory"]["hiddenPackages"]:
    require(macos, folder, "macOS")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print("shared addon catalog matches both platform implementations")
