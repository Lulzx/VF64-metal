kernel void soft_add_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_add64(a[gid], b[gid]);
}

kernel void soft_mul_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = soft_mul64(a[gid], b[gid]);
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

