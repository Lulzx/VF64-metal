inline wide_f64 make_wide(emu_f64 significand, int exponent) {
    return wide_f64{significand, exponent, 0u};
}

inline bool wide_is_special(wide_f64 a) {
    return !isfinite(a.significand.hi);
}

inline bool wide_is_zero(wide_f64 a) {
    return emu_is_zero(a.significand);
}

inline wide_f64 wide_normalize(wide_f64 a) {
    if (wide_is_special(a) || wide_is_zero(a)) {
        a.exponent = 0;
        return a;
    }
    a.significand = canonicalize(a.significand);
    float magnitude = fabs(a.significand.hi);
    while (magnitude >= 2.0f) {
        a.significand.hi *= 0.5f;
        a.significand.lo *= 0.5f;
        a.exponent += 1;
        magnitude *= 0.5f;
    }
    while (magnitude < 1.0f) {
        a.significand.hi *= 2.0f;
        a.significand.lo *= 2.0f;
        a.exponent -= 1;
        magnitude *= 2.0f;
    }
    a.significand = canonicalize(a.significand);
    return a;
}

inline wide_f64 wide_unpack64(ulong bits) {
    bool negative = (bits >> 63) != 0;
    uint exponentField = uint((bits >> 52) & 0x7fful);
    ulong fraction = bits & 0x000ffffffffffffful;
    if (exponentField == 0x7ffu || (exponentField == 0 && fraction == 0)) {
        bool ignored;
        return make_wide(unpack_binary64(bits, ignored), 0);
    }

    soft_normalized operand = soft_normalize_operand(exponentField, fraction);
    ulong top = operand.significand >> 29;
    ulong tail = operand.significand & ((1ul << 29) - 1ul);
    float hi = float(top) * 0x1p-23f;
    float lo = float(tail) * 0x1p-52f;
    if (negative) {
        hi = -hi;
        lo = -lo;
    }
    return make_wide(canonicalize(make_emu(hi, lo)), operand.exponent - 1023);
}

inline ulong wide_round_shift_even(ulong value, uint distance) {
    if (distance == 0) return value;
    if (distance > 63) return 0ul;
    ulong quotient = value >> distance;
    ulong remainder = value & ((1ul << distance) - 1ul);
    ulong halfway = 1ul << (distance - 1u);
    if (remainder > halfway ||
        (remainder == halfway && (quotient & 1ul) != 0)) {
        quotient += 1ul;
    }
    return quotient;
}

inline ulong wide_pack64(wide_f64 input) {
    if (wide_is_special(input) || wide_is_zero(input)) {
        return pack_binary64(input.significand);
    }
    wide_f64 a = wide_normalize(input);
    ulong packedSignificand = pack_binary64(a.significand);
    bool negative = (packedSignificand >> 63) != 0;
    uint sourceExponent = uint((packedSignificand >> 52) & 0x7fful);
    ulong significand = (1ul << 52) |
        (packedSignificand & 0x000ffffffffffffful);
    int unbiased = int(sourceExponent) - 1023 + a.exponent;
    ulong sign = ulong(negative) << 63;
    if (unbiased > 1023) return sign | 0x7ff0000000000000ul;
    if (unbiased >= -1022) {
        return sign | (ulong(unbiased + 1023) << 52) |
            (significand & 0x000ffffffffffffful);
    }
    uint distance = uint(-1022 - unbiased);
    ulong subnormal = wide_round_shift_even(significand, distance);
    if (subnormal >= (1ul << 52)) return sign | (1ul << 52);
    return sign | subnormal;
}

inline wide_f64 wide_special_binary(wide_f64 a, wide_f64 b, uint operation) {
    float result = operation == 0
        ? a.significand.hi + b.significand.hi
        : (operation == 1
            ? a.significand.hi * b.significand.hi
            : a.significand.hi / b.significand.hi);
    return make_wide(make_emu(result, 0.0f), 0);
}

inline wide_f64 wide_add(wide_f64 a, wide_f64 b) {
    if (wide_is_special(a) || wide_is_special(b)) {
        return wide_special_binary(a, b, 0);
    }
    if (wide_is_zero(a)) return b;
    if (wide_is_zero(b)) return a;
    if (a.exponent < b.exponent) {
        wide_f64 temporary = a;
        a = b;
        b = temporary;
    }
    int difference = a.exponent - b.exponent;
    if (difference > 60) return a;
    emu_f64 scaledB = make_emu(
        ldexp(b.significand.hi, -difference),
        ldexp(b.significand.lo, -difference)
    );
    return wide_normalize(make_wide(add_ff(a.significand, scaledB), a.exponent));
}

inline wide_f64 wide_sub(wide_f64 a, wide_f64 b) {
    b.significand = neg_ff(b.significand);
    return wide_add(a, b);
}

inline wide_f64 wide_mul(wide_f64 a, wide_f64 b) {
    if (wide_is_special(a) || wide_is_special(b) ||
        wide_is_zero(a) || wide_is_zero(b)) {
        return wide_special_binary(a, b, 1);
    }
    return wide_normalize(make_wide(
        mul_ff(a.significand, b.significand), a.exponent + b.exponent
    ));
}

inline wide_f64 wide_div(wide_f64 a, wide_f64 b) {
    if (wide_is_special(a) || wide_is_special(b) ||
        wide_is_zero(a) || wide_is_zero(b)) {
        return wide_special_binary(a, b, 2);
    }
    return wide_normalize(make_wide(
        div_ff(a.significand, b.significand), a.exponent - b.exponent
    ));
}

inline wide_f64 wide_fma(wide_f64 a, wide_f64 b, wide_f64 c) {
    return wide_add(wide_mul(a, b), c);
}
