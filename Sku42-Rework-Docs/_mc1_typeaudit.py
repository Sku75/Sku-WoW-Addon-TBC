"""Audit SkuSettings:Register schema entries: does declared `type` match the
type implied by `default`? A mismatch means validation would false-positive on a
correct option flip. Reports every entry where type(default) != declared type."""
import re, glob, os

FILES = [
    "Sku/SkuMob/Options.lua",
    "Sku/SkuQuest/Options.lua",
    "Sku/SkuChat/Options.lua",
    "Sku/SkuNav/Options.lua",
    "Sku/SkuZOptions/Options.lua",
    "Sku/SkuCore/Options.lua",
]
ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42"

def infer(default_src):
    s = default_src.strip()
    if s in ("true", "false"):
        return "boolean"
    if re.fullmatch(r"-?%d+", s.replace("%", "")):  # guard, shouldn't hit
        return "number"
    if re.fullmatch(r"-?\d+(\.\d+)?", s):
        return "number"
    if s.startswith('"') or s.startswith("'") or s.startswith("[["):
        return "string"
    if s.startswith("L[") or s.startswith("L "):
        return "string"   # localized string
    if s.startswith("{"):
        return "table"
    return None  # unknown (expression / table ref) -> can't infer

# entry: ["dotted.key"] = { scope = "x", default = <val>, type = "t" },
# default value may contain commas inside strings rarely; handle simple cases.
ENTRY = re.compile(r'\[\s*"([^"]+)"\s*\]\s*=\s*\{(.*)\}', re.S)
FIELD_TYPE = re.compile(r'type\s*=\s*"(\w+)"')
FIELD_DEF  = re.compile(r'default\s*=\s*(.+?)\s*,\s*type\s*=')

total = 0; mism = 0; uninf = 0
for f in FILES:
    p = os.path.join(ROOT, f)
    if not os.path.exists(p):
        print("MISSING", f); continue
    txt = open(p, encoding="utf-8-sig").read()
    # only scan inside Register(...) blocks
    for rb in re.finditer(r'SkuSettings:Register\("(\w+)",\s*\{(.*?)\n\}\)', txt, re.S):
        mod = rb.group(1); body = rb.group(2)
        for line in body.split("\n"):
            m = ENTRY.search(line)
            if not m: continue
            key, inner = m.group(1), m.group(2)
            t = FIELD_TYPE.search(inner)
            d = FIELD_DEF.search(line)
            if not t: continue
            total += 1
            declared = t.group(1)
            if not d:
                uninf += 1; continue
            inferred = infer(d.group(1))
            if inferred is None:
                uninf += 1; continue
            if inferred != declared:
                mism += 1
                print("MISMATCH %-10s %-45s declared=%-8s default=%r -> %s"
                      % (mod, key, declared, d.group(1).strip(), inferred))

print("\nTotal entries with default+type: %d | mismatches: %d | uninferable(no default/expr): %d"
      % (total, mism, uninf))
