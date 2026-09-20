// M9 wide evaluation core.
//
// A soft_wide value is (-1)^sign * significand * 2^(exponent - 128) with the
// significand normalized to [2^127, 2^128). Zero is significand 0 with
// exponent 0. There are no infinities, NaNs, or subnormals in this format:
// callers handle every special case in binary64 before entering, and the
// exponent is a plain int, so no intermediate can overflow or underflow.
//
// Every operation truncates toward zero, so each carries at most one unit in
// the last place of the 128-bit significand, that is a relative error below
// 2^-127. This is the internal format M9 evaluates in; it never crosses an
// observable boundary. Results return to binary64 through one final rounding
// in soft_wide_to_f64_status, which reuses the M2 rounding, subnormal,
// overflow, and exception behavior rather than restating it.

struct soft_wide {
    ulong hi;
    ulong lo;
    int exponent;
    bool sign;
};

inline bool soft_wide_is_zero(soft_wide a) {
    return (a.hi | a.lo) == 0ul;
}

inline soft_wide soft_wide_zero() {
    return soft_wide{0ul, 0ul, 0, false};
}

// Shift right without jamming. M9 needs plain truncation so that the sign of
// each operation's error stays known; the sticky bit sits in the final
// rounding step instead.
inline soft_u128 soft_shift_right128(soft_u128 a, uint distance) {
    if (distance == 0u) return a;
    if (distance < 64u) {
        return soft_u128{a.hi >> distance, (a.hi << (64u - distance)) | (a.lo >> distance)};
    }
    if (distance == 64u) return soft_u128{0ul, a.hi};
    if (distance < 128u) return soft_u128{0ul, a.hi >> (distance - 64u)};
    return soft_u128{0ul, 0ul};
}

inline bool soft_u128_less(soft_u128 a, soft_u128 b) {
    return a.hi < b.hi || (a.hi == b.hi && a.lo < b.lo);
}

inline soft_wide soft_wide_normalize(soft_u128 significand, int exponent, bool sign) {
    if ((significand.hi | significand.lo) == 0ul) return soft_wide_zero();
    if (significand.hi == 0ul) {
        significand.hi = significand.lo;
        significand.lo = 0ul;
        exponent -= 64;
    }
    uint leading = uint(clz(significand.hi));
    if (leading != 0u) {
        significand = soft_shift_left128(significand, leading);
        exponent -= int(leading);
    }
    return soft_wide{significand.hi, significand.lo, exponent, sign};
}

// Top 128 bits of a 256-bit product. Discarded bits are never rounded in, so
// the product is at most one unit in the last place below the exact value.
inline soft_u128 soft_wide_mul128(soft_u128 a, soft_u128 b) {
    ulong tail = mulhi(a.lo, b.lo);
    ulong crossLow0 = a.hi * b.lo;
    ulong crossHigh0 = mulhi(a.hi, b.lo);
    ulong crossLow1 = a.lo * b.hi;
    ulong crossHigh1 = mulhi(a.lo, b.hi);

    ulong partial = tail + crossLow0;
    ulong carry = ulong(partial < tail);
    ulong partial2 = partial + crossLow1;
    carry += ulong(partial2 < partial);

    soft_u128 result = soft_u128{mulhi(a.hi, b.hi), a.hi * b.hi};
    result = soft_add128(result, soft_u128{0ul, crossHigh0});
    result = soft_add128(result, soft_u128{0ul, crossHigh1});
    result = soft_add128(result, soft_u128{0ul, carry});
    return result;
}

inline soft_wide soft_wide_mul(soft_wide a, soft_wide b) {
    if (soft_wide_is_zero(a) || soft_wide_is_zero(b)) return soft_wide_zero();
    soft_u128 product = soft_wide_mul128(
        soft_u128{a.hi, a.lo}, soft_u128{b.hi, b.lo}
    );
    // Both significands are in [2^127, 2^128), so the retained product is in
    // [2^126, 2^128) and normalization shifts left by at most one.
    return soft_wide_normalize(product, a.exponent + b.exponent, a.sign != b.sign);
}

inline soft_wide soft_wide_add(soft_wide a, soft_wide b) {
    if (soft_wide_is_zero(a)) return b;
    if (soft_wide_is_zero(b)) return a;

    soft_wide large = a;
    soft_wide small = b;
    if (b.exponent > a.exponent ||
        (b.exponent == a.exponent &&
         soft_u128_less(soft_u128{a.hi, a.lo}, soft_u128{b.hi, b.lo}))) {
        large = b;
        small = a;
    }

    int distance = large.exponent - small.exponent;
    if (distance >= 128) return large;

    soft_u128 largeSig = soft_u128{large.hi, large.lo};
    soft_u128 smallSig = soft_shift_right128(
        soft_u128{small.hi, small.lo}, uint(distance)
    );

    if (large.sign == small.sign) {
        soft_u128 sum = soft_add128(largeSig, smallSig);
        if (sum.hi < largeSig.hi) {  // carried out of bit 127
            sum = soft_shift_right128(sum, 1u);
            sum.hi |= 1ul << 63;
            return soft_wide{sum.hi, sum.lo, large.exponent + 1, large.sign};
        }
        return soft_wide{sum.hi, sum.lo, large.exponent, large.sign};
    }
    soft_u128 difference = soft_sub128(largeSig, smallSig);
    return soft_wide_normalize(difference, large.exponent, large.sign);
}

inline soft_wide soft_wide_sub(soft_wide a, soft_wide b) {
    b.sign = !b.sign;
    return soft_wide_add(a, b);
}

inline soft_wide soft_wide_scale2(soft_wide a, int power) {
    if (soft_wide_is_zero(a)) return a;
    a.exponent += power;
    return a;
}

// Exact for every finite binary64 value, including subnormals.
inline soft_wide soft_wide_from_f64(ulong bits) {
    uint exponentField = uint((bits >> 52) & 0x7fful);
    ulong fraction = bits & 0x000ffffffffffffful;
    bool sign = (bits >> 63) != 0ul;
    if (exponentField == 0u && fraction == 0ul) return soft_wide_zero();
    soft_normalized normalized = soft_normalize_operand(exponentField, fraction);
    // soft_normalize_operand returns a 53-bit significand whose value is
    // significand * 2^(exponent - 1075). Placing it at bit 64 of the wide
    // significand scales it by 2^64, so the wide exponent is
    // (exponent - 1075) + 64 = exponent - 1011. The significand is placed in
    // the high limb directly: soft_shift_left128 by 64 would be a shift of a
    // 64-bit limb by its own width, which is undefined and on Apple GPUs
    // leaves the operand in place.
    soft_u128 significand = soft_u128{normalized.significand, 0ul};
    return soft_wide_normalize(significand, normalized.exponent - 1011, sign);
}

inline soft_wide soft_wide_from_int(int value) {
    if (value == 0) return soft_wide_zero();
    bool sign = value < 0;
    ulong magnitude = ulong(sign ? -value : value);
    return soft_wide_normalize(soft_u128{0ul, magnitude}, 128, sign);
}

// Nearest integer, ties away from zero. Callers guarantee |a| < 2^62.
inline int soft_wide_round_to_int(soft_wide a) {
    if (soft_wide_is_zero(a) || a.exponent <= -1) return 0;
    if (a.exponent == 0) return a.sign ? -1 : 1;  // magnitude in [0.5, 1)
    uint shift = uint(128 - a.exponent);
    soft_u128 truncated = soft_shift_right128(soft_u128{a.hi, a.lo}, shift);
    ulong magnitude = truncated.lo;
    soft_u128 halfway = soft_shift_right128(soft_u128{a.hi, a.lo}, shift - 1u);
    magnitude += (halfway.lo & 1ul);
    int result = int(magnitude);
    return a.sign ? -result : result;
}

// Certification test.
//
// Let W be the computed wide value and V the exact value, with
// |W - V| <= epsilon * |W| for the epsilon the caller has proven for its
// evaluation. If W is farther than epsilon * |W| from the rounding boundary
// that decides this result, then V rounds where W rounds, and the returned
// binary64 is correctly rounded for V. This function reports that condition
// directly instead of assuming a published worst case exists.
//
// Distances are measured in units of the wide significand, where |W| < 2^128,
// so a margin of 2^12 units covers every epsilon up to 2^-116.
constant ulong soft_wide_certify_margin = 4096ul;

inline soft_u128 soft_u128_abs_diff(soft_u128 a, soft_u128 b) {
    return soft_u128_less(a, b) ? soft_sub128(b, a) : soft_sub128(a, b);
}

inline bool soft_u128_above(soft_u128 a, ulong margin) {
    return a.hi != 0ul || a.lo > margin;
}

inline bool soft_wide_certified(soft_u128 significand, int shift, uint roundingMode) {
    bool nearest = roundingMode == soft_round_near_even ||
                   roundingMode == soft_round_near_max_mag;
    // Beyond 129 discarded bits every boundary is at least 2^127 units away
    // from a significand that is itself below 2^128.
    if (shift >= 130) return true;
    if (shift <= 0) return true;  // no bits discarded; the result is exact

    if (shift >= 128) {
        if (shift == 128) {
            soft_u128 halfway = soft_u128{1ul << 63, 0ul};
            if (nearest) {
                return soft_u128_above(soft_u128_abs_diff(significand, halfway), soft_wide_certify_margin);
            }
            soft_u128 toTop = soft_sub128(soft_u128{0ul, 0ul}, significand);
            return soft_u128_above(significand, soft_wide_certify_margin) &&
                   soft_u128_above(toTop, soft_wide_certify_margin);
        }
        // shift == 129: the halfway point is 2^128, the grid points are 0 and
        // 2^129, and the significand is at least 2^127 away from both.
        if (nearest) {
            soft_u128 toHalf = soft_sub128(soft_u128{0ul, 0ul}, significand);
            return soft_u128_above(toHalf, soft_wide_certify_margin);
        }
        return true;
    }

    uint discarded = uint(shift);
    soft_u128 residual;
    if (discarded < 64u) {
        residual = soft_u128{0ul, significand.lo & ((1ul << discarded) - 1ul)};
    } else if (discarded == 64u) {
        residual = soft_u128{0ul, significand.lo};
    } else {
        residual = soft_u128{significand.hi & ((1ul << (discarded - 64u)) - 1ul), significand.lo};
    }

    soft_u128 halfway = discarded - 1u < 64u
        ? soft_u128{0ul, 1ul << (discarded - 1u)}
        : soft_u128{1ul << (discarded - 65u), 0ul};
    if (nearest) {
        return soft_u128_above(soft_u128_abs_diff(residual, halfway), soft_wide_certify_margin);
    }
    soft_u128 grid = discarded < 64u
        ? soft_u128{0ul, 1ul << discarded}
        : soft_u128{1ul << (discarded - 64u), 0ul};
    soft_u128 toGrid = soft_sub128(grid, residual);
    return soft_u128_above(residual, soft_wide_certify_margin) &&
           soft_u128_above(toGrid, soft_wide_certify_margin);
}

// Final rounding to binary64. Mirrors the M2 multiply tail: the same rounding
// modes, the same subnormal handling, the same overflow result, and
// after-rounding tininess.
inline ulong soft_wide_to_f64_status(
    soft_wide a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    if (soft_wide_is_zero(a)) {
        certified = true;
        return ulong(a.sign) << 63;
    }
    int exponent = a.exponent + 1022;
    int shift = 75;
    bool subnormal = exponent <= 0;
    if (subnormal) shift += 1 - exponent;

    certified = certified &&
        soft_wide_certified(soft_u128{a.hi, a.lo}, shift, roundingMode);

    ulong significand;
    bool inexact;
    if (shift >= 128) {
        // round_shift_u128_status treats every distance of 128 or more as
        // below the halfway point. That is right for its callers, whose
        // 128-bit operand is a product sitting low in the word, but wrong
        // here: a soft_wide significand is normalized to bit 127, so a
        // distance of exactly 128 puts the value at or above halfway.
        ulong roundBits;
        if (shift == 128) {
            bool aboveHalf = a.hi > (1ul << 63) || a.lo != 0ul;
            roundBits = aboveHalf ? 5ul : 4ul;
        } else {
            roundBits = 1ul;  // nonzero, strictly below halfway
        }
        significand = soft_should_increment(a.sign, roundBits, 0ul, roundingMode)
            ? 1ul : 0ul;
        inexact = true;
    } else {
        bool aboveHalf = false;
        inexact = false;
        significand = round_shift_u128_status(
            a.hi, a.lo, shift, a.sign, roundingMode, inexact, aboveHalf
        );
    }

    if (subnormal) {
        exponent = significand >= (1ul << 52) ? 1 : 0;
    } else if (significand >= (1ul << 53)) {
        significand >>= 1;
        exponent += 1;
    }
    if (exponent >= 0x7ff) {
        flags |= soft_flag_overflow | soft_flag_inexact;
        return soft_overflow_result(a.sign, roundingMode);
    }
    if (inexact) {
        flags |= soft_flag_inexact;
        // Tininess after rounding: the delivered result is subnormal.
        if (exponent == 0) flags |= soft_flag_underflow;
    }
    if (significand == 0ul) return ulong(a.sign) << 63;
    return (ulong(a.sign) << 63) | (ulong(exponent) << 52) |
           (significand & 0x000ffffffffffffful);
}
