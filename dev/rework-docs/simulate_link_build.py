#!/usr/bin/env py -3
"""
simulate_link_build.py - does the folded link walk produce the same graph as the
four passes it replaces?

Written 2026-08-19 with the tier 1 + tier 3 implementation of
ROUTE-LINK-BUILD-PLAN.md. Reimplements BOTH versions of SkuNav's link build in
Python over the REAL shipped data (Era waypoints + the TBC union of both link
sets, exactly what LoadDefaultMapData wires up on TBC) and compares:

  * the surviving waypoint set after CleanupWaypoints
  * every record's links.byId map (target index -> distance)
  * the resulting SkuDB.SessionRouteData.Links table

OLD: CheckAndUpdateProfileLinkData (prune + symmetrise) -> materialise
     byId/byName -> SaveLinkDataToProfile (re-derive) -> CleanupWaypoints
NEW: one walk (prune + symmetrise + materialise both directions, reverse edges
     into the link table deferred), player's continent first, cleanup per
     continent, no re-derive.

Usage: py -3 dev/rework-docs/simulate_link_build.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze_link_build_assumptions import (  # noqa: E402
    DBIB, ARIB, ERA, WOTLK, read_areas, read_links, read_waypoints,
)

QUICK_WP = "Schnellwegpunkt"  # L["Quick waypoint"], deDE - never cleaned away


def build_cache():
    """The custom pass of CreateWaypointCache: index -> record, name -> canonical
    index (last wins), wpId -> index."""
    wps = read_waypoints(ERA)
    cache, lookup_all, id_for_idx = {}, {}, {}
    for i, w in enumerate(wps, start=1):
        if w is None or w["dead"] or not w["name"] or w["cont"] is None:
            continue
        area = w["areaId"] or 1
        wpid = i + (area << DBIB) + (1 << (DBIB + ARIB))
        cache[i] = {"name": w["name"], "cont": w["cont"], "wpid": wpid, "links": None}
        lookup_all[w["name"]] = i
        id_for_idx[wpid] = i
    return cache, lookup_all, id_for_idx


def union_links():
    era, wotlk = read_links(ERA), read_links(WOTLK)
    union = {s: dict(t) for s, t in wotlk.items()}
    for s, targets in era.items():
        dst = union.setdefault(s, {})
        for t, d in targets.items():
            dst.setdefault(t, d)
    return union


# --------------------------------------------------------------------------- old
def old_build(cache, lookup_all, id_for_idx, links):
    # pass 1 - CheckAndUpdateProfileLinkData
    for src in list(links.keys()):
        targets = links.get(src)
        if targets is None:
            continue
        sidx = id_for_idx.get(src)
        if sidx is None:
            del links[src]
            continue
        sname = cache[sidx]["name"]
        if lookup_all.get(sname) is None:
            del links[src]
            continue
        for tgt in list(targets.keys()):
            tidx = id_for_idx.get(tgt)
            if tidx is None:
                del targets[tgt]
                continue
            tname = cache[tidx]["name"]
            if sname == tname:
                del targets[tgt]
                continue
            if lookup_all.get(tname) is None:
                del targets[tgt]
                links.pop(tgt, None)
                continue
            back = links.setdefault(tgt, {})
            back.setdefault(src, targets[tgt])

    # pass 2 - materialise
    for src, targets in links.items():
        sidx = id_for_idx.get(src)
        if sidx is None:
            continue
        scanon = lookup_all.get(cache[sidx]["name"])
        if scanon is None:
            continue
        by_id, by_name = {}, {}
        cache[scanon]["links"] = (by_id, by_name)
        for tgt, dist in targets.items():
            tidx = id_for_idx.get(tgt)
            if tidx is None:
                continue
            tcanon = lookup_all.get(cache[tidx]["name"])
            if tcanon is None:
                continue
            by_name[cache[tidx]["name"]] = dist
            by_id[tcanon] = dist

    # pass 3 - SaveLinkDataToProfile (re-derive out of the cache)
    new_links = {}
    for idx, rec in cache.items():
        if rec["links"] is None:
            continue
        sid = rec["wpid"] if lookup_all.get(rec["name"]) == idx else None
        if sid is None:
            continue
        new = {}
        new_links[sid] = new
        for tname, dist in rec["links"][1].items():
            tcanon = lookup_all.get(tname)
            if tcanon is not None:
                new[cache[tcanon]["wpid"]] = dist
    links = new_links

    # pass 4 - CleanupWaypoints (full scan)
    for idx in list(cache.keys()):
        rec = cache[idx]
        has = rec["links"] is not None and bool(rec["links"][0])
        if not has and QUICK_WP not in rec["name"]:
            if lookup_all.get(rec["name"]) == idx:
                del lookup_all[rec["name"]]
            del cache[idx]
    return cache, links


# --------------------------------------------------------------------------- new
def new_build(cache, lookup_all, id_for_idx, links, player_cont):
    back_edges = []
    deleted = {}

    def ensure(rec):
        if rec["links"] is None:
            rec["links"] = ({}, {})
        return rec["links"]

    def restore(wpid):
        entry = deleted.pop(wpid, None)
        if entry is None:
            return None
        idx, rec = entry
        cache[idx] = rec
        id_for_idx[wpid] = idx
        lookup_all.setdefault(rec["name"], idx)
        return idx

    def process(src, targets, scanon, canon):
        sname = canon["name"]
        slinks = None
        for tgt in list(targets.keys()):
            dist = targets[tgt]
            tidx = id_for_idx.get(tgt)
            if tidx is None and deleted:
                tidx = restore(tgt)
            trec = cache.get(tidx) if tidx is not None else None
            tcanon = lookup_all.get(trec["name"]) if trec else None
            tcanon_rec = cache.get(tcanon) if tcanon is not None else None
            if tcanon_rec is None:
                del targets[tgt]
                continue
            if tcanon == scanon:
                del targets[tgt]
                continue
            slinks = slinks or ensure(canon)
            slinks[0][tcanon] = dist
            slinks[1][trec["name"]] = dist
            tlinks = ensure(tcanon_rec)
            if scanon not in tlinks[0]:
                tlinks[0][scanon] = dist
                tlinks[1][sname] = dist
            back = links.get(tgt)
            if back is not None:
                back.setdefault(src, dist)
            else:
                back_edges.append((tgt, src, dist))

    rest = []

    def walk(partition):
        """round 1: the only traversal of the link table. Sources of another
        continent are parked WITH their resolved canonical index."""
        for src in list(links.keys()):
            targets = links.get(src)
            if targets is None:
                continue
            sidx = id_for_idx.get(src)
            srec = cache.get(sidx) if sidx is not None else None
            scanon = lookup_all.get(srec["name"]) if srec else None
            canon = cache.get(scanon) if scanon is not None else None
            if canon is None:
                del links[src]
                continue
            if partition is not None and srec["cont"] != partition:
                rest.append((src, scanon))
                continue
            process(src, targets, scanon, canon)

    def walk_rest():
        for src, scanon in rest:
            targets = links.get(src)
            canon = cache.get(scanon)
            if targets is not None and canon is not None:
                process(src, targets, scanon, canon)

    def cleanup(only=None, skip=None):
        for idx in list(cache.keys()):
            rec = cache[idx]
            if only is not None and rec["cont"] != only:
                continue
            if skip is not None and rec["cont"] == skip:
                continue
            has = rec["links"] is not None and bool(rec["links"][0])
            if not has and QUICK_WP not in rec["name"]:
                if lookup_all.get(rec["name"]) == idx:
                    del lookup_all[rec["name"]]
                id_for_idx.pop(rec["wpid"], None)
                del cache[idx]
                if only is not None:
                    deleted[rec["wpid"]] = (idx, rec)

    walk(player_cont)
    cleanup(only=player_cont)
    walk_rest()
    for tgt, src, dist in back_edges:
        links.setdefault(tgt, {}).setdefault(src, dist)
    cleanup(skip=player_cont)
    return cache, links


def main():
    print("loading shipped data ...")
    cont_of_area = read_areas()  # noqa: F841 - kept for symmetry with the analyzer
    cache_a, all_a, id_a = build_cache()
    cache_b, all_b, id_b = build_cache()
    links_a = union_links()
    links_b = union_links()
    print("  %d custom waypoints, %d link sources" % (len(cache_a), len(links_a)))

    player_cont = int(sys.argv[1]) if len(sys.argv) > 1 else 1  # 1 = Kalimdor
    print("running OLD (four passes) ...")
    cache_a, links_a = old_build(cache_a, all_a, id_a, links_a)
    print("running NEW (one walk, %s first) ..." % player_cont)
    cache_b, links_b = new_build(cache_b, all_b, id_b, links_b, player_cont)

    print("\nsurviving waypoints: old %d, new %d" % (len(cache_a), len(cache_b)))
    only_a = set(cache_a) - set(cache_b)
    only_b = set(cache_b) - set(cache_a)
    print("  only in old:", len(only_a), "  only in new:", len(only_b))
    for i in list(only_a)[:5]:
        print("   old-only:", cache_a[i]["name"])
    for i in list(only_b)[:5]:
        print("   new-only:", cache_b[i]["name"])

    diff = 0
    for idx in set(cache_a) & set(cache_b):
        a = cache_a[idx]["links"][0] if cache_a[idx]["links"] else {}
        b = cache_b[idx]["links"][0] if cache_b[idx]["links"] else {}
        if a != b:
            diff += 1
            if diff <= 5:
                print("   byId differs for", cache_a[idx]["name"], len(a), "vs", len(b))
    print("records whose links.byId differ:", diff)

    ea = sum(len(v) for v in links_a.values())
    eb = sum(len(v) for v in links_b.values())
    print("\nlink table: old %d sources / %d edges, new %d sources / %d edges"
          % (len(links_a), ea, len(links_b), eb))
    ka, kb = set(links_a), set(links_b)
    print("  sources only in old:", len(ka - kb), " only in new:", len(kb - ka))
    payload_diff = sum(1 for k in ka & kb if links_a[k] != links_b[k])
    print("  shared sources with different targets:", payload_diff)

    ok = not only_a and not only_b and diff == 0
    print("\nVERDICT:", "cache identical" if ok else "CACHE DIFFERS - investigate")


if __name__ == "__main__":
    main()
