#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuInventoryTests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/tmp"
export SKU_INSTALLER_TEST_MODE=1
mkdir -p "$HOME" "$TMPDIR"

# shellcheck source=../Resources/SkuInstaller.command
source "$ROOT/Resources/SkuInstaller.command"
ADDONS_FOLDER="$TEST_ROOT/World of Warcraft/_anniversary_/Interface/AddOns"
export SKU_ADDONS_FOLDER_OVERRIDE="$ADDONS_FOLDER"
mkdir -p "$ADDONS_FOLDER/Details" "$ADDONS_FOLDER/Details_DataStorage" \
    "$ADDONS_FOLDER/Pawn" "$ADDONS_FOLDER/UnknownAddon" "$ADDONS_FOLDER/Questie 1.2.3" \
    "$ADDONS_FOLDER/Sku" "$ADDONS_FOLDER/SkuAudioData_en" "$ADDONS_FOLDER/!BugGrabber" "$ADDONS_FOLDER/BugSack" "$ADDONS_FOLDER/GTFO"

printf '## Version: 1.0.0\n## X-Curse-Project-ID: 61284\n' > "$ADDONS_FOLDER/Details/Details.toc"
printf '## Version: 1.0.0\n' > "$ADDONS_FOLDER/Details_DataStorage/Details_DataStorage.toc"
printf '## Version: 2.13.15\n## X-Wago-ID: R4N2k46L\n' > "$ADDONS_FOLDER/Pawn/Pawn.toc"
printf '## Title: Ohne Quelle\n## Version: 7\n' > "$ADDONS_FOLDER/UnknownAddon/UnknownAddon.toc"
printf '## Version: 1.2.3\n## X-Curse-Project-ID: 334372\n' > "$ADDONS_FOLDER/Questie 1.2.3/Questie.toc"
printf '## Version: 43.1\n' > "$ADDONS_FOLDER/Sku/Sku.toc"
printf '## Version: 12\n' > "$ADDONS_FOLDER/SkuAudioData_en/SkuAudioData_en.toc"
printf '## Version: 1\n' > "$ADDONS_FOLDER/!BugGrabber/!BugGrabber.toc"
printf '## Version: 1\n' > "$ADDONS_FOLDER/BugSack/BugSack.toc"
printf '## Version: 5.16.3\n' > "$ADDONS_FOLDER/GTFO/GTFO.toc"

output="$(addon_inventory)"
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Details Damage Meter'
[ "$(printf '%s\n' "$output" | /usr/bin/grep -Fc 'Details Damage Meter')" -eq 1 ]
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Quelle: CurseForge – 61284'
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Quelle: Wago – R4N2k46L'
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Status: Zuordnung erforderlich'
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Status: möglicher doppelter Ordner'
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Sku'
printf '%s\n' "$output" | /usr/bin/grep -Fq 'Quelle: GitHub – Sku75/Sku-WoW-Addon-TBC'
! printf '%s\n' "$output" | /usr/bin/grep -Fq 'SkuAudioData_en'
! printf '%s\n' "$output" | /usr/bin/grep -Fq 'BugGrabber'
! printf '%s\n' "$output" | /usr/bin/grep -Fq 'BugSack'
! printf '%s\n' "$output" | /usr/bin/grep -Fq 'GTFO'
printf '%s\n' "$output" | /usr/bin/grep -Fq '5 Pakete erkannt, 1 ohne eindeutige Quelle, 1 mögliche Dubletten.'

echo "Alle Tests fuer das AddOn-Inventar bestanden."

