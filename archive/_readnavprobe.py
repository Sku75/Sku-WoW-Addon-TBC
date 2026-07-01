import io, sys

PATH = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"

with io.open(PATH, "r", encoding="utf-8-sig", errors="replace") as f:
    lines = f.readlines()

# find the combatTrace = { line
start = None
for i, ln in enumerate(lines):
    if "combatTrace" in ln and "{" in ln:
        start = i
        break

if start is None:
    print("no combatTrace table found")
    sys.exit(0)

# brace-depth capture of the combatTrace block
depth = 0
block = []
started = False
for ln in lines[start:]:
    for ch in ln:
        if ch == "{":
            depth += 1
            started = True
        elif ch == "}":
            depth -= 1
    block.append(ln)
    if started and depth <= 0:
        break

# each entry is a { ... } table; parse fields by simple scanning
entries = []
cur = {}
d2 = 0
for ln in block:
    s = ln.strip()
    if s.startswith("{"):
        cur = {}
        d2 = 1
        # a one-liner entry?
    if d2:
        for key in ("t", "tag", "detail", "combat"):
            marker = '["%s"]' % key
            if marker in s:
                # value after '='
                val = s.split("=", 1)[1].strip().rstrip(",")
                val = val.strip().strip('"')
                cur[key] = val
    if s.startswith("}") or s.endswith("},"):
        if cur:
            entries.append(cur)
            cur = {}

print("total combatTrace entries: %d" % len(entries))
print("=" * 60)
# print navProbe + capture + PLAYER_REGEN lines in order
for e in entries:
    tag = e.get("tag", "")
    if tag in ("navProbe", "capture", "secureKeys") or "REGEN" in tag or "SESSION" in tag or "PLAYER" in tag:
        print("%s  combat=%s  [%s]  %s" % (e.get("t",""), e.get("combat",""), tag, e.get("detail","")))
