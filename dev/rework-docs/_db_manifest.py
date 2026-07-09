"""
[DB rework stage 0, tool 2] MANIFEST-DB: pin SHA-256 of every pristine SkuDB
data file AND every generated output, plus a one-time cross-check of the
pristine bytes against the upstream-src git blobs. The data files are
gitignored (Sku/.gitignore), so git alone can neither detect nor revert
damage to them - this manifest is the answer (DB-RESTRUCTURE-PLAN.md,
section 4 tool 2, risk A13).

Usage (from the repo root):
  py -3 Sku42-Rework-Docs/_db_manifest.py --write [--no-upstream]
      hash everything, cross-check upstream, (re)write MANIFEST-DB.txt.
      Run after every converter run so the G lines track the real output.
  py -3 Sku42-Rework-Docs/_db_manifest.py --check
      re-hash the tree and compare against MANIFEST-DB.txt. Cheap - run it
      before/after any data work, or whenever paranoia strikes.

Manifest line format (LF, committed to git):
  P <sha256> <size> <path>   pristine bytes (.bak if present, else the file)
  G <sha256> <size> <path>   generated output currently on disk (only listed
                             when a .bak exists, i.e. the file is converted)
  U <path> MATCH|MISMATCH|ABSENT   pristine vs upstream-src blob
"""
import hashlib
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKU = os.path.join(ROOT, "Sku")
MANIFEST = os.path.join(ROOT, "Sku42-Rework-Docs", "MANIFEST-DB.txt")

# the maintainer's source repo (remote upstream-src), v41.06 import commit -
# the second independent pristine copy besides our .bak files
UPSTREAM_COMMIT = "22e81c0"

# every SkuDB-block data file the TOC loads, plus the root route file and
# SkuDB/Core.lua (paths Sku-relative, posix style so they double as git paths)
FILES = ["routedata_global_wotlk.lua", "SkuDB/Core.lua"] + [
    "SkuDB/assets/" + f for f in [
        "maps.lua", "default_waypoints.lua",
        "quests.lua", "quests_fixes.lua",
        "creatures.lua", "creatures_fixes.lua",
        "items.lua", "items_fixes.lua",
        "objects.lua", "objects_fixes.lua",
        "spells.lua", "polygons.lua",
        "routedata_global.lua", "tasks.lua",
    ]
] + [
    "SkuDB/assets/WotLK/" + f for f in [
        "quests.lua", "quests_fixes.lua",
        "creatures.lua", "creatures_fixes.lua",
        "items.lua", "items_fixes.lua",
        "objects.lua", "objects_fixes.lua",
        "enchantIDs.lua",
    ]
] + [
    "SkuDB/assets/SoD/" + f for f in [
        "quests.lua", "quests_fixes.lua",
        "creatures.lua", "creatures_fixes.lua",
        "items.lua", "items_fixes.lua",
        "objects.lua", "objects_fixes.lua",
        "spells.lua",
    ]
]


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest(), os.path.getsize(path)


def pristine_source(rel):
    """(path_to_hash, kind): .bak pins the pristine bytes once a converter has
    touched the file; otherwise the file itself IS pristine."""
    path = os.path.join(SKU, rel.replace("/", os.sep))
    if os.path.exists(path + ".bak"):
        return path + ".bak", "bak"
    return path, "file"


def upstream_compare(rel, local_path):
    """MATCH, MATCH-EOL (identical after CRLF->LF, e.g. tracked files that our
    .gitattributes normalized), MISMATCH, or ABSENT."""
    spec = "%s:Sku/%s" % (UPSTREAM_COMMIT, rel)
    try:
        out = subprocess.run(["git", "-C", ROOT, "cat-file", "blob", spec],
                             capture_output=True)
    except OSError as e:
        return "ABSENT (%s)" % e
    if out.returncode != 0:
        return "ABSENT (%s)" % out.stderr.decode("utf-8", "replace").strip()
    with open(local_path, "rb") as f:
        local = f.read()
    if out.stdout == local:
        return "MATCH"
    if out.stdout.replace(b"\r\n", b"\n") == local.replace(b"\r\n", b"\n"):
        return "MATCH-EOL"
    return "MISMATCH"


def gather(with_upstream):
    p_lines, g_lines, u_lines, problems = [], [], [], []
    for rel in FILES:
        path = os.path.join(SKU, rel.replace("/", os.sep))
        if not os.path.exists(path):
            problems.append("MISSING on disk: %s" % rel)
            continue
        src, kind = pristine_source(rel)
        p_hash, p_size = sha256_file(src)
        p_lines.append("P %s %d %s" % (p_hash, p_size, rel))
        if kind == "bak":
            g_hash, g_size = sha256_file(path)
            if g_hash != p_hash:
                g_lines.append("G %s %d %s" % (g_hash, g_size, rel))
            else:
                g_lines.append("G pristine-on-disk 0 %s" % rel)
        if with_upstream:
            u_lines.append("U %s %s" % (rel, upstream_compare(rel, src)))
    return p_lines, g_lines, u_lines, problems


def write(with_upstream):
    p_lines, g_lines, u_lines, problems = gather(with_upstream)
    for x in problems:
        print(" ", x)
    if problems:
        print("REFUSING to write manifest with missing files.")
        sys.exit(2)
    with open(MANIFEST, "w", newline="\n") as f:
        f.write("# MANIFEST-DB - SkuDB data-file hashes (gitignored files!)\n")
        f.write("# written by _db_manifest.py --write; check with --check\n")
        f.write("# upstream cross-check against %s (remote upstream-src)\n" % UPSTREAM_COMMIT)
        for line in p_lines + g_lines + u_lines:
            f.write(line + "\n")
    mism = [l for l in u_lines if "MISMATCH" in l or "ABSENT" in l]
    print("wrote %s: %d pristine, %d generated, %d upstream checks (%d not matching)"
          % (os.path.relpath(MANIFEST, ROOT), len(p_lines), len(g_lines),
             len(u_lines), len(mism)))
    for l in mism:
        print("  NOTE", l)


def check():
    try:
        recorded = open(MANIFEST, encoding="utf-8").read().splitlines()
    except FileNotFoundError:
        print("no MANIFEST-DB.txt yet - run --write first")
        sys.exit(2)
    rec_p = {}
    rec_g = {}
    for line in recorded:
        parts = line.split()
        if len(parts) == 4 and parts[0] == "P":
            rec_p[parts[3]] = (parts[1], parts[2])
        elif len(parts) == 4 and parts[0] == "G":
            rec_g[parts[3]] = (parts[1], parts[2])
    p_lines, g_lines, _, problems = gather(False)
    drift = list(problems)
    seen_p = set()
    for line in p_lines:
        _, h, size, rel = line.split()
        seen_p.add(rel)
        if rel not in rec_p:
            drift.append("pristine NOT IN MANIFEST: %s" % rel)
        elif rec_p[rel] != (h, size):
            drift.append("pristine DRIFT: %s" % rel)
    for rel in rec_p:
        if rel not in seen_p:
            drift.append("pristine RECORDED BUT MISSING: %s" % rel)
    for line in g_lines:
        parts = line.split()
        rel = parts[3]
        if rel not in rec_g:
            drift.append("generated NOT IN MANIFEST (run --write after converting): %s" % rel)
        elif rec_g[rel][0] != parts[1]:
            if parts[1] == "pristine-on-disk" or rec_g[rel][0] == "pristine-on-disk":
                drift.append("generated state differs from manifest (converted vs unwrapped): %s" % rel)
            else:
                drift.append("generated DRIFT: %s" % rel)
    for rel in rec_g:
        if not os.path.exists(os.path.join(SKU, rel.replace("/", os.sep)) + ".bak"):
            drift.append("generated RECORDED but no .bak on disk: %s" % rel)
    if drift:
        for d in drift:
            print("  FAIL", d)
        print("FAIL - %d deviation(s)." % len(drift))
        sys.exit(2)
    print("PASS - %d pristine and %d generated entries match the manifest."
          % (len(p_lines), len(g_lines)))


def main():
    args = set(sys.argv[1:])
    if "--check" in args:
        check()
    elif "--write" in args:
        write("--no-upstream" not in args)
    else:
        print(__doc__)


if __name__ == "__main__":
    main()
