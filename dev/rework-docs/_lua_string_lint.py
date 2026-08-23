#!/usr/bin/env python3
"""Catch UNTERMINATED single-line string literals in Lua sources.

Why this exists: the `luaparser` package used as the pre-reload syntax gate does
NOT reject a raw newline inside a "..." literal, but the WoW client does
("unfinished string near ..."), and a load-time syntax error means the whole
file silently fails to load. That happened for real on 2026-08-23: a bash
heredoc ate the backslashes of "\\r\\n" and turned six string literals in
SkuAuras/Options.lua into unterminated ones. luaparser said OK; the client
refused the file and the aura menu was gone.

Run it as a second gate right after the luaparser check:

    py -3 dev/rework-docs/_lua_string_lint.py Sku

Scans a file, or every *.lua under a directory. Exit code 1 on any finding.
Long strings ([[ ]]) and block comments are skipped, so a multi-line literal
written the legal way is not reported.
"""
import io
import os
import sys


def scan(path):
    findings = []
    in_long = False
    for lineno, raw in enumerate(io.open(path, encoding="utf-8-sig", errors="replace"), 1):
        line = raw.rstrip("\n").rstrip("\r")

        if in_long:
            if "]]" in line:
                in_long = False
            continue

        stripped = line.lstrip()
        if stripped.startswith("--") and not stripped.startswith("--[["):
            continue
        if stripped.startswith("--[[") or ("[[" in line and "]]" not in line.split("[[", 1)[1]):
            # opens a long string / long comment that does not close on this line
            in_long = True
            continue

        quotes = 0
        apostrophes = 0
        i = 0
        escaped = False
        in_dq = False
        in_sq = False
        while i < len(line):
            c = line[i]
            if escaped:
                escaped = False
            elif c == "\\":
                escaped = True
            elif c == '"' and not in_sq:
                in_dq = not in_dq
                quotes += 1
            elif c == "'" and not in_dq:
                in_sq = not in_sq
                apostrophes += 1
            elif c == "-" and not in_dq and not in_sq and line[i:i + 2] == "--":
                break  # rest of the line is a comment
            i += 1

        if in_dq or in_sq:
            findings.append((lineno, line.strip()[:100]))
    return findings


def main():
    targets = sys.argv[1:] or ["Sku"]
    files = []
    for t in targets:
        if os.path.isdir(t):
            for root, _dirs, names in os.walk(t):
                for n in names:
                    if n.endswith(".lua"):
                        files.append(os.path.join(root, n))
        else:
            files.append(t)

    bad = 0
    for f in sorted(files):
        for lineno, text in scan(f):
            bad += 1
            print("%s:%d: unterminated string literal -> %s" % (f, lineno, text))
    print("checked %d file(s), %d finding(s)" % (len(files), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
