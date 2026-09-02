#!/bin/bash
# Sku Installer und Updater fuer macOS
# Benutzt nur Werkzeuge, die mit macOS geliefert werden.

set -u
set -o pipefail
export PATH="/usr/bin:/bin:/usr/sbin:/sbin"

APP_NAME="Sku Installer und Updater"
APP_VERSION="5.3.0"
REPO="Sku75/Sku-WoW-Addon-TBC"
FALLBACK_MAIN_VERSION="43.3"
COMPANION_TAG="v41.02.05"
MANIFEST_NAME="SkuInstall.json"
PREFERENCES_DOMAIN="org.sku-project.installer"
FORCE_INSTALL=0
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/SkuInstaller.XXXXXX")"
LOG_FILE="$HOME/Library/Logs/SkuInstaller.log"

mkdir -p "$(dirname "$LOG_FILE")"
touch "$LOG_FILE"

cleanup() {
    rm -rf "$TEMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
    printf '%s\n' "$*"
}

run_osascript() {
    /usr/bin/env LANG="de_DE.UTF-8" LC_ALL="de_DE.UTF-8" AppleLanguages="(de-DE)" \
        /usr/bin/osascript "$@"
}

speak() {
    log "$*"
    /usr/bin/say "$*" >/dev/null 2>&1 &
}

dialog() {
    run_osascript - "$1" <<'APPLESCRIPT'
on run argv
    display dialog (item 1 of argv) with title "Sku Installer und Updater" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
}

confirm() {
    run_osascript - "$1" <<'APPLESCRIPT'
on run argv
    display dialog (item 1 of argv) with title "Sku Installer und Updater" buttons {"Abbrechen", "Fortfahren"} default button "Fortfahren" cancel button "Abbrechen"
end run
APPLESCRIPT
}

choose_addons_folder() {
    run_osascript <<'APPLESCRIPT'
set picked to choose folder with prompt "Wähle den World-of-Warcraft-Ordner, den Ordner _anniversary_ oder Interface/AddOns."
POSIX path of picked
APPLESCRIPT
}

choose_language_pack() {
    run_osascript <<'APPLESCRIPT'
set packs to {"Deutsch", "Deutsch schnell", "Englisch"}
set picked to choose from list packs with title "Sku Installer und Updater" with prompt "Wähle genau ein Sprachausgabe-Paket:" default items {"Deutsch"} OK button name "Fortfahren" cancel button name "Abbrechen"
if picked is false then error number -128
item 1 of picked
APPLESCRIPT
}

choose_login_tool() {
    run_osascript <<'APPLESCRIPT'
display dialog "Soll das Hammerspoon-Login-Tool ebenfalls installiert werden? Hammerspoon muss auf dem Mac separat installiert und für Bedienungshilfen freigegeben sein." with title "Sku Installer und Updater" buttons {"Nein", "Ja"} default button "Ja"
button returned of result
APPLESCRIPT
}

normalize_addons_folder() {
    local picked="${1%/}"
    local candidate=""

    case "$picked" in
        */Interface/AddOns) candidate="$picked" ;;
        */Interface) candidate="$picked/AddOns" ;;
        */_anniversary_) candidate="$picked/Interface/AddOns" ;;
        */_classic_era_) candidate="$picked/Interface/AddOns" ;;
        *)
            if [ -d "$picked/_anniversary_" ]; then
                candidate="$picked/_anniversary_/Interface/AddOns"
            elif [ -d "$picked/_classic_era_" ]; then
                candidate="$picked/_classic_era_/Interface/AddOns"
            fi
            ;;
    esac

    case "$candidate" in
        */Interface/AddOns) printf '%s\n' "$candidate" ;;
        *) return 1 ;;
    esac
}

detect_addons_folders() {
    local candidates="
/Applications/World of Warcraft/_anniversary_/Interface/AddOns
/Applications/World of Warcraft/_classic_era_/Interface/AddOns
/Applications/World of Warcraft/_classic_/Interface/AddOns
/Applications/World of Warcraft/_retail_/Interface/AddOns
$HOME/Applications/World of Warcraft/_anniversary_/Interface/AddOns
$HOME/Applications/World of Warcraft/_classic_era_/Interface/AddOns
$HOME/Applications/World of Warcraft/_classic_/Interface/AddOns
$HOME/Applications/World of Warcraft/_retail_/Interface/AddOns"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        if [ -d "$path" ]; then
            printf '%s\n' "$path"
        fi
    done <<EOF
$candidates
EOF
}

flavor_name() {
    case "$1" in
        */_anniversary_/*) printf '%s\n' "Anniversary" ;;
        */_classic_era_/*) printf '%s\n' "Classic Era" ;;
        */_classic_/*) printf '%s\n' "Classic" ;;
        */_retail_/*) printf '%s\n' "Retail" ;;
        *) printf '%s\n' "Manueller Ordner" ;;
    esac
}

read_preference() {
    /usr/bin/defaults read "$PREFERENCES_DOMAIN" "$1" 2>/dev/null || true
}

write_preference() {
    /usr/bin/defaults write "$PREFERENCES_DOMAIN" "$1" -string "$2"
}

choose_detected_folder() {
    local folders="$1"
    run_osascript - "$folders" <<'APPLESCRIPT'
on run argv
    set rawFolders to item 1 of argv
    set oldDelimiters to AppleScript's text item delimiters
    set AppleScript's text item delimiters to linefeed
    set folderList to text items of rawFolders
    set AppleScript's text item delimiters to oldDelimiters
    set labels to {}
    repeat with p in folderList
        if p contains "/_anniversary_/" then
            set end of labels to "Anniversary — " & p
        else if p contains "/_classic_era_/" then
            set end of labels to "Classic Era — " & p
        else if p contains "/_classic_/" then
            set end of labels to "Classic — " & p
        else if p contains "/_retail_/" then
            set end of labels to "Retail — " & p
        else
            set end of labels to p
        end if
    end repeat
    set picked to choose from list labels with title "Sku Installer und Updater" with prompt "Wähle die WoW-Version:" OK button name "Auswählen" cancel button name "Abbrechen"
    if picked is false then error number -128
    set chosenLabel to item 1 of picked
    repeat with i from 1 to count labels
        if item i of labels is chosenLabel then return item i of folderList
    end repeat
end run
APPLESCRIPT
}

resolve_main_version() {
    local effective tag page official
    page="$(/usr/bin/curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://sku75.github.io/Sku-WoW-Addon-TBC/" 2>>"$LOG_FILE" || true)"
    official="$(printf '%s\n' "$page" | /usr/bin/sed -nE 's/.*Sku \(Main Addon\) - Version ([0-9]+([.][0-9]+)+).*/\1/p' | /usr/bin/head -n 1)"
    if [ -n "$official" ]; then
        printf '%s\n' "$official"
        return 0
    fi
    effective="$(/usr/bin/curl -LIsS --connect-timeout 10 --max-time 30 \
        -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>>"$LOG_FILE" || true)"
    tag="${effective##*/}"
    if printf '%s\n' "$tag" | /usr/bin/grep -Eq '^v[0-9]+([.][0-9]+)+$'; then
        printf '%s\n' "${tag#v}"
    else
        printf '%s\n' "$FALLBACK_MAIN_VERSION"
    fi
}

main_menu() {
    local flavor="$1" installed="$2" latest="$3" language="$4" login="$5" status login_label installed_spoken latest_spoken
    installed_spoken="$(printf '%s' "${installed:-nicht installiert}" | /usr/bin/sed 's/[.]/ Punkt /g')"
    latest_spoken="$(printf '%s' "$latest" | /usr/bin/sed 's/[.]/ Punkt /g')"
    if [ -n "$installed" ] && version_at_least "$installed" "$latest"; then
        status="Sku ist auf dem neuesten Stand. Installierte Version: $installed_spoken. Verfügbare Version: $latest_spoken."
    elif [ -n "$installed" ]; then
        status="Ein Update ist verfügbar. Installierte Version: $installed_spoken. Verfügbare Version: $latest_spoken."
    else
        status="Sku ist noch nicht installiert. Verfügbare Version: $latest_spoken."
    fi
    [ "$login" = "Ja" ] && login_label="aktiviert" || login_label="deaktiviert"
    run_osascript - "$flavor" "$status" "$language" "$login_label" <<'APPLESCRIPT'
on run argv
    set entries to {"Sku installieren oder aktualisieren", "WoW-Version wechseln", "AddOns-Ordner manuell auswählen", "Sprachpaket ändern — derzeit " & item 3 of argv, "Login-Tool umschalten — derzeit " & item 4 of argv, "Beenden"}
    set picked to choose from list entries with title "Sku Installer und Updater" with prompt ((item 2 of argv) & return & return & "Ausgewählte WoW-Version: " & (item 1 of argv)) default items {item 1 of entries} OK button name "Ausführen" cancel button name "Beenden"
    if picked is false then return "Beenden"
    return item 1 of picked
end run
APPLESCRIPT
}

manifest_tag() {
    local key="$1" manifest="$ADDONS_FOLDER/$MANIFEST_NAME"
    [ -f "$manifest" ] || return 0
    /usr/bin/sed -n 's/.*"'"$key"'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | /usr/bin/head -n 1
}

version_at_least() {
    local have="${1#v}" want="${2#v}"
    /usr/bin/awk -v have="$have" -v want="$want" 'BEGIN {
        nh=split(have,h,"."); nw=split(want,w,"."); n=(nh>nw?nh:nw)
        for(i=1;i<=n;i++) {
            hv=(i<=nh ? h[i]+0 : 0); wv=(i<=nw ? w[i]+0 : 0)
            if(hv>wv) exit 0
            if(hv<wv) exit 1
        }
        exit 0
    }'
}

installed_sku_version() {
    local toc="$ADDONS_FOLDER/Sku/Sku.toc"
    [ -f "$toc" ] || return 0
    /usr/bin/awk '
        /^[[:space:]]*##[[:space:]]*Version[[:space:]]*:/ {
            sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
        }
    ' "$toc"
}

validate_zip() {
    local zip="$1" listing
    listing="$(/usr/bin/unzip -Z1 "$zip" 2>>"$LOG_FILE")" || return 1
    [ -n "$listing" ] || return 1
    if printf '%s\n' "$listing" | /usr/bin/tr '\\' '/' | /usr/bin/grep -Eq '(^/|(^|/)\.\.(/|$)|^[A-Za-z]:)'; then
        log "Unsicherer Pfad im ZIP-Archiv erkannt."
        return 1
    fi
}

normalize_windows_zip_paths() {
    local staging="$1" path relative normalized target
    while IFS= read -r -d '' path; do
        relative="${path#"$staging/"}"
        case "$relative" in
            *\\*)
                normalized="$(printf '%s' "$relative" | /usr/bin/tr '\\' '/')"
                target="$staging/$normalized"
                mkdir -p "$(dirname "$target")" || return 1
                [ ! -e "$target" ] || { log "Doppelter Pfad nach ZIP-Normalisierung: $normalized"; return 1; }
                /bin/mv "$path" "$target" || return 1
                ;;
        esac
    done < <(/usr/bin/find "$staging" -type f -print0)
}

resolve_source_folder() {
    local staging="$1" folder="$2" first count
    if [ -d "$staging/$folder" ]; then
        printf '%s\n' "$staging/$folder"
        return 0
    fi
    count="$(find "$staging" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"
    first="$(find "$staging" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
    if [ "$count" = "1" ] && [ -n "$first" ]; then
        printf '%s\n' "$first"
    else
        printf '%s\n' "$staging"
    fi
}

install_package() {
    local folder="$1" asset="$2" tag="$3" label="$4"
    local current target zip staging source backup url
    current="$(manifest_tag "$folder")"
    target="$ADDONS_FOLDER/$folder"

    if [ -L "$target" ]; then
        log "$label: symbolischer Link erkannt; wird nicht veraendert."
        return 0
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ "$folder" = "Sku" ] && [ -d "$target" ]; then
        if [ -n "$current" ] && version_at_least "$current" "$tag"; then
            log "$label ist bereits gleich oder neuer als $tag ($current)."
            record_manifest "$folder" "$current"
            return 0
        fi
        if [ -z "$current" ]; then
            local toc_version
            toc_version="$(installed_sku_version)"
            if [ -n "$toc_version" ] && version_at_least "$toc_version" "$tag"; then
                log "$label wurde als vorhandene aktuelle Installation uebernommen ($toc_version)."
                record_manifest "$folder" "$tag"
                return 0
            fi
        fi
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ "$folder" != "Sku" ] && [ -d "$target" ] && [ -z "$current" ]; then
        log "$label wurde als vorhandene manuelle Installation uebernommen."
        record_manifest "$folder" "$tag"
        return 0
    fi
    if [ "$FORCE_INSTALL" != "1" ] && [ -d "$target" ] && [ "$current" = "$tag" ]; then
        log "$label ist bereits aktuell ($tag)."
        record_manifest "$folder" "$tag"
        return 0
    fi

    zip="$TEMP_ROOT/$asset"
    staging="$TEMP_ROOT/extract-$folder"
    url="https://github.com/$REPO/releases/download/$tag/$asset"
    speak "$label wird heruntergeladen."
    if ! /usr/bin/curl -fL --retry 3 --connect-timeout 15 --progress-bar \
        -o "$zip" "$url" 2>>"$LOG_FILE"; then
        log "Download fehlgeschlagen: $url"
        return 1
    fi
    if ! validate_zip "$zip"; then
        log "$label: Das heruntergeladene ZIP-Archiv ist ungueltig oder unsicher."
        return 1
    fi

    mkdir -p "$staging"
    speak "$label wird entpackt."
    if ! /usr/bin/ditto -x -k "$zip" "$staging" >>"$LOG_FILE" 2>&1; then
        log "$label konnte nicht entpackt werden."
        return 1
    fi
    normalize_windows_zip_paths "$staging" || return 1
    source="$(resolve_source_folder "$staging" "$folder")"
    [ -d "$source" ] || return 1

    backup="$ADDONS_FOLDER/.${folder}.old-$$"
    if [ -e "$backup" ]; then
        log "Unerwarteter Sicherungspfad existiert bereits: $backup"
        return 1
    fi
    if [ -d "$target" ]; then
        /bin/mv "$target" "$backup" || return 1
    fi
    if /usr/bin/ditto "$source" "$target" >>"$LOG_FILE" 2>&1; then
        rm -rf "$backup"
        record_manifest "$folder" "$tag"
        log "$label wurde installiert ($tag)."
        return 0
    fi

    log "$label: Installation fehlgeschlagen; vorherige Fassung wird wiederhergestellt."
    rm -rf "$target"
    if [ -d "$backup" ]; then /bin/mv "$backup" "$target"; fi
    return 1
}

preference_enabled() {
    [ "$(read_preference "$1")" != "Nein" ]
}

all_package_roots_exist() {
    local root
    for root in $1; do
        [ -d "$ADDONS_FOLDER/$root" ] || return 1
    done
}

package_root_allowed() {
    local candidate="$1" allowed="$2" root
    for root in $allowed; do
        [ "$candidate" = "$root" ] && return 0
    done
    return 1
}

install_curated_package() {
    local key="$1" label="$2" version="$3" url="$4" expected_sha="$5" roots="$6"
    local current zip staging actual root entry backup new_target failed=0
    current="$(manifest_tag "$key")"

    if [ "$FORCE_INSTALL" != "1" ] && [ "$current" = "$version" ] && all_package_roots_exist "$roots"; then
        log "$label ist bereits aktuell ($version)."
        record_manifest "$key" "$version"
        return 0
    fi

    zip="$TEMP_ROOT/curated-$key.zip"
    staging="$TEMP_ROOT/curated-$key"
    speak "$label wird von der offiziellen Quelle heruntergeladen."
    if ! /usr/bin/curl -fL --retry 3 --connect-timeout 15 --progress-bar -o "$zip" "$url" 2>>"$LOG_FILE"; then
        log "$label: Download fehlgeschlagen: $url"
        return 1
    fi
    actual="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$zip" | /usr/bin/awk '{print tolower($1)}')"
    if [ "$actual" != "$expected_sha" ]; then
        log "$label: SHA-256-Pruefsumme stimmt nicht. Erwartet $expected_sha, erhalten $actual."
        return 1
    fi
    validate_zip "$zip" || { log "$label: unsicheres oder ungueltiges ZIP-Archiv."; return 1; }

    while IFS= read -r entry; do
        [ -n "$entry" ] || continue
        package_root_allowed "$entry" "$roots" || {
            log "$label: unerwarteter oberster Archivordner: $entry"
            return 1
        }
    done <<EOF
$(/usr/bin/unzip -Z1 "$zip" | /usr/bin/awk -F/ 'NF {print $1}' | /usr/bin/sort -u)
EOF

    mkdir -p "$staging" || return 1
    /usr/bin/ditto -x -k "$zip" "$staging" >>"$LOG_FILE" 2>&1 || return 1
    if [ -n "$(/usr/bin/find "$staging" -type l -print -quit)" ]; then
        log "$label: symbolischer Link im Archiv erkannt; Paket wird abgelehnt."
        return 1
    fi
    for root in $roots; do
        [ -d "$staging/$root" ] || { log "$label: erwarteter Ordner $root fehlt."; return 1; }
        [ -n "$(/usr/bin/find "$staging/$root" -maxdepth 1 -type f -name '*.toc' -print -quit)" ] || {
            log "$label: $root enthaelt keine Add-on-TOC-Datei."
            return 1
        }
        [ ! -L "$ADDONS_FOLDER/$root" ] || { log "$label: $root ist ein symbolischer Link und wird nicht veraendert."; return 1; }
        backup="$ADDONS_FOLDER/.${root}.old-$$"
        new_target="$ADDONS_FOLDER/.${root}.new-$$"
        [ ! -e "$backup" ] && [ ! -e "$new_target" ] || { log "$label: unerwarteter Sicherungspfad fuer $root."; return 1; }
        /usr/bin/ditto "$staging/$root" "$new_target" >>"$LOG_FILE" 2>&1 || failed=1
        [ "$failed" = "0" ] || break
    done

    if [ "$failed" = "0" ]; then
        for root in $roots; do
            backup="$ADDONS_FOLDER/.${root}.old-$$"
            new_target="$ADDONS_FOLDER/.${root}.new-$$"
            if [ -d "$ADDONS_FOLDER/$root" ]; then /bin/mv "$ADDONS_FOLDER/$root" "$backup" || { failed=1; break; }; fi
            /bin/mv "$new_target" "$ADDONS_FOLDER/$root" || { failed=1; break; }
        done
    fi

    if [ "$failed" != "0" ]; then
        log "$label: Austausch fehlgeschlagen; vorherige Fassung wird wiederhergestellt."
        for root in $roots; do
            backup="$ADDONS_FOLDER/.${root}.old-$$"
            new_target="$ADDONS_FOLDER/.${root}.new-$$"
            [ -e "$new_target" ] && /bin/rm -rf "$new_target"
            if [ -d "$backup" ]; then
                [ -e "$ADDONS_FOLDER/$root" ] && /bin/rm -rf "$ADDONS_FOLDER/$root"
                /bin/mv "$backup" "$ADDONS_FOLDER/$root"
            fi
        done
        return 1
    fi

    for root in $roots; do
        backup="$ADDONS_FOLDER/.${root}.old-$$"
        [ -d "$backup" ] && /bin/rm -rf "$backup"
    done
    record_manifest "$key" "$version"
    log "$label wurde installiert ($version)."
}

github_release_asset() {
    local repo="$1" marker="$2" json="$TEMP_ROOT/github-${repo//\//-}.json" result version url digest
    local api_base="${SKU_GITHUB_API_BASE:-https://api.github.com}"
    if [ "$api_base" != "https://api.github.com" ] && [ "${SKU_INSTALLER_TEST_MODE:-0}" != "1" ]; then return 1; fi
    /usr/bin/curl -fsSL --retry 3 --connect-timeout 15 --max-time 45 \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2022-11-28' \
        "$api_base/repos/$repo/releases/latest" -o "$json" 2>>"$LOG_FILE" || return 1
    result="$(/usr/bin/osascript -l JavaScript - "$json" "$marker" <<'JXA'
function run(argv) {
    ObjC.import('Foundation');
    const path = $(argv[0]).stringByStandardizingPath;
    const data = $.NSData.dataWithContentsOfFile(path);
    if (!data) throw new Error('Release-Metadaten konnten nicht gelesen werden.');
    const text = $.NSString.alloc.initWithDataEncoding(data, $.NSUTF8StringEncoding).js;
    const release = JSON.parse(text);
    const marker = argv[1];
    const asset = (release.assets || []).find(a => a.name.indexOf(marker) >= 0 && /[.]zip$/i.test(a.name));
    if (!asset || !asset.digest) throw new Error('Passendes Release-ZIP oder Prüfsumme fehlt.');
    return [String(release.tag_name || '').replace(/^[^0-9]*/, ''), asset.browser_download_url || '', String(asset.digest).replace(/^sha256:/, '')].join('\n');
}
JXA
)" || return 1
    version="$(printf '%s\n' "$result" | /usr/bin/sed -n '1p')"
    url="$(printf '%s\n' "$result" | /usr/bin/sed -n '2p')"
    digest="$(printf '%s\n' "$result" | /usr/bin/sed -n '3p' | tr 'A-F' 'a-f')"
    printf '%s\n' "$version" | /usr/bin/grep -Eq '^[0-9]+([.][0-9A-Za-z_-]+)*$' || return 1
    case "$url" in "https://github.com/$repo/releases/download/"*) ;; *) return 1 ;; esac
    printf '%s\n' "$digest" | /usr/bin/grep -Eq '^[0-9a-f]{64}$' || return 1
    printf '%s\n%s\n%s\n' "$version" "$url" "$digest"
}

install_anniversary_addons() {
    local failures=0 release version url sha
    case "$ADDONS_FOLDER" in
        */_anniversary_/Interface/AddOns) ;;
        *) log "Kuratierte AddOns werden nur fuer Anniversary verwaltet."; return 0 ;;
    esac

    if preference_enabled "ManageQuestie"; then
        release="$(github_release_asset "Questie/Questie" "Questie-v" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="11.37.1"; url="https://edge.forgecdn.net/files/8742/429/Questie-v11.37.1.zip"; sha="450e09bd795ff25d5529abdb4b431d360e76d1097bb59992098bb39a907b8926"; }
        install_curated_package "CurseQuestie" "Questie" "$version" "$url" "$sha" \
            "Questie" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageAtlasLoot"; then
        install_curated_package "CurseAtlasLootAnniversary" "AtlasLootClassic Anniversary" "2.5.6.12334" \
            "https://edge.forgecdn.net/files/8721/161/AtlasLootClassic-Master_12334.zip" \
            "e286fa10bfe2a5ae15d405ebe65071caab386d1eb61cf9b25bad3ab6a9e1ad0d" \
            "AtlasLootClassic AtlasLootClassic_BiS AtlasLootClassic_Collections AtlasLootClassic_Crafting AtlasLootClassic_Data AtlasLootClassic_DungeonsAndRaids AtlasLootClassic_Factions AtlasLootClassic_Options AtlasLootClassic_PvP" || failures=$((failures + 1))
    fi
    if preference_enabled "ManageDetails"; then
        install_curated_package "CurseDetailsTBC" "Details Damage Meter" "20260707.15250.172_TBC" \
            "https://edge.forgecdn.net/files/8401/886/Details.20260707.15250.172_TBC.zip" \
            "9c16a88e153fd855fb2177aa23cc2a1110ede6928553c373706c946b6e10cb25" \
            "Details Details_Compare2 Details_DataStorage Details_EncounterDetails Details_RaidCheck Details_Streamer Details_TinyThreat Details_Vanguard" || failures=$((failures + 1))
    fi
    if preference_enabled "ManagePawn"; then
        release="$(github_release_asset "VgerMods/Pawn" "BurningCrusade" || true)"
        version="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"
        url="$(printf '%s\n' "$release" | /usr/bin/sed -n '2p')"
        sha="$(printf '%s\n' "$release" | /usr/bin/sed -n '3p')"
        [ -n "$version" ] || { version="2.13.15"; url="https://edge.forgecdn.net/files/8671/944/Pawn-2.13.15-BurningCrusade.zip"; sha="412a77ae5007aa00cf50ae91272f0af84262c63c0b70144906dedc0ab8d39750"; }
        install_curated_package "CursePawnTBC" "Pawn" "$version" "$url" "$sha" \
            "Pawn" || failures=$((failures + 1))
    fi
    return "$failures"
}

set_cvar_file() {
    local file="$1" name="$2" value="$3" tmp="$TEMP_ROOT/cvar-$$"
    local canonical="SET $name \"$value\""
    mkdir -p "$(dirname "$file")"
    if [ ! -f "$file" ]; then
        printf '%s\n' "$canonical" > "$file"
        log "Spieleinstellung gesetzt: $name = $value in $file"
        return 0
    fi
    /usr/bin/awk -v wanted="$name" -v replacement="$canonical" '
        BEGIN { found=0 }
        tolower($1) == "set" && tolower($2) == tolower(wanted) {
            if (!found) print replacement
            found=1
            next
        }
        { print }
        END { if (!found) print replacement }
    ' "$file" > "$tmp" || return 1
    if ! /usr/bin/cmp -s "$file" "$tmp"; then
        /usr/bin/ditto "$tmp" "$file" || return 1
        log "Spieleinstellung gesetzt: $name = $value in $file"
    fi
}

apply_game_settings() {
    local flavor_dir wtf account
    flavor_dir="$(cd "$ADDONS_FOLDER/../.." 2>/dev/null && pwd)" || return 0
    wtf="$flavor_dir/WTF"
    [ -d "$wtf" ] || { log "Kein WTF-Ordner vorhanden; Spieleinstellungen werden später gesetzt."; return 0; }
    set_cvar_file "$wtf/Config.wtf" "checkAddonVersion" "0" || return 1
    if [ -d "$wtf/Account" ]; then
        for account in "$wtf/Account"/*; do
            [ -d "$account" ] || continue
            [ "$(basename "$account")" = "SavedVariables" ] && continue
            set_cvar_file "$account/config-cache.wtf" "AllowDangerousScripts" "1" || return 1
        done
    fi
}

json_escape() {
    printf '%s' "$1" | /usr/bin/sed 's/\\/\\\\/g; s/"/\\"/g'
}

print_status_json() {
    local latest first=1 path installed flavor
    latest="$(resolve_main_version)"
    printf '{"installerVersion":"%s","latestSku":"%s","targets":[' "$APP_VERSION" "$latest"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        ADDONS_FOLDER="$path"
        installed="$(installed_sku_version)"
        flavor="$(flavor_name "$path")"
        [ "$first" = "1" ] || printf ','
        first=0
        printf '{"name":"%s","path":"%s","installed":"%s","hasSku":%s}' \
            "$(json_escape "$flavor")" "$(json_escape "$path")" "$(json_escape "$installed")" \
            "$([ -n "$installed" ] && printf true || printf false)"
    done <<EOF
$(detect_addons_folders)
EOF
    printf ']}\n'
}

toc_value() {
    local folder="$1" field="$2" file value
    while IFS= read -r file; do
        value="$(/usr/bin/awk -v wanted="$field" '
            BEGIN { IGNORECASE=1 }
            $0 ~ "^[[:space:]]*##[[:space:]]*" wanted "[[:space:]]*:" {
                sub(/^[^:]*:[[:space:]]*/, ""); gsub(/\r/, ""); print; exit
            }
        ' "$file")"
        [ -n "$value" ] && { printf '%s\n' "$value"; return 0; }
    done < <(/usr/bin/find "$ADDONS_FOLDER/$folder" -maxdepth 1 -type f -iname '*.toc' -print 2>/dev/null | /usr/bin/sort)
}

inventory_package_line() {
    local name="$1" roots="$2" version="" source="" source_id="" status="erkannt" root value
    while IFS= read -r root; do
        [ -n "$root" ] || continue
        [ -d "$ADDONS_FOLDER/$root" ] || continue
        [ -n "$version" ] || version="$(toc_value "$root" "Version" || true)"
        if [ -z "$source" ]; then
            value="$(toc_value "$root" "X-SkuInstaller-Provider" || true)"
            [ -n "$value" ] && source="$value"
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-SkuInstaller-Project" || true)"
            [ -n "$value" ] && source_id="$value"
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-Curse-Project-ID" || true)"
            [ -n "$value" ] && { source="CurseForge"; source_id="$value"; }
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-Wago-ID" || true)"
            [ -n "$value" ] && { source="Wago"; source_id="$value"; }
        fi
        if [ -z "$source_id" ]; then
            value="$(toc_value "$root" "X-WoWI-ID" || true)"
            [ -n "$value" ] && { source="WoWInterface"; source_id="$value"; }
        fi
    done <<EOF
$roots
EOF
    case "$name" in
        Sku)
            source="GitHub"
            source_id="$REPO"
            ;;
        "Sku AudioData"|"Sku Beacon Soundsets"|"Sku Custom Beacons")
            [ -n "$source" ] || source="GitHub"
            [ -n "$source_id" ] || source_id="$REPO"
            ;;
        Questie|AtlasLootClassic|"Details Damage Meter"|Pawn)
            [ -n "$source" ] || source="CurseForge"
            ;;
    esac
    [ -n "$version" ] || version="Version nicht angegeben"
    if [ -z "$source" ]; then source="Quelle unbekannt"; status="Zuordnung erforderlich"; fi
    case "$name" in *' '[0-9]*.[0-9]*) status="möglicher doppelter Ordner" ;; esac
    [ -n "$source_id" ] || source_id="-"
    printf '%s\t%s\t%s\t%s\t%s\n' "$name" "$version" "$source" "$source_id" "$status"
}

addon_inventory() {
    local selected records seen folder base roots name count=0 unknown=0 attention=0
    selected="${SKU_ADDONS_FOLDER_OVERRIDE:-$(read_preference "SelectedAddonsFolder")}"
    ADDONS_FOLDER="$(normalize_addons_folder "$selected" || true)"
    [ -n "$ADDONS_FOLDER" ] && [ -d "$ADDONS_FOLDER" ] || { printf 'Kein gültiger AddOns-Ordner ausgewählt.\n'; return 1; }
    records="$TEMP_ROOT/addon-inventory.tsv"
    seen="$TEMP_ROOT/addon-inventory-seen.txt"
    : > "$records"; : > "$seen"

    for folder in "$ADDONS_FOLDER"/*; do
        [ -d "$folder" ] && [ ! -L "$folder" ] || continue
        base="$(basename "$folder")"
        case "$base" in
            !BugGrabber|BugSack|GTFO) continue ;;
            Details|Details_*) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d -name 'Details*' -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="Details Damage Meter" ;;
            AtlasLootClassic|AtlasLootClassic_*) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d -name 'AtlasLootClassic*' -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="AtlasLootClassic" ;;
            SkuCustomBeaconsEssential|SkuCustomBeaconsAdditional) roots="$(printf '%s\n' SkuCustomBeaconsEssential SkuCustomBeaconsAdditional)"; name="Sku Custom Beacons" ;;
            Sku) roots="$(/usr/bin/find "$ADDONS_FOLDER" -mindepth 1 -maxdepth 1 -type d \( -name 'Sku' -o -name 'SkuAudioData*' \) -print | /usr/bin/sed 's#.*/##' | /usr/bin/sort)"; name="Sku" ;;
            SkuAudioData|SkuAudioData_en|SkuAudioData_fast_de) continue ;;
            SkuBeaconSoundsets) roots="$base"; name="Sku Beacon Soundsets" ;;
            *) roots="$base"; name="$base" ;;
        esac
        /usr/bin/grep -Fqx "$name" "$seen" 2>/dev/null && continue
        printf '%s\n' "$name" >> "$seen"
        inventory_package_line "$name" "$roots" >> "$records"
    done

    printf 'Installierte AddOns – %s\n\n' "$(flavor_name "$ADDONS_FOLDER")"
    while IFS=$'\t' read -r name version source source_id status; do
        count=$((count + 1))
        [ "$source" = "Quelle unbekannt" ] && unknown=$((unknown + 1))
        [ "$status" = "möglicher doppelter Ordner" ] && attention=$((attention + 1))
        printf '%d. %s\n   Version: %s\n   Quelle: %s' "$count" "$name" "$version" "$source"
        [ "$source_id" != "-" ] && printf ' – %s' "$source_id"
        printf '\n   Status: %s\n\n' "$status"
    done < <(/usr/bin/sort -f -t $'\t' -k1,1 "$records")
    printf 'Zusammenfassung: %d Pakete erkannt, %d ohne eindeutige Quelle, %d mögliche Dubletten.\n' "$count" "$unknown" "$attention"
}

addon_update_status_json() {
    local selected release questie pawn questie_current pawn_current atlas_current details_current
    selected="${SKU_ADDONS_FOLDER_OVERRIDE:-$(read_preference "SelectedAddonsFolder")}"
    ADDONS_FOLDER="$(normalize_addons_folder "$selected" || true)"
    [ -n "$ADDONS_FOLDER" ] && [ -d "$ADDONS_FOLDER" ] || return 1
    release="$(github_release_asset "Questie/Questie" "Questie-v" || true)"
    questie="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$questie" ] || questie="11.37.1"
    release="$(github_release_asset "VgerMods/Pawn" "BurningCrusade" || true)"
    pawn="$(printf '%s\n' "$release" | /usr/bin/sed -n '1p')"; [ -n "$pawn" ] || pawn="2.13.15"
    questie_current="$(manifest_tag "CurseQuestie")"
    atlas_current="$(manifest_tag "CurseAtlasLootAnniversary")"
    details_current="$(manifest_tag "CurseDetailsTBC")"
    pawn_current="$(manifest_tag "CursePawnTBC")"
    printf '{"Questie":{"latest":"%s","installed":"%s"},' "$(json_escape "$questie")" "$(json_escape "$questie_current")"
    printf '"AtlasLoot":{"latest":"2.5.6.12334","installed":"%s"},' "$(json_escape "$atlas_current")"
    printf '"Details":{"latest":"20260707.15250.172_TBC","installed":"%s"},' "$(json_escape "$details_current")"
    printf '"Pawn":{"latest":"%s","installed":"%s"}}\n' "$(json_escape "$pawn")" "$(json_escape "$pawn_current")"
}

collect_logs() {
    local out_dir="$HOME/Downloads" stamp staging path flavor root flavor_dir f
    stamp="$(date '+%Y%m%d-%H%M%S')"
    staging="$TEMP_ROOT/Sku-Diagnose-$stamp"
    mkdir -p "$staging"
    [ -f "$LOG_FILE" ] && /usr/bin/ditto "$LOG_FILE" "$staging/SkuInstaller.log"
    while IFS= read -r path; do
        [ -n "$path" ] || continue
        flavor="$(flavor_name "$path")"
        root="$staging/$flavor"
        mkdir -p "$root"
        [ -f "$path/Sku/Sku.toc" ] && /usr/bin/ditto "$path/Sku/Sku.toc" "$root/Sku.toc"
        [ -f "$path/$MANIFEST_NAME" ] && /usr/bin/ditto "$path/$MANIFEST_NAME" "$root/$MANIFEST_NAME"
        flavor_dir="$(cd "$path/../.." 2>/dev/null && pwd || true)"
        [ -f "$flavor_dir/WTF/Config.wtf" ] && /usr/bin/ditto "$flavor_dir/WTF/Config.wtf" "$root/Config.wtf"
        /usr/bin/find "$flavor_dir/WTF/Account" \( -path '*/SavedVariables/Sku.lua' -o -path '*/SavedVariables/!BugGrabber.lua' \) -type f 2>/dev/null | while IFS= read -r f; do
            /usr/bin/ditto "$f" "$root/$(basename "$(dirname "$(dirname "$f")")")-$(basename "$f")"
        done
        /usr/bin/find "$path" -mindepth 1 -maxdepth 1 -type d -print | /usr/bin/sed 's#.*/##' > "$root/addons.txt"
    done <<EOF
$(detect_addons_folders)
EOF
    mkdir -p "$out_dir"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$staging" "$out_dir/Sku-Diagnose-$stamp.zip"
    printf '%s\n' "$out_dir/Sku-Diagnose-$stamp.zip"
}

mac_installer_metadata() {
    /usr/bin/curl -fsSL --connect-timeout 10 --max-time 30 \
        "https://github.com/$REPO/releases/latest/download/installer-version-macos.txt"
}

version_is_newer() {
    /usr/bin/awk -v candidate="$1" -v current="$2" 'BEGIN {
        nc=split(candidate,c,"."); no=split(current,o,"."); n=(nc>no?nc:no);
        for(i=1;i<=n;i++){cv=(c[i]==""?0:c[i]+0); ov=(o[i]==""?0:o[i]+0); if(cv>ov)exit 0; if(cv<ov)exit 1}
        exit 1
    }'
}

replace_installed_app() {
    local source="$1" destination_dir target new backup
    destination_dir="${SKU_INSTALLER_APPLICATIONS_DIR:-/Applications}"
    target="$destination_dir/Sku Installer.app"
    new="$destination_dir/.Sku Installer.new-$$"
    backup="$destination_dir/.Sku Installer.backup-$$"

    if [ "${SKU_INSTALLER_TEST_MODE:-0}" = "1" ]; then
        /bin/rm -rf "$new" "$backup"
        /usr/bin/ditto "$source" "$new" || return 1
        [ ! -e "$target" ] || /bin/mv "$target" "$backup" || return 1
        if /bin/mv "$new" "$target"; then
            /bin/rm -rf "$backup"
            return 0
        fi
        /bin/rm -rf "$target"
        [ ! -e "$backup" ] || /bin/mv "$backup" "$target"
        return 1
    fi

    /usr/bin/osascript - "$source" "$target" "$new" "$backup" <<'APPLESCRIPT'
on run argv
    set sourcePath to item 1 of argv
    set targetPath to item 2 of argv
    set newPath to item 3 of argv
    set backupPath to item 4 of argv
    set qSource to quoted form of sourcePath
    set qTarget to quoted form of targetPath
    set qNew to quoted form of newPath
    set qBackup to quoted form of backupPath
    set commandText to "/bin/rm -rf " & qNew & " " & qBackup & " && /usr/bin/ditto " & qSource & " " & qNew & " && if [ -e " & qTarget & " ]; then /bin/mv " & qTarget & " " & qBackup & " || exit 1; fi; if /bin/mv " & qNew & " " & qTarget & "; then /bin/rm -rf " & qBackup & "; else result=$?; /bin/rm -rf " & qTarget & "; if [ -e " & qBackup & " ]; then /bin/mv " & qBackup & " " & qTarget & "; fi; exit $result; fi"
    do shell script commandText with administrator privileges
end run
APPLESCRIPT
}

self_update_check() {
    local metadata latest sha
    metadata="$(mac_installer_metadata 2>/dev/null || true)"
    latest="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==1 {sub(/^version=/,""); gsub(/^[vV]/,""); gsub(/\r/,""); print; exit}')"
    sha="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==2 {sub(/^sha256=/,""); gsub(/\r/,""); print tolower($1); exit}')"
    printf 'CURRENT=%s\nLATEST=%s\nSHA256=%s\n' "$APP_VERSION" "$latest" "$sha"
    if [ -n "$latest" ] && version_is_newer "$latest" "$APP_VERSION"; then printf 'AVAILABLE=1\n'; else printf 'AVAILABLE=0\n'; fi
}

self_update_apply() {
    local metadata latest expected zip stage app actual bundle team current_app expected_team installed_app
    metadata="$(mac_installer_metadata)" || return 1
    latest="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==1 {sub(/^version=/,""); gsub(/^[vV]/,""); gsub(/\r/,""); print; exit}')"
    expected="$(printf '%s\n' "$metadata" | /usr/bin/awk 'NR==2 {sub(/^sha256=/,""); gsub(/\r/,""); print tolower($1); exit}')"
    case "$expected" in [0-9a-f][0-9a-f]*) ;; *) log "Ungültige Prüfsumme für das Installer-Update."; return 1 ;; esac
    [ "${#expected}" -eq 64 ] || return 1
    zip="$TEMP_ROOT/Sku-Installer-macOS.zip"; stage="$TEMP_ROOT/self-update"; mkdir -p "$stage"
    /usr/bin/curl -fL --retry 3 --connect-timeout 15 \
        "https://github.com/$REPO/releases/latest/download/Sku-Installer-macOS.zip" -o "$zip" || return 1
    actual="$(env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$zip" | /usr/bin/awk '{print tolower($1)}')"
    [ "$actual" = "$expected" ] || { log "Prüfsumme des Installer-Updates stimmt nicht."; return 1; }
    /usr/bin/ditto -x -k "$zip" "$stage" || return 1
    app="$(/usr/bin/find "$stage" -maxdepth 2 -type d -name 'Sku Installer.app' -print -quit)"
    [ -n "$app" ] || return 1
    /usr/bin/codesign --verify --deep --strict "$app" || return 1
    bundle="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app/Contents/Info.plist" 2>/dev/null || true)"
    [ "$bundle" = "org.sku-project.installer" ] || return 1
    team="$(/usr/bin/codesign -dv --verbose=4 "$app" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
    current_app="$(cd "$SCRIPT_DIR/../.." 2>/dev/null && pwd || true)"
    expected_team="${SKU_EXPECTED_TEAM_ID:-$(/usr/bin/codesign -dv --verbose=4 "$current_app" 2>&1 | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')}"
    [ -n "$team" ] && [ "$team" != "not set" ] || { log "Das veröffentlichte Update besitzt keine Developer-ID-Signatur."; return 1; }
    [ -n "$expected_team" ] && [ "$team" = "$expected_team" ] || { log "Die Developer Team-ID des Updates stimmt nicht mit der installierten App überein."; return 1; }
    /usr/sbin/spctl --assess --type execute "$app" || { log "Das Installer-Update wurde von Gatekeeper nicht akzeptiert."; return 1; }
    replace_installed_app "$app" || return 1
    installed_app="${SKU_INSTALLER_APPLICATIONS_DIR:-/Applications}/Sku Installer.app"
    /usr/bin/codesign --verify --deep --strict "$installed_app" || return 1
    log "Installer wurde auf Version $latest aktualisiert."
    /usr/bin/open -a "$installed_app" >/dev/null 2>&1 &
}

MANIFEST_KEYS=""
MANIFEST_VALUES=""
record_manifest() {
    MANIFEST_KEYS="${MANIFEST_KEYS}${1}\n"
    MANIFEST_VALUES="${MANIFEST_VALUES}${2}\n"
}

save_manifest() {
    local out="$TEMP_ROOT/$MANIFEST_NAME" key value index=1 total
    total="$(printf '%b' "$MANIFEST_KEYS" | /usr/bin/sed '/^$/d' | wc -l | tr -d ' ')"
    {
        printf '{\n  "version": 1,\n  "addons": {\n'
        while IFS= read -r key && IFS= read -r value <&3; do
            [ -n "$key" ] || continue
            if [ "$index" -lt "$total" ]; then
                printf '    "%s": "%s",\n' "$key" "$value"
            else
                printf '    "%s": "%s"\n' "$key" "$value"
            fi
            index=$((index + 1))
        done < <(printf '%b' "$MANIFEST_KEYS") 3< <(printf '%b' "$MANIFEST_VALUES")
        printf '  }\n}\n'
    } > "$out"
    /usr/bin/ditto "$out" "$ADDONS_FOLDER/$MANIFEST_NAME"
}

interface_version() {
    local flavor_dir root flavor line=""
    flavor_dir="$(cd "$ADDONS_FOLDER/../.." 2>/dev/null && pwd)" || return 0
    root="$(cd "$flavor_dir/.." 2>/dev/null && pwd)" || return 0
    [ -f "$flavor_dir/.flavor.info" ] || return 0
    flavor="$(/usr/bin/awk 'NR > 1 && $0 !~ /!/ && NF {gsub(/\r/,""); print; exit}' "$flavor_dir/.flavor.info")"
    [ -f "$root/.build.info" ] || return 0
    line="$(/usr/bin/awk -F'|' -v wanted="$flavor" '
        NR==1 { for(i=1;i<=NF;i++){split($i,a,"!"); if(a[1]=="Product")p=i; if(a[1]=="Version")v=i} }
        NR>1 && p && v && $p==wanted {gsub(/\r/,"",$v); print $v; exit}' "$root/.build.info")"
    printf '%s\n' "$line" | /usr/bin/awk -F'.' 'NF >= 3 {printf "%d%02d%02d\n", $1, $2, $3}'
}

sync_toc() {
    local folder="$1"
    local desired="$2"
    local toc="$ADDONS_FOLDER/$folder/$folder.toc"
    local tmp
    [ -n "$desired" ] || return 0
    [ -f "$toc" ] || return 0
    [ -L "$ADDONS_FOLDER/$folder" ] && return 0
    tmp="$TEMP_ROOT/$folder.toc"
    /usr/bin/awk -v desired="$desired" '
        !done && $0 ~ /^[[:space:]]*##[[:space:]]*Interface[[:space:]]*:/ {
            sub(/^[[:space:]]*##[[:space:]]*Interface[[:space:]]*:[^\r\n]*/, "## Interface: " desired)
            done=1
        }
        { print }
    ' "$toc" > "$tmp"
    if ! /usr/bin/cmp -s "$toc" "$tmp"; then
        /usr/bin/ditto "$tmp" "$toc"
        log "$folder: Interface-Version auf $desired gesetzt."
    fi
}

install_login_tool() {
    local source="$SCRIPT_DIR/SkuLoginTool.lua" sense="$SCRIPT_DIR/SkuLoginSense" starter="$SCRIPT_DIR/StartSkuLoginTool.applescript" target_dir="$HOME/.hammerspoon"
    if [ ! -f "$source" ]; then
        log "SkuLoginTool.lua liegt nicht neben dem Installer und wurde daher nicht installiert."
        return 0
    fi
    mkdir -p "$target_dir"
    /usr/bin/ditto "$source" "$target_dir/SkuLoginTool.lua" || return 1
    if [ -f "$sense" ]; then
        /usr/bin/ditto "$sense" "$target_dir/SkuLoginSense" || return 1
        /bin/chmod 755 "$target_dir/SkuLoginSense" || return 1
    fi
    if [ ! -f "$target_dir/init.lua" ]; then
        printf 'dofile(hs.configdir .. "/SkuLoginTool.lua")\n' > "$target_dir/init.lua"
    elif ! /usr/bin/grep -Fq 'SkuLoginTool.lua' "$target_dir/init.lua"; then
        printf '\ndofile(hs.configdir .. "/SkuLoginTool.lua")\n' >> "$target_dir/init.lua"
    fi
    log "Hammerspoon-Login-Tool wurde unter $target_dir installiert."
    if [ -d "/Applications/Hammerspoon.app" ] && [ -f "$starter" ]; then
        /usr/bin/osascript "$starter" >>"$LOG_FILE" 2>&1 || {
            log "Hammerspoon konnte nicht automatisch neu geladen werden. Das Skript ist vollständig installiert."
            return 1
        }
        log "Hammerspoon wurde gestartet und die Sku-Konfiguration geladen."
    else
        log "Hammerspoon ist nicht unter /Applications installiert. Das Login-Tool wird beim nächsten Hammerspoon-Start geladen."
    fi
}

main() {
    local picked language login_choice main_version main_tag main_asset interface failures curated_failures action folders installed flavor headless
    headless="${1:-}"
    [ "$headless" = "--headless-update-force" ] && FORCE_INSTALL=1
    log "---- $APP_NAME $APP_VERSION gestartet ----"
    speak "Sku Installer und Updater wird gestartet."

    ADDONS_FOLDER="$(read_preference "SelectedAddonsFolder")"
    language="$(read_preference "LanguagePack")"
    login_choice="$(read_preference "LoginTool")"
    [ -n "$language" ] || language="Deutsch"
    [ "$login_choice" = "Ja" ] || login_choice="Nein"

    if [ -n "$ADDONS_FOLDER" ]; then
        ADDONS_FOLDER="$(normalize_addons_folder "$ADDONS_FOLDER" || true)"
        [ -d "$ADDONS_FOLDER" ] || ADDONS_FOLDER=""
    fi
    if [ -z "$ADDONS_FOLDER" ]; then
        folders="$(detect_addons_folders)"
        if [ -n "$folders" ]; then
            ADDONS_FOLDER="$(choose_detected_folder "$folders")" || exit 0
        else
            picked="$(choose_addons_folder)" || exit 0
            ADDONS_FOLDER="$(normalize_addons_folder "$picked" || true)"
        fi
    fi
    if [ -z "$ADDONS_FOLDER" ]; then
        dialog "Der ausgewählte Ordner ist keine erkannte WoW-Installation." >/dev/null
        exit 1
    fi
    mkdir -p "$ADDONS_FOLDER" || exit 1
    case "$ADDONS_FOLDER" in */Interface/AddOns) ;; *) exit 1 ;; esac
    write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
    write_preference "LanguagePack" "$language"
    write_preference "LoginTool" "$login_choice"

    main_version="$(resolve_main_version)"
    log "Neueste verwendete Sku-Version: $main_version"

    while true; do
        installed="$(installed_sku_version)"
        flavor="$(flavor_name "$ADDONS_FOLDER")"
        if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
            action="Sku installieren oder aktualisieren"
        else
            action="$(main_menu "$flavor" "$installed" "$main_version" "$language" "$login_choice")" || exit 0
        fi
        case "$action" in
            "Beenden") exit 0 ;;
            "WoW-Version wechseln")
                folders="$(detect_addons_folders)"
                picked="$(choose_detected_folder "$folders")" || continue
                ADDONS_FOLDER="$(normalize_addons_folder "$picked" || true)"
                write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
                ;;
            "AddOns-Ordner manuell auswählen")
                picked="$(choose_addons_folder)" || continue
                picked="$(normalize_addons_folder "$picked" || true)"
                if [ -n "$picked" ]; then
                    ADDONS_FOLDER="$picked"
                    mkdir -p "$ADDONS_FOLDER" || continue
                    write_preference "SelectedAddonsFolder" "$ADDONS_FOLDER"
                else
                    dialog "Der ausgewählte Ordner ist keine erkannte WoW-Installation." >/dev/null
                fi
                ;;
            Sprachpaket*)
                language="$(choose_language_pack)" || continue
                write_preference "LanguagePack" "$language"
                ;;
            Login-Tool*)
                if [ "$login_choice" = "Ja" ]; then login_choice="Nein"; else login_choice="Ja"; fi
                write_preference "LoginTool" "$login_choice"
                speak "Login Tool $([ "$login_choice" = "Ja" ] && printf aktiviert || printf deaktiviert)."
                ;;
            "Sku installieren oder aktualisieren")
                if [ "$headless" != "--headless-update" ] && [ "$headless" != "--headless-update-force" ] && ! confirm "World of Warcraft muss geschlossen sein.\n\nWoW-Version: $flavor\nInstallationsordner:\n$ADDONS_FOLDER\n\nSprachpaket: $language\n\nJetzt installieren oder aktualisieren?" >/dev/null 2>&1; then continue; fi
                if /usr/bin/pgrep -if 'World of Warcraft|WowClassic' >/dev/null 2>&1; then
                    dialog "World of Warcraft läuft noch. Bitte beende das Spiel vollständig." >/dev/null
                    continue
                fi
                failures=0
                apply_game_settings || failures=$((failures + 1))
                MANIFEST_KEYS=""
                MANIFEST_VALUES=""
                main_tag="v$main_version"
                main_asset="Sku-$main_version.zip"
                install_package "Sku" "$main_asset" "$main_tag" "Sku" || failures=$((failures + 1))
                install_package "SkuBeaconSoundsets" "SkuBeaconSoundsets.zip" "$COMPANION_TAG" "Beacon Soundsets" || failures=$((failures + 1))
                install_package "SkuCustomBeaconsEssential" "SkuCustomBeaconsEssential.zip" "$COMPANION_TAG" "Wesentliche Custom Beacons" || failures=$((failures + 1))
                install_package "SkuCustomBeaconsAdditional" "SkuCustomBeaconsAdditional.zip" "$COMPANION_TAG" "Zusaetzliche Custom Beacons" || failures=$((failures + 1))
                case "$language" in
                    "Englisch") install_package "SkuAudioData_en" "SkuAudioData_en.zip" "$COMPANION_TAG" "Englisches Sprachpaket" || failures=$((failures + 1)) ;;
                    "Deutsch schnell") install_package "SkuAudioData_fast_de" "SkuAudioData_fast_de.zip" "$COMPANION_TAG" "Schnelles deutsches Sprachpaket" || failures=$((failures + 1)) ;;
                    *) install_package "SkuAudioData" "SkuAudioData.zip" "$COMPANION_TAG" "Deutsches Sprachpaket" || failures=$((failures + 1)) ;;
                esac
                install_anniversary_addons
                curated_failures=$?
                failures=$((failures + curated_failures))
                save_manifest
                interface="$(interface_version || true)"
                sync_toc "Sku" "$interface"
                sync_toc "SkuBeaconSoundsets" "$interface"
                sync_toc "SkuCustomBeaconsEssential" "$interface"
                sync_toc "SkuCustomBeaconsAdditional" "$interface"
                case "$language" in
                    "Englisch") sync_toc "SkuAudioData_en" "$interface" ;;
                    "Deutsch schnell") sync_toc "SkuAudioData_fast_de" "$interface" ;;
                    *) sync_toc "SkuAudioData" "$interface" ;;
                esac
                if [ "$login_choice" = "Ja" ]; then install_login_tool || failures=$((failures + 1)); fi
                if [ "$failures" -eq 0 ]; then
                    speak "Sku wurde erfolgreich installiert oder aktualisiert."
                    if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
                        printf '%s\n' "Sku wurde erfolgreich installiert oder aktualisiert."
                        exit 0
                    fi
                    dialog "Sku wurde erfolgreich installiert oder aktualisiert.\n\nProtokoll: $LOG_FILE" >/dev/null
                else
                    speak "Die Installation wurde mit Fehlern beendet."
                    if [ "$headless" = "--headless-update" ] || [ "$headless" = "--headless-update-force" ]; then
                        printf '%s\n' "Die Installation wurde mit $failures Fehlern beendet."
                        exit 1
                    fi
                    dialog "Die Installation wurde mit $failures Fehlern beendet.\n\nProtokoll: $LOG_FILE" >/dev/null
                fi
                ;;
        esac
    done
}

case "${1:-}" in
    --status-json) print_status_json; exit $? ;;
    --addon-inventory) addon_inventory; exit $? ;;
    --addon-update-status) addon_update_status_json; exit $? ;;
    --collect-logs) collect_logs; exit $? ;;
    --self-update-check) self_update_check; exit $? ;;
    --self-update) self_update_apply; exit $? ;;
esac

if [ "${SKU_INSTALLER_TEST_MODE:-0}" != "1" ]; then
    main "$@" || {
        status=$?
        log "Unerwarteter interner Fehler (Status $status)."
        dialog "Der Installer wurde wegen eines internen Fehlers beendet.\n\nBitte sende fuer die Diagnose diese Datei:\n$LOG_FILE" >/dev/null 2>&1 || true
        exit "$status"
    }
fi
