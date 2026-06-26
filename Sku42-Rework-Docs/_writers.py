import os, re, sys, collections

ROOT = r"C:/Users/fabia/Dev/Sku-TBC-42/Sku"
SKIP_DIRS = {"Libs", "SkuDB", "SkuAudioData", "audio", "locales"}

def all_files():
    for dirpath, dirs, fs in os.walk(ROOT):
        dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
        for fn in fs:
            if fn.endswith(".lua"):
                yield os.path.join(dirpath, fn)

def read(p):
    try:
        return open(p, encoding="utf-8-sig").read()
    except Exception:
        return open(p, encoding="latin-1").read()

# field given on cmdline like SkuCore.inCombat
fields = sys.argv[1:]
# assignment: TABLE.FIELD <optional spaces> = <not = ~ < > >
assign_re = {f: re.compile(r"\b" + re.escape(f) + r"\s*=\s*(?![=])") for f in fields}
# also catch compound: SkuCore.inCombat, X = ...  (rare) — ignore for now
ref_re = {f: re.compile(r"\b" + re.escape(f) + r"\b") for f in fields}
# exclude false-positive: == ~= <= >=
not_eq_re = re.compile(r"[=~<>]=\s*$")

rel = lambda p: os.path.relpath(p, ROOT).replace("\\", "/")

for f in fields:
    writers = []      # (relpath, lineno, text)
    reader_files = collections.Counter()
    total_refs = 0
    for p in all_files():
        for i, ln in enumerate(read(p).splitlines(), 1):
            if not ref_re[f].search(ln):
                continue
            total_refs += 1
            # is it a write on this line?
            m = assign_re[f].search(ln)
            is_write = False
            if m:
                # guard against '==' etc: char before '=' must not be = ~ < >
                eqpos = ln.find("=", m.start())
                if eqpos > 0 and ln[eqpos-1] not in "=~<>":
                    # and next char not '='
                    if eqpos+1 >= len(ln) or ln[eqpos+1] != "=":
                        is_write = True
            if is_write:
                writers.append((rel(p), i, ln.strip()))
            else:
                reader_files[rel(p)] += 1
    print("=== %s ===" % f)
    print("  WRITERS (%d):" % len(writers))
    for rp, i, t in writers:
        print("    %s:%d  %s" % (rp, i, t[:110]))
    print("  READERS by file (%d files, %d refs):" % (len(reader_files), sum(reader_files.values())))
    for rp, n in reader_files.most_common():
        print("    %-40s %d" % (rp, n))
    print()
