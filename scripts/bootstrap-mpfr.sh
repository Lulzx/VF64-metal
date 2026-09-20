#!/bin/sh
# Pin and build the M9 reference oracle.
#
# Berkeley TestFloat has no transcendental generators, so M9 is gated against
# MPFR instead. This script fails closed when the pinned oracle versions are
# not the ones installed, so an artifact can never be produced against an
# unrecorded oracle.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
build_dir="$repo_dir/.deps/m9"

mpfr_version=${VF64_MPFR_VERSION:-4.2.2}
gmp_version=${VF64_GMP_VERSION:-6.3.0}
prefix=${VF64_MPFR_PREFIX:-/opt/homebrew}

header="$prefix/include/mpfr.h"
if [ ! -f "$header" ]; then
    printf 'mpfr headers not found under %s\n' "$prefix" >&2
    printf 'install with: brew install mpfr gmp\n' >&2
    exit 1
fi

found_mpfr=$(sed -n 's/^#define MPFR_VERSION_STRING "\([^"]*\)".*/\1/p' "$header")
if [ "$found_mpfr" != "$mpfr_version" ]; then
    printf 'mpfr version mismatch: pinned %s, found %s\n' \
        "$mpfr_version" "$found_mpfr" >&2
    exit 1
fi

gmp_header="$prefix/include/gmp.h"
gmp_field() {
    awk -v key="$1" '$1 == "#define" && $2 == key { print $3 }' "$gmp_header"
}
found_gmp=$(gmp_field __GNU_MP_VERSION)
found_gmp_minor=$(gmp_field __GNU_MP_VERSION_MINOR)
found_gmp_patch=$(gmp_field __GNU_MP_VERSION_PATCHLEVEL)
found_gmp="$found_gmp.$found_gmp_minor.$found_gmp_patch"
if [ "$found_gmp" != "$gmp_version" ]; then
    printf 'gmp version mismatch: pinned %s, found %s\n' \
        "$gmp_version" "$found_gmp" >&2
    exit 1
fi

mkdir -p "$build_dir"
cc -O2 -Wall -Wextra -o "$build_dir/exp_ref" "$repo_dir/tools/m9/exp_ref.c" \
    -I"$prefix/include" -L"$prefix/lib" -lmpfr -lgmp

printf '%s\n' "$build_dir/exp_ref"
