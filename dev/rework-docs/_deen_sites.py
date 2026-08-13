#!/usr/bin/env python3
# Extract every Sku.deEn(de, en) call site so the French third argument can be
# filled in, then splice the translations back.
#
#   py -3 _deen_sites.py list           -> idx <TAB> file:line <TAB> de <TAB> en
#   py -3 _deen_sites.py apply <tsv>    -> insert aFr from "idx<TAB>fr" lines
#
# Keyed on INDEX into a deterministic scan order, not on the German text. The
# German arguments contain UTF-8, and one site stores it as escaped bytes
# (\195\188), so retyping them by hand to key the splice would silently miss
# exactly those sites. Index keying also survives line-number drift.
#
# Sites that already carry a third argument are skipped, so re-running is safe
# and incremental.

import io
import os
import re
import sys

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKU = os.path.join(REPO, "Sku")

CALL = re.compile(r'Sku\.deEn\(')


def lua_string(s, i):
    """Parse a Lua "..." literal at s[i]; return (text, endIndex) or (None, i)."""
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


def scan(path):
    """Yield (lineno, de, en, hasThird, endOfSecondArg)."""
    text = io.open(path, encoding="utf-8-sig").read()
    for m in CALL.finditer(text):
        i = m.end()
        while i < len(text) and text[i].isspace():
            i += 1
        de, j = lua_string(text, i)
        if de is None:
            continue
        k = j
        while k < len(text) and text[k].isspace():
            k += 1
        if k >= len(text) or text[k] != ",":
            continue
        k += 1
        while k < len(text) and text[k].isspace():
            k += 1
        en, l = lua_string(text, k)
        if en is None:
            continue
        p = l
        while p < len(text) and text[p].isspace():
            p += 1
        yield (text.count("\n", 0, m.start()) + 1, de, en,
               p < len(text) and text[p] == ",", l)


def all_files():
    for dp, dirs, fns in os.walk(SKU):
        dirs[:] = [d for d in dirs if d not in ("Libs", "SkuDB", "locales", "audio")]
        for f in sorted(fns):
            if f.endswith(".lua"):
                yield os.path.join(dp, f)


def pending():
    """[(idx, path, lineno, endpos, de, en)] for sites still lacking aFr."""
    rows, seen, nxt = [], {}, 0
    for p in all_files():
        for lineno, de, en, third, endpos in scan(p):
            if third:
                continue
            if de not in seen:
                seen[de] = nxt
                nxt += 1
            rows.append((seen[de], p, lineno, endpos, de, en))
    return rows


def cmd_list():
    rows = pending()
    first = {}
    for i, p, lineno, _, de, en in rows:
        first.setdefault(i, (p, lineno, de, en))
    for i in sorted(first):
        p, lineno, de, en = first[i]
        sys.stdout.write("%d\t%s:%d\t%s\t%s\n" % (i, os.path.relpath(p, REPO), lineno, de, en))
    sys.stderr.write("call sites needing aFr %d, distinct strings %d\n" % (len(rows), len(first)))


def cmd_apply(tsvpath):
    fr = {}
    for line in io.open(tsvpath, encoding="utf-8"):
        line = line.rstrip("\r\n")
        if not line or "\t" not in line:
            continue
        i, f = line.split("\t", 1)
        if f.strip():
            try:
                fr[int(i)] = f
            except ValueError:
                pass
    def restore_edges(src, dst):
        """Leading/trailing spaces are load-bearing here ("You offer " is
        concatenated with a value) but do not survive a TSV round-trip and are
        invisible in review. Take them from the English argument instead of
        trusting the translation to carry them."""
        lead = src[:len(src) - len(src.lstrip(" "))]
        trail = src[len(src.rstrip(" ")):] if src.strip(" ") else ""
        return lead + dst.strip(" ") + trail

    byfile = {}
    for i, p, lineno, endpos, de, en in pending():
        if i in fr:
            byfile.setdefault(p, []).append((endpos, restore_edges(en, fr[i])))
    total = 0
    for p, items in sorted(byfile.items()):
        text = io.open(p, encoding="utf-8-sig").read()
        for pos, v in sorted(items, reverse=True):
            ins = ', "%s"' % v.replace("\\", "\\\\").replace('"', '\\"')
            text = text[:pos] + ins + text[pos:]
        io.open(p, "w", encoding="utf-8-sig", newline="\n").write(text)
        total += len(items)
        print("%-46s +%d" % (os.path.relpath(p, REPO), len(items)))
    print("inserted %d third arguments" % total)


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "apply":
        cmd_apply(sys.argv[2])
    else:
        cmd_list()
