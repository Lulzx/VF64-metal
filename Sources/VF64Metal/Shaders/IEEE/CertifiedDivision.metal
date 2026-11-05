/*

License for Berkeley SoftFloat Release 3e

John R. Hauser
2018 January 20

The following applies to the whole of SoftFloat Release 3e as well as to
each source file individually.

Copyright 2011, 2012, 2013, 2014, 2015, 2016, 2017, 2018 The Regents of the
University of California.  All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

 1. Redistributions of source code must retain the above copyright notice,
    this list of conditions, and the following disclaimer.

 2. Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions, and the following disclaimer in the
    documentation and/or other materials provided with the distribution.

 3. Neither the name of the University nor the names of its contributors
    may be used to endorse or promote products derived from this software
    without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE REGENTS AND CONTRIBUTORS "AS IS", AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, ARE
DISCLAIMED.  IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR ANY
DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/
#ifndef VF64_CERTIFIED_DIVISION_INCLUDED
#define VF64_CERTIFIED_DIVISION_INCLUDED

#include <metal_stdlib>

constant ushort soft_reciprocal_k0[16] = {
0xFFC4,0xF0BE,0xE363,0xD76F,0xCCAD,0xC2F0,0xBA16,0xB201,
0xAA97,0xA3C6,0x9D7A,0x97A6,0x923C,0x8D32,0x887E,0x8417,
};
constant ushort soft_reciprocal_k1[16] = {
0xF0F1,0xD62C,0xBFA1,0xAC77,0x9C0A,0x8DDB,0x8185,0x76BA,
0x6D3B,0x64D4,0x5D5C,0x56B1,0x50B6,0x4B55,0x4679,0x4211,
};

// SoftFloat's table interpolation gives a lower-sided reciprocal estimate.
// The exact certificate protects the quotient even for arbitrary coefficients.
inline void soft_certified_division_leaf(
    const ulong u, const ulong v, const uint k0, const uint k1,
    thread ulong* proxy, thread bool* accepted, thread bool* boundary,
    thread bool* repaired)
{
    const ulong C = 1ul << 63;
    const ulong b = v >> 32;
    const uint epsilon = (static_cast<uint>(b) >> 11) & 0xffffu;
    const uint r0 = k0 - ((k1 * epsilon) >> 20);
    const uint sigma = ~static_cast<uint>((static_cast<ulong>(r0) * b) >> 7);
    const uint r1 = (r0 << 16) + static_cast<uint>((static_cast<ulong>(r0) * sigma) >> 24);
    const uint seed = r1 + (metal::mulhi(r1, metal::mulhi(sigma, sigma)) >> 16);
    ulong r = seed;
    ulong br = b * r;

    // Repair the cited 2.006-unit seed bound to the strict two-unit certificate.
    const bool repair = br < C && C - br >= (b << 1);
    const bool seedBelow = br < C;
    if (repair) {
        ++r;
        br += b;
    }
    const bool certified = seedBelow && br < C && C - br < (b << 1);
    const uint rho = static_cast<uint>((certified ? r : 0x80000000ul) - 2);
    *repaired = repair;

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
