"""Build the review list for hand-authored quest-target (triggerEnd) fixes.

Since PR #15's geometry fallback, a quests_fixes.lua entry of the form
    [questKeys.triggerEnd] = {"text", {[zoneIDs.X]={{xx.x,yy.y}}}}
is all a target-less quest needs - map-percent coordinates, no waypoint
authoring. This tool finds the quests worth fixing and gathers coordinate
evidence for each, for HUMAN review (data is fuzzy; nothing is auto-applied):

  priority = no usable target source (base data after the Questie refresh,
  minus what quests_fixes.lua already provides) AND
    P1: a class quest (requiredClasses set), or
    P2: no finishedBy either (nothing to route at all)

Evidence per quest:
  * objectivesText (what the quest actually asks for),
  * zoneOrSort zone name,
  * coordinates mined from the wowpedia dump (SkuDB/assets/wiki.lua),
    article = exact enUS quest name, redirects followed once, sub-articles
    "Name (...)" included,
  * hand-made "quest target;..." waypoints in routedata whose name tokens
    overlap the quest name/zone (verified in-game positions - confirmation,
    their world coords are NOT map percent),
  * a marker when Questie's static blacklist knows the quest (likely
    removed-from-game or event -> probably skip).

Output: dev/rework-docs/QUEST-TARGET-CANDIDATES.txt (linear text, one block
per quest, screen-reader friendly). Run:
  py -3 dev/rework-docs/_quest_target_candidates.py
"""
import importlib.util
import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(ROOT, "Sku", "SkuDB", "assets")
QUESTIE_BL = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
              r"\Interface\AddOns\Questie\Database\Corrections\QuestieQuestBlacklist.lua")
OUT = os.path.join(HERE, "QUEST-TARGET-CANDIDATES.txt")

spec = importlib.util.spec_from_file_location(
    "refresh", os.path.join(HERE, "_refresh_questdata_from_questie.py"))
r = importlib.util.module_from_spec(spec)
spec.loader.exec_module(r)

# standard chrClasses bitmask (2^(classID-1)) - the DATA uses this; note
# Sku's own SkuDB.classKeys says SHAMAN=32, which contradicts the data
# (Call of Water carries 64) - flagged separately, do not copy that table
CLASS_NAMES = {1: "Warrior", 2: "Paladin", 4: "Hunter", 8: "Rogue", 16: "Priest",
               32: "DeathKnight", 64: "Shaman", 128: "Mage", 256: "Warlock",
               512: "Monk?", 1024: "Druid"}

# a quest whose objective text only says bring/speak/deliver is covered by
# the Abgabe (turn-in) entry - a missing Ziel is harmless there. Fix-worthy
# is a FIELD action at a place that is neither a creature/object/item nor
# the turn-in NPC.
FIELD_VERBS = re.compile(
    r"\b(use|using|explore|exploring|fill|place|plant|light|extinguish|douse|"
    r"cleanse|purify|activate|read the|drink|bathe|swim|dig|scout|investigate|"
    r"venture|discover|locate the|search the|destroy the|burn|ignite|pour|"
    r"empty the|open the|free the|release|perform|complete the ritual|"
    r"summon\w* .{0,40}\bat\b)\b", re.I)


def unescape(s):
    return s.replace('\\"', '"').replace("\\'", "'").replace("\\\\", "\\")


# --- base quest data (post-refresh pristine) -------------------------------
sku, sku_bytes, _, _ = r.load_table_records(
    os.path.join(ASSETS, "quests.lua.bak"), "SkuDB.questDataTBC")

quests = {}
for qid, rec in sku.items():
    f = [r.canon_field(x) for x in r.record_fields(r.record_body(rec))[:26]]
    f += [None] * (26 - len(f))
    quests[qid] = f


def tbl_pos(v):
    return v[1] if isinstance(v, tuple) and v and v[0] == "T" else ()


def has_list(v, idx):
    p = tbl_pos(v)
    return len(p) > idx and p[idx] is not None


# --- enUS names from the lookup -------------------------------------------
text = open(os.path.join(ASSETS, "quests.lua.bak"), encoding="utf-8-sig",
            errors="replace").read()
i = text.find("SkuDB.questLookup = {")
i = text.find('["enUS"] = {', i)
end = text.find('\n\t},', i)
names = {}
for m in re.finditer(r'\[(\d+)\] = \{"((?:[^"\\]|\\.)*)"', text[i:end]):
    names[int(m.group(1))] = unescape(m.group(2))

# --- what quests_fixes.lua already provides -------------------------------
fixes_txt = open(os.path.join(ASSETS, "quests_fixes.lua"), encoding="utf-8-sig",
                 errors="replace").read()
fixes_txt = re.sub(r"--\[\[.*?\]\]", "", fixes_txt, flags=re.S)
fix_gives_target = set()
fix_gives_finish = set()
blocks = re.split(r"(?m)^(\s{3,8}\[(\d+)\] = \{)", fixes_txt)
# re.split with 2 groups yields [pre, whole, id, body, whole, id, body...]
for k in range(1, len(blocks) - 2, 3):
    qid = int(blocks[k + 1])
    body = blocks[k + 2]
    # block body runs until the next block header; good enough to detect keys
    head = body.split("\n    [", 1)[0]
    if re.search(r"questKeys\.(triggerEnd|objectives)\b", head):
        fix_gives_target.add(qid)
    if "questKeys.finishedBy" in head:
        fix_gives_finish.add(qid)

# --- Questie static blacklist (removed / seasonal markers) ----------------
questie_bl = set()
if os.path.exists(QUESTIE_BL):
    bl = open(QUESTIE_BL, encoding="utf-8", errors="replace").read()
    for m in re.finditer(r"\[(\d+)\] = (?:true|HIDE_ON_MAP)", bl):
        questie_bl.add(int(m.group(1)))

# --- zone names -----------------------------------------------------------
maps_txt = open(os.path.join(ASSETS, "maps.lua"), encoding="utf-8-sig",
                errors="replace").read()
zone_names = {}
for m in re.finditer(r'\[(\d+)\] = \{ZoneName = "[^"]*", AreaName_lang = \{[^}]*\["enUS"\] = "([^"]*)"',
                     maps_txt):
    zone_names[int(m.group(1))] = m.group(2)

# --- wiki dump (enUS articles) --------------------------------------------
wiki_txt = open(os.path.join(ASSETS, "wiki.lua"), encoding="utf-8-sig",
                errors="replace").read()
wiki_end = wiki_txt.find('["deDE"]')
if wiki_end == -1:
    wiki_end = len(wiki_txt)

COORD1 = re.compile(r"\((\d{1,2}(?:\.\d+)?),\s?(\d{1,2}(?:\.\d+)?)(?:\s+([A-Z][\w' .-]{2,28}?))?\)")
COORD2 = re.compile(r"\[(\d{1,2}(?:\.\d+)?),\s?(\d{1,2}(?:\.\d+)?)\]")


def wiki_article(name):
    """Return content string for the article, following one redirect."""
    key = '["%s"] = { content = "' % name.replace("\\", "\\\\").replace('"', '\\"')
    i = wiki_txt.find(key, 0, wiki_end)
    if i == -1:
        return None
    j = i + len(key)
    # find closing quote not preceded by an odd number of backslashes
    k = j
    while True:
        k = wiki_txt.find('"', k)
        if k == -1:
            return None
        b = 0
        while wiki_txt[k - 1 - b] == "\\":
            b += 1
        if b % 2 == 0:
            break
        k += 1
    content = wiki_txt[j:k]
    m = re.match(r"#redirect ?\[\[([^\]]+)\]\]", content, re.I)
    if m:
        return wiki_article(m.group(1)) or content
    return content


def wiki_coords(name):
    """Collect coordinate mentions from the article and its sub-articles."""
    out = []
    seen = set()

    def collect(content, label):
        if not content:
            return
        for m in COORD1.finditer(content):
            x, y, zone = m.group(1), m.group(2), m.group(3) or ""
            key = (x, y)
            if key not in seen:
                seen.add(key)
                out.append("%s,%s %s%s" % (x, y, zone, (" [%s]" % label) if label else ""))
        for m in COORD2.finditer(content):
            key = (m.group(1), m.group(2))
            if key not in seen:
                seen.add(key)
                out.append("%s,%s%s" % (m.group(1), m.group(2), (" [%s]" % label) if label else ""))

    collect(wiki_article(name), "")
    # sub-articles like "Call of Water (Durotar)"
    subkey = '["%s (' % name.replace("\\", "\\\\").replace('"', '\\"')
    i = 0
    while len(out) < 12:
        i = wiki_txt.find(subkey, i, wiki_end)
        if i == -1:
            break
        variant = wiki_txt[i + 2:wiki_txt.find('"]', i)]
        collect(wiki_article(variant), variant[len(name) + 2:-1])
        i += len(subkey)
    return out[:10]


# --- hand-made quest-target waypoints from routedata ----------------------
route_txt = open(os.path.join(ASSETS, "routedata_global.lua"), encoding="utf-8-sig",
                 errors="replace").read()
route_wps = []
for chunk in re.split(r"\n\},\s*\n\{", route_txt):
    m = re.search(r'\["names"\] = "((?:quest target|questziel)[^"]*)', chunk)
    if not m:
        continue
    # the locale separator byte decodes to U+FFFD under errors="replace";
    # keep only the enUS segment
    name = m.group(1).split("�")[0]
    area = re.search(r'\["areaId"\] = (\d+)', chunk)
    wx = re.search(r'\["worldX"\] = ([-\d.]+)', chunk)
    wy = re.search(r'\["worldY"\] = ([-\d.]+)', chunk)
    route_wps.append({
        "name": name,
        "areaId": int(area.group(1)) if area else None,
        "worldX": wx.group(1) if wx else "?",
        "worldY": wy.group(1) if wy else "?",
        "tokens": set(w.lower() for w in re.findall(r"[A-Za-z']{4,}", name)),
    })

STOP = {"quest", "target", "questziel", "north", "south", "east", "west",
        "northwest", "northeast", "southwest", "southeast", "auto", "the",
        "isle", "lake", "shore", "camp", "hill", "vale", "forest"}


def route_matches(qname, zname):
    """Only report a hand-made waypoint when the overlap is convincing:
    two shared tokens, or one shared token of 7+ characters."""
    qtok = set(w.lower() for w in re.findall(r"[A-Za-z']{4,}", qname + " " + (zname or ""))) - STOP
    hits = []
    for wp in route_wps:
        overlap = (wp["tokens"] - STOP) & qtok
        if len(overlap) >= 2 or any(len(t) >= 7 for t in overlap):
            hits.append((len(overlap), wp))
    hits.sort(key=lambda h: -h[0])
    return [h[1] for h in hits[:3]]


# --- creature name -> id (for "Speak to X" quests missing finishedBy) ------
cre_txt = open(os.path.join(ASSETS, "creatures.lua.bak"), encoding="utf-8-sig",
               errors="replace").read()
i = cre_txt.find("SkuDB.NpcData.Names")
i = cre_txt.find('["enUS"] = {', i)
cre_end = cre_txt.find("\n\t},", i)
npc_by_name = {}
for m in re.finditer(r'\[(\d+)\] = \{"((?:[^"\\]|\\.)*)"', cre_txt[i:cre_end]):
    npc_by_name.setdefault(unescape(m.group(2)), []).append(int(m.group(1)))

SPEAK_RE = re.compile(r"[Ss]peak (?:to|with) ((?:[A-Z][\w'-]+[ .]?)+)")


def finishedby_proposal(text):
    """If the objective text names a talk-to NPC we carry, propose its id."""
    m = SPEAK_RE.search(text)
    if not m:
        return None
    cand = m.group(1).strip().rstrip(".")
    # try longest prefix of the captured capitalized words
    words = cand.split()
    for n in range(len(words), 0, -1):
        name = " ".join(words[:n])
        ids = npc_by_name.get(name)
        if ids:
            return name, ids
    return None


# --- classification -------------------------------------------------------
def obj_text(f):
    ot = tbl_pos(f[7])
    return ot[0] if ot and isinstance(ot[0], str) else ""


sec_a, sec_b, sec_c, sec_bl = [], [], [], []
for qid, f in sorted(quests.items()):
    obj = f[9]
    has_target = (has_list(obj, 0) or has_list(obj, 1) or has_list(obj, 2)
                  or has_list(obj, 4) or f[8] is not None
                  or qid in fix_gives_target)
    if has_target:
        continue
    fin = f[2]
    has_finish = has_list(fin, 0) or has_list(fin, 1) or qid in fix_gives_finish
    cls = f[6] if isinstance(f[6], int) else 0
    entry = (qid, cls, has_finish)
    if qid in questie_bl:
        if not has_finish or FIELD_VERBS.search(obj_text(f)):
            sec_bl.append(entry)
        continue
    if not has_finish:
        sec_a.append(entry)
    elif cls > 0 and FIELD_VERBS.search(obj_text(f)):
        sec_b.append(entry)
    elif FIELD_VERBS.search(obj_text(f)):
        sec_c.append(entry)

print("A: no turn-in at all:              %d" % len(sec_a))
print("B: class quests, field objective:  %d" % len(sec_b))
print("C: other quests, field objective:  %d" % len(sec_c))
print("appendix: questie-blacklisted:     %d" % len(sec_bl))


def class_str(mask):
    return "+".join(n for b, n in sorted(CLASS_NAMES.items()) if mask & b) or "-"


def block(qid, cls, has_finish):
    f = quests[qid]
    name = names.get(qid, "(no enUS name)")
    zid = f[16] if isinstance(f[16], int) and f[16] > 0 else None
    zname = zone_names.get(zid) if zid else None
    lines = []
    lines.append("Quest %d: %s" % (qid, name))
    meta = []
    if cls:
        meta.append("class " + class_str(cls))
    meta.append("level %s (min %s)" % (f[4], f[3]))
    if zname:
        meta.append("zone %s (%d)" % (zname, zid))
    elif zid:
        meta.append("zone id %d" % zid)
    meta.append("turn-in " + ("yes" if has_finish else "NO"))
    if qid in questie_bl:
        meta.append("QUESTIE-BLACKLISTED (likely removed/seasonal - probably skip)")
    lines.append("  " + "; ".join(str(x) for x in meta))
    otext = f[7]
    ot = tbl_pos(otext)
    text = ""
    if ot and isinstance(ot[0], str):
        text = ot[0]
        lines.append("  Objective text: " + text[:220])
    if not has_finish:
        prop = finishedby_proposal(text)
        if prop:
            pname, ids = prop
            lines.append("  PROPOSED FIX: finishedBy creature %s = %s (talk-to; no coords needed)"
                         % (pname, ids))
    wc = wiki_coords(name)
    if wc:
        lines.append("  Wiki coords: " + " | ".join(wc))
    else:
        lines.append("  Wiki coords: none found")
    for wp in route_matches(name, zname):
        lines.append("  Routedata waypoint: %s (areaId %s, world %s/%s)"
                     % (wp["name"][:90], wp["areaId"], wp["worldX"], wp["worldY"]))
    return "\n".join(lines)


SECTIONS = [
    ("A: QUESTS WITH NEITHER TARGET NOR TURN-IN (nothing to route at all)", sec_a),
    ("B: CLASS QUESTS WITH A FIELD OBJECTIVE (turn-in exists, but the field step is unguided)", sec_b),
    ("C: OTHER QUESTS WITH A FIELD OBJECTIVE (turn-in exists, but the field step is unguided)", sec_c),
    ("APPENDIX: QUESTIE-BLACKLISTED (likely removed from game or seasonal - probably skip)", sec_bl),
]

n_wiki = 0
with open(OUT, "w", encoding="utf-8", newline="\n") as fh:
    fh.write("Quest-target candidates for hand-authored triggerEnd fixes\n")
    fh.write("Generated by _quest_target_candidates.py - REVIEW LIST, nothing applied.\n")
    fh.write("A fix needs: zone + map-percent coords -> quests_fixes.lua triggerEnd entry.\n")
    fh.write("Wiki coords are map percent (usable directly); routedata world coords are\n")
    fh.write("NOT map percent - they only confirm that a hand-made waypoint exists.\n")
    fh.write("Quests whose objective is only bring/speak/deliver are NOT listed - the\n")
    fh.write("Abgabe entry already routes those.\n\n")
    for title, entries in SECTIONS:
        fh.write("=" * 70 + "\n")
        fh.write("%s (%d)\n" % (title, len(entries)))
        fh.write("=" * 70 + "\n\n")
        for qid, cls, hf in entries:
            b = block(qid, cls, hf)
            if "Wiki coords: none" not in b:
                n_wiki += 1
            fh.write(b + "\n\n")

print("blocks with wiki coordinates: %d" % n_wiki)
print("wrote %s" % OUT)
