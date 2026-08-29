#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/vf64-abi.XXXXXX")
trap 'rm -rf "$temporary_dir"' EXIT HUP INT TERM

clang -std=c11 -Wall -Wextra -Werror \
    -I "$repo_dir/include" \
    "$repo_dir/tests/abi/vf64_header_test.c" \
    -o "$temporary_dir/vf64_header_test"
"$temporary_dir/vf64_header_test"
printf 'vf64_c_abi=pass\n'
