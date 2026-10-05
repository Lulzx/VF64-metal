#!/bin/sh
# Links the M9 support-ABI conformance kernels against vf64-support.air and
# writes one metallib. The kernels reach the transcendentals only through
# unresolved vf64_<name>_rne/_round externals, so a passing campaign over this
# library gates the linkable symbols themselves.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
output=${1:-"$repo_dir/.build/vf64/vf64-m9-support.metallib"}
work=$(mktemp -d "${TMPDIR:-/tmp}/vf64-m9-support.XXXXXX")
trap 'rm -rf "$work"' EXIT HUP INT TERM

"$script_dir/build-vf64-support.sh" "$work/vf64-support.air" >/dev/null
xcrun metal -std=metal3.2 -c \
    "$repo_dir/tests/interop/vf64_m9_support_kernels.metal" \
    -o "$work/kernels.air"

# Every transcendental must arrive unresolved, so the link supplies it.
undefined=$(xcrun metal-nm "$work/kernels.air" | grep -c ' U vf64_' || true)
if [ "$undefined" != 44 ]; then
    printf 'expected 44 unresolved vf64 symbols in the kernels, found %s\n' \
        "$undefined" >&2
    exit 1
fi

xcrun air-link "$work/kernels.air" "$work/vf64-support.air" \
    -o "$work/linked.air"
mkdir -p "$(dirname -- "$output")"
xcrun metallib "$work/linked.air" -o "$output"
printf '%s\n' "$output"
