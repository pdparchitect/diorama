#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
source="$project_root/dist/Diorama.app"
install_root="${DIORAMA_INSTALL_DIR:-/Applications}"
destination="$install_root/Diorama.app"
[[ -d "$source" ]] || { print -u2 'Build the app first.'; exit 1; }
[[ ! -L "$destination" ]] || { print -u2 'Refusing to replace a symbolic link.'; exit 1; }
[[ "${source:A}" != "${destination:A}" ]] || { print -u2 'Source and destination must differ.'; exit 1; }
"$project_root/scripts/verify-app.sh" "$source" >&2
if [[ -e "$destination" ]]; then
  identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$destination/Contents/Info.plist")"
  [[ "$identifier" == com.pdparchitect.diorama ]] || { print -u2 'Refusing to replace another application.'; exit 1; }
fi
if pgrep -x Diorama >/dev/null; then
  print -u2 'Quit Diorama before installing the app.'; exit 1
fi
mkdir -p "$install_root"
staging="$(mktemp -d "$install_root/.diorama-install.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$source" "$staging/Diorama.app"
"$project_root/scripts/verify-app.sh" "$staging/Diorama.app" >&2
if [[ -e "$destination" ]]; then
  mv "$destination" "$staging/previous.app"
fi
if ! mv "$staging/Diorama.app" "$destination"; then
  if [[ -d "$staging/previous.app" ]]; then
    mv "$staging/previous.app" "$destination"
  fi
  exit 1
fi
"$project_root/scripts/verify-app.sh" "$destination" >&2
print "$destination"
