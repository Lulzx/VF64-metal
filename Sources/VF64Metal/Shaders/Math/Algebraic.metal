// M9 correctly rounded binary64 cbrt and hypot.
//
// These are algebraic, so their rounding can be decided exactly instead of
// certified against an error bound. Each function computes an integer
// R = floor(F) for a scaled exact quantity F (a cube root or a square root),
// using wide arithmetic only to guess R, then confirms the guess with exact
// integer arithmetic: R^k <= T < (R+1)^k for the exact integer T = F^k. The
// result is R with a sticky bit for F != R, rounded once. Every binary64
// rounding boundary of F is an integer multiple of a power of two no smaller
// than one in R's units, so R plus a sticky bit lies on the same side of every
// boundary as F itself, and an exact F is rounded exactly. This is proof
// obligation state 1: the rounding is correct for every argument, with no
// per-call certificate. A guess that the bounded correction cannot confirm is
// reported uncertified rather than delivered.

struct soft_u256 {
    ulong w0, w1, w2, w3;  // little-endian limbs
};

inline soft_u256 soft_u256_zero() {
    return soft_u256{0ul, 0ul, 0ul, 0ul};
}

// a += value << (64 * limb), with carry propagation.
inline soft_u256 soft_u256_add_at(soft_u256 a, ulong value, uint limb) {
    ulong limbs[4] = {a.w0, a.w1, a.w2, a.w3};
    ulong carry = value;
    for (uint index = limb; index < 4u && carry != 0ul; ++index) {
        ulong sum = limbs[index] + carry;
        carry = sum < carry ? 1ul : 0ul;
        limbs[index] = sum;
    }
    return soft_u256{limbs[0], limbs[1], limbs[2], limbs[3]};
}

inline soft_u256 soft_u256_mul128(soft_u128 a, soft_u128 b) {
    soft_u256 result = soft_u256_zero();
    ulong left[2] = {a.lo, a.hi};
    ulong right[2] = {b.lo, b.hi};
    for (uint i = 0; i < 2u; ++i) {
        for (uint j = 0; j < 2u; ++j) {
            result = soft_u256_add_at(result, left[i] * right[j], i + j);
            result = soft_u256_add_at(result, mulhi(left[i], right[j]), i + j + 1u);
        }
    }
    return result;
}

inline soft_u256 soft_u256_from128(soft_u128 a) {
    return soft_u256{a.lo, a.hi, 0ul, 0ul};
}

inline soft_u256 soft_u256_add(soft_u256 a, soft_u256 b) {
    a = soft_u256_add_at(a, b.w0, 0u);
    a = soft_u256_add_at(a, b.w1, 1u);
    a = soft_u256_add_at(a, b.w2, 2u);
    return soft_u256_add_at(a, b.w3, 3u);
}

// Left shift by any distance below 256, avoiding a 64-bit shift by 64.
inline soft_u256 soft_u256_shift_left(soft_u256 a, uint distance) {
    ulong limbs[4] = {a.w0, a.w1, a.w2, a.w3};
    ulong shifted[4] = {0ul, 0ul, 0ul, 0ul};
    uint whole = distance / 64u;
    uint bits = distance % 64u;
    for (uint index = 3u; ; --index) {
        if (index >= whole) {
            ulong value = limbs[index - whole] << bits;
            if (bits != 0u && index - whole >= 1u) {
                value |= limbs[index - whole - 1u] >> (64u - bits);
            }
            shifted[index] = value;
        }
        if (index == 0u) break;
    }
    return soft_u256{shifted[0], shifted[1], shifted[2], shifted[3]};
}

// -1, 0, or 1 as a < b, a == b, a > b.
inline int soft_u256_compare(soft_u256 a, soft_u256 b) {
    if (a.w3 != b.w3) return a.w3 < b.w3 ? -1 : 1;
    if (a.w2 != b.w2) return a.w2 < b.w2 ? -1 : 1;
    if (a.w1 != b.w1) return a.w1 < b.w1 ? -1 : 1;
    if (a.w0 != b.w0) return a.w0 < b.w0 ? -1 : 1;
    return 0;
}

inline uint soft_u128_bit_length(soft_u128 a) {
    return a.hi != 0ul ? 128u - uint(clz(a.hi)) : 64u - uint(clz(a.lo));
}

// floor of a positive wide value below 2^127.
inline soft_u128 soft_wide_floor(soft_wide a) {
    if (soft_wide_is_zero(a) || a.exponent <= 0) return soft_u128{0ul, 0ul};
    return soft_shift_right128(soft_u128{a.hi, a.lo}, uint(128 - a.exponent));
}

// soft_shift_left128 serves distances below 64 only; this covers [0, 128).
inline soft_u128 soft_shift_left128_any(soft_u128 a, uint distance) {
    if (distance >= 64u) return soft_u128{a.lo << (distance - 64u), 0ul};
    return soft_shift_left128(a, distance);
}

// R plus a sticky bit for an inexact root, as a wide value with exponent
// chosen so that it equals (R + sticky) 2^power.
inline soft_wide soft_wide_from_root(
    soft_u128 root, bool inexact, int power, bool sign
) {
    uint length = soft_u128_bit_length(root);
    soft_u128 significand = soft_shift_left128_any(root, 128u - length);
    if (inexact) significand.lo |= 1ul;
    return soft_wide{significand.hi, significand.lo, power + int(length), sign};
}

inline soft_u128 soft_u128_increment(soft_u128 a) {
    return soft_add128(a, soft_u128{0ul, 1ul});
}

inline soft_u128 soft_u128_decrement(soft_u128 a) {
    return soft_sub128(a, soft_u128{0ul, 1ul});
}

// Confirms R = floor(T^(1/k)) for k = 2 or 3 with at most four steps either
// way, returning false if the guess was further off than that.
inline soft_u256 soft_root_power(soft_u128 root, uint degree) {
    soft_u256 square = soft_u256_mul128(root, root);
    if (degree == 2u) return square;
    // root < 2^64 for cube roots, so the square fits in 128 bits.
    return soft_u256_mul128(soft_u128{square.w1, square.w0}, root);
}

inline bool soft_confirm_root(
    thread soft_u128 &root, soft_u256 target, uint degree, thread bool &exact
) {
    for (int step = 0; step < 4; ++step) {
        if (soft_u256_compare(soft_root_power(root, degree), target) <= 0) break;
        root = soft_u128_decrement(root);
    }
    for (int step = 0; step < 4; ++step) {
        soft_u128 next = soft_u128_increment(root);
        if (soft_u256_compare(soft_root_power(next, degree), target) > 0) break;
        root = next;
    }
    int lower = soft_u256_compare(soft_root_power(root, degree), target);
    int upper = soft_u256_compare(
        soft_root_power(soft_u128_increment(root), degree), target
    );
    exact = lower == 0;
    return lower <= 0 && upper > 0;
}

// FP32 seed for a wide value's inverse k-th root, k = 2 or 3. With
// a = f 2^p, f in [1, 2), p = degree * q + t, the seed is
// (f 2^t)^(-1/k) 2^-q. Even a 2^-16 seed reaches 2^-120 in three
// quadratic steps.
inline soft_wide soft_wide_inverse_root_seed(soft_wide a, int degree) {
    int power = a.exponent - 1;
    int quotient = power >= 0 ? power / degree : -((-power + degree - 1) / degree);
    int remainder = power - degree * quotient;
    float fraction = float(a.hi >> 40) * 0x1.0p-23f * float(1 << remainder);
    float seed = degree == 2 ? rsqrt(fraction) : powr(fraction, -1.0f / 3.0f);
    ulong seedBits = ulong(seed * 0x1.0p24f);
    return soft_wide_normalize(soft_u128{0ul, seedBits}, 104 - quotient, false);
}

// cbrt(x) = 2^q cbrt(N) with N = M 2^t, where x = M 2^E, M a 53-bit integer,
// and E = 3q + t. R = floor(cbrt(N 2^108)) has 54 or 55 bits, so the result
// is (R + sticky) 2^(q - 36). Every cube root of a binary64 lies in
// [2^-358, 2^342), so the result is always normal.
inline ulong soft_cbrt64_certified(
    ulong a, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    uint exponentField = uint((a >> 52) & 0x7fful);
    ulong fraction = a & 0x000ffffffffffffful;
    bool sign = (a >> 63) != 0ul;
    if (exponentField == 0x7ffu) {
        if (fraction != 0ul) {
            if (soft_is_signaling_nan(a)) flags |= soft_flag_invalid;
            return a | 0x0008000000000000ul;
        }
        return a;
    }
    if (exponentField == 0u && fraction == 0ul) return a;

    soft_normalized operand = soft_normalize_operand(exponentField, fraction);
    int power = operand.exponent - 1075;
    int q = power >= 0 ? power / 3 : -((-power + 2) / 3);
    int t = power - 3 * q;
    ulong n = operand.significand << uint(t);

    // Guess cbrt(N) by r <- r + r (1 - N r^3) / 3 from an FP32 seed: three
    // quadratic steps from 2^-20 reach the 2^-120 level, far closer than the
    // one unit the confirmation below allows for.
    soft_wide wideN = soft_wide_normalize(soft_u128{0ul, n}, 128, false);
    soft_wide r = soft_wide_inverse_root_seed(wideN, 3);
    soft_wide one = soft_wide_one();
    for (int step = 0; step < 3; ++step) {
        soft_wide cube = soft_wide_mul(soft_wide_mul(r, r), soft_wide_mul(r, wideN));
        soft_wide correction = soft_wide_mul(soft_wide_sub(one, cube), SOFT_CBRT_ONE_THIRD);
        r = soft_wide_add(r, soft_wide_mul(r, correction));
    }
    soft_wide root = soft_wide_mul(wideN, soft_wide_mul(r, r));
    soft_u128 guess = soft_wide_floor(soft_wide_scale2(root, 36));

    soft_u256 target = soft_u256_shift_left(
        soft_u256{n, 0ul, 0ul, 0ul}, 108u
    );
    bool exact = false;
    certified = soft_confirm_root(guess, target, 3u, exact);
    return soft_wide_exact_to_f64_status(
        soft_wide_from_root(guess, !exact, q - 36, sign), roundingMode, flags
    );
}

// hypot(x, y) with |x| >= |y| > 0, x = MX 2^EX, y = MY 2^EY, D = EX - EY:
//
//   D > 30:  hypot = |x| sqrt(1 + (y/x)^2) lies strictly above |x| and within
//            (y/x)^2 / 2 < 2^-60 |x| of it, inside half an ulp.
//   else:    S = MX^2 2^(2D) + MY^2 is an exact integer below 2^167, and
//            hypot = sqrt(4S) 2^(EY - 1). R = floor(sqrt(4S)) has at least 54
//            bits, so the rounding boundaries are whole units of R.
//
// Special values follow IEEE 754-2019 9.2.1: an infinity wins over a quiet
// NaN; a signaling NaN raises invalid and propagates as in M2.
inline ulong soft_hypot64_certified(
    ulong a, ulong b, uint roundingMode, thread uint &flags, thread bool &certified
) {
    certified = true;
    if (soft_is_signaling_nan(a) || soft_is_signaling_nan(b)) {
        flags |= soft_flag_invalid;
        return soft_propagate_nan(a, b);
    }
    ulong magnitudeA = a & 0x7ffffffffffffffful;
    ulong magnitudeB = b & 0x7ffffffffffffffful;
    if (magnitudeA == 0x7ff0000000000000ul || magnitudeB == 0x7ff0000000000000ul) {
        return 0x7ff0000000000000ul;
    }
    if (soft_is_nan(a) || soft_is_nan(b)) return soft_propagate_nan(a, b);

    ulong large = max(magnitudeA, magnitudeB);
    ulong small = min(magnitudeA, magnitudeB);
    if (small == 0ul) return large;

    soft_normalized x = soft_normalize_operand(uint(large >> 52), large & 0x000ffffffffffffful);
    soft_normalized y = soft_normalize_operand(uint(small >> 52), small & 0x000ffffffffffffful);
    int gap = x.exponent - y.exponent;
    if (gap > 30) return soft_round_beside(large, true, roundingMode, flags);

    soft_u128 mx = soft_u128{0ul, x.significand};
    soft_u128 my = soft_u128{0ul, y.significand};
    soft_u256 xSquared = soft_u256_mul128(mx, mx);
    soft_u256 ySquared = soft_u256_mul128(my, my);
    soft_u256 target = soft_u256_shift_left(
        soft_u256_add(soft_u256_shift_left(xSquared, uint(2 * gap)), ySquared), 2u
    );

    // Guess sqrt(4S) = 2 sqrt(S) by r <- r + r (1 - S r^2) / 2 from an FP32
    // seed, in wide arithmetic on S = (MX 2^D)^2 + MY^2.
    soft_wide wideX = soft_wide_normalize(mx, 128 + gap, false);
    soft_wide wideY = soft_wide_normalize(my, 128, false);
    soft_wide s = soft_wide_add(soft_wide_mul(wideX, wideX), soft_wide_mul(wideY, wideY));
    soft_wide r = soft_wide_inverse_root_seed(s, 2);
    soft_wide one = soft_wide_one();
    for (int step = 0; step < 3; ++step) {
        soft_wide square = soft_wide_mul(soft_wide_mul(r, r), s);
        r = soft_wide_add(r, soft_wide_scale2(soft_wide_mul(r, soft_wide_sub(one, square)), -1));
    }
    soft_u128 guess = soft_wide_floor(soft_wide_scale2(soft_wide_mul(s, r), 1));

    bool exact = false;
    certified = soft_confirm_root(guess, target, 2u, exact);
    return soft_wide_exact_to_f64_status(
        soft_wide_from_root(guess, !exact, y.exponent - 1075 - 1, false),
        roundingMode, flags
    );
}
