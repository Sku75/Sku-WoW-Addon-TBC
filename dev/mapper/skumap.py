"""skumap.py — maintainer-side pipeline for numbered map datasets (SkuMapper).

The exchange model (see dev/mapper/MAPPER-WORKFLOW.md):
  * Every map dataset we hand out has a NUMBER (map id). The registry below
    (seeds.json) maps id -> git commit of Sku/SkuDB/assets/routedata_global.lua,
    so a seed is materialised via `git show` — no extra 20 MB copies.
  * A mapper edits freely, runs `/sku save <comment>` + /reload in game, then
    HandInMapData.bat zips their SavedVariables file. That file (or zip) is the
    contribution; its MapMeta header says which map id it is based on.
  * This tool does a per-waypoint / per-link THREE-WAY MERGE:
    base (the seed) vs contribution vs live (the current tree file). Only
    "both changed the same thing differently" is a conflict; conflicts keep the
    live value and are written to a human-readable report (German, linear text,
    screen-reader friendly). Everything else merges automatically.

Commands (run from anywhere; paths are repo-anchored):
  py -3 dev/mapper/skumap.py status
  py -3 dev/mapper/skumap.py seed [--note "text"]
      Register the CURRENT COMMITTED routedata_global.lua as the next map id
      and stamp SkuMapper/SkuDB/assets/mapid.lua for packaging. Refuses if the
      file has uncommitted changes.
  py -3 dev/mapper/skumap.py merge <contribution.zip|SkuMapper.lua> [more ...]
      [--base N] [--base-file PATH] [--assume-base-live] [--dry-run]
      Merge one or more contributions (in order) into the live route file.
      Base resolution per contribution: its MapMeta.basedOn -> seeds.json;
      --base/--base-file override; --assume-base-live treats the live file as
      the base (bootstrap only: every change in the contribution then wins).
      Writes the merged pristine body to routedata_global.lua.bak, re-wraps the
      shipped file via dev/rework-docs/_wrap_deferred.py, regenerates the zone
      dumps and writes a merge report under dev/mapper/reports/.
  py -3 dev/mapper/skumap.py dump
      Regenerate dev/mapper/zones/*.txt from the live file (one line per
      waypoint, links inline) — the git-diffable view of the map data.
  py -3 dev/mapper/skumap.py selftest
      Synthetic three-way merge exercise + parser/serialiser round-trip on the
      real live file. Run after changing this tool.

Data-format notes (all verified against the live tree):
  * The shipped route file is the "sections" wrapper from _wrap_deferred.py:
    per-section builder functions whose loadstring blobs are byte-exact slices
    of the pristine body. Unwrapping = concatenating the blobs.
  * Waypoint identity is ARRAY POSITION; deletions are {false} tombstones so
    positions never shift within one lineage. Custom waypoint id packing
    (SkuNav:BuildWpIdFromData): id = dbIndex + base(type) + (areaId << 20)
    + (spawn << 38); custom = base 0, spawn 1. Appended waypoints from a
    contribution get NEW positions here, and every link/level key referencing
    them is remapped.
  * Names are one packed string per waypoint, "§"-separated, positional per
    Sku.Locs (enUS, deDE, frFR). Trailing empty fields are insignificant.
  * SequenceNumbers only ever grow; a both-changed sequence merges as max().
  * The four "Quick Waypoint;N" records at the head of the array are player
    conveniences, not map data: contribution changes to them are ignored.
"""

import json
import os
import re
import subprocess
import sys
import zipfile
from datetime import datetime

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
LIVE_REL = "Sku/SkuDB/assets/routedata_global.lua"
LIVE = os.path.join(ROOT, *LIVE_REL.split("/"))
SEEDS_JSON = os.path.join(HERE, "seeds.json")
ZONES_DIR = os.path.join(HERE, "zones")
REPORTS_DIR = os.path.join(HERE, "reports")
INBOX_DIR = os.path.join(HERE, "inbox")
MAPID_LUA = os.path.join(ROOT, "SkuMapper", "SkuDB", "assets", "mapid.lua")
WRAP_PY = os.path.join(ROOT, "dev", "rework-docs", "_wrap_deferred.py")

QUICK_WP_PREFIX = "Quick Waypoint;"
CUSTOM_SPAWN_SHIFT = 1 << 38
AREA_SHIFT = 1 << 20


# =============================================================== value model
class Num:
    """A Lua number keeping its source text, so untouched values re-serialise
    byte-identically (WoW prints e.g. 838.2000122070312; Python repr would
    shorten it and churn every line)."""
    __slots__ = ("value", "raw")

    def __init__(self, value, raw=None):
        self.value = value
        self.raw = raw if raw is not None else fmt_number(value)

    def __eq__(self, other):
        if isinstance(other, Num):
            return self.value == other.value
        return NotImplemented

    def __hash__(self):
        return hash(self.value)

    def __repr__(self):
        return "Num(%s)" % self.raw


def fmt_number(v):
    if isinstance(v, int) or (isinstance(v, float) and v.is_integer()):
        return "%d" % int(v)
    return repr(v)


class LTable:
    """arr = positional part (list), hash = keyed part (dict, int|str keys)."""
    __slots__ = ("arr", "hash")

    def __init__(self):
        self.arr = []
        self.hash = {}

    def __eq__(self, other):
        if not isinstance(other, LTable):
            return NotImplemented
        return self.arr == other.arr and self.hash == other.hash

    def __repr__(self):
        return "LTable(arr=%d, hash=%d)" % (len(self.arr), len(self.hash))


# ================================================================== tokenizer
TOKEN_RE = re.compile(
    r'(?P<ws>\s+)'
    r'|(?P<comment>--[^\n]*)'
    r'|(?P<string>"(?:\\.|[^"\\])*")'
    r'|(?P<number>-?(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)'
    r'|(?P<name>[A-Za-z_][A-Za-z0-9_]*)'
    r'|(?P<punct>[{}\[\]=,;()])'
)


class Tokens:
    """Streaming tokenizer with one-token lookahead (files are 20+ MB; a
    materialised token list would cost hundreds of MB)."""

    def __init__(self, text, pos=0):
        self.text = text
        self.pos = pos
        self._peeked = None

    def _next_raw(self):
        text, pos = self.text, self.pos
        n = len(text)
        while pos < n:
            m = TOKEN_RE.match(text, pos)
            if not m:
                raise SyntaxError("bad token at offset %d: %r" % (pos, text[pos:pos + 40]))
            pos = m.end()
            kind = m.lastgroup
            if kind in ("ws", "comment"):
                continue
            self.pos = pos
            return kind, m.group()
        self.pos = pos
        return None, None

    def peek(self):
        if self._peeked is None:
            self._peeked = self._next_raw()
        return self._peeked

    def take(self):
        if self._peeked is not None:
            t, self._peeked = self._peeked, None
            return t
        return self._next_raw()

    def expect(self, value):
        kind, tok = self.take()
        if tok != value:
            raise SyntaxError("expected %r, got %r (offset %d)" % (value, tok, self.pos))


def parse_value(tk):
    kind, tok = tk.take()
    if kind == "string":
        return tok[1:-1]  # raw inner text, escapes intact
    if kind == "number":
        try:
            return Num(int(tok), tok)
        except ValueError:
            return Num(float(tok), tok)
    if kind == "name":
        if tok == "true":
            return True
        if tok == "false":
            return False
        if tok == "nil":
            return None
        raise SyntaxError("unexpected name %r as value" % tok)
    if tok == "{":
        return parse_table(tk)
    raise SyntaxError("unexpected token %r" % (tok,))


def parse_table(tk):
    """Parse the inside of a table constructor; the opening '{' is consumed."""
    t = LTable()
    while True:
        kind, tok = tk.peek()
        if tok is None:
            raise SyntaxError("unterminated table")
        if tok == "}":
            tk.take()
            return t
        if tok == "[":
            tk.take()
            key = parse_value(tk)
            if isinstance(key, Num):
                key = int(key.value) if float(key.value).is_integer() else key.value
            tk.expect("]")
            tk.expect("=")
            t.hash[key] = parse_value(tk)
        elif kind == "name" and tok not in ("true", "false", "nil"):
            # bare-name key (name = value)
            tk.take()
            tk.expect("=")
            t.hash[tok] = parse_value(tk)
        else:
            v = parse_value(tk)
            if v is None:
                # positional nil hole (WoW writes them in mixed tables):
                # keep position by storing None
                t.arr.append(None)
            else:
                t.arr.append(v)
        kind, tok = tk.peek()
        if tok in (",", ";"):
            tk.take()


# ================================================================= serializer
WP_FIELD_ORDER = ["names", "areaId", "contintentId", "worldX", "worldY",
                  "size", "phase", "createdBy", "createdAt", "lComments"]


def hash_key_sort(k):
    return (0, k, "") if isinstance(k, (int, float)) else (1, 0, k)


def serialize_value(v, out, field_order=None):
    if isinstance(v, LTable):
        out.append("{\n")
        for item in v.arr:
            if item is None:
                out.append("nil,\n")
            else:
                serialize_value(item, out)
                out.append(",\n")
        keys = list(v.hash.keys())
        if field_order:
            order_index = {name: i for i, name in enumerate(field_order)}
            keys.sort(key=lambda k: (order_index.get(k, len(field_order)),) + hash_key_sort(k))
        else:
            keys.sort(key=hash_key_sort)
        for k in keys:
            val = v.hash[k]
            if val is None:
                continue
            if isinstance(k, (int, float)):
                out.append("[%s] = " % fmt_number(k))
            else:
                out.append('["%s"] = ' % k)
            serialize_value(val, out)
            out.append(",\n")
        out.append("}")
    elif isinstance(v, Num):
        out.append(v.raw)
    elif isinstance(v, str):
        out.append('"%s"' % v)
    elif v is True:
        out.append("true")
    elif v is False:
        out.append("false")
    else:
        raise TypeError("cannot serialise %r" % (v,))


def serialize_section(name, table):
    out = ['["%s"] = ' % name]
    if name == "WaypointsNew":
        # array of records: serialise each record with the canonical field order
        out.append("{\n")
        for rec in table.arr:
            serialize_value(rec, out, field_order=WP_FIELD_ORDER)
            out.append(",\n")
        out.append("}")
    else:
        serialize_value(table, out)
    out.append(",\n")
    return "".join(out)


# ======================================================== route file handling
def read_file_text(path_or_bytes):
    if isinstance(path_or_bytes, bytes):
        raw = path_or_bytes
    else:
        with open(path_or_bytes, "rb") as f:
            raw = f.read()
    bom = raw.startswith(b"\xef\xbb\xbf")
    return raw.decode("utf-8-sig"), bom


def scan_table_end(text, start):
    """Index just past the '}' matching the '{' at text[start-1] (depth 1 at
    start). Skips strings and line comments."""
    i, n, depth = start, len(text), 1
    while i < n:
        c = text[i]
        if c == '"':
            i += 1
            while i < n:
                d = text[i]
                if d == "\\":
                    i += 2
                    continue
                i += 1
                if d == '"':
                    break
            continue
        if c == "-" and text[i + 1:i + 2] == "-":
            j = text.find("\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise SyntaxError("unbalanced braces")


def read_routedata(path_or_bytes):
    """-> (sections: {name: LTable}, section_order, root_name, version_or_None,
    bom). Accepts the wrapped ("sections") form and the pristine body form."""
    text, bom = read_file_text(path_or_bytes)
    root_m = re.search(r'^(SkuDB[A-Za-z]*)\s*=', text, re.M)
    root = root_m.group(1) if root_m else "SkuDB"
    ver_m = re.search(r'\.routedata\.version\s*=\s*([0-9.]+)', text)
    version = ver_m.group(1) if ver_m else None

    sections = {}
    order = []
    if "-- GENERATED WRAPPER" in text[:400]:
        for m in re.finditer(r'\["([A-Za-z][A-Za-z0-9_]*)"\]\s*=\s*loadstring\((\[=*\[)return \{\n', text):
            name = m.group(1)
            op = m.group(2)
            cl = "]" + "=" * (len(op) - 2) + "]"
            end = text.index("\n}" + cl, m.end())
            blob = text[m.end():end + 1]
            tk = Tokens("{" + blob + "}")
            tk.expect("{")
            t = parse_table(tk)
            if name not in t.hash:
                raise SyntaxError("section blob %s lacks its own key" % name)
            sections[name] = t.hash[name]
            order.append(name)
    else:
        m = re.search(r'\.routedata\["global"\]\s*=\s*[^\n{]*\{', text)
        if not m:
            raise SyntaxError('no routedata["global"] assignment found')
        tk = Tokens(text, m.end() - 1)
        tk.expect("{")
        t = parse_table(tk)
        for k in t.hash:
            sections[k] = t.hash[k]
            order.append(k)
    return sections, order, root, version, bom


def write_pristine(path, sections, order, root, version, bom):
    out = []
    out.append("%s = %s or {}\n" % (root, root))
    out.append("%s.SessionRouteData = %s.SessionRouteData or {}\n" % (root, root))
    out.append("%s.routedata = %s.routedata or {}\n" % (root, root))
    if version is not None:
        out.append("%s.routedata.version = %s\n" % (root, version))
    out.append('%s.routedata["global"] = {\n' % root)
    for name in order:
        out.append(serialize_section(name, sections[name]))
    out.append("}\n")
    data = "".join(out).encode("utf-8")
    if bom:
        data = b"\xef\xbb\xbf" + data
    with open(path, "wb") as f:
        f.write(data)


# ========================================================= contribution files
def read_contribution(path):
    """-> dict(waypoints=LTable, links=LTable, levels=LTable, seq=LTable,
    meta=dict, seed_map_id=int, source=str). Accepts the raw SavedVariables
    .lua or a HandInMapData.bat zip containing it."""
    if path.lower().endswith(".zip"):
        with zipfile.ZipFile(path) as z:
            lua_names = [n for n in z.namelist() if n.lower().endswith(".lua")]
            if not lua_names:
                raise SystemExit("ERROR: no .lua file inside %s" % path)
            raw = z.read(lua_names[0])
        text, _ = read_file_text(raw)
    else:
        text, _ = read_file_text(path)

    m = re.search(r'^SkuOptionsDB\s*=\s*\{', text, re.M)
    if not m:
        raise SystemExit("ERROR: no SkuOptionsDB table in %s (not a SkuMapper SavedVariables file?)" % path)
    tk = Tokens(text, m.end() - 1)
    tk.expect("{")
    db = parse_table(tk)
    g = db.hash.get("global")
    nav = g.hash.get("SkuNav") if isinstance(g, LTable) else None
    if not isinstance(nav, LTable):
        raise SystemExit("ERROR: no global.SkuNav data in %s" % path)

    wps = nav.hash.get("WaypointsNew")
    if not isinstance(wps, LTable) or not wps.arr:
        raise SystemExit(
            "ERROR: no WaypointsNew in %s.\n"
            "The mapper must run /sku save and then /reload IN GAME before the\n"
            "file is handed in (only the reload writes the packed data)." % path)

    meta_t = nav.hash.get("MapMeta")
    meta = {}
    if isinstance(meta_t, LTable):
        for k, v in meta_t.hash.items():
            meta[k] = v.value if isinstance(v, Num) else v
    seed_id = nav.hash.get("seedMapId")
    seed_id = int(seed_id.value) if isinstance(seed_id, Num) else 0

    return {
        "waypoints": wps,
        "links": nav.hash.get("Links") or LTable(),
        "levels": nav.hash.get("WaypointLevels") or LTable(),
        "seq": nav.hash.get("SequenceNumbers") or LTable(),
        "meta": meta,
        "seed_map_id": seed_id,
        "source": os.path.basename(path),
    }


# ================================================================== id packing
def unpack_id(wid):
    wid = int(wid)
    spawn = wid >> 38
    rest = wid - (spawn << 38)
    area = rest >> 20
    db_index = rest - (area << 20)
    if db_index < 200000:
        return 1, db_index, spawn, area
    if db_index < 500000:
        return 2, db_index - 200000, spawn, area
    return 3, db_index - 500000, spawn, area


def pack_custom(db_index, area):
    return db_index + (area << 20) + CUSTOM_SPAWN_SHIFT


# =========================================================== record utilities
def is_tombstone(rec):
    return isinstance(rec, LTable) and rec.arr and rec.arr[0] is False


def split_names(rec):
    packed = rec.hash.get("names")
    if not isinstance(packed, str):
        return []
    fields = packed.split("§")
    while len(fields) > 1 and fields[-1] == "":
        fields.pop()
    return fields


def en_name(rec):
    f = split_names(rec)
    return f[0] if f else ""


def rec_area(rec):
    a = rec.hash.get("areaId")
    return int(a.value) if isinstance(a, Num) else 0


def wp_equal(a, b):
    """Waypoint-record equality for the three-way compare. Deep equality with
    one normalisation: packed names compare after trailing-empty-field trim."""
    if is_tombstone(a) or is_tombstone(b):
        return is_tombstone(a) and is_tombstone(b)
    if not isinstance(a, LTable) or not isinstance(b, LTable):
        return a == b
    if split_names(a) != split_names(b):
        return False
    ka = set(a.hash) - {"names"}
    kb = set(b.hash) - {"names"}
    if ka != kb:
        return False
    for k in ka:
        if a.hash[k] != b.hash[k]:
            return False
    return a.arr == b.arr


def wp_brief(rec, lua_idx):
    if is_tombstone(rec):
        return "#%d GELOESCHT" % lua_idx
    x = rec.hash.get("worldX")
    y = rec.hash.get("worldY")
    return "#%d '%s' (areaId %d, x=%s y=%s)" % (
        lua_idx, en_name(rec), rec_area(rec),
        x.raw if isinstance(x, Num) else "?", y.raw if isinstance(y, Num) else "?")


def wp_diff_lines(base, other, label):
    """Field-level description of what `other` changed vs `base` — the report
    must let a human decide without reading Lua."""
    lines = []
    if is_tombstone(other):
        return ["  %s: Wegpunkt geloescht." % label]
    if is_tombstone(base):
        return ["  %s: Wegpunkt neu angelegt: %s" % (label, wp_brief(other, 0)[3:])]
    if split_names(base) != split_names(other):
        lines.append("  %s: Name '%s' -> '%s'" % (label, "§".join(split_names(base)), "§".join(split_names(other))))
    keys = sorted(set(base.hash) | set(other.hash) - {"names"}, key=str)
    for k in keys:
        if k == "names":
            continue
        bv, ov = base.hash.get(k), other.hash.get(k)
        if bv != ov:
            def show(v):
                if isinstance(v, Num):
                    return v.raw
                if isinstance(v, LTable):
                    return "<tabelle>"
                return repr(v)
            lines.append("  %s: %s %s -> %s" % (label, k, show(bv), show(ov)))
    return lines or ["  %s: (Detailunterschied in Untertabellen)" % label]


# ============================================================ links utilities
def flatten_links(links):
    edges = {}
    for src, targets in links.hash.items():
        if not isinstance(targets, LTable):
            continue
        for dst, dist in targets.hash.items():
            edges[(int(src), int(dst))] = dist
    return edges


def rebuild_links(edges):
    t = LTable()
    for (src, dst), dist in edges.items():
        inner = t.hash.get(src)
        if inner is None:
            inner = LTable()
            t.hash[src] = inner
        inner.hash[dst] = dist
    return t


def remap_id(wid, idmap):
    return idmap.get(int(wid), int(wid))


# ==================================================================== registry
def load_seeds():
    if os.path.exists(SEEDS_JSON):
        with open(SEEDS_JSON, encoding="utf-8") as f:
            return json.load(f)
    return {"current": 0, "seeds": {}}


def save_seeds(reg):
    with open(SEEDS_JSON, "w", encoding="utf-8") as f:
        json.dump(reg, f, indent=2, ensure_ascii=False)
        f.write("\n")


def git(*args):
    return subprocess.run(["git"] + list(args), cwd=ROOT, capture_output=True,
                          text=True, encoding="utf-8", errors="replace")


def seed_data(map_id, reg):
    info = reg["seeds"].get(str(map_id))
    if not info:
        raise SystemExit("ERROR: map id %s is not in seeds.json — register seeds with the 'seed' command." % map_id)
    r = subprocess.run(["git", "show", "%s:%s" % (info["commit"], LIVE_REL)],
                       cwd=ROOT, capture_output=True)
    if r.returncode != 0:
        raise SystemExit("ERROR: git show failed for seed %s: %s" % (map_id, r.stderr[:400]))
    return read_routedata(r.stdout)


# ======================================================================= merge
class Report:
    def __init__(self):
        self.lines = []
        self.conflicts = 0
        self.notes = 0

    def head(self, s):
        self.lines += ["", s, "=" * len(s)]

    def sub(self, s):
        self.lines += ["", s, "-" * len(s)]

    def conflict(self, *ls):
        self.conflicts += 1
        self.lines += ["", "KONFLIKT %d:" % self.conflicts] + list(ls)

    def note(self, *ls):
        self.notes += 1
        self.lines += list(ls)

    def plain(self, *ls):
        self.lines += list(ls)


def merge_contribution(live, contrib, base, report):
    """Mutates `live` (sections dict). Returns stats dict."""
    stats = dict(modified=0, deleted=0, appended=0, same=0,
                 links_added=0, links_removed=0, links_changed=0,
                 levels_changed=0, seq_changed=0, skipped_quick=0)

    base_arr = base["WaypointsNew"].arr
    live_arr = live["WaypointsNew"].arr
    c_arr = contrib["waypoints"].arr
    n_base = len(base_arr)

    if len(c_arr) < n_base:
        raise SystemExit(
            "ERROR: contribution has fewer waypoints (%d) than its base (%d) — "
            "wrong base map id, or a corrupted file. Nothing merged." % (len(c_arr), n_base))
    if len(live_arr) < n_base:
        raise SystemExit(
            "ERROR: live file has fewer waypoints (%d) than the base (%d) — the "
            "declared base is NOT an ancestor of the live data. Check the map id." % (len(live_arr), n_base))

    live_names = set()
    for rec in live_arr:
        if isinstance(rec, LTable) and not is_tombstone(rec):
            live_names.add(en_name(rec))

    # ---- existing positions: classic three-way, position = identity
    for i in range(n_base):
        b, c, l = base_arr[i], c_arr[i], live_arr[i]
        if wp_equal(b, c):
            stats["same"] += 1
            continue
        if en_name(b).startswith(QUICK_WP_PREFIX) or en_name(c).startswith(QUICK_WP_PREFIX):
            stats["skipped_quick"] += 1
            continue
        if wp_equal(b, l):
            live_arr[i] = c
            if is_tombstone(c):
                stats["deleted"] += 1
            else:
                stats["modified"] += 1
                live_names.add(en_name(c))
        elif wp_equal(c, l):
            pass  # both made the same change
        else:
            report.conflict(
                "Wegpunkt %s" % wp_brief(b, i + 1),
                "  Beide Seiten haben denselben Wegpunkt unterschiedlich geaendert.",
                *(wp_diff_lines(b, c, "Beitrag") + wp_diff_lines(b, l, "Live")),
                "  ENTSCHEIDUNG: Live-Version behalten. Beitrag-Version oben zum Nachpruefen.")

    # ---- appended waypoints: re-index onto the end of live, remap their ids
    idmap = {}
    for i in range(n_base, len(c_arr)):
        c = c_arr[i]
        if is_tombstone(c):
            continue  # created and deleted within the same round: nothing to keep
        area = rec_area(c)
        old_id = pack_custom(i + 1, area)
        nm = en_name(c)
        if nm in live_names:
            f = split_names(c)
            f = [(x + " (2)") if x != "" else x for x in f]
            c.hash["names"] = "§".join(f)
            report.note("HINWEIS: Neuer Wegpunkt '%s' kollidierte mit einem vorhandenen Namen "
                        "und wurde zu '%s' umbenannt." % (nm, en_name(c)))
            nm = en_name(c)
        live_arr.append(c)
        live_names.add(nm)
        new_id = pack_custom(len(live_arr), area)
        idmap[old_id] = new_id
        stats["appended"] += 1

    # ---- links: three-way per edge, contribution ids remapped first
    base_edges = flatten_links(base["Links"]) if "Links" in base else {}
    live_edges = flatten_links(live["Links"]) if "Links" in live else {}
    c_edges = {}
    for (src, dst), dist in flatten_links(contrib["links"]).items():
        c_edges[(remap_id(src, idmap), remap_id(dst, idmap))] = dist

    for e in set(base_edges) | set(c_edges):
        b, c, l = base_edges.get(e), c_edges.get(e), live_edges.get(e)
        if b == c:
            continue
        if c is None:                      # deleted in the contribution
            if l is None:
                pass
            elif l == b:
                del live_edges[e]
                stats["links_removed"] += 1
            else:
                report.conflict(
                    "Verbindung %s -> %s" % (edge_name(e[0], live_arr), edge_name(e[1], live_arr)),
                    "  Beitrag hat die Verbindung geloescht, Live hat ihre Distanz geaendert.",
                    "  ENTSCHEIDUNG: Live-Version behalten (Verbindung bleibt).")
        elif b is None:                    # added in the contribution
            if l is None:
                live_edges[e] = c
                stats["links_added"] += 1
            elif l == c:
                pass
            else:
                live_edges[e] = c
                stats["links_changed"] += 1
                report.note("HINWEIS: Verbindung %s -> %s wurde von beiden Seiten neu angelegt; "
                            "Distanz des Beitrags uebernommen." % (edge_name(e[0], live_arr), edge_name(e[1], live_arr)))
        else:                              # distance changed in the contribution
            if l == b:
                live_edges[e] = c
                stats["links_changed"] += 1
            elif l == c:
                pass
            else:
                report.conflict(
                    "Verbindung %s -> %s" % (edge_name(e[0], live_arr), edge_name(e[1], live_arr)),
                    "  Beide Seiten haben die Distanz unterschiedlich geaendert (Beitrag %s, Live %s)."
                    % (show_num(c), show_num(l)),
                    "  ENTSCHEIDUNG: Live-Version behalten.")
    live["Links"] = rebuild_links(live_edges)

    # ---- waypoint levels (layer assignment per waypoint id)
    base_lv = base.get("WaypointLevels") or LTable()
    live_lv = live.get("WaypointLevels") or LTable()
    live["WaypointLevels"] = live_lv
    for k, cv in contrib["levels"].hash.items():
        k2 = remap_id(k, idmap)
        bv = base_lv.hash.get(int(k))
        lv = live_lv.hash.get(k2)
        if cv == bv:
            continue
        if lv == bv or lv is None:
            live_lv.hash[k2] = cv
            stats["levels_changed"] += 1
        elif lv == cv:
            pass
        else:
            report.conflict(
                "Ebenen-Zuordnung fuer Wegpunkt %s" % edge_name(k2, live_arr),
                "  Beitrag %s, Live %s — Live behalten." % (show_num(cv), show_num(lv)))
    for k, bv in base_lv.hash.items():     # deletions of a level assignment
        if int(k) not in {int(x) for x in contrib["levels"].hash} and k in live_lv.hash:
            if live_lv.hash[k] == bv:
                del live_lv.hash[k]
                stats["levels_changed"] += 1

    # ---- sequence numbers: counters only grow -> both-changed merges as max
    base_sq = seq_as_dict(base.get("SequenceNumbers"))
    live_sq_t = live.get("SequenceNumbers") or LTable()
    live_sq = seq_as_dict(live_sq_t)
    for k, cv in seq_as_dict(contrib["seq"]).items():
        bv, lv = base_sq.get(k), live_sq.get(k)
        if cv == bv:
            continue
        if lv is None or lv == bv:
            live_sq[k] = cv
            stats["seq_changed"] += 1
        elif lv != cv:
            mx = cv if cv.value >= lv.value else lv
            if mx is not lv:
                live_sq[k] = mx
                stats["seq_changed"] += 1
    t = LTable()
    t.hash.update(live_sq)
    live["SequenceNumbers"] = t
    return stats


def seq_as_dict(seq):
    d = {}
    if not isinstance(seq, LTable):
        return d
    for i, v in enumerate(seq.arr):
        if v is not None:
            d[i + 1] = v
    for k, v in seq.hash.items():
        if v is not None:
            d[int(k)] = v
    return d


def show_num(v):
    return v.raw if isinstance(v, Num) else repr(v)


def edge_name(wid, live_arr):
    tid, dbi, spawn, area = unpack_id(wid)
    if tid == 1 and 1 <= dbi <= len(live_arr):
        rec = live_arr[dbi - 1]
        if isinstance(rec, LTable) and not is_tombstone(rec):
            return "'%s' (#%d)" % (en_name(rec), dbi)
        return "#%d (geloescht)" % dbi
    kind = {1: "custom", 2: "creature", 3: "object"}[tid]
    return "%s %d (spawn %d, areaId %d)" % (kind, dbi, spawn, area)


# ================================================================== zone dumps
def write_zone_dumps(sections):
    os.makedirs(ZONES_DIR, exist_ok=True)
    arr = sections["WaypointsNew"].arr
    links = sections.get("Links") or LTable()

    by_area = {}
    for i, rec in enumerate(arr):
        if isinstance(rec, LTable) and not is_tombstone(rec):
            by_area.setdefault(rec_area(rec), []).append(i)

    out_links = {}
    for src, targets in links.hash.items():
        _, _, _, area = unpack_id(src)
        if isinstance(targets, LTable):
            out_links.setdefault(area, []).append((int(src), targets))

    old = {f for f in os.listdir(ZONES_DIR) if f.endswith(".txt")}
    written = set()
    for area in sorted(set(by_area) | set(out_links)):
        fname = "area-%d.txt" % area
        written.add(fname)
        lines = ["Zone areaId %d — eine Zeile pro Wegpunkt; Links inline." % area, ""]
        for i in by_area.get(area, []):
            rec = arr[i]
            x = rec.hash.get("worldX")
            y = rec.hash.get("worldY")
            size = rec.hash.get("size")
            phase = rec.hash.get("phase")
            parts = ["#%d" % (i + 1), "§".join(split_names(rec)),
                     "x=%s y=%s" % (x.raw if isinstance(x, Num) else "?",
                                    y.raw if isinstance(y, Num) else "?"),
                     "size=%s" % (size.raw if isinstance(size, Num) else "?")]
            if isinstance(phase, str):
                parts.append("phase=" + phase)
            wid = pack_custom(i + 1, area)
            targets = links.hash.get(wid)
            if isinstance(targets, LTable) and targets.hash:
                ls = []
                for dst in sorted(targets.hash, key=int):
                    ls.append("%s:%s" % (edge_ref(dst, arr), show_num(targets.hash[dst])))
                parts.append("links=" + " ".join(ls))
            lines.append(" | ".join(parts))
        extra = [(s, t) for s, t in out_links.get(area, [])
                 if unpack_id(s)[0] != 1]
        if extra:
            lines += ["", "Kreatur-/Objekt-Verbindungsquellen in dieser Zone:"]
            for src, targets in sorted(extra):
                ls = ["%s:%s" % (edge_ref(d, arr), show_num(targets.hash[d]))
                      for d in sorted(targets.hash, key=int)]
                lines.append("%s | links=%s" % (edge_ref(src, arr), " ".join(ls)))
        with open(os.path.join(ZONES_DIR, fname), "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines) + "\n")
    for stale in sorted(old - written):
        os.remove(os.path.join(ZONES_DIR, stale))
    return len(written)


def edge_ref(wid, arr):
    tid, dbi, spawn, area = unpack_id(wid)
    if tid == 1:
        if 1 <= dbi <= len(arr) and isinstance(arr[dbi - 1], LTable) and not is_tombstone(arr[dbi - 1]):
            return "#%d(%s)" % (dbi, en_name(arr[dbi - 1]))
        return "#%d(?)" % dbi
    return "%s%d.%d" % ("co"[tid - 2], dbi, spawn)


# ==================================================================== commands
def cmd_status():
    reg = load_seeds()
    print("Current map id: %s" % reg["current"])
    for mid in sorted(reg["seeds"], key=int):
        s = reg["seeds"][mid]
        print("  map %s  commit %s  %s  %s" % (mid, s["commit"][:10], s.get("date", ""), s.get("note", "")))
    if os.path.exists(LIVE):
        r = git("status", "--porcelain", "--", LIVE_REL)
        dirty = bool(r.stdout.strip())
        print("Live file: %s (%s)" % (LIVE_REL, "UNCOMMITTED CHANGES" if dirty else "clean"))
    else:
        print("Live file MISSING: %s" % LIVE_REL)


def cmd_seed(note):
    r = git("status", "--porcelain", "--", LIVE_REL)
    if r.stdout.strip():
        raise SystemExit("ERROR: %s has uncommitted changes. Commit the merged data first —\n"
                         "a seed must be reproducible from git." % LIVE_REL)
    commit = git("rev-parse", "HEAD").stdout.strip()
    reg = load_seeds()
    new_id = reg["current"] + 1
    reg["seeds"][str(new_id)] = {
        "commit": commit,
        "date": datetime.now().strftime("%Y-%m-%d"),
        "note": note or "",
    }
    reg["current"] = new_id
    save_seeds(reg)

    with open(MAPID_LUA, encoding="utf-8-sig") as f:
        mapid_src = f.read()
    mapid_src = re.sub(r"SKUMAPPER_SEED_MAPID\s*=\s*\d+", "SKUMAPPER_SEED_MAPID = %d" % new_id, mapid_src)
    with open(MAPID_LUA, "w", encoding="utf-8", newline="\n") as f:
        f.write(mapid_src)

    print("Registered map %d (commit %s)." % (new_id, commit[:10]))
    print("Stamped %s." % os.path.relpath(MAPID_LUA, ROOT))
    print("NEXT: commit seeds.json + mapid.lua, then package SkuMapper with the")
    print("      current routedata_global.lua (copy Sku/SkuDB/assets/routedata_global.lua")
    print("      into the package's SkuMapper/SkuDB/assets/).")


def cmd_merge(paths, base_override, base_file, assume_base_live, dry_run):
    live_secs, order, root, version, bom = read_routedata(LIVE)
    if "WaypointsNew" not in live_secs:
        raise SystemExit("ERROR: live file has no WaypointsNew section")
    reg = load_seeds()
    report = Report()
    report.plain("Sku Kartendaten — Merge-Bericht %s" % datetime.now().strftime("%Y-%m-%d %H:%M"),
                 "Konflikt-Regel: bei 'beide Seiten anders geaendert' bleibt IMMER die",
                 "Live-Version; der Beitrag steht daneben zum Nachpruefen im Spiel.")
    total = []

    for path in paths:
        contrib = read_contribution(path)
        meta = contrib["meta"]
        based_on = base_override or meta.get("basedOn") or contrib["seed_map_id"]
        based_on = int(based_on.value) if isinstance(based_on, Num) else int(based_on or 0)

        report.head("Beitrag: %s" % contrib["source"])
        report.plain("Mapper: %s (%s)  Phase: %s  Gespeichert: %s  Tool: %s" % (
            meta.get("mapper", "?"), meta.get("realm", "?"), meta.get("phase", "?"),
            meta.get("savedAt", "?"), meta.get("tool", "?")))
        if meta.get("comment"):
            report.plain("Kommentar: %s" % meta["comment"])
        report.plain("Basis: Karte %s" % based_on)

        if base_file:
            base_secs, _, _, _, _ = read_routedata(base_file)
        elif assume_base_live:
            print("WARNING: --assume-base-live — every change in %s wins against the seed." % contrib["source"])
            base_secs, _, _, _, _ = read_routedata(LIVE)
        elif based_on > 0:
            base_secs, _, _, _, _ = seed_data(based_on, reg)
        else:
            raise SystemExit(
                "ERROR: %s declares no usable base map id (basedOn=0 — an old package).\n"
                "Pass --base N, --base-file PATH, or --assume-base-live (bootstrap)." % contrib["source"])

        stats = merge_contribution(live_secs, contrib, base_secs, report)
        total.append((contrib["source"], stats))
        report.sub("Ergebnis fuer %s" % contrib["source"])
        report.plain("Wegpunkte: %d geaendert, %d geloescht, %d neu, %d unveraendert (Quick-Wegpunkte ignoriert: %d)"
                     % (stats["modified"], stats["deleted"], stats["appended"], stats["same"], stats["skipped_quick"]))
        report.plain("Verbindungen: %d neu, %d entfernt, %d Distanz geaendert" %
                     (stats["links_added"], stats["links_removed"], stats["links_changed"]))
        report.plain("Ebenen geaendert: %d, Sequenzzaehler geaendert: %d" %
                     (stats["levels_changed"], stats["seq_changed"]))

        os.makedirs(INBOX_DIR, exist_ok=True)
        dst = os.path.join(INBOX_DIR, datetime.now().strftime("%Y%m%d-%H%M%S-") + os.path.basename(path))
        if os.path.abspath(path) != os.path.abspath(dst):
            with open(path, "rb") as fsrc, open(dst, "wb") as fdst:
                fdst.write(fsrc.read())

    report.head("Zusammenfassung")
    report.plain("%d Beitrag/Beitraege verarbeitet, %d Konflikt(e), %d Hinweis(e)."
                 % (len(total), report.conflicts, report.notes))
    if report.conflicts:
        report.plain("Alle Konflikte oben einzeln aufgefuehrt; ueberall wurde die Live-Version behalten.",
                     "Zum Nachpruefen im Spiel an die genannte Stelle gehen — das Spiel ist der Schiedsrichter.")

    os.makedirs(REPORTS_DIR, exist_ok=True)
    rpath = os.path.join(REPORTS_DIR, "merge-%s.txt" % datetime.now().strftime("%Y-%m-%d-%H%M%S"))
    with open(rpath, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(report.lines) + "\n")

    print("Report: %s" % os.path.relpath(rpath, ROOT))
    for src, st in total:
        print("  %s: wp +%d ~%d -%d, links +%d ~%d -%d, conflicts so far %d" % (
            src, st["appended"], st["modified"], st["deleted"],
            st["links_added"], st["links_changed"], st["links_removed"], report.conflicts))

    if dry_run:
        print("DRY RUN — nothing written to the route file.")
        return

    bak = LIVE + ".bak"
    write_pristine(bak, live_secs, order, root, version, bom)
    print("Wrote merged pristine body: %s" % os.path.relpath(bak, ROOT))
    r = subprocess.run([sys.executable, WRAP_PY], cwd=ROOT, capture_output=True, text=True,
                       encoding="utf-8", errors="replace")
    sys.stdout.write(r.stdout)
    if r.returncode != 0:
        sys.stdout.write(r.stderr)
        raise SystemExit("ERROR: _wrap_deferred.py failed — the live file was NOT safely rewrapped. "
                         "The pristine body is in %s.bak; fix and re-run the wrapper." % LIVE_REL)
    n = write_zone_dumps(live_secs)
    print("Zone dumps: %d files under dev/mapper/zones/" % n)
    print("NEXT: review the report, syntax-gate + in-game check, commit, then run 'seed' to")
    print("      register the result as the next numbered map.")


def cmd_dump():
    live_secs, _, _, _, _ = read_routedata(LIVE)
    n = write_zone_dumps(live_secs)
    print("Zone dumps: %d files under dev/mapper/zones/" % n)


# ==================================================================== selftest
def _mk_wp(name_en, name_de, area, x, y, size=1, phase=None):
    t = LTable()
    t.hash["names"] = "%s§%s" % (name_en, name_de)
    t.hash["areaId"] = Num(area)
    t.hash["contintentId"] = Num(0)
    t.hash["worldX"] = Num(float(x), repr(float(x)))
    t.hash["worldY"] = Num(float(y), repr(float(y)))
    t.hash["size"] = Num(size)
    t.hash["createdBy"] = "SkuNav"
    lc = LTable()
    lc.hash["enUS"] = LTable()
    lc.hash["deDE"] = LTable()
    t.hash["lComments"] = lc
    if phase:
        t.hash["phase"] = phase
    return t


def _tomb():
    t = LTable()
    t.arr.append(False)
    return t


def _copy(v):
    if isinstance(v, LTable):
        c = LTable()
        c.arr = [_copy(x) for x in v.arr]
        c.hash = {k: _copy(x) for k, x in v.hash.items()}
        return c
    if isinstance(v, Num):
        return Num(v.value, v.raw)
    return v


def _sections_of(arr, edges, seq=None, levels=None):
    s = {}
    w = LTable()
    w.arr = arr
    s["WaypointsNew"] = w
    s["Links"] = rebuild_links(edges)
    lv = LTable()
    if levels:
        lv.hash.update(levels)
    s["WaypointLevels"] = lv
    sq = LTable()
    if seq:
        sq.hash.update(seq)
    s["SequenceNumbers"] = sq
    return s


def cmd_selftest():
    fails = []

    def check(cond, what):
        print(("  ok  " if cond else "  FAIL") + " " + what)
        if not cond:
            fails.append(what)

    print("[1] synthetic three-way merge")
    A, B = 40, 12  # two zones
    base_arr = [
        _mk_wp("Quick Waypoint;1", "Schnellwegpunkt;1", 85, 0, 0),
        _mk_wp("auto Westfall;1", "auto Westfall;1", A, 100, 200),
        _mk_wp("auto Westfall;2", "auto Westfall;2", A, 110, 210),
        _mk_wp("auto Westfall;3", "auto Westfall;3", A, 120, 220),
        _mk_wp("auto Elwynn;1", "auto Elwynn;1", B, 300, 400),
        _mk_wp("auto Elwynn;2", "auto Elwynn;2", B, 310, 410),
    ]
    def wid(i):  # 1-based
        return pack_custom(i, rec_area(base_arr[i - 1]))
    base_edges = {(wid(2), wid(3)): Num(15.5, "15.5"), (wid(3), wid(4)): Num(20.0, "20"),
                  (wid(5), wid(6)): Num(30.0, "30")}
    base = _sections_of([_copy(r) for r in base_arr], dict(base_edges), seq={A: Num(3), B: Num(2)},
                        levels={wid(2): Num(1)})

    # live: independently renamed wp4 and appended one Elwynn waypoint
    live_arr = [_copy(r) for r in base_arr]
    live_arr[3].hash["names"] = "auto Westfall;3 live§auto Westfall;3 live"
    live_arr.append(_mk_wp("auto Elwynn;3", "auto Elwynn;3", B, 320, 420))
    live_edges = dict(base_edges)
    live_edges[(pack_custom(7, B), wid(5))] = Num(9.0, "9")
    live = _sections_of(live_arr, live_edges, seq={A: Num(3), B: Num(3)}, levels={wid(2): Num(1)})

    # contribution: moved wp2, deleted wp5, renamed wp4 DIFFERENTLY (conflict),
    # appended one Westfall waypoint with a link, changed one distance,
    # touched the quick waypoint (must be ignored), bumped the A sequence
    c_arr = [_copy(r) for r in base_arr]
    c_arr[0].hash["worldX"] = Num(55.0, "55")            # quick wp churn -> ignored
    c_arr[1].hash["worldX"] = Num(105.5, "105.5")        # clean modify
    c_arr[3].hash["names"] = "auto Westfall;3 beitrag§auto Westfall;3 beitrag"  # conflict
    c_arr[4] = _tomb()                                   # delete wp5 (Elwynn;1)
    c_arr.append(_mk_wp("auto Westfall;4", "auto Westfall;4", A, 130, 230, phase="era"))
    c_edges = dict(base_edges)
    c_edges[(pack_custom(7, A), wid(2))] = Num(12.0, "12")   # link from the appended wp
    c_edges[(wid(2), wid(3))] = Num(16.5, "16.5")            # distance change
    del c_edges[(wid(5), wid(6))]                            # delete a link of deleted wp
    contrib = {"waypoints": _sections_of(c_arr, {})["WaypointsNew"],
               "links": rebuild_links(c_edges),
               "levels": LTable(), "seq": LTable(), "meta": {}, "seed_map_id": 1,
               "source": "selftest"}
    contrib["seq"].hash[A] = Num(4)
    contrib["levels"].hash[wid(2)] = Num(1)

    rep = Report()
    stats = merge_contribution(live, contrib, base, rep)
    arr = live["WaypointsNew"].arr

    check(stats["modified"] == 1 and arr[1].hash["worldX"].value == 105.5, "clean modify taken")
    check(stats["deleted"] == 1 and is_tombstone(arr[4]), "deletion taken")
    check(stats["skipped_quick"] == 1 and arr[0].hash["worldX"].value == 0, "quick waypoint ignored")
    check("live" in en_name(arr[3]) and rep.conflicts >= 1, "rename conflict kept live + reported")
    check(len(arr) == 8 and en_name(arr[7]) == "auto Westfall;4", "append re-indexed to position 8")
    edges = flatten_links(live["Links"])
    check((pack_custom(8, A), wid(2)) in edges, "appended waypoint's link remapped to new id")
    check((pack_custom(7, A), wid(2)) not in edges, "old (contribution-local) id absent")
    check(edges.get((wid(2), wid(3))) == Num(16.5), "distance change taken")
    check((wid(5), wid(6)) not in edges, "link deletion taken")
    check((pack_custom(7, B), wid(5)) in edges, "live's own new link untouched")
    sq = seq_as_dict(live["SequenceNumbers"])
    check(sq[A] == Num(4) and sq[B] == Num(3), "sequence numbers merged (max)")

    print("[2] serializer/parser round-trip (synthetic)")
    buf = os.path.join(HERE, "_selftest_tmp.lua")
    try:
        write_pristine(buf, live, ["WaypointsNew", "Links", "WaypointLevels", "SequenceNumbers"],
                       "SkuDB", None, True)
        secs2, _, _, _, _ = read_routedata(buf)
        check(secs2["WaypointsNew"] == live["WaypointsNew"], "waypoints round-trip")
        check(flatten_links(secs2["Links"]) == flatten_links(live["Links"]), "links round-trip")
        check(seq_as_dict(secs2["SequenceNumbers"]) == seq_as_dict(live["SequenceNumbers"]), "sequence round-trip")
    finally:
        if os.path.exists(buf):
            os.remove(buf)

    if os.path.exists(LIVE):
        print("[3] real live file: parse + serialize + reparse (takes a while)")
        secs, order, root, version, bom = read_routedata(LIVE)
        n_wp = len(secs["WaypointsNew"].arr)
        print("  parsed: %d waypoints, %d link sources" % (n_wp, len(secs["Links"].hash)))
        check(n_wp > 40000, "live waypoint count plausible")
        buf = os.path.join(HERE, "_selftest_live.lua")
        try:
            write_pristine(buf, secs, order, root, version, bom)
            secs2, _, _, _, _ = read_routedata(buf)
            check(secs2["WaypointsNew"] == secs["WaypointsNew"], "live waypoints round-trip")
            check(flatten_links(secs2["Links"]) == flatten_links(secs["Links"]), "live links round-trip")
            check(seq_as_dict(secs2["SequenceNumbers"]) == seq_as_dict(secs["SequenceNumbers"]),
                  "live sequence numbers round-trip")
            check(secs2.get("WaypointLevels") == secs.get("WaypointLevels"), "live levels round-trip")
        finally:
            if os.path.exists(buf):
                os.remove(buf)
    else:
        print("[3] live file missing — skipped")

    print()
    if fails:
        raise SystemExit("SELFTEST FAILED: %d check(s):\n  " % len(fails) + "\n  ".join(fails))
    print("SELFTEST PASSED")


# ======================================================================== main
def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        return
    cmd, rest = args[0], args[1:]
    if cmd == "status":
        cmd_status()
    elif cmd == "seed":
        note = ""
        if "--note" in rest:
            note = rest[rest.index("--note") + 1]
        cmd_seed(note)
    elif cmd == "merge":
        base_override = None
        base_file = None
        assume = "--assume-base-live" in rest
        dry = "--dry-run" in rest
        if "--base" in rest:
            base_override = int(rest[rest.index("--base") + 1])
        if "--base-file" in rest:
            base_file = rest[rest.index("--base-file") + 1]
        paths = [a for i, a in enumerate(rest)
                 if not a.startswith("--")
                 and (i == 0 or rest[i - 1] not in ("--base", "--base-file", "--note"))]
        if not paths:
            raise SystemExit("usage: merge <contribution.zip|SkuMapper.lua> [...] "
                             "[--base N | --base-file PATH | --assume-base-live] [--dry-run]")
        cmd_merge(paths, base_override, base_file, assume, dry)
    elif cmd == "dump":
        cmd_dump()
    elif cmd == "selftest":
        cmd_selftest()
    else:
        raise SystemExit("unknown command %r — run without arguments for help" % cmd)


if __name__ == "__main__":
    main()
