import io

PATH = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\!BugGrabber.lua"
t = io.open(PATH, encoding="utf-8-sig", errors="replace").read()

# current session number
import re
m = re.search(r'\["session"\]\s*=\s*(\d+)', t)
cur = m.group(1) if m else "?"
print("current session:", cur)

def find_key_brace(text, key):
    i = text.find(key)
    if i < 0: return None
    return i

# Locate the top-level ["errors"] = { ... }, string-aware brace match
start = t.find('["errors"]')
b = t.find("{", start)
depth = 0
instr = False
esc = False
end = None
for j in range(b, len(t)):
    c = t[j]
    if instr:
        if esc: esc = False
        elif c == "\\": esc = True
        elif c == '"': instr = False
        continue
    if c == '"': instr = True
    elif c == "{": depth += 1
    elif c == "}":
        depth -= 1
        if depth == 0:
            end = j; break
errors_block = t[b+1:end]

# split top-level records (string-aware)
def split_records(block):
    recs, depth, start, instr, esc = [], 0, None, False, False
    for j, c in enumerate(block):
        if instr:
            if esc: esc = False
            elif c == "\\": esc = True
            elif c == '"': instr = False
            continue
        if c == '"': instr = True
        elif c == "{":
            if depth == 0: start = j
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0 and start is not None:
                recs.append(block[start+1:j]); start = None
    return recs

recs = split_records(errors_block)

def field(rec, name):
    # find ["name"] = at top nesting; value may be a long quoted string
    key = '["%s"]' % name
    i = rec.find(key)
    if i < 0: return None
    eq = rec.find("=", i)
    # skip ws
    k = eq + 1
    while k < len(rec) and rec[k] in " \t": k += 1
    if k < len(rec) and rec[k] == '"':
        # read string
        out = []
        k += 1; esc = False
        while k < len(rec):
            c = rec[k]
            if esc:
                out.append(c); esc = False
            elif c == "\\":
                esc = True
            elif c == '"':
                break
            else:
                out.append(c)
            k += 1
        return "".join(out)
    else:
        # number/other until comma/newline
        e = k
        while e < len(rec) and rec[e] not in ",\n": e += 1
        return rec[k:e].strip()

parsed = []
for r in recs:
    parsed.append(dict(msg=field(r,"message"), time=field(r,"time"),
                       sess=field(r,"session"), cnt=field(r,"counter"),
                       stack=field(r,"stack")))

print("total captured errors:", len(parsed))
# sessions distribution
from collections import Counter
cc = Counter(p["sess"] for p in parsed)
print("errors per session (top):", cc.most_common(8))

def clean(s):
    return (s or "").replace("\\n", " | ")[:400]

print("\n=== errors in CURRENT session %s ===" % cur)
cursess = [p for p in parsed if p["sess"] == cur]
if not cursess:
    print("(none in current session; showing last 12 overall)")
    cursess = parsed[-12:]
for p in cursess:
    print("\n--- counter=%s session=%s time=%s ---" % (p["cnt"], p["sess"], p["time"]))
    print("MSG :", clean(p["msg"]))
    print("STK :", clean(p["stack"]))

print("\n\n=== unique messages (dedup) with count ===")
um = Counter((p["msg"] or "").split("\\n")[0][:160] for p in parsed)
for msg, n in um.most_common(25):
    print("%3d x  %s" % (n, msg))
