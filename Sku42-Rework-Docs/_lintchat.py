import re
from luaparser import ast

p = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku/SkuChat/Core.lua"
s = open(p, encoding="utf-8-sig").read()
# Drop the backslash before regex-style escape chars that luaparser's strict
# lexer rejects (e.g. \. \] \[ \( \+), while keeping genuine Lua escapes
# (\n \t \" \\ etc.). Pre-existing in this file, unrelated to the W4 edit.
keep = set("abfnrtvxz0123456789\"'\\\n")
s = re.sub(r"\\(.)", lambda m: m.group(1) if m.group(1) not in keep else m.group(0), s)
ast.parse(s)
print("SkuChat/Core.lua structure OK (regex escapes neutralized)")
