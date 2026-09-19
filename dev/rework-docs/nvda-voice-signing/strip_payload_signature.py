"""Strip the Authenticode signature from one engine DLL inside sapi2sr-payload.zip.

Why: the bundled engine DLLs get signed on the USER's machine by
sku-nvda-voice-sign.ps1 with a per-machine throwaway certificate. A copy that
was pulled back out of a developer's Program Files still carries THAT machine's
signature; on every other PC it reads as "signed by an untrusted root", which
is a worse look to antivirus than a plain unsigned file. Ship the bare DLL.

The Authenticode PE hash excludes the signature, the security directory entry
and the checksum field, so the pins in sku-nvda-voice-sign.ps1 stay valid.

Usage: py -3 strip_payload_signature.py <payload.zip> <entry, e.g. x86/sapi2sr_engine.dll>
Every other entry is carried over unchanged (bytes, timestamps, order).
"""
import sys, io, os, zipfile, pefile

zpath, entry = sys.argv[1], sys.argv[2]

def strip(raw):
    pe = pefile.PE(data=raw)
    sec = pe.OPTIONAL_HEADER.DATA_DIRECTORY[pefile.DIRECTORY_ENTRY['IMAGE_DIRECTORY_ENTRY_SECURITY']]
    if not sec.Size:
        return None
    data = bytearray(raw)
    assert sec.VirtualAddress + sec.Size == len(data), "signature is not the file tail"
    del data[sec.VirtualAddress:]
    o_dir = sec.get_file_offset()
    data[o_dir:o_dir+8] = b"\0" * 8          # IMAGE_DATA_DIRECTORY {VirtualAddress, Size}
    out = pefile.PE(data=bytes(data))
    out.OPTIONAL_HEADER.CheckSum = out.generate_checksum()
    return out.write()

src = zipfile.ZipFile(zpath)
buf = io.BytesIO()
done = False
with zipfile.ZipFile(buf, 'w', zipfile.ZIP_DEFLATED) as dst:
    for info in src.infolist():
        raw = src.read(info)
        if info.filename == entry:
            stripped = strip(raw)
            if stripped is None:
                print("already unsigned:", entry); sys.exit(0)
            print("%s: %d -> %d bytes" % (entry, len(raw), len(stripped)))
            raw, done = stripped, True
        dst.writestr(info, raw, compress_type=info.compress_type)
src.close()
assert done, "entry not found: " + entry
tmp = zpath + ".tmp"
open(tmp, 'wb').write(buf.getvalue())
os.replace(tmp, zpath)
print("wrote", zpath)
