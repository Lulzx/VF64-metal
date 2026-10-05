#!/usr/bin/env python3
"""Emit the M9 trigonometric constant block for Shaders/Math/Trig.metal.

Three things are produced:

* the leading 1280 bits of 2/pi as 64-bit words, for Payne-Hanek reduction;
* reciprocal factorials 1/n! as soft_wide literals truncated toward zero, as
  in generate-exp-constants.py, for the sine and cosine series;
* a rigorous lower bound on |x - k pi/2| over every binary64 x >= pi/4, which
  the reduction's error bound depends on, and the arguments that come closest
  to a multiple of pi/2 (tools/m9/trig_worst_cases.h, for the MPFR corpus).

pi comes from Machin's formula in integer arithmetic and is cross-checked
against mpmath when it is installed.

The bound: write x = M 2^E with M a 53-bit integer, so x (2/pi) = M a_E with
a_E = 2^E (2/pi). The distance from x 2/pi to the nearest integer is
||M frac(a_E)||, and for every M < 2^53 that is at least ||q frac(a_E)||,
where q is the largest continued-fraction convergent denominator of frac(a_E)
below 2^53 (best approximation of the second kind). frac(a_E) is evaluated to
2^-200, which moves ||M a_E|| by under 2^53 2^-199, and that slack is
subtracted. E ranges over [-53, 971]; below that |x| < pi/4 and no reduction
is done.

Usage: python3 tools/m9/generate-trig-constants.py \
           --worst-cases tools/m9/trig_worst_cases.h
"""
import argparse
import math
from fractions import Fraction

PRECISION = 2200          # bits of the fixed-point pi computation
TABLE_WORDS = 20          # 1280 bits of 2/pi
FACTORIALS = 33           # 1/n! for n = 0..32
SIN_TERMS = 15            # sin r = r sum_{k=0..15} (-1)^k r^(2k) / (2k+1)!
COS_TERMS = 16            # cos r = sum_{k=0..16} (-1)^k r^(2k) / (2k)!
FRACTION_BITS = 200       # precision of frac(2^E 2/pi) in the search
E_MIN, E_MAX = -53, 971


def arctan_inverse(n: int, bits: int) -> int:
    """arctan(1/n) 2^bits, truncated, to within a few units."""
    total = 0
    power = (1 << bits) // n
    k = 0
    n2 = n * n
    while power:
        term = power // (2 * k + 1)
        total += -term if k % 2 else term
        power //= n2
        k += 1
    return total


def pi_fixed(bits: int) -> int:
    guard = 64
    value = 16 * arctan_inverse(5, bits + guard) - 4 * arctan_inverse(239, bits + guard)
    return value >> guard


def wide(numerator: int, denominator: int) -> str:
    """A positive rational as a soft_wide literal, truncated toward zero."""
    exponent = numerator.bit_length() - denominator.bit_length()
    # Normalize so that value / 2^exponent is in [1/2, 1).
    while Fraction(numerator, denominator) >= Fraction(2) ** exponent:
        exponent += 1
    while Fraction(numerator, denominator) < Fraction(2) ** (exponent - 1):
        exponent -= 1
    shift = 128 - exponent
    sig = (numerator << shift) // denominator if shift >= 0 else numerator // (denominator << -shift)
    assert 1 << 127 <= sig < 1 << 128
    return (
        f"soft_wide{{0x{sig >> 64:016x}ul, 0x{sig & ((1 << 64) - 1):016x}ul, "
        f"{exponent}, false}}"
    )


def log2(value: float) -> str:
    return f"{math.log2(value):.1f}"


def convergents(numerator: int, denominator: int, limit: int):
    """Continued-fraction convergent denominators of n/d below limit."""
    q_prev, q = 1, 0
    p_prev, p = 0, 1
    n, d = numerator, denominator
    result = []
    while d:
        a = n // d
        n, d = d, n - a * d
        p_prev, p = p, a * p + p_prev
        q_prev, q = q, a * q + q_prev
        if q >= limit:
            break
        result.append((p, q))
    return result


def distance_to_integer(value: Fraction) -> Fraction:
    floor = value.numerator // value.denominator
    low = value - floor
    return min(low, 1 - low)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--worst-cases", help="write the hardest arguments as a C header")
    options = parser.parse_args()

    pi = pi_fixed(PRECISION)                       # pi 2^PRECISION
    two_over_pi = (2 << (2 * PRECISION)) // pi     # (2/pi) 2^PRECISION
    try:
        import mpmath
        mpmath.mp.prec = PRECISION + 64
        reference = int(mpmath.floor(2 / mpmath.pi * mpmath.mpf(2) ** PRECISION))
        assert abs(reference - two_over_pi) < 1 << 16, "2/pi disagrees with mpmath"
        checked = "cross-checked against mpmath"
    except ImportError:
        checked = "not cross-checked: mpmath unavailable"

    # Words of 2/pi: word k holds bits 64k+1 .. 64k+64 after the binary point.
    table_bits = 64 * TABLE_WORDS
    leading = two_over_pi >> (PRECISION - table_bits)
    words = [(leading >> (64 * (TABLE_WORDS - 1 - k))) & ((1 << 64) - 1)
             for k in range(TABLE_WORDS)]

    # Reduction search.
    minimum = None
    worst = []
    slack = Fraction(1, 1 << (FRACTION_BITS - 53 - 1))
    for E in range(E_MIN, E_MAX + 1):
        shift = PRECISION - E - FRACTION_BITS
        scaled = two_over_pi >> shift if shift >= 0 else two_over_pi << -shift
        fraction = scaled & ((1 << FRACTION_BITS) - 1)
        alpha = Fraction(fraction, 1 << FRACTION_BITS)
        best = convergents(fraction, 1 << FRACTION_BITS, 1 << 53)
        p, q = best[-1]
        bound = distance_to_integer(q * alpha) - slack
        assert bound > 0
        if minimum is None or bound < minimum[0]:
            minimum = (bound, E, q)
        # A 53-bit multiple of the best denominator, for the test corpus.
        for p, q in best[-3:]:
            if q == 0:
                continue
            multiple = q * -(-(1 << 52) // q)
            if multiple < 1 << 53:
                worst.append((distance_to_integer(multiple * alpha), multiple, E))

    bound, worst_e, worst_q = minimum
    reduced = float(bound) * math.pi / 2

    print("// Generated by tools/m9/generate-trig-constants.py. Do not edit by hand.")
    print(f"// 2/pi to {table_bits} bits, {checked}; word k holds bits")
    print("// 64k+1 .. 64k+64 after the binary point, truncated.")
    print(f"constant ulong SOFT_TRIG_TWO_OVER_PI[{TABLE_WORDS}] = {{")
    for k in range(0, TABLE_WORDS, 2):
        print(f"    0x{words[k]:016x}ul, 0x{words[k + 1]:016x}ul,")
    print("};")
    print()
    print(f"constant soft_wide SOFT_TRIG_RECIPROCAL_FACTORIAL[{FACTORIALS}] = {{")
    for n in range(FACTORIALS):
        print(f"    {wide(1, math.factorial(n))},  // 1/{n}!")
    print("};")
    print(f"constant int SOFT_TRIG_SIN_TERMS = {SIN_TERMS};")
    print(f"constant int SOFT_TRIG_COS_TERMS = {COS_TERMS};")
    r = math.pi / 4
    sin_tail = r ** (2 * SIN_TERMS + 2) / math.factorial(2 * SIN_TERMS + 3)
    cos_tail = r ** (2 * COS_TERMS + 2) / math.factorial(2 * COS_TERMS + 2) / math.cos(r)
    print(f"// truncated series tails at |r| <= pi/4: sine < 2^{log2(sin_tail)} relative,")
    print(f"// cosine < 2^{log2(cos_tail)} relative")
    print(f"// min |x - k pi/2| over binary64 x >= pi/4: > 2^{log2(reduced)}")
    print(f"// (x 2/pi within 2^{log2(float(bound))} of an integer, at exponent {worst_e})")

    if options.worst_cases:
        worst = sorted(set(worst))
        with open(options.worst_cases, "w") as out:
            out.write("/* Generated by tools/m9/generate-trig-constants.py. Do not edit by hand.\n")
            out.write(" * Binary64 arguments M 2^E closest to a multiple of pi/2, one or more\n")
            out.write(" * per exponent, hardest first: the trigonometric reduction stress corpus. */\n")
            out.write(f"static const uint64_t trig_worst_cases[{len(worst)}] = {{\n")
            for _, multiple, E in worst:
                value = math.ldexp(float(multiple), E)
                bits = int.from_bytes(__import__("struct").pack(">d", value), "big")
                out.write(f"    0x{bits:016x}ull,\n")
            out.write("};\n")


if __name__ == "__main__":
    main()
