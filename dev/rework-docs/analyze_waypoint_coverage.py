#!/usr/bin/env py -3
"""
analyze_waypoint_coverage.py - what is actually IN each shipped route file's
waypoint half, per continent and per zone?

Written 2026-08-20 for the "can we stop building the WotLK waypoints on TBC"
question (ROUTE-LINK-BUILD-PLAN.md 13) and for the Lich King port: is the WotLK
waypoint set just Northrend, or does it carry the old world too - the part we
already ship in the Era file?

Counts waypoints per areaId inside the WaypointsNew section of both files (one
`["areaId"] = N` line per waypoint block), maps areaId -> continent + zone name
through SkuDB.InternalAreaTable, and reports the per-continent totals plus the
zones where the two files diverge most.

Usage: py -3 dev/rework-docs/analyze_waypoint_coverage.py
"""
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from analyze_link_build_assumptions import ERA, WOTLK, MAPS  # noqa: E402

SECTION_RE = re.compile(r'^\s*\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')
AREAID_RE = re.compile(r'^\s*\["areaId"\]\s*=\s*(-?\d+)')
CONT_NAME = {0: "Eastern Kingdoms", 1: "Kalimdor", 530: "Outland", 571: "Northrend"}


def read_areas():
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


def count_waypoints(path):
    """areaId -> number of waypoint blocks in the WaypointsNew section."""
    per_area = {}
    section = None
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = SECTION_RE.match(line)
            if m:
                section = m.group(1)
                continue
            if section != "WaypointsNew":
                continue
            m = AREAID_RE.match(line)
            if m:
                a = int(m.group(1))
                per_area[a] = per_area.get(a, 0) + 1
    return per_area


def main():
    cont_of, zone_of = read_areas()
    era = count_waypoints(ERA)
    wotlk = count_waypoints(WOTLK)

    print("waypoints in the WaypointsNew section:")
    print("  Era file  : %d" % sum(era.values()))
    print("  WotLK file: %d" % sum(wotlk.values()))

    print("\n=== per continent ===")
    conts = sorted({cont_of.get(a) for a in set(era) | set(wotlk)} - {None})
    for c in conts:
        e = sum(v for a, v in era.items() if cont_of.get(a) == c)
        w = sum(v for a, v in wotlk.items() if cont_of.get(a) == c)
        print("  %-18s Era %7d   WotLK %7d   (WotLK %+d)" % (CONT_NAME.get(c, "cont %s" % c), e, w, w - e))
    eu = sum(v for a, v in era.items() if cont_of.get(a) is None)
    wu = sum(v for a, v in wotlk.items() if cont_of.get(a) is None)
    print("  %-18s Era %7d   WotLK %7d" % ("(unknown areaId)", eu, wu))

    def show(title, items):
        print("\n=== %s ===" % title)
        for a, e, w in items:
            print("  %-32s (%s, area %5d)  Era %6d  WotLK %6d" % (
                zone_of.get(a, "?")[:32], CONT_NAME.get(cont_of.get(a), "?")[:16], a, e, w))

    diffs = []
    for a in set(era) | set(wotlk):
        diffs.append((a, era.get(a, 0), wotlk.get(a, 0)))
    show("zones where the WotLK file has MORE (top 20)",
         sorted(diffs, key=lambda t: t[1] - t[2])[:20])
    show("zones where the Era file has MORE (top 20)",
         sorted(diffs, key=lambda t: t[2] - t[1])[:20])

    only_w = [t for t in diffs if t[1] == 0 and t[2] > 0]
    only_e = [t for t in diffs if t[2] == 0 and t[1] > 0]
    print("\nzones present ONLY in the WotLK file: %d (%d waypoints)"
          % (len(only_w), sum(t[2] for t in only_w)))
    print("zones present ONLY in the Era file  : %d (%d waypoints)"
          % (len(only_e), sum(t[1] for t in only_e)))
    if only_w:
        show("only in the WotLK file (top 15)", sorted(only_w, key=lambda t: -t[2])[:15])


if __name__ == "__main__":
    main()
