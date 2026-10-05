#!/bin/sh
# Gates the M9 support-ABI symbols on the GPU: links the support conformance
# kernels against vf64-support.air and runs the pinned MPFR smoke vectors for
# all 22 functions in five rounding modes through them, comparing result bits.
# The full corpus is VF64_M9_PATH=support scripts/run-mpfr-m9.sh.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
binary="$repo_dir/.build/release/vf64-metal"
work=$(mktemp -d "${TMPDIR:-/tmp}/vf64-m9-support-check.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

if [ ! -x "$binary" ]; then
    printf 'release binary missing: %s\n' "$binary" >&2
    exit 1
fi

"$script_dir/build-vf64-m9-support-kernels.sh" "$work/m9-support.metallib" >/dev/null
"$binary" transcendental --support-library="$work/m9-support.metallib" \
    > "$work/log.txt"
cat "$work/log.txt"
passed=$(grep -c 'passed through the support ABI' "$work/log.txt" || true)
if [ "$passed" != 22 ]; then
    printf 'expected 22 functions through the support ABI, %s passed\n' "$passed" >&2
    exit 1
fi
printf 'vf64_m9_support=pass functions=22 symbols=44\n'
