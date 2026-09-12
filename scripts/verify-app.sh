#!/bin/zsh
set -euo pipefail
app="${1:?Usage: verify-app.sh /path/to/Diorama.app}"
codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
python3 - "$app" <<'PY'
import pathlib
import plistlib
import subprocess
import sys

app = pathlib.Path(sys.argv[1])
with (app / 'Contents/Info.plist').open('rb') as source:
    info = plistlib.load(source)
required = {
    'CFBundleIdentifier': 'com.pdparchitect.diorama',
    'CFBundleExecutable': 'Diorama',
    'CFBundlePackageType': 'APPL',
    'CFBundleIconFile': 'Diorama',
    'LSMinimumSystemVersion': '15.0',
}
for key, value in required.items():
    if info.get(key) != value:
        raise SystemExit(f'Unexpected bundle metadata: {key}')
icon = app / 'Contents/Resources/Diorama.icns'
if not icon.is_file() or icon.read_bytes()[:4] != b'icns':
    raise SystemExit('Missing or invalid application icon')
executable = app / 'Contents/MacOS/Diorama'
if not executable.is_file():
    raise SystemExit('Missing application executable')
metadata = subprocess.run(['codesign', '-dv', '--verbose=4', str(app)], capture_output=True, text=True, check=True).stderr
if not any('flags=' in line and 'runtime' in line for line in metadata.splitlines()):
    raise SystemExit('Hardened runtime is not enabled')
entitlements = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(app)], capture_output=True, check=True).stdout
if entitlements.strip() and plistlib.loads(entitlements):
    raise SystemExit('Unexpected entitlements: Diorama ships with no entitlement grants')
for path in (app / 'Contents').rglob('*'):
    if not path.is_file():
        continue
    kind = subprocess.check_output(['file', '-b', str(path)], text=True)
    if 'Mach-O' in kind and path != executable:
        raise SystemExit(f'Unexpected embedded executable: {path}')
dependencies = subprocess.check_output(['otool', '-L', str(executable)], text=True).splitlines()[1:]
for line in dependencies:
    dependency = line.strip().split(' (', 1)[0]
    if not dependency.startswith(('/System/Library/', '/usr/lib/', '@rpath/libswift')):
        raise SystemExit(f'Unexpected external dependency: {dependency}')
# Swift runtime rpaths must resolve to the OS, not a developer's writable toolchain.
commands = subprocess.check_output(['otool', '-l', str(executable)], text=True).splitlines()
for i, line in enumerate(commands):
    if line.strip() == 'cmd LC_RPATH':
        path = commands[i + 2].strip().split(' (offset', 1)[0].removeprefix('path ')
        local = path.replace('@loader_path', str(executable.parent)).replace('@executable_path', str(executable.parent))
        in_bundle = pathlib.Path(local).is_absolute() and pathlib.Path(local).resolve().is_relative_to(app.resolve())
        if not in_bundle and not path.startswith(('/usr/lib/', '/System/Library/')):
            raise SystemExit(f'Unexpected runtime search path: {path}')
print('Verified: hardened runtime, no entitlements, one executable, system libraries, app metadata and icon.')
PY
