kernel void soft_add_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_add64(a[gid], b[gid]);
}

kernel void soft_sub_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_sub64(a[gid], b[gid]);
}

kernel void soft_mul_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_mul64(a[gid], b[gid]);
}

kernel void soft_div_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_div64(a[gid], b[gid]);
}

kernel void soft_sqrt_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *unused [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    (void)unused;
    if (gid < count) output[gid] = soft_sqrt64(a[gid]);
}

kernel void soft_add_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_add64_status(a[gid], b[gid], roundingMode, raised);
        flags[gid] = raised;
    }
}

kernel void soft_sub_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_sub64_status(a[gid], b[gid], roundingMode, raised);
        flags[gid] = raised;
    }
}

kernel void soft_mul_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_mul64_status(a[gid], b[gid], roundingMode, raised);
        flags[gid] = raised;
    }
}

kernel void soft_div_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_div64_status(a[gid], b[gid], roundingMode, raised);
        flags[gid] = raised;
    }
}

kernel void soft_sqrt_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *unused [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    (void)unused;
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_sqrt64_status(a[gid], roundingMode, raised);
        flags[gid] = raised;
    }
}

kernel void soft_fma_round_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device const ulong *c [[buffer(5)]],
    device uint *flags [[buffer(6)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_fma64_status(
            a[gid], b[gid], c[gid], roundingMode, raised
        );
        flags[gid] = raised;
    }
}

kernel void soft_eq_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_equal64_status(a[gid], b[gid], false, raised));
        flags[gid] = raised;
    }
}

kernel void soft_eq_signaling_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_equal64_status(a[gid], b[gid], true, raised));
        flags[gid] = raised;
    }
}

kernel void soft_lt_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_less64_status(a[gid], b[gid], false, false, raised));
        flags[gid] = raised;
    }
}

kernel void soft_le_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_less64_status(a[gid], b[gid], true, false, raised));
        flags[gid] = raised;
    }
}

kernel void soft_lt_quiet_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_less64_status(a[gid], b[gid], false, true, raised));
        flags[gid] = raised;
    }
}

kernel void soft_le_quiet_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    device uint *flags [[buffer(6)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = ulong(soft_less64_status(a[gid], b[gid], true, true, raised));
        flags[gid] = raised;
    }
}

kernel void soft_round_to_int_kernel(
    device const ulong *a [[buffer(0)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    constant uint &roundingMode [[buffer(4)]],
    device uint *flags [[buffer(6)]], constant uint &exact [[buffer(7)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) {
        uint raised = 0;
        output[gid] = soft_round_to_int64_status(
            a[gid], roundingMode, exact != 0, raised
        );
        flags[gid] = raised;
    }
}

kernel void soft_add_chain_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    ulong value = a[gid];
    ulong term = b[gid];
    for (uint i = 0; i < 32; ++i) value = soft_add64(value, term);
    output[gid] = value;
}

kernel void soft_mul_chain_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    ulong value = a[gid];
    ulong factor = b[gid];
    for (uint i = 0; i < 32; ++i) value = soft_mul64(value, factor);
    output[gid] = value;
}
