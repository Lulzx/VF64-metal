#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

printf 'VF64-metal release verification\n'
printf 'source_commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
sw_vers
system_profiler SPDisplaysDataType | sed -n '1,24p'

"$script_dir/check-vf64-abi.sh"
"$script_dir/check-conformance-data.sh"
"$script_dir/test-cross-generation-evidence.sh"
"$script_dir/check-vf64-support.sh"
swift build --package-path "$repo_dir" -c release
"$script_dir/check-cli-api.sh"
"$repo_dir/.build/release/vf64-metal" resources --json
"$repo_dir/.build/release/vf64-metal" validate
"$script_dir/run-testfloat-m2.sh"
"$script_dir/run-testfloat-m4.sh"
"$repo_dir/.build/release/vf64-metal" bench
"$repo_dir/.build/release/vf64-metal" workloads
"$script_dir/fetch-matrix-market.sh"
"$repo_dir/.build/release/vf64-metal" matrix-market \
    "$repo_dir/.deps/external-matrices/bcsstk01.mtx" \
    "$repo_dir/.deps/external-matrices/494_bus.mtx"

printf 'release_verification=pass\n'
