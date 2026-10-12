#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
# Keep generated test bundles outside File Provider-managed Documents folders.
scratch_dir="$(mktemp -d /private/tmp/mamori-tests.XXXXXX)"
trap 'rm -rf "$scratch_dir"' EXIT
export CLANG_MODULE_CACHE_PATH="$scratch_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$scratch_dir/module-cache"
swift test --scratch-path "$scratch_dir/build" --cache-path "$scratch_dir/cache" --config-path "$scratch_dir/config" --security-path "$scratch_dir/security" --disable-sandbox
