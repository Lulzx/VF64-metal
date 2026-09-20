/*
 * M9 reference generator for binary64 exp.
 *
 * MPFR is the oracle: mpfr_exp is correctly rounded by construction, so with a
 * 53-bit destination, the binary64 exponent range installed, and
 * mpfr_subnormalize applied, mpfr_get_d returns the correctly rounded result
 * for the requested direction. No approximation is compared here; the
 * reference is the rounded value itself.
 *
 * Output is one case per line, matching the field order the VF64 runner
 * already accepts for TestFloat vectors:
 *
 *     <argument bits> <result bits> <exception flags>
 *
 * Flags use the VF64 runtime encoding: 1 inexact, 2 underflow, 4 overflow,
 * 8 divide by zero, 16 invalid. Tininess is detected after rounding, so
 * underflow is raised when the delivered result is subnormal and inexact.
 *
 * Ties away from zero (rnear_maxMag) is generated with MPFR_RNDN. exp(x) is
 * transcendental for every nonzero algebraic x, so it is never exactly halfway
 * between two binary64 values and the two nearest modes cannot disagree. The
 * one argument where exp is exactly representable, x = 0, is a special case
 * handled before rounding.
 *
 * Build: see scripts/bootstrap-mpfr.sh.
 */

#include <math.h>
#include <mpfr.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#define FLAG_INEXACT 1u
#define FLAG_UNDERFLOW 2u
#define FLAG_OVERFLOW 4u
#define FLAG_INVALID 16u

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

/* Reference result and flags for one argument. */
static void reference(uint64_t argument, mpfr_rnd_t rounding, uint64_t *result,
                      unsigned *flags) {
    uint64_t exponentField = (argument >> 52) & 0x7ffull;
    uint64_t fraction = argument & 0x000fffffffffffffull;
    int sign = (argument >> 63) != 0;
    *flags = 0;

    if (exponentField == 0x7ff) {
        if (fraction != 0) {
            if ((argument & 0x0008000000000000ull) == 0) *flags |= FLAG_INVALID;
            *result = argument | 0x0008000000000000ull;
            return;
        }
        *result = sign ? 0ull : 0x7ff0000000000000ull;
        return;
    }
    if (exponentField == 0 && fraction == 0) {
        *result = 0x3ff0000000000000ull; /* exp(+-0) = 1, exactly */
        return;
    }

    mpfr_t x, y;
    mpfr_init2(x, 53);
    mpfr_init2(y, 53);
    mpfr_set_d(x, value_of(argument), MPFR_RNDN); /* exact: same format */

    mpfr_clear_flags();
    int ternary = mpfr_exp(y, x, rounding);
    ternary = mpfr_check_range(y, ternary, rounding);
    mpfr_subnormalize(y, ternary, rounding);

    double rounded = mpfr_get_d(y, rounding);
    uint64_t bits = bits_of(rounded);
    uint64_t resultExponent = (bits >> 52) & 0x7ffull;

    if (ternary != 0) *flags |= FLAG_INEXACT;
    if (mpfr_overflow_p() || resultExponent == 0x7ff) {
        *flags |= FLAG_OVERFLOW | FLAG_INEXACT;
    } else if (resultExponent == 0 && (*flags & FLAG_INEXACT) != 0) {
        *flags |= FLAG_UNDERFLOW;
    }

    *result = bits;
    mpfr_clear(x);
    mpfr_clear(y);
}

static void emit(uint64_t argument, mpfr_rnd_t rounding) {
    uint64_t result;
    unsigned flags;
    reference(argument, rounding, &result, &flags);
    printf("%016llx %016llx %02x\n", (unsigned long long)argument,
           (unsigned long long)result, flags);
}

/* Arguments that decide a boundary, plus a few ulps either side of each. */
static const double boundary_values[] = {
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

static void emit_boundary(mpfr_rnd_t rounding) {
    static const uint64_t specials[] = {
        0x0000000000000000ull, 0x8000000000000000ull, /* +-0 */
        0x7ff0000000000000ull, 0xfff0000000000000ull, /* +-infinity */
        0x7ff8000000000000ull, 0xfff8000000000000ull, /* quiet NaN */
        0x7ff4000000000000ull, 0xfff4000000000000ull, /* signaling NaN */
        0x0000000000000001ull, 0x8000000000000001ull, /* +-min subnormal */
        0x000fffffffffffffull, 0x0010000000000000ull, /* subnormal edge */
        0x7fefffffffffffffull, 0xffefffffffffffffull, /* +-max finite */
    };
    for (size_t i = 0; i < sizeof specials / sizeof specials[0]; ++i) {
        emit(specials[i], rounding);
    }
    size_t count = sizeof boundary_values / sizeof boundary_values[0];
    for (size_t i = 0; i < count; ++i) {
        uint64_t centre = bits_of(boundary_values[i]);
        for (int64_t delta = -4; delta <= 4; ++delta) {
            emit((uint64_t)((int64_t)centre + delta), rounding);
        }
    }
    /* Near multiples of ln 2, where argument reduction cancels hardest. */
    for (int k = -1000; k <= 1000; k += 7) {
        double centre = (double)k * 0.6931471805599453;
        uint64_t bits = bits_of(centre);
        for (int64_t delta = -2; delta <= 2; ++delta) {
            emit((uint64_t)((int64_t)bits + delta), rounding);
        }
    }
    /* The closed-form tiny region and its edge. */
    for (int exponent = -80; exponent <= -55; ++exponent) {
        double value = ldexp(1.0, exponent);
        emit(bits_of(value), rounding);
        emit(bits_of(-value), rounding);
    }
}

/* Three strata, so that no region of the domain is starved:
 *   0-59:  the reduction range, exponents in [-60, 10];
 *   60-79: the closed-form tiny range, exponents in [-1074, -60);
 *   80-99: uniform reals across the finite result range, which concentrates
 *          cases on the overflow and underflow edges.
 */
static void emit_random(mpfr_rnd_t rounding, long count, uint64_t seed) {
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
        uint64_t bits = bits_of(sign ? -magnitude : magnitude);
        emit(bits, rounding);
    }
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr,
                "usage: exp_ref <rounding> boundary|random <count> <seed>\n");
        return 2;
    }
    const char *roundingName = argv[1];
    mpfr_rnd_t rounding;
    if (strcmp(roundingName, "rnear_even") == 0) rounding = MPFR_RNDN;
    else if (strcmp(roundingName, "rminMag") == 0) rounding = MPFR_RNDZ;
    else if (strcmp(roundingName, "rmin") == 0) rounding = MPFR_RNDD;
    else if (strcmp(roundingName, "rmax") == 0) rounding = MPFR_RNDU;
    else if (strcmp(roundingName, "rnear_maxMag") == 0) rounding = MPFR_RNDN;
    else {
        fprintf(stderr, "unknown rounding mode %s\n", roundingName);
        return 2;
    }

    mpfr_set_emin(-1073);
    mpfr_set_emax(1024);

    if (strcmp(argv[2], "boundary") == 0) {
        emit_boundary(rounding);
        return 0;
    }
    if (strcmp(argv[2], "random") == 0 && argc == 5) {
        emit_random(rounding, strtol(argv[3], NULL, 10),
                    strtoull(argv[4], NULL, 10));
        return 0;
    }
    fprintf(stderr, "usage: exp_ref <rounding> boundary|random <count> <seed>\n");
    return 2;
}
