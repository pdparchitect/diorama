#!/bin/zsh
set -euo pipefail

# Match Noodle's SDK selection for compilation and linking. Without the linker
# sysroot, SwiftPM can stamp the deployment target as the SDK and make SwiftUI
# select legacy controls, menu ordering, and settings-window behavior.
diorama_sdk="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT="$diorama_sdk"
diorama_command="${1:?Pass build or test}"
shift
exec "$(xcrun --find swift)" "$diorama_command" --build-system native --sdk "$diorama_sdk" \
    -Xlinker -syslibroot -Xlinker "$diorama_sdk" "$@"
