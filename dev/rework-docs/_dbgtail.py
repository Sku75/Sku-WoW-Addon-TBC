path = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
lines = open(path, encoding='utf-8-sig', errors='replace').read().splitlines()

# Find SkuDebugLog = { ... } and its ["lines"] = { ... } sub-table; dump last N entries.
# Entries look like: { ["seq"]=..., ["t"]="HH:MM:SS", ["msg"]="..." },
out = []
in_lines = False
depth = 0
cur = {}
start = None
for i, ln in enumerate(lines):
    s = ln.strip()
    if s.startswith('["lines"]') and '{' in s:
        in_lines = True
        continue
    if in_lines:
        if s.startswith('["seq"]'):
            cur['seq'] = s.split('=',1)[1].strip().rstrip(',')
        elif s.startswith('["t"]'):
            v = s.split('=',1)[1].strip().rstrip(',')
            cur['t'] = v.strip('"')
        elif s.startswith('["msg"]'):
            v = s.split('=',1)[1].strip().rstrip(',')
            cur['msg'] = v[1:-1] if v.startswith('"') else v
        elif s == '},':
            if cur.get('msg') is not None:
                out.append(cur); cur = {}
        elif s.startswith('}') and not s.startswith('},'):
            # end of lines table (heuristic): stop when we dedent out
            in_lines = False

print("total lines entries:", len(out))
for e in out[-90:]:
    print(f"{e.get('seq','?'):>7} {e.get('t','')}  {e.get('msg','')}")
