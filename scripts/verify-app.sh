#!/bin/zsh
set -euo pipefail
app="${1:?Usage: verify-app.sh /path/to/Diorama.app}"
codesign --verify --deep --strict --verbose=2 "$app"
plutil -lint "$app/Contents/Info.plist"
dependencies="$(otool -L "$app/Contents/MacOS/Diorama")"
# The first line names the inspected executable; check dependency lines only.
if print -r -- "$dependencies" | tail -n +2 | /usr/bin/grep -E '/opt/homebrew|/usr/local|/Users/'; then
  print -u2 'Unexpected external dependency'; exit 1
fi
