#!/usr/bin/env python3
# Append a third frFR field to the packed route-name strings.
#
# Route names are positional: "<enUS>§<deDE>", split against Sku.Locs by
# SkuNav:LoadDefaultMapData. Sku.Locs is now {enUS, deDE, frFR}, so a third
# field lands in the French slot.
#
# The names are COMPOSED, not prose: semicolon-separated tokens that are mostly
# zone names, NPC/object names, and a small keyword vocabulary. So French is
# produced by translating token-by-token from the id-linked name tables - the
# same "import, never machine translate" rule as the rest of the game data.
# Anything unknown is left as the English token, which still reads correctly.
#
# Sources
#   zones   maps.lua enUS/deDE names, joined to the frFR dump by areaId
#   npcs    Sku enUS/deDE chunks joined to the generated frFR chunks by id
#   objects same, via deDE (the base objects file ships German chunks only)
#   items   same
#   keywords hand-written below
#
# Usage: py -3 dev/rework-docs/_gen_frfr_routenames.py [--write]

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SKU = os.path.join(REPO, "Sku")
ASSETS = os.path.join(SKU, "SkuDB", "assets")
SV = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
      r"\WTF\Account\1107979492#1\SavedVariables\Sku.lua")

ROUTE_FILES = [
    os.path.join(ASSETS, "routedata_global.lua"),
    os.path.join(SKU, "routedata_global_wotlk.lua"),
]

# Route jargon. These are Sku's own words, not game data, so they are the one
# part that genuinely has to be translated rather than imported.
KEYWORDS = {
    "auto": "auto",
    "passage": "passage",
    "from": "de",
    "to": "vers",
    "Quick Waypoint": "Point de passage rapide",
    "Inside": "Intérieur",
    "inside": "intérieur",
    "Outside": "Extérieur",
    "outside": "extérieur",
    "up": "haut",
    "down": "bas",
    "entrance": "entrée",
    "exit": "sortie",
    "Innkeepers": "Aubergistes",
    "Taxi": "Taxi",
    "Postbox": "Boîte aux lettres",
    "Zones": "Zones",
    "horde": "horde",
    "alliance": "alliance",
    "OBJECT": "OBJET",
    "s": "s", "h": "h", "a": "a",
    # Sku's own route jargon, seen in the coverage report
    "entry and exit": "entrée et sortie",
    "central location": "emplacement central",
    "centralpoint": "point central",
    "crossing": "traversée",
    "waters": "eaux",
    "quest target": "objectif de quête",
    "rescue": "sauvetage",
    "one": "un",
    "two": "deux",
    "three": "trois",
    "four": "quatre",
    "five": "cinq",
}

# DELIBERATELY NOT hand-translated: the WotLK zone names (Dragonblight,
# Grizzly Hills, Zul'Drak, The Storm Peaks, Icecrown, Dalaran, Wintergrasp,
# Plaguelands: The Scarlet Enclave, ...). They are missing because the dump came
# from a TBC Anniversary client, whose GetMapInfo has no WotLK map data - not
# because the method failed. Guessing them from memory would put wrong French
# into 20k route names; re-running /skudebug dumpmapnames on a French client
# once the timeline reaches WotLK fills them in correctly and for free. Until
# then they stay as readable English.

id_line = re.compile(r'^\s*\[(\d+)\]\s*=\s*(.*)$')


def dump_areas():
    """areaId -> French name, from SkuDebugLog.mapNameDump."""
    out = {}
    try:
        lines = io.open(SV, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return out
    start = None
    for i, l in enumerate(lines):
        if l.strip().startswith('["mapNameDump"] = {'):
            start = i
            break
    if start is None:
        return out
    depth, inareas = 0, False
    for l in lines[start:]:
        s = l.strip()
        if s.startswith('["areas"] = {'):
            inareas, depth = True, 1
            continue
        if inareas:
            depth += l.count("{") - l.count("}")
            m = id_line.match(l)
            if m:
                v = m.group(2).strip().rstrip(",").strip()
                if v.startswith('"') and v.endswith('"'):
                    out[int(m.group(1))] = v[1:-1]
            if depth <= 0:
                break
    return out


def dump_maps():
    """uiMapId -> French name, from the dump's ["maps"] block. This is the one
    that matters: GetMapInfo covers the top-level ZONES (Silverpine Forest,
    Blasted Lands, ...), which are what route names are built from. The
    ["areas"] block is sub-areas and misses nearly every zone."""
    out = {}
    try:
        lines = io.open(SV, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return out
    start = None
    for i, l in enumerate(lines):
        if l.strip().startswith('["mapNameDump"] = {'):
            start = i
            break
    if start is None:
        return out
    depth, inb = 0, False
    for l in lines[start:]:
        s2 = l.strip()
        if s2.startswith('["maps"] = {'):
            inb, depth = True, 1
            continue
        if inb:
            depth += l.count("{") - l.count("}")
            m = id_line.match(l)
            if m:
                v = m.group(2).strip().rstrip(",").strip()
                if v.startswith('"') and v.endswith('"'):
                    out[int(m.group(1))] = v[1:-1]
            if depth <= 0:
                break
    return out


def ext_map_names():
    """uiMapId -> (enUS, deDE) from SkuDB.ExternalMapID."""
    out = {}
    p = os.path.join(ASSETS, "maps.lua")
    for line in io.open(p, encoding="utf-8", errors="replace"):
        m = id_line.match(line)
        if not m or "Name_lang" not in line or "ParentExternalMapID" not in line:
            continue
        de = re.search(r'\["deDE"\]\s*=\s*"([^"]*)"', line)
        en = re.search(r'\["enUS"\]\s*=\s*"([^"]*)"', line)
        if de and en:
            out[int(m.group(1))] = (en.group(1), de.group(1))
    return out


def maps_names():
    """areaId -> (enUS, deDE) from maps.lua."""
    out = {}
    p = os.path.join(ASSETS, "maps.lua")
    for line in io.open(p, encoding="utf-8", errors="replace"):
        m = id_line.match(line)
        if not m or "AreaName_lang" not in line:
            continue
        de = re.search(r'\["deDE"\]\s*=\s*"([^"]*)"', line)
        en = re.search(r'\["enUS"\]\s*=\s*"([^"]*)"', line)
        if de and en:
            out[int(m.group(1))] = (en.group(1), de.group(1))
    return out


def chunk_names(path, table, first_only=True):
    """id -> name, from SkuDBChunks entries whose path == table."""
    out = {}
    if not os.path.exists(path):
        return out
    inchunk = False
    for line in io.open(path, encoding="utf-8", errors="replace"):
        if "SkuDBChunks[#SkuDBChunks+1]" in line:
            inchunk = ('"%s"' % table) in line
            line = line.split("[=[return {", 1)[-1] if "[=[return {" in line else ""
        if not inchunk:
            continue
        m = id_line.match(line)
        if not m:
            continue
        v = m.group(2).strip().rstrip(",").strip()
        if v.startswith('{'):
            q = re.match(r'\{\s*"((?:[^"\\]|\\.)*)"', v)
            if q:
                out[int(m.group(1))] = q.group(1)
        elif v.startswith('"'):
            q = re.match(r'"((?:[^"\\]|\\.)*)"', v)
            if q:
                out[int(m.group(1))] = q.group(1)
    return out


def build_map():
    """Any known source-language name -> French name."""
    tr = {}
    n_zone = n_npc = n_obj = n_item = 0

    # uiMap join FIRST - these are the top-level zones route names use.
    fr_maps = dump_maps()
    for mid, (en, de) in ext_map_names().items():
        fr = fr_maps.get(mid)
        if fr:
            tr.setdefault(en, fr)
            tr.setdefault(de, fr)
            n_zone += 1
    # then the finer areaId join for sub-areas
    fr_areas = dump_areas()
    for aid, (en, de) in maps_names().items():
        fr = fr_areas.get(aid)
        if fr:
            tr.setdefault(en, fr)
            tr.setdefault(de, fr)
            n_zone += 1

    def join(src_pairs, fr_pairs):
        n = 0
        for i, frname in fr_pairs.items():
            for src in src_pairs:
                nm = src.get(i)
                if nm:
                    tr.setdefault(nm, frname)
                    n = 1 if n == 0 else n + 1
        return len(fr_pairs)

    fam = [
        ("creatures", "NpcData.Names", "creatures_frFR.lua", "SkuDB.NpcData.Names.frFR"),
        ("objects", "objectLookup", "objects_frFR.lua", "SkuDB.objectLookup.frFR"),
        ("items", "itemLookup", "items_frFR.lua", "SkuDB.itemLookup.frFR"),
        ("quests", "questLookup", "quests_frFR.lua", "SkuDB.questLookup.frFR"),
    ]
    base = {"creatures": "creatures.lua", "objects": "objects.lua",
            "items": "items.lua", "quests": "quests.lua"}
    counts = {}
    for key, tbl, frfile, frtable in fam:
        srcs = []
        for pref, sub in (("SkuDB.", ""), ("SkuDB.WotLK.", "WotLK")):
            for loc in ("enUS", "deDE"):
                path = os.path.join(ASSETS, sub, base[key]) if sub else os.path.join(ASSETS, base[key])
                srcs.append(chunk_names(path, "%s%s.%s" % (pref, tbl, loc)))
        frs = {}
        for sub in ("", "WotLK"):
            d = os.path.join(ASSETS, sub, "frFR", frfile) if sub else os.path.join(ASSETS, "frFR", frfile)
            frs.update(chunk_names(d, frtable.replace("SkuDB.", "SkuDB.WotLK.") if sub else frtable))
        counts[key] = join(srcs, frs)

    for k, v in KEYWORDS.items():
        tr.setdefault(k, v)

    print("translation map: zones=%d  creatures=%d  objects=%d  items=%d  quests=%d  total keys=%d"
          % (n_zone, counts.get("creatures", 0), counts.get("objects", 0),
             counts.get("items", 0), counts.get("quests", 0), len(tr)))
    return tr


def translate_name(en, tr, stats):
    parts = en.split(";")
    out = []
    for p in parts:
        if p == "" or p.replace(".", "").replace("-", "").isdigit():
            out.append(p)
            continue
        fr = tr.get(p)
        if fr is None:
            fr = tr.get(p.strip())
        if fr is None and p.startswith("auto "):
            rest = tr.get(p[5:])
            if rest:
                fr = "auto " + rest
        if fr is None:
            stats["miss"][p] = stats["miss"].get(p, 0) + 1
            out.append(p)
        else:
            stats["hit"] += 1
            out.append(fr)
    return ";".join(out)


def main():
    write = "--write" in sys.argv
    tr = build_map()
    stats = {"hit": 0, "miss": {}}

    for path in ROUTE_FILES:
        if not os.path.exists(path):
            print("missing", path)
            continue
        n_names = n_third = 0
        out = []
        for line in io.open(path, encoding="utf-8", errors="replace"):
            s = line.strip()
            if s.startswith('["names"] = "') and s.endswith('",'):
                val = s[len('["names"] = "'):-2]
                fields = val.split("§")
                if len(fields) == 2:
                    n_names += 1
                    fr = translate_name(fields[0], tr, stats)
                    indent = line[:len(line) - len(line.lstrip())]
                    line = '%s["names"] = "%s§%s§%s",\n' % (indent, fields[0], fields[1], fr)
                    n_third += 1
            out.append(line)
        print("%-28s names=%6d  third field added=%6d" % (os.path.basename(path), n_names, n_third))
        if write:
            io.open(path, "w", encoding="utf-8", newline="\n").write("".join(out))

    miss = stats["miss"]
    total = stats["hit"] + sum(miss.values())
    print("\ntokens: %d translated, %d left English (%.1f%% covered), %d distinct misses"
          % (stats["hit"], sum(miss.values()),
             stats["hit"] / total * 100 if total else 0, len(miss)))
    print("top untranslated:")
    for k, v in sorted(miss.items(), key=lambda x: -x[1])[:25]:
        print("   %6d x  %s" % (v, k))
    if not write:
        print("\n(dry run - pass --write to rewrite the route files)")


if __name__ == "__main__":
    main()
