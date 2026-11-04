#ifndef VF64_CERTIFIED_DIVISION_INCLUDED
#define VF64_CERTIFIED_DIVISION_INCLUDED

#include <metal_stdlib>

// Quotient proxy for round-to-nearest division of normalized significands.
// docs/certified-division.md states the operand ranges and derives each bound.
// Unsigned wraparound in the residuals is intended.
inline void soft_certified_division_leaf(
    const ulong u, const ulong v, const float estimate,
    thread ulong* proxy, thread bool* accepted, thread bool* boundary)
{
    const ulong C = 1ul << 63;
    const ulong b = v >> 32;

    // Ordered comparisons also reject NaN before the integer conversion.
    const bool seedConvertible = estimate >= 0.0f && estimate < 0x1p33f;
    ulong seed = static_cast<ulong>(seedConvertible ? estimate : 0.0f);
    seed = seed < 0x80000000ul ? 0x80000000ul : seed;
    seed = seed > 0xfffffffful ? 0xfffffffful : seed;

    // One integer Newton step towards R = C / b.
    const ulong bs = b * seed;
    const bool tooLarge = bs > C;
    const ulong error = tooLarge ? bs - C : C - bs;
    const ulong step = (metal::mulhi(seed, error) << 1) | ((seed * error) >> 63);
    ulong r = tooLarge ? seed - step : seed + step;

    // Ensure b r < C; then C - b r < 2b certifies 0 < R - r < 2.
    ulong br = b * r;
    if (br >= C) {
        r -= 1;
        br -= b;
    }
    const bool certified = seedConvertible && br < C && C - br < (b << 1);
    const uint rho = static_cast<uint>((certified ? r : 0x80000000ul) - 2);

    // First quotient digit h and the remainder W = (U 2^31 - h V) / 8.
    const uint h = metal::mulhi(static_cast<uint>(u >> 32), rho);
    const ulong w = (u << 28) - static_cast<ulong>(h) * (v >> 3);
    const ulong high = static_cast<ulong>(h) << 32;

    // Second digit, biased so that the proxy lies within (-16, 64) of U 2^63 / V.
    const uint q = metal::mulhi(static_cast<uint>(w >> 32), rho) + 4u;
    const ulong biased = high + (static_cast<ulong>(q) << 4);

    // Near a rounding threshold, the exact residual of q rounded down to a
    // multiple of eight decides on which side the quotient lies.
    const bool nearThreshold = (q & 31u) < 4u;
    const uint qDown = q & ~7u;
    const ulong residual = (w << 28) - static_cast<ulong>(qDown) * (v >> 3);
    const ulong down = high + (static_cast<ulong>(qDown) << 4);
    ulong corrected;
    if ((residual >> 63) != 0)
        corrected = down - 0x80ul;
    else if (residual == 0)
        corrected = down;
    else
        corrected = down + 1;

    *proxy = nearThreshold ? corrected : biased;
    *accepted = certified;
    *boundary = nearThreshold;
}

#endif
