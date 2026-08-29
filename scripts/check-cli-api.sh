#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
binary="$repo_dir/.build/release/f64-metal"

if [ ! -x "$binary" ]; then
    printf 'release binary missing: %s\n' "$binary" >&2
    exit 1
fi

text=$($binary version)
json=$($binary version --json)
[ "$text" = "f64-metal 0.9.0-dev (VF64 ABI 1.0)" ]
[ "$json" = '{"tool":"0.9.0-dev","vf64_abi":"1.0","vf64_binary_version":"0x10000"}' ]
printf 'vf64_cli_api=pass\n'
