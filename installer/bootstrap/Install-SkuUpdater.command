#!/bin/bash
set -euo pipefail

base="https://github.com/Sku75/Sku-WoW-Addon-TBC/releases/latest/download"
temp="$(mktemp -d "${TMPDIR:-/tmp}/SkuSetup.XXXXXX")"
trap 'rm -rf "$temp"' EXIT HUP INT TERM

metadata="$temp/installer-version-macos.txt"
archive="$temp/Sku-Installer-macOS.zip"
stage="$temp/stage"

printf '%s\n' 'Sku Updater fuer macOS wird heruntergeladen.'
/usr/bin/curl -fL --retry 3 --connect-timeout 15 "$base/installer-version-macos.txt" -o "$metadata"
/usr/bin/curl -fL --retry 3 --connect-timeout 15 "$base/Sku-Installer-macOS.zip" -o "$archive"

expected="$(/usr/bin/awk 'NR==2 {sub(/^sha256=/, ""); gsub(/\r/, ""); print tolower($1); exit}' "$metadata")"
published_version="$(/usr/bin/awk 'NR==1 {sub(/^version=/, ""); gsub(/^[vV]/, ""); gsub(/\r/, ""); print; exit}' "$metadata")"
case "$expected" in
  [0-9a-f][0-9a-f]*) ;;
  *) printf '%s\n' 'Die veroeffentlichte SHA-256-Pruefsumme fehlt oder ist ungueltig.' >&2; exit 1 ;;
esac
[ "${#expected}" -eq 64 ] || { printf '%s\n' 'Die SHA-256-Pruefsumme hat eine ungueltige Laenge.' >&2; exit 1; }
actual="$(/usr/bin/shasum -a 256 "$archive" | /usr/bin/awk '{print tolower($1)}')"
[ "$actual" = "$expected" ] || { printf '%s\n' 'Die SHA-256-Pruefsumme des macOS-Installers stimmt nicht.' >&2; exit 1; }

mkdir -p "$stage"
/usr/bin/ditto -x -k "$archive" "$stage"
app="$(/usr/bin/find "$stage" -maxdepth 2 -type d -name 'Sku Installer.app' -print -quit)"
[ -n "$app" ] || { printf '%s\n' 'Das Archiv enthaelt keine Sku Installer App.' >&2; exit 1; }
/usr/bin/codesign --verify --deep --strict "$app"
bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist")"
[ "$bundle" = 'org.sku-project.installer' ] || { printf '%s\n' 'Die Bundle-ID des Installers ist ungueltig.' >&2; exit 1; }
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
[ -n "$published_version" ] && [ "$app_version" = "$published_version" ] || { printf '%s\n' 'Die App-Version stimmt nicht mit den Release-Metadaten ueberein.' >&2; exit 1; }

source_path="$app" /usr/bin/osascript <<'APPLESCRIPT'
set sourcePath to system attribute "source_path"
set commandText to "/usr/bin/ditto " & quoted form of sourcePath & " " & quoted form of "/Applications/Sku Installer.app"
do shell script commandText with administrator privileges
APPLESCRIPT

/usr/bin/codesign --verify --deep --strict '/Applications/Sku Installer.app'
/usr/bin/open -a '/Applications/Sku Installer.app'
printf '%s\n' 'Sku Installer wurde installiert. Falls macOS den ersten Start blockiert, waehle in Datenschutz und Sicherheit die Option Dennoch oeffnen.'
