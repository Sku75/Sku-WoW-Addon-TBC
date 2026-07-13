#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Inventory the login tool's replacement BLP textures.

For every BLP under CopyTheContentOfThisFolderToInterface/ print size, mode,
number of distinct opaque colors and the top colors by share, so the mapping
texture -> fiducial color (data.ini gGameUiColors) is explicit before the
Phase 3 redesign touches anything.

Usage: py -3 tools/analyze_textures.py [--all] [substring-filter]
       (without --all only textures with <= 8 distinct colors are listed,
        i.e. the flat fiducial candidates)
"""
import sys
from pathlib import Path
from collections import Counter
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / "CopyTheContentOfThisFolderToInterface"


def analyze(path: Path):
    im = Image.open(path)
    rgba = im.convert("RGBA")
    px = list(rgba.getdata())
    opaque = [(r, g, b) for (r, g, b, a) in px if a >= 128]
    counter = Counter(opaque)
    total = len(px)
    return {
        "size": im.size,
        "mode": im.mode,
        "opaque_share": len(opaque) / total if total else 0,
        "distinct": len(counter),
        "top": counter.most_common(4),
        "opaque_total": len(opaque),
    }


def main():
    show_all = "--all" in sys.argv
    filters = [a for a in sys.argv[1:] if not a.startswith("--")]
    for path in sorted(ROOT.rglob("*.blp")) + sorted(ROOT.rglob("*.BLP")):
        rel = path.relative_to(ROOT)
        if filters and not any(f.lower() in str(rel).lower() for f in filters):
            continue
        try:
            info = analyze(path)
        except Exception as e:  # noqa: BLE001
            print(f"{rel}: ERROR {e}")
            continue
        if not show_all and info["distinct"] > 8:
            continue
        tops = ", ".join(
            f"{c} x{n} ({100.0 * n / max(1, info['opaque_total']):.0f}%)"
            for c, n in info["top"]
        )
        print(
            f"{rel}: {info['size'][0]}x{info['size'][1]} {info['mode']} "
            f"opaque={info['opaque_share']:.0%} distinct={info['distinct']} | {tops}"
        )


if __name__ == "__main__":
    main()
