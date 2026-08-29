#!/usr/bin/env python3
# Syntax gate for Sku's Lua files -- the CLAUDE.md one-liner, but usable on the
# files it chokes on.
#
#   py -3 dev/rework-docs/_lua_syntax_check.py Sku/SkuChat/Core.lua [more...]
#
# WHY THIS EXISTS
#   luaparser is stricter than the client in BOTH directions:
#     * it ACCEPTS a raw newline inside a "..." literal, which WoW refuses at
#       load time -- that is what _lua_string_lint.py is for, run it too;
#     * it REJECTS escapes that are legal in Lua 5.1, where an unknown escape
#       simply yields the character itself. Sku/SkuChat/Core.lua uses "\]" and
#       "\." and therefore cannot be parsed at all by the plain one-liner,
#       even though it ships and runs.
#   For the CHECK only, the non-standard escapes are neutralised in a copy in
#   memory. The file on disk is never touched.
#
# Exit 1 on the first file that fails to parse.

import io
import os
import re
import sys

from luaparser import ast

BS = chr(92)
# Escapes Lua 5.1 gives a special meaning; everything else is just the char.
VALID = set("abfnrtvxz0123456789" + BS + '"' + "'" + chr(10))
ESCAPE = re.compile(re.escape(BS) + "(.)", re.S)


def neutralise(match):
    char = match.group(1)
    return (BS + char) if char in VALID else char


def main(paths):
    if not paths:
        print("usage: _lua_syntax_check.py <file.lua> [...]")
        return 2
    failed = 0
    for path in paths:
        if not os.path.isfile(path):
            print("MISSING   ", path)
            failed = 1
            continue
        # utf-8-sig: Sku's Lua files start with a BOM the parser would trip on.
        src = io.open(path, encoding="utf-8-sig").read()
        try:
            ast.parse(ESCAPE.sub(neutralise, src))
        except Exception as err:
            print("SYNTAX FAIL", path, str(err)[:300])
            failed = 1
        else:
            print("SYNTAX OK  ", path)
    return failed


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
