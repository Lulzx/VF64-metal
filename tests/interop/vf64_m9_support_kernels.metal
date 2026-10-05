// M9 conformance kernels for the linkable support ABI. Each kernel calls the
// vf64_<name>_rne or vf64_<name>_round symbol as an unresolved external, the
// way a source-language backend does, and is statically linked against
// vf64-support.air with air-link. The buffer layout matches the
// soft_<name>_round_kernel campaign kernels, minus the flag and certificate
// buffers, which this ABI does not return. Round-to-nearest-even dispatches
// exercise the _rne symbol; the other four modes exercise _round.
#include <metal_stdlib>

#define VF64_M9_UNARY_SUPPORT_KERNEL(name) \
extern "C" ulong vf64_##name##_rne(ulong a); \
extern "C" ulong vf64_##name##_round(ulong a, uint roundingMode); \
kernel void vf64_##name##_support_kernel( \
    device const ulong *a [[buffer(0)]], \
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]], \
    constant uint &roundingMode [[buffer(4)]], \
    uint gid [[thread_position_in_grid]]) \
{ \
    if (gid < count) { \
        output[gid] = roundingMode == 0u \
            ? vf64_##name##_rne(a[gid]) \
            : vf64_##name##_round(a[gid], roundingMode); \
    } \
}

#define VF64_M9_BINARY_SUPPORT_KERNEL(name) \
extern "C" ulong vf64_##name##_rne(ulong a, ulong b); \
extern "C" ulong vf64_##name##_round(ulong a, ulong b, uint roundingMode); \
kernel void vf64_##name##_support_kernel( \
    device const ulong *a [[buffer(0)]], \
    device const ulong *b [[buffer(1)]], \
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]], \
    constant uint &roundingMode [[buffer(4)]], \
    uint gid [[thread_position_in_grid]]) \
{ \
    if (gid < count) { \
        output[gid] = roundingMode == 0u \
            ? vf64_##name##_rne(a[gid], b[gid]) \
            : vf64_##name##_round(a[gid], b[gid], roundingMode); \
    } \
}

VF64_M9_UNARY_SUPPORT_KERNEL(exp)
VF64_M9_UNARY_SUPPORT_KERNEL(exp2)
VF64_M9_UNARY_SUPPORT_KERNEL(expm1)
VF64_M9_UNARY_SUPPORT_KERNEL(log)
VF64_M9_UNARY_SUPPORT_KERNEL(log2)
VF64_M9_UNARY_SUPPORT_KERNEL(log1p)
VF64_M9_UNARY_SUPPORT_KERNEL(cbrt)
VF64_M9_BINARY_SUPPORT_KERNEL(hypot)
VF64_M9_BINARY_SUPPORT_KERNEL(pow)
VF64_M9_UNARY_SUPPORT_KERNEL(atan)
VF64_M9_BINARY_SUPPORT_KERNEL(atan2)
VF64_M9_UNARY_SUPPORT_KERNEL(asin)
VF64_M9_UNARY_SUPPORT_KERNEL(acos)
VF64_M9_UNARY_SUPPORT_KERNEL(sin)
VF64_M9_UNARY_SUPPORT_KERNEL(cos)
VF64_M9_UNARY_SUPPORT_KERNEL(tan)
VF64_M9_UNARY_SUPPORT_KERNEL(sinh)
VF64_M9_UNARY_SUPPORT_KERNEL(cosh)
VF64_M9_UNARY_SUPPORT_KERNEL(tanh)
VF64_M9_UNARY_SUPPORT_KERNEL(asinh)
VF64_M9_UNARY_SUPPORT_KERNEL(acosh)
VF64_M9_UNARY_SUPPORT_KERNEL(atanh)
