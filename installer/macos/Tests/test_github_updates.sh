#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuGithubTests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT
export HOME="$TEST_ROOT/home" TMPDIR="$TEST_ROOT/tmp" SKU_INSTALLER_TEST_MODE=1
mkdir -p "$HOME" "$TMPDIR" "$TEST_ROOT/api/repos/Test/Addon/releases"

# shellcheck source=../Resources/SkuInstaller.command
source "$ROOT/Resources/SkuInstaller.command"
export SKU_GITHUB_API_BASE="file://$TEST_ROOT/api"
printf '%s\n' '{"tag_name":"Addon-9.8.7","assets":[{"name":"Addon-9.8.7-BurningCrusade.zip","browser_download_url":"https://github.com/Test/Addon/releases/download/Addon-9.8.7/Addon-9.8.7-BurningCrusade.zip","digest":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"}]}' > "$TEST_ROOT/api/repos/Test/Addon/releases/latest"

result="$(github_release_asset 'Test/Addon' 'BurningCrusade')"
[ "$(printf '%s\n' "$result" | sed -n '1p')" = "9.8.7" ]
[ "$(printf '%s\n' "$result" | sed -n '2p')" = "https://github.com/Test/Addon/releases/download/Addon-9.8.7/Addon-9.8.7-BurningCrusade.zip" ]
[ "$(printf '%s\n' "$result" | sed -n '3p')" = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ]

echo "Alle Tests fuer dynamische GitHub-Updates bestanden."

