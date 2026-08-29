kernel void wide_roundtrip_kernel(
    device const ulong *input [[buffer(0)]], device ulong *output [[buffer(1)]],
    constant uint &count [[buffer(2)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(wide_unpack64(input[gid]));
}

kernel void wide_add_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(
        wide_add(wide_unpack64(a[gid]), wide_unpack64(b[gid]))
    );
}

kernel void wide_sub_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(
        wide_sub(wide_unpack64(a[gid]), wide_unpack64(b[gid]))
    );
}

kernel void wide_mul_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(
        wide_mul(wide_unpack64(a[gid]), wide_unpack64(b[gid]))
    );
}

kernel void wide_div_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(
        wide_div(wide_unpack64(a[gid]), wide_unpack64(b[gid]))
    );
}

kernel void wide_fma_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device const ulong *c [[buffer(2)]], device ulong *output [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = wide_pack64(wide_fma(
        wide_unpack64(a[gid]), wide_unpack64(b[gid]), wide_unpack64(c[gid])
    ));
}

kernel void wide_mul_chain_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    wide_f64 value = wide_unpack64(a[gid]);
    wide_f64 factor = wide_unpack64(b[gid]);
    for (uint i = 0; i < 32; ++i) value = wide_mul(value, factor);
    output[gid] = wide_pack64(value);
}
