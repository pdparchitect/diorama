#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$project_root/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
mkdir -p "$CLANG_MODULE_CACHE_PATH"
python3 -m unittest discover -s "$project_root/Tests/ReleaseAutomation" -v
zsh "$project_root/scripts/swift.sh" test --package-path "$project_root"
