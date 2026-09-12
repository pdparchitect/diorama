#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
configuration="${DIORAMA_BUILD_CONFIGURATION:-release}"
# Keep local builds tied to one certificate; changing an ad-hoc CDHash breaks TCC grants.
identity="${DIORAMA_SIGNING_IDENTITY:-$(git -C "$project_root" config --local --get diorama.signingIdentity 2>/dev/null || true)}"
if [[ -z "$identity" ]]; then
  print -u2 -- 'Choose a persistent signing identity before building Diorama:'
  print -u2 -- '  security find-identity -v -p codesigning'
  print -u2 -- '  git config --local diorama.signingIdentity CERTIFICATE_SHA1'
  print -u2 -- 'For disposable CI builds only, explicitly set DIORAMA_SIGNING_IDENTITY=-.'
  exit 1
fi
if [[ "$identity" == - && "${DIORAMA_SIGNING_IDENTITY:-}" != - ]]; then
  print -u2 -- 'Ad-hoc signing requires an explicit DIORAMA_SIGNING_IDENTITY=- override.'
  exit 1
fi
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
swift build --package-path "$project_root" --configuration "$configuration" >&2
bin_path="$(swift build --package-path "$project_root" --configuration "$configuration" --show-bin-path)"
output="$project_root/dist/Diorama.app"
mkdir -p "$project_root/dist"
staging="$(mktemp -d "$project_root/dist/.diorama-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Diorama.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_path/Diorama" "$app/Contents/MacOS/Diorama"
# Recent Swift toolchains add a development-only fallback runtime path. Keep only OS/bundle paths.
python3 - "$app/Contents/MacOS/Diorama" <<'PY'
import subprocess
import sys
executable = sys.argv[1]
lines = subprocess.check_output(['otool', '-l', executable], text=True).splitlines()
for index, line in enumerate(lines):
    if line.strip() != 'cmd LC_RPATH':
        continue
    path = lines[index + 2].strip().split(' (offset', 1)[0].removeprefix('path ')
    if '.xctoolchain/' in path:
        subprocess.run(['install_name_tool', '-delete_rpath', path, executable], check=True)
PY
cp "$project_root/Support/Info.plist" "$app/Contents/Info.plist"
cp "$project_root/Support/Diorama.icns" "$app/Contents/Resources/Diorama.icns"
codesign --force --options runtime --timestamp=none --sign "$identity" "$app"
"$project_root/scripts/verify-app.sh" "$app" >&2
rm -rf "$output"
mv "$app" "$output"
print "$output"
