#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
"$project_root/scripts/build-app.sh"
open "$project_root/dist/Diorama.app"
