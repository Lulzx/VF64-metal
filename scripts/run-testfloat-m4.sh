#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
tools_dir=$($script_dir/bootstrap-testfloat.sh | tail -n 1)

swift build --package-path "$repo_dir" -c release
exec "$repo_dir/.build/release/vf64-metal" testfloat-suite-isa "$tools_dir"
