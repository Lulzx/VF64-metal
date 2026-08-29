#include <metal_stdlib>
using namespace metal;

// Error-free transforms require source-order evaluation. Explicit fma() calls
// below remain fused; implicit contraction and reassociation must stay disabled.
#pragma METAL fp math_mode(safe)
#pragma METAL fp contract(off)

struct emu_f64 {
    float hi;
    float lo;
};

struct wide_f64 {
    emu_f64 significand;
    int exponent;
    uint reserved;
};

inline emu_f64 from_float2(float2 value);
inline float2 to_float2(emu_f64 value);
