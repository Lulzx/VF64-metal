#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)

printf 'f64-metal release verification\n'
printf 'source_commit=%s\n' "$(git -C "$repo_dir" rev-parse HEAD)"
sw_vers
system_profiler SPDisplaysDataType | sed -n '1,24p'

swift build --package-path "$repo_dir" -c release
"$repo_dir/.build/release/f64-metal" validate
"$script_dir/run-testfloat-m2.sh"
"$script_dir/run-testfloat-m4.sh"
"$repo_dir/.build/release/f64-metal" bench
"$repo_dir/.build/release/f64-metal" workloads

printf 'release_verification=pass\n'
