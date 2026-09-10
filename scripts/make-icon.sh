#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
iconset="$project_root/.build/Diorama.iconset"
rm -rf "$iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$project_root/Support/AppIcon.png" --out "$iconset/icon_${size}x${size}.png" >/dev/null
  doubled=$((size * 2))
  sips -z "$doubled" "$doubled" "$project_root/Support/AppIcon.png" --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$project_root/Support/Diorama.icns"
