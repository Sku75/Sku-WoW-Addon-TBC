import pefile, struct
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

SCR = r"C:\Users\fabia\AppData\Local\Temp\claude\C--Users-fabia-Dev-Sku-TBC-42\9eacac07-c2e6-4b7a-9d6a-828bc10a9fb2\scratchpad"
src = SCR + r"\sapi2sr_engine_x64.orig.dll"
dst = SCR + r"\sapi2sr_engine_x64.patched2.dll"

pe = pefile.PE(src)
base = pe.OPTIONAL_HEADER.ImageBase
data = bytearray(open(src, 'rb').read())
def off(va): return pe.get_offset_from_rva(va - base)

# ---- Patch A: bookmark-skip (same as validated patched.dll) ----
VA_LOOP, VA_SKIP, VA_BACK, VA_CAVE = 0x1800097f5, 0x18000986d, 0x1800097fc, 0x1800168f2
o_loop, o_cave = off(VA_LOOP), off(VA_CAVE)
assert bytes(data[o_loop:o_loop+7]) == bytes.fromhex("4c8b4e504d85c9")
assert all(b == 0 for b in data[o_cave:o_cave+32])
def rel32(t, rip): return struct.pack('<i', t - rip)
data[o_loop:o_loop+7] = b'\xE9' + rel32(VA_CAVE, VA_LOOP+5) + b'\x90\x90'
cave  = bytes.fromhex("837E0803")
cave += b'\x0F\x84' + rel32(VA_SKIP, VA_CAVE+len(cave)+6)
cave += bytes.fromhex("4C8B4E50") + bytes.fromhex("4D85C9")
cave += b'\xE9' + rel32(VA_BACK, VA_CAVE+len(cave)+5)
data[o_cave:o_cave+len(cave)] = cave

# ---- Patch B: route WoW's XML path from speakSsml (slot3, [RAX+0x18]) to
#      speakText (slot2, [RAX+0x10]).  FF 50 18 -> FF 50 10 at 0x180009ba1 ----
VA_SSML = 0x180009ba1
o_ssml = off(VA_SSML)
assert bytes(data[o_ssml:o_ssml+3]) == bytes.fromhex("ff5018"), bytes(data[o_ssml:o_ssml+3]).hex()
data[o_ssml+2] = 0x10   # 0x18 -> 0x10

open(dst, 'wb').write(data)
print("wrote", dst)

md = Cs(CS_ARCH_X86, CS_MODE_64)
print("--- patched loop ---")
for i in md.disasm(bytes(data[o_loop:o_loop+16]), VA_LOOP): print("  %#x %-8s %s"%(i.address,i.mnemonic,i.op_str))
print("--- cave ---")
for i in md.disasm(bytes(data[o_cave:o_cave+len(cave)]), VA_CAVE): print("  %#x %-8s %s"%(i.address,i.mnemonic,i.op_str))
print("--- backend call (was speakSsml, now speakText) ---")
for i in md.disasm(bytes(data[o_ssml:o_ssml+3]), VA_SSML): print("  %#x %-8s %s"%(i.address,i.mnemonic,i.op_str))
