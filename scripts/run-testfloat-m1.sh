#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
tools_dir=$($script_dir/bootstrap-testfloat.sh | tail -n 1)
runner=${F64_TESTFLOAT_COMMAND:-testfloat}

swift build --package-path "$repo_dir" -c release

for rounding in rnear_even rminMag rmin rmax rnear_maxMag; do
    for function in f64_add f64_sub f64_mul f64_div f64_sqrt f64_mulAdd; do
        "$tools_dir/testfloat_gen" \
            -seed 1 -level 1 "-$rounding" "$function" |
            "$repo_dir/.build/release/vf64-metal" "$runner" "$function" "$rounding"
    done
done
