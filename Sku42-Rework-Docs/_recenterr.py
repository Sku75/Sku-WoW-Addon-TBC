path = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
lines = open(path, encoding='utf-8-sig', errors='replace').read().splitlines()

# Find ["recent"] = { and dump the LAST N record blocks (message/t/source/stackHead).
start = None
for i, ln in enumerate(lines):
    if ln.strip().startswith('["recent"]') and '{' in ln:
        start = i; break
recs, cur = [], {}
if start is not None:
    depth = 0
    for ln in lines[start:]:
        s = ln.strip()
        depth += s.count('{') - s.count('}')
        if s.startswith('["message"]'): cur['message'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
        elif s.startswith('["t"]'):       cur['t'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
        elif s.startswith('["source"]'):  cur['source'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
        elif s.startswith('["stackHead"]'): cur['stackHead'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
        if s == '},':
            if cur: recs.append(cur); cur = {}
        if depth <= 0 and cur == {} and recs:
            break

for r in recs[-25:]:
    print(f"{r.get('t','')}  [{r.get('source','')}]  {r.get('message','')}")
    if r.get('stackHead'): print(f"      {r['stackHead']}")
print("total recent parsed:", len(recs))
