# Dump the tail of Sku's general debug ring (SkuDebugLog.lines) from SavedVariables.
#
# Handles BOTH ring formats:
#   format 1 (Sku <= 42.06): one table per entry -> { ["seq"]=, ["t"]=, ["msg"]= },
#   format 2 (current):      one string per entry -> "seq|HH:MM:SS|msg",
# Format 2 exists because a plain string costs ~4-5x less RAM, file size and
# login-time Lua parsing than a 3-field table, which is what let the ring grow
# from 2000 to 12000 lines (see DEBUGLOG_MAX_DEFAULT in Sku/Core.lua).
#
# Usage:  py -3 _dbgtail.py [tail_count] [substring_filter]
#   py -3 _dbgtail.py            -> last 90 entries
#   py -3 _dbgtail.py 400        -> last 400
#   py -3 _dbgtail.py 0 aqCombat -> every entry containing "aqCombat"

import sys

import os
# Default = the TBC-Anniversary client. Set SKU_SV to read another client's store
# (e.g. Era/Hardcore: ..._classic_era_\WTF\...\SavedVariables\Sku.lua).
PATH = os.environ.get("SKU_SV") or r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"

tail = int(sys.argv[1]) if len(sys.argv) > 1 else 90
needle = sys.argv[2] if len(sys.argv) > 2 else None


def unescape(s):
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == '\\' and i + 1 < len(s):
            n = s[i + 1]
            out.append({'n': '\n', 't': '\t', 'r': '\r', '"': '"', '\\': '\\'}.get(n, n))
            i += 2
        else:
            out.append(c)
            i += 1
    return ''.join(out)


lines = open(PATH, encoding='utf-8-sig', errors='replace').read().splitlines()

out = []
in_lines = False
cur = {}
for ln in lines:
    s = ln.strip()
    if not in_lines:
        if s.startswith('["lines"]') and '{' in s:
            in_lines = True
        continue

    # end of the lines table
    if s in ('},', '}'):
        if cur.get('msg') is not None:      # format 1 entry just closed
            out.append(cur)
            cur = {}
        else:
            in_lines = False
        continue

    if s.startswith('"'):                    # format 2: one quoted string per line
        body = s
        if body.endswith(','):
            body = body[:-1]
        cut = body.rfind('", --')            # strip the "-- [n]" index comment
        if cut != -1:
            body = body[:cut + 1]
        elif body.endswith('"'):
            pass
        body = unescape(body.strip().strip('"'))
        seq, _, rest = body.partition('|')
        t, _, msg = rest.partition('|')
        out.append({'seq': seq, 't': t, 'msg': msg})
    elif s.startswith('["seq"]'):            # format 1
        cur['seq'] = s.split('=', 1)[1].strip().rstrip(',')
    elif s.startswith('["t"]'):
        cur['t'] = s.split('=', 1)[1].strip().rstrip(',').strip('"')
    elif s.startswith('["msg"]'):
        v = s.split('=', 1)[1].strip().rstrip(',')
        cur['msg'] = unescape(v[1:-1]) if v.startswith('"') else v

if needle:
    out = [e for e in out if needle in e.get('msg', '')]

print("total lines entries:", len(out))
for e in (out if tail == 0 else out[-tail:]):
    print(f"{e.get('seq','?'):>8} {e.get('t','')}  {e.get('msg','')}")
