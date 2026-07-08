#!/usr/bin/env py -3
"""
decode_links_by_zone.py — bucket the Links section of a route file by the source
waypoint's areaId, to measure real navigation connectivity per zone.

wpId packing (SkuNav:BuildWpIdFromData, Core.lua):
  dbIndexBits=20, areaIdBits=18, spawnBits=10
  wpId = dbIndex + base + (areaId << 20) + (spawn << 38)
  base: typeId1 custom=0, typeId2 creature=200000, typeId3 object=500000
Decode:
  spawn  = wpId >> 38
  areaId = (wpId - (spawn<<38)) >> 20
  dbIndex= wpId - (areaId<<20) - (spawn<<38)   (typeId from dbIndex vs bases)

Reports, per dataset: for a focus areaId, how many link edges have their SOURCE
in that zone, split by endpoint typeId (1=custom route wp, 2=creature, 3=object),
plus zone totals.
Usage: py -3 decode_links_by_zone.py [focusAreaId]
"""
import re, sys, os

ROOT = r"C:\Users\fabia\Dev\Sku-TBC-42"
FILES = {
    "Era":       r"old-addon-versions/SkuAddon Era/SkuDB/assets/routedata_global.lua",
    "WotLK-end": r"old-addon-versions/SkuAddon LK/Sku/SkuDB/assets/routedata_global.lua",
}
DBIB, ARIB = 20, 18
BASE2, BASE3 = 200000, 500000

KEY_RE   = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{')          # source wpId opening a link table
EDGE_RE  = re.compile(r'^\s*\[(\d+)\]\s*=\s*(\d+),?\s*$')  # neighborWpId = distance
SECT_RE  = re.compile(r'^\s*\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')

def decode(wpid):
    spawn = wpid >> (DBIB + ARIB)
    areaId = (wpid - (spawn << (DBIB + ARIB))) >> DBIB
    dbIndex = wpid - (areaId << DBIB) - (spawn << (DBIB + ARIB))
    if dbIndex < BASE2:
        typeId = 1
    elif dbIndex < BASE3:
        typeId = 2
    else:
        typeId = 3
    return typeId, areaId

def analyze(path, focus):
    section = None
    in_link_table = False
    cur_src_area = None
    cur_src_type = None
    # per-zone: source-count, edge-count; for focus zone: edges split by neighbor typeId
    zone_srcs = {}
    zone_edges = {}
    focus_src_by_type = {1: 0, 2: 0, 3: 0}
    focus_edge_by_neighbor_type = {1: 0, 2: 0, 3: 0}
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = SECT_RE.match(line)
            if m:
                section = m.group(1)
                in_link_table = False
                continue
            if section != "Links":
                continue
            # a line like "[wpid] = {" opens a source's neighbor table
            k = KEY_RE.match(line)
            if k:
                src = int(k.group(1))
                t, a = decode(src)
                cur_src_area, cur_src_type = a, t
                in_link_table = True
                zone_srcs[a] = zone_srcs.get(a, 0) + 1
                if a == focus:
                    focus_src_by_type[t] = focus_src_by_type.get(t, 0) + 1
                continue
            e = EDGE_RE.match(line)
            if e and in_link_table and cur_src_area is not None:
                nbr = int(e.group(1))
                nt, na = decode(nbr)
                zone_edges[cur_src_area] = zone_edges.get(cur_src_area, 0) + 1
                if cur_src_area == focus:
                    focus_edge_by_neighbor_type[nt] = focus_edge_by_neighbor_type.get(nt, 0) + 1
    return zone_srcs, zone_edges, focus_src_by_type, focus_edge_by_neighbor_type

def load_zone_meta():
    """areaId -> (name, continentId) from maps.lua."""
    ZONE_RE = re.compile(
        r'^\s*\[(\d+)\]\s*=\s*\{ZoneName\s*=\s*"[^"]*".*?\["enUS"\]\s*=\s*"([^"]*)".*?ContinentID\s*=\s*(\d+)')
    meta = {}
    with open(os.path.join(ROOT, r"Sku/SkuDB/assets/maps.lua"), encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = ZONE_RE.match(line)
            if m:
                meta[int(m.group(1))] = (m.group(2), int(m.group(3)))
    return meta

CONT = {0: "EK", 1: "Kalimdor", 530: "Outland", 571: "Northrend", 609: "DK-phase"}

def main():
    meta = load_zone_meta()
    per = {}
    for label, rel in FILES.items():
        p = os.path.join(ROOT, rel)
        srcs, edges, _, _ = analyze(p, -1)
        per[label] = edges  # areaId -> edge count
    # per-continent totals
    print("=== link EDGES per continent (Era vs WotLK-end) ===")
    conts = {}
    for label, edges in per.items():
        for aid, c in edges.items():
            cont = meta.get(aid, ("?", -1))[1]
            conts.setdefault(cont, {}).setdefault(label, 0)
            conts[cont][label] += c
    for cont in sorted(conts, key=lambda c: -sum(conts[c].values())):
        e = conts[cont].get("Era", 0); w = conts[cont].get("WotLK-end", 0)
        print(f"  {CONT.get(cont, 'cont'+str(cont)):9s}  Era={e:7d}  WotLK={w:7d}  (WotLK-Era={w-e:+d})")

    print("\n=== OUTLAND + TBC-added zones: per-zone edges (Era / WotLK) ===")
    # Outland (530) plus BE/Draenei starting zones live on EK(0)/Kalimdor(1) but are TBC content
    tbc_added = {3430:"Eversong Woods",3433:"Ghostlands",3524:"Azuremyst Isle",3525:"Bloodmyst Isle",
                 3487:"Silvermoon City",3557:"The Exodar",4080:"Isle of Quel'Danas"}
    outland = sorted([a for a in set(list(per['Era'])+list(per['WotLK-end'])) if meta.get(a,('',-1))[1]==530])
    for aid in outland + list(tbc_added):
        e = per['Era'].get(aid, 0); w = per['WotLK-end'].get(aid, 0)
        nm = meta.get(aid, (tbc_added.get(aid,'?'), -1))[0]
        flag = "  <-- Era EMPTY" if e == 0 and w > 0 else ""
        print(f"  {aid:6d} {nm:22s} Era={e:6d}  WotLK={w:6d}{flag}")

if __name__ == "__main__":
    main()
