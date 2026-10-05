#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
source_file="$repo_dir/Sources/VF64Metal/Shaders/Interop/VF64Support.metal"
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
    vf64_wide_mul vf64_wide_div vf64_wide_sqrt vf64_wide_fma \
    vf64_exp_rne vf64_exp_round vf64_exp2_rne vf64_exp2_round \
    vf64_expm1_rne vf64_expm1_round vf64_log_rne vf64_log_round \
    vf64_log2_rne vf64_log2_round vf64_log1p_rne vf64_log1p_round \
    vf64_cbrt_rne vf64_cbrt_round vf64_hypot_rne vf64_hypot_round \
    vf64_pow_rne vf64_pow_round vf64_atan_rne vf64_atan_round \
    vf64_atan2_rne vf64_atan2_round vf64_asin_rne vf64_asin_round \
    vf64_acos_rne vf64_acos_round vf64_sin_rne vf64_sin_round vf64_cos_rne \
    vf64_cos_round vf64_tan_rne vf64_tan_round vf64_sinh_rne \
    vf64_sinh_round vf64_cosh_rne vf64_cosh_round vf64_tanh_rne \
    vf64_tanh_round vf64_asinh_rne vf64_asinh_round vf64_acosh_rne \
    vf64_acosh_round vf64_atanh_rne vf64_atanh_round
do
    printf '%s\n' "$symbols" | grep -q " T $symbol\$"
done

printf 'vf64_support=pass symbols=82 output=%s\n' "$output"
