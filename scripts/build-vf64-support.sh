#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_file="$repo_dir/Sources/F64Metal/Shaders/Interop/VF64Support.metal"
output=${1:-"$repo_dir/.build/vf64/vf64-support.air"}

mkdir -p "$(dirname -- "$output")"
xcrun metal -std=metal3.2 -c "$source_file" -o "$output"

symbols=$(xcrun metal-nm "$output")
for symbol in \
    vf64_add_rne vf64_sub_rne vf64_mul_rne vf64_div_rne vf64_sqrt_rne \
    vf64_fma_rne vf64_add_round vf64_sub_round vf64_mul_round \
    vf64_div_round vf64_sqrt_round vf64_fma_round vf64_remainder \
    vf64_round_to_int vf64_eq vf64_eq_signaling vf64_lt vf64_le \
    vf64_lt_quiet vf64_le_quiet vf64_ui32_to_f64 vf64_ui64_to_f64 \
    vf64_i32_to_f64 vf64_i64_to_f64 vf64_f64_to_ui32 vf64_f64_to_ui64 \
    vf64_f64_to_i32 vf64_f64_to_i64 vf64_f64_to_f32 vf64_f64_to_f16 \
    vf64_f32_to_f64 vf64_f16_to_f64 vf64_wide_add vf64_wide_sub \
    vf64_wide_mul vf64_wide_div vf64_wide_sqrt vf64_wide_fma
do
    printf '%s\n' "$symbols" | grep -q " T $symbol\$"
done

printf 'vf64_support=pass symbols=38 output=%s\n' "$output"
