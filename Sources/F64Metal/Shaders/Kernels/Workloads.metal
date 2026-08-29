kernel void spmv_fp32_kernel(
    device const uint *rowOffsets [[buffer(0)]],
    device const uint *columns [[buffer(1)]],
    device const ulong *values [[buffer(2)]],
    device const ulong *x [[buffer(3)]],
    device ulong *output [[buffer(4)]],
    constant uint &rowCount [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= rowCount) return;
    float accumulator = 0.0f;
    bool ignored;
    for (uint entry = rowOffsets[row]; entry < rowOffsets[row + 1u]; ++entry) {
        float a = unpack_binary64(values[entry], ignored).hi;
        float b = unpack_binary64(x[columns[entry]], ignored).hi;
        accumulator = fma(a, b, accumulator);
    }
    output[row] = pack_binary64(make_emu(accumulator, 0.0f));
}

kernel void spmv_fast48_kernel(
    device const uint *rowOffsets [[buffer(0)]],
    device const uint *columns [[buffer(1)]],
    device const ulong *values [[buffer(2)]],
    device const ulong *x [[buffer(3)]],
    device ulong *output [[buffer(4)]],
    constant uint &rowCount [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= rowCount) return;
    emu_f64 accumulator = make_emu(0.0f, 0.0f);
    bool ignored;
    for (uint entry = rowOffsets[row]; entry < rowOffsets[row + 1u]; ++entry) {
        accumulator = fma_ff(
            unpack_binary64(values[entry], ignored),
            unpack_binary64(x[columns[entry]], ignored), accumulator
        );
    }
    output[row] = pack_binary64(accumulator);
}

kernel void spmv_wide48_kernel(
    device const uint *rowOffsets [[buffer(0)]],
    device const uint *columns [[buffer(1)]],
    device const ulong *values [[buffer(2)]],
    device const ulong *x [[buffer(3)]],
    device ulong *output [[buffer(4)]],
    constant uint &rowCount [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= rowCount) return;
    wide_f64 accumulator = wide_unpack64(0ul);
    for (uint entry = rowOffsets[row]; entry < rowOffsets[row + 1u]; ++entry) {
        accumulator = wide_fma(
            wide_unpack64(values[entry]),
            wide_unpack64(x[columns[entry]]), accumulator
        );
    }
    output[row] = wide_pack64(accumulator);
}

kernel void spmv_ieee64_kernel(
    device const uint *rowOffsets [[buffer(0)]],
    device const uint *columns [[buffer(1)]],
    device const ulong *values [[buffer(2)]],
    device const ulong *x [[buffer(3)]],
    device ulong *output [[buffer(4)]],
    constant uint &rowCount [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= rowCount) return;
    ulong accumulator = 0ul;
    uint ignoredFlags = 0;
    for (uint entry = rowOffsets[row]; entry < rowOffsets[row + 1u]; ++entry) {
        accumulator = soft_fma64_status(
            values[entry], x[columns[entry]], accumulator,
            soft_round_near_even, ignoredFlags
        );
    }
    output[row] = accumulator;
}

kernel void cg_update_x_r_fast48_kernel(
    device const ulong *alpha [[buffer(0)]],
    device const ulong *p [[buffer(1)]],
    device const ulong *ap [[buffer(2)]],
    device ulong *x [[buffer(3)]],
    device ulong *r [[buffer(4)]],
    constant uint &count [[buffer(5)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 scale = unpack_binary64(alpha[0], ignored);
    emu_f64 pv = unpack_binary64(p[gid], ignored);
    emu_f64 xv = unpack_binary64(x[gid], ignored);
    emu_f64 rv = unpack_binary64(r[gid], ignored);
    emu_f64 apv = unpack_binary64(ap[gid], ignored);
    x[gid] = pack_binary64(fma_ff(scale, pv, xv));
    r[gid] = pack_binary64(fma_ff(neg_ff(scale), apv, rv));
}

kernel void cg_update_p_fast48_kernel(
    device const ulong *beta [[buffer(0)]],
    device const ulong *r [[buffer(1)]],
    device ulong *p [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 scale = unpack_binary64(beta[0], ignored);
    emu_f64 rv = unpack_binary64(r[gid], ignored);
    emu_f64 pv = unpack_binary64(p[gid], ignored);
    p[gid] = pack_binary64(fma_ff(scale, pv, rv));
}

kernel void vector_scale_fast48_kernel(
    device const ulong *scale [[buffer(0)]],
    device const ulong *input [[buffer(1)]],
    device ulong *output [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = pack_binary64(mul_ff(
        unpack_binary64(scale[0], ignored),
        unpack_binary64(input[gid], ignored)
    ));
}

kernel void gemm_fp32_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &dimension [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint row = gid / dimension;
    uint column = gid % dimension;
    float accumulator = 0.0f;
    bool ignored;
    for (uint k = 0; k < dimension; ++k) {
        accumulator = fma(
            unpack_binary64(a[row * dimension + k], ignored).hi,
            unpack_binary64(b[k * dimension + column], ignored).hi,
            accumulator
        );
    }
    output[gid] = pack_binary64(make_emu(accumulator, 0.0f));
}

kernel void gemm_fast48_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &dimension [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint row = gid / dimension;
    uint column = gid % dimension;
    emu_f64 accumulator = make_emu(0.0f, 0.0f);
    bool ignored;
    for (uint k = 0; k < dimension; ++k) {
        accumulator = fma_ff(
            unpack_binary64(a[row * dimension + k], ignored),
            unpack_binary64(b[k * dimension + column], ignored), accumulator
        );
    }
    output[gid] = pack_binary64(accumulator);
}

kernel void gemm_wide48_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &dimension [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint row = gid / dimension;
    uint column = gid % dimension;
    wide_f64 accumulator = wide_unpack64(0ul);
    for (uint k = 0; k < dimension; ++k) {
        accumulator = wide_fma(
            wide_unpack64(a[row * dimension + k]),
            wide_unpack64(b[k * dimension + column]), accumulator
        );
    }
    output[gid] = wide_pack64(accumulator);
}

kernel void gemm_ieee64_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device ulong *output [[buffer(2)]], constant uint &dimension [[buffer(3)]],
    constant uint &count [[buffer(4)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint row = gid / dimension;
    uint column = gid % dimension;
    ulong accumulator = 0ul;
    uint ignoredFlags = 0;
    for (uint k = 0; k < dimension; ++k) {
        accumulator = soft_fma64_status(
            a[row * dimension + k], b[k * dimension + column], accumulator,
            soft_round_near_even, ignoredFlags
        );
    }
    output[gid] = accumulator;
}
