path = r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
lines = open(path, encoding='utf-8-sig', errors='replace').read().splitlines()

# Dump SkuDebugLog.combatTrace (tag/detail/combat/t) and blockProbe tail.
def dump(section):
    out, cur, inside, depth = [], {}, False, 0
    for ln in lines:
        s = ln.strip()
        if s.startswith('["%s"]' % section) and '{' in s:
            inside = True; depth = 1; continue
        if inside:
            depth += s.count('{') - s.count('}')
            if s.startswith('["t"]'):    cur['t'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            elif s.startswith('["tag"]'): cur['tag'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            elif s.startswith('["detail"]'): cur['detail'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            elif s.startswith('["combat"]'): cur['combat'] = s.split('=',1)[1].strip().rstrip(',')
            elif s.startswith('["ev"]'):  cur['ev'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            elif s.startswith('["func"]'):cur['func'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            elif s.startswith('["addon"]'):cur['addon'] = s.split('=',1)[1].strip().rstrip(',').strip('"')
            if s == '},' and cur:
                out.append(cur); cur = {}
            if depth <= 0:
                inside = False
    return out

ct = dump('combatTrace')
print("=== combatTrace (%d) ===" % len(ct))
for e in ct[-80:]:
    print(f"{e.get('t','')}  c={e.get('combat','?')}  {e.get('tag','')}  {e.get('detail','')}")

bp = dump('blockProbe')
print("\n=== blockProbe tail (%d) ===" % len(bp))
for e in bp[-40:]:
    print(f"{e.get('t','')}  c={e.get('combat','?')}  {e.get('ev','')}  {e.get('addon','')}  {e.get('func','')}")
