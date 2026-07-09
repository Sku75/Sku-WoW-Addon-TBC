import io

path = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
text = io.open(path, encoding="utf-8-sig", errors="replace").read()

# Locate the SkuDebugLog table and capture its block by brace-depth counting.
i = text.find("SkuDebugLog = {")
if i < 0:
    i = text.find('SkuDebugLog = ')
assert i >= 0, "SkuDebugLog not found"
b = text.find("{", i)
depth = 0
end = b
for j in range(b, len(text)):
    c = text[j]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            end = j
            break
block = text[b:end+1]

# Each record serialises seq/t/msg onto their own lines. Walk lines, group into
# records, keep records whose msg matches our markers.
cur = {}
records = []
for raw in block.splitlines():
    s = raw.strip()
    if s.startswith('["seq"]'):
        cur = {}
        cur["seq"] = s.split("=", 1)[1].strip().rstrip(",")
    elif s.startswith('["t"]'):
        cur["t"] = s.split("=", 1)[1].strip().rstrip(",").strip('"')
    elif s.startswith('["msg"]'):
        v = s.split("=", 1)[1].strip().rstrip(",")
        if len(v) >= 2 and v[0] == '"' and v[-1] == '"':
            v = v[1:-1]
        cur["msg"] = v
        records.append(cur)

# Strip WoW colour escapes for readability.
def clean(m):
    return m.replace("|cff80c0ff", "").replace("|r", "")

# A perf dump = a "SkuPerf ...:" header line followed by "  "-indented rows.
# Collect each header plus its contiguous indented rows.
blocks = []
i = 0
n = len(records)
while i < n:
    msg = clean(records[i].get("msg", ""))
    if msg.startswith("SkuPerf"):
        blk = [(records[i].get("t", "?"), msg)]
        j = i + 1
        while j < n:
            m2 = clean(records[j].get("msg", ""))
            if m2.startswith("  "):
                blk.append((records[j].get("t", "?"), m2))
                j += 1
            else:
                break
        blocks.append(blk)
        i = j
    else:
        i += 1

print("total log records:", len(records), "| perf dump blocks:", len(blocks))
for blk in blocks:
    print("=" * 70)
    for t, m in blk:
        print("[%s] %s" % (t, m))

# Since 2026-07-05 the auto-capture at login lives in the eviction-proof
# SkuDebugLog.loadPerf field (an array of plain strings, overwritten each
# load) because ring flooding used to evict the in-ring capture.
lp = block.find('["loadPerf"]')
if lp >= 0:
    lb = block.find("{", lp)
    depth2 = 0
    lend = lb
    for j in range(lb, len(block)):
        c = block[j]
        if c == "{":
            depth2 += 1
        elif c == "}":
            depth2 -= 1
            if depth2 == 0:
                lend = j
                break
    print("=" * 70)
    print("SkuDebugLog.loadPerf (latest load):")
    for raw in block[lb:lend].splitlines():
        s = raw.strip().rstrip(",")
        if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
            print(clean(s[1:-1].replace('\\"', '"')))
else:
    print("(no loadPerf capture yet - needs a Sku session with the 2026-07-05 build)")
