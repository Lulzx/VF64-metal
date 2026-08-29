inline bool soft_is_nan(ulong a) {
    return (a & 0x7ff0000000000000ul) == 0x7ff0000000000000ul &&
           (a & 0x000ffffffffffffful) != 0;
}

inline bool soft_is_inf(ulong a) {
    return (a & 0x7ffffffffffffffful) == 0x7ff0000000000000ul;
}

inline ulong soft_propagate_nan(ulong a, ulong b) {
    ulong source = soft_is_nan(a) ? a : b;
    return source | 0x0008000000000000ul;
}

inline ulong shift_right_jam(ulong value, uint distance) {
    if (distance == 0) return value;
    if (distance < 64) {
        ulong discarded = value & ((1ul << distance) - 1ul);
        return (value >> distance) | ulong(discarded != 0);
    }
    return ulong(value != 0);
}

constant uint soft_round_near_even = 0;
constant uint soft_round_min_mag = 1;
constant uint soft_round_min = 2;
constant uint soft_round_max = 3;
constant uint soft_round_near_max_mag = 4;

inline bool soft_should_increment(
    bool sign, ulong roundBits, ulong significand, uint roundingMode
) {
    if (roundBits == 0) return false;
    if (roundingMode == soft_round_near_even) {
        return roundBits > 4ul ||
               (roundBits == 4ul && (significand & 1ul) != 0);
    }
    if (roundingMode == soft_round_near_max_mag) return roundBits >= 4ul;
    if (roundingMode == soft_round_min) return sign;
    if (roundingMode == soft_round_max) return !sign;
    return false;
}

inline ulong soft_overflow_result(bool sign, uint roundingMode) {
    bool toInfinity =
        roundingMode == soft_round_near_even ||
        roundingMode == soft_round_near_max_mag ||
        (roundingMode == soft_round_min && sign) ||
        (roundingMode == soft_round_max && !sign);
    ulong signBit = ulong(sign) << 63;
    return toInfinity
        ? signBit | 0x7ff0000000000000ul
        : signBit | 0x7feffffffffffffful;
}

inline ulong soft_round_pack(
    bool sign, int exponent, ulong significandWithRound, uint roundingMode
) {
    if (exponent <= 0) {
        uint distance = uint(1 - exponent);
        significandWithRound = shift_right_jam(significandWithRound, distance);
        exponent = 0;
    }

    ulong roundBits = significandWithRound & 7ul;
    ulong significand = significandWithRound >> 3;
    if (soft_should_increment(sign, roundBits, significand, roundingMode)) {
        significand += 1ul;
    }

    if (exponent == 0) {
        if (significand >= (1ul << 52)) exponent = 1;
    } else if (exponent == 1 && significand < (1ul << 52)) {
        // Subnormal operands use effective exponent 1 during alignment.
        exponent = 0;
    } else if (significand >= (1ul << 53)) {
        significand >>= 1;
        exponent += 1;
    }
    if (exponent >= 0x7ff) {
        return soft_overflow_result(sign, roundingMode);
    }
    if (significand == 0) return ulong(sign) << 63;
    return (ulong(sign) << 63) | (ulong(exponent) << 52) |
           (significand & 0x000ffffffffffffful);
}

inline ulong soft_add64_mode(ulong a, ulong b, uint roundingMode) {
    uint expAField = uint((a >> 52) & 0x7fful);
    uint expBField = uint((b >> 52) & 0x7fful);
    ulong fracA = a & 0x000ffffffffffffful;
    ulong fracB = b & 0x000ffffffffffffful;
    bool signA = (a >> 63) != 0;
    bool signB = (b >> 63) != 0;

    if (expAField == 0x7ffu || expBField == 0x7ffu) {
        if (soft_is_nan(a) || soft_is_nan(b)) return soft_propagate_nan(a, b);
        if (soft_is_inf(a) && soft_is_inf(b) && signA != signB) {
            return 0x7ff8000000000000ul;
        }
        return soft_is_inf(a) ? a : b;
    }

    int expA = expAField == 0 ? 1 : int(expAField);
    int expB = expBField == 0 ? 1 : int(expBField);
    ulong sigA = fracA | (expAField == 0 ? 0ul : (1ul << 52));
    ulong sigB = fracB | (expBField == 0 ? 0ul : (1ul << 52));

    // Order by magnitude so opposite-sign subtraction is nonnegative.
    if (expA < expB || (expA == expB && sigA < sigB)) {
        int te = expA; expA = expB; expB = te;
        ulong ts = sigA; sigA = sigB; sigB = ts;
        bool tb = signA; signA = signB; signB = tb;
    }

    sigA <<= 3;
    sigB <<= 3;
    sigB = shift_right_jam(sigB, uint(expA - expB));

    if (signA == signB) {
        ulong sum = sigA + sigB;
        if ((sum & (1ul << 56)) != 0) {
            sum = shift_right_jam(sum, 1);
            expA += 1;
        }
        return soft_round_pack(signA, expA, sum, roundingMode);
    }

    ulong difference = sigA - sigB;
    if (difference == 0) {
        // Exact cancellation is -0 only when rounding toward -infinity.
        return roundingMode == soft_round_min ? 0x8000000000000000ul : 0ul;
    }
    int leading = 63 - int(clz(difference));
    int left = 55 - leading;
    if (left > 0) {
        difference <<= uint(left);
        expA -= left;
    }
    return soft_round_pack(signA, expA, difference, roundingMode);
}

inline ulong soft_add64(ulong a, ulong b) {
    return soft_add64_mode(a, b, soft_round_near_even);
}

inline ulong soft_sub64_mode(ulong a, ulong b, uint roundingMode) {
    return soft_add64_mode(a, b ^ 0x8000000000000000ul, roundingMode);
}

inline ulong soft_sub64(ulong a, ulong b) {
    return soft_sub64_mode(a, b, soft_round_near_even);
}

struct soft_normalized {
    ulong significand;
    int exponent;
};

inline soft_normalized soft_normalize_operand(uint exponentField, ulong fraction) {
    if (exponentField != 0) {
        return soft_normalized{fraction | (1ul << 52), int(exponentField)};
    }
    int leading = 63 - int(clz(fraction));
    int left = 52 - leading;
    return soft_normalized{fraction << uint(left), 1 - left};
}

inline ulong round_shift_u128(
    ulong hi, ulong lo, int distance, bool sign, uint roundingMode
) {
    if (distance <= 0) return lo;
    ulong quotient;
    bool greaterHalf = false;
    bool exactlyHalf = false;
    if (distance < 64) {
        uint d = uint(distance);
        quotient = (hi << (64u - d)) | (lo >> d);
        ulong remainder = lo & ((1ul << d) - 1ul);
        ulong halfwayBit = 1ul << (d - 1u);
        greaterHalf = remainder > halfwayBit;
        exactlyHalf = remainder == halfwayBit;
    } else if (distance == 64) {
        quotient = hi;
        ulong halfwayBit = 1ul << 63;
        greaterHalf = lo > halfwayBit;
        exactlyHalf = lo == halfwayBit;
    } else if (distance < 128) {
        uint d = uint(distance - 64);
        quotient = hi >> d;
        ulong highRemainder = hi & ((1ul << d) - 1ul);
        ulong halfwayBit = 1ul << (d - 1u);
        greaterHalf = highRemainder > halfwayBit || (highRemainder == halfwayBit && lo != 0);
        exactlyHalf = highRemainder == halfwayBit && lo == 0;
    } else {
        quotient = 0ul;
        greaterHalf = false;
        exactlyHalf = false;
        bool inexact = hi != 0 || lo != 0;
        ulong syntheticRoundBits = inexact ? 1ul : 0ul;
        if (soft_should_increment(sign, syntheticRoundBits, quotient, roundingMode)) {
            quotient += 1ul;
        }
        return quotient;
    }
    ulong roundBits = greaterHalf ? 5ul : (exactlyHalf ? 4ul : 0ul);
    bool inexact = greaterHalf || exactlyHalf;
    if (!inexact) {
        if (distance < 64) {
            inexact = (lo & ((1ul << uint(distance)) - 1ul)) != 0;
        } else if (distance == 64) {
            inexact = lo != 0;
        } else {
            uint d = uint(distance - 64);
            inexact = (hi & ((1ul << d) - 1ul)) != 0 || lo != 0;
        }
        if (inexact) roundBits = 1ul;
    }
    if (soft_should_increment(sign, roundBits, quotient, roundingMode)) quotient += 1ul;
    return quotient;
}

inline ulong soft_mul64_mode(ulong a, ulong b, uint roundingMode) {
    bool sign = ((a ^ b) >> 63) != 0;
    uint expAField = uint((a >> 52) & 0x7fful);
    uint expBField = uint((b >> 52) & 0x7fful);
    ulong fracA = a & 0x000ffffffffffffful;
    ulong fracB = b & 0x000ffffffffffffful;

    if (expAField == 0x7ffu || expBField == 0x7ffu) {
        if (soft_is_nan(a) || soft_is_nan(b)) return soft_propagate_nan(a, b);
        bool zeroA = (a & 0x7ffffffffffffffful) == 0;
        bool zeroB = (b & 0x7ffffffffffffffful) == 0;
        if (zeroA || zeroB) return 0x7ff8000000000000ul;
        return (ulong(sign) << 63) | 0x7ff0000000000000ul;
    }
    if ((expAField == 0 && fracA == 0) || (expBField == 0 && fracB == 0)) {
        return ulong(sign) << 63;
    }

    soft_normalized na = soft_normalize_operand(expAField, fracA);
    soft_normalized nb = soft_normalize_operand(expBField, fracB);
    ulong lo = na.significand * nb.significand;
    ulong hi = mulhi(na.significand, nb.significand);
    int top = 127 - int(clz(hi));
    int exponent = na.exponent + nb.exponent - 1023 + (top - 104);
    int shift = top - 52;
    bool subnormal = exponent <= 0;
    if (subnormal) shift += 1 - exponent;
    ulong significand = round_shift_u128(hi, lo, shift, sign, roundingMode);

    if (subnormal) {
        if (significand >= (1ul << 52)) exponent = 1;
        else exponent = 0;
    } else if (significand >= (1ul << 53)) {
        significand >>= 1;
        exponent += 1;
    }
    if (exponent >= 0x7ff) {
        return soft_overflow_result(sign, roundingMode);
    }
    if (significand == 0) return ulong(sign) << 63;
    return (ulong(sign) << 63) | (ulong(exponent) << 52) |
           (significand & 0x000ffffffffffffful);
}

inline ulong soft_mul64(ulong a, ulong b) {
    return soft_mul64_mode(a, b, soft_round_near_even);
}

inline ulong soft_div64_mode(ulong a, ulong b, uint roundingMode) {
    bool sign = ((a ^ b) >> 63) != 0;
    uint expAField = uint((a >> 52) & 0x7fful);
    uint expBField = uint((b >> 52) & 0x7fful);
    ulong fracA = a & 0x000ffffffffffffful;
    ulong fracB = b & 0x000ffffffffffffful;
    bool zeroA = expAField == 0 && fracA == 0;
    bool zeroB = expBField == 0 && fracB == 0;

    if (soft_is_nan(a) || soft_is_nan(b)) return soft_propagate_nan(a, b);
    if (soft_is_inf(a)) {
        if (soft_is_inf(b)) return 0x7ff8000000000000ul;
        return (ulong(sign) << 63) | 0x7ff0000000000000ul;
    }
    if (soft_is_inf(b)) return ulong(sign) << 63;
    if (zeroB) {
        if (zeroA) return 0x7ff8000000000000ul;
        return (ulong(sign) << 63) | 0x7ff0000000000000ul;
    }
    if (zeroA) return ulong(sign) << 63;

    soft_normalized na = soft_normalize_operand(expAField, fracA);
    soft_normalized nb = soft_normalize_operand(expBField, fracB);
    int exponent = na.exponent - nb.exponent + 1023;
    ulong remainder = na.significand;
    if (remainder < nb.significand) {
        remainder <<= 1;
        exponent -= 1;
    }

    // Generate the hidden bit, 52 stored significand bits, and three rounding
    // bits. The residual is then jammed into the low bit as sticky state.
    ulong quotientWithRound = 0;
    for (uint bit = 0; bit < 56; ++bit) {
        quotientWithRound <<= 1;
        if (remainder >= nb.significand) {
            quotientWithRound |= 1ul;
            remainder -= nb.significand;
        }
        remainder <<= 1;
    }
    if (remainder != 0) quotientWithRound |= 1ul;
    return soft_round_pack(sign, exponent, quotientWithRound, roundingMode);
}

inline ulong soft_div64(ulong a, ulong b) {
    return soft_div64_mode(a, b, soft_round_near_even);
}

inline ulong soft_sqrt64_mode(ulong a, uint roundingMode) {
    uint exponentField = uint((a >> 52) & 0x7fful);
    ulong fraction = a & 0x000ffffffffffffful;
    bool sign = (a >> 63) != 0;

    if (soft_is_nan(a)) return a | 0x0008000000000000ul;
    if (soft_is_inf(a)) {
        return sign ? 0x7ff8000000000000ul : a;
    }
    if (exponentField == 0 && fraction == 0) return a;
    if (sign) return 0x7ff8000000000000ul;

    soft_normalized operand = soft_normalize_operand(exponentField, fraction);
    int unbiasedExponent = operand.exponent - 1023;
    ulong adjustedSignificand = operand.significand;
    if ((unbiasedExponent & 1) != 0) {
        adjustedSignificand <<= 1;
        unbiasedExponent -= 1;
    }

    // Compute floor(sqrt(adjustedSignificand << 58)). This is the normalized
    // 53-bit result plus three rounding bits. Feeding two radicand bits per
    // iteration keeps the partial remainder below 2^59, so ulong is enough.
    ulong rootWithRound = 0;
    ulong remainder = 0;
    for (uint pairIndex = 0; pairIndex < 56; ++pairIndex) {
        int radicandBit = 110 - int(pairIndex * 2);
        ulong pair = 0;
        if (radicandBit >= 58) {
            pair = (adjustedSignificand >> uint(radicandBit - 58)) & 3ul;
        }
        remainder = (remainder << 2) | pair;
        rootWithRound <<= 1;
        ulong trial = (rootWithRound << 1) | 1ul;
        if (remainder >= trial) {
            remainder -= trial;
            rootWithRound |= 1ul;
        }
    }
    if (remainder != 0) rootWithRound |= 1ul;
    int resultExponent = unbiasedExponent / 2 + 1023;
    return soft_round_pack(false, resultExponent, rootWithRound, roundingMode);
}

inline ulong soft_sqrt64(ulong a) {
    return soft_sqrt64_mode(a, soft_round_near_even);
}
