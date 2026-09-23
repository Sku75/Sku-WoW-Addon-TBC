"""Patch D (EXPERIMENT) for sapi2sr_engine.dll (x64): report failure to SAPI.

Input : the shipped Patch A+B+C engine (signed or unsigned).
Output: the same engine plus Patch D, signature stripped (the signing step
        re-signs it on the machine).

Why: the 12.0 client caches rendered TTS audio by text and replays it without
calling the voice again. The bridge renders no audio, so every text it has
forwarded once is silent on repeat. Sku busts the cache from Lua by varying
the text; the glue-screen narration (WoW Forever) is Blizzard's text and out
of reach. Hypothesis: the client does not cache an utterance whose engine
call FAILED. The bridge forwards the text to NVDA first and only then returns,
so a failure code costs nothing but the cache entry.

ISpTTSEngine::Speak has one normal exit (0x180009d65: xor eax,eax = S_OK)
before the security-cookie check and the epilogue. Patch D replaces that
`xor eax,eax` + the following `mov rcx,[rbp+0x180]` (9 bytes) with a jump
to a cave that loads the chosen HRESULT into eax, redoes the mov and jumps
back. __security_check_cookie only uses rcx, so eax survives to the ret.

Usage: py -3 patch_sapi2sr_x64_nocache.py <in.dll> <out.dll> [hresult]
       hresult defaults to 0x80004005 (E_FAIL); 1 = S_FALSE for variant B.
"""
import sys, struct, pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

src, dst = sys.argv[1], sys.argv[2]
hres = int(sys.argv[3], 0) if len(sys.argv) > 3 else 0x80004005

pe = pefile.PE(src)
base = pe.OPTIONAL_HEADER.ImageBase
def off(va): return pe.get_offset_from_rva(va - base)
def rel32(target, next_ip): return struct.pack('<i', target - next_ip)

data = bytearray(open(src, 'rb').read())
sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_SECURITY']]
if sec.Size:
    assert sec.VirtualAddress + sec.Size == len(data), "signature is not the file tail"
    del data[sec.VirtualAddress:]
    o_dir = sec.get_file_offset()
    data[o_dir:o_dir + 8] = b"\0" * 8

VA_EXIT = 0x180009d65     # xor eax,eax ; mov rcx,[rbp+0x180]
VA_BACK = 0x180009d6e     # xor rcx,rsp ; call __security_check_cookie ...
VA_CAVE = 0x180016970     # .text zero padding after Patch C's cave

# Patches A and C must be present (this builds on the shipped engine)
assert data[off(0x1800097f5)] == 0xE9, "Patch A missing"
assert data[off(0x1800097b7)] == 0xE9, "Patch C missing"
o_exit = off(VA_EXIT)
orig = bytes(data[o_exit:o_exit + 9])
assert orig == bytes.fromhex("33c0488b8d80010000"), orig.hex()

c = bytearray()
c += b"\xB8" + struct.pack('<I', hres & 0xffffffff)   # mov eax, hresult
c += bytes.fromhex("488b8d80010000")                  # mov rcx, [rbp+0x180]
c += b"\xE9" + rel32(VA_BACK, VA_CAVE + len(c) + 5)   # jmp back

o_cave = off(VA_CAVE)
assert all(b == 0 for b in data[o_cave:o_cave + len(c) + 8]), "cave not free"
text = pe.sections[0]
assert VA_CAVE + len(c) <= base + text.VirtualAddress + text.SizeOfRawData
data[o_cave:o_cave + len(c)] = c
data[o_exit:o_exit + 9] = b"\xE9" + rel32(VA_CAVE, VA_EXIT + 5) + b"\x90" * 4

out = pefile.PE(data=bytes(data))
out.OPTIONAL_HEADER.CheckSum = out.generate_checksum()
open(dst, 'wb').write(out.write())
print("wrote", dst, "hresult", hex(hres))

md = Cs(CS_ARCH_X86, CS_MODE_64)
print("--- exit ---")
for i in md.disasm(bytes(data[o_exit:o_exit + 9]), VA_EXIT): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
print("--- cave ---")
for i in md.disasm(bytes(c), VA_CAVE): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
