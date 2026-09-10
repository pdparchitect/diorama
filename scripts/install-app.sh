#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
source="$project_root/dist/Diorama.app"
destination="${DIORAMA_INSTALL_DIR:-/Applications}/Diorama.app"
[[ -d "$source" ]] || { print -u2 'Build the app first.'; exit 1; }
if [[ -e "$destination" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$identifier" == com.pdparchitect.diorama ]] || { print -u2 'Refusing to replace another application.'; exit 1; }
  if pgrep -x Diorama >/dev/null; then
    print -u2 'Quit Diorama before replacing the installed app.'; exit 1
  fi
fi
mkdir -p "${destination:h}"
ditto "$source" "$destination"
"$project_root/scripts/verify-app.sh" "$destination"
print "$destination"
