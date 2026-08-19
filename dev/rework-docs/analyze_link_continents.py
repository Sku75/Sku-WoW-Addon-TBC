#!/usr/bin/env py -3
"""
analyze_link_continents.py - does the route link graph ever cross a continent?

Written 2026-08-19 for ROUTE-LINK-BUILD-PLAN.md (tier 3: can the link build be
partitioned per continent and the player's own continent be built first?).

Decodes the Links section of both shipped route files (wpId packing per
SkuNav:BuildWpIdFromData, same as decode_links_by_zone.py) and maps BOTH
endpoints of every directed edge to a ContinentID via SkuDB.InternalAreaTable
(Sku/SkuDB/assets/maps.lua, one line per area).

Reports per file: edge count, cross-continent edge count, the offending
zone pairs, and the share of edges per continent.

Result on 2026-08-19: 8 of 144,364 (Era) and 8 of 192,084 (WotLK) edges cross,
and all of them are a name collision - two areas are called "Valley of Bones",
2657 in Desolace (Kalimdor) and 3794 in Hellfire Peninsula (Outland); two
Outland waypoints carry the Kalimdor id. Genuine crossings: zero.

Usage: py -3 dev/rework-docs/analyze_link_continents.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPS = os.path.join(ROOT, "Sku", "SkuDB", "assets", "maps.lua")
FILES = (
    ("Era (routedata_global)", os.path.join(ROOT, "Sku", "SkuDB", "assets", "routedata_global.lua")),
    ("WotLK (routedata_global_wotlk)", os.path.join(ROOT, "Sku", "routedata_global_wotlk.lua")),
)

DBIB, ARIB = 20, 18          # dbIndexBits, areaIdBits (spawn takes the rest)
BASE2, BASE3 = 200000, 500000  # typeId bases: 1 custom, 2 creature, 3 object
CONT_NAME = {0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland", 571: "Northrend"}


def decode(wpid):
    spawn = wpid >> (DBIB + ARIB)
    area_id = (wpid - (spawn << (DBIB + ARIB))) >> DBIB
    db_index = wpid - (area_id << DBIB) - (spawn << (DBIB + ARIB))
    type_id = 1 if db_index < BASE2 else (2 if db_index < BASE3 else 3)
    return type_id, area_id


def read_areas():
    """areaId -> (ContinentID, ZoneName). InternalAreaTable is one line per area;
    commented-out rows (--[21] = ...) are skipped by the anchored match."""
    row = re.compile(r'^\[(\d+)\]\s*=\s*\{.*?ContinentID\s*=\s*(-?\d+)')
    name = re.compile(r'ZoneName\s*=\s*"([^"]*)"')
    cont, zone = {}, {}
    inside = False
    with open(MAPS, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            if not inside:
                if s.startswith("SkuDB.InternalAreaTable"):
                    inside = True
                continue
            if s.startswith("}"):
                break
            m = row.match(s)
            if m:
                a = int(m.group(1))
                cont[a] = int(m.group(2))
                n = name.search(s)
                if n:
                    zone[a] = n.group(1)
    return cont, zone


KEY_RE = re.compile(r"^\[(\d+)\]\s*=\s*\{")
EDGE_RE = re.compile(r"^\[(\d+)\]\s*=\s*(\d+),?$")
SECT_RE = re.compile(r'^\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')


def analyze(path, cont, zone):
    section, src_area = None, None
    edges = cross = unknown = sources = 0
    pairs, per_cont = {}, {}
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            m = SECT_RE.match(s)
            if m:
                section = m.group(1)
                continue
            if section != "Links":
                continue
            m = KEY_RE.match(s)
            if m:
                _, src_area = decode(int(m.group(1)))
                sources += 1
                continue
            m = EDGE_RE.match(s)
            if m and src_area is not None:
                _, tgt_area = decode(int(m.group(1)))
                edges += 1
                cs, ct = cont.get(src_area), cont.get(tgt_area)
                if cs is not None:
                    per_cont[cs] = per_cont.get(cs, 0) + 1
                if cs is None or ct is None:
                    unknown += 1
                elif cs != ct:
                    cross += 1
                    k = (cs, ct, zone.get(src_area, src_area), zone.get(tgt_area, tgt_area))
                    pairs[k] = pairs.get(k, 0) + 1
    return sources, edges, cross, unknown, pairs, per_cont


def main():
    cont, zone = read_areas()
    print("InternalAreaTable: %d areas with a ContinentID" % len(cont))
    for label, path in FILES:
        if not os.path.exists(path):
            print("\n%s: MISSING (%s)" % (label, path))
            continue
        sources, edges, cross, unknown, pairs, per_cont = analyze(path, cont, zone)
        print("\n%s" % label)
        print("  link sources: %d, directed edges: %d" % (sources, edges))
        print("  cross-continent edges: %d (%.4f%%), endpoints with unknown areaId: %d"
              % (cross, 100.0 * cross / max(edges, 1), unknown))
        for k, v in sorted(pairs.items(), key=lambda kv: -kv[1]):
            print("    cont %s -> %s   %s -> %s   x%d" % (k[0], k[1], k[2], k[3], v))
        print("  edge share per continent (source side):")
        for c, n in sorted(per_cont.items(), key=lambda kv: -kv[1]):
            print("    %-5s %-18s %7d  (%5.1f%%)" % (c, CONT_NAME.get(c, "?"), n, 100.0 * n / max(edges, 1)))


if __name__ == "__main__":
    main()
