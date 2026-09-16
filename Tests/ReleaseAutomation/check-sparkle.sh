#!/bin/zsh
# Exercise the real Sparkle tools using an ephemeral key and a copy of the CI app.
set -euo pipefail
project_root="${0:A:h:h:h}"
app="${1:-$project_root/dist/Diorama.app}"
work="$(mktemp -d "$project_root/.build/sparkle-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT
umask 077
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" - "$work" <<'SWIFT'
import CryptoKit
import Foundation
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
for name in ["signing", "wrong"] {
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent(name + ".key"), atomically: true, encoding: .utf8)
    try key.publicKey.rawRepresentation.base64EncodedString().write(to: directory.appendingPathComponent(name + ".pub"), atomically: true, encoding: .utf8)
}
SWIFT
mkdir -p "$work/assets"
ditto "$app" "$work/Diorama.app"
/usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $(cat "$work/signing.pub")" "$work/Diorama.app/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign - "$work/Diorama.app"
ditto -c -k --keepParent "$work/Diorama.app" "$work/assets/Diorama-arm64.zip"
(cd "$work/assets" && shasum -a 256 Diorama-arm64.zip > Diorama-arm64.zip.sha256)
version="$(python3 "$project_root/scripts/release.py" version)"
sparkle_tools="$project_root/.build/artifacts/sparkle/Sparkle/bin"
"$sparkle_tools/generate_appcast" --ed-key-file "$work/signing.key" \
  --download-url-prefix "https://github.com/pdparchitect/diorama/releases/download/v$version/" \
  --maximum-deltas 0 "$work/assets"
# Validate the production parser against the actual tool's XML, using fixture notes.
python3 - "$project_root" "$work" "$version" <<'PY'
import importlib.util, pathlib, sys
root, work = map(pathlib.Path, sys.argv[1:3])
spec = importlib.util.spec_from_file_location('release', root / 'scripts/release.py')
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
release.ROOT = work
(work / 'VERSION').write_text(sys.argv[3] + '\n')
(work / 'CHANGELOG.md').write_text(f'## [{sys.argv[3]}] - 2026-09-16\n\n- Fixture.\n')
(work / 'assets/release-notes.md').write_text(release.notes())
(work / 'signature').write_text(release.validate_assets(work / 'assets'))
PY
signature="$(cat "$work/signature")"
"$sparkle_tools/sign_update" --ed-key-file "$work/signing.key" --verify "$work/assets/appcast.xml"
"$sparkle_tools/sign_update" --ed-key-file "$work/signing.key" --verify "$work/assets/Diorama-arm64.zip" "$signature"
if "$sparkle_tools/sign_update" --ed-key-file "$work/wrong.key" --verify "$work/assets/appcast.xml" > "$work/negative.log" 2>&1; then
  print -u2 'Wrong signing key was unexpectedly accepted.'; exit 1
fi
print 'tampered' >> "$work/assets/Diorama-arm64.zip"
if "$sparkle_tools/sign_update" --ed-key-file "$work/signing.key" --verify "$work/assets/Diorama-arm64.zip" "$signature" > "$work/negative.log" 2>&1; then
  print -u2 'Tampered archive was unexpectedly accepted.'; exit 1
fi
print 'Verified: real signed feed and archive, wrong-key rejection, and tampered-archive rejection.'
