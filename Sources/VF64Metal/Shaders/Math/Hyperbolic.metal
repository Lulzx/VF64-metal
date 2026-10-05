// M9 correctly rounded binary64 sinh, cosh, tanh, asinh, acosh, and atanh, on
// the exp and log evaluation cores.
//
// sinh and cosh. For |x| < 1/2, sinh(x) = x * sum_{k=0..13} z^k / (2k+1)!
// with z = x^2 <= 1/4: the tail is below 2^-130.8 relative, every term is
// positive, and a running bound over the Horner steps gives under 2^-125.9.
// Above, with E = exp(|x|) within 2^-120 and 1/E within 2^-120 + 2^-125,
// sinh = (E - 1/E) / 2 amplifies by coth(|x|) <= coth(1/2) < 2.17, a result
// within 2^-118.8, and cosh = (E + 1/E) / 2 does not amplify, within 2^-119.9.
// The wide format has no overflow, so 1/2 <= |x| < 1024 is evaluated and
// rounded, which delivers overflow from the final rounding; |x| >= 1024
// overflows by range.
//
// tanh. For |x| < 1/4, tanh = E / (E + 2) with E = expm1(2|x|) on the direct
// series, within 2^-120, which the quotient carries to 2^-119.6. Above, with
// e = exp(2|x|), tanh = (e - 1) / (e + 1): a relative error d in e moves the
// result by 2e / (e^2 - 1) d, at most 1.92 d at e = exp(1/2), so with the
// division the result is within 2^-119. 2|x| is a binary64 value, so the exp
// reduction stays exact.
//
// asinh, acosh, and atanh are log1p(t) for a positive wide t formed without
// cancellation:
//
//     asinh |x| = log1p(|x| + x^2 / (1 + sqrt(1 + x^2))),
//     acosh x   = log1p(d + sqrt(d (x + 1))),  d = x - 1,
//     atanh |x| = log1p(2|x| / (1 - |x|)) / 2,
//
// d and 1 - |x| exact. A relative error d in t moves log1p(t) by at most d
// relative, because t / ((1 + t) log1p(t)) <= 1, so t's error of at most
// 2^-123.2 (asinh: two truncating sums, the square, the square root's
// 2^-124.7, the division's 2^-124.6) adds to log1p's 2^-121 and every
// inverse function stays within 2^-120.5.
//
// Closed forms, for nonzero |x| < 2^-27: sinh and atanh lie within x^2/3 of x
// away from zero, tanh and asinh within x^2/3 toward zero, all inside 2^-54
// relative, and cosh lies strictly between 1 and 1 + 2^-55. For |x| >= 22,
// 1 - |tanh x| < 2 e^-44 < 2^-62. Every other result of a nonzero argument
// is transcendental (Lindemann-Weierstrass), so never on the grid or a
// midpoint; acosh(1) = 0 is decided exactly.

// log1p(t) for a positive wide t, as soft_log1p64_certified: with e = 0, m - 1
// is t itself. 1 + t truncates by under 2^-127 once t is wide, which moves m + 1
// in the reduction by the same relative amount.
inline soft_wide soft_log1p_wide(soft_wide t) {
    int e;
    soft_wide m = soft_log_split(soft_wide_add(soft_wide_one(), t), e);
    soft_wide f = e == 0 ? t : soft_wide_sub(m, soft_wide_one());
    soft_wide result = soft_log_reduced(f, m);
    if (e != 0) {
        result = soft_wide_add(
            soft_wide_mul(soft_wide_from_int(e), SOFT_LOG_LN2), result
        );
    }
    return result;
}

inline bool soft_hyperbolic_nan(ulong a, thread ulong &result, thread uint &flags) {
    if (!soft_is_nan(a)) return false;
    if (soft_is_signaling_nan(a)) flags |= soft_flag_invalid;
    result = a | 0x0008000000000000ul;
    return true;
}

// |x| < 2^-27, nonzero.
constant uint soft_hyperbolic_tiny_exponent_field = 996u;

inline ulong soft_sinh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    ulong magnitude = a & 0x7ffffffffffffffful;
    uint exponentField = uint(magnitude >> 52);
    bool sign = (a >> 63) != 0ul;
    if (magnitude == 0ul || magnitude == 0x7ff0000000000000ul) return a;
    if (exponentField < soft_hyperbolic_tiny_exponent_field) {
        return soft_round_beside(a, !sign, roundingMode, flags);
    }
    if (exponentField >= 1033u) {  // |x| >= 1024
        flags |= soft_flag_overflow | soft_flag_inexact;
        return soft_overflow_result(sign, roundingMode);
    }
    soft_wide value;
    if (magnitude < 0x3fe0000000000000ul) {  // |x| < 1/2
        soft_wide x = soft_wide_from_f64(magnitude);
        soft_wide z = soft_wide_mul(x, x);
        soft_wide accumulator = SOFT_EXP_RECIPROCAL_FACTORIAL[27];
        for (int term = 12; term >= 0; --term) {
            accumulator = soft_wide_add(
                SOFT_EXP_RECIPROCAL_FACTORIAL[2 * term + 1], soft_wide_mul(z, accumulator)
            );
        }
        value = soft_wide_mul(x, accumulator);
    } else {
        soft_wide e = soft_exp64_wide(magnitude);
        value = soft_wide_scale2(soft_wide_sub(e, soft_wide_reciprocal(e)), -1);
    }
    return soft_wide_to_f64_status(
        soft_wide_negate_if(value, sign), roundingMode, flags, certified
    );
}

inline ulong soft_cosh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    ulong magnitude = a & 0x7ffffffffffffffful;
    uint exponentField = uint(magnitude >> 52);
    if (magnitude == 0ul) return 0x3ff0000000000000ul;
    if (magnitude == 0x7ff0000000000000ul) return magnitude;
    if (exponentField < soft_hyperbolic_tiny_exponent_field) {
        return soft_round_beside(0x3ff0000000000000ul, true, roundingMode, flags);
    }
    if (exponentField >= 1033u) {
        flags |= soft_flag_overflow | soft_flag_inexact;
        return soft_overflow_result(false, roundingMode);
    }
    soft_wide e = soft_exp64_wide(magnitude);
    soft_wide value = soft_wide_scale2(soft_wide_add(e, soft_wide_reciprocal(e)), -1);
    return soft_wide_to_f64_status(value, roundingMode, flags, certified);
}

inline ulong soft_tanh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    ulong magnitude = a & 0x7ffffffffffffffful;
    uint exponentField = uint(magnitude >> 52);
    bool sign = (a >> 63) != 0ul;
    ulong one = sign ? 0xbff0000000000000ul : 0x3ff0000000000000ul;
    if (magnitude == 0ul) return a;
    if (magnitude == 0x7ff0000000000000ul) return one;
    if (exponentField < soft_hyperbolic_tiny_exponent_field) {
        return soft_round_beside(a, sign, roundingMode, flags);
    }
    if (magnitude >= 0x4036000000000000ul) {  // |x| >= 22
        return soft_round_beside(one, sign, roundingMode, flags);
    }
    soft_wide value;
    if (magnitude < 0x3fd0000000000000ul) {  // |x| < 1/4
        soft_wide e = soft_expm1_series(soft_wide_from_f64(magnitude + 0x0010000000000000ul));
        value = soft_wide_div(e, soft_wide_add(e, soft_wide_scale2(soft_wide_one(), 1)));
    } else {
        soft_wide e = soft_exp64_wide(magnitude + 0x0010000000000000ul);  // exp(2|x|)
        value = soft_wide_div(
            soft_wide_sub(e, soft_wide_one()), soft_wide_add(e, soft_wide_one())
        );
    }
    return soft_wide_to_f64_status(
        soft_wide_negate_if(value, sign), roundingMode, flags, certified
    );
}

inline ulong soft_asinh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    ulong magnitude = a & 0x7ffffffffffffffful;
    uint exponentField = uint(magnitude >> 52);
    bool sign = (a >> 63) != 0ul;
    if (magnitude == 0ul || magnitude == 0x7ff0000000000000ul) return a;
    if (exponentField < soft_hyperbolic_tiny_exponent_field) {
        return soft_round_beside(a, sign, roundingMode, flags);
    }
    soft_wide one = soft_wide_one();
    soft_wide x = soft_wide_from_f64(magnitude);
    soft_wide square = soft_wide_mul(x, x);
    soft_wide t = soft_wide_add(x, soft_wide_div(
        square, soft_wide_add(one, soft_wide_sqrt(soft_wide_add(one, square)))
    ));
    return soft_wide_to_f64_status(
        soft_wide_negate_if(soft_log1p_wide(t), sign), roundingMode, flags, certified
    );
}

inline ulong soft_acosh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    if ((a >> 63) != 0ul || a < 0x3ff0000000000000ul) {
        flags |= soft_flag_invalid;  // x < 1, including -0 and -infinity
        return 0x7ff8000000000000ul;
    }
    if (a == 0x3ff0000000000000ul) return 0ul;
    if (a == 0x7ff0000000000000ul) return a;
    soft_wide one = soft_wide_one();
    soft_wide x = soft_wide_from_f64(a);
    soft_wide d = soft_wide_sub(x, one);
    soft_wide t = soft_wide_add(d, soft_wide_sqrt(soft_wide_mul(d, soft_wide_add(x, one))));
    return soft_wide_to_f64_status(soft_log1p_wide(t), roundingMode, flags, certified);
}

inline ulong soft_atanh64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    ulong special;
    if (soft_hyperbolic_nan(a, special, flags)) return special;
    ulong magnitude = a & 0x7ffffffffffffffful;
    uint exponentField = uint(magnitude >> 52);
    bool sign = (a >> 63) != 0ul;
    if (magnitude == 0ul) return a;
    if (magnitude == 0x3ff0000000000000ul) {
        flags |= soft_flag_infinite;
        return (a & 0x8000000000000000ul) | 0x7ff0000000000000ul;
    }
    if (magnitude > 0x3ff0000000000000ul) {
        flags |= soft_flag_invalid;
        return 0x7ff8000000000000ul;
    }
    if (exponentField < soft_hyperbolic_tiny_exponent_field) {
        return soft_round_beside(a, !sign, roundingMode, flags);
    }
    soft_wide x = soft_wide_from_f64(magnitude);
    soft_wide t = soft_wide_div(soft_wide_scale2(x, 1), soft_wide_sub(soft_wide_one(), x));
    return soft_wide_to_f64_status(
        soft_wide_negate_if(soft_wide_scale2(soft_log1p_wide(t), -1), sign),
        roundingMode, flags, certified
    );
}
