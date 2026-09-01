#!/usr/bin/env python3
# Build Sku/locales/frFR.lua from the enUS table plus a translation store.
#
# WORKFLOW
#   py -3 _frfr_locale.py extract          -> scratch/frfr_src.tsv  (idx, key, enUS)
#   py -3 _frfr_locale.py batch <n> <size> -> print one batch to translate
#   ... append the answers to scratch/parts/frfr_keys.tsv as  key <TAB> french
#   py -3 _frfr_locale.py verify           -> would assemble change frFR.lua?
#   py -3 _frfr_locale.py assemble         -> Sku/locales/frFR.lua + validation
#
# THE STORE IS KEYED BY THE LOCALE KEY, NOT BY LINE POSITION (2026-08-26).
#
# It used to be keyed by the entry's INDEX in enUS.lua, which quietly rotted:
# enUS.lua grew from 3250 to 3331 entries after the part files were written, so
# 2870 of 3250 indices no longer pointed at the key they had been translated
# for - first drift at index 52. An assemble run would have shifted nearly the
# whole French table onto the wrong keys ("Aktuelle Ressource" = "Carte actuelle
# par distance avec auto", and so on down the file) while still reporting
# "validation clean", because nothing in the pipeline compared the two. Every
# new enUS entry made it worse. A key is stable under insertions, so the store
# cannot drift again, and an entry whose key disappears is now a loud abort
# instead of a silent one-line shift (see the orphan guard in load_store).
#
# SAFETY: assemble falls back to the enUS value for any entry not in the store,
# so the generated file is ALWAYS complete and valid Lua. A partially translated
# frFR.lua behaves exactly like today's English fallback for the untranslated
# remainder - never blank, never missing keys.
#
# The keys of Sku's locale table are a MIX of German and English originals
# (~2000 German-keyed, ~1200 English-keyed), so the enUS *value* is the only
# field that is uniformly English. That is the translation source.

import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
LOCALES = os.path.join(REPO, "Sku", "locales")
SCRATCH = os.path.join(HERE, "_frfr_scratch")
PARTS = os.path.join(SCRATCH, "parts")
SRC = os.path.join(SCRATCH, "frfr_src.tsv")
STORE = os.path.join(PARTS, "frfr_keys.tsv")
HEADER = "#format: key\tfrench"

RX = re.compile(r'^\s*L\[(".*?(?<!\\)")\]\s*=\s*(".*?(?<!\\)")\s*(--.*)?$')


def decode(lit):
    body = lit[1:-1]
    out, i = [], 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            out.append({"n": "\n", "t": "\t"}.get(body[i + 1], body[i + 1]))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def encode(s):
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def parse(path):
    """Ordered [(key, value)] from a locale file."""
    return [(k, v) for k, v, c in parse_full(path)]


def parse_full(path):
    """Ordered [(key, value, trailing comment)] from a locale file."""
    rows = []
    with io.open(path, encoding="utf-8-sig") as fh:
        for line in fh:
            if not line.lstrip().startswith("L["):
                continue
            m = RX.match(line.rstrip())
            if m:
                rows.append((decode(m.group(1)), decode(m.group(2)), (m.group(3) or "").strip()))
    return rows


def esc_line(s):
    """One-line, round-trippable form for the TSV batch/store files."""
    return (s.replace("\\", "\\\\").replace("\r", "\\r")
             .replace("\n", "\\n").replace("\t", "\\t"))


def unesc_line(s):
    out, i = [], 0
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s):
            out.append({"n": "\n", "r": "\r", "t": "\t", "\\": "\\"}.get(s[i + 1], s[i + 1]))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def restore_edges(src, dst):
    """Give dst the same leading/trailing spaces as src."""
    lead = src[:len(src) - len(src.lstrip(" "))]
    trail = src[len(src.rstrip(" ")):] if src.strip(" ") else ""
    return lead + dst.strip(" ") + trail


def legacy_files():
    """Part files still in the old index-keyed format."""
    if not os.path.isdir(PARTS):
        return []
    out = []
    for name in sorted(os.listdir(PARTS)):
        path = os.path.join(PARTS, name)
        if not name.endswith(".tsv") or path == STORE:
            continue
        with io.open(path, encoding="utf-8") as fh:
            first = fh.readline().rstrip("\n").rstrip("\r")
        if first != HEADER:
            out.append(path)
    return out


def load_legacy():
    """idx -> french, from the pre-2026-08-26 index-keyed part files."""
    out = {}
    for path in legacy_files():
        with io.open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n").rstrip("\r")
                if not line or "\t" not in line:
                    continue
                idx, fr = line.split("\t", 1)
                try:
                    out[int(idx)] = unesc_line(fr)
                except ValueError:
                    pass
    return out


def load_store(rows=None, allow_orphans=False):
    """key -> (french, comment). Aborts on a key no longer in enUS.lua.

    A '#' does NOT start a comment in this file: L["#"] is a real locale key
    ("Dièse"), and skipping lines by their first character dropped it silently.
    Only the format header line is skipped.
    """
    stale = legacy_files()
    if stale:
        sys.exit("index-keyed part files are still present:\n  "
                 + "\n  ".join(stale)
                 + "\nThey drift against enUS.lua. Run 'migrate' once to convert them.")
    out = {}
    if os.path.isfile(STORE):
        with io.open(STORE, encoding="utf-8") as fh:
            for line in fh:
                line = line.rstrip("\n").rstrip("\r")
                if not line or line == HEADER or "\t" not in line:
                    continue
                cols = line.split("\t")
                out[unesc_line(cols[0])] = (unesc_line(cols[1]),
                                            unesc_line(cols[2]) if len(cols) > 2 else "")
    if rows is not None and not allow_orphans:
        known = set(k for k, _ in rows)
        orphans = sorted(k for k in out if k not in known)
        if orphans:
            print("ORPHANED STORE ENTRIES (%d) - key no longer in enUS.lua:" % len(orphans))
            for k in orphans[:40]:
                print("  %s\t%s" % (esc_line(k), esc_line(out[k][0])))
            if len(orphans) > 40:
                print("  ... %d more" % (len(orphans) - 40))
            sys.exit("Refusing to assemble. The key was renamed or removed: re-add the "
                     "translation under the new key, or run 'prune' to drop these entries.")
    return out


def write_store(store):
    os.makedirs(PARTS, exist_ok=True)
    with io.open(STORE, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(HEADER + "\n")
        for key in sorted(store):
            val, comment = store[key]
            line = "%s\t%s" % (esc_line(key), esc_line(val))
            if comment:
                line += "\t" + esc_line(comment)
            fh.write(line + "\n")


def cmd_extract():
    os.makedirs(PARTS, exist_ok=True)
    rows = parse(os.path.join(LOCALES, "enUS.lua"))
    with io.open(SRC, "w", encoding="utf-8", newline="\n") as fh:
        for i, (k, v) in enumerate(rows):
            fh.write("%d\t%s\t%s\n" % (i, k.replace("\t", " "), v.replace("\t", " ")))
    print("extracted %d entries -> %s" % (len(rows), SRC))


def cmd_batch(n, size):
    rows = parse(os.path.join(LOCALES, "enUS.lua"))
    store = load_store(rows)
    start, end = n * size, min((n + 1) * size, len(rows))
    shown = 0
    for i in range(start, end):
        k, v = rows[i]
        if k in store:
            continue
        print("%s\t%s" % (esc_line(k), esc_line(v)))
        shown += 1
    print("--- batch %d: %d untranslated of %d..%d (total %d) ---"
          % (n, shown, start, end - 1, len(rows)))


def cmd_migrate():
    """One-off: index-keyed part files -> the key-keyed store.

    The SHIPPED frFR.lua wins over the part files, because it is the file that
    has been maintained by hand since the parts were last touched (22 values
    diverged, among them the deliberate 'bring' revert from PR #5 and the four
    zone names from PR #8). Importing the part value instead would silently
    undo those.
    """
    rows = parse(os.path.join(LOCALES, "enUS.lua"))
    fr, frcom = {}, {}
    for k, v, c in parse_full(os.path.join(LOCALES, "frFR.lua")):
        fr[k] = v                      # duplicate key: last wins, as AceLocale does
        if c:
            frcom[k] = c
    en = dict(rows)
    snap = {}
    if os.path.isfile(SRC):
        with io.open(SRC, encoding="utf-8") as fh:
            for line in fh:
                p = line.rstrip("\n").split("\t")
                if len(p) >= 2 and p[0].isdigit():
                    snap[int(p[0])] = p[1]
    legacy = load_legacy()
    had_part = set(snap[i] for i in legacy if i in snap)

    store, translated, english, dropped = {}, 0, 0, 0
    for key, val in rows:
        shipped = fr.get(key)
        if shipped is None:
            continue
        if key in had_part or shipped != val or key in frcom:
            store[key] = (shipped, frcom.get(key, ""))
            if shipped == val:
                english += 1
            else:
                translated += 1
    for i in legacy:
        key = snap.get(i)
        if key is None or key not in en:
            dropped += 1
    write_store(store)
    print("store written: %s" % STORE)
    print("  entries %d (translated %d, deliberately english %d)"
          % (len(store), translated, english))
    print("  legacy part entries whose index no longer resolves: %d (dropped)" % dropped)
    for path in legacy_files():
        os.remove(path)
        print("  removed legacy part file %s" % os.path.basename(path))


def cmd_prune():
    rows = parse(os.path.join(LOCALES, "enUS.lua"))
    store = load_store(rows, allow_orphans=True)
    known = set(k for k, _ in rows)
    orphans = sorted(k for k in store if k not in known)
    for k in orphans:
        print("dropping %s\t%s" % (esc_line(k), esc_line(store.pop(k)[0])))
    write_store(store)
    print("pruned %d orphan(s), %d entries left" % (len(orphans), len(store)))


def build():
    """The frFR.lua text plus the validation findings."""
    rows = parse(os.path.join(LOCALES, "enUS.lua"))
    store = load_store(rows)
    out = [
        "--[[",
        "\tSku French locale.",
        "",
        "\tGENERATED by dev/rework-docs/_frfr_locale.py - re-run assemble after",
        "\tediting the translation store; do not hand-edit this file.",
        "",
        "\tMachine translated from the enUS values. The keys of this table are a",
        "\tmix of German and English originals, so the enUS value is the only",
        "\tuniformly English field and therefore the translation source.",
        "",
        "\tEntries not yet translated fall back to their English value, which is",
        "\texactly what a French client saw before this file existed.",
        "",
        "\tInstructions for translators:",
        "\t\t- don't omit leading or trailing spaces",
        "\t\t- don't omit semicolons",
        "\t\t- don't replace semicolons by spaces",
        "]]",
        "",
        'local L = LibStub("AceLocale-3.0"):NewLocale("Sku", "frFR")',
        "if not L then return end",
    ]
    translated, problems = 0, []
    for k, v in rows:
        # Sku.Loc is read straight from L["locale"] (Sku/Core.lua:28) and selects
        # which SkuDB name tables the whole client uses, so it must stay the
        # locale CODE and must never be re-imported from enUS. It is written once
        # at the end of the file instead of at its enUS position.
        if k == "locale":
            continue
        val, comment = store.get(k, (None, ""))
        if val is None or val == "":
            val = v
        else:
            # Leading/trailing spaces are load-bearing in this table (the file
            # header warns translators about exactly that) but they do not
            # survive a TSV round-trip and are invisible in review. So they are
            # not carried in the translation at all: re-apply the English
            # entry's own edge whitespace to the French text.
            val = restore_edges(v, val)
            translated += 1
            if val.count("%s") != v.count("%s") or val.count("%d") != v.count("%d"):
                problems.append("%r placeholder mismatch: %r -> %r" % (k, v, val))
            if v.count(";") != val.count(";"):
                problems.append("%r semicolon count: %r -> %r" % (k, v, val))
        line = 'L["%s"] = "%s"' % (encode(k), encode(val))
        if comment:
            line += " " + comment
        out.append(line)
    out.append("")
    out.append("-- NOT user-facing text: Sku.Loc is read straight from this (Sku/Core.lua:28)")
    out.append("-- and selects which SkuDB name tables the whole client uses. It must stay the")
    out.append("-- locale CODE. assemble skips the enUS 'locale' row and writes this line, so a")
    out.append("-- regeneration can no longer re-import it - check with _locale_dupes.py, which")
    out.append("-- fails on a duplicate here.")
    out.append('L["locale"] = "frFR"')
    out.append("")
    return "\ufeff" + "\n".join(out), len(rows), translated, problems


def report(total, translated, problems):
    print("entries %d, translated %d (%.1f%%), english fallback %d"
          % (total, translated, translated / total * 100, total - translated))
    if problems:
        print("\nVALIDATION PROBLEMS (%d):" % len(problems))
        for p in problems[:40]:
            print("  " + p)
    else:
        print("validation clean")


def cmd_assemble():
    text, total, translated, problems = build()
    dest = os.path.join(LOCALES, "frFR.lua")
    with io.open(dest, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(text)
    print("wrote %s" % dest)
    report(total, translated, problems)


def effective(text):
    """key -> value as AceLocale would see it (duplicates: last wins)."""
    out = {}
    for line in text.splitlines():
        if not line.lstrip().startswith("L["):
            continue
        m = RX.match(line.rstrip())
        if m:
            out[decode(m.group(1))] = decode(m.group(2))
    return out


def cmd_verify():
    """Assemble in memory and diff against the shipped file - changes nothing.

    This is the regression test for the drift that made the store key-based:
    right after a clean assemble it must say IDENTICAL, and the per-key
    comparison must stay empty no matter how the file is laid out.
    """
    text, total, translated, problems = build()
    dest = os.path.join(LOCALES, "frFR.lua")
    with io.open(dest, encoding="utf-8-sig") as fh:
        have = "\ufeff" + fh.read()
    report(total, translated, problems)

    a, b = effective(have), effective(text)
    lost = sorted(set(a) - set(b))
    added = sorted(set(b) - set(a))
    changed = sorted(k for k in set(a) & set(b) if a[k] != b[k])
    print("")
    print("per-key: %d on disk, %d generated, %d lost, %d added, %d changed"
          % (len(a), len(b), len(lost), len(added), len(changed)))
    for k in (lost + added)[:20]:
        print("  key only on one side: %s" % esc_line(k))
    for k in changed[:20]:
        print("  %s\n    disk: %s\n    gen : %s"
              % (esc_line(k), esc_line(a[k]), esc_line(b[k])))

    if have == text:
        print("frFR.lua is BYTE-IDENTICAL to what assemble would write")
        return
    la, lb = have.splitlines(), text.splitlines()
    diff = [i for i in range(max(len(la), len(lb)))
            if (la[i] if i < len(la) else None) != (lb[i] if i < len(lb) else None)]
    print("frFR.lua differs in layout: %d line(s) (%d on disk, %d generated)"
          % (len(diff), len(la), len(lb)))
    for i in diff[:10]:
        print("  line %d" % (i + 1))
        print("    disk: %s" % (la[i] if i < len(la) else "<none>"))
        print("    gen : %s" % (lb[i] if i < len(lb) else "<none>"))
    sys.exit(1)


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "assemble"
    if cmd == "extract":
        cmd_extract()
    elif cmd == "batch":
        cmd_batch(int(sys.argv[2]), int(sys.argv[3]) if len(sys.argv) > 3 else 200)
    elif cmd == "migrate":
        cmd_migrate()
    elif cmd == "prune":
        cmd_prune()
    elif cmd == "verify":
        cmd_verify()
    elif cmd == "assemble":
        cmd_assemble()
    else:
        # An UNKNOWN argument used to fall through to assemble, so a harmless
        # "--help" silently rewrote frFR.lua - and with it reverted every string
        # that had been hand-added to the file but never put into the store
        # (28 of them on 2026-09-01). Nothing but "assemble" or no argument at
        # all may write the locale.
        sys.exit("unknown command %r\n"
                 "usage: _frfr_locale.py [extract | batch <n> [size] | migrate | "
                 "prune | verify | assemble]\n"
                 "       no argument = assemble (writes Sku/locales/frFR.lua)" % cmd)
