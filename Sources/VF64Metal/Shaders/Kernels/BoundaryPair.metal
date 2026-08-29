kernel void codec_roundtrip(
    device const ulong *input [[buffer(0)]],
    device ulong *output [[buffer(1)]],
    device uint *rangeFlags [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool rangeFlag;
    emu_f64 value = unpack_binary64(input[gid], rangeFlag);
    output[gid] = pack_binary64(value);
    rangeFlags[gid] = rangeFlag ? 1u : 0u;
}

kernel void add_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(add_ff(unpack_binary64(a[gid], ignored),
                                       unpack_binary64(b[gid], ignored)));
}

kernel void mul_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(mul_ff(unpack_binary64(a[gid], ignored),
                                       unpack_binary64(b[gid], ignored)));
}

kernel void mul_short_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(mul_ff_short(unpack_binary64(a[gid], ignored),
                                             unpack_binary64(b[gid], ignored)));
}

kernel void mul_dekker_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(mul_ff_dekker(unpack_binary64(a[gid], ignored),
                                              unpack_binary64(b[gid], ignored)));
}

