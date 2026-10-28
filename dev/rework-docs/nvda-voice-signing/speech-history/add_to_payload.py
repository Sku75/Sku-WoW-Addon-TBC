"""Put the speech-history proxy into a sapi2sr-payload.zip.

    py -3 add_to_payload.py <in.zip> <out.zip> out/nvdaControllerClient.dll ../sku-nvda-voice-sign.ps1

x64/nvdaControllerClient.dll (NV Access's signed original) becomes
x64/nvdaControllerClient.nvaccess.dll unchanged, our UNSIGNED proxy build is
x64/nvdaControllerClient.dll (the installer's signing run signs it - its PE
hash must be pinned in the signing script), and the signing script is
replaced. Everything else is copied byte for byte. On a zip that already
carries the proxy only the proxy and the script are replaced."""
import sys, zipfile
src, dst, proxy, sign = sys.argv[1:5]
zin = zipfile.ZipFile(src)
already = 'x64/nvdaControllerClient.nvaccess.dll' in zin.namelist()
with zipfile.ZipFile(dst, 'w', zipfile.ZIP_DEFLATED) as zout:
    for i in zin.infolist():
        data = zin.read(i.filename)
        if i.filename == 'x64/nvdaControllerClient.dll':
            if not already:
                zout.writestr('x64/nvdaControllerClient.nvaccess.dll', data)
            zout.writestr('x64/nvdaControllerClient.dll', open(proxy, 'rb').read())
        elif i.filename == 'sku-nvda-voice-sign.ps1':
            zout.writestr(i.filename, open(sign, 'rb').read())
        else:
            zout.writestr(i, data)
for i in zipfile.ZipFile(dst).infolist():
    print(f'{i.filename:45} {i.file_size}')
