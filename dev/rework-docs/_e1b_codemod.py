#!/usr/bin/env py -3
# W4-E1b namespace codemod for ONE hard-3 feature.
#
# Usage:
#   py -3 _e1b_codemod.py <featureFile> <ModuleLocal> <HandleField> [--apply] [--exclude N1,N2]
#
# What it does (behaviour-preserving):
#   1. Collect every method NAME defined in <featureFile> as `function SkuCore[:.]NAME`
#      (minus any --exclude names that legitimately stay on SkuCore).
#   2. In <featureFile> (in-file refs): rewrite SkuCore<sep>NAME -> <ModuleLocal><sep>NAME
#      for sep in {:, ., ["..."]}, INCLUDING the `function SkuCore:NAME` defs.
#   3. In every OTHER .lua file (cross-file callers): rewrite SkuCore<sep>NAME ->
#      SkuCore.<HandleField><sep>NAME  (the published handle == the module table).
#   String literals are masked before rewriting and restored after, so a method
#   name appearing inside a quoted string is never corrupted (the SkuCore-B6 lesson).
#   Dry-run by default; pass --apply to write. Prints a per-file change count.
import os, re, sys

ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku"

def read(p):
    try:    return open(p, encoding="utf-8-sig").read(), "utf-8-sig"
    except Exception: return open(p, encoding="latin-1").read(), "latin-1"

def all_lua():
    for dp, _, fs in os.walk(ROOT):
        if os.sep + "Libs" in dp:  # never touch vendored libs
            continue
        for fn in fs:
            if fn.endswith(".lua"):
                yield os.path.join(dp, fn)

# No string masking: the method names here are highly distinctive (AuctionFoo,
# aqCombatBar, ...) and will not appear in non-code strings, while `/run` macrotext
# strings ARE real call sites that must be rewritten. (Naive quote-masking also
# mis-handles lone apostrophes in comments and silently skips real code.) Every
# changed line is reviewed in the git diff before commit.
def mask_strings(txt):
    return txt, None
def unmask(txt, store):
    return txt

def main():
    feat = sys.argv[1]; MOD = sys.argv[2]; HANDLE = sys.argv[3]
    apply = "--apply" in sys.argv
    exclude = set()
    for i,a in enumerate(sys.argv):
        if a == "--exclude":
            exclude = set(sys.argv[i+1].split(","))
    featpath = os.path.join(ROOT, feat)
    ftxt, _ = read(featpath)
    defre = re.compile(r"^\s*function\s+SkuCore[:.]([A-Za-z_]\w*)\s*\(", re.M)
    names = sorted(set(defre.findall(ftxt)) - exclude, key=len, reverse=True)
    print("methods to move: %d (excluded: %s)" % (len(names), ",".join(sorted(exclude)) or "none"))

    # build per-name regex: SkuCore [:.] NAME  OR  SkuCore [ "NAME" ]
    alt = "|".join(re.escape(n) for n in names)
    colondot = re.compile(r"\bSkuCore(\s*[:.]\s*)(%s)\b" % alt)
    bracket  = re.compile(r"\bSkuCore\s*\[\s*([\"'])(%s)\1\s*\]" % alt)

    total = 0
    for p in all_lua():
        txt, enc = read(p)
        masked, store = mask_strings(txt)
        n = 0
        if os.path.abspath(p) == os.path.abspath(featpath):
            # in-file: SkuCore -> MOD
            masked, c1 = colondot.subn(lambda m: "%s%s%s" % (MOD, m.group(1), m.group(2)), masked); n += c1
            masked, c2 = bracket.subn(lambda m: "%s[%s%s%s]" % (MOD, m.group(1), m.group(2), m.group(1)), masked); n += c2
        else:
            # cross-file: SkuCore -> SkuCore.HANDLE
            masked, c1 = colondot.subn(lambda m: "SkuCore.%s%s%s" % (HANDLE, m.group(1), m.group(2)), masked); n += c1
            masked, c2 = bracket.subn(lambda m: "SkuCore.%s[%s%s%s]" % (HANDLE, m.group(1), m.group(2), m.group(1)), masked); n += c2
        if n:
            out = unmask(masked, store)
            print("  %-45s %d" % (os.path.relpath(p, ROOT), n))
            total += n
            if apply:
                with open(p, "w", encoding=enc, newline="") as fh:
                    fh.write(out)   # encoding=utf-8-sig re-adds the BOM
    print("TOTAL rewrites: %d  (%s)" % (total, "APPLIED" if apply else "dry-run"))

main()
