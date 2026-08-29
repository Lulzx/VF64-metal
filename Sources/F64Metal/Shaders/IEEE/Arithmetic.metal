inline bool soft_is_nan(ulong a) {
    return (a & 0x7ff0000000000000ul) == 0x7ff0000000000000ul &&
           (a & 0x000ffffffffffffful) != 0;
}

inline bool soft_is_inf(ulong a) {
    return (a & 0x7ffffffffffffffful) == 0x7ff0000000000000ul;
}

inline bool soft_is_signaling_nan(ulong a) {
    return soft_is_nan(a) && (a & 0x0008000000000000ul) == 0;
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
constant uint soft_flag_inexact = 1;
constant uint soft_flag_underflow = 2;
constant uint soft_flag_overflow = 4;
constant uint soft_flag_infinite = 8;
constant uint soft_flag_invalid = 16;

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

inline ulong soft_round_pack_status(
    bool sign, int exponent, ulong significandWithRound, uint roundingMode,
    thread uint &flags
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
        flags |= soft_flag_overflow | soft_flag_inexact;
        return soft_overflow_result(sign, roundingMode);
    }
    if (roundBits != 0) {
        flags |= soft_flag_inexact;
        if (exponent == 0) flags |= soft_flag_underflow;
    }
    if (significand == 0) return ulong(sign) << 63;
    return (ulong(sign) << 63) | (ulong(exponent) << 52) |
           (significand & 0x000ffffffffffffful);
}

inline ulong soft_round_pack(
    bool sign, int exponent, ulong significandWithRound, uint roundingMode
) {
    uint ignoredFlags = 0;
    return soft_round_pack_status(
        sign, exponent, significandWithRound, roundingMode, ignoredFlags
    );
}

inline ulong soft_add64_status(
    ulong a, ulong b, uint roundingMode, thread uint &flags
) {
    uint expAField = uint((a >> 52) & 0x7fful);
    uint expBField = uint((b >> 52) & 0x7fful);
    ulong fracA = a & 0x000ffffffffffffful;
    ulong fracB = b & 0x000ffffffffffffful;
    bool signA = (a >> 63) != 0;
    bool signB = (b >> 63) != 0;

    if (expAField == 0x7ffu || expBField == 0x7ffu) {
        if (soft_is_nan(a) || soft_is_nan(b)) {
            if (soft_is_signaling_nan(a) || soft_is_signaling_nan(b)) {
                flags |= soft_flag_invalid;
            }
            return soft_propagate_nan(a, b);
        }
        if (soft_is_inf(a) && soft_is_inf(b) && signA != signB) {
            flags |= soft_flag_invalid;
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
        return soft_round_pack_status(signA, expA, sum, roundingMode, flags);
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
    return soft_round_pack_status(
        signA, expA, difference, roundingMode, flags
    );
}

inline ulong soft_add64_mode(ulong a, ulong b, uint roundingMode) {
    uint ignoredFlags = 0;
    return soft_add64_status(a, b, roundingMode, ignoredFlags);
}

inline ulong soft_add64(ulong a, ulong b) {
    return soft_add64_mode(a, b, soft_round_near_even);
}

inline ulong soft_sub64_mode(ulong a, ulong b, uint roundingMode) {
    return soft_add64_mode(a, b ^ 0x8000000000000000ul, roundingMode);
}

inline ulong soft_sub64_status(
    ulong a, ulong b, uint roundingMode, thread uint &flags
) {
    return soft_add64_status(
        a, b ^ 0x8000000000000000ul, roundingMode, flags
    );
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

struct soft_u128 {
    ulong hi;
    ulong lo;
};

inline soft_u128 soft_add128(soft_u128 a, soft_u128 b) {
    ulong lo = a.lo + b.lo;
    return soft_u128{a.hi + b.hi + ulong(lo < a.lo), lo};
}

inline soft_u128 soft_sub128(soft_u128 a, soft_u128 b) {
    ulong lo = a.lo - b.lo;
    return soft_u128{a.hi - b.hi - ulong(a.lo < b.lo), lo};
}

inline soft_u128 soft_shift_right_jam128(soft_u128 a, uint distance) {
    if (distance == 0) return a;
    if (distance < 64) {
        ulong discarded = a.lo & ((1ul << distance) - 1ul);
        return soft_u128{
            a.hi >> distance,
            (a.hi << (64u - distance)) | (a.lo >> distance) |
                ulong(discarded != 0)
        };
    }
    if (distance == 64) {
        return soft_u128{0, a.hi | ulong(a.lo != 0)};
    }
    if (distance < 128) {
        uint shift = distance - 64;
        ulong discarded = a.hi & ((1ul << shift) - 1ul);
        return soft_u128{
            0,
            (a.hi >> shift) | ulong(discarded != 0 || a.lo != 0)
        };
    }
    return soft_u128{0, ulong(a.hi != 0 || a.lo != 0)};
}

inline soft_u128 soft_shift_left128(soft_u128 a, uint distance) {
    if (distance == 0) return a;
    return soft_u128{
        (a.hi << distance) | (a.lo >> (64u - distance)),
        a.lo << distance
    };
}

inline ulong soft_finish_fma(
    bool sign, int exponent, ulong significand, uint roundingMode
) {
    return soft_round_pack(
        sign, exponent + 1, shift_right_jam(significand, 7), roundingMode
    );
}

inline ulong soft_fma64_mode(ulong a, ulong b, ulong c, uint roundingMode) {
    bool signProduct = ((a ^ b) >> 63) != 0;
    bool signC = (c >> 63) != 0;
    uint expAField = uint((a >> 52) & 0x7fful);
    uint expBField = uint((b >> 52) & 0x7fful);
    uint expCField = uint((c >> 52) & 0x7fful);
    ulong fracA = a & 0x000ffffffffffffful;
    ulong fracB = b & 0x000ffffffffffffful;
    ulong fracC = c & 0x000ffffffffffffful;
    bool zeroA = expAField == 0 && fracA == 0;
    bool zeroB = expBField == 0 && fracB == 0;

    if (soft_is_nan(a) || soft_is_nan(b)) {
        ulong ab = soft_propagate_nan(a, b);
        return soft_is_nan(c) ? soft_propagate_nan(ab, c) : ab;
    }
    if (soft_is_nan(c)) return c | 0x0008000000000000ul;

    if (soft_is_inf(a) || soft_is_inf(b)) {
        if (zeroA || zeroB) return 0x7ff8000000000000ul;
        ulong productInfinity =
            (ulong(signProduct) << 63) | 0x7ff0000000000000ul;
        if (soft_is_inf(c) && signProduct != signC) {
            return 0x7ff8000000000000ul;
        }
        return productInfinity;
    }
    if (soft_is_inf(c)) return c;
    if (zeroA || zeroB) {
        bool zeroC = expCField == 0 && fracC == 0;
        if (zeroC && signProduct != signC) {
            return roundingMode == soft_round_min
                ? 0x8000000000000000ul : 0ul;
        }
        return c;
    }

    soft_normalized na = soft_normalize_operand(expAField, fracA);
    soft_normalized nb = soft_normalize_operand(expBField, fracB);
    int exponent = na.exponent + nb.exponent - 0x3fe;
    ulong sigA = na.significand << 10;
    ulong sigB = nb.significand << 10;
    soft_u128 product = soft_u128{mulhi(sigA, sigB), sigA * sigB};
    if (product.hi < 0x2000000000000000ul) {
        exponent -= 1;
        product = soft_add128(product, product);
    }

    bool zeroC = expCField == 0 && fracC == 0;
    if (zeroC) {
        exponent -= 1;
        ulong significand = (product.hi << 1) | ulong(product.lo != 0);
        return soft_finish_fma(
            signProduct, exponent, significand, roundingMode
        );
    }

    soft_normalized nc = soft_normalize_operand(expCField, fracC);
    ulong sigC = nc.significand << 9;
    int exponentDifference = exponent - nc.exponent;
    soft_u128 alignedC = soft_u128{0, 0};
    if (exponentDifference < 0) {
        exponent = nc.exponent;
        if (signProduct == signC || exponentDifference < -1) {
            product.hi = shift_right_jam(
                product.hi, uint(-exponentDifference)
            );
        } else {
            product = soft_shift_right_jam128(product, 1);
        }
    } else if (exponentDifference > 0) {
        alignedC = soft_shift_right_jam128(
            soft_u128{sigC, 0}, uint(exponentDifference)
        );
    }

    ulong significand;
    bool signResult = signProduct;
    if (signProduct == signC) {
        if (exponentDifference <= 0) {
            significand = (sigC + product.hi) | ulong(product.lo != 0);
        } else {
            product = soft_add128(product, alignedC);
            significand = product.hi | ulong(product.lo != 0);
        }
        if (significand < 0x4000000000000000ul) {
            exponent -= 1;
            significand <<= 1;
        }
    } else {
        if (exponentDifference < 0) {
            signResult = signC;
            product = soft_sub128(soft_u128{sigC, 0}, product);
        } else if (exponentDifference == 0) {
            product.hi -= sigC;
            if ((product.hi | product.lo) == 0) {
                return roundingMode == soft_round_min
                    ? 0x8000000000000000ul : 0ul;
            }
            if ((product.hi >> 63) != 0) {
                signResult = !signResult;
                product = soft_sub128(soft_u128{0, 0}, product);
            }
        } else {
            product = soft_sub128(product, alignedC);
        }

        if (product.hi == 0) {
            exponent -= 64;
            product.hi = product.lo;
            product.lo = 0;
        }
        int shiftDistance = int(clz(product.hi)) - 1;
        if (shiftDistance < 0) {
            significand = shift_right_jam(product.hi, 1);
            exponent += 1;
        } else {
            exponent -= shiftDistance;
            product = soft_shift_left128(product, uint(shiftDistance));
            significand = product.hi;
        }
        significand |= ulong(product.lo != 0);
    }
    return soft_finish_fma(signResult, exponent, significand, roundingMode);
}

inline ulong soft_fma64(ulong a, ulong b, ulong c) {
    return soft_fma64_mode(a, b, c, soft_round_near_even);
}
