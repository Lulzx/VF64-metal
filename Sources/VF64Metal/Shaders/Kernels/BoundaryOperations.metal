kernel void div_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(div_ff(unpack_binary64(a[gid], ignored),
                                       unpack_binary64(b[gid], ignored)));
}

kernel void div_one_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(div_ff_one_correction(unpack_binary64(a[gid], ignored),
                                                      unpack_binary64(b[gid], ignored)));
}

kernel void fma_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device const ulong *c [[buffer(2)]], device ulong *output [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(fma_ff(unpack_binary64(a[gid], ignored),
                                       unpack_binary64(b[gid], ignored),
                                       unpack_binary64(c[gid], ignored)));
}

kernel void axpy_kernel(
    device const ulong *alpha [[buffer(0)]], device const ulong *x [[buffer(1)]],
    device const ulong *y [[buffer(2)]], device ulong *output [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 av = unpack_binary64(alpha[0], ignored);
    output[gid] = pack_binary64(fma_ff(av, unpack_binary64(x[gid], ignored),
                                      unpack_binary64(y[gid], ignored)));
}

