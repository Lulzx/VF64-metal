/*
 * M9 reference generator for correctly rounded binary64 functions.
 *
 * MPFR is the oracle: each mpfr_* function used here is correctly rounded by
 * construction, so with a 53-bit destination, the binary64 exponent range
 * installed, and mpfr_subnormalize applied, mpfr_get_d returns the correctly
 * rounded result for the requested direction. No approximation is compared;
 * the reference is the rounded value itself.
 *
 * Output is one case per line, in the field order the VF64 runner already
 * accepts for TestFloat vectors:
 *
 *     unary:  <argument bits> <result bits> <exception flags>
 *     binary: <first bits> <second bits> <result bits> <exception flags>
 *
 * Flags use the VF64 runtime encoding: 1 inexact, 2 underflow, 4 overflow,
 * 8 divide by zero, 16 invalid. Tininess is detected after rounding, so
 * underflow is raised when the delivered result is subnormal and inexact.
 *
 * Ties away from zero (rnear_maxMag) has no general MPFR rounding mode, so it
 * is derived: the MPFR_RNDN result is used unless the exact value is a
 * binary64 midpoint, in which case the away-from-zero neighbour is taken.
 * Midpoints are detected by evaluating at 256 bits: a midpoint is exactly
 * representable there, and the evaluation is then exact. Only hypot reaches
 * real midpoints; for the other functions this path never fires.
 *
 * Special values are decided here rather than by MPFR, so that the NaN
 * payload, default NaN, and flag policy are stated once and match the M2
 * runtime: quiet NaNs propagate with the quiet bit set, signaling NaNs raise
 * invalid, and an invalid operation returns the default NaN 0x7ff8...0.
 *
 * Build: see scripts/bootstrap-mpfr.sh.
 */

#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define FLAG_INEXACT 1u
#define FLAG_UNDERFLOW 2u
#define FLAG_OVERFLOW 4u
#define FLAG_INFINITE 8u
#define FLAG_INVALID 16u

#define DEFAULT_NAN 0x7ff8000000000000ull
#define POS_INF 0x7ff0000000000000ull
#define NEG_INF 0xfff0000000000000ull
#define ONE 0x3ff0000000000000ull

typedef int (*unary_fn)(mpfr_ptr, mpfr_srcptr, mpfr_rnd_t);
typedef int (*binary_fn)(mpfr_ptr, mpfr_srcptr, mpfr_srcptr, mpfr_rnd_t);

static int nearest_away = 0;

static uint64_t bits_of(double value) {
    uint64_t bits;
    memcpy(&bits, &value, sizeof bits);
    return bits;
}

static double value_of(uint64_t bits) {
    double value;
    memcpy(&value, &bits, sizeof value);
    return value;
}

static uint64_t splitmix64(uint64_t *state) {
    uint64_t z = (*state += 0x9e3779b97f4a7c15ull);
    z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9ull;
    z = (z ^ (z >> 27)) * 0x94d049bb133111ebull;
    return z ^ (z >> 31);
}

static int is_nan(uint64_t bits) {
    return ((bits >> 52) & 0x7ffull) == 0x7ff && (bits & 0x000fffffffffffffull) != 0;
}

static int is_signaling(uint64_t bits) {
    return is_nan(bits) && (bits & 0x0008000000000000ull) == 0;
}

static int is_zero(uint64_t bits) {
    return (bits & 0x7fffffffffffffffull) == 0;
}

static int is_inf(uint64_t bits) {
    return (bits & 0x7fffffffffffffffull) == POS_INF;
}

static int is_negative(uint64_t bits) {
    return (bits >> 63) != 0;
}

/* Round an MPFR value already computed with `ternary` to binary64. */
static uint64_t finish(mpfr_t y, int ternary, mpfr_rnd_t rounding, unsigned *flags,
                       int overflowed) {
    ternary = mpfr_check_range(y, ternary, rounding);
    ternary = mpfr_subnormalize(y, ternary, rounding);
    double rounded = mpfr_get_d(y, rounding);
    uint64_t bits = bits_of(rounded);
    uint64_t resultExponent = (bits >> 52) & 0x7ffull;
    if (ternary != 0) *flags |= FLAG_INEXACT;
    if (overflowed || mpfr_overflow_p() || resultExponent == 0x7ff) {
        *flags |= FLAG_OVERFLOW | FLAG_INEXACT;
    } else if (resultExponent == 0 && (*flags & FLAG_INEXACT) != 0) {
        *flags |= FLAG_UNDERFLOW;
    }
    return bits;
}

/*
 * Evaluate in `rounding`, deriving ties-away-from-zero when requested.
 * `evaluate` computes the function into its first argument.
 */
typedef int (*evaluator)(mpfr_ptr, const void *, mpfr_rnd_t);

static uint64_t rounded_reference(evaluator evaluate, const void *context,
                                  mpfr_rnd_t rounding, unsigned *flags) {
    mpfr_t y;
    mpfr_init2(y, 53);
    mpfr_clear_flags();
    int ternary = evaluate(y, context, rounding);
    uint64_t bits = finish(y, ternary, rounding, flags, 0);

    if (nearest_away && (*flags & FLAG_INEXACT) != 0 &&
        (*flags & FLAG_OVERFLOW) == 0) {
        mpfr_t exact, lower, upper, middle;
        mpfr_inits2(256, exact, middle, (mpfr_ptr)0);
        mpfr_inits2(53, lower, upper, (mpfr_ptr)0);
        /* The midpoint may lie below the binary64 range (2^-1075 is the
         * midpoint of 0 and the smallest subnormal), so the exact evaluation
         * runs with MPFR's full exponent range. */
        mpfr_exp_t savedEmin = mpfr_get_emin();
        mpfr_exp_t savedEmax = mpfr_get_emax();
        mpfr_set_emin(mpfr_get_emin_min());
        mpfr_set_emax(mpfr_get_emax_max());
        int exactTernary = evaluate(exact, context, MPFR_RNDN);
        mpfr_set_emin(savedEmin);
        mpfr_set_emax(savedEmax);
        if (exactTernary == 0) {
            unsigned ignored = 0;
            mpfr_clear_flags();
            uint64_t toward = finish(lower, evaluate(lower, context, MPFR_RNDZ),
                                     MPFR_RNDZ, &ignored, 0);
            ignored = 0;
            mpfr_clear_flags();
            uint64_t away = finish(upper, evaluate(upper, context, MPFR_RNDA),
                                   MPFR_RNDA, &ignored, 0);
            mpfr_set_emin(mpfr_get_emin_min());
            mpfr_set_d(middle, value_of(toward), MPFR_RNDN);
            mpfr_t awayValue;
            mpfr_init2(awayValue, 256);
            mpfr_set_d(awayValue, value_of(away), MPFR_RNDN);
            mpfr_add(middle, middle, awayValue, MPFR_RNDN);
            mpfr_div_2ui(middle, middle, 1, MPFR_RNDN);
            if (toward != away && mpfr_cmp(middle, exact) == 0) bits = away;
            mpfr_clear(awayValue);
            mpfr_set_emin(savedEmin);
        }
        mpfr_clears(exact, middle, lower, upper, (mpfr_ptr)0);
    }
    mpfr_clear(y);
    return bits;
}

struct unary_context {
    unary_fn function;
    double x;
};

static int evaluate_unary(mpfr_ptr y, const void *raw, mpfr_rnd_t rounding) {
    const struct unary_context *context = raw;
    mpfr_t x;
    mpfr_init2(x, 53);
    mpfr_set_d(x, context->x, MPFR_RNDN); /* exact: same format */
    int ternary = context->function(y, x, rounding);
    mpfr_clear(x);
    return ternary;
}

struct binary_context {
    binary_fn function;
    double a, b;
};

static int evaluate_binary(mpfr_ptr y, const void *raw, mpfr_rnd_t rounding) {
    const struct binary_context *context = raw;
    mpfr_t a, b;
    mpfr_inits2(53, a, b, (mpfr_ptr)0);
    mpfr_set_d(a, context->a, MPFR_RNDN);
    mpfr_set_d(b, context->b, MPFR_RNDN);
    int ternary = context->function(y, a, b, rounding);
    mpfr_clears(a, b, (mpfr_ptr)0);
    return ternary;
}

/* ---------------------------------------------------------------------- */
/* Special values. Each returns 1 when it decided the case.                */

static int quiet_nan(uint64_t x, uint64_t *result, unsigned *flags) {
    if (!is_nan(x)) return 0;
    if (is_signaling(x)) *flags |= FLAG_INVALID;
    *result = x | 0x0008000000000000ull;
    return 1;
}

static int special_exp(uint64_t x, uint64_t *result, unsigned *flags) {
    if (quiet_nan(x, result, flags)) return 1;
    if (is_inf(x)) { *result = is_negative(x) ? 0ull : POS_INF; return 1; }
    if (is_zero(x)) { *result = ONE; return 1; }
    return 0;
}

static int special_expm1(uint64_t x, uint64_t *result, unsigned *flags) {
    if (quiet_nan(x, result, flags)) return 1;
    if (is_inf(x)) { *result = is_negative(x) ? 0xbff0000000000000ull : POS_INF; return 1; }
    if (is_zero(x)) { *result = x; return 1; }
    return 0;
}

/* log, log2: negative arguments are invalid; zero is a pole. */
static int special_log(uint64_t x, uint64_t *result, unsigned *flags) {
    if (quiet_nan(x, result, flags)) return 1;
    if (is_zero(x)) { *result = NEG_INF; *flags |= FLAG_INFINITE; return 1; }
    if (is_negative(x)) { *result = DEFAULT_NAN; *flags |= FLAG_INVALID; return 1; }
    if (is_inf(x)) { *result = POS_INF; return 1; }
    return 0;
}

static int special_log1p(uint64_t x, uint64_t *result, unsigned *flags) {
    if (quiet_nan(x, result, flags)) return 1;
    if (is_zero(x)) { *result = x; return 1; }
    if (x == 0xbff0000000000000ull) { *result = NEG_INF; *flags |= FLAG_INFINITE; return 1; }
    if (is_negative(x) && value_of(x) < -1.0) {
        *result = DEFAULT_NAN; *flags |= FLAG_INVALID; return 1;
    }
    if (is_inf(x)) { *result = POS_INF; return 1; }
    return 0;
}

static int special_cbrt(uint64_t x, uint64_t *result, unsigned *flags) {
    if (quiet_nan(x, result, flags)) return 1;
    if (is_inf(x) || is_zero(x)) { *result = x; return 1; }
    return 0;
}

/*
 * hypot: a signaling NaN in either operand raises invalid and propagates as in
 * the M2 binary operations. Otherwise an infinity in either operand gives +inf
 * even when the other operand is a quiet NaN (IEEE 754-2019, 9.2.1), and a
 * remaining quiet NaN propagates.
 */
static uint64_t propagate_nan(uint64_t a, uint64_t b) {
    uint64_t source;
    if (is_signaling(a) || is_signaling(b)) source = is_signaling(a) ? a : b;
    else source = is_nan(a) ? a : b;
    return source | 0x0008000000000000ull;
}

static int special_hypot(uint64_t a, uint64_t b, uint64_t *result, unsigned *flags) {
    if (is_signaling(a) || is_signaling(b)) {
        *flags |= FLAG_INVALID;
        *result = propagate_nan(a, b);
        return 1;
    }
    if (is_inf(a) || is_inf(b)) { *result = POS_INF; return 1; }
    if (is_nan(a) || is_nan(b)) { *result = propagate_nan(a, b); return 1; }
    return 0;
}

/* ---------------------------------------------------------------------- */

struct unary_function {
    const char *name;
    unary_fn mpfr;
    int (*special)(uint64_t, uint64_t *, unsigned *);
};

static const struct unary_function unary_functions[] = {
    {"f64_exp", mpfr_exp, special_exp},
    {"f64_exp2", mpfr_exp2, special_exp},
    {"f64_expm1", mpfr_expm1, special_expm1},
    {"f64_log", mpfr_log, special_log},
    {"f64_log2", mpfr_log2, special_log},
    {"f64_log1p", mpfr_log1p, special_log1p},
    {"f64_cbrt", mpfr_cbrt, special_cbrt},
};

static const struct unary_function *active = NULL;
static int binary = 0;
static mpfr_rnd_t active_rounding;

static void emit(uint64_t argument) {
    uint64_t result;
    unsigned flags = 0;
    if (!active->special(argument, &result, &flags)) {
        struct unary_context context = {active->mpfr, value_of(argument)};
        result = rounded_reference(evaluate_unary, &context, active_rounding, &flags);
    }
    printf("%016llx %016llx %02x\n", (unsigned long long)argument,
           (unsigned long long)result, flags);
}

static void emit2(uint64_t a, uint64_t b) {
    uint64_t result;
    unsigned flags = 0;
    if (!special_hypot(a, b, &result, &flags)) {
        struct binary_context context = {mpfr_hypot, value_of(a), value_of(b)};
        result = rounded_reference(evaluate_binary, &context, active_rounding, &flags);
    }
    printf("%016llx %016llx %016llx %02x\n", (unsigned long long)a,
           (unsigned long long)b, (unsigned long long)result, flags);
}

static void emit_near(double centre, int radius) {
    uint64_t bits = bits_of(centre);
    for (int64_t delta = -radius; delta <= radius; ++delta) {
        emit((uint64_t)((int64_t)bits + delta));
    }
}

static const uint64_t unary_specials[] = {
    0x0000000000000000ull, 0x8000000000000000ull, /* +-0 */
    0x7ff0000000000000ull, 0xfff0000000000000ull, /* +-infinity */
    0x7ff8000000000000ull, 0xfff8000000000000ull, /* quiet NaN */
    0x7ff4000000000000ull, 0xfff4000000000000ull, /* signaling NaN */
    0x0000000000000001ull, 0x8000000000000001ull, /* +-min subnormal */
    0x000fffffffffffffull, 0x0010000000000000ull, /* subnormal edge */
    0x7fefffffffffffffull, 0xffefffffffffffffull, /* +-max finite */
};

static void emit_unary_specials(void) {
    for (size_t i = 0; i < sizeof unary_specials / sizeof unary_specials[0]; ++i) {
        emit(unary_specials[i]);
    }
}

static double random_significand(uint64_t *state) {
    uint64_t fraction = splitmix64(state) & 0x000fffffffffffffull;
    return 1.0 + (double)fraction / 4503599627370496.0;
}

static double random_magnitude(uint64_t *state, int lowExponent, int highExponent) {
    int exponent = lowExponent +
        (int)(splitmix64(state) % (uint64_t)(highExponent - lowExponent + 1));
    return ldexp(random_significand(state), exponent);
}

static uint64_t random_subnormal(uint64_t *state) {
    return 1ull + splitmix64(state) % 0x000fffffffffffffull;
}

/* ---------------------------------------------------------------------- */
/* exp. Kept identical to the generator behind the 2026-09-20 artifact.   */

static const double exp_boundary_values[] = {
    0.0,
    1.0, -1.0, 2.0, -2.0, 0.5, -0.5,
    0.6931471805599453,   /* ln 2 */
    -0.6931471805599453,
    709.782712893384,     /* largest finite result */
    709.7827128933841,
    -708.3964185322641,   /* smallest normal result */
    -744.4400719213812,   /* smallest subnormal result */
    -745.1332191019411,   /* below half the smallest subnormal */
    -745.1332191019412,
    88.0, -88.0, 100.0, -100.0, 500.0, -500.0,
    1e-16, -1e-16, 1e-8, -1e-8, 1e-300, -1e-300,
    1024.0, -1024.0, 1e300, -1e300,
};

static void boundary_exp(void) {
    emit_unary_specials();
    size_t count = sizeof exp_boundary_values / sizeof exp_boundary_values[0];
    for (size_t i = 0; i < count; ++i) emit_near(exp_boundary_values[i], 4);
    /* Near multiples of ln 2, where argument reduction cancels hardest. */
    for (int k = -1000; k <= 1000; k += 7) emit_near((double)k * 0.6931471805599453, 2);
    /* The closed-form tiny region and its edge. */
    for (int exponent = -80; exponent <= -55; ++exponent) {
        double value = ldexp(1.0, exponent);
        emit(bits_of(value));
        emit(bits_of(-value));
    }
}

/* Three strata, so that no region of the domain is starved:
 *   0-59:  the reduction range, exponents in [-60, 10];
 *   60-79: the closed-form tiny range, exponents in [-1074, -60);
 *   80-99: uniform reals across the finite result range, which concentrates
 *          cases on the overflow and underflow edges.
 */
static void random_exp(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        uint64_t fraction = splitmix64(&state) & 0x000fffffffffffffull;
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        int sign = (int)(splitmix64(&state) & 1ull);
        double magnitude;
        if (stratum < 60u) {
            int exponent = -60 + (int)(splitmix64(&state) % 71ull);
            magnitude = ldexp(1.0 + (double)fraction / 4503599627370496.0,
                              exponent);
        } else if (stratum < 80u) {
            int exponent = -1074 + (int)(splitmix64(&state) % 1014ull);
            magnitude = ldexp(1.0 + (double)fraction / 4503599627370496.0,
                              exponent);
        } else {
            double unit = (double)(splitmix64(&state) >> 11) /
                          9007199254740992.0;
            magnitude = unit * (sign ? 745.2 : 709.8);
        }
        emit(bits_of(sign ? -magnitude : magnitude));
    }
}

/* ---------------------------------------------------------------------- */
/* exp2                                                                    */

static void boundary_exp2(void) {
    emit_unary_specials();
    static const double values[] = {
        0.5, -0.5, 1023.0, 1023.9999999999999, 1024.0, -1022.0, -1074.0,
        -1074.5, -1075.0, -1075.5, -1076.0, -1080.0, -1100.0, 1e-16, -1e-16,
        1e-300, -1e-300, 0.25, -0.25, 1e300, -1e300,
    };
    for (size_t i = 0; i < sizeof values / sizeof values[0]; ++i) emit_near(values[i], 4);
    /* Every integer argument from full underflow to overflow: exact results. */
    for (int k = -1100; k <= 1030; ++k) emit(bits_of((double)k));
    for (int k = -1090; k <= 1030; k += 17) {
        emit_near((double)k, 2);
        emit_near((double)k + 0.5, 1);
    }
    for (int exponent = -80; exponent <= -55; ++exponent) {
        emit(bits_of(ldexp(1.0, exponent)));
        emit(bits_of(-ldexp(1.0, exponent)));
    }
}

/*   0-49: reduction range, |x| exponents in [-60, 10];
 *  50-64: closed-form tiny range;
 *  65-84: uniform reals over the whole finite and underflowing result range;
 *  85-99: near integers, where the reduced argument is smallest.
 */
static void random_exp2(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        int sign = (int)(splitmix64(&state) & 1ull);
        double value;
        if (stratum < 50u) {
            value = random_magnitude(&state, -60, 10);
            if (sign) value = -value;
        } else if (stratum < 65u) {
            value = random_magnitude(&state, -1074, -61);
            if (sign) value = -value;
        } else if (stratum < 85u) {
            double unit = (double)(splitmix64(&state) >> 11) / 9007199254740992.0;
            value = -1080.0 + unit * 2110.0;
        } else {
            int k = -1080 + (int)(splitmix64(&state) % 2110ull);
            double offset = random_magnitude(&state, -52, -2);
            value = (double)k + (sign ? -offset : offset);
        }
        emit(bits_of(value));
    }
}

/* ---------------------------------------------------------------------- */
/* expm1                                                                   */

static void boundary_expm1(void) {
    emit_unary_specials();
    static const double values[] = {
        0.5, -0.5, 1.0, -1.0, 0.6931471805599453, -0.6931471805599453,
        709.782712893384, 709.7827128933841, 1024.0, -37.0, -38.0, -40.0,
        -44.0, -45.0, -46.0, -700.0, -745.2, -1e300, 1e-16, -1e-16, 1e-8,
        -1e-8, 1e-300, -1e-300, 2.0, -2.0, 0.25, -0.25,
    };
    for (size_t i = 0; i < sizeof values / sizeof values[0]; ++i) emit_near(values[i], 4);
    for (int k = -60; k <= 1000; k += 7) emit_near((double)k * 0.6931471805599453, 2);
    for (int exponent = -80; exponent <= -55; ++exponent) {
        emit(bits_of(ldexp(1.0, exponent)));
        emit(bits_of(-ldexp(1.0, exponent)));
        emit(bits_of(ldexp(1.9999999999999998, exponent)));
        emit(bits_of(-ldexp(1.9999999999999998, exponent)));
    }
}

/*   0-49: series and reduction range, |x| exponents in [-60, 10];
 *  50-64: closed-form tiny range, including subnormals;
 *  65-84: uniform reals over [-750, 709.8];
 *  85-99: |x| in [0.25, 1], around the switch between the two paths.
 */
static void random_expm1(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        int sign = (int)(splitmix64(&state) & 1ull);
        double value;
        if (stratum < 50u) {
            value = random_magnitude(&state, -60, 10);
        } else if (stratum < 65u) {
            uint64_t bits = (splitmix64(&state) % 4u == 0u)
                ? random_subnormal(&state)
                : bits_of(random_magnitude(&state, -1022, -61));
            value = value_of(bits);
        } else if (stratum < 85u) {
            double unit = (double)(splitmix64(&state) >> 11) / 9007199254740992.0;
            value = unit * (sign ? 750.0 : 709.8);
        } else {
            value = random_magnitude(&state, -2, -1);
        }
        emit(bits_of(sign ? -value : value));
    }
}

/* ---------------------------------------------------------------------- */
/* log and log2                                                            */

static void boundary_log(void) {
    emit_unary_specials();
    emit_near(1.0, 64);
    emit_near(1.4142135623730951, 4);
    emit_near(0.7071067811865476, 4);
    emit_near(2.718281828459045, 4);
    emit_near(-1.0, 2);
    emit_near(10.0, 4);
    for (int exponent = -1074; exponent <= 1023; ++exponent) emit(bits_of(ldexp(1.0, exponent)));
    for (int exponent = -1022; exponent <= 1023; exponent += 8) {
        emit_near(ldexp(1.0, exponent), 2);
    }
    for (int e = 1; e <= 60; ++e) {
        emit(bits_of(1.0 + ldexp(1.0, -e)));
        emit(bits_of(1.0 - ldexp(1.0, -e - 1)));
    }
}

/*   0-39: uniform over every normal binade;
 *  40-54: subnormals;
 *  55-79: near 1, where the result is smallest relative to the argument;
 *  80-89: near powers of two;
 *  90-99: arbitrary bit patterns, including negatives and NaNs.
 */
static void random_log(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        uint64_t bits;
        if (stratum < 40u) {
            bits = bits_of(random_magnitude(&state, -1022, 1023));
        } else if (stratum < 55u) {
            bits = random_subnormal(&state);
        } else if (stratum < 80u) {
            double offset = random_magnitude(&state, -60, -1);
            bits = bits_of((splitmix64(&state) & 1ull) ? 1.0 + offset : 1.0 - offset / 2.0);
        } else if (stratum < 90u) {
            int exponent = -1022 + (int)(splitmix64(&state) % 2046ull);
            int64_t delta = (int64_t)(splitmix64(&state) % 9ull) - 4;
            bits = (uint64_t)((int64_t)bits_of(ldexp(1.0, exponent)) + delta);
        } else {
            bits = splitmix64(&state);
        }
        emit(bits);
    }
}

/* ---------------------------------------------------------------------- */
/* log1p                                                                   */

static void boundary_log1p(void) {
    emit_unary_specials();
    emit_near(-1.0, 8);
    emit_near(-0.9999999999999999, 4);
    emit_near(0.41421356237309503, 4);
    emit_near(-0.2928932188134524, 4);
    emit_near(1.0, 4);
    emit_near(-0.5, 4);
    emit_near(1.718281828459045, 4);
    emit_near(ldexp(1.0, 53), 2);
    emit_near(ldexp(1.0, 75), 2);
    emit_near(ldexp(1.0, 76), 2);
    for (int exponent = -80; exponent <= -55; ++exponent) {
        emit(bits_of(ldexp(1.0, exponent)));
        emit(bits_of(-ldexp(1.0, exponent)));
        emit(bits_of(ldexp(1.9999999999999998, exponent)));
        emit(bits_of(-ldexp(1.9999999999999998, exponent)));
    }
    for (int exponent = 0; exponent <= 1023; exponent += 3) emit(bits_of(ldexp(1.0, exponent)));
}

/*   0-29: |x| exponents in [-60, -1], both signs;
 *  30-44: closed-form tiny range, including subnormals;
 *  45-69: positive x with exponents in [0, 1023];
 *  70-84: x uniform in (-1, -0.25);
 *  85-99: x just above -1.
 */
static void random_log1p(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        int sign = (int)(splitmix64(&state) & 1ull);
        double value;
        if (stratum < 30u) {
            value = random_magnitude(&state, -60, -1);
            if (sign) value = -value;
        } else if (stratum < 45u) {
            uint64_t bits = (splitmix64(&state) % 4u == 0u)
                ? random_subnormal(&state)
                : bits_of(random_magnitude(&state, -1022, -61));
            value = sign ? -value_of(bits) : value_of(bits);
        } else if (stratum < 70u) {
            value = random_magnitude(&state, 0, 1023);
        } else if (stratum < 85u) {
            double unit = (double)(splitmix64(&state) >> 11) / 9007199254740992.0;
            value = -1.0 + unit * 0.75;
            if (value == -1.0) value = -0.5;
        } else {
            value = -1.0 + random_magnitude(&state, -53, -2);
        }
        emit(bits_of(value));
    }
}

/* ---------------------------------------------------------------------- */
/* cbrt                                                                    */

static void boundary_cbrt(void) {
    emit_unary_specials();
    for (int exponent = -1074; exponent <= 1023; ++exponent) {
        emit(bits_of(ldexp(1.0, exponent)));
        emit(bits_of(-ldexp(1.0, exponent)));
    }
    /* Perfect cubes, exact results, and their neighbours. */
    for (uint64_t k = 1; k <= 3000; ++k) {
        double cube = (double)(k * k * k);
        emit_near(cube, 1);
        emit(bits_of(-cube));
        emit(bits_of(ldexp(cube, -999)));
        emit(bits_of(ldexp(cube, 900)));
    }
    emit_near(0.125, 2);
    emit_near(27.0, 2);
}

/*   0-59: arbitrary finite magnitudes over every binade, both signs;
 *  60-79: subnormals;
 *  80-99: perfect cubes of 17-bit integers, scaled, and their neighbours.
 */
static void random_cbrt(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        int sign = (int)(splitmix64(&state) & 1ull);
        uint64_t bits;
        if (stratum < 60u) {
            bits = bits_of(random_magnitude(&state, -1022, 1023));
        } else if (stratum < 80u) {
            bits = random_subnormal(&state);
        } else {
            uint64_t k = 1 + splitmix64(&state) % 131071ull;
            int scale = 3 * ((int)(splitmix64(&state) % 600ull) - 300);
            int64_t delta = (int64_t)(splitmix64(&state) % 3ull) - 1;
            bits = (uint64_t)((int64_t)bits_of(ldexp((double)(k * k * k), scale)) + delta);
        }
        emit(sign ? bits | 0x8000000000000000ull : bits);
    }
}

/* ---------------------------------------------------------------------- */
/* hypot                                                                   */

/*
 * A Pythagorean triple from Euclid's formula whose hypotenuse is an odd
 * 54-bit integer and whose legs fit in 53 bits: hypot of the legs is then
 * exactly halfway between two binary64 values, which exercises the
 * ties-away-from-zero mode against a real midpoint.
 */
static int midpoint_triple(uint64_t *state, double *a, double *b) {
    for (int attempt = 0; attempt < 64; ++attempt) {
        uint64_t n = 38000000ull + splitmix64(state) % 5000000ull;
        uint64_t m = (uint64_t)((double)n * 2.414213562373095);
        if (((m + n) & 1ull) == 0ull) m += 1;
        uint64_t legA = m * m - n * n;
        uint64_t legB = 2 * m * n;
        uint64_t hypotenuse = m * m + n * n;
        if (legA < (1ull << 53) && legB < (1ull << 53) &&
            hypotenuse > (1ull << 53) && hypotenuse < (1ull << 54)) {
            *a = (double)legA;
            *b = (double)legB;
            return 1;
        }
    }
    return 0;
}

static void boundary_hypot(void) {
    static const uint64_t values[] = {
        0x0000000000000000ull, 0x8000000000000000ull, 0x7ff0000000000000ull,
        0xfff0000000000000ull, 0x7ff8000000000000ull, 0xfff8000000000000ull,
        0x7ff4000000000000ull, 0x0000000000000001ull, 0x8000000000000003ull,
        0x000fffffffffffffull, 0x0010000000000000ull, 0x7fefffffffffffffull,
        0x3ff0000000000000ull, 0x4008000000000000ull, 0x4010000000000000ull,
        0x4014000000000000ull,
    };
    size_t count = sizeof values / sizeof values[0];
    for (size_t i = 0; i < count; ++i) {
        for (size_t j = 0; j < count; ++j) emit2(values[i], values[j]);
    }
    /* Exact results: scaled Pythagorean triples. */
    static const double triples[][2] = {
        {3, 4}, {5, 12}, {8, 15}, {7, 24}, {20, 21}, {9, 40}, {119, 120},
    };
    for (size_t t = 0; t < sizeof triples / sizeof triples[0]; ++t) {
        for (int scale = -1074; scale <= 1010; scale += 13) {
            emit2(bits_of(ldexp(triples[t][0], scale)), bits_of(ldexp(triples[t][1], scale)));
        }
    }
    /* Exponent gaps around the closed-form edge. */
    for (int gap = 0; gap <= 70; ++gap) {
        emit2(bits_of(1.5), bits_of(ldexp(1.25, -gap)));
        emit2(bits_of(ldexp(1.9999999999999998, 300)), bits_of(ldexp(1.0000000000000002, 300 - gap)));
    }
    /* Overflow edge. */
    emit2(0x7fefffffffffffffull, 0x7fefffffffffffffull);
    emit2(bits_of(ldexp(1.4142135623730951, 1022) / 2.0), bits_of(ldexp(1.4142135623730951, 1022) / 2.0));
    emit2(bits_of(ldexp(1.0, 1023)), bits_of(ldexp(1.0, 1023)));
    uint64_t state = 7;
    for (int i = 0; i < 64; ++i) {
        double a, b;
        if (midpoint_triple(&state, &a, &b)) {
            emit2(bits_of(a), bits_of(b));
            emit2(bits_of(ldexp(a, -1100)), bits_of(ldexp(b, -1100)));
            emit2(bits_of(ldexp(-b, 900)), bits_of(ldexp(a, 900)));
        }
    }
}

/*   0-39: exponent gap 0-40 at arbitrary base exponents;
 *  40-54: gap 25-80, across the closed-form edge;
 *  55-69: subnormal operands;
 *  70-84: scaled Pythagorean triples and their neighbours (exact results);
 *  85-99: odd 54-bit hypotenuse triples (exact binary64 midpoints).
 */
static void random_hypot(long count, uint64_t seed) {
    uint64_t state = seed;
    for (long i = 0; i < count; ++i) {
        unsigned stratum = (unsigned)(splitmix64(&state) % 100ull);
        double a, b;
        if (stratum < 55u) {
            int gap = stratum < 40u ? (int)(splitmix64(&state) % 41ull)
                                    : 25 + (int)(splitmix64(&state) % 56ull);
            int base = -1022 + gap + (int)(splitmix64(&state) % (uint64_t)(2046 - gap));
            a = ldexp(random_significand(&state), base);
            b = ldexp(random_significand(&state), base - gap);
        } else if (stratum < 70u) {
            a = value_of(random_subnormal(&state));
            b = (splitmix64(&state) & 1ull) ? value_of(random_subnormal(&state))
                                           : random_magnitude(&state, -1022, -1000);
        } else if (stratum < 85u) {
            uint64_t m = 2 + splitmix64(&state) % 60000ull;
            uint64_t n = 1 + splitmix64(&state) % (m - 1);
            int scale = -1000 + (int)(splitmix64(&state) % 1980ull);
            a = ldexp((double)(m * m - n * n), scale);
            b = ldexp((double)(2 * m * n), scale);
            int64_t delta = (int64_t)(splitmix64(&state) % 3ull) - 1;
            b = value_of((uint64_t)((int64_t)bits_of(b) + delta));
        } else {
            if (!midpoint_triple(&state, &a, &b)) { a = 3.0; b = 4.0; }
            int scale = -1100 + (int)(splitmix64(&state) % 2050ull);
            a = ldexp(a, scale);
            b = ldexp(b, scale);
        }
        if (splitmix64(&state) & 1ull) a = -a;
        if (splitmix64(&state) & 1ull) b = -b;
        if (splitmix64(&state) & 1ull) { double t = a; a = b; b = t; }
        emit2(bits_of(a), bits_of(b));
    }
}

/* ---------------------------------------------------------------------- */

struct corpus {
    const char *name;
    void (*boundary)(void);
    void (*random)(long, uint64_t);
};

static const struct corpus corpora[] = {
    {"f64_exp", boundary_exp, random_exp},
    {"f64_exp2", boundary_exp2, random_exp2},
    {"f64_expm1", boundary_expm1, random_expm1},
    {"f64_log", boundary_log, random_log},
    {"f64_log2", boundary_log, random_log},
    {"f64_log1p", boundary_log1p, random_log1p},
    {"f64_cbrt", boundary_cbrt, random_cbrt},
    {"f64_hypot", boundary_hypot, random_hypot},
};

static int usage(void) {
    fprintf(stderr,
            "usage: m9_ref <function> <rounding> boundary|random <count> <seed>\n"
            "functions: f64_exp f64_exp2 f64_expm1 f64_log f64_log2 f64_log1p "
            "f64_cbrt f64_hypot\n");
    return 2;
}

int main(int argc, char **argv) {
    if (argc < 4) return usage();
    const char *functionName = argv[1];
    const char *roundingName = argv[2];

    const struct corpus *selected = NULL;
    for (size_t i = 0; i < sizeof corpora / sizeof corpora[0]; ++i) {
        if (strcmp(corpora[i].name, functionName) == 0) selected = &corpora[i];
    }
    if (selected == NULL) return usage();
    binary = strcmp(functionName, "f64_hypot") == 0;
    for (size_t i = 0; i < sizeof unary_functions / sizeof unary_functions[0]; ++i) {
        if (strcmp(unary_functions[i].name, functionName) == 0) active = &unary_functions[i];
    }

    if (strcmp(roundingName, "rnear_even") == 0) active_rounding = MPFR_RNDN;
    else if (strcmp(roundingName, "rminMag") == 0) active_rounding = MPFR_RNDZ;
    else if (strcmp(roundingName, "rmin") == 0) active_rounding = MPFR_RNDD;
    else if (strcmp(roundingName, "rmax") == 0) active_rounding = MPFR_RNDU;
    else if (strcmp(roundingName, "rnear_maxMag") == 0) {
        active_rounding = MPFR_RNDN;
        nearest_away = 1;
    } else {
        fprintf(stderr, "unknown rounding mode %s\n", roundingName);
        return 2;
    }

    mpfr_set_emin(-1073);
    mpfr_set_emax(1024);

    if (strcmp(argv[3], "boundary") == 0) {
        selected->boundary();
        return 0;
    }
    if (strcmp(argv[3], "random") == 0 && argc == 6) {
        selected->random(strtol(argv[4], NULL, 10), strtoull(argv[5], NULL, 10));
        return 0;
    }
    return usage();
}
