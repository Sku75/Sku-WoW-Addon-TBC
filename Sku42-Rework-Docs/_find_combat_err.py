import re, collections
P=r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
txt=open(P,encoding="utf-8-sig",errors="replace").read()

# Pull the SkuErrorLog.unique block and list each entry's message/source/stackHead/count.
def block(name):
    i=txt.find(name+" = {")
    if i<0: return None
    j=txt.find("{",i); depth=0; k=j
    while k<len(txt):
        c=txt[k]
        if c=="{": depth+=1
        elif c=="}":
            depth-=1
            if depth==0: return txt[j:k+1]
        k+=1
    return None

for store in ('["unique"]','["recent"]'):
    b=block(store)
    print("="*70)
    print(store, "present" if b else "MISSING")
    if not b: continue
    # split entries by top-level "{ ... }" inside
    # crude: find each ["message"] / ["source"] / ["stackHead"] / ["stack"] / ["count"]
    # We scan line by line, grouping by record via brace depth.
    lines=b.splitlines()
    rec={}
    depth=0
    seen=set()
    for ln in lines:
        depth+=ln.count("{")-ln.count("}")
        s=ln.strip()
        for key in ("message","source","stackHead","count","lastSeen","firstSeen"):
            tag='["%s"]'%key
            if s.startswith(tag):
                val=s.split("=",1)[1].strip().rstrip(",")
                rec[key]=val
        if s.startswith("},") or s=="}":
            src=rec.get("source","")
            if src and "blocked" not in src and "forbidden" not in src and not src.startswith('"sku:auction') and "dungeonBrowser" not in src:
                k=(rec.get("source"),rec.get("message"))
                if k not in seen:
                    seen.add(k)
                    print("\n  source   :",rec.get("source"))
                    print("  message  :",rec.get("message"))
                    print("  stackHead:",rec.get("stackHead"))
                    print("  count    :",rec.get("count"), " last:",rec.get("lastSeen"))
            rec={}
