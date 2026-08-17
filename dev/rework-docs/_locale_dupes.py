# Duplicate-key report for Sku's AceLocale files.
#
# Why this exists (2026-08-16, after PR #2):
#
# AceLocale-3.0 resolves a duplicated key DIFFERENTLY depending on whether the
# locale is the default one (Libs/AceLocale-3.0/AceLocale-3.0.lua):
#
#   * enUS is registered with isDefault = true -> the proxy at line 67 REFUSES
#     to overwrite an existing value, so the FIRST occurrence wins.
#   * deDE / frFR are non-default -> the proxy at line 53 rawsets
#     unconditionally, so the LAST occurrence wins.
#
# So the same duplicated key can resolve to two different ENTRIES depending on
# the client language. L["SKU_KEY_DEBUGMODE"] is a live example: English gets
# "debug mode" (first), German "debug modus" (last), French "sortie de
# debogage" (last, and semantically "debug output").
#
# The dangerous case is a key that is not text at all. frFR.lua carried
# L["locale"] twice - "enUS" in the sorted body and "frFR" appended at the end.
# It only resolved to "frFR" because non-default locales are last-wins; a
# regeneration or an alphabetical sort of that file would have flipped the
# whole French client to English DATA silently, with no error anywhere.
#
# Usage:
#   py -3 dev/rework-docs/_locale_dupes.py            # conflicting values only
#   py -3 dev/rework-docs/_locale_dupes.py --all      # every duplicate
#
# Exit code 1 if any CONFLICTING duplicate is found, so it can gate a release.
#
# Trailing "-- comment" note (2026-08-16, after PR #3): a line's raw
# right-hand side is "<lua string literal> -- optional comment". Comparing
# that raw text (as the tool originally did) flags two lines as
# CONFLICTING whenever their trailing comment differs, even when the
# actual Lua string is byte-identical - e.g. `"Copper" --currency unit
# name` vs `"Copper"` is not a real conflict, AceLocale never sees the
# comment. Conflict detection below compares only the parsed string
# literal (VALUE, applied to each entry's raw text); the raw text is
# still what gets printed, so --all output is unchanged.

import collections
import io
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "Sku", "locales")
FILES = ["enUS.lua", "deDE.lua", "frFR.lua"]

# L["key"] = value   /   L['key'] = value   /   L[ [[key]] ] = value
KEY = re.compile(r'^L\[\s*("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|\[\[.*?\]\])\s*\]\s*=\s*(.*)$')
# Same string-literal grammar, applied to the right-hand side to split the
# actual Lua value from a trailing comment.
VALUE = re.compile(r'^("(?:[^"\\]|\\.)*"|\'(?:[^\'\\]|\\.)*\'|\[\[.*?\]\])')


def normalize(raw):
    m = VALUE.match(raw)
    return m.group(1) if m else raw


def scan(path):
    keys = collections.OrderedDict()
    with io.open(path, "r", encoding="utf-8-sig", newline="") as fh:
        for n, line in enumerate(fh.read().splitlines(), 1):
            m = KEY.match(line.strip())
            if m:
                raw = m.group(2).strip()
                keys.setdefault(m.group(1), []).append((n, raw, normalize(raw)))
    return keys


def main():
    show_all = "--all" in sys.argv
    conflicts = 0
    for name in FILES:
        path = os.path.join(ROOT, name)
        if not os.path.exists(path):
            print("%s: MISSING" % name)
            continue
        keys = scan(path)
        dupes = [(k, v) for k, v in keys.items() if len(v) > 1]
        bad = [(k, v) for k, v in dupes if len(set(x[2] for x in v)) > 1]
        # enUS is the AceLocale default locale -> first occurrence wins.
        # Every other locale is last-wins.
        winner = "FIRST" if name.startswith("enUS") else "LAST"
        print("%s: %d keys, %d duplicated, %d with CONFLICTING values (%s wins)"
              % (name, len(keys), len(dupes), len(bad), winner))
        conflicts += len(bad)
        for k, v in (dupes if show_all else bad):
            print("   %s" % k)
            win = 0 if winner == "FIRST" else len(v) - 1
            for i, (n, val, norm) in enumerate(v):
                print("      line %-6d %s %s" % (n, "<--" if i == win else "   ", val))
        print("")
    if conflicts:
        print("%d conflicting duplicate(s). Delete the losing line, do not "
              "rely on AceLocale's resolution order." % conflicts)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
