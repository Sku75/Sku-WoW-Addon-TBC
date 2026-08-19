#!/usr/bin/env py -3
"""
analyze_link_build_assumptions.py - verify the assumptions ROUTE-LINK-BUILD-PLAN
tier 1 + tier 3 rest on, against the shipped route data.

Written 2026-08-19, before implementing tiers 1+3. Answers four questions the
plan leaves as reasoning:

 1. DUPLICATE CUSTOM WAYPOINT NAMES. The cache keys everything by NAME
    (WaypointCacheLookupAll, last index wins). Where two custom waypoints share
    a name, the link table's source id and the cache's canonical id diverge -
    that is the ONLY case in which pass 3 (SaveLinkDataToProfile, the re-derive)
    changes the link table at all. If the number is 0, skipping pass 3 in the
    build is a provable no-op.
 2. ASYMMETRIC EDGES. How much work pass 1's symmetrisation actually does.
 3. CROSS-CONTINENT EDGES - re-confirmed here for the merged TBC union, not per
    file (analyze_link_continents.py did the per-file view).
 4. CLEANUP ORDERING RISK (tier 3 step 3): custom waypoints that are reachable
    ONLY by an INBOUND edge from another continent. Those are the waypoints a
    per-continent cleanup could delete before their links arrive.

Usage: py -3 dev/rework-docs/analyze_link_build_assumptions.py
"""
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MAPS = os.path.join(ROOT, "Sku", "SkuDB", "assets", "maps.lua")
ERA = os.path.join(ROOT, "Sku", "SkuDB", "assets", "routedata_global.lua")
WOTLK = os.path.join(ROOT, "Sku", "routedata_global_wotlk.lua")

DBIB, ARIB = 20, 18
BASE2, BASE3 = 200000, 500000
LOC_INDEX = 1  # deDE = second §-field (Sku.Locs = enUS, deDE, frFR)

SECT_RE = re.compile(r'^\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')
KEY_RE = re.compile(r"^\[(\d+)\]\s*=\s*\{")
EDGE_RE = re.compile(r"^\[(\d+)\]\s*=\s*(\d+),?$")
NAMES_RE = re.compile(r'^\["names"\]\s*=\s*"(.*)",?$')
AREA_RE = re.compile(r'^\["areaId"\]\s*=\s*(\d+),?$')
CONT_RE = re.compile(r'^\["contintentId"\]\s*=\s*(-?\d+),?$')


def decode(wpid):
    spawn = wpid >> (DBIB + ARIB)
    area_id = (wpid - (spawn << (DBIB + ARIB))) >> DBIB
    db_index = wpid - (area_id << DBIB) - (spawn << (DBIB + ARIB))
    type_id = 1 if db_index < BASE2 else (2 if db_index < BASE3 else 3)
    return type_id, db_index, spawn, area_id


def read_areas():
    row = re.compile(r'^\[(\d+)\]\s*=\s*\{.*?ContinentID\s*=\s*(-?\d+)')
    cont = {}
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
                cont[int(m.group(1))] = int(m.group(2))
    return cont


def read_waypoints(path):
    """array index (1-based, ipairs order) -> dict(name, areaId, cont, dead).
    Tombstones ({false}) keep their slot. Brace-depth counting (the elements
    contain nested tables like lComments), strings stripped first so a brace
    inside a name cannot shift the depth."""
    wps = []
    section = None
    depth = 0
    cur = None
    strip_str = re.compile(r'"[^"]*"')
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            m = SECT_RE.match(s)
            if m:
                section = m.group(1)
                depth = 0
                continue
            if section != "WaypointsNew":
                continue
            bare = strip_str.sub('""', s)
            opens, closes = bare.count("{"), bare.count("}")
            if depth == 0 and opens == 0 and closes > 0:
                section = None          # closing brace of the section itself
                continue
            if depth == 0 and opens > 0:
                cur = {"name": None, "areaId": None, "cont": None, "dead": False}
            if depth >= 1 and cur is not None:
                if s == "false," or s == "[1] = false,":
                    cur["dead"] = True
                else:
                    m = NAMES_RE.match(s)
                    if m:
                        fields = m.group(1).split("§")
                        cur["name"] = fields[LOC_INDEX] if len(fields) > LOC_INDEX and fields[LOC_INDEX] else fields[0]
                    else:
                        m = AREA_RE.match(s)
                        if m:
                            cur["areaId"] = int(m.group(1))
                        else:
                            m = CONT_RE.match(s)
                            if m:
                                cur["cont"] = int(m.group(1))
            depth += opens - closes
            if depth == 0 and cur is not None:
                wps.append(cur)
                cur = None
    return wps


def read_links(path):
    """source id -> {target id: distance}"""
    links = {}
    section = None
    src = None
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            s = line.strip()
            m = SECT_RE.match(s)
            if m:
                section = m.group(1)
                src = None
                continue
            if section != "Links":
                continue
            m = KEY_RE.match(s)
            if m:
                src = int(m.group(1))
                links.setdefault(src, {})
                continue
            if src is not None:
                m = EDGE_RE.match(s)
                if m:
                    links[src][int(m.group(1))] = int(m.group(2))
    return links


def main():
    cont_of_area = read_areas()
    print("reading Era waypoints ...")
    wps = read_waypoints(ERA)
    print("  array slots:", len(wps))

    # cache build: custom pass, ipairs order, name -> index (last wins)
    name_last = {}
    id_of_index = {}
    index_of_id = {}
    alive = 0
    for i, w in enumerate(wps, start=1):
        if w is None or w["dead"] or not w["name"] or w["cont"] is None:
            continue
        alive += 1
        name_last[w["name"]] = i
        area = w["areaId"] or 1
        wpid = i + (area << DBIB) + (1 << (DBIB + ARIB))
        id_of_index[i] = wpid
        index_of_id[wpid] = i
    print("  live custom waypoints:", alive)
    dup_names = {n: 0 for n in name_last}
    for i, w in enumerate(wps, start=1):
        if w is None or w["dead"] or not w["name"] or w["cont"] is None:
            continue
        dup_names[w["name"]] += 1
    dupes = {n: c for n, c in dup_names.items() if c > 1}
    print("  names shared by >1 live custom waypoint:", len(dupes),
          "(waypoints involved:", sum(dupes.values()), ")")

    print("reading links ...")
    era = read_links(ERA)
    wotlk = read_links(WOTLK)
    # LoadDefaultMapData's TBC union: WotLK wins, Era adds what is missing
    union = {s: dict(t) for s, t in wotlk.items()}
    for s, targets in era.items():
        dst = union.setdefault(s, {})
        for t, d in targets.items():
            dst.setdefault(t, d)
    edges = sum(len(t) for t in union.values())
    print("  union: %d sources, %d directed edges" % (len(union), edges))

    # ---- 1. divergence: link sources whose canonical cache id differs
    div_sources = 0
    resolvable_sources = 0
    stale_sources = 0
    for s in union:
        idx = index_of_id.get(s)
        if idx is None:
            stale_sources += 1
            continue
        resolvable_sources += 1
        if name_last.get(wps[idx - 1]["name"]) != idx:
            div_sources += 1
    print("\n1) pass 3 (re-derive) relevance")
    print("   link sources resolvable in the cache:", resolvable_sources)
    print("   stale sources (id not in the cache) :", stale_sources)
    print("   DIVERGENT sources (duplicate name)  :", div_sources)

    # ---- 2. asymmetry
    missing_back = 0
    self_links = 0
    for s, targets in union.items():
        for t in targets:
            if t == s:
                self_links += 1
                continue
            back = union.get(t)
            if back is None or s not in back:
                missing_back += 1
    print("\n2) symmetrisation work (pass 1)")
    print("   self links          :", self_links)
    print("   missing back edges  :", missing_back, "(%.2f%% of %d)" % (100.0 * missing_back / max(edges, 1), edges))

    # ---- 3. cross-continent edges in the union
    def cont_of_id(wpid):
        idx = index_of_id.get(wpid)
        if idx is None:
            return None
        w = wps[idx - 1]
        if w["cont"] is not None:
            return w["cont"]
        return cont_of_area.get(w["areaId"])

    cross = 0
    for s, targets in union.items():
        cs = cont_of_id(s)
        if cs is None:
            continue
        for t in targets:
            ct = cont_of_id(t)
            if ct is not None and ct != cs:
                cross += 1
    print("\n3) cross-continent edges in the TBC union:", cross)

    # ---- 4. inbound-only waypoints (the per-continent cleanup risk)
    inbound = {}
    for s, targets in union.items():
        for t in targets:
            inbound.setdefault(t, set()).add(s)
    inbound_only = 0
    inbound_only_cross = 0
    for t, srcs in inbound.items():
        idx = index_of_id.get(t)
        if idx is None:
            continue
        own = union.get(t)
        if own:  # has outbound edges of its own -> walked with its own continent
            continue
        inbound_only += 1
        ct = cont_of_id(t)
        for s in srcs:
            if cont_of_id(s) != ct:
                inbound_only_cross += 1
                break
    print("\n4) per-continent cleanup risk")
    print("   waypoints reachable only by INBOUND edges           :", inbound_only)
    print("   ... of those, inbound ONLY from another continent   :", inbound_only_cross)


if __name__ == "__main__":
    main()
