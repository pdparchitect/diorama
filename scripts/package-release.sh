#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
version="$(python3 "$project_root/scripts/release.py" version)"
: "${DIORAMA_SIGNING_IDENTITY:?Set a Developer ID Application signing identity.}"
: "${APPLE_API_KEY_PATH:?Set the path to the App Store Connect API key.}"
: "${APPLE_API_KEY_ID:?Set the App Store Connect key ID.}"
: "${APPLE_API_ISSUER_ID:?Set the App Store Connect issuer ID.}"
: "${SPARKLE_PRIVATE_KEY_PATH:?Set the path to the publisher Sparkle key.}"
[[ "$DIORAMA_SIGNING_IDENTITY" == Developer\ ID\ Application:* ]] || { print -u2 'A Developer ID Application identity is required.'; exit 1; }
[[ "$(uname -m)" == arm64 ]] || { print -u2 'Release packaging requires an Apple Silicon Mac.'; exit 1; }
# Validate notes before doing any signing or submission.
python3 "$project_root/scripts/release.py" notes >/dev/null
export DIORAMA_BUILD_CONFIGURATION=release DIORAMA_RELEASE=1
app="$("$project_root/scripts/build-app.sh")"
[[ "$(lipo -archs "$app/Contents/MacOS/Diorama")" == arm64 ]]
work="$(mktemp -d "$project_root/.build/diorama-release.XXXXXX")"
trap 'rm -rf "$work"' EXIT
assets="$work/assets"
mkdir -p "$assets"
archive="$assets/Diorama-arm64.zip"
sparkle_tools="$project_root/.build/artifacts/sparkle/Sparkle/bin"

ditto -c -k --sequesterRsrc --keepParent "$app" "$work/notarization.zip"
xcrun notarytool submit "$work/notarization.zip" \
  --key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" \
  --issuer "$APPLE_API_ISSUER_ID" --wait --output-format json > "$work/notarization.json"
python3 - "$work/notarization.json" <<'PY'
import json, sys
result = json.load(open(sys.argv[1]))
if result.get('status') != 'Accepted':
    raise SystemExit(f"Notarization failed: {result}")
PY
xcrun stapler staple "$app"
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
"$project_root/scripts/verify-app.sh" "$app" >&2

ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
(cd "$assets" && shasum -a 256 Diorama-arm64.zip > Diorama-arm64.zip.sha256)
"$sparkle_tools/generate_appcast" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" \
  --download-url-prefix "https://github.com/pdparchitect/diorama/releases/download/v$version/" \
  --full-release-notes-url "https://github.com/pdparchitect/diorama/releases/tag/v$version" \
  --maximum-deltas 0 "$assets"
python3 "$project_root/scripts/release.py" notes > "$assets/release-notes.md"
# generate_appcast only includes signatures when the key matches SUPublicEDKey.
signature="$(python3 "$project_root/scripts/release.py" signature --directory "$assets")"
"$sparkle_tools/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" --verify "$assets/appcast.xml"
"$sparkle_tools/sign_update" --ed-key-file "$SPARKLE_PRIVATE_KEY_PATH" --verify "$archive" "$signature"
python3 "$project_root/scripts/release.py" manifest --directory "$assets"
# Expose only complete, verified assets to CI, never the intermediate notary ZIP.
rm -rf "$project_root/dist/release"
mv "$assets" "$project_root/dist/release"
print "$project_root/dist/release/Diorama-arm64.zip"
