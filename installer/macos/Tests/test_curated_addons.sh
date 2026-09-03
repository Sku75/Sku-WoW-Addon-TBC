#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuInstallerTests.XXXXXX")"
trap 'rm -rf "$TEST_ROOT"' EXIT

mkdir -p "$TEST_ROOT/home" "$TEST_ROOT/World of Warcraft/_anniversary_/Interface/AddOns"
export HOME="$TEST_ROOT/home"
export TMPDIR="$TEST_ROOT/tmp"
mkdir -p "$TMPDIR"
export SKU_INSTALLER_TEST_MODE=1

# shellcheck source=../Resources/SkuInstaller.command
source "$ROOT/Resources/SkuInstaller.command"
ADDONS_FOLDER="$TEST_ROOT/World of Warcraft/_anniversary_/Interface/AddOns"

make_archive() {
    local stage="$1" archive="$2" version="$3"
    mkdir -p "$stage/TestCore" "$stage/TestModule"
    printf '## Interface: 20506\n## Version: %s\n' "$version" > "$stage/TestCore/TestCore_TBC.toc"
    printf '## Interface: 20506\n## Version: %s\n' "$version" > "$stage/TestModule/TestModule_TBC.toc"
    printf '%s\n' "$version" > "$stage/TestCore/payload.txt"
    (cd "$stage" && /usr/bin/zip -qr "$archive" TestCore TestModule)
}

ARCHIVE1="$TEST_ROOT/package-1.zip"
make_archive "$TEST_ROOT/stage-1" "$ARCHIVE1" "1.0.0"
SHA1="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$ARCHIVE1" | awk '{print $1}')"
install_curated_package "TestPackage" "Testpaket" "1.0.0" "file://$ARCHIVE1" "$SHA1" "TestCore TestModule"
[ -f "$ADDONS_FOLDER/TestCore/TestCore_TBC.toc" ]
[ -f "$ADDONS_FOLDER/TestModule/TestModule_TBC.toc" ]
save_manifest

MANIFEST_KEYS=""
MANIFEST_VALUES=""
install_curated_package "TestPackage" "Testpaket" "1.0.0" "file:///existiert-nicht.zip" \
    "$SHA1" "TestCore TestModule"

printf 'bestehend\n' > "$ADDONS_FOLDER/TestCore/sentinel.txt"
if install_curated_package "BadHash" "Testpaket" "2.0.0" "file://$ARCHIVE1" \
    "0000000000000000000000000000000000000000000000000000000000000000" "TestCore TestModule"; then
    echo "Fehler: Paket mit falscher Pruefsumme wurde akzeptiert." >&2
    exit 1
fi
[ "$(cat "$ADDONS_FOLDER/TestCore/sentinel.txt")" = "bestehend" ]

BAD_ARCHIVE="$TEST_ROOT/unexpected.zip"
mkdir -p "$TEST_ROOT/bad/Unexpected"
printf '## Interface: 20506\n' > "$TEST_ROOT/bad/Unexpected/Unexpected.toc"
(cd "$TEST_ROOT/bad" && /usr/bin/zip -qr "$BAD_ARCHIVE" Unexpected)
BAD_SHA="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$BAD_ARCHIVE" | awk '{print $1}')"
if install_curated_package "Unexpected" "Testpaket" "2.0.0" "file://$BAD_ARCHIVE" "$BAD_SHA" "TestCore TestModule"; then
    echo "Fehler: Paket mit unerwartetem Zielordner wurde akzeptiert." >&2
    exit 1
fi
[ "$(cat "$ADDONS_FOLDER/TestCore/sentinel.txt")" = "bestehend" ]

LINK_ARCHIVE="$TEST_ROOT/link.zip"
mkdir -p "$TEST_ROOT/link/TestCore" "$TEST_ROOT/link/TestModule"
printf '## Interface: 20506\n' > "$TEST_ROOT/link/TestCore/TestCore.toc"
printf '## Interface: 20506\n' > "$TEST_ROOT/link/TestModule/TestModule.toc"
/bin/ln -s /tmp "$TEST_ROOT/link/TestCore/unsafe-link"
(cd "$TEST_ROOT/link" && /usr/bin/zip -qry "$LINK_ARCHIVE" TestCore TestModule)
LINK_SHA="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$LINK_ARCHIVE" | awk '{print $1}')"
if install_curated_package "Link" "Testpaket" "2.0.0" "file://$LINK_ARCHIVE" "$LINK_SHA" "TestCore TestModule"; then
    echo "Fehler: Paket mit symbolischem Link wurde akzeptiert." >&2
    exit 1
fi
[ "$(cat "$ADDONS_FOLDER/TestCore/sentinel.txt")" = "bestehend" ]

# Muster-Allowlist ("Test*", wie "DBM-*"): ein zusaetzlicher Ordner aus einem
# kuenftigen Release muss durchgehen und mitinstalliert werden; namentlich
# geforderte Ordner bleiben Pflicht.
WILD_ARCHIVE="$TEST_ROOT/wild.zip"
mkdir -p "$TEST_ROOT/wild/TestCore" "$TEST_ROOT/wild/TestModule" "$TEST_ROOT/wild/TestExtra"
printf '## Interface: 20506\n## Version: 3.0.0\n' > "$TEST_ROOT/wild/TestCore/TestCore_TBC.toc"
printf '## Interface: 20506\n## Version: 3.0.0\n' > "$TEST_ROOT/wild/TestModule/TestModule_TBC.toc"
printf '## Interface: 20506\n## Version: 3.0.0\n' > "$TEST_ROOT/wild/TestExtra/TestExtra_TBC.toc"
(cd "$TEST_ROOT/wild" && /usr/bin/zip -qr "$WILD_ARCHIVE" TestCore TestModule TestExtra)
WILD_SHA="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$WILD_ARCHIVE" | awk '{print $1}')"
install_curated_package "TestPackage" "Testpaket" "3.0.0" "file://$WILD_ARCHIVE" "$WILD_SHA" "TestCore Test*"
[ -f "$ADDONS_FOLDER/TestExtra/TestExtra_TBC.toc" ]

# Ein Muster ersetzt die Pflicht nicht: fehlt ein namentlich geforderter
# Ordner im Archiv, wird das Paket abgelehnt.
if install_curated_package "MissingRequired" "Testpaket" "3.0.0" "file://$WILD_ARCHIVE" "$WILD_SHA" "TestMissing Test*"; then
    echo "Fehler: Paket ohne geforderten Ordner wurde akzeptiert." >&2
    exit 1
fi

# Standard-Vorwahlen: ohne gespeicherte Einstellung ist nur Pawn abgewaehlt.
if preference_enabled "ManagePawn"; then
    echo "Fehler: ManagePawn muss standardmaessig abgewaehlt sein." >&2
    exit 1
fi
preference_enabled "ManageDBM" || { echo "Fehler: ManageDBM muss standardmaessig gewaehlt sein." >&2; exit 1; }
preference_enabled "ManageGTFO" || { echo "Fehler: ManageGTFO muss standardmaessig gewaehlt sein." >&2; exit 1; }
preference_enabled "ManageBugSack" || { echo "Fehler: ManageBugSack muss standardmaessig gewaehlt sein." >&2; exit 1; }

echo "Alle Tests fuer kuratierte Anniversary-AddOns bestanden."

