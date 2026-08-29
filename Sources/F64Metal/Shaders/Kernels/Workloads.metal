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
