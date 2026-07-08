# -*- coding: utf-8 -*-
# Per-zone reconciliation report for Sku's base vs WotLK route files.
# Read-only. Simulates the runtime hybrid (base waypoints + wotlk links) to count
# how many links the hybrid strands, per zone, and flags WotLK-only waypoints.
import re
from collections import defaultdict

BASE  = r'C:\Users\fabia\Dev\Sku-TBC-42\Sku\SkuDB\assets\routedata_global.lua'
WOTLK = r'C:\Users\fabia\Dev\Sku-TBC-42\Sku\routedata_global_wotlk.lua'
MAPS  = r'C:\Users\fabia\Dev\Sku-TBC-42\Sku\SkuDB\assets\maps.lua'

DBIDXBITS = 20
AREABITS  = 18
def decode(i):
    spawn   = i >> (DBIDXBITS + AREABITS)
    areaId  = (i >> DBIDXBITS) & ((1 << AREABITS) - 1)
    dbIndex = i & ((1 << DBIDXBITS) - 1)
    return dbIndex, areaId, spawn

def read(p): return open(p, encoding='utf-8-sig').read()

def wp_section_bounds(t):
    i = t.find('WaypointsNew')
    ends = [p for p in [t.find('"Links"'), t.find('WaypointLevels'), t.find('SequenceNumbers')] if p > i]
    j = min(ends) if ends else len(t)
    b = t.find('{', i)
    return b, j

def iter_records(t):
    start, end = wp_section_bounds(t)
    i = start + 1
    while i < end:
        c = t[i]
        if c == '{':
            j = i + 1; d = 1
            while j < end and d >= 1:
                if t[j] == '{': d += 1
                elif t[j] == '}': d -= 1
                j += 1
            yield t[i:j]
            i = j
        elif c == '}':
            break
        else:
            i += 1

fa = lambda rec: re.search(r'\["areaId"\]\s*=\s*(\d+)', rec)
fx = lambda rec: re.search(r'\["worldX"\]\s*=\s*([-0-9.]+)', rec)
fy = lambda rec: re.search(r'\["worldY"\]\s*=\s*([-0-9.]+)', rec)

def parse_wps(path):
    t = read(path)
    idx = 0
    live_area_by_index = {}      # 1-based array index (incl tombstones) -> areaId  (live only)
    per_area_coords = defaultdict(set)
    for rec in iter_records(t):
        idx += 1
        if re.match(r'\s*\{\s*false\s*\}', rec):
            continue
        a = fa(rec)
        if not a:
            continue
        aid = int(a.group(1))
        live_area_by_index[idx] = aid
        x, y = fx(rec), fy(rec)
        if x and y:
            per_area_coords[aid].add((round(float(x.group(1)), 1), round(float(y.group(1)), 1)))
    return live_area_by_index, per_area_coords

def parse_links(path):
    t = read(path)
    i = t.find('"Links"')
    ends = [p for p in [t.find('WaypointLevels'), t.find('SequenceNumbers')] if p > i]
    end = min(ends) if ends else len(t)
    seg = t[i:end]
    links = {}
    for m in re.finditer(r'\[(\d+)\]\s*=\s*\{', seg):
        sid = int(m.group(1))
        j = m.end() - 1
        d = 0; k = j
        while k < len(seg):
            if seg[k] == '{': d += 1
            elif seg[k] == '}':
                d -= 1
                if d == 0: break
            k += 1
        block = seg[j+1:k]
        targets = [int(x) for x in re.findall(r'\[(\d+)\]\s*=\s*\d+', block)]
        links[sid] = targets
    return links

def parse_names():
    t = read(MAPS)
    byareaid = {}
    for m in re.finditer(r'Name_lang\s*=\s*\{[^}]*?\["enUS"\]\s*=\s*"([^"]*)"[^}]*\}[^\]]*?AreaId\s*=\s*(\d+)', t):
        byareaid.setdefault(int(m.group(2)), m.group(1))
    return byareaid

print("parsing waypoints...", flush=True)
base_idx_area, base_coords = parse_wps(BASE)
wot_idx_area,  wot_coords  = parse_wps(WOTLK)
print("parsing links...", flush=True)
wot_links  = parse_links(WOTLK)
base_links = parse_links(BASE)
names = parse_names()
nm = lambda a: names.get(a, '?')

# --- simulate the hybrid: wotlk links applied to base waypoint ids ---
# Only CUSTOM endpoints (dbIndex < 200000 == array position) come from the route
# files and can break under the hybrid. Creature (>=200000) / object (>=500000)
# endpoints are generated from the shared SkuDB at runtime — identical whether we
# use base or wotlk — so they never break due to the base/wotlk choice; treat them
# as resolvable so they don't pollute the stranding count.
BASE2, BASE3 = 200000, 500000
def base_resolves(wp_id):
    dbi, area, spawn = decode(wp_id)
    if dbi >= BASE2:
        return True  # creature/object endpoint from shared SkuDB
    return base_idx_area.get(dbi) == area

zone_link_total = defaultdict(int)
zone_link_ok    = defaultdict(int)
for sid, targets in wot_links.items():
    _, sarea, _ = decode(sid)
    src_ok = base_resolves(sid)
    for tid in targets:
        zone_link_total[sarea] += 1
        if src_ok and base_resolves(tid):
            zone_link_ok[sarea] += 1

# base's own self-consistent link counts (per source zone)
base_zone_links = defaultdict(int)
for sid, targets in base_links.items():
    _, sarea, _ = decode(sid)
    base_zone_links[sarea] += len(targets)

# --- per-zone completeness ---
allareas = set(base_coords) | set(wot_coords)
rows = []
for a in allareas:
    cb, cw = base_coords.get(a, set()), wot_coords.get(a, set())
    if cb == cw:
        continue  # identical zones: nothing to decide
    shared = len(cb & cw)
    rows.append({
        'area': a, 'name': nm(a),
        'base_wp': len(cb), 'wot_wp': len(cw),
        'shared': shared, 'base_only': len(cb) - shared, 'wot_only': len(cw) - shared,
        'hyb_links': zone_link_total.get(a, 0),
        'hyb_ok': zone_link_ok.get(a, 0),
        'hyb_stranded': zone_link_total.get(a, 0) - zone_link_ok.get(a, 0),
        'base_links': base_zone_links.get(a, 0),
    })

rows.sort(key=lambda r: r['hyb_stranded'], reverse=True)

tot_str = sum(r['hyb_stranded'] for r in rows)
tot_lnk = sum(zone_link_total.values())
print()
print("=== HYBRID LINK STRANDING (whole world) ===")
print(f"wotlk link-assignments total: {tot_lnk}")
print(f"  resolved against base waypoints: {tot_lnk - sum(zone_link_total[a]-zone_link_ok[a] for a in zone_link_total)}")
print(f"  STRANDED (pruned) by the hybrid: {sum(zone_link_total[a]-zone_link_ok[a] for a in zone_link_total)}")
print(f"stranding concentrated in the differing zones below (sum {tot_str}).")
print()
print("=== PER-ZONE REPORT (only zones where base and wotlk differ) ===")
print("legend: base_wp/wot_wp = waypoints; shared/base_only/wot_only = coord overlap;")
print("        hyb_links = wotlk links whose SOURCE is this zone; stranded = of those, pruned by the hybrid;")
print("        base_links = links base's OWN self-consistent set would give this zone")
print()
for r in rows:
    fuller = 'base' if r['base_wp'] > r['wot_wp'] else ('wotlk' if r['wot_wp'] > r['base_wp'] else 'tie')
    print(f"area {r['area']:>6} {r['name'][:26]:26} | wp base {r['base_wp']:>5} / wotlk {r['wot_wp']:>5} "
          f"(shared {r['shared']:>5}, base_only {r['base_only']:>5}, wotlk_only {r['wot_only']:>5}) "
          f"| hybrid links {r['hyb_links']:>5} stranded {r['hyb_stranded']:>5} "
          f"| base_own_links {r['base_links']:>5} | fuller={fuller}")
print()
print(f"zones differing: {len(rows)}")
