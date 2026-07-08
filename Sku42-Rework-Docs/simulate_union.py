#!/usr/bin/env py -3
"""
simulate_union.py — replicate the runtime Option-C link union OFFLINE and report
per-zone edge counts for: WotLK-only (old hybrid), Era-only (Option A), and the
UNION (Option C). Confirms the union >= hybrid everywhere and reconnects EPL.

Mirrors Core.lua: start from WotLK links, merge Era edges in WITHOUT overwriting
existing WotLK edges. Buckets edges by the source wpId's decoded areaId.
"""
import re, os

ROOT = r"C:\Users\fabia\Dev\Sku-TBC-42"
ERA  = r"old-addon-versions/SkuAddon Era/SkuDB/assets/routedata_global.lua"
WOT  = r"old-addon-versions/SkuAddon LK/Sku/SkuDB/assets/routedata_global.lua"
DBIB, ARIB, BASE2, BASE3 = 20, 18, 200000, 500000
SECT_RE = re.compile(r'^\s*\["(WaypointsNew|Waypoints|Links|WaypointLevels|SequenceNumbers)"\]\s*=\s*\{')
KEY_RE  = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{')
EDGE_RE = re.compile(r'^\s*\[(\d+)\]\s*=\s*(\d+),?\s*$')

def area_of(wpid):
    spawn = wpid >> (DBIB + ARIB)
    return (wpid - (spawn << (DBIB + ARIB))) >> DBIB

def load_links(path):
    links = {}
    section = None; cur = None
    with open(os.path.join(ROOT, path), encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            m = SECT_RE.match(line)
            if m:
                section = m.group(1); cur = None; continue
            if section != "Links":
                continue
            k = KEY_RE.match(line)
            if k:
                cur = int(k.group(1)); links[cur] = links.get(cur, {}); continue
            e = EDGE_RE.match(line)
            if e and cur is not None:
                links[cur][int(e.group(1))] = int(e.group(2))
    return links

def edges_by_zone(links):
    z = {}
    for src, tgts in links.items():
        a = area_of(src)
        z[a] = z.get(a, 0) + len(tgts)
    return z

def zone_meta():
    R = re.compile(r'^\s*\[(\d+)\]\s*=\s*\{ZoneName\s*=\s*"[^"]*".*?\["enUS"\]\s*=\s*"([^"]*)".*?ContinentID\s*=\s*(\d+)')
    m = {}
    with open(os.path.join(ROOT, r"Sku/SkuDB/assets/maps.lua"), encoding="utf-8-sig", errors="replace") as fh:
        for line in fh:
            x = R.match(line)
            if x: m[int(x.group(1))] = (x.group(2), int(x.group(3)))
    return m

print("loading Era links..."); era = load_links(ERA)
print("loading WotLK links..."); wot = load_links(WOT)

# union: Era merged into a copy of WotLK, no overwrite (mirrors Lua)
print("merging union...")
union = {s: dict(t) for s, t in wot.items()}
for src, tgts in era.items():
    dst = union.get(src)
    if dst is None:
        union[src] = dict(tgts)
    else:
        for tgt, dist in tgts.items():
            dst.setdefault(tgt, dist)

meta = zone_meta()
ez, wz, uz = edges_by_zone(era), edges_by_zone(wot), edges_by_zone(union)
CONT = {0:"EK",1:"Kalimdor",530:"Outland",571:"Northrend",609:"DK-phase"}

def tot(z, cont): return sum(v for a,v in z.items() if meta.get(a,("",-1))[1]==cont)
print("\n=== edges per continent: Era(optA) / WotLK(hybrid) / UNION(optC) ===")
for c in (530,0,1,571,609):
    print(f"  {CONT[c]:9s}  Era={tot(ez,c):7d}  WotLK={tot(wz,c):7d}  UNION={tot(uz,c):7d}")

print("\n=== key zones: Era / WotLK / UNION edges ===")
for aid in (139,28,8,1519,14,40,85,3, 3483,3523,3520,3524,3525):
    nm = meta.get(aid,("?",-1))[0]
    print(f"  {aid:6d} {nm:22s} Era={ez.get(aid,0):6d}  WotLK={wz.get(aid,0):6d}  UNION={uz.get(aid,0):6d}")

# sanity: union must be >= wotlk for every zone
regress = [a for a in wz if uz.get(a,0) < wz[a]]
print(f"\nzones where UNION < WotLK (should be none): {regress}")
print(f"total edges  Era={sum(ez.values())}  WotLK={sum(wz.values())}  UNION={sum(uz.values())}")
