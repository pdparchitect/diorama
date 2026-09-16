#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
configuration="${DIORAMA_BUILD_CONFIGURATION:-release}"
version="$(python3 "$project_root/scripts/release.py" version)"
release="${DIORAMA_RELEASE:-0}"
[[ "$release" == 0 || "$release" == 1 ]] || { print -u2 'DIORAMA_RELEASE must be 0 or 1.'; exit 1; }
[[ "$configuration" == release || "$configuration" == debug ]] || { print -u2 'Invalid build configuration.'; exit 1; }
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
if [[ "$release" == 1 && ( "$identity" != Developer\ ID\ Application:* || "$configuration" != release ) ]]; then
  print -u2 'Distributed releases require a Developer ID Application identity and release configuration.'
  exit 1
fi
timestamp_option=--timestamp=none
if [[ "$release" == 1 ]]; then timestamp_option=--timestamp; fi
signing_options=(--force --options runtime "$timestamp_option" --sign "$identity")
if [[ -n "${DIORAMA_SIGNING_KEYCHAIN:-}" ]]; then
  signing_options+=(--keychain "$DIORAMA_SIGNING_KEYCHAIN")
fi
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
zsh "$project_root/scripts/swift.sh" build --package-path "$project_root" --configuration "$configuration" >&2
bin_path="$(zsh "$project_root/scripts/swift.sh" build --package-path "$project_root" --configuration "$configuration" --show-bin-path)"
python3 "$project_root/scripts/verify-build-sdk.py" "$bin_path/Diorama" "$(xcrun --sdk macosx --show-sdk-version)" >&2
output="$project_root/dist/Diorama.app"
mkdir -p "$project_root/dist"
staging="$(mktemp -d "$project_root/dist/.diorama-build.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Diorama.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" "$app/Contents/Frameworks"
sparkle="$app/Contents/Frameworks/Sparkle.framework"
ditto "$project_root/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework" "$sparkle"
# Diorama is unsandboxed and does not use either Sparkle XPC service.
rm -rf "$sparkle/Versions/B/XPCServices" "$sparkle/XPCServices"
cp "$project_root/.build/checkouts/Sparkle/LICENSE" "$app/Contents/Resources/Sparkle-LICENSE.txt"
cp "$project_root/Support/Noodle-LICENSE.txt" "$app/Contents/Resources/Noodle-LICENSE.txt"
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
    if path.startswith('/') and not path.startswith(('/System/Library/', '/usr/lib/')):
        subprocess.run(['install_name_tool', '-delete_rpath', path, executable], check=True)
PY
cp "$project_root/Support/Info.plist" "$app/Contents/Info.plist"
cp "$project_root/Support/Diorama.icns" "$app/Contents/Resources/Diorama.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $version" "$app/Contents/Info.plist"
if [[ "$release" == 1 ]]; then
  /usr/libexec/PlistBuddy -c 'Set :DioramaUpdatesEnabled true' "$app/Contents/Info.plist"
fi
# Sign nested code inside-out, without inheriting or adding entitlement grants.
for component in "$sparkle/Versions/B/Autoupdate" "$sparkle/Versions/B/Updater.app" "$sparkle" "$app"; do
  codesign "${signing_options[@]}" "$component"
done
"$project_root/scripts/verify-app.sh" "$app" >&2
rm -rf "$output"
mv "$app" "$output"
print "$output"
