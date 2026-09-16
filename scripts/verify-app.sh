#!/bin/zsh
set -euo pipefail
app="${1:?Usage: verify-app.sh /path/to/Diorama.app}"
codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
python3 - "$app" <<'PY'
import pathlib
import plistlib
import re
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
    'SUFeedURL': 'https://github.com/pdparchitect/diorama/releases/latest/download/appcast.xml',
    'SUPublicEDKey': '1ZT5NrPiDPaQ54iHGSI1a9JIn6kTrmjQvzZRBA9f/sk=',
    'SURequireSignedFeed': True,
    'SUVerifyUpdateBeforeExtraction': True,
    'SUEnableAutomaticChecks': True,
    'SUScheduledCheckInterval': 86400,
    'SUAutomaticallyUpdate': False,
    'SUSendProfileInfo': False,
}
for key, value in required.items():
    if info.get(key) != value:
        raise SystemExit(f'Unexpected bundle metadata: {key}')
version = info.get('CFBundleShortVersionString', '')
if not re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)', version) or info.get('CFBundleVersion') != version:
    raise SystemExit('Invalid or inconsistent bundle version')
if type(info.get('DioramaUpdatesEnabled')) is not bool:
    raise SystemExit('Missing update policy')
if info.get('SUEnableInstallerLauncherService') or info.get('SUEnableDownloaderService'):
    raise SystemExit('Unexpected Sparkle XPC service enabled')
icon = app / 'Contents/Resources/Diorama.icns'
if not icon.is_file() or icon.read_bytes()[:4] != b'icns':
    raise SystemExit('Missing or invalid application icon')
executable = app / 'Contents/MacOS/Diorama'
if not executable.is_file():
    raise SystemExit('Missing application executable')
sparkle = app / 'Contents/Frameworks/Sparkle.framework'
if (sparkle / 'Versions/B/XPCServices').exists() or (sparkle / 'XPCServices').is_symlink():
    raise SystemExit('Unexpected Sparkle XPC services')
if not (app / 'Contents/Resources/Sparkle-LICENSE.txt').is_file():
    raise SystemExit('Missing Sparkle license')
components = [app, sparkle, sparkle / 'Versions/B/Autoupdate', sparkle / 'Versions/B/Updater.app']
team = None
for component in components:
    subprocess.run(['codesign', '--verify', '--strict', str(component)], check=True)
    metadata = subprocess.run(['codesign', '-dv', '--verbose=4', str(component)], capture_output=True, text=True, check=True).stderr
    if not any('flags=' in line and 'runtime' in line for line in metadata.splitlines()):
        raise SystemExit(f'Hardened runtime is not enabled: {component}')
    component_team = next((line for line in metadata.splitlines() if line.startswith('TeamIdentifier=')), None)
    if component == app:
        team = component_team
    elif component_team != team:
        raise SystemExit(f'Updater signer does not match the app: {component}')
    if info['DioramaUpdatesEnabled'] and ('Authority=Developer ID Application:' not in metadata or 'Timestamp=' not in metadata):
        raise SystemExit(f'Distributed code requires Developer ID and a secure timestamp: {component}')
    entitlements = subprocess.run(['codesign', '-d', '--entitlements', ':-', str(component)], capture_output=True, check=True).stdout
    if entitlements.strip() and plistlib.loads(entitlements):
        raise SystemExit(f'Unexpected entitlement grants: {component}')
expected_binaries = {
    executable.resolve(),
    (sparkle / 'Versions/B/Sparkle').resolve(),
    (sparkle / 'Versions/B/Autoupdate').resolve(),
    (sparkle / 'Versions/B/Updater.app/Contents/MacOS/Updater').resolve(),
}
binaries = set()
for path in (app / 'Contents').rglob('*'):
    if path.is_symlink() and not path.resolve().is_relative_to(app.resolve()):
        raise SystemExit(f'Symlink escapes app bundle: {path}')
    if not path.is_file():
        continue
    kind = subprocess.check_output(['file', '-b', str(path)], text=True)
    if 'Mach-O' in kind:
        binaries.add(path.resolve())
if binaries != expected_binaries:
    raise SystemExit(f'Unexpected executable boundary: {binaries.symmetric_difference(expected_binaries)}')
for binary in binaries:
    dependencies = subprocess.check_output(['otool', '-L', str(binary)], text=True).splitlines()[1:]
    for line in dependencies:
        dependency = line.strip().split(' (', 1)[0]
        if line.endswith(':') or not dependency:
            continue  # Universal binary architecture headers.
        if dependency == '@rpath/Sparkle.framework/Versions/B/Sparkle':
            continue
        if not dependency.startswith(('/System/Library/', '/usr/lib/', '@rpath/libswift')):
            raise SystemExit(f'Unexpected external dependency: {dependency}')
# Runtime search paths may only resolve to the OS or this signed bundle.
for binary in binaries:
    commands = subprocess.check_output(['otool', '-l', str(binary)], text=True).splitlines()
    for i, line in enumerate(commands):
        if line.strip() != 'cmd LC_RPATH':
            continue
        path = commands[i + 2].strip().split(' (offset', 1)[0].removeprefix('path ')
        local = path.replace('@loader_path', str(binary.parent)).replace('@executable_path', str(executable.resolve().parent))
        in_bundle = pathlib.Path(local).is_absolute() and pathlib.Path(local).resolve().is_relative_to(app.resolve())
        if not in_bundle and not path.startswith(('/usr/lib/', '/System/Library/')):
            raise SystemExit(f'Unexpected runtime search path in {binary}: {path}')
    if binary == executable.resolve() and '@executable_path/../Frameworks' not in '\n'.join(commands):
        raise SystemExit('Missing bundle-relative Sparkle search path')
print('Verified: hardened runtime, no entitlements, signed Sparkle helpers, bundle-contained dependencies, update policy, metadata and icon.')
PY
