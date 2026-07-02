import io
p=r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\Sku.lua"
s=io.open(p,encoding='utf-8-sig',errors='replace').read()
i=s.find('["recent"]')
print("recent at",i)
if i<0:
    raise SystemExit
b=s.find('{', i)
depth=0;j=b
while j<len(s):
    c=s[j]
    if c=='{':depth+=1
    elif c=='}':
        depth-=1
        if depth==0:break
    j+=1
block=s[b:j+1]
recs=[];depth=0;start=None
for k,c in enumerate(block):
    if c=='{':
        depth+=1
        if depth==2:start=k
    elif c=='}':
        if depth==2 and start is not None:
            recs.append(block[start:k+1]);start=None
        depth-=1
BS=chr(92)
def field(r,name):
    key='["%s"]'%name
    idx=r.find(key)
    if idx<0:return ''
    eq=r.find('=',idx);rest=r[eq+1:].lstrip()
    if rest.startswith('"'):
        out=[];k=1
        while k<len(rest):
            ch=rest[k]
            if ch==BS and k+1<len(rest):
                out.append(rest[k+1]);k+=2;continue
            if ch=='"':break
            out.append(ch);k+=1
        return ''.join(out)
    out=[]
    for ch in rest:
        if ch in ','+chr(10)+'}':break
        out.append(ch)
    return ''.join(out).strip()
for r in recs[-40:]:
    t=field(r,'t');src=field(r,'source');msg=field(r,'message')
    print(t,'|',src,'|',msg[:110])
