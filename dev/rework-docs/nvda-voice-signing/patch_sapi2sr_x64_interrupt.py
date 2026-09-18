"""Patch C for sapi2sr_engine.dll (x64): an in-band interrupt marker.

Input : the shipped Patch A+B engine (Authenticode PE hash A7F300BA...).
Output: the same engine plus Patch C, with the Authenticode signature
        stripped (the installer's signing step re-signs it on the machine).

Why: WoW's C_VoiceChat.StopSpeakingText only stops the client's own playback,
and SAPI never forwards "purge before speak" to an engine, so nothing on the
bridge path ever cancels NVDA. The only thing that reaches the engine is the
utterance itself -- markup included. Sku therefore puts the interrupt INTO the
utterance: `<bookmark mark="skuint"/>`. That is Prism's speak(text, interrupt)
done in one call: cancel the screen reader, then forward the text.

The engine already contains the cancel call: Speak() at 0x1800097b7 does
`test r13b,2 / je 0x1800097cf` (r13 = dwSpeakFlags, 2 = SPF_PURGEBEFORESPEAK)
and 0x1800097bd calls the back end's cancel (vtable slot 4 ->
nvdaController_cancelSpeech). SAPI never sets that flag for an engine, so the
branch is dead in practice. Patch C redirects the test into a cave that walks
the fragment list (rsi = pTextFragList) and takes the existing cancel branch if
a SPVA_Bookmark fragment named "skuint" is present. The original flag test is
kept as the fall-through. Patch A skips the bookmark later, so it is never
spoken. rax/rcx/rdx are clobbered, which is safe: the cancel path merges at
0x1800097cf after a call, so the compiler cannot rely on volatiles there.
"""
import sys, struct, pefile
from capstone import Cs, CS_ARCH_X86, CS_MODE_64

src, dst = sys.argv[1], sys.argv[2]
pe = pefile.PE(src)
base = pe.OPTIONAL_HEADER.ImageBase
def off(va): return pe.get_offset_from_rva(va - base)
def rel32(target, next_ip): return struct.pack('<i', target - next_ip)

# strip the signature first (it lives at the end of the file)
sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_SECURITY']]
data = bytearray(open(src, 'rb').read())
if sec.Size:
    assert sec.VirtualAddress + sec.Size == len(data), "signature is not the file tail"
    del data[sec.VirtualAddress:]
    o_dir = sec.get_file_offset()
    data[o_dir:o_dir+8] = b"\0" * 8          # IMAGE_DATA_DIRECTORY {VirtualAddress, Size}

VA_TEST   = 0x1800097b7   # test r13b,2 ; je 0x1800097cf
VA_CANCEL = 0x1800097bd   # mov rcx,[r15+0xd0] ... call [rax+0x20]
VA_MERGE  = 0x1800097cf
VA_CAVE   = 0x180016910   # .text zero padding after Patch A's cave (ends 0x180016908)

# Patch A must already be present (this builds on the shipped engine)
assert bytes(data[off(0x1800097f5):off(0x1800097f5)+5])[0] == 0xE9, "Patch A missing"
o_test = off(VA_TEST)
assert bytes(data[o_test:o_test+6]) == bytes.fromhex("41f6c5027412"), bytes(data[o_test:o_test+6]).hex()

NAME = "skuint".encode('utf-16le')          # 12 bytes
name_q = NAME[:8]; name_d = NAME[8:]

c = bytearray()
def here(): return VA_CAVE + len(c)
c += bytes.fromhex("4889F0")                 # mov rax, rsi
L_loop = len(c)
c += bytes.fromhex("4885C0")                 # test rax, rax
j_nomark = len(c); c += b"\x74\x00"          # jz nomark
c += bytes.fromhex("83780803")               # cmp dword [rax+8], 3   (SPVA_Bookmark)
j_n1 = len(c); c += b"\x75\x00"              # jne next
c += bytes.fromhex("83785806")               # cmp dword [rax+0x58], 6 (ulTextLen)
j_n2 = len(c); c += b"\x75\x00"              # jne next
c += bytes.fromhex("488B4850")               # mov rcx, [rax+0x50]    (pTextStart)
c += bytes.fromhex("4885C9")                 # test rcx, rcx
j_n3 = len(c); c += b"\x74\x00"              # jz next
c += b"\x48\xBA" + name_q                    # mov rdx, "skui"
c += bytes.fromhex("483911")                 # cmp [rcx], rdx
j_n4 = len(c); c += b"\x75\x00"              # jne next
c += b"\x81\x79\x08" + name_d                # cmp dword [rcx+8], "nt"
c += b"\x0F\x84"; c += rel32(VA_CANCEL, here() + 4)   # je cancel
L_next = len(c)
c += bytes.fromhex("488B00")                 # mov rax, [rax]         (pNext)
c += b"\xEB" + struct.pack('<b', L_loop - (len(c) + 2))  # jmp loop
L_nomark = len(c)
c += bytes.fromhex("41F6C502")               # test r13b, 2  (original)
c += b"\x0F\x85"; c += rel32(VA_CANCEL, here() + 4)   # jne cancel
c += b"\xE9"; c += rel32(VA_MERGE, here() + 4)        # jmp merge

def fix8(at, target):
    c[at+1] = struct.pack('<b', target - (at + 2))[0]
fix8(j_nomark, L_nomark)
for j in (j_n1, j_n2, j_n3, j_n4): fix8(j, L_next)

o_cave = off(VA_CAVE)
assert all(b == 0 for b in data[o_cave:o_cave+len(c)+8]), "cave not free"
assert VA_CAVE + len(c) <= base + pe.sections[0].VirtualAddress + pe.sections[0].SizeOfRawData
data[o_cave:o_cave+len(c)] = c
data[o_test:o_test+6] = b"\xE9" + rel32(VA_CAVE, VA_TEST + 5) + b"\x90"

# refresh the PE checksum
out = pefile.PE(data=bytes(data))
out.OPTIONAL_HEADER.CheckSum = out.generate_checksum()
open(dst, 'wb').write(out.write())
print("wrote", dst, "cave bytes", len(c))

md = Cs(CS_ARCH_X86, CS_MODE_64)
print("--- entry ---")
for i in md.disasm(bytes(data[o_test:o_test+6]), VA_TEST): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
print("--- cave ---")
for i in md.disasm(bytes(c), VA_CAVE): print("  %#x %-6s %s" % (i.address, i.mnemonic, i.op_str))
