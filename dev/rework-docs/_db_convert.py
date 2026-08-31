"""
[DB rework stage 2, tool 1] Convert the nine big SkuDB data files from executed
table constructors into chunked string-literal builders, with verification
BUILT IN (the tool refuses to leave bad output on disk on any failed check).
See Sku42-Rework-Docs/DB-RESTRUCTURE-PLAN.md, sections 2 and 4.

Design rule (risk A3): the converter NEVER rewrites record text. It scans the
pristine file with a string/comment-aware brace-depth scanner, finds the
whitelisted big tables, and cuts their INTERIOR into chunks at record
boundaries - every chunk is a verbatim byte slice of the original interior.
Only scaffolding (the "SkuDB.x = {}" heads, the chunk-registry statements, the
"return {" / "}" wrappers) is generated. Concatenating all chunk bodies of a
table therefore reproduces the original interior byte-for-byte, and the
verifier checks exactly that, from the bytes on disk, against the pristine
.bak - plus key sets/sequences, uniqueness, a literal-only content check per
chunk (risk A4), bracket-level safety (risk A2), a luaparser parse of the
scaffolding (bodies stubbed), and a file-scope reference scan over the whole
SkuDB TOC block (risk A4 check 2).

The pristine file is kept in a one-time .bak (source of truth, like
_wrap_deferred.py); re-running always regenerates from it (idempotent, no
timestamps in the output). The .bak stays on disk after --unwrap so the
pristine bytes stay pinned for MANIFEST-DB.

Run from the repo root:
  py -3 Sku42-Rework-Docs/_db_convert.py              convert + full verify
  py -3 Sku42-Rework-Docs/_db_convert.py --verify     re-verify existing output
  py -3 Sku42-Rework-Docs/_db_convert.py --unwrap     restore pristine files
                                                      (alias: --revert-all)
  py -3 Sku42-Rework-Docs/_db_convert.py --no-filescope-scan
                                                      skip the (slower)
                                                      luaparser file-scope scan
"""
import hashlib
import os
import re
import sys

# this file lives in <repo>/dev/rework-docs/ since the 2026-07-10 single-repo
# merge (formerly <repo>/Sku42-Rework-Docs/) - ROOT is the repo root
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SKU = os.path.join(ROOT, "Sku")
ASSETS = os.path.join(SKU, "SkuDB", "assets")
BOM = b"\xef\xbb\xbf"
CHUNK_RECORDS = 500

# The whitelist (risk A4): ONLY these tables in these files are converted.
# mode "flat"    - records [key] = value at depth 1 of the table
# mode "locales" - depth-1 entries are ["xxXX"] = { records }; chunking happens
#                  inside each locale subtable, target path gets ".xxXX"
TARGETS = [
    ("creatures.lua", [("SkuDB.NpcData.Names", "locales"),
                       ("SkuDB.NpcData.Data", "flat")]),
    ("items.lua", [("SkuDB.itemLookup", "locales"),
                   ("SkuDB.itemDataTBC", "flat")]),
    ("spells.lua", [("SkuDB.SpellDataTBC", "flat")]),
    ("quests.lua", [("SkuDB.questLookup", "locales"),
                    ("SkuDB.questDataTBC", "flat")]),
    ("objects.lua", [("SkuDB.objectDataTBC", "flat"),
                     ("SkuDB.objectLookup", "locales")]),
    (os.path.join("WotLK", "creatures.lua"),
     [("SkuDB.WotLK.NpcData.Names", "locales"),
      ("SkuDB.WotLK.NpcData.Data", "flat")]),
    (os.path.join("WotLK", "items.lua"),
     [("SkuDB.WotLK.itemLookup", "locales"),
      ("SkuDB.WotLK.itemDataTBC", "flat")]),
    (os.path.join("WotLK", "quests.lua"),
     [("SkuDB.WotLK.questLookup", "locales"),
      ("SkuDB.WotLK.questDataTBC", "flat")]),
    (os.path.join("WotLK", "objects.lua"),
     [("SkuDB.WotLK.objectDataTBC", "flat"),
      ("SkuDB.WotLK.objectLookup", "locales")]),
]

# every wrapped dotted path (for the file-scope scan)
WRAPPED_PATHS = [lhs for _, tabs in TARGETS for lhs, _ in tabs]

# all OTHER files of the SkuDB TOC block (checked for file-scope references to
# wrapped paths; the SoD tree and fixes files load between/after the converted
# files and before the chunk loader)
SCAN_FILES = [
    os.path.join(SKU, "SkuDB", "Core.lua"),
    os.path.join(ASSETS, "maps.lua"),
    os.path.join(ASSETS, "default_waypoints.lua"),
    os.path.join(ASSETS, "quests_fixes.lua"),
    os.path.join(ASSETS, "creatures_fixes.lua"),
    os.path.join(ASSETS, "items_fixes.lua"),
    os.path.join(ASSETS, "objects_fixes.lua"),
    os.path.join(ASSETS, "polygons.lua"),
    os.path.join(ASSETS, "tasks.lua"),
    os.path.join(ASSETS, "WotLK", "quests_fixes.lua"),
    os.path.join(ASSETS, "WotLK", "creatures_fixes.lua"),
    os.path.join(ASSETS, "WotLK", "items_fixes.lua"),
    os.path.join(ASSETS, "WotLK", "objects_fixes.lua"),
    os.path.join(ASSETS, "WotLK", "enchantIDs.lua"),
    os.path.join(ASSETS, "SoD", "quests.lua"),
    os.path.join(ASSETS, "SoD", "quests_fixes.lua"),
    os.path.join(ASSETS, "SoD", "creatures.lua"),
    os.path.join(ASSETS, "SoD", "creatures_fixes.lua"),
    os.path.join(ASSETS, "SoD", "items.lua"),
    os.path.join(ASSETS, "SoD", "items_fixes.lua"),
    os.path.join(ASSETS, "SoD", "objects.lua"),
    os.path.join(ASSETS, "SoD", "objects_fixes.lua"),
    os.path.join(ASSETS, "SoD", "spells.lua"),
]

RECORDS_MANIFEST = os.path.join(HERE, "MANIFEST-DB-RECORDS.txt")


class ConvertError(Exception):
    pass


def die(msg):
    raise ConvertError(msg)


def context(data, pos):
    return repr(data[max(0, pos - 60):pos + 60])


# ---------------------------------------------------------------------------
# byte scanner (string- and comment-aware brace depth; regex jumps between
# structurally interesting bytes so the Python loop runs per token, not per
# byte - the files total ~46 MB)

JUMP = re.compile(rb"[{}\"'\-\[]")     # bytes that can change structure
NONWS = re.compile(rb"[^ \t\r\n]")
LONGOPEN = re.compile(rb"\[(=*)\[")

O_BRACE, C_BRACE, DQUOTE, SQUOTE, DASH, LBRACK = (
    ord("{"), ord("}"), ord('"'), ord("'"), ord("-"), ord("["))


def skip_long_bracket(data, i):
    """If data[i:] starts a long bracket [=*[ return index past its close,
    else None. Unterminated long bracket is a hard error."""
    m = LONGOPEN.match(data, i)
    if not m:
        return None
    close = b"]" + m.group(1) + b"]"
    e = data.find(close, m.end())
    if e == -1:
        die("unterminated long bracket at %d: %s" % (i, context(data, i)))
    return e + len(close)


def skip_string(data, i):
    """data[i] is ' or \". Return index past the closing quote."""
    q = data[i]
    j = i + 1
    n = len(data)
    while j < n:
        j = data.find(data[i:i + 1], j)
        if j == -1:
            die("unterminated string at %d" % i)
        # closing quote only if preceded by an EVEN number of backslashes
        k = j - 1
        while data[k] == 0x5C:  # backslash
            k -= 1
        if (j - 1 - k) % 2 == 0:
            if data.find(b"\n", i, j) != -1:
                die("string contains newline at %d: %s" % (i, context(data, i)))
            return j + 1
        j += 1
    die("unterminated string at %d" % i)


def skip_comment(data, i):
    """data[i:i+2] is --. Return index past the comment."""
    j = i + 2
    e = skip_long_bracket(data, j)
    if e is not None:
        return e
    e = data.find(b"\n", j)
    return len(data) if e == -1 else e + 1


def skip_ws_comments(data, i, end):
    while i < end:
        m = NONWS.search(data, i, end)
        if not m:
            return end
        i = m.start()
        if data[i] == DASH and data[i + 1:i + 2] == b"-":
            i = skip_comment(data, i)
        else:
            return i
    return i


def skip_balanced_table(data, i, end):
    """data[i] is '{'. Return index past the matching '}'."""
    depth = 0
    while i < end:
        m = JUMP.search(data, i, end)
        if not m:
            break
        i = m.start()
        c = data[i]
        if c == O_BRACE:
            depth += 1
            i += 1
        elif c == C_BRACE:
            depth -= 1
            i += 1
            if depth == 0:
                return i
        elif c in (DQUOTE, SQUOTE):
            i = skip_string(data, i)
        elif c == DASH:
            if data[i + 1:i + 2] == b"-":
                i = skip_comment(data, i)
            else:
                i += 1
        else:  # LBRACK
            e = skip_long_bracket(data, i)
            i = e if e is not None else i + 1
    die("unbalanced table starting at %d" % i)


ATOM = re.compile(rb"[0-9a-fA-FxXeEpP+\-.]+")


def skip_value(data, i, end):
    """data[i] starts a record value. Return index past it."""
    c = data[i]
    if c == O_BRACE:
        return skip_balanced_table(data, i, end)
    if c in (DQUOTE, SQUOTE):
        return skip_string(data, i)
    e = skip_long_bracket(data, i)
    if e is not None:
        return e
    # bare atom: nil / true / false / number
    if data[i:i + 3] == b"nil":
        return i + 3
    if data[i:i + 4] == b"true":
        return i + 4
    if data[i:i + 5] == b"false":
        return i + 5
    j = i + 1 if c == DASH else i
    m = ATOM.match(data, j, end)
    if not m:
        die("unrecognized value atom at %d: %s" % (i, context(data, i)))
    atom = m.group(0)
    try:
        float(atom)
    except ValueError:
        try:
            int(atom, 16)
        except ValueError:
            die("bad number %r at %d: %s" % (atom, i, context(data, i)))
    return m.end()


def parse_key(data, i, end):
    """data[i] is '[' of a [key] form. Return (key_text, index past ']')."""
    j = skip_ws_comments(data, i + 1, end)
    if data[j] in (DQUOTE, SQUOTE):
        e = skip_string(data, j)
        key = data[j:e]
    else:
        e = data.find(b"]", j, end)
        if e == -1:
            die("malformed key at %d: %s" % (i, context(data, i)))
        key = data[j:e].strip()
    e = skip_ws_comments(data, e, end)
    if data[e] != ord("]"):
        die("malformed key at %d: %s" % (i, context(data, i)))
    return key, e + 1


def split_records(data, i, end, where):
    """Split a table interior [i, end) into records of the form [key] = value.
    Returns list of (key_bytes, rec_start, rec_end). Validates that between
    records there is exactly one ',' or ';' plus whitespace/comments, nothing
    else (risks A3/A5)."""
    records = []
    pos = i
    first = True
    comma_semi = (ord(","), ord(";"))
    while True:
        sep_start = pos
        commas = 0
        while pos < end:
            m = NONWS.search(data, pos, end)
            if not m:
                pos = end
                break
            pos = m.start()
            c = data[pos]
            if c == DASH and data[pos + 1:pos + 2] == b"-":
                pos = skip_comment(data, pos)
            elif c in comma_semi:
                commas += 1
                pos += 1
            else:
                break
        if pos >= end:
            if commas > 1:
                die("%s: %d separators after last record at %d" % (where, commas, sep_start))
            break
        if first and commas > 0:
            die("%s: separator before first record at %d" % (where, sep_start))
        if not first and commas != 1:
            die("%s: expected exactly 1 separator between records, got %d at %d: %s"
                % (where, commas, sep_start, context(data, pos)))
        if data[pos] != LBRACK:
            die("%s: record does not start with [key]= at %d: %s"
                % (where, pos, context(data, pos)))
        rec_start = pos
        key, pos = parse_key(data, pos, end)
        pos = skip_ws_comments(data, pos, end)
        if data[pos] != ord("="):
            die("%s: no '=' after key %r at %d: %s" % (where, key, pos, context(data, pos)))
        pos = skip_ws_comments(data, pos + 1, end)
        rec_end = skip_value(data, pos, end)
        records.append((key, rec_start, rec_end))
        pos = rec_end
        first = False
    if not records:
        die("%s: no records found" % where)
    return records


def count_dupes(records):
    """Duplicate keys DO exist in the data (e.g. creatures.lua deDE carries a
    second, partially untranslated block re-listing thousands of ids). The
    original constructor silently last-wins; the chunk loader merges records
    in the SAME order, so last-wins is preserved exactly - duplicates are
    therefore allowed, but counted and reported. The key-SEQUENCE identity
    check (pristine vs output) is what actually pins the semantics."""
    seen, dupes = set(), 0
    for k, _, _ in records:
        if k in seen:
            dupes += 1
        seen.add(k)
    return dupes


def find_stmt(data, lhs):
    """Find the top-level statement '<lhs> = {' ... matching '}'. Returns
    (stmt_start, open_pos, stmt_end) with stmt_start at the lhs line start and
    stmt_end just past the closing brace. The candidate found by regex is
    verified to sit at code level, depth 0, by a structural walk from the file
    start (strings/comments/long brackets skipped)."""
    pat = re.compile(rb"(?m)^[ \t]*" + re.escape(lhs.encode("ascii")) + rb"[ \t]*=[ \t\r\n]*\{")
    candidates = [m for m in pat.finditer(data)]
    if not candidates:
        die("statement not found: %s" % lhs)
    if len(candidates) > 1:
        die("statement found %d times (expected once): %s" % (len(candidates), lhs))
    m = candidates[0]
    target = m.start()
    # structural walk to the candidate: it must be reached at depth 0
    i = 0
    depth = 0
    while i < target:
        jm = JUMP.search(data, i, target)
        if not jm:
            i = target
            break
        i = jm.start()
        c = data[i]
        if c == O_BRACE:
            depth += 1
            i += 1
        elif c == C_BRACE:
            depth -= 1
            i += 1
        elif c in (DQUOTE, SQUOTE):
            i = skip_string(data, i)
        elif c == DASH:
            i = skip_comment(data, i) if data[i + 1:i + 2] == b"-" else i + 1
        else:
            e = skip_long_bracket(data, i)
            i = e if e is not None else i + 1
    if i > target:
        die("%s: statement candidate at %d is inside a string/comment" % (lhs, target))
    if depth != 0:
        die("%s: statement candidate at %d is at depth %d, not top level" % (lhs, target, depth))
    open_pos = m.end() - 1
    stmt_end = skip_balanced_table(data, open_pos, len(data))
    return m.start(), open_pos, stmt_end


# ---------------------------------------------------------------------------
# literal-only content check (risk A4 check 1). Fast path: one anchored regex
# that only matches allowed content (literals, table punctuation, comments);
# if it does not swallow the whole body, the slow tokenizer reports WHERE.

ALLOWED_RE = re.compile(
    rb"(?:"
    rb"[ \t\r\n{}\[\]=,;]+"                                # ws + table punctuation
    rb"|--\[(=*)\[[\s\S]*?\]\1\]"                           # block comment
    rb"|--[^\n]*"                                           # line comment
    rb"|\"(?:\\.|[^\"\\\n])*\""                             # double-quoted string
    rb"|'(?:\\.|[^'\\\n])*'"                                # single-quoted string
    rb"|\[(=*)\[[\s\S]*?\]\2\]"                             # long-string value
    rb"|(?:nil|true|false)(?![A-Za-z0-9_])"                 # keyword literals
    rb"|-?(?:0[xX][0-9a-fA-F]+|(?:[0-9]+\.?[0-9]*|\.[0-9]+)(?:[eE][+-]?[0-9]+)?)"  # number
    rb")+")


def check_literal_only(body, where):
    m = ALLOWED_RE.match(body)
    if m and m.end() == len(body):
        return
    pos = m.end() if m else 0
    # slow tokenizer from pos for a precise error
    i = pos
    n = len(body)
    while i < n:
        i = skip_ws_comments(body, i, n)
        if i >= n:
            break
        c = body[i]
        if c in (DQUOTE, SQUOTE):
            i = skip_string(body, i)
            continue
        if chr(c) in "{}[]=,;":
            e = skip_long_bracket(body, i) if c == LBRACK else None
            i = e if e is not None else i + 1
            continue
        if body[i:i + 3] == b"nil" or body[i:i + 4] == b"true" or body[i:i + 5] == b"false":
            i += 3 if body[i:i + 3] == b"nil" else (4 if body[i:i + 4] == b"true" else 5)
            continue
        am = ATOM.match(body, i + 1 if c == DASH else i, n)
        if am:
            try:
                float(am.group(0))
                i = am.end()
                continue
            except ValueError:
                try:
                    int(am.group(0), 16)
                    i = am.end()
                    continue
                except ValueError:
                    pass
        die("%s: non-literal content at %d: %s" % (where, i, context(body, i)))
    # tokenizer walked it clean although the regex did not: still refuse -
    # the two must agree, disagreement means a checker bug
    die("%s: literal check disagreement at %d: %s" % (where, pos, context(body, pos)))


# ---------------------------------------------------------------------------
# conversion

def pick_level(body):
    n = 1
    while (b"]" + b"=" * n + b"]") in body:
        n += 1
    return n


def pristine_bytes(path):
    if not os.path.exists(path + ".bak"):
        with open(path, "rb") as f:
            cur = f.read()
        with open(path + ".bak", "wb") as f:
            f.write(cur)
    with open(path + ".bak", "rb") as f:
        return f.read()


def chunk_spans(records, interior_start, interior_end):
    """Cut points at every CHUNK_RECORDS-th record start; chunk 0 starts at the
    interior start (keeps leading whitespace/comments verbatim), the last chunk
    ends at the interior end (keeps trailing separator bytes verbatim). The
    concatenation of all spans is therefore the ENTIRE interior, verbatim."""
    spans = []
    for i in range(0, len(records), CHUNK_RECORDS):
        start = interior_start if i == 0 else records[i][1]
        if i + CHUNK_RECORDS < len(records):
            stop = records[i + CHUNK_RECORDS][1]
        else:
            stop = interior_end
        spans.append((start, stop))
    return spans


def emit_chunks(out, data, path_name, records, interior_start, interior_end):
    """Append the chunk-registry statements for one target table."""
    n_chunks = 0
    for start, stop in chunk_spans(records, interior_start, interior_end):
        body = data[start:stop]
        lvl = pick_level(body)
        op = b"[" + b"=" * lvl + b"["
        cl = b"]" + b"=" * lvl + b"]"
        out.append(b'SkuDBChunks[#SkuDBChunks+1] = {"' + path_name.encode("ascii")
                   + b'", ' + op + b"return {" + body + b"\r\n}" + cl + b"}\r\n")
        n_chunks += 1
    return n_chunks


def locale_subtables(data, lhs, open_pos, close_pos):
    """For a 'locales' table: return list of (locale_name, sub_open, sub_end)
    in original order; assert depth-1 entries are exactly ["xxXX"] = {...}."""
    outer = split_records(data, open_pos + 1, close_pos - 1, lhs)
    subs = []
    for key, rec_start, rec_end in outer:
        if not (key.startswith(b'"') and key.endswith(b'"')):
            die("%s: depth-1 key %r is not a quoted locale string" % (lhs, key))
        loc = key[1:-1].decode("ascii")
        if not (len(loc) == 4 and loc.isalpha()):
            die("%s: unexpected locale key %r" % (lhs, loc))
        eq = data.find(b"=", rec_start, rec_end)
        vs = skip_ws_comments(data, eq + 1, rec_end)
        if data[vs] != O_BRACE:
            die("%s[%s]: locale value is not a table" % (lhs, loc))
        subs.append((loc, vs, rec_end))  # rec_end is just past the matching '}'
    # duplicate LOCALE keys would change semantics (the original constructor
    # REPLACES the whole subtable, the chunk loader would union) - hard error,
    # unlike record-level duplicates (see count_dupes)
    locs = [s[0] for s in subs]
    if len(set(locs)) != len(locs):
        die("%s: duplicate locale keys: %s" % (lhs, locs))
    return subs


def convert_file(rel, tables):
    path = os.path.join(ASSETS, rel)
    data = pristine_bytes(path)
    bom = b""
    if data.startswith(BOM):
        bom, data = BOM, data[len(BOM):]
    stmts = []
    for lhs, mode in tables:
        stmt_start, open_pos, stmt_end = find_stmt(data, lhs)
        stmts.append((stmt_start, open_pos, stmt_end, lhs, mode))
    stmts.sort()
    out = [bom]
    prev = 0
    report = []
    for stmt_start, open_pos, stmt_end, lhs, mode in stmts:
        if stmt_start < prev:
            die("%s: overlapping statements" % rel)
        out.append(data[prev:stmt_start])
        prev = stmt_end
        piece = [lhs.encode("ascii") + b" = {}\r\n",
                 b"SkuDBChunks = SkuDBChunks or {}\r\n",
                 b"SkuDBChunkHashes = SkuDBChunkHashes or {}\r\n"]
        if mode == "flat":
            i0, i1 = open_pos + 1, stmt_end - 1
            records = split_records(data, i0, i1, lhs)
            piece.append(b'SkuDBChunkHashes["' + lhs.encode("ascii") + b'"] = "'
                         + hashlib.sha256(data[i0:i1]).hexdigest().encode("ascii") + b'"\r\n')
            n = emit_chunks(piece, data, lhs, records, i0, i1)
            report.append((lhs, len(records), n, count_dupes(records)))
        else:
            subs = locale_subtables(data, lhs, open_pos, stmt_end)
            for loc, vs, ve in subs:
                piece.append(lhs.encode("ascii") + b'["' + loc.encode("ascii") + b'"] = {}\r\n')
            for loc, vs, ve in subs:
                sub_lhs = "%s.%s" % (lhs, loc)
                i0, i1 = vs + 1, ve - 1
                records = split_records(data, i0, i1, sub_lhs)
                piece.append(b'SkuDBChunkHashes["' + sub_lhs.encode("ascii") + b'"] = "'
                             + hashlib.sha256(data[i0:i1]).hexdigest().encode("ascii") + b'"\r\n')
                n = emit_chunks(piece, data, sub_lhs, records, i0, i1)
                report.append((sub_lhs, len(records), n, count_dupes(records)))
        out.append(b"".join(piece))
    out.append(data[prev:])
    with open(path, "wb") as f:
        f.write(b"".join(out))
    return report


# ---------------------------------------------------------------------------
# verification (always reads the bytes back from disk, compares against .bak)

def extract_chunks(gen):
    """Parse the generated file bytes; return (dict path -> [body, ...] in file
    order, long-string spans for stub building). body is the verbatim slice
    between 'return {' and the trailing '\\r\\n}' scaffold."""
    marker = b'SkuDBChunks[#SkuDBChunks+1] = {"'
    chunks = {}
    stub_spans = []
    i = 0
    while True:
        i = gen.find(marker, i)
        if i == -1:
            break
        ps = i + len(marker)
        pe = gen.find(b'"', ps)
        path_name = gen[ps:pe].decode("ascii")
        j = pe + 1
        if gen[j:j + 2] != b", ":
            die("verify: malformed chunk statement at %d" % i)
        j += 2
        m = LONGOPEN.match(gen, j)
        if not m:
            die("verify: no long string in chunk statement at %d" % i)
        e = skip_long_bracket(gen, j)
        opener = m.end()
        closer = e - len(m.group(1)) - 2
        inner = gen[opener:closer]
        if not inner.startswith(b"return {") or not inner.endswith(b"\r\n}"):
            die("verify: chunk body scaffold mismatch at %d" % i)
        body = inner[len(b"return {"):-len(b"\r\n}")]
        chunks.setdefault(path_name, []).append(body)
        stub_spans.append((opener, closer))
        i = e
    return chunks, stub_spans


def verify_file(rel, tables, quiet=False):
    path = os.path.join(ASSETS, rel)
    bak = path + ".bak"
    if not os.path.exists(bak):
        die("verify: no .bak for %s (not converted yet?)" % rel)
    with open(bak, "rb") as f:
        pristine = f.read()
    if pristine.startswith(BOM):
        pristine = pristine[len(BOM):]
    with open(path, "rb") as f:
        gen = f.read()
    chunks, stub_spans = extract_chunks(gen)
    results = []
    for lhs, mode in tables:
        stmt_start, open_pos, stmt_end = find_stmt(pristine, lhs)
        wanted = []
        if mode == "flat":
            wanted.append((lhs, open_pos + 1, stmt_end - 1))
        else:
            for loc, vs, ve in locale_subtables(pristine, lhs, open_pos, stmt_end):
                wanted.append(("%s.%s" % (lhs, loc), vs + 1, ve - 1))
        for path_name, i0, i1 in wanted:
            orig_interior = pristine[i0:i1]
            bodies = chunks.pop(path_name, None)
            if not bodies:
                die("verify %s: no chunks for %s in output" % (rel, path_name))
            # (1) full reassembly: verbatim byte identity of the whole interior
            if b"".join(bodies) != orig_interior:
                die("verify %s: reassembled bytes differ for %s" % (rel, path_name))
            # (2) keys: sequence + uniqueness, pristine vs output chunks
            orig_records = split_records(pristine, i0, i1, path_name + " (pristine)")
            new_keys = []
            for bi, body in enumerate(bodies):
                where = "%s chunk %d" % (path_name, bi)
                recs = split_records(body, 0, len(body), where)
                new_keys.extend(k for k, _, _ in recs)
                # (3) literal-only content per chunk (risk A4)
                check_literal_only(body, where)
            if new_keys != [k for k, _, _ in orig_records]:
                die("verify %s: key sequence differs for %s" % (rel, path_name))
            dupes = count_dupes(orig_records)
            results.append((path_name, len(orig_records), len(bodies), dupes))
            if not quiet:
                print("  PASS %-42s %6d records, %3d chunks, %.1f MB%s"
                      % (path_name, len(orig_records), len(bodies), len(orig_interior) / 1e6,
                         (", %d dupe keys (last-wins kept)" % dupes) if dupes else ""))
    if chunks:
        die("verify %s: output contains chunks for unexpected paths: %s"
            % (rel, sorted(chunks)))
    # (4) luaparser parse of the scaffolding (bodies stubbed to 'return {}');
    # chunk-body COMPILABILITY is covered by (1)+(3): the bytes are the
    # original interior verbatim, cut at record boundaries, literal-only
    try:
        from luaparser import ast
        stub = bytearray(gen)
        for opener, closer in sorted(stub_spans, reverse=True):
            stub[opener:closer] = b"return {}"
        ast.parse(bytes(stub).decode("utf-8-sig"))
    except ImportError:
        print("  WARN: luaparser not installed, scaffold parse skipped")
    except ConvertError:
        raise
    except Exception as e:
        die("verify %s: scaffold does not parse: %s" % (rel, e))
    return results


# ---------------------------------------------------------------------------
# file-scope reference scan (risk A4 check 2): no OTHER file of the SkuDB
# block may read or write a wrapped table path at file scope (function bodies
# are fine - they run at event time, after the chunk loader).

def dotted_name(node):
    from luaparser import astnodes as N
    parts = []
    while isinstance(node, N.Index):
        idx = node.idx
        if isinstance(idx, N.Name):
            parts.append(idx.id)
        elif isinstance(idx, N.String):
            s = idx.s
            parts.append(s.decode("utf-8", "replace") if isinstance(s, bytes) else s)
        else:
            return None
        node = node.value
    if isinstance(node, N.Name):
        parts.append(node.id)
        parts.reverse()
        return ".".join(parts)
    return None


def scan_filescope():
    from luaparser import ast
    from luaparser import astnodes as N
    func_types = tuple(t for t in (getattr(N, "Function", None),
                                   getattr(N, "LocalFunction", None),
                                   getattr(N, "Method", None),
                                   getattr(N, "AnonymousFunction", None)) if t)
    hits = []
    for path in SCAN_FILES:
        if not os.path.exists(path):
            print("  WARN: scan file missing:", path)
            continue
        src = open(path, encoding="utf-8-sig").read()
        tree = ast.parse(src)

        # iterative walk (deep ASTs blow Python's recursion limit) with a
        # visited set as cycle guard
        stack = [(tree, False)]
        seen = set()
        while stack:
            node, in_func = stack.pop()
            if id(node) in seen:
                continue
            seen.add(id(node))
            if isinstance(node, func_types):
                in_func = True
            if isinstance(node, N.Index) and not in_func:
                name = dotted_name(node)
                if name:
                    for wp in WRAPPED_PATHS:
                        if name == wp or name.startswith(wp + "."):
                            hits.append("%s: file-scope reference to %s"
                                        % (os.path.relpath(path, ROOT), name))
                            break
            for child in vars(node).values():
                if isinstance(child, list):
                    for c in child:
                        if hasattr(c, "__dict__"):
                            stack.append((c, in_func))
                elif hasattr(child, "__dict__") and not isinstance(child, str):
                    stack.append((child, in_func))
    if hits:
        for h in hits:
            print("  FAIL", h)
        die("file-scope scan found %d reference(s) to wrapped paths" % len(hits))
    print("  PASS: no file-scope references to wrapped paths in %d files" % len(SCAN_FILES))


# ---------------------------------------------------------------------------

def unwrap():
    for rel, _ in TARGETS:
        path = os.path.join(ASSETS, rel)
        if os.path.exists(path + ".bak"):
            with open(path + ".bak", "rb") as f:
                raw = f.read()
            with open(path, "wb") as f:
                f.write(raw)
            print("  restored pristine (bak kept): %s" % rel)
        else:
            print("  no .bak, unchanged: %s" % rel)


def main():
    args = set(sys.argv[1:])
    if "--unwrap" in args or "--revert-all" in args:
        unwrap()
        print("Done. Code side: git revert the stage-2 commit if needed.")
        return
    verify_only = "--verify" in args
    all_reports = []
    try:
        if not verify_only:
            print("converting (from pristine .bak, idempotent):")
            for rel, tables in TARGETS:
                for name, n_rec, n_chunks, n_dupes in convert_file(rel, tables):
                    print("  wrote %-42s %6d records, %3d chunks" % (name, n_rec, n_chunks))
        print("verifying output bytes on disk against pristine .bak:")
        for rel, tables in TARGETS:
            all_reports.extend(verify_file(rel, tables))
        if "--no-filescope-scan" not in args:
            print("file-scope scan of the SkuDB TOC block (luaparser):")
            scan_filescope()
        else:
            print("file-scope scan SKIPPED (--no-filescope-scan)")
    except ConvertError as e:
        print("FAILED: %s" % e)
        if not verify_only:
            print("restoring pristine files (refusing to leave bad output on disk)")
            unwrap()
        sys.exit(2)
    with open(RECORDS_MANIFEST, "w", newline="\n") as f:
        f.write("# per-dataset record/chunk/duplicate-key counts, by _db_convert.py\n")
        f.write("# in-game record counts (/skudbcheck) = records minus dupe keys\n")
        for name, n_rec, n_chunks, n_dupes in all_reports:
            f.write("%s|%d|%d|%d\n" % (name, n_rec, n_chunks, n_dupes))
    total_rec = sum(r[1] for r in all_reports)
    total_chunks = sum(r[2] for r in all_reports)
    print("ALL PASS: %d datasets, %d records, %d chunks. Record counts -> %s"
          % (len(all_reports), total_rec, total_chunks,
             os.path.relpath(RECORDS_MANIFEST, ROOT)))


if __name__ == "__main__":
    main()
