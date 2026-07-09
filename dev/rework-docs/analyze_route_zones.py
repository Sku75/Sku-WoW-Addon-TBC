#!/usr/bin/env py -3
"""
analyze_route_zones.py — per-zone (areaId) waypoint + link inventory for the four
route-data snapshots (Era / TBC-base / TBC-wotlk / WotLK-end).

Goal: empirically settle the base-vs-wotlk phase question. Streams each
routedata_global*.lua, counts waypoints per areaId within the WaypointsNew
section, and (optionally) tallies the Links section size.

The route file is a flat Lua table dump. We do NOT eval it — we scan lines:
  - WaypointsNew section runs from its `["WaypointsNew"] = {` line to the next
    top-level section key (`["Waypoints"]`).
  - Each waypoint block contains exactly one `["areaId"] = N,` line, so counting
    those lines within the section = counting waypoints, grouped by areaId.
Usage: py -3 analyze_route_zones.py
"""
import re, sys, os

FILES = {
    "Era":       r"old-addon-versions/SkuAddon Era/SkuDB/assets/routedata_global.lua",
    "TBC-base":  r"Sku/SkuDB/assets/routedata_global.lua",
    "TBC-wotlk": r"Sku/routedata_global_wotlk.lua",
    "WotLK-end": r"old-addon-versions/SkuAddon LK/Sku/SkuDB/assets/routedata_global.lua",
}
ROOT = r"C:\Users\fabia\Dev\Sku-TBC-42"

SECTION_RE = re.compile(r'^\s*\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')
AREAID_RE  = re.compile(r'^\s*\["areaId"\]\s*=\s*(-?\d+)')
NAMES_RE   = re.compile(r'^\s*\["names"\]\s*=')

# areaId -> (enUS name, continentId) parsed from maps.lua's
#   [id] = {ZoneName = "...", AreaName_lang = {... ["enUS"] = "..."}, ContinentID = N, ...}
ZONE_RE = re.compile(
    r'^\s*\[(\d+)\]\s*=\s*\{ZoneName\s*=\s*"[^"]*".*?\["enUS"\]\s*=\s*"([^"]*)".*?ContinentID\s*=\s*(\d+)')
CONTINENT = {0: "EK", 1: "Kalimdor", 530: "Outland", 571: "Northrend", 609: "DK-phase"}

def load_zone_names():
    names = {}
    p = os.path.join(ROOT, r"Sku/SkuDB/assets/maps.lua")
    with open(p, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = ZONE_RE.match(line)
            if m:
                names[int(m.group(1))] = (m.group(2), int(m.group(3)))
    return names

def analyze(path):
    """Return (per_area dict areaId->count, total_wps, links_line_count)."""
    per_area = {}
    total = 0
    section = None
    links_lines = 0
    with open(path, encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = SECTION_RE.match(line)
            if m:
                section = m.group(1)
                continue
            if section == "WaypointsNew":
                a = AREAID_RE.match(line)
                if a:
                    aid = int(a.group(1))
                    per_area[aid] = per_area.get(aid, 0) + 1
                    total += 1
            elif section == "Links":
                links_lines += 1
    return per_area, total, links_lines

def main():
    results = {}
    for label, rel in FILES.items():
        p = os.path.join(ROOT, rel)
        if not os.path.exists(p):
            print(f"MISSING: {label} -> {p}", file=sys.stderr)
            continue
        per_area, total, links = analyze(p)
        results[label] = (per_area, total, links)
        print(f"{label:10s}  total_wps={total:7d}  zones={len(per_area):4d}  links_section_lines={links}")

    names = load_zone_names()
    order = ["Era", "WotLK-end"]  # the two clean anchors (TBC files are proven-identical twins)
    all_areas = set()
    for per_area, _, _ in results.values():
        all_areas.update(per_area.keys())

    def diverge(aid):
        vals = [results[l][0].get(aid, 0) for l in order if l in results]
        return max(vals) - min(vals)

    def verdict(aid, era, wot):
        nm, cont = names.get(aid, ("?", -1))
        c = CONTINENT.get(cont, f"cont{cont}")
        if cont in (571, 609):
            return c, "EXCLUDE (not on TBC)"
        if abs(era - wot) <= 2:
            return c, "either (identical)"
        if cont == 530:
            return c, "WotLK (Outland unchanged, richer mapping)"
        # EK / Kalimdor old world with a real diff -> WotLK changed old world in 3.0
        return c, "ERA (old-world pre-WotLK geometry)"

    print("\n=== ZONES WITH Era<->WotLK DIVERGENCE (the decision points) ===")
    print("  areaId  Era  WotLK  diff  continent  zone  ->  TBC verdict")
    for aid in sorted(all_areas, key=lambda a: (-diverge(a), a)):
        d = diverge(aid)
        if d == 0:
            continue
        era = results["Era"][0].get(aid, 0)
        wot = results["WotLK-end"][0].get(aid, 0)
        nm = names.get(aid, ("?", -1))[0]
        cont, v = verdict(aid, era, wot)
        print(f"  {aid:6d}  {era:5d} {wot:5d}  {d:5d}  {cont:9s}  {nm:28s} -> {v}")

    identical = sum(1 for aid in all_areas if diverge(aid) == 0)
    print(f"\n  ({identical} zones identical across Era & WotLK — no decision needed)")

if __name__ == "__main__":
    main()
