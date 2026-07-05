# [DB rework stage 0, tool 5] Read the /skudbmem capture from SavedVariables
# and rank the subtrees by estimated size (DB-RESTRUCTURE-PLAN.md section 4).
# The estimate is a RANKING proxy (crude Lua 5.1 cost model), not exact bytes.
#
# Usage: py -3 _dbmem.py [N]    (N = only the top N subtrees, default all)
import io
import sys

PATH = (r"C:\Program Files (x86)\World of Warcraft\_anniversary_"
        r"\WTF\Account\1107979492#1\SavedVariables\Sku.lua")


def read_block(lines, start):
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


def main():
    try:
        all_lines = io.open(PATH, encoding="utf-8", errors="replace").read().split("\n")
    except FileNotFoundError:
        print("SavedVariables nicht gefunden:", PATH)
        sys.exit(1)
    top = None
    for i, line in enumerate(all_lines):
        if line.strip().startswith("SkuDebugLog = {"):
            top, _ = read_block(all_lines, i)
            break
    if top is None:
        print("Kein SkuDebugLog - im Spiel /skudbmem laufen lassen und /reload.")
        sys.exit(1)
    sub = None
    for i, line in enumerate(top):
        if line.strip().startswith('["dbMem"] = {'):
            sub, _ = read_block(top, i)
            break
    if sub is None:
        print("Kein dbMem-Feld - im Spiel /skudbmem laufen lassen und /reload.")
        sys.exit(1)
    t = total = took = ""
    entries = []
    in_lines = False
    for line in sub:
        s = line.strip()
        if in_lines:
            if s.startswith('"'):
                entries.append(s.rstrip(",").strip('"'))
                continue
            if s.startswith("}"):
                in_lines = False
            continue
        if s.startswith('["t"]'):
            t = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["totalMB"]'):
            total = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["took"]'):
            took = s.split("=", 1)[1].strip().rstrip(",").strip('"')
        elif s.startswith('["lines"]'):
            in_lines = True
    rows = []
    for e in entries:
        p = e.split("|")
        if len(p) == 7:
            # target|tables|strings|stringBytes|numbers|booleans|estKB
            rows.append((int(p[6]), p[0], int(p[1]), int(p[2]), int(p[3]), int(p[4])))
    rows.sort(reverse=True)
    n = int(sys.argv[1]) if len(sys.argv) > 1 else len(rows)
    print("Capture vom %s, Lua-Heap gesamt %s MB, Messdauer %s s" % (t, total, took))
    print("Hinweis: Aliasse (SessionRouteData, WaypointCache) zaehlen ihren")
    print("erreichbaren Baum jeweils voll - Summen ueberlappen absichtlich.")
    for est_kb, name, tables, strings, sbytes, numbers in rows[:n]:
        print("%8.1f MB  %s  (Tabellen %d, Strings %d mit %.1f MB Text, Zahlen %d)"
              % (est_kb / 1024.0, name, tables, strings, sbytes / 1e6, numbers))


if __name__ == "__main__":
    main()
