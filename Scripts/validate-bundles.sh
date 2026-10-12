#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
source "$project_dir/Scripts/lib/bundles.zsh"
if (( $# != 0 && $# != 2 )); then
    print -u2 'Usage: ./Scripts/validate-bundles.sh [Mamori.app "Mamori Preview.app"]'
    exit 2
fi
mamori_validate_bundles "${1:-$project_dir/build/Mamori.app}" "${2:-$project_dir/build/Mamori Preview.app}"
print "Validated Mamori $mamori_version ($mamori_asset_arch, $mamori_signing_kind). No service was launched."
