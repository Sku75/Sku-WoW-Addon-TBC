#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuGithubTests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" SKU_INSTALLER_TEST_MODE=1
mkdir -p "$HOME" "$TMPDIR" "$TEST_ROOT/api/repos/Test/Addon/releases"

# shellcheck source=../Resources/SkuInstaller.command
source "$ROOT/Resources/SkuInstaller.command"

metadata_fixture=$'version=5.4.0\nsha256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
mac_installer_metadata() { printf '%s\n' "$metadata_fixture"; }
self_update_output="$(self_update_check)"
printf '%s\n' "$self_update_output" | grep -Fqx 'LATEST=5.4.0'
printf '%s\n' "$self_update_output" | grep -Fqx 'SHA256=0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
printf '%s\n' "$self_update_output" | grep -Fqx 'AVAILABLE=1'

export SKU_INSTALLER_APPLICATIONS_DIR="$TEST_ROOT/Applications"
mkdir -p "$SKU_INSTALLER_APPLICATIONS_DIR/Sku Installer.app" "$TEST_ROOT/new/Sku Installer.app"
printf '%s\n' old > "$SKU_INSTALLER_APPLICATIONS_DIR/Sku Installer.app/build.txt"
printf '%s\n' new > "$TEST_ROOT/new/Sku Installer.app/build.txt"
replace_installed_app "$TEST_ROOT/new/Sku Installer.app"
[ "$(cat "$SKU_INSTALLER_APPLICATIONS_DIR/Sku Installer.app/build.txt")" = "new" ]
[ -z "$(find "$SKU_INSTALLER_APPLICATIONS_DIR" -maxdepth 1 -name '.Sku Installer.*' -print -quit)" ]

export SKU_GITHUB_API_BASE="file://$TEST_ROOT/api"
printf '%s\n' '{"tag_name":"Addon-9.8.7","assets":[{"name":"Addon-9.8.7-BurningCrusade.zip","browser_download_url":"https://github.com/Test/Addon/releases/download/Addon-9.8.7/Addon-9.8.7-BurningCrusade.zip","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}' > "$TEST_ROOT/api/repos/Test/Addon/releases/latest"

result="$(github_release_asset 'Test/Addon' 'BurningCrusade')"
[ "$(printf '%s\n' "$result" | sed -n '1p')" = "9.8.7" ]
[ "$(printf '%s\n' "$result" | sed -n '2p')" = "https://github.com/Test/Addon/releases/download/Addon-9.8.7/Addon-9.8.7-BurningCrusade.zip" ]
[ "$(printf '%s\n' "$result" | sed -n '3p')" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]

echo "Alle Tests fuer dynamische GitHub-Updates bestanden."
