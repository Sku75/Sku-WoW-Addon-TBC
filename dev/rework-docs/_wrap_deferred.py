"""
[Workstream 3] Wrap a large SkuDB data file as a deferred BUILDER function.

The route data files are huge Lua data that, as plain top-level statements,
construct their tables the instant the file loads (the expensive, RAM-heavy
part of login). This rewrites each file so loading it only DEFINES a builder;
the tables are built later, on demand, when Sku:EnsureData(...) calls it.

Two modes (per target):
  "func" - wrap the body in `function Name() <body> end`. Defers table
           CONSTRUCTION, but the body literal is still PARSED at load. Best when
           the body is already a loadstring blob (cheap parse), e.g. the wotlk
           route file.
  "lstr" - wrap as `function Name() loadstring([==[ <body> ]==])() end`. Defers
           BOTH parse and construction (only a long-string literal is lexed at
           load). Best for a plain table literal, e.g. the global route file.

The pristine body is kept in a one-time .bak and is the source of truth, so
re-running (even with a changed mode) always regenerates from the original.
Operates on raw bytes to preserve the UTF-8 BOM and original line endings.

Run from the repo root:  py -3 Sku42-Rework-Docs/_wrap_deferred.py
Revert all:              py -3 Sku42-Rework-Docs/_wrap_deferred.py --unwrap
"""
import os, sys

# (relative-to-Sku path, builder global name, mode)
TARGETS = [
    ("routedata_global_wotlk.lua", "SkuDBBuildRouteWotlk", "func"),
    (os.path.join("SkuDB", "assets", "routedata_global.lua"), "SkuDBBuildRouteGlobal", "lstr"),
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKU = os.path.join(ROOT, "Sku")
BOM = b"\xef\xbb\xbf"


def pristine_body(path):
    """Return (bom, body) from the .bak (source of truth), creating it from the
    current file on first run."""
    if not os.path.exists(path + ".bak"):
        with open(path, "rb") as f:
            cur = f.read()
        with open(path + ".bak", "wb") as f:
            f.write(cur)
    with open(path + ".bak", "rb") as f:
        raw = f.read()
    if raw.startswith(BOM):
        return BOM, raw[len(BOM):]
    return b"", raw


def pick_level(body):
    """Smallest long-bracket level n>=1 whose close token ]=*] is absent in body."""
    n = 1
    while ("]" + "=" * n + "]").encode("ascii") in body:
        n += 1
    return n


def wrap(path, builder, mode):
    bom, body = pristine_body(path)
    if mode == "func":
        out = bom + ("function %s()\n" % builder).encode("ascii") + body + b"\nend\n"
    elif mode == "lstr":
        n = pick_level(body)
        op = ("[" + "=" * n + "[").encode("ascii")
        cl = ("]" + "=" * n + "]").encode("ascii")
        out = (bom + ("function %s()\nloadstring(" % builder).encode("ascii")
               + op + b"\n" + body + b"\n" + cl + b")()\nend\n")
        print("  loadstring level =%d" % n)
    else:
        print("  unknown mode %r, skipping" % mode)
        return
    with open(path, "wb") as f:
        f.write(out)
    print("  wrapped (%s) as %s(): %s" % (mode, builder, path))


def unwrap(path):
    if os.path.exists(path + ".bak"):
        with open(path + ".bak", "rb") as f:
            raw = f.read()
        with open(path, "wb") as f:
            f.write(raw)
        os.remove(path + ".bak")
        print("  reverted from .bak: %s" % path)
    else:
        print("  no .bak, cannot revert: %s" % path)


def main():
    revert = "--unwrap" in sys.argv
    for rel, builder, mode in TARGETS:
        path = os.path.join(SKU, rel)
        if not os.path.exists(path):
            print("  MISSING: %s" % path)
            continue
        unwrap(path) if revert else wrap(path, builder, mode)


if __name__ == "__main__":
    main()
