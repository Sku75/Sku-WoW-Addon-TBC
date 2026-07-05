# [DB rework stage 0, tool 4] Read /skudbcheck captures from SavedVariables and
# diff two of them (DB-RESTRUCTURE-PLAN.md section 4).
#
# Usage:
#   py -3 _dbcheck.py              list all captures (index, time, label)
#   py -3 _dbcheck.py A B          diff captures A and B -> PASS/FAIL per dataset
#                                  A/B: 1-based index, negative from the end
#                                  (-1 = newest), or a label text.
#
# Parsing method per project rules: brace-depth block capture + startswith line
# scan, no regex over the SavedVariables body.
import io
import sys

PATH = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
        r"\WTF\Account\1107979492#1\SavedVariables\Sku.lua")


def read_block(lines, start):
    """Return (blocklines, next_index) of the {...} block whose opening line is
    lines[start]. Depth counted per line; quoted-only lines never counted."""
    depth = 0
    out = []
    i = start
    while i < len(lines):
        line = lines[i]
        s = line.strip()
        out.append(line)
        if not s.startswith('"'):
            depth += line.count("{") - line.count("}")
        i += 1
        if depth <= 0 and len(out) > 1:
            break
    return out, i


def load_captures():
    try:
        all_lines = io.open(PATH, encoding="utf-8", errors="replace").read().split("\n")
    except FileNotFoundError:
        print("SavedVariables nicht gefunden:", PATH)
        sys.exit(1)
    # locate the SkuDebugLog block, then its dbCheck subblock
    top = None
    for i, line in enumerate(all_lines):
        if line.strip().startswith("SkuDebugLog = {"):
            top, _ = read_block(all_lines, i)
            break
    if top is None:
        print("Kein SkuDebugLog in der Datei - im Spiel /skudbcheck laufen lassen und /reload.")
        sys.exit(1)
    sub = None
    for i, line in enumerate(top):
        if line.strip().startswith('["dbCheck"] = {'):
            sub, _ = read_block(top, i)
            break
    if sub is None:
        print("Kein dbCheck-Feld - im Spiel /skudbcheck laufen lassen und /reload.")
        sys.exit(1)
    # parse capture entries
    captures = []
    cur = None
    in_lines = False
    for line in sub[1:-1]:
        s = line.strip()
        if in_lines:
            if s.startswith('"'):
                cur["lines"].append(s.rstrip(",").strip('"'))
                continue
            if s.startswith("}"):
                in_lines = False
                continue
        if s.startswith("{"):
            cur = {"t": "", "label": "", "took": "", "lines": []}
            continue
        if cur is None:
            continue
        if s.startswith('["t"]'):
            cur["t"] = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["label"]'):
            cur["label"] = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["took"]'):
            cur["took"] = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["lines"]'):
            in_lines = True
        elif s.startswith("},") or s == "}":
            if cur["lines"] or cur["t"]:
                captures.append(cur)
            cur = None
    return captures


def pick(captures, sel):
    try:
        idx = int(sel)
        if idx < 0:
            idx = len(captures) + idx
        else:
            idx = idx - 1
        return captures[idx], idx + 1
    except (ValueError, IndexError):
        pass
    for i, c in enumerate(captures):
        if c["label"] == sel:
            return c, i + 1
    print("Capture nicht gefunden:", sel)
    sys.exit(1)


def as_map(cap):
    out = {}
    for entry in cap["lines"]:
        parts = entry.split("|")
        if len(parts) >= 3:
            out[parts[0]] = (parts[1], parts[2])  # (count, fingerprint)
    return out


def main():
    captures = load_captures()
    if len(sys.argv) < 3:
        if not captures:
            print("Keine Captures vorhanden.")
            return
        print("Captures (aeltestes zuerst):")
        for i, c in enumerate(captures):
            print("  %d. %s  Label: %s  (%s s, %d Datensaetze)"
                  % (i + 1, c["t"], c["label"] or "-", c["took"], len(c["lines"])))
        print("Diff: py -3 _dbcheck.py <A> <B>   (z.B. -2 -1 fuer die letzten beiden)")
        return
    ca, na = pick(captures, sys.argv[1])
    cb, nb = pick(captures, sys.argv[2])
    print("Vergleich Capture %d (%s, %s) gegen Capture %d (%s, %s)"
          % (na, ca["t"], ca["label"] or "-", nb, cb["t"], cb["label"] or "-"))
    ma, mb = as_map(ca), as_map(cb)
    fails = 0
    for path in sorted(set(ma) | set(mb)):
        a = ma.get(path)
        b = mb.get(path)
        if a is None or b is None:
            print("FAIL  %s  nur in %s vorhanden" % (path, "A" if b is None else "B"))
            fails += 1
        elif a != b:
            print("FAIL  %s  A: count=%s fp=%s  B: count=%s fp=%s"
                  % (path, a[0], a[1], b[0], b[1]))
            fails += 1
    if fails == 0:
        print("PASS - alle %d Datensaetze identisch (Anzahl und Fingerprint)." % len(ma))
    else:
        print("FAIL - %d Datensaetze weichen ab." % fails)
        sys.exit(2)


if __name__ == "__main__":
    main()
