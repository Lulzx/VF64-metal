#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
deps_dir="$repo_dir/.deps"
softfloat_dir="$deps_dir/berkeley-softfloat-3"
testfloat_dir="$deps_dir/berkeley-testfloat-3"
softfloat_commit=a0c6494cdc11865811dec815d5c0049fba9d82a8
testfloat_commit=a9c849f1b0eb0264b626d9686ffae167d996e3be
platform=Linux-ARM-VFPv2-GCC
testfloat_opts='-DFLOAT16 -DFLOAT32 -DFLOAT64 -DFLOAT_ROUND_ODD'

mkdir -p "$deps_dir"

clone_at_commit() {
    url=$1
    target=$2
    commit=$3
    if [ ! -d "$target/.git" ]; then
        git clone "$url" "$target"
    fi
    if ! git -C "$target" cat-file -e "$commit^{commit}" 2>/dev/null; then
        git -C "$target" fetch origin "$commit"
    fi
    git -C "$target" checkout --detach "$commit"
}

clone_at_commit \
    https://github.com/ucb-bar/berkeley-softfloat-3.git \
    "$softfloat_dir" "$softfloat_commit"
clone_at_commit \
    https://github.com/ucb-bar/berkeley-testfloat-3.git \
    "$testfloat_dir" "$testfloat_commit"

make -C "$softfloat_dir/build/$platform" -j8
opts_stamp="$testfloat_dir/build/$platform/.vf64-metal-opts"
if [ ! -f "$opts_stamp" ] || [ "$(cat "$opts_stamp")" != "$testfloat_opts" ]; then
    make -C "$testfloat_dir/build/$platform" clean
    printf '%s\n' "$testfloat_opts" > "$opts_stamp"
fi
make -C "$testfloat_dir/build/$platform" -j8 \
    SOFTFLOAT_DIR="$softfloat_dir" \
    PLATFORM="$platform" \
    TESTFLOAT_OPTS="$testfloat_opts" \
    testfloat_gen testfloat_ver

printf '%s\n' "$testfloat_dir/build/$platform"
