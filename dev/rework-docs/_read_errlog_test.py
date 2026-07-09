import io, sys

PATH = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"

def read():
    with io.open(PATH, encoding="utf-8-sig", errors="replace") as f:
        return f.read()

def find_block(text, key):
    """Return the substring inside the { } that follows `<key> = {` (brace depth)."""
    i = text.find(key)
    if i < 0:
        return None
    b = text.find("{", i)
    if b < 0:
        return None
    depth = 0
    for j in range(b, len(text)):
        c = text[j]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[b+1:j]
    return None

def split_top_records(block):
    """Yield each top-level { ... } record inside an array-like block."""
    recs = []
    depth = 0
    start = None
    for j, c in enumerate(block):
        if c == "{":
            if depth == 0:
                start = j
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                recs.append(block[start+1:j])
                start = None
    return recs

def field(rec, name):
    key = '["%s"]' % name
    for line in rec.splitlines():
        s = line.strip()
        if s.startswith(key):
            # ["x"] = value,
            val = s.split("=", 1)[1].strip().rstrip(",")
            if val.startswith('"') and val.endswith('"'):
                val = val[1:-1]
            return val
    return None

def main():
    text = read()
    el = find_block(text, "SkuErrorLog = {")
    if el is None:
        el = find_block(text, '["SkuErrorLog"] = {')
    if el is None:
        print("SkuErrorLog table not found in file.")
        return
    recent = find_block(el, '["recent"] = {')
    if recent is None:
        print("No ['recent'] sub-table found.")
        return
    recs = split_top_records(recent)
    parsed = []
    for r in recs:
        parsed.append(dict(
            seq=field(r, "seq"), t=field(r, "t"), src=field(r, "source"),
            msg=field(r, "message"), head=field(r, "stackHead"), sess=field(r, "session")))
    print("=== SkuErrorLog.recent : %d entries total ===" % len(parsed))
    sessions = sorted(set(p["sess"] for p in parsed if p["sess"]), key=lambda s: int(s) if s and s.isdigit() else -1)
    print("sessions present:", ", ".join(sessions))
    days = sorted(set((p["t"] or "")[:10] for p in parsed))
    print("days present:", ", ".join(d for d in days if d))
    print()

    def show(p):
        print("#%s  t=%s  session=%s  source=%s" % (p["seq"], p["t"], p["sess"], p["src"]))
        if p["msg"]:  print("     msg : %s" % p["msg"])
        if p["head"]: print("     head: %s" % p["head"])

    # 1) Everything from today (2026-07-03)
    today = [p for p in parsed if (p["t"] or "").startswith("2026-07-03")]
    print("=== TODAY (2026-07-03): %d entries ===" % len(today))
    for p in today:
        show(p)
    print()

    # 2) Real errors across the whole ring (exclude the combat-lockdown noise)
    NOISE = {"addon_action_blocked", "addon_action_forbidden"}
    reals = [p for p in parsed if (p["src"] or "") not in NOISE]
    print("=== NON-lockdown entries across ring: %d ===" % len(reals))
    for p in reals[-60:]:
        show(p)
    print()

    # 3) Keyword hits
    KW = ("atlas", "questie", "detail", "alintegration", "buildsource", "nil")
    hits = [p for p in parsed if any(k in ((p["msg"] or "")+(p["head"] or "")+(p["src"] or "")).lower() for k in KW)]
    print("=== keyword hits (atlas/questie/details/nil/...): %d ===" % len(hits))
    for p in hits[-60:]:
        show(p)
    # unique summary
    uniq = find_block(el, '["unique"] = {')
    if uniq is not None:
        urecs = split_top_records(uniq)
        print()
        print("=== SkuErrorLog.unique : %d fingerprints ===" % len(urecs))
        for r in urecs:
            cnt = field(r, "count")
            msg = field(r, "message")
            first = field(r, "firstSeen")
            last = field(r, "lastSeen")
            print("count=%s  first=%s  last=%s" % (cnt, first, last))
            if msg: print("     msg : %s" % msg)

main()
