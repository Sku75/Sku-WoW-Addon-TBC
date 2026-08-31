"""Refresh SkuDB.questDataTBC in quests.lua.bak from the installed Questie's
TBC quest database (semantic merge, not a byte copy).

Why not a wholesale replace:
  * the SCHEMAS diverged at the tail: Sku has extraObjectives=27 + skuData=28,
    Questie moved extraObjectives to 29 and added breadcrumb/spell/rank keys
    27-36. Keys 1-26 are identical (verified). So only fields 1-26 are
    adopted; Questie's 27+ are dropped; Sku's 27/28 are preserved per record
    (skuData carries the hand-maintained quest blacklist + Sku comments).
  * Questie's exporter formats records differently (no trailing commas,
    trailing nils trimmed, all-nil tables written as plain nil). A textual
    diff would replace every record; the semantic compare below only touches
    records whose CONTENT changed, so the git diff stays honest.
  * every id a changed/new record references (creatures, objects, items) is
    validated against the shipped Sku DBs (base + WotLK, which merge at
    runtime). A record referencing an id we cannot resolve is NOT adopted -
    a "Ziel" entry that resolves to nothing would announce "Empty", the
    false positive this repo explicitly avoids. Report only.

Run from anywhere:
  py -3 dev/rework-docs/_refresh_questdata_from_questie.py           dry run
  py -3 dev/rework-docs/_refresh_questdata_from_questie.py --write   apply

After --write, re-run the chunker (regenerates quests.lua from the .bak and
verifies byte-identity, key sequences, literal-only content):
  py -3 dev/rework-docs/_db_convert.py
"""
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
ASSETS = os.path.join(ROOT, "Sku", "SkuDB", "assets")
QUESTIE_DB = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
              r"\Interface\AddOns\Questie\Database\TBC\tbcQuestDB.lua")

SHARED_FIELDS = 26   # fields 1..26 are schema-identical Sku vs Questie
SKU_EXTRA_MAX = 28   # Sku-only tail: extraObjectives=27, skuData=28

spec = importlib.util.spec_from_file_location(
    "dbconv", os.path.join(HERE, "_db_convert.py"))
dbconv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(dbconv)


# ---------------------------------------------------------------------------
# canonical Lua-literal parser (positional tables + [key]=value entries)

class LuaParseError(Exception):
    pass


TOK_WS = re.compile(rb"[ \t\r\n]+")
TOK_NUM = re.compile(rb"-?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)")
ESC = {b"n": "\n", b"t": "\t", b"r": "\r", b'"': '"', b"'": "'", b"\\": "\\"}


def parse_value(data, i):
    """Parse one Lua literal at data[i]; return (python_value, next_index)."""
    m = TOK_WS.match(data, i)
    if m:
        i = m.end()
    c = data[i:i + 1]
    if c == b"{":
        return parse_table(data, i)
    if c in (b'"', b"'"):
        q = c
        j = i + 1
        out = []
        while True:
            k = data.find(q, j)
            if k == -1:
                raise LuaParseError("unterminated string at %d" % i)
            seg = data[j:k]
            # count trailing backslashes
            b = 0
            while b < len(seg) and seg[-1 - b:len(seg) - b] == b"\\":
                b += 1
            out.append(seg)
            j = k + 1
            if b % 2 == 0:
                break
        raw = b"".join(out)
        # normalize escapes for COMPARISON purposes
        s = []
        p = 0
        while p < len(raw):
            ch = raw[p:p + 1]
            if ch == b"\\" and p + 1 < len(raw):
                nx = raw[p + 1:p + 2]
                if nx in ESC:
                    s.append(ESC[nx])
                    p += 2
                    continue
                if nx.isdigit():
                    q2 = p + 1
                    num = b""
                    while q2 < len(raw) and raw[q2:q2 + 1].isdigit() and len(num) < 3:
                        num += raw[q2:q2 + 1]
                        q2 += 1
                    s.append(chr(int(num)))
                    p = q2
                    continue
            s.append(ch.decode("utf-8", "replace"))
            p += 1
        return "".join(s), j
    if data[i:i + 3] == b"nil":
        return None, i + 3
    if data[i:i + 4] == b"true":
        return True, i + 4
    if data[i:i + 5] == b"false":
        return False, i + 5
    m = TOK_NUM.match(data, i)
    if m:
        txt = m.group(0)
        if txt[:2].lower() in (b"0x", b"-0"):
            try:
                return int(txt, 16), m.end()
            except ValueError:
                pass
        f = float(txt)
        return int(f) if f == int(f) else f, m.end()
    raise LuaParseError("cannot parse value at %d: %r" % (i, data[i:i + 40]))


def parse_table(data, i):
    """data[i] == '{'. Returns ((positional_tuple, keyed_tuple), next)."""
    i += 1
    pos = []
    keyed = []
    while True:
        m = TOK_WS.match(data, i)
        if m:
            i = m.end()
        c = data[i:i + 1]
        if c == b"}":
            i += 1
            break
        if c in (b",", b";"):
            i += 1
            continue
        if c == b"[":
            j = data.index(b"]", i)
            key, _ = parse_value(data, i + 1)
            i = j + 1
            m = TOK_WS.match(data, i)
            if m:
                i = m.end()
            if data[i:i + 1] != b"=":
                raise LuaParseError("no = after key at %d" % i)
            val, i = parse_value(data, i + 1)
            keyed.append((key, canon(val)))
            continue
        val, i = parse_value(data, i)
        pos.append(val)
    return ("T", tuple(pos), tuple(sorted(keyed, key=repr))), i


def canon(v):
    """Normalize: strip trailing Nones from positional parts; a table with
    nothing left becomes None (Questie writes all-nil tables as plain nil)."""
    if isinstance(v, tuple) and v and v[0] == "T":
        pos = [canon(x) for x in v[1]]
        while pos and pos[-1] is None:
            pos.pop()
        keyed = v[2]
        if not pos and not keyed:
            return None
        return ("T", tuple(pos), keyed)
    return v


def record_fields(body):
    """Split one record body (bytes between the outer braces) into raw field
    byte-slices at depth 0 (comma-separated), Questie/Sku style."""
    fields = []
    depth = 0
    start = 0
    i = 0
    n = len(body)
    while i < n:
        c = body[i:i + 1]
        if c in (b'"', b"'"):
            i = dbconv.skip_string(body, i)
            continue
        if c == b"{":
            depth += 1
        elif c == b"}":
            depth -= 1
        elif c == b"," and depth == 0:
            fields.append(body[start:i].strip())
            start = i + 1
        i += 1
    tail = body[start:].strip()
    if tail:
        fields.append(tail)
    return fields


def canon_field(raw):
    if not raw or raw == b"nil":
        return None
    v, _ = parse_value(raw, 0)
    return canon(v)


def canon_record(fields, upto):
    vals = [canon_field(f) for f in fields[:upto]]
    # requiredRaces (field 6) convention shift: the old exporter wrote the
    # all-races mask (2047, Era: 255) where the current one writes 0 - Sku's
    # eligibility logic treats both as "available to everyone" (the raceKeys
    # loop's else-branch sets both faction flags), so they compare EQUAL here;
    # 2117 records differ ONLY by this and would bloat the diff for nothing.
    if len(vals) >= 6 and vals[5] in (2047, 255):
        vals[5] = 0
    while vals and vals[-1] is None:
        vals.pop()
    return tuple(vals)


# ---------------------------------------------------------------------------
# load both databases as id -> raw record body

def load_table_records(path, lhs):
    data = open(path, "rb").read()
    if data.startswith(dbconv.BOM):
        data = data[len(dbconv.BOM):]
    stmt_start, open_pos, stmt_end = dbconv.find_stmt(data, lhs)
    recs = dbconv.split_records(data, open_pos + 1, stmt_end - 1, lhs)
    out = {}
    for key, rs, re_ in recs:
        out[int(key)] = data[rs:re_]
    return out, data, open_pos, stmt_end


def record_body(rec):
    """rec is '[id] = { ... }' bytes; return the bytes between outer braces."""
    i = rec.index(b"{")
    return rec[i + 1:len(rec) - 1]


def load_questie():
    data = open(QUESTIE_DB, "rb").read()
    anchor = b"questData = [[return {"
    i = data.index(anchor) + len(anchor)
    end = data.index(b"}]]", i)
    recs = dbconv.split_records(data, i, end, "questie questData")
    out = {}
    for key, rs, re_ in recs:
        out[int(key)] = data[rs:re_]
    return out


def key_set(path, lhs):
    data = open(path, "rb").read()
    if data.startswith(dbconv.BOM):
        data = data[len(dbconv.BOM):]
    _, open_pos, stmt_end = dbconv.find_stmt(data, lhs)
    recs = dbconv.split_records(data, open_pos + 1, stmt_end - 1, lhs)
    return set(int(k) for k, _, _ in recs)


# ---------------------------------------------------------------------------
# id extraction from a canonical record (fields 1-26, 1-based questKeys)

def tbl_pos(v):
    return v[1] if isinstance(v, tuple) and v and v[0] == "T" else ()


def id_list(v):
    """A Questie id list: {id, id, ...} or {{id, text}, ...}."""
    ids = []
    for e in tbl_pos(v):
        if isinstance(e, int):
            ids.append(e)
        elif isinstance(e, tuple) and e and e[0] == "T":
            p = tbl_pos(e)
            if p and isinstance(p[0], int):
                ids.append(p[0])
    return ids


def referenced_ids(fields_canon):
    """Yield (kind, id) for every creature/object/item reference."""
    def fld(n):
        return fields_canon[n - 1] if len(fields_canon) >= n else None
    refs = []
    started = tbl_pos(fld(2))
    finished = tbl_pos(fld(3))
    objectives = tbl_pos(fld(10))
    for kind, v in (("creature", started[0:1]), ("object", started[1:2]),
                    ("item", started[2:3]), ("creature", finished[0:1]),
                    ("object", finished[1:2])):
        for lst in v:
            refs.extend((kind, i) for i in id_list(lst))
    if objectives:
        for kind, idx in (("creature", 0), ("object", 1), ("item", 2)):
            if len(objectives) > idx:
                refs.extend((kind, i) for i in id_list(objectives[idx]))
        if len(objectives) > 4:  # kill credit: {{ids...}, base, text}
            kc = tbl_pos(objectives[4])
            if kc:
                refs.extend(("creature", i) for i in id_list(kc[0]))
    src = fld(11)
    if isinstance(src, int):
        refs.append(("item", src))
    return refs


def trigger_zones(fields_canon):
    fld = fields_canon[8] if len(fields_canon) >= 9 else None
    p = tbl_pos(fld)
    if len(p) >= 2 and isinstance(p[1], tuple) and p[1][0] == "T":
        return [k for k, _ in p[1][2] if isinstance(k, int)]
    if isinstance(fld, tuple) and fld[0] == "T" and len(fld) == 3:
        # keyed zone table sits in the keyed part of the 2nd entry
        pass
    return []


# ---------------------------------------------------------------------------

def main():
    write = "--write" in sys.argv[1:]

    quests_bak = os.path.join(ASSETS, "quests.lua.bak")
    sku, sku_bytes, open_pos, stmt_end = load_table_records(
        quests_bak, "SkuDB.questDataTBC")
    questie = load_questie()
    print("sku records: %d   questie records: %d" % (len(sku), len(questie)))

    print("loading id sets for validation (base + WotLK)...")
    creatures = key_set(os.path.join(ASSETS, "creatures.lua.bak"), "SkuDB.NpcData.Data") \
        | key_set(os.path.join(ASSETS, "WotLK", "creatures.lua.bak"), "SkuDB.WotLK.NpcData.Data")
    items = key_set(os.path.join(ASSETS, "items.lua.bak"), "SkuDB.itemDataTBC") \
        | key_set(os.path.join(ASSETS, "WotLK", "items.lua.bak"), "SkuDB.WotLK.itemDataTBC")
    objects = key_set(os.path.join(ASSETS, "objects.lua.bak"), "SkuDB.objectDataTBC") \
        | key_set(os.path.join(ASSETS, "WotLK", "objects.lua.bak"), "SkuDB.WotLK.objectDataTBC")
    sets = {"creature": creatures, "item": items, "object": objects}
    print("  creatures %d, items %d, objects %d" %
          (len(creatures), len(items), len(objects)))

    changed, added, kept_old, only_sku = [], [], [], []
    preserved_tail = 0
    for qid in sorted(set(sku) | set(questie)):
        if qid not in questie:
            only_sku.append(qid)
            continue
        q_fields = record_fields(record_body(questie[qid]))
        q_canon = canon_record(q_fields, SHARED_FIELDS)
        if qid in sku:
            s_fields = record_fields(record_body(sku[qid]))
            s_canon = canon_record(s_fields, SHARED_FIELDS)
            if q_canon == s_canon:
                continue
        else:
            s_fields = []

        # validate every referenced id of the INCOMING record
        missing = sorted(set(
            (k, i) for k, i in referenced_ids(
                [canon_field(f) for f in q_fields[:SHARED_FIELDS]])
            if i not in sets[k]))
        if missing:
            kept_old.append((qid, missing))
            continue

        # build the new record: Questie fields 1-26, Sku tail 27/28 preserved
        new_fields = [f if f else b"nil" for f in q_fields[:SHARED_FIELDS]]
        tail = s_fields[SHARED_FIELDS:SKU_EXTRA_MAX]
        if any(canon_field(f) is not None for f in tail):
            while len(new_fields) < SHARED_FIELDS:
                new_fields.append(b"nil")
            new_fields.extend(f if f else b"nil" for f in tail)
            preserved_tail += 1
        new_rec = b"[" + str(qid).encode() + b"] = {" + b",".join(new_fields) + b",}"
        if qid in sku:
            changed.append((qid, new_rec))
        else:
            added.append((qid, new_rec))

    print("\nunchanged: %d" % (len(sku) - len(changed)
                               - sum(1 for q, _ in kept_old if q in sku)))
    print("changed:   %d" % len(changed))
    print("added:     %d  %s" % (len(added), [q for q, _ in added]))
    print("kept OLD (incoming record references unknown ids): %d" % len(kept_old))
    for qid, missing in kept_old[:20]:
        print("   %d: %s" % (qid, missing[:6]))
    print("only in sku (untouched): %d %s" % (len(only_sku), only_sku[:10]))
    print("records with preserved Sku tail fields (27/28): %d" % preserved_tail)

    if not write:
        print("\nDRY RUN - nothing written. Re-run with --write to apply.")
        return

    # apply: replace changed record spans, insert added records in id order.
    # Work on the interior slice, then reassemble the file.
    interior = sku_bytes[open_pos + 1:stmt_end - 1]
    recs = dbconv.split_records(sku_bytes, open_pos + 1, stmt_end - 1,
                                "SkuDB.questDataTBC")
    by_id = {int(k): (rs, re_) for k, rs, re_ in recs}
    edits = []  # (abs_start, abs_end, replacement_bytes)
    for qid, new_rec in changed:
        rs, re_ = by_id[qid]
        edits.append((rs, re_, new_rec))
    # insertion points for new ids: before the first existing record with a
    # larger id (records are in ascending order - verified by the sort below)
    ordered = sorted(by_id)
    if ordered != [int(k) for k, _, _ in recs]:
        print("FATAL: records are not in ascending id order; refusing insert")
        sys.exit(2)
    for qid, new_rec in added:
        import bisect
        pos = bisect.bisect_left(ordered, qid)
        if pos == len(ordered):
            anchor = by_id[ordered[-1]][1]  # after last record's end
            edits.append((anchor, anchor, b",\r\n\t" + new_rec))
        else:
            anchor = by_id[ordered[pos]][0]  # before that record's start
            edits.append((anchor, anchor, new_rec + b",\r\n\t"))
    edits.sort(key=lambda e: (e[0], e[1]))
    out = []
    prev = 0
    for s, e, rep in edits:
        out.append(sku_bytes[prev:s])
        out.append(rep)
        prev = e
    out.append(sku_bytes[prev:])
    new_bytes = b"".join(out)
    with open(quests_bak, "wb") as f:
        f.write(new_bytes)
    print("\nwrote %s (%d -> %d bytes)" %
          (quests_bak, len(sku_bytes), len(new_bytes)))
    print("NOW RUN: py -3 dev/rework-docs/_db_convert.py")


if __name__ == "__main__":
    main()
