"""Package an actually compiled device app. Never create a source-only fake IPA."""
from pathlib import Path
import plistlib
import struct
import zipfile

root = Path(__file__).resolve().parent.parent
app = root / 'build/Build/Products/Release-iphoneos/ThomTroll.app'
extension = app / 'PlugIns/ThomTrollKeyboard.appex'

def check_bundle(bundle, expected_type):
    with (bundle / 'Info.plist').open('rb') as stream:
        info = plistlib.load(stream)
    assert info['CFBundlePackageType'] == expected_type
    binary = bundle / info['CFBundleExecutable']
    with binary.open('rb') as stream:
        magic, cpu = struct.unpack('<II', stream.read(8))
    assert magic == 0xfeedfacf and cpu == 0x0100000c, f'Not an arm64 Mach-O executable: {binary}'
    return info

main = check_bundle(app, 'APPL')
keyboard = check_bundle(extension, 'XPC!')
assert keyboard['CFBundleIdentifier'].startswith(main['CFBundleIdentifier'] + '.')
assert keyboard['NSExtension']['NSExtensionPointIdentifier'] == 'com.apple.keyboard-service'
output = root / 'dist/ThomTroll-unsigned.ipa'
output.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
    for path in sorted(app.rglob('*')):
        if path.is_file():
            archive.write(path, 'Payload/' + str(path.relative_to(app.parent)))
with zipfile.ZipFile(output) as archive:
    assert archive.testzip() is None
print(f'Created {output} ({output.stat().st_size} bytes). UNSIGNED: sign app AND keyboard extension before installation.')
