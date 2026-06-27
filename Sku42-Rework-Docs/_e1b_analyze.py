#!/usr/bin/env py -3
# W4-E1b helper: analyse a hard-3 feature file before namespace extraction.
# For the given file:
#   - list every `function SkuCore:NAME` / `function SkuCore.NAME` def
#   - flag whether each def body references bare `self`
#   - count tree-wide call sites of each NAME via SkuCore:NAME / SkuCore.NAME
#     / SkuCore["NAME"] (any folder), so nothing is missed.
import os, re, sys, collections

ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku"

def read(p):
    try:
        return open(p, encoding="utf-8-sig").read()
    except Exception:
        return open(p, encoding="latin-1").read()

def all_lua():
    for dp, _, fs in os.walk(ROOT):
        if os.sep + "Libs" in dp:
            continue
        for fn in fs:
            if fn.endswith(".lua"):
                yield os.path.join(dp, fn)

target_file = sys.argv[1]
txt = read(os.path.join(ROOT, target_file))
lines = txt.splitlines()

# 1) collect defs and their body span (until matching top-level `end` at col0-ish)
def_re = re.compile(r"^\s*function\s+SkuCore([:.])([A-Za-z_]\w*)\s*\(")
defs = []  # (name, accessor, start_idx)
for i, ln in enumerate(lines):
    m = def_re.match(ln)
    if m:
        defs.append((m.group(2), m.group(1), i))

# body self-usage: scan from def start to next def (approx) for bare 'self'
def_starts = [d[2] for d in defs]
names = [d[0] for d in defs]
self_use = {}
for idx, (name, acc, start) in enumerate(defs):
    end = def_starts[idx+1] if idx+1 < len(defs) else len(lines)
    body = "\n".join(lines[start:end])
    # bare self not part of a longer ident
    uses_self = bool(re.search(r"(?<![\w.])self\b", body))
    self_use[name] = uses_self

print("=== %s : %d defs ===" % (target_file, len(defs)))
print("defs using bare 'self' in body:")
any_self = False
for name, acc, start in defs:
    if self_use[name]:
        any_self = True
        print("  L%-5d function SkuCore%s%s   <-- USES self" % (start+1, acc, name))
if not any_self:
    print("  (none)")

# 2) tree-wide call sites per name
nameset = set(names)
callsite = collections.defaultdict(lambda: collections.Counter())  # name -> file -> count
patt = {n: re.compile(r"SkuCore\s*[:.]\s*%s\b|SkuCore\s*\[\s*[\"']%s[\"']\s*\]" % (re.escape(n), re.escape(n))) for n in nameset}
for p in all_lua():
    t = read(p)
    base = os.path.relpath(p, ROOT)
    for n in nameset:
        c = len(patt[n].findall(t))
        if c:
            callsite[n][base] += c

print("\n=== tree-wide call sites (SkuCore:/./[] NAME), excluding the def itself ===")
selfbase = target_file
for name, acc, start in defs:
    files = callsite[name]
    total = sum(files.values())
    # subtract defs in own file? defs are `function SkuCore:NAME` not matched by call patt (no SkuCore: w/o function)... actually patt matches `SkuCore:NAME` inside the def line too.
    ext = {f: c for f, c in files.items() if f != selfbase}
    own = files.get(selfbase, 0)
    print("  %-40s own_file=%-3d external=%s" % (name, own, dict(ext) if ext else "{}"))
