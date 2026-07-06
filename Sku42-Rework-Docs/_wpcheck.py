# [DB rework lever A] Read the /skudbwpcheck capture from SavedVariables and
# print the waypoint-cache record validation result (WAYPOINT-CACHE-ANALYSIS.md).
#
# Usage: py -3 _wpcheck.py
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


def scalar(s):
    v = s.split("=", 1)[1].strip().rstrip(",")
    return v.strip('"')


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
        print("Kein SkuDebugLog - im Spiel /skudbwpcheck laufen lassen und /reload.")
        sys.exit(1)
    sub = None
    for i, line in enumerate(top):
        if line.strip().startswith('["wpCheck"] = {'):
            sub, _ = read_block(top, i)
            break
    if sub is None:
        print("Kein wpCheck-Feld - im Spiel /skudbwpcheck laufen lassen und /reload.")
        sys.exit(1)

    fields = {}
    by_type = {}
    examples = []
    i = 0
    while i < len(sub):
        s = sub[i].strip()
        if s.startswith('["byType"] = {'):
            block, j = read_block(sub, i)
            for b in block[1:-1]:
                bs = b.strip()
                if bs.startswith("["):
                    k = bs.split("]", 1)[0].lstrip("[")
                    by_type[k] = bs.split("=", 1)[1].strip().rstrip(",")
            i = j
            continue
        if s.startswith('["examples"] = {'):
            block, j = read_block(sub, i)
            for b in block[1:-1]:
                bs = b.strip()
                if bs.startswith('"'):
                    examples.append(bs.rstrip(",").strip('"'))
            i = j
            continue
        for key in ("t", "took", "total", "errors", "sessionRecords",
                    "commentsNil", "shadowed", "dupNames", "wpCacheReady"):
            if s.startswith('["%s"]' % key):
                fields[key] = scalar(s)
        i += 1

    names = {"1": "custom", "2": "creature", "3": "object", "4": "standard"}
    print("Wegpunkt-Cache-Pruefung vom %s (Dauer %s s, cacheReady=%s)"
          % (fields.get("t", "?"), fields.get("took", "?"), fields.get("wpCacheReady", "?")))
    print("Wegpunkte gesamt: %s" % fields.get("total", "?"))
    for k in sorted(by_type):
        print("  Typ %s (%s): %s" % (k, names.get(k, "?"), by_type[k]))
    print("Sitzungs-Records (ohne wpId, alles gespeichert): %s" % fields.get("sessionRecords", "?"))
    print("Custom ohne Kommentare (jetzt nil statt Leertabelle): %s" % fields.get("commentsNil", "?"))
    print("Records mit gespeicherten Overrides (createdBy/size/contintentId): %s" % fields.get("shadowed", "?"))
    print("Namensdubletten (Datenbestand, kein Fehler - z.B. Trigger-NPCs): %s" % fields.get("dupNames", "?"))
    err = fields.get("errors", "?")
    print("FEHLER: %s" % err)
    if examples:
        print("Beispiele (max 20):")
        for e in examples:
            print("  " + e)
    if err == "0":
        print("ERGEBNIS: PASS")
    else:
        print("ERGEBNIS: FAIL (oder unbekannt)")


if __name__ == "__main__":
    main()
