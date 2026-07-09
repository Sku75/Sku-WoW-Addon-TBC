import io, sys

path = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
lines = open(path, encoding='utf-8-sig', errors='replace').read().splitlines()

# Walk the file, track the most recent scalar fields per record block.
# A record is a { ... } table; we collect message/source/t/stackHead/stack/count/firstSeen/lastSeen
# lines as we see them, and emit when we hit a record whose date field mentions today.

TODAY = "2026-07-01"

def field(s):
    # ["key"] = "value",  -> (key, value)
    s = s.strip()
    if not s.startswith('['): return None
    try:
        k = s.split(']',1)[0]
        k = k[2:-1]  # strip [" and "]
        rest = s.split('=',1)[1].strip().rstrip(',')
        if rest.startswith('"'):
            rest = rest[1:]
            if rest.endswith('"'): rest = rest[:-1]
        return (k, rest)
    except Exception:
        return None

# Simpler: group into records by blank-brace boundaries is unreliable; instead scan for
# 'message' lines and gather the small window of fields that belong to the same record.
records = []
cur = {}
for i, ln in enumerate(lines):
    f = field(ln)
    if f:
        k, v = f
        if k in ('message','source','t','stackHead','stack','count','firstSeen','lastSeen','lastSource'):
            if k == 'message' and cur.get('message'):
                records.append(cur); cur = {}
            cur[k] = v
    if ln.strip() == '},' and cur.get('message'):
        records.append(cur); cur = {}
if cur.get('message'): records.append(cur)

seen = set()
for r in records:
    stamp = r.get('t','') or r.get('lastSeen','')
    if TODAY not in stamp: continue
    msg = r.get('message','')
    head = r.get('stackHead','') or (r.get('stack','').split('\\n')[0] if r.get('stack') else '')
    key = (msg, head)
    if key in seen: continue
    seen.add(key)
    print("TIME :", stamp)
    print("MSG  :", msg)
    print("HEAD :", head)
    st = r.get('stack','')
    if st:
        for part in st.split('\\n')[:6]:
            if part.strip(): print("   >", part)
    print()
print("total unique today:", len(seen))
