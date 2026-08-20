"""
[Workstream 3] Wrap a large SkuDB data file as deferred BUILDER functions.

The route data files are huge Lua data that, as plain top-level statements,
construct their tables the instant the file loads (the expensive, RAM-heavy
part of login). This rewrites each file so loading it only DEFINES builders;
the tables are built later, on demand, when Sku:EnsureData(...) calls them.

Modes (per target):
  "func"     - wrap the body in `function Name() <body> end`. Defers table
               CONSTRUCTION, but the body literal is still PARSED at load.
  "lstr"     - wrap as `function Name() loadstring([==[ <body> ]==])() end`.
               Defers BOTH parse and construction.
  "sections" - ONE BUILDER PER TOP-LEVEL SECTION of routedata.global
               (WaypointsNew / Waypoints / SequenceNumbers / WaypointLevels /
               Links). Same deferral as "lstr", but the flavour can now build
               only the sections it actually reads: on TBC the WotLK waypoint
               half is built and then nil'ed unread by LoadDefaultMapData
               (~265 ms), on Era the whole WotLK file is unused (~375 ms).
               See ROUTE-LINK-BUILD-PLAN.md section 13. The data is NEVER
               re-serialised: each blob is a byte-exact slice of the original
               and the tool asserts the slices concatenate back to it.

The pristine body is kept in a one-time .bak and is the source of truth, so
re-running (even with a changed mode) always regenerates from the original.
--rebak refreshes that .bak from the CURRENT file, which is needed after a
route-data re-import overwrites an already-wrapped file: the .bak then still
holds the OLD dataset (exactly what happened on 2026-08-13 - the .bak was from
2026-06-28 and predated both the +2099 waypoints and the French names).
Operates on raw bytes to preserve the UTF-8 BOM and original line endings.

Run from the repo root:  py -3 dev/rework-docs/_wrap_deferred.py
Refresh the .bak first:  py -3 dev/rework-docs/_wrap_deferred.py --rebak
Revert all:              py -3 dev/rework-docs/_wrap_deferred.py --unwrap
"""
import os, re, sys

# (relative-to-Sku path, builder base name, mode, root table name)
TARGETS = [
    ("routedata_global_wotlk.lua", "SkuDBBuildRouteWotlk", "sections", "SkuDBTMP"),
    (os.path.join("SkuDB", "assets", "routedata_global.lua"), "SkuDBBuildRouteGlobal", "sections", "SkuDB"),
]

# .../<repo>/dev/rework-docs/_wrap_deferred.py -> <repo>
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SKU = os.path.join(ROOT, "Sku")
BOM = b"\xef\xbb\xbf"

HEADER = b"""-- GENERATED WRAPPER - do not hand-edit the scaffolding.
-- dev/rework-docs/_wrap_deferred.py, mode "sections": one builder per top-level
-- section of routedata.global, so a flavour builds only the sections it reads
-- (ROUTE-LINK-BUILD-PLAN.md section 13). The data blobs are byte-exact slices
-- of the source file; the per-flavour selection lives in SkuDeferredData.lua.
"""


# --------------------------------------------------------------------------- io
def read(path):
    with open(path, "rb") as f:
        raw = f.read()
    if raw.startswith(BOM):
        return BOM, raw[len(BOM):]
    return b"", raw


def pristine_body(path):
    """(bom, body) from the .bak (source of truth), created from the current file
    on first run."""
    if not os.path.exists(path + ".bak"):
        with open(path, "rb") as f:
            cur = f.read()
        with open(path + ".bak", "wb") as f:
            f.write(cur)
    return read(path + ".bak")


# ----------------------------------------------------------------- lua scanning
def scan_to_close(body, start):
    """Byte scanner over Lua data starting just INSIDE a '{' (depth 1): tracks
    brace depth, skips quoted strings and line comments. Returns the index just
    past the '}' that brings the depth back to 0."""
    i, n, depth = start, len(body), 1
    while i < n:
        c = body[i:i + 1]
        if c == b'"':
            i += 1
            while i < n:
                d = body[i:i + 1]
                if d == b"\\":
                    i += 2
                    continue
                i += 1
                if d == b'"':
                    break
            continue
        if c == b"-" and body[i + 1:i + 2] == b"-":
            j = body.find(b"\n", i)
            i = n if j < 0 else j + 1
            continue
        if c == b"{":
            depth += 1
        elif c == b"}":
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise RuntimeError("unbalanced braces")


def split_body(body):
    """(prefix, inner, suffix) around the routedata.global table constructor.
    Works on the pristine body and on the older single-builder wrapped forms,
    because all of them still carry the `<root>.routedata["global"] = ... {`
    assignment; `inner` excludes the outer braces."""
    m = re.search(rb'\.routedata\["global"\]\s*=\s*[^\n{]*\{', body)
    if not m:
        raise RuntimeError('no routedata["global"] assignment found')
    j = m.end()
    k = scan_to_close(body, j)
    return body[:j], body[j:k - 1], body[k - 1:]


def split_sections(inner):
    """[(name, blob)] for every top-level `["Name"] = { ... },` in the
    constructor. Each blob runs from its own key to the next key, so the blobs
    concatenate back to `inner` byte for byte (asserted by the caller)."""
    marks, i, n, depth = [], 0, len(inner), 0
    while i < n:
        c = inner[i:i + 1]
        if c == b'"':
            i += 1
            while i < n:
                d = inner[i:i + 1]
                if d == b"\\":
                    i += 2
                    continue
                i += 1
                if d == b'"':
                    break
            continue
        if c == b"-" and inner[i + 1:i + 2] == b"-":
            j = inner.find(b"\n", i)
            i = n if j < 0 else j + 1
            continue
        if depth == 0 and c == b"[":
            m = re.match(rb'\["([A-Za-z][A-Za-z0-9_]*)"\]\s*=\s*\{', inner[i:i + 64])
            if m:
                # cut at the START of the key's line, so every blob ends on a
                # newline (the next section's indentation must not trail it)
                cut = i
                while cut > 0 and inner[cut - 1:cut] in (b" ", b"\t"):
                    cut -= 1
                marks.append((cut, m.group(1).decode("ascii")))
                i += m.end()
                depth = 1
                continue
        if c == b"{":
            depth += 1
        elif c == b"}":
            depth -= 1
        i += 1
    if not marks:
        raise RuntimeError("no top-level sections found")
    if inner[:marks[0][0]].strip():
        raise RuntimeError("non-whitespace before the first section")
    out = []
    for x, (pos, name) in enumerate(marks):
        start = 0 if x == 0 else pos          # the leading gap rides on slice 1
        end = marks[x + 1][0] if x + 1 < len(marks) else len(inner)
        out.append((name, inner[start:end]))
    return out


def pick_level(blob):
    """Smallest long-bracket level n>=1 whose close token ]=*] is absent."""
    n = 1
    while ("]" + "=" * n + "]").encode("ascii") in blob:
        n += 1
    return n


# ------------------------------------------------------------------- generators
def prologue(root, version):
    """Every section builder is self-sufficient: it creates the containers if it
    is the first one to run, and leaves them alone if it is not. That is what
    makes the per-flavour selection free to run any subset in any order."""
    lines = [
        "%s = %s or {}" % (root, root),
        "%s.SessionRouteData = %s.SessionRouteData or {}" % (root, root),
        "%s.routedata = %s.routedata or {}" % (root, root),
    ]
    if version is not None:
        lines.append("%s.routedata.version = %s" % (root, version))
    lines.append('%s.routedata["global"] = %s.routedata["global"] or {}' % (root, root))
    return ("\n".join(lines) + "\n").encode("ascii")


def wrap_sections(path, base, root):
    bom, body = pristine_body(path)
    prefix, inner, _suffix = split_body(body)
    mv = re.search(rb"\.routedata\.version\s*=\s*([0-9.]+)", prefix)
    version = mv.group(1).decode("ascii") if mv else None
    parts = split_sections(inner)
    if b"".join(b for _, b in parts) != inner:
        raise RuntimeError("slices do not reassemble into the original body")

    pro = prologue(root, version)
    out = [bom, HEADER]
    names = []
    for name, blob in parts:
        fn = base + name
        names.append(fn)
        lvl = pick_level(blob)
        op = ("[" + "=" * lvl + "[").encode("ascii")
        cl = ("]" + "=" * lvl + "]").encode("ascii")
        key = ('["%s"]' % name).encode("ascii")
        out.append(b"function " + fn.encode("ascii") + b"()\n")
        out.append(pro)
        out.append(root.encode("ascii") + b'.routedata["global"]' + key
                   + b" = loadstring(" + op + b"return {\n")
        out.append(blob)
        out.append(b"}" + cl + b")()" + key + b"\nend\n")
    with open(path, "wb") as f:
        f.write(b"".join(out))
    print("  wrapped (sections) %s" % path)
    for name, blob in parts:
        print("     %-16s %9.2f MB  -> %s%s()" % (name, len(blob) / 1048576.0, base, name))
    verify_sections(path, inner)


def verify_sections(path, inner):
    """Re-read the generated file: the blobs must still concatenate to `inner`,
    and the scaffolding (everything outside the blobs) must be valid Lua."""
    bom, body = read(path)
    blobs, skel, i = [], [], 0
    for m in re.finditer(rb"loadstring\((\[=*\[)return \{\n", body):
        op = m.group(1)
        cl = b"]" + b"=" * (len(op) - 2) + b"]"
        end = body.index(b"\n}" + cl, m.end())
        blobs.append(body[m.end():end + 1])
        skel.append(body[i:m.start()] + b'loadstring("return {}")')
        i = end + 2 + len(cl) + 1   # past the '}', the close bracket and the ')'
    skel.append(body[i:])
    if b"".join(blobs) != inner:
        raise RuntimeError("generated blobs no longer reassemble")
    src = b"".join(skel).decode("utf-8")
    try:
        from luaparser import ast
        ast.parse(src)
        print("     %d blobs, byte-exact; scaffolding parses as Lua" % len(blobs))
    except ImportError:
        print("     %d blobs, byte-exact (luaparser absent, scaffolding unchecked)" % len(blobs))


def wrap(path, builder, mode, root):
    if mode == "sections":
        return wrap_sections(path, builder, root)
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


def rebak(path):
    """Rewrite the .bak from the CURRENT file, unwrapped back to a pristine body.
    Needed when a route-data re-import overwrote an already-wrapped file: the old
    .bak then holds the previous dataset. The old .bak is kept as .bak.old."""
    bom, body = read(path)
    if body.startswith(b"-- GENERATED WRAPPER"):
        # already split into per-section builders: there is no single
        # constructor left to recover, and the prologue's `= <root> or {}` line
        # would parse as an empty one. Revert with --unwrap first.
        raise RuntimeError("%s is already section-wrapped; --unwrap it first" % path)
    prefix, inner, _suffix = split_body(body)
    m = re.search(rb"^(SkuDB[A-Za-z]*)\.", prefix, re.M)
    if not m:
        raise RuntimeError("cannot find the root assignment in %s" % path)
    root = m.group(1)
    # keep the whole statement block from the first line that touches the root
    # table (`SkuDBTMP = {}` included - without it the restored body would
    # index a nil global), and undo the loadstring form of the assignment.
    hm = re.search(rb"^" + re.escape(root) + rb"\b", prefix, re.M)
    head = prefix[hm.start():]
    head = re.sub(rb"=\s*loadstring\(\[=*\[return \{$", b"= {", head.rstrip(b"\n"))
    out = bom + head + inner + b"}\n"
    if os.path.exists(path + ".bak"):
        if os.path.exists(path + ".bak.old"):
            os.remove(path + ".bak.old")
        os.rename(path + ".bak", path + ".bak.old")
    with open(path + ".bak", "wb") as f:
        f.write(out)
    print("  .bak refreshed from the current file (%.1f MB): %s" % (len(out) / 1048576.0, path))


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
    for rel, builder, mode, root in TARGETS:
        path = os.path.join(SKU, rel)
        if not os.path.exists(path):
            print("  MISSING: %s" % path)
            continue
        if "--unwrap" in sys.argv:
            unwrap(path)
        elif "--rebak" in sys.argv:
            rebak(path)
        else:
            wrap(path, builder, mode, root)


if __name__ == "__main__":
    main()
