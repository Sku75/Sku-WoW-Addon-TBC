"""Patch E for sapi2sr_engine.dll (x64): silent parts stay silent.

Input : the shipped Patch A+B+C engine (the installed one, signed or not).
Output: the same engine plus Patch E, with the Authenticode signature
        stripped (the installer's signing step re-signs it on the machine).

Why: SAPI parses the utterance's markup before the engine sees it and hands
the engine a list of fragments, each with its own SPVSTATE (volume, rate,
pitch as plain numbers). A real voice plays a fragment at <volume level="0">
as silence. The stock engine glues EVERY fragment's text together for the
screen reader, so text meant to be silent is read aloud: WowVision's group
health monitor gates its parts by volume, and NVDA read "1 1 1 full" where a
real voice says "1 full".

Patch E skips every fragment whose SPVSTATE.Volume is 0, in the same place
Patch A skips bookmark fragments. SPVTEXTFRAG layout (sapiddk.h, x64):
pNext +0x00, State +0x08 (eAction +0x08, LangID +0x0C, EmphAdj +0x10,
RateAdj +0x14, Volume +0x18, PitchAdj.MiddleAdj +0x1C, RangeAdj +0x20, ...),
pTextStart +0x50, ulTextLen +0x58. Patch A already reads +0x08 and +0x50,
Patch C +0x58, so the layout is confirmed by working code.

How: the loop's entry jump at 0x1800097f5 (Patch A's, to its cave at
0x1800168f2) is pointed at a new cave that does Patch A's bookmark test, then
the volume test, then Patch A's clobbered instructions, and jumps back. Patch
A's old cave stays in the file, unused. If every fragment is skipped, the
text stays empty and the engine's own check at 0x18000994d (length 0 -> skip)
sends nothing to the screen reader. Patch C (the skuint interrupt) walks the
fragment list on its own before this loop and is not changed: an utterance
carrying skuint still cancels the screen reader even if all of it is silent.

Usage: py patch_sapi2sr_x64_volume.py <engine in> <engine out>
"""
import sys, struct, pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

src, dst = sys.argv[1], sys.argv[2]
pe = pefile.PE(src)
base = pe.OPTIONAL_HEADER.ImageBase
text = pe.sections[0]
# Raw offsets: the caves lie past .text's VirtualSize (inside its raw size,
# mapped with the last page), where pefile's rva lookup does not reach.
def off(va): return text.PointerToRawData + (va - base - text.VirtualAddress)
def rel32(target, next_ip): return struct.pack('<i', target - next_ip)

# strip the signature first (it lives at the end of the file)
sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_SECURITY']]
data = bytearray(open(src, 'rb').read())
if sec.Size:
    assert sec.VirtualAddress + sec.Size == len(data), "signature is not the file tail"
    del data[sec.VirtualAddress:]
    o_dir = sec.get_file_offset()
    data[o_dir:o_dir+8] = b"\0" * 8          # IMAGE_DATA_DIRECTORY {VirtualAddress, Size}

VA_LOOP   = 0x1800097f5   # Patch A: jmp 0x1800168f2 ; nop ; nop
VA_BACK   = 0x1800097fc   # je 0x18000986d (on test r9,r9)
VA_SKIP   = 0x18000986d   # next fragment
VA_A_CAVE = 0x1800168f2
VA_C_CAVE = 0x180016910
VA_CAVE   = 0x180016970   # .text zero padding after Patch C's cave (ends 0x18001695d)

o_loop = off(VA_LOOP)
assert bytes(data[o_loop:o_loop+7]) == b'\xE9' + rel32(VA_A_CAVE, VA_LOOP+5) + b'\x90\x90', \
    "Patch A missing, or Patch E already applied: " + bytes(data[o_loop:o_loop+7]).hex()
assert data[off(0x1800097b7)] == 0xE9 and bytes(data[off(0x1800097b8):off(0x1800097bc)]) == rel32(VA_C_CAVE, 0x1800097b7+5), \
    "Patch C missing"

c = bytearray()
def here(): return VA_CAVE + len(c)
c += bytes.fromhex("837E0803")                       # cmp dword [rsi+8], 3     (SPVA_Bookmark, Patch A)
c += b"\x0F\x84"; c += rel32(VA_SKIP, here() + 4)    # je skip
c += bytes.fromhex("837E1800")                       # cmp dword [rsi+0x18], 0  (Volume)
c += b"\x0F\x84"; c += rel32(VA_SKIP, here() + 4)    # je skip
c += bytes.fromhex("4C8B4E50")                       # mov r9, [rsi+0x50]       (pTextStart)
c += bytes.fromhex("4D85C9")                         # test r9, r9
c += b"\xE9"; c += rel32(VA_BACK, here() + 4)        # jmp back (its je reads these flags)

o_cave = off(VA_CAVE)
assert VA_CAVE + len(c) <= base + text.VirtualAddress + text.SizeOfRawData, "cave past .text"
assert all(b == 0 for b in data[o_cave:o_cave+len(c)+8]), "cave not free"
data[o_cave:o_cave+len(c)] = c
data[o_loop:o_loop+5] = b"\xE9" + rel32(VA_CAVE, VA_LOOP + 5)

# refresh the PE checksum
out = pefile.PE(data=bytes(data))
out.OPTIONAL_HEADER.CheckSum = out.generate_checksum()
open(dst, 'wb').write(out.write())
print("wrote", dst, "cave bytes", len(c))

md = Cs(CS_ARCH_X86, CS_MODE_64)
print("--- entry ---")
for i in md.disasm(bytes(data[o_loop:o_loop+7]), VA_LOOP): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
print("--- cave ---")
for i in md.disasm(bytes(c), VA_CAVE): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
