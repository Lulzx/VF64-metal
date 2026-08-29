#include "../Core/Preamble.metal"
#include "../Pair/Arithmetic.metal"
#include "../Pair/Codec.metal"
#include "../IEEE/Arithmetic.metal"
#include "../Wide/Arithmetic.metal"

// Linkable round-to-nearest-even entry points for source-language backends.
// Arguments and results are raw IEEE-754 binary64 bits so no native FP64 ALU
// operation can enter the generated AIR. CUDA/PTX directed-rounding variants
// use the corresponding *_round functions below.
[[visible]] ulong vf64_add_rne(ulong a, ulong b) {
    uint flags = 0;
    return soft_add64_status(a, b, soft_round_near_even, flags);
}

[[visible]] ulong vf64_sub_rne(ulong a, ulong b) {
    uint flags = 0;
    return soft_sub64_status(a, b, soft_round_near_even, flags);
}

[[visible]] ulong vf64_mul_rne(ulong a, ulong b) {
    uint flags = 0;
    return soft_mul64_status(a, b, soft_round_near_even, flags);
}

[[visible]] ulong vf64_div_rne(ulong a, ulong b) {
    uint flags = 0;
    return soft_div64_status(a, b, soft_round_near_even, flags);
}

[[visible]] ulong vf64_sqrt_rne(ulong a) {
    uint flags = 0;
    return soft_sqrt64_status(a, soft_round_near_even, flags);
}

[[visible]] ulong vf64_fma_rne(ulong a, ulong b, ulong c) {
    uint flags = 0;
    return soft_fma64_status(a, b, c, soft_round_near_even, flags);
}

[[visible]] ulong vf64_add_round(ulong a, ulong b, uint roundingMode) {
    uint flags = 0;
    return soft_add64_status(a, b, roundingMode, flags);
}

[[visible]] ulong vf64_sub_round(ulong a, ulong b, uint roundingMode) {
    uint flags = 0;
    return soft_sub64_status(a, b, roundingMode, flags);
}

[[visible]] ulong vf64_mul_round(ulong a, ulong b, uint roundingMode) {
    uint flags = 0;
    return soft_mul64_status(a, b, roundingMode, flags);
}

[[visible]] ulong vf64_div_round(ulong a, ulong b, uint roundingMode) {
    uint flags = 0;
    return soft_div64_status(a, b, roundingMode, flags);
}

[[visible]] ulong vf64_sqrt_round(ulong a, uint roundingMode) {
    uint flags = 0;
    return soft_sqrt64_status(a, roundingMode, flags);
}

[[visible]] ulong vf64_fma_round(
    ulong a, ulong b, ulong c, uint roundingMode
) {
    uint flags = 0;
    return soft_fma64_status(a, b, c, roundingMode, flags);
}

[[visible]] ulong vf64_remainder(ulong a, ulong b) {
    uint flags = 0;
    return soft_remainder64_status(a, b, flags);
}

[[visible]] ulong vf64_round_to_int(
    ulong a, uint roundingMode, bool exact
) {
    uint flags = 0;
    return soft_round_to_int64_status(a, roundingMode, exact, flags);
}

[[visible]] bool vf64_eq(ulong a, ulong b) {
    uint flags = 0;
    return soft_equal64_status(a, b, false, flags);
}

[[visible]] bool vf64_eq_signaling(ulong a, ulong b) {
    uint flags = 0;
    return soft_equal64_status(a, b, true, flags);
}

[[visible]] bool vf64_lt(ulong a, ulong b) {
    uint flags = 0;
    return soft_less64_status(a, b, false, false, flags);
}

[[visible]] bool vf64_le(ulong a, ulong b) {
    uint flags = 0;
    return soft_less64_status(a, b, true, false, flags);
}

[[visible]] bool vf64_lt_quiet(ulong a, ulong b) {
    uint flags = 0;
    return soft_less64_status(a, b, false, true, flags);
}

[[visible]] bool vf64_le_quiet(ulong a, ulong b) {
    uint flags = 0;
    return soft_less64_status(a, b, true, true, flags);
}

[[visible]] ulong vf64_ui32_to_f64(uint value, uint roundingMode) {
    uint flags = 0;
    return soft_uint_to_f64_status(ulong(value), false, roundingMode, flags);
}

[[visible]] ulong vf64_ui64_to_f64(ulong value, uint roundingMode) {
    uint flags = 0;
    return soft_uint_to_f64_status(value, false, roundingMode, flags);
}

[[visible]] ulong vf64_i32_to_f64(int value, uint roundingMode) {
    bool sign = value < 0;
    uint magnitude = sign ? uint(-(value + 1)) + 1u : uint(value);
    uint flags = 0;
    return soft_uint_to_f64_status(ulong(magnitude), sign, roundingMode, flags);
}

[[visible]] ulong vf64_i64_to_f64(long value, uint roundingMode) {
    bool sign = value < 0;
    ulong magnitude = sign ? ulong(-(value + 1l)) + 1ul : ulong(value);
    uint flags = 0;
    return soft_uint_to_f64_status(magnitude, sign, roundingMode, flags);
}

[[visible]] uint vf64_f64_to_ui32(
    ulong value, uint roundingMode, bool exact
) {
    uint flags = 0;
    return uint(soft_f64_to_int_status(
        value, roundingMode, exact, false, 32u, flags
    ));
}

[[visible]] ulong vf64_f64_to_ui64(
    ulong value, uint roundingMode, bool exact
) {
    uint flags = 0;
    return soft_f64_to_int_status(
        value, roundingMode, exact, false, 64u, flags
    );
}

[[visible]] int vf64_f64_to_i32(
    ulong value, uint roundingMode, bool exact
) {
    uint flags = 0;
    uint raw = uint(soft_f64_to_int_status(
        value, roundingMode, exact, true, 32u, flags
    ));
    return as_type<int>(raw);
}

[[visible]] long vf64_f64_to_i64(
    ulong value, uint roundingMode, bool exact
) {
    uint flags = 0;
    ulong raw = soft_f64_to_int_status(
        value, roundingMode, exact, true, 64u, flags
    );
    return as_type<long>(raw);
}

[[visible]] uint vf64_f64_to_f32(ulong value, uint roundingMode) {
    uint flags = 0;
    return uint(soft_f64_to_format_status(
        value, roundingMode, 8u, 23u, 127, flags
    ));
}

[[visible]] ushort vf64_f64_to_f16(ulong value, uint roundingMode) {
    uint flags = 0;
    return ushort(soft_f64_to_format_status(
        value, roundingMode, 5u, 10u, 15, flags
    ));
}

[[visible]] ulong vf64_f32_to_f64(uint raw) {
    uint flags = 0;
    return soft_format_to_f64_status(ulong(raw), 8u, 23u, 127, flags);
}

[[visible]] ulong vf64_f16_to_f64(ushort raw) {
    uint flags = 0;
    return soft_format_to_f64_status(ulong(raw), 5u, 10u, 15, flags);
}

[[visible]] ulong vf64_wide_add(ulong a, ulong b) {
    return wide_pack64(wide_add(wide_unpack64(a), wide_unpack64(b)));
}

[[visible]] ulong vf64_wide_sub(ulong a, ulong b) {
    return wide_pack64(wide_sub(wide_unpack64(a), wide_unpack64(b)));
}

[[visible]] ulong vf64_wide_mul(ulong a, ulong b) {
    return wide_pack64(wide_mul(wide_unpack64(a), wide_unpack64(b)));
}

[[visible]] ulong vf64_wide_div(ulong a, ulong b) {
    return wide_pack64(wide_div(wide_unpack64(a), wide_unpack64(b)));
}

[[visible]] ulong vf64_wide_sqrt(ulong a) {
    return wide_pack64(wide_sqrt(wide_unpack64(a)));
}

[[visible]] ulong vf64_wide_fma(ulong a, ulong b, ulong c) {
    return wide_pack64(wide_fma(
        wide_unpack64(a), wide_unpack64(b), wide_unpack64(c)
    ));
}
