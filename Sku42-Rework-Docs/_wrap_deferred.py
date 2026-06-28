"""
[Workstream 3] Wrap a large SkuDB data file as a deferred BUILDER function.

The route data files are huge Lua table literals that, as plain top-level
statements, construct their tables the instant the file loads (the expensive,
RAM-heavy part of login). This rewrites a file from:

    <statements>

into:

    function <BuilderName>()
    <statements>
    end

so loading the file only PARSES it (defines the builder); the tables are built
later, on demand, when Sku:EnsureData(...) calls the builder. Operates on raw
bytes to preserve the UTF-8 BOM and the original line endings. Idempotent: skips
a file that already starts with the builder header. Keeps a one-time .bak.

Run from the repo root:  py -3 Sku42-Rework-Docs/_wrap_deferred.py
"""
import os, sys

# (relative-to-Sku path, builder global name)
TARGETS = [
    ("routedata_global_wotlk.lua", "SkuDBBuildRouteWotlk"),
    (os.path.join("SkuDB", "assets", "routedata_global.lua"), "SkuDBBuildRouteGlobal"),
]

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKU = os.path.join(ROOT, "Sku")
BOM = b"\xef\xbb\xbf"


def wrap(path, builder):
    with open(path, "rb") as f:
        raw = f.read()
    bom = b""
    if raw.startswith(BOM):
        bom, raw = BOM, raw[len(BOM):]
    header = ("function %s()\n" % builder).encode("ascii")
    if raw.lstrip().startswith(header.strip()):
        print("  already wrapped, skipping: %s" % path)
        return
    if not os.path.exists(path + ".bak"):
        with open(path + ".bak", "wb") as f:
            f.write(bom + raw)
    wrapped = bom + header + raw + b"\nend\n"
    with open(path, "wb") as f:
        f.write(wrapped)
    print("  wrapped as %s(): %s" % (builder, path))


def unwrap(path):
    """Restore from the .bak if present (revert helper: pass --unwrap)."""
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
    for rel, builder in TARGETS:
        path = os.path.join(SKU, rel)
        if not os.path.exists(path):
            print("  MISSING: %s" % path)
            continue
        if revert:
            unwrap(path)
        else:
            wrap(path, builder)


if __name__ == "__main__":
    main()
