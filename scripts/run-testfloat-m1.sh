#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
tools_dir=$($script_dir/bootstrap-testfloat.sh | tail -n 1)

swift build --package-path "$repo_dir" -c release

for rounding in rnear_even rminMag rmin rmax rnear_maxMag; do
    for function in f64_add f64_sub f64_mul f64_div f64_sqrt f64_mulAdd; do
        "$tools_dir/testfloat_gen" \
            -seed 1 -level 1 "-$rounding" "$function" |
            "$repo_dir/.build/release/f64-metal" testfloat "$function" "$rounding"
    done
done

for rounding in rnear_even rminMag rmin rmax rnear_maxMag
do
    for function in f64_to_ui32 f64_to_ui64 f64_to_i32 f64_to_i64
    do
        "$tools_dir/testfloat_gen" \
            -seed 1 -level 1 "-$rounding" -notexact "$function" |
            "$repo_dir/.build/release/f64-metal" \
                testfloat "$function" "$rounding"
        "$tools_dir/testfloat_gen" \
            -seed 1 -level 1 "-$rounding" -exact "$function" |
            "$repo_dir/.build/release/f64-metal" \
                testfloat "$function" "$rounding" exact
    done
done

for rounding in rnear_even rminMag rmin rmax rnear_maxMag
do
    for function in ui32_to_f64 ui64_to_f64 i32_to_f64 i64_to_f64
    do
        "$tools_dir/testfloat_gen" -seed 1 -level 1 "-$rounding" "$function" |
            "$repo_dir/.build/release/f64-metal" \
                testfloat "$function" "$rounding"
    done
done

for rounding in rnear_even rminMag rmin rmax rnear_maxMag
do
    "$tools_dir/testfloat_gen" \
        -seed 1 -level 1 "-$rounding" -notexact f64_roundToInt |
        "$repo_dir/.build/release/f64-metal" \
            testfloat f64_roundToInt "$rounding"
    "$tools_dir/testfloat_gen" \
        -seed 1 -level 1 "-$rounding" -exact f64_roundToInt |
        "$repo_dir/.build/release/f64-metal" \
            testfloat f64_roundToInt "$rounding" exact
done

for function in \
    f64_eq f64_le f64_lt f64_eq_signaling f64_le_quiet f64_lt_quiet f64_rem
do
    "$tools_dir/testfloat_gen" -seed 1 -level 1 "$function" |
        "$repo_dir/.build/release/f64-metal" testfloat "$function" rnear_even
done
