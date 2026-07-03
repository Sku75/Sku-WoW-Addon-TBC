import io

PATH = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"

def read():
    with io.open(PATH, encoding="utf-8-sig", errors="replace") as f:
        return f.read()

def find_block(text, key):
    i = text.find(key)
    if i < 0: return None
    b = text.find("{", i)
    if b < 0: return None
    depth = 0
    for j in range(b, len(text)):
        c = text[j]
        if c == "{": depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0: return text[b+1:j]
    return None

def split_top_records(block):
    recs, depth, start = [], 0, None
    for j, c in enumerate(block):
        if c == "{":
            if depth == 0: start = j
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                recs.append(block[start+1:j]); start = None
    return recs

def field(rec, name):
    key = '["%s"]' % name
    for line in rec.splitlines():
        s = line.strip()
        if s.startswith(key):
            val = s.split("=", 1)[1].strip().rstrip(",")
            if val.startswith('"') and val.endswith('"'): val = val[1:-1]
            return val
    return None

text = read()
dl = find_block(text, "SkuDebugLog = {")
if dl is None:
    print("SkuDebugLog not found."); raise SystemExit
lines = find_block(dl, '["lines"] = {')
if lines is None:
    print("SkuDebugLog.lines not found."); raise SystemExit
recs = split_top_records(lines)
parsed = [dict(seq=field(r,"seq"), t=field(r,"t"), msg=field(r,"msg")) for r in recs]
print("=== SkuDebugLog.lines : %d entries ===" % len(parsed))
if parsed:
    print("first t=%s   last t=%s" % (parsed[0]["t"], parsed[-1]["t"]))

# markers: "=== log enabled ..."
print("\n--- last 8 'log enabled' markers ---")
marks = [p for p in parsed if p["msg"] and "log enabled" in p["msg"]]
for p in marks[-8:]:
    print("seq=%s t=%s  %s" % (p["seq"], p["t"], p["msg"]))

# last 40 lines overall (the tail = current run)
print("\n--- last 40 lines (tail) ---")
for p in parsed[-40:]:
    print("[%s] %s" % (p["t"], p["msg"]))

# keyword hits
KW = ("atlas", "questie", "detail", "nil", "error", "missing", "forbidden")
print("\n--- keyword hits (atlas/questie/detail/nil/error/missing/forbidden) ---")
hits = [p for p in parsed if p["msg"] and any(k in p["msg"].lower() for k in KW)]
for p in hits[-60:]:
    print("[%s] %s" % (p["t"], p["msg"]))
