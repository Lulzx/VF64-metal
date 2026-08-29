inline float signed_float(float value, bool negative) {
    return negative ? -value : value;
}

// Decode IEEE binary64 storage into a canonical ~48-bit FP32 expansion.
// Finite values outside FP32's dynamic range are reported through rangeFlag;
// silently turning them into zero/Inf would violate the emulation contract.
inline emu_f64 unpack_binary64(ulong bits, thread bool &rangeFlag) {
    bool negative = (bits >> 63) != 0;
    uint exponent = uint((bits >> 52) & 0x7fful);
    ulong fraction = bits & 0x000ffffffffffffful;
    rangeFlag = false;

    if (exponent == 0x7ffu) {
        if (fraction == 0) {
            return make_emu(signed_float(INFINITY, negative), 0.0f);
        }
        uint payload = uint(fraction >> 29) & 0x003fffffu;
        float nanValue = as_type<float>(0x7fc00000u | payload);
        return make_emu(signed_float(nanValue, negative), 0.0f);
    }
    if (exponent == 0 && fraction == 0) {
        return make_emu(as_type<float>(negative ? 0x80000000u : 0u), 0.0f);
    }
    if (exponent == 0) {
        // Every binary64 subnormal is below the FP32 pair's dynamic range.
        rangeFlag = true;
        return make_emu(as_type<float>(negative ? 0x80000000u : 0u), 0.0f);
    }

    int unbiased = int(exponent) - 1023;
    if (unbiased > 127 || unbiased < -126) {
        rangeFlag = true;
        return make_emu(as_type<float>(negative ? 0x80000000u : 0u), 0.0f);
    }

    ulong mantissa = (1ul << 52) | fraction;
    if (unbiased == 127 &&
        mantissa > (ulong(0x00ffffffu) << 29)) {
        rangeFlag = true;
        return make_emu(signed_float(INFINITY, negative), 0.0f);
    }
    ulong top = mantissa >> 29;
    ulong tail = mantissa & ((1ul << 29) - 1ul);
    ulong halfway = 1ul << 28;
    if (tail > halfway || (tail == halfway && (top & 1ul) != 0)) {
        top += 1ul;
    }

    long remainder = long(mantissa) - long(top << 29);
    float hi = ldexp(float(top), unbiased - 23);
    if (!isfinite(hi)) {
        rangeFlag = true;
        return make_emu(signed_float(INFINITY, negative), 0.0f);
    }
    float lo = ldexp(float(remainder), unbiased - 52);
    return make_emu(signed_float(hi, negative), signed_float(lo, negative));
}

inline int float_unbiased_exponent(uint bits) {
    uint exponent = (bits >> 23) & 0xffu;
    return exponent == 0 ? -126 : int(exponent) - 127;
}

inline uint float_mantissa(uint bits) {
    uint exponent = (bits >> 23) & 0xffu;
    return exponent == 0 ? bits & 0x007fffffu
                         : (bits & 0x007fffffu) | 0x00800000u;
}

inline long signed_mantissa(uint bits) {
    long value = long(float_mantissa(bits));
    return (bits >> 31) != 0 ? -value : value;
}

inline ulong canonical_nan64(uint floatBits) {
    ulong sign = ulong(floatBits >> 31) << 63;
    ulong payload = ulong(floatBits & 0x003fffffu) << 29;
    return sign | 0x7ff8000000000000ul | payload;
}

inline ulong pack_binary64(emu_f64 input) {
    uint inputHiBits = as_type<uint>(input.hi);
    uint inputLoBits = as_type<uint>(input.lo);
    if ((inputHiBits & 0x7fffffffu) == 0 && (inputLoBits & 0x7fffffffu) == 0) {
        return ulong(inputHiBits >> 31) << 63;
    }
    emu_f64 a = canonicalize(input);
    uint hiBits = as_type<uint>(a.hi);
    uint hiExponent = (hiBits >> 23) & 0xffu;

    if (hiExponent == 0xffu) {
        if ((hiBits & 0x007fffffu) != 0) {
            return canonical_nan64(hiBits);
        }
        return (ulong(hiBits >> 31) << 63) | 0x7ff0000000000000ul;
    }
    if ((hiBits & 0x7fffffffu) == 0) {
        uint loBits = as_type<uint>(a.lo);
        if ((loBits & 0x7fffffffu) == 0) {
            return ulong(hiBits >> 31) << 63;
        }
        a.hi = a.lo;
        a.lo = 0.0f;
        hiBits = loBits;
    }

    uint loBits = as_type<uint>(a.lo);
    int hiE = float_unbiased_exponent(hiBits);
    long total = signed_mantissa(hiBits) << 29;

    if ((loBits & 0x7fffffffu) != 0) {
        int loE = float_unbiased_exponent(loBits);
        int shift = loE - hiE + 29;
        long loMantissa = signed_mantissa(loBits);
        if (shift >= 0 && shift < 39) {
            total += loMantissa << shift;
        } else if (shift < 0) {
            int right = -shift;
            if (right < 63) {
                total += loMantissa >> right;
            }
        }
    }

    bool negative = total < 0;
    ulong magnitude = negative ? ulong(-total) : ulong(total);
    if (magnitude == 0) {
        return negative ? (1ul << 63) : 0ul;
    }

    int topBit = 63 - int(clz(magnitude));
    int outputE = hiE - 52 + topBit;
    ulong significand;
    if (topBit > 52) {
        int right = topBit - 52;
        ulong discardedMask = (1ul << right) - 1ul;
        ulong discarded = magnitude & discardedMask;
        significand = magnitude >> right;
        ulong halfway = 1ul << (right - 1);
        if (discarded > halfway || (discarded == halfway && (significand & 1ul) != 0)) {
            significand += 1ul;
            if (significand == (1ul << 53)) {
                significand >>= 1;
                outputE += 1;
            }
        }
    } else {
        significand = magnitude << (52 - topBit);
    }

    if (outputE > 1023) {
        return (ulong(negative) << 63) | 0x7ff0000000000000ul;
    }
    // A nonzero FP32 limb is much larger than the binary64 normal threshold.
    uint outputExponent = uint(outputE + 1023);
    ulong fraction = significand & 0x000ffffffffffffful;
    return (ulong(negative) << 63) | (ulong(outputExponent) << 52) | fraction;
}

// -------------------------------------------------------------------------
// Integer software binary64. Unlike emu_f64, this path retains all 53 bits,
// the full binary64 exponent range, and subnormals. Arithmetic rounding is
// round-to-nearest, ties-to-even.
