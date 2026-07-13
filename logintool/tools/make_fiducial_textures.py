#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Phase 3 fiducial texture redesign - in-place color surgery on the shipped BLPs.

Two lossless techniques, chosen per file:
- paletted BLP1/BLP2 (colorEncoding 1): rewrite matching palette entries
  (mips share the palette, alpha untouched).
- DXT-compressed BLP2 (colorEncoding 2): rewrite matching RGB565 endpoint
  colors inside each 4x4 block, for every mip level. Flat fiducial regions
  have exact-match endpoints, so this recolors them cleanly; anti-aliased
  edges keep their gradient (toward the new color). For DXT1 the endpoint
  ORDER encodes 4-color vs 3-color+transparent mode, so if a replacement
  inverts the order the endpoints are swapped back and the 2-bit indices
  remapped.

Rules (see dev/rework-docs/LOGINTOOL-REWORK-PLAN.md, Phase 3):
1. RED->DARKRED (140,0,0), all files: red buttons keep a unique fiducial
   color but yellow button text becomes readable (contrast ~2.7:1 -> ~6:1).
2. WHITE->SELBLUE (0,40,120), char-select highlight/atlas files only: the
   selected-character row becomes a dark flat surface (gold text readable);
   the blue is the new selection fiducial.
3. CHARCREATE marker: UI-CharacterCreate-Background.blp -> flat (48,0,96),
   one unique marker color for the character creation screen (replaces the
   drifting-logo scan).

Usage:
  py -3 tools/make_fiducial_textures.py           apply (backs up originals first)
  py -3 tools/make_fiducial_textures.py --dry-run report only
  py -3 tools/make_fiducial_textures.py --restore restore backed-up originals
"""
import struct
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1] / "CopyTheContentOfThisFolderToInterface"
BACKUP = Path(__file__).resolve().parent / "texture_originals"

DARKRED = (140, 0, 0)
SELBLUE = (0, 40, 120)
CC_PURPLE = (48, 0, 96)

WHITE_RULE_FILES = {
    "glues/characterselect/glue-characterselect-highlight.blp",
    "glues/characterselect/uicharacterselectglues.blp",
    "glues/characterselect/uicharacterselectglues2x.blp",
}
CC_MARKER_FILES = {
    "glues/charactercreate/ui-charactercreate-background.blp",
}


def rgb565_decode(v):
    r = (v >> 11) & 0x1F
    g = (v >> 5) & 0x3F
    b = v & 0x1F
    return ((r << 3) | (r >> 2), (g << 2) | (g >> 4), (b << 3) | (b >> 2))


def rgb565_encode(rgb):
    r, g, b = rgb
    return ((r >> 3) << 11) | ((g >> 2) << 5) | (b >> 3)


def match_red(rgb):
    r, g, b = rgb
    return r >= 240 and g <= 16 and b <= 16


def match_white(rgb):
    r, g, b = rgb
    return r >= 240 and g >= 240 and b >= 240


def endpoint_replacement(v, rules):
    """rules = list of (match_fn, new_rgb). Returns new 565 value or None."""
    rgb = rgb565_decode(v)
    for match, new in rules:
        if match(rgb):
            return rgb565_encode(new)
    return None


class Blp:
    def __init__(self, data: bytearray):
        self.data = data
        magic = bytes(data[:4])
        if magic == b"BLP2":
            self.version = 2
            self.color_encoding = data[8]
            self.alpha_depth = data[9]
            self.alpha_type = data[10]
            self.width = struct.unpack_from("<I", data, 12)[0]
            self.height = struct.unpack_from("<I", data, 16)[0]
            self.mip_offsets = struct.unpack_from("<16I", data, 20)
            self.mip_sizes = struct.unpack_from("<16I", data, 84)
            self.palette_off = 148
        elif magic == b"BLP1":
            self.version = 1
            compression = struct.unpack_from("<I", data, 4)[0]
            self.color_encoding = 1 if compression == 1 else 0
            self.alpha_depth = struct.unpack_from("<I", data, 8)[0]
            self.alpha_type = 0
            self.width = struct.unpack_from("<I", data, 12)[0]
            self.height = struct.unpack_from("<I", data, 16)[0]
            self.mip_offsets = struct.unpack_from("<16I", data, 28)
            self.mip_sizes = struct.unpack_from("<16I", data, 92)
            self.palette_off = 156
        else:
            self.version = 0

    @property
    def is_paletted(self):
        return self.version and self.color_encoding == 1

    @property
    def is_dxt(self):
        return self.version == 2 and self.color_encoding == 2

    def dxt_layout(self):
        """(block_size, color_offset_in_block) - DXT1: 8,0; DXT3/5: 16,8."""
        if self.alpha_depth == 0 or (self.alpha_depth == 1 and self.alpha_type == 0):
            return 8, 0
        return 16, 8


def recolor_palette(blp: Blp, rules):
    hits = 0
    for i in range(256):
        p = blp.palette_off + i * 4
        b, g, r = blp.data[p], blp.data[p + 1], blp.data[p + 2]
        for match, new in rules:
            if match((r, g, b)):
                blp.data[p], blp.data[p + 1], blp.data[p + 2] = new[2], new[1], new[0]
                hits += 1
                break
    return hits


def recolor_dxt(blp: Blp, rules):
    block_size, color_off = blp.dxt_layout()
    is_dxt1 = block_size == 8
    hits = 0
    for level in range(16):
        off, size = blp.mip_offsets[level], blp.mip_sizes[level]
        if off == 0 or size == 0:
            continue
        for bpos in range(off, off + size - (block_size - 1), block_size):
            cpos = bpos + color_off
            c0, c1 = struct.unpack_from("<HH", blp.data, cpos)
            n0 = endpoint_replacement(c0, rules)
            n1 = endpoint_replacement(c1, rules)
            if n0 is None and n1 is None:
                continue
            new0 = n0 if n0 is not None else c0
            new1 = n1 if n1 is not None else c1
            if is_dxt1 and ((c0 > c1) != (new0 > new1)):
                # Preserve 4-color vs 3-color mode: swap endpoints and remap
                # the 2-bit indices (0<->1, 2<->3).
                new0, new1 = new1, new0
                idx = struct.unpack_from("<I", blp.data, cpos + 4)[0]
                remapped = 0
                for t in range(16):
                    v = (idx >> (t * 2)) & 3
                    v = {0: 1, 1: 0, 2: 3, 3: 2}[v]
                    remapped |= v << (t * 2)
                struct.pack_into("<I", blp.data, cpos + 4, remapped)
            struct.pack_into("<HH", blp.data, cpos, new0, new1)
            hits += 1
    return hits


def transform(path: Path, rel: str, dry: bool):
    data = bytearray(path.read_bytes())
    blp = Blp(data)
    if blp.version == 0:
        return None

    key = rel.replace("\\", "/").lower()
    rules = [(match_red, DARKRED)]
    if key in WHITE_RULE_FILES:
        rules.append((match_white, SELBLUE))
    if key in CC_MARKER_FILES:
        rules = [(lambda rgb: True, CC_PURPLE)]

    if blp.is_paletted:
        hits = recolor_palette(blp, rules)
        how = "palette"
    elif blp.is_dxt:
        hits = recolor_dxt(blp, rules)
        how = "dxt-endpoints"
    else:
        return f"{rel}: unsupported encoding {blp.color_encoding}, skipped"

    if hits:
        if not dry:
            backup = BACKUP / rel
            if not backup.exists():
                backup.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, backup)
            path.write_bytes(bytes(data))
        return f"{rel}: {how} {hits} entries/blocks recolored{' (dry-run)' if dry else ''}"
    return None


def restore():
    n = 0
    for backup in BACKUP.rglob("*"):
        if backup.is_file():
            shutil.copy2(backup, ROOT / backup.relative_to(BACKUP))
            print(f"restored {backup.relative_to(BACKUP)}")
            n += 1
    print(f"{n} files restored")


def main():
    if "--restore" in sys.argv:
        restore()
        return
    dry = "--dry-run" in sys.argv
    seen = set()
    changed = 0
    for path in sorted(ROOT.rglob("*")):
        if not path.is_file() or path.suffix.lower() != ".blp":
            continue
        key = str(path).lower()
        if key in seen:
            continue
        seen.add(key)
        rel = str(path.relative_to(ROOT))
        msg = transform(path, rel, dry)
        if msg:
            print(msg)
            if "skipped" not in msg:
                changed += 1
    print(f"-- {changed} files changed{' (dry-run)' if dry else ''}")


if __name__ == "__main__":
    main()
