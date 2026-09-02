#!/usr/bin/env python3
"""Fail when platform updater definitions drift from the shared catalog."""

import json
import pathlib
import sys


ROOT = pathlib.Path(__file__).resolve().parents[2]
catalog = json.loads((ROOT / "installer/shared/addon-catalog.json").read_text())
windows = (ROOT / "installer/SkuInstaller/Config.cs").read_text()
macos = (ROOT / "installer/macos/Resources/SkuInstaller.command").read_text()

errors = []


def require(text, value, platform):
    if value not in text:
        errors.append(f"{platform}: missing shared catalog value {value!r}")


require(windows, catalog["repository"].split("/", 1)[0], "Windows")
require(windows, catalog["repository"].split("/", 1)[1], "Windows")
require(windows, catalog["companionTag"], "Windows")

for section in ("companions", "languagePacks"):
    for package in catalog[section]:
        for value in (package["key"], package["asset"]):
            require(windows, value, "Windows")

for package in catalog["managedAnniversaryAddons"]:
    require(macos, package["key"], "macOS")
    require(macos, package["displayName"], "macOS")
    if package.get("project"):
        require(macos, package["project"], "macOS")
    if package.get("assetContains"):
        require(macos, package["assetContains"], "macOS")

for folder in catalog["inventory"]["hiddenPackages"]:
    require(macos, folder, "macOS")

if errors:
    print("\n".join(errors), file=sys.stderr)
    sys.exit(1)

print("shared addon catalog matches both platform implementations")
