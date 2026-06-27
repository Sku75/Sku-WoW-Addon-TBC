import sys

P = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"

try:
    txt = open(P, encoding="utf-8-sig", errors="replace").read()
except Exception as e:
    print("CANNOT READ:", e); sys.exit(1)

def block(name):
    i = txt.find(name + " = {")
    if i < 0:
        return None
    j = txt.find("{", i)
    depth = 0
    k = j
    while k < len(txt):
        c = txt[k]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return txt[j:k+1]
        k += 1
    return None

def field(line, key):
    # line like:  ["message"] = "....",
    s = line.strip()
    tag = '["%s"]' % key
    if not s.startswith(tag):
        return None
    rhs = s.split("=", 1)[1].strip()
    if rhs.endswith(","):
        rhs = rhs[:-1].strip()
    if len(rhs) >= 2 and rhs[0] == '"' and rhs[-1] == '"':
        rhs = rhs[1:-1]
    return rhs

el = block("SkuErrorLog")
if not el:
    print("No SkuErrorLog table found (no errors captured this session, or file absent).")
    sys.exit(0)

# Walk the 'recent' sub-block by brace depth
ri = el.find('["recent"]')
if ri < 0:
    print("SkuErrorLog present but no 'recent' subtable.")
    sys.exit(0)

j = el.find("{", ri)
depth = 0
k = j
end = len(el)
while k < len(el):
    c = el[k]
    if c == "{":
        depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            end = k+1
            break
    k += 1
recent = el[j:end]

entries = []
cur = {}
for line in recent.splitlines():
    for key in ("seq", "t", "source", "message", "stackHead", "session"):
        v = field(line, key)
        if v is not None:
            cur[key] = v
    if line.strip() == "},":
        if cur:
            entries.append(cur); cur = {}
if cur:
    entries.append(cur)

print("SkuErrorLog.recent entries:", len(entries))
for e in entries[-50:]:
    print("  [%s seq=%s src=%s] %s" % (
        e.get("t","?"), e.get("seq","?"), e.get("source","?"),
        (e.get("message","") or "")[:200]))
