kernel void soft_exp_round_kernel(
    device const ulong *a [[buffer(0)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    device uint *certified [[buffer(7)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        bool proven = true;
        output[gid] = soft_exp64_certified(a[gid], roundingMode, raised, proven);
        flags[gid] = raised;
        certified[gid] = uint(proven);
    }
}


// Per-function entry points follow the exp convention: `_certified` returns
// the certificate by reference, `_status` folds an uncertified result into
// flag bit 5, and the flag-free forms discard both.
#define SOFT_M9_UNARY_ENTRY_POINTS(name) \
inline ulong soft_##name##_status(ulong a, uint roundingMode, thread uint &flags) { \
    bool certified = true; \
    ulong result = soft_##name##_certified(a, roundingMode, flags, certified); \
    if (!certified) flags |= soft_flag_uncertified; \
    return result; \
} \
inline ulong soft_##name##_mode(ulong a, uint roundingMode) { \
    uint ignoredFlags = 0u; \
    return soft_##name##_status(a, roundingMode, ignoredFlags); \
} \
inline ulong soft_##name(ulong a) { \
    return soft_##name##_mode(a, soft_round_near_even); \
} \
kernel void soft_##name##_round_kernel( \
    device const ulong *a [[buffer(0)]], \
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]], \
    constant uint &roundingMode [[buffer(4)]], \
    device uint *flags [[buffer(6)]], \
    device uint *certified [[buffer(7)]], \
    uint gid [[thread_position_in_grid]]) \
{ \
    if (gid < count) { \
        uint raised = 0; \
        bool proven = true; \
        output[gid] = soft_##name##_certified(a[gid], roundingMode, raised, proven); \
        flags[gid] = raised; \
        certified[gid] = uint(proven); \
    } \
}

SOFT_M9_UNARY_ENTRY_POINTS(exp2_64)
SOFT_M9_UNARY_ENTRY_POINTS(expm1_64)
SOFT_M9_UNARY_ENTRY_POINTS(log64)
SOFT_M9_UNARY_ENTRY_POINTS(log2_64)
SOFT_M9_UNARY_ENTRY_POINTS(log1p64)
SOFT_M9_UNARY_ENTRY_POINTS(cbrt64)

inline ulong soft_hypot64_status(ulong a, ulong b, uint roundingMode, thread uint &flags) {
    bool certified = true;
    ulong result = soft_hypot64_certified(a, b, roundingMode, flags, certified);
    if (!certified) flags |= soft_flag_uncertified;
    return result;
}

inline ulong soft_hypot64_mode(ulong a, ulong b, uint roundingMode) {
    uint ignoredFlags = 0u;
    return soft_hypot64_status(a, b, roundingMode, ignoredFlags);
}

inline ulong soft_hypot64(ulong a, ulong b) {
    return soft_hypot64_mode(a, b, soft_round_near_even);
}

kernel void soft_hypot64_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    device uint *certified [[buffer(7)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        bool proven = true;
        output[gid] = soft_hypot64_certified(a[gid], b[gid], roundingMode, raised, proven);
        flags[gid] = raised;
        certified[gid] = uint(proven);
    }
}
