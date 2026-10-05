// M9 correctly rounded binary64 exp2 and expm1, on the exp evaluation core.

// exp2(x) = 2^k exp(r ln2) with k = round(x) and r = x - k exact, |r| <= 1/2.
//
// t = r ln2 carries the 128-bit ln2 constant's error and one truncating
// product, a relative error below 2^-126 and so an absolute error below
// 2^-127.5 at |t| <= ln2/2. That perturbs exp(t) by under 2^-127.5 relative,
// on top of the polynomial's 2^-120, so the result is within 2^-119.9.
//
// Integer arguments give exact powers of two and are rounded exactly, which
// also covers x = -1075, the one argument whose result is exactly halfway
// between two binary64 values. exp2 of any other binary64 is irrational
// (Gelfond-Schneider), so no other result lies on the grid or a midpoint.
inline ulong soft_exp2_64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    uint exponentField = uint((a >> 52) & 0x7fful);
    ulong fraction = a & 0x000ffffffffffffful;
    bool sign = (a >> 63) != 0ul;

    if (exponentField == 0x7ffu) {
        if (fraction != 0ul) {
            if (soft_is_signaling_nan(a)) flags |= soft_flag_invalid;
            return soft_propagate_nan(a, a);
        }
        return sign ? 0ul : 0x7ff0000000000000ul;
    }
    if (exponentField == 0u && fraction == 0ul) return 0x3ff0000000000000ul;
    // |x| < 2^-60: exp2(x) = exp(x ln2) with |x ln2| < 2^-60 as well.
    if (exponentField < soft_exp_tiny_exponent_field) {
        return soft_exp_tiny(sign, roundingMode, flags);
    }
    // |x| >= 2048 overflows or lies far below half the smallest subnormal.
    if (exponentField >= 1034u) {
        flags |= soft_flag_inexact;
        if (!sign) {
            flags |= soft_flag_overflow;
            return soft_overflow_result(false, roundingMode);
        }
        flags |= soft_flag_underflow;
        return roundingMode == soft_round_max ? 1ul : 0ul;
    }

    soft_wide x = soft_wide_from_f64(a);
    int k = soft_wide_round_to_int(x);
    soft_wide r = soft_wide_sub(x, soft_wide_from_int(k));
    if (soft_wide_is_zero(r)) {
        return soft_wide_exact_to_f64_status(
            soft_wide_scale2(soft_wide_one(), k), roundingMode, flags
        );
    }
    soft_wide value = soft_wide_scale2(
        soft_exp_poly(soft_wide_mul(r, SOFT_LOG_LN2)), k
    );
    return soft_wide_to_f64_status(value, roundingMode, flags, certified);
}

// expm1(x) = exp(x) - 1.
//
// For |x| < 1/2 the cancellation in exp(x) - 1 would cost relative accuracy,
// so expm1 is summed directly: expm1(x) = x * sum_{n=0..28} x^n / (n+1)!, by
// Horner over the exp factorial table. The truncated tail is below 2^-136.7
// at |x| <= 1/2, the accumulator stays in [0.78, 1.3], and the 57 truncating
// operations keep the result within 2^-120, as for the exp polynomial.
//
// For 1/2 <= |x| the exp core is used and 1 subtracted. The exp error,
// 2^-120 of e^x, is amplified by e^x / |e^x - 1|, at most 2.55 for x >= 1/2
// and 1.55 for x <= -1/2; with the subtraction's 2^-127 the result is within
// 2^-118.6.
//
// Closed forms: for nonzero |x| < 2^-60, expm1(x) = x + x^2/2 + ... lies
// strictly above x and within 2^-61 |x| of it. For x <= -45, expm1(x) =
// -1 + e^x with 0 < e^x < 2^-64, strictly above -1 and far inside half an ulp.
// The direct series for |x| < 1/2, shared with tanh.
inline soft_wide soft_expm1_series(soft_wide x) {
    soft_wide accumulator = SOFT_EXP_RECIPROCAL_FACTORIAL[29];
    for (int term = 27; term >= 0; --term) {
        accumulator = soft_wide_add(
            SOFT_EXP_RECIPROCAL_FACTORIAL[term + 1],
            soft_wide_mul(x, accumulator)
        );
    }
    return soft_wide_mul(x, accumulator);
}

inline ulong soft_expm1_64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    uint exponentField = uint((a >> 52) & 0x7fful);
    ulong fraction = a & 0x000ffffffffffffful;
    ulong magnitude = a & 0x7ffffffffffffffful;
    bool sign = (a >> 63) != 0ul;

    if (exponentField == 0x7ffu) {
        if (fraction != 0ul) {
            if (soft_is_signaling_nan(a)) flags |= soft_flag_invalid;
            return soft_propagate_nan(a, a);
        }
        return sign ? 0xbff0000000000000ul : 0x7ff0000000000000ul;
    }
    if (magnitude == 0ul) return a;
    if (exponentField < soft_exp_tiny_exponent_field) {
        return soft_round_beside(a, true, roundingMode, flags);
    }
    if (sign && magnitude >= 0x4046800000000000ul) {  // x <= -45
        return soft_round_beside(0xbff0000000000000ul, true, roundingMode, flags);
    }
    if (!sign && exponentField >= 1033u) {  // x >= 1024
        flags |= soft_flag_inexact | soft_flag_overflow;
        return soft_overflow_result(false, roundingMode);
    }

    soft_wide value;
    if (magnitude < 0x3fe0000000000000ul) {  // |x| < 1/2
        value = soft_expm1_series(soft_wide_from_f64(a));
    } else {
        value = soft_wide_sub(soft_exp64_wide(a), soft_wide_one());
    }
    return soft_wide_to_f64_status(value, roundingMode, flags, certified);
}
