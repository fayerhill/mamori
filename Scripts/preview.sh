#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
if [[ ! -x "$project_dir/build/Mamori Preview.app/Contents/MacOS/Mamori" ]]; then
    "$project_dir/Scripts/build.sh"
fi
open "$project_dir/build/Mamori Preview.app" --args --demo "$@"
