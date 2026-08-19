#!/usr/bin/env py -3
"""
analyze_tier4_payoff.py - what is tier 4 (shipping the links already pruned and
symmetric) actually worth, now that tier 1 has landed?

ROUTE-LINK-BUILD-PLAN.md 7.2 demands one measurement before committing to tier 4:
"run the normalization offline and report the size delta of both files". This
does that, plus the two questions tier 1 changed:

  1. WHAT KIND of ids do the links reference? If every endpoint is a custom
     waypoint (typeId 1) then the shipped graph can be normalized offline
     against the route file alone. If creature/object ids appear, normalization
     depends on the SkuDB creature and object tables too - a much bigger
     promise for the generator.
  2. HOW MUCH of the shipped link data is dead weight? Every edge the runtime
     drops is still parsed by WoW at login and held in memory until the build
     throws it away - that, not the walk, is what tier 4 could still save,
     because tier 1 already folded the prune INTO the materialisation walk.

Byte accounting is exact: the Links section of both files is measured line by
line, so "N bytes per edge" is not an estimate.

Usage: py -3 dev/rework-docs/analyze_tier4_payoff.py
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze_link_build_assumptions import (  # noqa: E402
    DBIB, ARIB, BASE2, BASE3, ERA, WOTLK, KEY_RE, EDGE_RE, SECT_RE,
    read_waypoints,
)


def type_of(wpid):
    spawn = wpid >> (DBIB + ARIB)
    area_id = (wpid - (spawn << (DBIB + ARIB))) >> DBIB
    db_index = wpid - (area_id << DBIB) - (spawn << (DBIB + ARIB))
    return 1 if db_index < BASE2 else (2 if db_index < BASE3 else 3)


def measure(path):
    """Exact byte + line accounting of the Links section, and the typeId mix of
    both endpoint sides."""
    out = {
        "file_bytes": os.path.getsize(path),
        "links_bytes": 0, "links_lines": 0,
        "src_bytes": 0, "edge_bytes": 0,
        "sources": 0, "edges": 0,
        "src_types": {1: 0, 2: 0, 3: 0},
        "tgt_types": {1: 0, 2: 0, 3: 0},
        "src_ids": set(), "tgt_ids": set(),
        "wp_bytes": 0,
    }
    section = None
    with open(path, "rb") as fh:
        for raw in fh:
            line = raw.decode("utf-8", "replace")
            s = line.strip()
            m = SECT_RE.match(s)
            if m:
                section = m.group(1)
                continue
            if section == "WaypointsNew" or section == "Waypoints":
                out["wp_bytes"] += len(raw)
                continue
            if section != "Links":
                continue
            out["links_bytes"] += len(raw)
            out["links_lines"] += 1
            m = KEY_RE.match(s)
            if m:
                out["sources"] += 1
                out["src_bytes"] += len(raw)
                wpid = int(m.group(1))
                out["src_types"][type_of(wpid)] += 1
                out["src_ids"].add(wpid)
                continue
            m = EDGE_RE.match(s)
            if m:
                out["edges"] += 1
                out["edge_bytes"] += len(raw)
                wpid = int(m.group(1))
                out["tgt_types"][type_of(wpid)] += 1
                out["tgt_ids"].add(wpid)
    return out


def main():
    era = measure(ERA)
    wotlk = measure(WOTLK)

    print("=== shipped route files ===")
    for name, m in (("Era   ", era), ("WotLK ", wotlk)):
        print("%s file %6.1f MB   links section %6.1f MB (%4.1f%%)   waypoints %6.1f MB" % (
            name, m["file_bytes"] / 1e6, m["links_bytes"] / 1e6,
            100.0 * m["links_bytes"] / m["file_bytes"], m["wp_bytes"] / 1e6))
        print("        %7d sources (%.1f B each), %7d edges (%.1f B each)" % (
            m["sources"], m["src_bytes"] / max(m["sources"], 1),
            m["edges"], m["edge_bytes"] / max(m["edges"], 1)))
        print("        source ids by type: custom %d, creature %d, object %d" % (
            m["src_types"][1], m["src_types"][2], m["src_types"][3]))
        print("        target ids by type: custom %d, creature %d, object %d" % (
            m["tgt_types"][1], m["tgt_types"][2], m["tgt_types"][3]))

    # --- what the TBC union looks like (WotLK wins, Era adds what is missing).
    # The byte figures are per file; the union is what the runtime holds.
    union_src = era["src_ids"] | wotlk["src_ids"]
    union_tgt = era["tgt_ids"] | wotlk["tgt_ids"]
    print("\n=== TBC union (both files loaded) ===")
    print("  distinct source ids: %d   distinct target ids: %d" % (len(union_src), len(union_tgt)))
    print("  target ids that are never a source: %d" % len(union_tgt - union_src))

    # --- how much of that can be judged from the route file alone
    wps = read_waypoints(ERA)
    live_custom = set()
    for i, w in enumerate(wps, start=1):
        if w is None or w["dead"] or not w["name"] or w["cont"] is None:
            continue
        live_custom.add(i + ((w["areaId"] or 1) << DBIB) + (1 << (DBIB + ARIB)))
    print("\n=== resolvability against the ERA waypoint set alone ===")
    cust_src = {i for i in union_src if type_of(i) == 1}
    print("  custom source ids: %d, of which the Era waypoint list has: %d (missing %d)" % (
        len(cust_src), len(cust_src & live_custom), len(cust_src - live_custom)))
    noncust = len(union_src) - len(cust_src)
    print("  non-custom source ids (creature/object): %d" % noncust)
    if noncust:
        print("  -> normalization CANNOT be done from the route file alone:")
        print("     those endpoints only resolve against the SkuDB creature/object tables,")
        print("     which are generated separately and change with every data update.")

    # --- the prize, in bytes: the runtime drops N sources and M edges (measured
    # in game: 10833 stale sources / 6858 stale target edges on TBC).
    print("\n=== what tier 4 could remove (using the in-game counters) ===")
    stale_sources, stale_edges = 10833, 6858
    per_src = (era["src_bytes"] + wotlk["src_bytes"]) / (era["sources"] + wotlk["sources"])
    per_edge = (era["edge_bytes"] + wotlk["edge_bytes"]) / (era["edges"] + wotlk["edges"])
    total_links_bytes = era["links_bytes"] + wotlk["links_bytes"]
    total_bytes = era["file_bytes"] + wotlk["file_bytes"]
    total_sources = era["sources"] + wotlk["sources"]
    total_edges = era["edges"] + wotlk["edges"]
    print("  shipped (both files): %d source lines, %d edge lines, %.1f MB of links"
          % (total_sources, total_edges, total_links_bytes / 1e6))
    print("  the runtime drops %d sources (%.1f%%) and %d further edges (%.2f%%)"
          % (stale_sources, 100.0 * stale_sources / total_sources,
             stale_edges, 100.0 * stale_edges / total_edges))
    print("  NOTE: the edges BELOW a dropped source are dropped with it and are not")
    print("        counted above - the in-game counter has to report that number;")
    print("        the range below brackets it at 1 and at the average fan-out.")
    avg_fan = total_edges / total_sources
    for label, edges_below in (("1 edge each", stale_sources),
                               ("average fan-out %.1f" % avg_fan, int(stale_sources * avg_fan))):
        saved = stale_sources * per_src + (stale_edges + edges_below) * per_edge
        print("    if dropped sources carry %s: %.2f MB saved (%.1f%% of the links section, %.1f%% of both files)"
              % (label, saved / 1e6, 100.0 * saved / total_links_bytes, 100.0 * saved / total_bytes))


if __name__ == "__main__":
    main()
