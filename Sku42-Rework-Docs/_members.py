import os, re, collections, sys

ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku"

def files(folder):
    fdir = os.path.join(ROOT, folder)
    for dirpath, _, fs in os.walk(fdir):
        for fn in fs:
            if fn.endswith(".lua"):
                yield os.path.join(dirpath, fn)

def read(p):
    try:
        return open(p, encoding="utf-8-sig").read()
    except Exception:
        return open(p, encoding="latin-1").read()

# enumerate member accesses target.X  / target:X from a caller folder
def members(caller_folder, target):
    pat = re.compile(r"\b" + target + r"\s*([.:])\s*([A-Za-z_]\w*)")
    counts = collections.Counter()         # "method"/"field" name -> count
    kind = {}                              # name -> set of accessor symbols (: or .)
    per_file = collections.defaultdict(collections.Counter)
    for p in files(caller_folder):
        txt = read(p)
        for ln in txt.splitlines():
            for m in pat.finditer(ln):
                acc, name = m.group(1), m.group(2)
                counts[name] += 1
                kind.setdefault(name, set()).add(acc)
                per_file[os.path.basename(p)][name] += 1
    return counts, kind, per_file

caller, target = sys.argv[1], sys.argv[2]
counts, kind, per_file = members(caller, target)
print("%s -> %s : %d distinct members, %d total qualified accesses" %
      (caller, target, len(counts), sum(counts.values())))
for name, n in counts.most_common():
    accs = "".join(sorted(kind[name]))
    print("  %-32s %3d  (%s)" % (name, n, accs))
print("--- per file ---")
for fn, c in sorted(per_file.items()):
    print("  %-28s %s" % (fn, dict(c)))
