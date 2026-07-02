import io
p=r"C:\Program Files (x86)\World of Warcraft\_anniversary_\WTF\Account\1107979492#1\SavedVariables\WVDebug.lua"
s=io.open(p,encoding='utf-8-sig',errors='replace').read()
# Grab WVDebugData block
start=s.find('WVDebugData = {')
end=s.find('\nWVDebugLog = {')
if end<0: end=len(s)
block=s[start:end]
# find the ["tree"] = { ... } within
ti=block.find('["tree"]')
b=block.find('{', ti)
depth=0;j=b
while j<len(block):
    c=block[j]
    if c=='{':depth+=1
    elif c=='}':
        depth-=1
        if depth==0:break
    j+=1
tree=block[b:j+1]
# Walk char by char, tracking brace depth; print name lines with indent = depth
BS=chr(92)
lines=tree.split(chr(10))
depth=0
for ln in lines:
    stripped=ln.strip()
    # count braces to adjust depth for display
    opens=stripped.count('{')
    closes=stripped.count('}')
    if stripped.startswith('["name"]'):
        val=stripped.split('=',1)[1].strip().strip(',').strip('"')
        # find numChildren/itemType on nearby lines is hard; just print name with current depth
        print('  '*max(0,depth-1)+ '- '+val)
    # adjust depth AFTER printing (name appears inside its own {})
    depth+=opens-closes
