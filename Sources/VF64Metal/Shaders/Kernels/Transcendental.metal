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

