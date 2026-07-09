import os, re, collections

ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku"

# folder -> owned global table name
OWN = {
    "SkuCore": "SkuCore",
    "SkuChat": "SkuChat",
    "SkuNav": "SkuNav",
    "SkuQuest": "SkuQuest",
    "SkuAuras": "SkuAuras",
    "SkuMob": "SkuMob",
    "SkuDispatcher": "SkuDispatcher",
    "SkuZOptions": "SkuOptions",
}
# globals we count references TO (exclude shared infra SkuOptions/SkuDB)
TARGETS = ["SkuCore", "SkuChat", "SkuNav", "SkuQuest", "SkuAuras", "SkuMob", "SkuDispatcher"]
patterns = {g: re.compile(r"\b" + g + r"\b") for g in TARGETS}

# matrix[caller_folder][target_global] = count
matrix = collections.defaultdict(lambda: collections.Counter())      # total matches
linematrix = collections.defaultdict(lambda: collections.Counter())  # matching lines (grep -c style)

for folder in OWN:
    fdir = os.path.join(ROOT, folder)
    for dirpath, _, files in os.walk(fdir):
        for fn in files:
            if not fn.endswith((".lua",)):
                continue
            p = os.path.join(dirpath, fn)
            try:
                txt = open(p, encoding="utf-8-sig").read()
            except Exception:
                txt = open(p, encoding="latin-1").read()
            own = OWN[folder]
            for g in TARGETS:
                if g == own:
                    continue
                n = len(patterns[g].findall(txt))
                if n:
                    matrix[folder][g] += n
                lines = sum(1 for ln in txt.splitlines() if patterns[g].search(ln))
                if lines:
                    linematrix[folder][g] += lines

# print
order = ["SkuCore", "SkuNav", "SkuQuest", "SkuAuras", "SkuMob", "SkuChat", "SkuDispatcher", "SkuZOptions"]
def show(m, title):
    print("=== %s ===" % title)
    for folder in order:
        if folder not in m:
            continue
        edges = m[folder]
        parts = ["%s %d" % (g, edges[g]) for g in sorted(edges, key=lambda k: -edges[k])]
        print("%-14s -> %s" % (folder, ", ".join(parts)))
show(linematrix, "matching lines (grep -c equivalent; baseline 4.1 used this)")
print()
show(matrix, "total matches (every token occurrence)")
