// M9 192-bit evaluation format, for functions whose error budget a 128-bit
// significand cannot meet. pow is the user: y log2(x) amplifies the relative
// error of log2 by up to |y log2 x| / |log2 m|, which reaches 2^11.
//
// A soft_wide3 value is (-1)^sign * significand * 2^(exponent - 192) with the
// significand normalized to [2^191, 2^192); zero is significand 0, exponent
// 0. As in soft_wide, every operation truncates toward zero, so each carries
// at most one unit in the last place, a relative error below 2^-191, and no
// intermediate can overflow or underflow.

struct soft_wide3 {
    ulong w2, w1, w0;  // most significant limb first
    int exponent;
    bool sign;
};

inline bool soft_wide3_is_zero(soft_wide3 a) {
    return (a.w2 | a.w1 | a.w0) == 0ul;
}

inline soft_wide3 soft_wide3_zero() {
    return soft_wide3{0ul, 0ul, 0ul, 0, false};
}

// Shifts of a three-limb significand by any distance, never shifting a 64-bit
// limb by 64.
inline soft_wide3 soft_wide3_shift_left_raw(soft_wide3 a, uint distance) {
    ulong limbs[3] = {a.w0, a.w1, a.w2};
    ulong shifted[3] = {0ul, 0ul, 0ul};
    uint whole = distance / 64u;
    uint bits = distance % 64u;
    for (uint index = 0; index < 3u; ++index) {
        if (index < whole) continue;
        ulong value = limbs[index - whole] << bits;
        if (bits != 0u && index - whole >= 1u) {
            value |= limbs[index - whole - 1u] >> (64u - bits);
        }
        shifted[index] = value;
    }
    a.w0 = shifted[0];
    a.w1 = shifted[1];
    a.w2 = shifted[2];
    return a;
}

inline soft_wide3 soft_wide3_shift_right_raw(soft_wide3 a, uint distance) {
    ulong limbs[3] = {a.w0, a.w1, a.w2};
    ulong shifted[3] = {0ul, 0ul, 0ul};
    uint whole = distance / 64u;
    uint bits = distance % 64u;
    for (uint index = 0; index < 3u; ++index) {
        uint source = index + whole;
        if (source >= 3u) continue;
        ulong value = limbs[source] >> bits;
        if (bits != 0u && source + 1u < 3u) {
            value |= limbs[source + 1u] << (64u - bits);
        }
        shifted[index] = value;
    }
    a.w0 = shifted[0];
    a.w1 = shifted[1];
    a.w2 = shifted[2];
    return a;
}

inline soft_wide3 soft_wide3_normalize(soft_wide3 a) {
    if (soft_wide3_is_zero(a)) return soft_wide3_zero();
    uint leading = a.w2 != 0ul ? uint(clz(a.w2))
        : a.w1 != 0ul ? 64u + uint(clz(a.w1)) : 128u + uint(clz(a.w0));
    if (leading != 0u) {
        a = soft_wide3_shift_left_raw(a, leading);
        a.exponent -= int(leading);
    }
    return a;
}

inline bool soft_wide3_significand_less(soft_wide3 a, soft_wide3 b) {
    if (a.w2 != b.w2) return a.w2 < b.w2;
    if (a.w1 != b.w1) return a.w1 < b.w1;
    return a.w0 < b.w0;
}

// Top 192 bits of the 384-bit product, discarded bits never rounded in.
inline soft_wide3 soft_wide3_mul(soft_wide3 a, soft_wide3 b) {
    if (soft_wide3_is_zero(a) || soft_wide3_is_zero(b)) return soft_wide3_zero();
    ulong left[3] = {a.w0, a.w1, a.w2};
    ulong right[3] = {b.w0, b.w1, b.w2};
    ulong product[6] = {0ul, 0ul, 0ul, 0ul, 0ul, 0ul};
    for (uint i = 0; i < 3u; ++i) {
        ulong carry = 0ul;
        for (uint j = 0; j < 3u; ++j) {
            ulong low = left[i] * right[j];
            ulong high = mulhi(left[i], right[j]);
            ulong sum = product[i + j] + low;
            high += sum < low ? 1ul : 0ul;
            sum += carry;
            high += sum < carry ? 1ul : 0ul;
            product[i + j] = sum;
            carry = high;
        }
        product[i + 3u] = carry;
    }
    soft_wide3 result = soft_wide3{
        product[5], product[4], product[3], a.exponent + b.exponent,
        a.sign != b.sign
    };
    // The product of two significands in [2^191, 2^192) keeps its top bit in
    // one of the two highest positions.
    return soft_wide3_normalize(result);
}

inline soft_wide3 soft_wide3_add(soft_wide3 a, soft_wide3 b) {
    if (soft_wide3_is_zero(a)) return b;
    if (soft_wide3_is_zero(b)) return a;
    soft_wide3 large = a;
    soft_wide3 small = b;
    if (b.exponent > a.exponent ||
        (b.exponent == a.exponent && soft_wide3_significand_less(a, b))) {
        large = b;
        small = a;
    }
    int distance = large.exponent - small.exponent;
    if (distance >= 192) return large;
    small = soft_wide3_shift_right_raw(small, uint(distance));

    soft_wide3 result = large;
    if (large.sign == small.sign) {
        ulong sum0 = large.w0 + small.w0;
        ulong carry = sum0 < large.w0 ? 1ul : 0ul;
        ulong partial1 = large.w1 + small.w1;
        ulong carry1 = partial1 < large.w1 ? 1ul : 0ul;
        ulong sum1 = partial1 + carry;
        carry1 += sum1 < partial1 ? 1ul : 0ul;
        ulong partial2 = large.w2 + small.w2;
        ulong carry2 = partial2 < large.w2 ? 1ul : 0ul;
        ulong sum2 = partial2 + carry1;
        carry2 += sum2 < partial2 ? 1ul : 0ul;
        result.w0 = sum0;
        result.w1 = sum1;
        result.w2 = sum2;
        if (carry2 != 0ul) {
            result = soft_wide3_shift_right_raw(result, 1u);
            result.w2 |= 1ul << 63;
            result.exponent += 1;
        }
        return result;
    }
    ulong borrow0 = large.w0 < small.w0 ? 1ul : 0ul;
    result.w0 = large.w0 - small.w0;
    ulong difference1 = large.w1 - small.w1;
    ulong borrow1 = large.w1 < small.w1 ? 1ul : 0ul;
    borrow1 += difference1 < borrow0 ? 1ul : 0ul;
    result.w1 = difference1 - borrow0;
    result.w2 = large.w2 - small.w2 - borrow1;
    return soft_wide3_normalize(result);
}

inline soft_wide3 soft_wide3_sub(soft_wide3 a, soft_wide3 b) {
    b.sign = !b.sign;
    return soft_wide3_add(a, b);
}

inline soft_wide3 soft_wide3_scale2(soft_wide3 a, int power) {
    if (!soft_wide3_is_zero(a)) a.exponent += power;
    return a;
}

// Exact: a 128-bit significand fits in the top two limbs.
inline soft_wide3 soft_wide3_from_wide(soft_wide a) {
    return soft_wide3{a.hi, a.lo, 0ul, a.exponent, a.sign};
}

// Truncates the low limb: a relative error below 2^-127.
inline soft_wide soft_wide3_to_wide(soft_wide3 a) {
    return soft_wide{a.w2, a.w1, a.exponent, a.sign};
}

inline soft_wide3 soft_wide3_from_f64(ulong bits) {
    return soft_wide3_from_wide(soft_wide_from_f64(bits));
}

inline soft_wide3 soft_wide3_from_int(int value) {
    return soft_wide3_from_wide(soft_wide_from_int(value));
}

inline soft_wide3 soft_wide3_one() {
    return soft_wide3{1ul << 63, 0ul, 0ul, 1, false};
}

// Nearest integer, ties away from zero. Callers guarantee |a| < 2^62.
inline int soft_wide3_round_to_int(soft_wide3 a) {
    return soft_wide_round_to_int(soft_wide3_to_wide(a));
}

// The 128-bit reciprocal (relative error below 2^-125) refined by one Newton
// step, e -> e^2 plus three truncations: below 2^-189.4.
inline soft_wide3 soft_wide3_reciprocal(soft_wide3 b) {
    soft_wide3 r = soft_wide3_from_wide(soft_wide_reciprocal(soft_wide3_to_wide(b)));
    soft_wide3 error = soft_wide3_sub(soft_wide3_one(), soft_wide3_mul(b, r));
    return soft_wide3_add(r, soft_wide3_mul(r, error));
}

// a / b with relative error below 2^-189.
inline soft_wide3 soft_wide3_div(soft_wide3 a, soft_wide3 b) {
    return soft_wide3_mul(a, soft_wide3_reciprocal(b));
}
