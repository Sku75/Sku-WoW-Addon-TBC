#!/usr/bin/env python3
# Extract tAdditionalTranslations (SkuZOptions/utilities.lua) - the hand-written
# German->English overrides the /sku translate route pipeline uses for terms the
# id-linked name tables cannot resolve.
#
#   py -3 _route_overrides.py list          -> idx <TAB> de <TAB> en <TAB> kind
#   py -3 _route_overrides.py apply <tsv>   -> write the frFR sibling table
#
# "kind" classifies each entry, because they are not one thing:
#   place  - a proper noun (Emberstrife's Den, Salty Sailor Tavern). These must
#            be IMPORTED, not invented; matched against the frFR client dump.
#   prose  - a route instruction ("STOP! From here you have to..."). Genuinely
#            translatable text.
# Guessing a French place name would put wrong data into route output, so
# unmatched places are reported rather than translated.

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(REPO, "Sku", "SkuZOptions", "utilities.lua")
SV = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
      r"\WTF\Account\1107979492#1\SavedVariables\Sku.lua")


def lua_string(s, i):
    if i >= len(s) or s[i] != '"':
        return None, i
    out, i = [], i + 1
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append(s[i:i + 2]); i += 2; continue
        if s[i] == '"':
            return "".join(out), i + 1
        out.append(s[i]); i += 1
    return None, i


def entries():
    text = io.open(SRC, encoding="utf-8-sig").read()
    start = text.find("local tAdditionalTranslations")
    brace = text.find("{", start)
    depth, i = 1, brace + 1
    out = []
    while i < len(text) and depth > 0:
        if text[i] == "{":
            depth += 1; i += 1; continue
        if text[i] == "}":
            depth -= 1; i += 1; continue
        if text[i] == "[":
            j = i + 1
            while j < len(text) and text[j].isspace():
                j += 1
            de, k = lua_string(text, j)
            if de is None:
                i += 1; continue
            while k < len(text) and text[k].isspace():
                k += 1
            if k < len(text) and text[k] == "]":
                k += 1
                while k < len(text) and text[k].isspace():
                    k += 1
                if k < len(text) and text[k] == "=":
                    k += 1
                    while k < len(text) and text[k].isspace():
                        k += 1
                    en, m = lua_string(text, k)
                    if en is not None:
                        out.append((de, en))
                        i = m
                        continue
            i = k
            continue
        i += 1
    return out


def dump_names():
    """Every French name the client gave us, keyed by nothing - just the set of
    (english-ish id) -> french is unavailable here, so we can only report."""
    names = []
    try:
        lines = io.open(SV, encoding="utf-8", errors="replace").read().splitlines()
    except OSError:
        return names
    start = None
    for i, l in enumerate(lines):
        if l.strip().startswith('["mapNameDump"] = {'):
            start = i
            break
    if start is None:
        return names
    depth = 0
    for l in lines[start:]:
        depth += l.count("{") - l.count("}")
        m = re.match(r'^\s*\[\d+\]\s*=\s*"(.*)",?\s*$', l)
        if m:
            names.append(m.group(1))
        if depth <= 0 and l.strip().endswith("},"):
            break
    return names


PROSE = re.compile(r'[.!?]\s|\b(you|the|from|here|and|to|not|is|are|can)\b\s+\w+\s+\w+', re.I)


def classify(en):
    if len(en) > 60 or PROSE.search(en) and len(en.split()) > 6:
        return "prose"
    return "place"


def cmd_list():
    rows = entries()
    for i, (de, en) in enumerate(rows):
        sys.stdout.write("%d\t%s\t%s\t%s\n" % (i, de, en, classify(en)))
    kinds = {}
    for _, en in rows:
        k = classify(en)
        kinds[k] = kinds.get(k, 0) + 1
    sys.stderr.write("entries %d  %s\n" % (len(rows), kinds))


if __name__ == "__main__":
    cmd_list()


def cmd_apply(hits_tsv, prose_tsv, out_lua):
    """Emit the frFR sibling of tAdditionalTranslations.

    Two sources, deliberately kept apart:
      hits  - place names RESOLVED from the real frFR client dump. Imported,
              never invented, same rule as the rest of the game data.
      prose - route instructions, genuinely translated.
    Anything in neither stays English: guessing a French place name would put
    wrong data into route output, which is worse than an English one.
    """
    def load(p):
        d = {}
        for line in io.open(p, encoding="utf-8"):
            line = line.rstrip("\r\n")
            if not line or "\t" not in line:
                continue
            i, v = line.split("\t", 1)
            if v.strip():
                try:
                    d[int(i)] = v
                except ValueError:
                    pass
        return d

    hits, prose = load(hits_tsv), load(prose_tsv)
    rows = entries()
    out = [
        "-- [v42.09 i18n] French sibling of tAdditionalTranslations.",
        "--",
        "-- GENERATED by dev/rework-docs/_route_overrides.py - do not hand-edit.",
        "--",
        "-- Place names are IMPORTED from a real frFR client capture (/skudebug",
        "-- dumpmapnames), not invented. Route instructions are translated. Entries",
        "-- that are neither keep their English value: a guessed French place name",
        "-- would corrupt route output, which is worse than leaving it English.",
        "SkuOptions = SkuOptions or {}",
        "SkuOptions.RouteOverridesFrFR = {",
    ]
    n_place = n_prose = n_keep = 0
    for i, (de, en) in enumerate(rows):
        if i in hits:
            v, kind = hits[i], "place"
            n_place += 1
        elif i in prose:
            v, kind = prose[i], "prose"
            n_prose += 1
        else:
            v, kind = en, None
            n_keep += 1
        if kind:
            out.append('\t["%s"] = "%s",' % (
                de.replace("\\", "\\\\").replace('"', '\\"'),
                v.replace("\\", "\\\\").replace('"', '\\"')))
    out.append("}")
    io.open(out_lua, "w", encoding="utf-8", newline="\n").write("\n".join(out) + "\n")
    print("wrote %s: %d imported places, %d translated instructions, %d left English"
          % (os.path.relpath(out_lua, REPO), n_place, n_prose, n_keep))
