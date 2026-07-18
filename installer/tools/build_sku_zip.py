#!/usr/bin/env python3
"""Build Sku-<version>.zip for a GitHub release.

Two coupled steps that both need BOM-safe handling, so they live together:

  1. Bump Sku/Sku.toc's "## Title:" and "## Version:" lines to <version>,
     IN PLACE (the file keeps its UTF-8 BOM and LF line endings). The bump is
     left on disk (not restored) so git tracks the released version — the repo's
     TOC and the newest release stay in step.
  2. Zip the Sku/ folder as top-level "Sku/..." entries, minus the handful of
     VCS/editor/backup files that must never ship (proven by diffing a shipped
     release zip against disk: those are the only on-disk extras).

The gitignored binary assets (mp3/ogg/routedata/SkuDB tables) live on disk and
ARE included — the release zip is the full ~150 MB addon, unlike git.

Usage:
  py -3 build_sku_zip.py --version 42.07 --sku-dir <repo>/Sku --out <path>/Sku-42.07.zip
"""
import argparse
import os
import zipfile

# The only on-disk files under Sku/ that must NOT go into the release zip.
EXCLUDE_EXACT = {".gitignore", ".gitattributes", "Sku.code-workspace"}
EXCLUDE_SUFFIX = (".bak",)


def bump_toc(toc_path, version):
    """Rewrite the Title/Version lines to <version>, preserving BOM + LF."""
    with open(toc_path, encoding="utf-8-sig") as f:
        text = f.read()
    out = []
    for line in text.split("\n"):
        if line.startswith("## Title:"):
            out.append("## Title: Sku v" + version)
        elif line.startswith("## Version:"):
            out.append("## Version: " + version)
        else:
            out.append(line)
    # utf-8-sig writes the BOM back; newline="" + explicit "\n" keeps LF.
    with open(toc_path, "w", encoding="utf-8-sig", newline="") as f:
        f.write("\n".join(out))


def build_zip(sku_dir, out_zip, arc_prefix="Sku"):
    count = 0
    with zipfile.ZipFile(out_zip, "w", zipfile.ZIP_DEFLATED) as z:
        for root, _dirs, files in os.walk(sku_dir):
            for name in files:
                if name in EXCLUDE_EXACT or name.endswith(EXCLUDE_SUFFIX):
                    continue
                full = os.path.join(root, name)
                rel = os.path.relpath(full, sku_dir).replace(os.sep, "/")
                z.write(full, arc_prefix + "/" + rel)
                count += 1
    return count


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--sku-dir", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--no-bump", action="store_true",
                    help="skip the TOC bump (zip the folder exactly as-is)")
    a = ap.parse_args()

    toc = os.path.join(a.sku_dir, "Sku.toc")
    if not os.path.isdir(a.sku_dir):
        raise SystemExit("sku-dir not found: " + a.sku_dir)
    if not a.no_bump:
        if not os.path.isfile(toc):
            raise SystemExit("Sku.toc not found: " + toc)
        bump_toc(toc, a.version)

    out_dir = os.path.dirname(a.out)
    if out_dir and not os.path.isdir(out_dir):
        os.makedirs(out_dir)
    if os.path.exists(a.out):
        os.remove(a.out)

    n = build_zip(a.sku_dir, a.out)
    print("OK version=%s files=%d out=%s" % (a.version, n, a.out))


if __name__ == "__main__":
    main()
