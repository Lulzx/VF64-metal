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

kernel void nbody_fp32_kernel(
    device const ulong *px [[buffer(0)]], device const ulong *py [[buffer(1)]],
    device const ulong *pz [[buffer(2)]], device const ulong *mass [[buffer(3)]],
    device ulong *axOut [[buffer(4)]], device ulong *ayOut [[buffer(5)]],
    device ulong *azOut [[buffer(6)]], device const ulong *softening [[buffer(7)]],
    constant uint &count [[buffer(8)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    float xi = unpack_binary64(px[gid], ignored).hi;
    float yi = unpack_binary64(py[gid], ignored).hi;
    float zi = unpack_binary64(pz[gid], ignored).hi;
    float epsilon2 = unpack_binary64(softening[0], ignored).hi;
    float ax = 0.0f, ay = 0.0f, az = 0.0f;
    for (uint j = 0; j < count; ++j) {
        float dx = unpack_binary64(px[j], ignored).hi - xi;
        float dy = unpack_binary64(py[j], ignored).hi - yi;
        float dz = unpack_binary64(pz[j], ignored).hi - zi;
        float r2 = fma(dx, dx, fma(dy, dy, fma(dz, dz, epsilon2)));
        float scale = unpack_binary64(mass[j], ignored).hi / (r2 * sqrt(r2));
        ax = fma(dx, scale, ax);
        ay = fma(dy, scale, ay);
        az = fma(dz, scale, az);
    }
    axOut[gid] = pack_binary64(make_emu(ax, 0.0f));
    ayOut[gid] = pack_binary64(make_emu(ay, 0.0f));
    azOut[gid] = pack_binary64(make_emu(az, 0.0f));
}

kernel void nbody_fast48_kernel(
    device const ulong *px [[buffer(0)]], device const ulong *py [[buffer(1)]],
    device const ulong *pz [[buffer(2)]], device const ulong *mass [[buffer(3)]],
    device ulong *axOut [[buffer(4)]], device ulong *ayOut [[buffer(5)]],
    device ulong *azOut [[buffer(6)]], device const ulong *softening [[buffer(7)]],
    constant uint &count [[buffer(8)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 xi = unpack_binary64(px[gid], ignored);
    emu_f64 yi = unpack_binary64(py[gid], ignored);
    emu_f64 zi = unpack_binary64(pz[gid], ignored);
    emu_f64 epsilon2 = unpack_binary64(softening[0], ignored);
    emu_f64 ax = make_emu(0.0f, 0.0f);
    emu_f64 ay = make_emu(0.0f, 0.0f);
    emu_f64 az = make_emu(0.0f, 0.0f);
    for (uint j = 0; j < count; ++j) {
        emu_f64 dx = sub_ff(unpack_binary64(px[j], ignored), xi);
        emu_f64 dy = sub_ff(unpack_binary64(py[j], ignored), yi);
        emu_f64 dz = sub_ff(unpack_binary64(pz[j], ignored), zi);
        emu_f64 r2 = fma_ff(dx, dx, fma_ff(dy, dy, fma_ff(dz, dz, epsilon2)));
        emu_f64 scale = div_ff(
            unpack_binary64(mass[j], ignored), mul_ff(r2, sqrt_ff(r2))
        );
        ax = fma_ff(dx, scale, ax);
        ay = fma_ff(dy, scale, ay);
        az = fma_ff(dz, scale, az);
    }
    axOut[gid] = pack_binary64(ax);
    ayOut[gid] = pack_binary64(ay);
    azOut[gid] = pack_binary64(az);
}

kernel void nbody_wide48_kernel(
    device const ulong *px [[buffer(0)]], device const ulong *py [[buffer(1)]],
    device const ulong *pz [[buffer(2)]], device const ulong *mass [[buffer(3)]],
    device ulong *axOut [[buffer(4)]], device ulong *ayOut [[buffer(5)]],
    device ulong *azOut [[buffer(6)]], device const ulong *softening [[buffer(7)]],
    constant uint &count [[buffer(8)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    wide_f64 xi = wide_unpack64(px[gid]);
    wide_f64 yi = wide_unpack64(py[gid]);
    wide_f64 zi = wide_unpack64(pz[gid]);
    wide_f64 epsilon2 = wide_unpack64(softening[0]);
    wide_f64 ax = wide_unpack64(0ul), ay = wide_unpack64(0ul), az = wide_unpack64(0ul);
    for (uint j = 0; j < count; ++j) {
        wide_f64 dx = wide_sub(wide_unpack64(px[j]), xi);
        wide_f64 dy = wide_sub(wide_unpack64(py[j]), yi);
        wide_f64 dz = wide_sub(wide_unpack64(pz[j]), zi);
        wide_f64 r2 = wide_fma(dx, dx, wide_fma(dy, dy, wide_fma(dz, dz, epsilon2)));
        wide_f64 scale = wide_div(
            wide_unpack64(mass[j]), wide_mul(r2, wide_sqrt(r2))
        );
        ax = wide_fma(dx, scale, ax);
        ay = wide_fma(dy, scale, ay);
        az = wide_fma(dz, scale, az);
    }
    axOut[gid] = wide_pack64(ax);
    ayOut[gid] = wide_pack64(ay);
    azOut[gid] = wide_pack64(az);
}

kernel void nbody_ieee64_kernel(
    device const ulong *px [[buffer(0)]], device const ulong *py [[buffer(1)]],
    device const ulong *pz [[buffer(2)]], device const ulong *mass [[buffer(3)]],
    device ulong *axOut [[buffer(4)]], device ulong *ayOut [[buffer(5)]],
    device ulong *azOut [[buffer(6)]], device const ulong *softening [[buffer(7)]],
    constant uint &count [[buffer(8)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint flags = 0;
    ulong ax = 0ul, ay = 0ul, az = 0ul;
    for (uint j = 0; j < count; ++j) {
        ulong dx = soft_sub64_status(px[j], px[gid], soft_round_near_even, flags);
        ulong dy = soft_sub64_status(py[j], py[gid], soft_round_near_even, flags);
        ulong dz = soft_sub64_status(pz[j], pz[gid], soft_round_near_even, flags);
        ulong r2 = soft_fma64_status(dz, dz, softening[0], soft_round_near_even, flags);
        r2 = soft_fma64_status(dy, dy, r2, soft_round_near_even, flags);
        r2 = soft_fma64_status(dx, dx, r2, soft_round_near_even, flags);
        ulong root = soft_sqrt64_status(r2, soft_round_near_even, flags);
        ulong denominator = soft_mul64_status(r2, root, soft_round_near_even, flags);
        ulong scale = soft_div64_status(mass[j], denominator, soft_round_near_even, flags);
        ax = soft_fma64_status(dx, scale, ax, soft_round_near_even, flags);
        ay = soft_fma64_status(dy, scale, ay, soft_round_near_even, flags);
        az = soft_fma64_status(dz, scale, az, soft_round_near_even, flags);
    }
    axOut[gid] = ax;
    ayOut[gid] = ay;
    azOut[gid] = az;
}
