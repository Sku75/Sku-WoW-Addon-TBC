"""Merge local + web findings into the final proposal review file.
Verifies EVERY claimed object/creature id against the shipped DBs
(existence + spawns + zone) before proposing it."""
import importlib.util, os, io, sys, re

HERE = r"C:\Users\fabia\Dev\Sku-TBC\dev\rework-docs"
SCRATCH = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("q", os.path.join(HERE, "_quest_target_candidates.py"))
old = sys.stdout
sys.stdout = io.StringIO()
q = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q)
sys.stdout = old
rspec = importlib.util.spec_from_file_location("refresh", os.path.join(HERE, "_refresh_questdata_from_questie.py"))
r = importlib.util.module_from_spec(rspec)
rspec.loader.exec_module(r)

base_obj, _, _, _ = r.load_table_records(os.path.join(r.ASSETS, "objects.lua.bak"), "SkuDB.objectDataTBC")
wot_obj, _, _, _ = r.load_table_records(os.path.join(r.ASSETS, "WotLK", "objects.lua.bak"), "SkuDB.WotLK.objectDataTBC")
cre, _, _, _ = r.load_table_records(os.path.join(r.ASSETS, "creatures.lua.bak"), "SkuDB.NpcData.Data")
squests, _, _, _ = r.load_table_records(os.path.join(r.ASSETS, "quests.lua.bak"), "SkuDB.questDataTBC")

zone_id_by_name = {v: k for k, v in q.zone_names.items()}


def zones_of(rec, fidx):
    if not rec:
        return None
    f = r.record_fields(r.record_body(rec))
    if len(f) <= fidx or f[fidx] in (b"nil", b""):
        return None
    return sorted(set(q.zone_names.get(int(z), z.decode())
                      for z in re.findall(rb"\[(\d+)\]", f[fidx])))


def obj_zones(oid):
    return zones_of(base_obj.get(oid) or wot_obj.get(oid), 3)


def cre_zones(cid):
    return zones_of(cre.get(cid), 6)


def qname(qid):
    return q.names.get(qid, "?")


# ---------------------------------------------------------------------------
OBJ_FIX = {  # qid -> (object ids, label, evidence)
    28: ([177117, 177122, 177129], "Shrine of Remulos", "local name match, all Moonglade"),
    29: ([177117, 177122, 177129], "Shrine of Remulos", "local name match, all Moonglade"),
    6001: ([177525], "Moonkin Stone", "local; spawns Darkshore+Barrens cover both variants"),
    6002: ([177525], "Moonkin Stone", "local; spawns Darkshore+Barrens cover both variants"),
    328: ([288], "Bookie Herod's Strongbox", "local name match, STV"),
    754: ([2913], "Winterhoof Water Well", "local name match, Mulgore"),
    941: ([7923], "Denalan's Planter", "local name match, Teldrassil"),
    4285: ([164955], "Northern Crystal Pylon", "local name match, Un'Goro"),
    4287: ([164957], "Eastern Crystal Pylon", "local name match, Un'Goro"),
    4288: ([164956], "Western Crystal Pylon", "local name match, Un'Goro"),
    10819: ([185165], "Legion Communicator", "local name match, Blade's Edge"),
    264: ([24776], "Yuriv's Tombstone", "web agent via SkuDB; graveyard behind the Sepulcher"),
    281: ([261], "Damaged Crate", "web agent via SkuDB + wiki 13.5,41.5 Bluegill Marsh"),
    321: ([2734], "Waterlogged Chest", "web agent via SkuDB; ends quest 321"),
    760: ([2909], "Wildmane Water Pump", "web agent via SkuDB; Wildmane Water Well"),
    3912: ([148504], "A Conspicuous Gravestone", "web agent via SkuDB; Gadgetzan graveyard"),
    4125: ([164909], "Wrecked Row Boat", "web agent via SkuDB; ends quest 4125"),
    4131: ([164953], "Large Leather Backpacks", "web agent via SkuDB + wiki"),
    5084: ([176091], "Deadwood Cauldron", "web agent via SkuDB; Felpaw Village"),
    894: ([4141], "Control Console", "web agent via SkuDB + guide 52,12 Barrens"),
    2701: ([141980], "Spectral Lockbox", "web agent via SkuDB + web 33.5,66 Swamp of Sorrows"),
    524: ([1728], "Dusty Rug", "local; Hillsbrad 62.81,18.73 = Tarren Mill inn upstairs"),
    4451: ([173265], "Wooden Outhouse", "local; Searing Gorge 65.59,62.17"),
    280: ([1585], "Explosive Charge", "local; Loch Modan 50.58,14.3 = dam base"),
    7843: ([179912], "Aerie Peak Town Center", "local; Hinterlands 14.34,48.0 = the well in the town center"),
}

CRE_FIX = {  # qid -> (creature ids, label, evidence)
    10964: ([22834], "Clintar Dreamwalker", "local; Moonglade"),
    9539: ([17361], "Totem of Coo", "local; Azuremyst; web coords 55.2,41.7 agree"),
    9540: ([17362], "Totem of Tikti", "local; Azuremyst; web coords 64.2,40.2 agree"),
    9541: ([17363], "Totem of Yor", "local; Azuremyst"),
    9542: ([17364], "Totem of Vark", "local; Azuremyst; web coords 28.1,62.4 agree"),
    1030: ([3897], "Krolg", "local + web 50.8,75.1 Ashenvale, Krolg's Hut"),
    8447: ([11832], "Keeper Remulos", "local; Moonglade; event runs at his shrine"),
    2844: ([7774], "Shay Leafrunner", "web agent via SkuDB + web ~38,10 Feralas"),
    9771: ([18035], "Scout Jyoba", "local name match, Zangarmarsh"),
    6061: ([2956], "Adult Plainstrider", "local; tame target"),
    6062: ([3099], "Dire Mottled Boar", "local; tame target"),
    6063: ([1998], "Webwood Lurker", "local; tame target"),
    6064: ([1126], "Large Crag Boar", "local; tame target"),
    6082: ([3126], "Armored Scorpid", "local; tame target"),
    6083: ([3107], "Surf Crawler", "local; tame target"),
    6084: ([1201], "Snow Leopard", "local; tame target"),
    6085: ([1196], "Ice Claw Bear", "local; tame target"),
    6087: ([2959], "Prairie Stalker", "local; tame target"),
    6088: ([2970], "Swoop", "local; tame target"),
    6101: ([2043], "Nightsaber Stalker", "local; tame target"),
    6102: ([1996], "Strigid Screecher", "local; tame target"),
    6501: ([10929], "Haleh", "local; Winterspring; NOTE reachable only via teleport runes at the bottom of Mazthoril"),
}

TRIG_FIX = {  # qid -> (zone name, [(x,y)...], text, confidence, evidence)
    1517: ("Durotar", [(44.0, 76.0)], "Drink the Earth Sapta at Spirit Rock", "medium", "wowpedia; atop the Hidden Path above the Valley of Trials"),
    1520: ("Mulgore", [(54.0, 80.0)], "Drink the Earth Sapta at Kodo Rock", "high", "wiki.gg; east of Camp Narache"),
    45: ("Elwynn Forest", [(79.0, 55.0)], "Search the murloc village for Rolf", "high", "wiki.gg; eastern lakeshore"),
    139: ("Westfall", [(40.7, 17.1)], "Search the empty jug next to the windmill", "high", "wiki.gg; sea bluffs"),
    250: ("Loch Modan", [(56.1, 13.2)], "Investigate near the eastern dam ramp", "high", "wiki.gg; Suspicious Barrel"),
    465: ("Wetlands", [(47.5, 46.9)], "Destroy the Dragonmaw catapults", "medium", "wowpedia; around the Dragonmaw gates"),
    758: ("Mulgore", [(44.0, 46.0)], "Use the totem at the Thunderhorn Water Well", "high", "wiki.gg; NW of Bloodhoof Village"),
    2278: ("Badlands", [(42.6, 12.2)], "Uldaman entrance (discs at the end of the instance)", "medium", "dungeon guides"),
    2932: ("The Hinterlands", [(31.5, 58.0), (22.8, 57.0)], "Place the pike at a Witherbark village", "medium", "Hiri'watha and Zun'watha"),
    2969: ("Feralas", [(65.5, 47.4)], "The Sprite Darter pen behind the Grimtotem camp", "medium", "spawn clusters + guide; hidden cliff path"),
    3373: ("Swamp of Sorrows", [(69.0, 53.0)], "Sunken Temple entrance (Essence Font is inside)", "medium", "instance-interior objective; Pool of Tears"),
    3447: ("Swamp of Sorrows", [(69.0, 53.0)], "Sunken Temple entrance (statue circle is inside)", "medium", "Pool of Tears, underwater portal"),
    4734: ("Searing Gorge", [(35.4, 84.7)], "Blackrock Mountain entrance (Rookery is inside UBRS)", "medium", "instance-interior objective"),
    5265: ("Eastern Plaguelands", [(76.0, 52.0)], "The Argent Hold chest at Light's Hope", "high", "wiki.gg [76, 52]"),
    8305: ("Silithus", [(28.7, 89.1)], "The Crystalline Tear before the Scarab Wall", "high", "warcrafttavern 28.68,89.14"),
    9410: ("Hellfire Peninsula", [(33.0, 43.0)], "Krun Spinebreaker's body; use the Wolf Totem", "high", "wiki.gg [33, 43]"),
    5902: ("Western Plaguelands", [(48.4, 31.9)], "Place the barrel at the Northridge Lumber Mill crate", "high", "wowpedia Termite Barrel"),
    5904: ("Western Plaguelands", [(48.4, 31.9)], "Place the barrel at the Northridge Lumber Mill crate", "high", "same spot as 5902"),
    6389: ("Western Plaguelands", [(48.4, 31.9)], "Release the termites at the Northridge Lumber Mill", "high", "same spot as 5902"),
    6390: ("Western Plaguelands", [(48.4, 31.9)], "Release the termites at the Northridge Lumber Mill", "high", "same spot as 5902"),
    9550: ("Bloodmyst Isle", [(61.2, 41.9)], "The ruined pavilion north of the Ruins of Loreth'Aran", "high", "wiki.gg"),
    9561: ("Bloodmyst Isle", [(60.9, 49.6)], "The Mound of Dirt in the Ruins of Loreth'Aran", "high", "wowpedia"),
    5202: ("Felwood", [(37.0, 58.0)], "Jaedenar entrance (the cell is inside Shadow Hold)", "medium", "cave-interior objective"),
    5463: ("Eastern Plaguelands", [(27.0, 12.0)], "Stratholme entrance (the Gift is inside)", "medium", "instance-interior objective"),
    8929: ("Eastern Plaguelands", [(27.0, 12.0)], "Use the Ghost Revealer outside the Stratholme gate", "medium", "wiki.gg"),
    8930: ("Eastern Plaguelands", [(27.0, 12.0)], "Use the Ghost Revealer outside the Stratholme gate", "medium", "same as 8929"),
    10166: ("Eversong Woods", [(38.0, 86.0)], "The runestone at the Scorched Grove", "high", "wiki.gg"),
    10174: ("Netherstorm", [(57.6, 86.2)], "Use the staff at the Violet Tower, Kirin'Var", "medium", "wiki.gg"),
    10910: ("Blade's Edge Mountains", [(64.0, 64.0)], "Death's Door; use the Druid Signal", "medium", "wiki.gg; via tunnel south of Mok'Nathal"),
    4506: ("Felwood", [(32.32, 66.56)], "The corrupted moonwell in the Ruins of Constellas", "high", "own DB: DND spell-focus object 148501 spawn; object name too ugly to list, use coords"),
}

PARKED = [
    (7001, "Frostwolf taming: AV zone 2597 missing from InternalAreaTable - fix the maps gap first"),
    (7027, "Alterac Ram taming: same AV zone gap"),
    (8960, "Bodley: inside Blackrock Mountain, no open-world zone map for waypoints"),
    (9032, "Bodley: same as 8960"),
    (3481, "Searing Gorge chest: no source named the object or coords"),
]
# 266 resolved as NOFIX: finishedBy is already Tavernkeep Smitts (273)

# leftover names worth a second local look
print("=== leftover object-name lookups ===")
t = open(os.path.join(q.ASSETS, "WotLK", "objects.lua.bak"), encoding="utf-8-sig", errors="replace").read()
i = t.find("SkuDB.WotLK.objectLookup")
i = t.find('["enUS"] = {', i)
end = t.find("\n\t},", i)
seg = t[i:end]
for nm in ("Dusty Rug", "Wooden Outhouse", "Explosive Charge", "Mound of Dirt",
           "Corrupted Moonwell", "Aerie Peak", "Dragonmaw Catapult"):
    hits = re.findall(r'\[(\d+)\] = "(%s[^"]*)"' % re.escape(nm), seg)
    print(" ", nm, "->", hits[:4])

print("=== creature checks ===")
for nm in ("Haleh", "Tavernkeep Smitts", "Dragonmaw Catapult"):
    ids = q.npc_by_name.get(nm)
    print(" ", nm, "->", ids, [cre_zones(c) for c in (ids or [])])
f266 = [r.canon_field(x) for x in r.record_fields(r.record_body(squests[266]))[:26]]
print("  quest 266 finishedBy:", f266[2])

# ---------------------------------------------------------------------------
print("\n=== id verification ===")
bad = []
for qid, (ids, label, ev) in sorted(OBJ_FIX.items()):
    for oid in ids:
        z = obj_zones(oid)
        if not z:
            bad.append((qid, "object", oid))
        print("  q%-6s obj %-7s %-28s zones %s" % (qid, oid, label, z))
for qid, (ids, label, ev) in sorted(CRE_FIX.items()):
    for cid in ids:
        z = cre_zones(cid)
        if not z:
            bad.append((qid, "creature", cid))
        print("  q%-6s cre %-7s %-28s zones %s" % (qid, cid, label, z))
print("BAD (no spawns):", bad)

miss = [zn for zn, _, _, _, _ in TRIG_FIX.values() if zn not in zone_id_by_name]
print("trigger zones missing from InternalAreaTable:", sorted(set(miss)))

# ---------------------------------------------------------------------------
OUT = os.path.join(HERE, "QUEST-TARGET-PROPOSALS.txt")
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
    W = fh.write
    W("Proposed quest-target fixes - REVIEW FILE, nothing applied yet.\n")
    W("Sources: local SkuDB name/spawn matches, six web research agents\n")
    W("(warcraft.wiki.gg / wowhead / guides), routedata waypoint cross-checks.\n")
    W("Object/creature proposals use OUR OWN spawn data (exact positions);\n")
    W("triggerEnd proposals use web map-percent coordinates.\n\n")

    W("=" * 70 + "\nSECTION 1: OBJECT OBJECTIVES (%d quests)\n" % len(OBJ_FIX))
    W("Fix form: [questKeys.objectives] = {nil,{{id,nil}},nil,nil,nil}\n" + "=" * 70 + "\n\n")
    for qid, (ids, label, ev) in sorted(OBJ_FIX.items()):
        zs = sorted(set(sum((obj_zones(o) or [] for o in ids), [])))
        W("Quest %d: %s\n  object %s = %s; spawns in %s\n  evidence: %s\n\n"
          % (qid, qname(qid), label, ids, zs, ev))

    W("=" * 70 + "\nSECTION 2: CREATURE OBJECTIVES (%d quests)\n" % len(CRE_FIX))
    W("Fix form: [questKeys.objectives] = {{{id,nil}},nil,nil,nil,nil}\n" + "=" * 70 + "\n\n")
    for qid, (ids, label, ev) in sorted(CRE_FIX.items()):
        zs = sorted(set(sum((cre_zones(c) or [] for c in ids), [])))
        W("Quest %d: %s\n  creature %s = %s; spawns in %s\n  evidence: %s\n\n"
          % (qid, qname(qid), label, ids, zs, ev))

    W("=" * 70 + "\nSECTION 3: TRIGGEREND COORDINATES (%d quests)\n" % len(TRIG_FIX))
    W("Fix form: [questKeys.triggerEnd] = {\"text\", {[zoneID]={{x,y},...}}}\n" + "=" * 70 + "\n\n")
    for qid, (zn, coords, txt, conf, ev) in sorted(TRIG_FIX.items()):
        zid = zone_id_by_name.get(zn, "?")
        W("Quest %d: %s\n  %s (%s) %s - confidence %s\n  text: %s\n  evidence: %s\n\n"
          % (qid, qname(qid), zn, zid, coords, conf, txt, ev))

    W("=" * 70 + "\nSECTION 4: PARKED / OPEN (%d quests)\n" % len(PARKED) + "=" * 70 + "\n\n")
    for qid, note in PARKED:
        W("Quest %d: %s\n  %s\n\n" % (qid, qname(qid), note))

print("\nwrote", OUT)
print("counts: obj %d, cre %d, trig %d, parked %d" % (len(OBJ_FIX), len(CRE_FIX), len(TRIG_FIX), len(PARKED)))
