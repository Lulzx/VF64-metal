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

kernel void scalar_copy_fast48_kernel(
    device const ulong *input [[buffer(0)]],
    device ulong *output [[buffer(1)]])
{
    output[0] = input[0];
}

kernel void cg_check_convergence_fast48_kernel(
    device const ulong *residualSquared [[buffer(0)]],
    device const ulong *initialResidualSquared [[buffer(1)]],
    device uint *completed [[buffer(2)]],
    device ulong *convergedResidualSquared [[buffer(3)]],
    constant uint &iteration [[buffer(4)]],
    constant uint &maximumIterations [[buffer(5)]],
    constant float &tolerance [[buffer(6)]])
{
    bool ignored;
    emu_f64 rr = unpack_binary64(residualSquared[0], ignored);
    emu_f64 initial = unpack_binary64(initialResidualSquared[0], ignored);
    float threshold = tolerance * tolerance * (initial.hi + initial.lo);
    bool reachedTolerance = rr.hi + rr.lo <= threshold;
    if (completed[0] == 0u && (reachedTolerance || iteration == maximumIterations)) {
        completed[0] = iteration;
        convergedResidualSquared[0] = residualSquared[0];
    }
}

kernel void cg_snapshot_solution_fast48_kernel(
    device const uint *completed [[buffer(0)]],
    device const ulong *x [[buffer(1)]],
    device ulong *solution [[buffer(2)]],
    constant uint &iteration [[buffer(3)]],
    constant uint &count [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count && completed[0] == iteration) solution[gid] = x[gid];
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

kernel void scalar_div_fast48_kernel(
    device const ulong *numerator [[buffer(0)]],
    device const ulong *denominator [[buffer(1)]],
    device ulong *output [[buffer(2)]])
{
    bool ignored;
    output[0] = pack_binary64(div_ff(
        unpack_binary64(numerator[0], ignored),
        unpack_binary64(denominator[0], ignored)
    ));
}

kernel void gmres_initialize_fast48_kernel(
    device const ulong *normSquared [[buffer(0)]],
    device ulong *inverseNorm [[buffer(1)]],
    device ulong *g [[buffer(2)]],
    device ulong *initialNorm [[buffer(3)]])
{
    bool ignored;
    emu_f64 norm = sqrt_ff(unpack_binary64(normSquared[0], ignored));
    inverseNorm[0] = pack_binary64(div_ff(make_emu(1.0f, 0.0f), norm));
    g[0] = pack_binary64(norm);
    initialNorm[0] = pack_binary64(norm);
}

kernel void gmres_orthogonalize_fast48_kernel(
    device const ulong *coefficient [[buffer(0)]],
    device const ulong *basis [[buffer(1)]],
    device ulong *work [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 h = unpack_binary64(coefficient[0], ignored);
    emu_f64 q = unpack_binary64(basis[gid], ignored);
    emu_f64 w = unpack_binary64(work[gid], ignored);
    work[gid] = pack_binary64(fma_ff(neg_ff(h), q, w));
}

kernel void gmres_finalize_column_fast48_kernel(
    device ulong *h [[buffer(0)]],
    device const ulong *normSquared [[buffer(1)]],
    device ulong *cosine [[buffer(2)]],
    device ulong *sine [[buffer(3)]],
    device ulong *g [[buffer(4)]],
    device ulong *inverseNorm [[buffer(5)]],
    device const ulong *initialNorm [[buffer(6)]],
    device uint *completed [[buffer(7)]],
    device ulong *convergedResidual [[buffer(8)]],
    constant uint &column [[buffer(9)]],
    constant uint &stride [[buffer(10)]],
    constant float &tolerance [[buffer(11)]])
{
    bool ignored;
    emu_f64 norm = sqrt_ff(unpack_binary64(normSquared[0], ignored));
    h[(column + 1u) * stride + column] = pack_binary64(norm);
    inverseNorm[0] = pack_binary64(div_ff(make_emu(1.0f, 0.0f), norm));

    for (uint row = 0; row < column; ++row) {
        uint upperIndex = row * stride + column;
        uint lowerIndex = (row + 1u) * stride + column;
        emu_f64 upper = unpack_binary64(h[upperIndex], ignored);
        emu_f64 lower = unpack_binary64(h[lowerIndex], ignored);
        emu_f64 c = unpack_binary64(cosine[row], ignored);
        emu_f64 s = unpack_binary64(sine[row], ignored);
        h[upperIndex] = pack_binary64(add_ff(mul_ff(c, upper), mul_ff(s, lower)));
        h[lowerIndex] = pack_binary64(add_ff(mul_ff(neg_ff(s), upper), mul_ff(c, lower)));
    }

    uint diagonalIndex = column * stride + column;
    uint subdiagonalIndex = (column + 1u) * stride + column;
    emu_f64 diagonal = unpack_binary64(h[diagonalIndex], ignored);
    emu_f64 subdiagonal = unpack_binary64(h[subdiagonalIndex], ignored);
    emu_f64 magnitude = sqrt_ff(add_ff(
        mul_ff(diagonal, diagonal), mul_ff(subdiagonal, subdiagonal)
    ));
    emu_f64 c = div_ff(diagonal, magnitude);
    emu_f64 s = div_ff(subdiagonal, magnitude);
    cosine[column] = pack_binary64(c);
    sine[column] = pack_binary64(s);
    h[diagonalIndex] = pack_binary64(magnitude);
    h[subdiagonalIndex] = 0ul;

    emu_f64 previousG = unpack_binary64(g[column], ignored);
    g[column] = pack_binary64(mul_ff(c, previousG));
    emu_f64 nextG = mul_ff(neg_ff(s), previousG);
    g[column + 1u] = pack_binary64(nextG);

    float residualMagnitude = fabs(nextG.hi + nextG.lo);
    emu_f64 bNorm = unpack_binary64(initialNorm[0], ignored);
    bool reachedTolerance = residualMagnitude <= tolerance * fabs(bNorm.hi + bNorm.lo);
    bool finalColumn = column + 1u == stride;
    if (completed[0] == 0u && (reachedTolerance || finalColumn)) {
        completed[0] = column + 1u;
        emu_f64 magnitudeValue = nextG.hi < 0.0f ? neg_ff(nextG) : nextG;
        convergedResidual[0] = pack_binary64(magnitudeValue);
    }
}

kernel void gmres_backsolve_fast48_kernel(
    device const ulong *h [[buffer(0)]],
    device const ulong *g [[buffer(1)]],
    device ulong *y [[buffer(2)]],
    device const uint *completedState [[buffer(3)]],
    constant uint &stride [[buffer(4)]])
{
    bool ignored;
    uint completed = completedState[0];
    for (int row = int(completed) - 1; row >= 0; --row) {
        emu_f64 rhs = unpack_binary64(g[uint(row)], ignored);
        for (uint column = uint(row) + 1u; column < completed; ++column) {
            emu_f64 coefficient = unpack_binary64(
                h[uint(row) * stride + column], ignored
            );
            rhs = sub_ff(rhs, mul_ff(
                coefficient, unpack_binary64(y[column], ignored)
            ));
        }
        y[uint(row)] = pack_binary64(div_ff(
            rhs, unpack_binary64(h[uint(row) * stride + uint(row)], ignored)
        ));
    }
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

kernel void nbody_integrate_fast48_kernel(
    device const ulong *dtBuffer [[buffer(0)]],
    device const ulong *ax [[buffer(1)]], device const ulong *ay [[buffer(2)]],
    device const ulong *az [[buffer(3)]], device ulong *px [[buffer(4)]],
    device ulong *py [[buffer(5)]], device ulong *pz [[buffer(6)]],
    device ulong *vx [[buffer(7)]], device ulong *vy [[buffer(8)]],
    device ulong *vz [[buffer(9)]], constant uint &count [[buffer(10)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 dt = unpack_binary64(dtBuffer[0], ignored);
    emu_f64 nextVX = fma_ff(dt, unpack_binary64(ax[gid], ignored),
                            unpack_binary64(vx[gid], ignored));
    emu_f64 nextVY = fma_ff(dt, unpack_binary64(ay[gid], ignored),
                            unpack_binary64(vy[gid], ignored));
    emu_f64 nextVZ = fma_ff(dt, unpack_binary64(az[gid], ignored),
                            unpack_binary64(vz[gid], ignored));
    vx[gid] = pack_binary64(nextVX);
    vy[gid] = pack_binary64(nextVY);
    vz[gid] = pack_binary64(nextVZ);
    px[gid] = pack_binary64(fma_ff(dt, nextVX, unpack_binary64(px[gid], ignored)));
    py[gid] = pack_binary64(fma_ff(dt, nextVY, unpack_binary64(py[gid], ignored)));
    pz[gid] = pack_binary64(fma_ff(dt, nextVZ, unpack_binary64(pz[gid], ignored)));
}

inline bool lp_fast48_leq(emu_f64 a, emu_f64 b) {
    uint flags = 0;
    return soft_less64_status(
        pack_binary64(a), pack_binary64(b), true, true, flags
    );
}

inline void lp_fast48_consider(
    emu_f64 x, emu_f64 y, emu_f64 c0, emu_f64 c1,
    device const ulong *a, device const ulong *b, device const ulong *rhs,
    uint constraintCount, thread emu_f64 &bestX, thread emu_f64 &bestY,
    thread emu_f64 &bestObjective)
{
    emu_f64 zero = make_emu(0.0f, 0.0f);
    if (!lp_fast48_leq(zero, x) || !lp_fast48_leq(zero, y)) return;
    bool ignored;
    for (uint k = 0; k < constraintCount; ++k) {
        emu_f64 lhs = fma_ff(
            unpack_binary64(a[k], ignored), x,
            mul_ff(unpack_binary64(b[k], ignored), y)
        );
        emu_f64 feasibleBound = add_ff(
            unpack_binary64(rhs[k], ignored), make_emu(1.0e-10f, 0.0f)
        );
        if (!lp_fast48_leq(lhs, feasibleBound)) return;
    }
    emu_f64 objective = fma_ff(c0, x, mul_ff(c1, y));
    if (lp_fast48_leq(bestObjective, objective)) {
        bestX = x;
        bestY = y;
        bestObjective = objective;
    }
}

kernel void lp_fast48_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device const ulong *rhs [[buffer(2)]], device const ulong *c0s [[buffer(3)]],
    device const ulong *c1s [[buffer(4)]], device ulong *solution [[buffer(5)]],
    device const uint *constraintCountBuffer [[buffer(6)]],
    constant uint &count [[buffer(7)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint constraintCount = constraintCountBuffer[0];
    bool ignored;
    emu_f64 zero = make_emu(0.0f, 0.0f);
    emu_f64 c0 = unpack_binary64(c0s[gid], ignored);
    emu_f64 c1 = unpack_binary64(c1s[gid], ignored);
    emu_f64 bestX = zero, bestY = zero, bestObjective = zero;
    lp_fast48_consider(zero, zero, c0, c1, a, b, rhs, constraintCount,
                       bestX, bestY, bestObjective);
    for (uint i = 0; i < constraintCount; ++i) {
        emu_f64 ai = unpack_binary64(a[i], ignored);
        emu_f64 bi = unpack_binary64(b[i], ignored);
        emu_f64 ri = unpack_binary64(rhs[i], ignored);
        lp_fast48_consider(div_ff(ri, ai), zero, c0, c1, a, b, rhs,
                           constraintCount, bestX, bestY, bestObjective);
        lp_fast48_consider(zero, div_ff(ri, bi), c0, c1, a, b, rhs,
                           constraintCount, bestX, bestY, bestObjective);
        for (uint j = i + 1; j < constraintCount; ++j) {
            emu_f64 aj = unpack_binary64(a[j], ignored);
            emu_f64 bj = unpack_binary64(b[j], ignored);
            emu_f64 rj = unpack_binary64(rhs[j], ignored);
            emu_f64 determinant = sub_ff(mul_ff(ai, bj), mul_ff(aj, bi));
            if (determinant.hi == 0.0f) continue;
            emu_f64 x = div_ff(sub_ff(mul_ff(ri, bj), mul_ff(rj, bi)), determinant);
            emu_f64 y = div_ff(sub_ff(mul_ff(ai, rj), mul_ff(aj, ri)), determinant);
            lp_fast48_consider(x, y, c0, c1, a, b, rhs, constraintCount,
                               bestX, bestY, bestObjective);
        }
    }
    solution[gid * 3u] = pack_binary64(bestX);
    solution[gid * 3u + 1u] = pack_binary64(bestY);
    solution[gid * 3u + 2u] = pack_binary64(bestObjective);
}

inline bool lp_ieee_leq(ulong a, ulong b) {
    uint flags = 0;
    return soft_less64_status(a, b, true, true, flags);
}

inline void lp_ieee_consider(
    ulong x, ulong y, ulong c0, ulong c1,
    device const ulong *a, device const ulong *b, device const ulong *rhs,
    uint constraintCount, thread ulong &bestX, thread ulong &bestY,
    thread ulong &bestObjective)
{
    uint flags = 0;
    if (!lp_ieee_leq(0ul, x) || !lp_ieee_leq(0ul, y)) return;
    for (uint k = 0; k < constraintCount; ++k) {
        ulong lhs = soft_mul64_status(b[k], y, soft_round_near_even, flags);
        lhs = soft_fma64_status(a[k], x, lhs, soft_round_near_even, flags);
        ulong feasibleBound = soft_add64_status(
            rhs[k], 0x3ddb7cdfd9d7bdbbul, soft_round_near_even, flags
        );
        if (!lp_ieee_leq(lhs, feasibleBound)) return;
    }
    ulong objective = soft_mul64_status(c1, y, soft_round_near_even, flags);
    objective = soft_fma64_status(c0, x, objective, soft_round_near_even, flags);
    if (lp_ieee_leq(bestObjective, objective)) {
        bestX = x;
        bestY = y;
        bestObjective = objective;
    }
}

kernel void lp_ieee64_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device const ulong *rhs [[buffer(2)]], device const ulong *c0s [[buffer(3)]],
    device const ulong *c1s [[buffer(4)]], device ulong *solution [[buffer(5)]],
    device const uint *constraintCountBuffer [[buffer(6)]],
    constant uint &count [[buffer(7)]], uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    uint constraintCount = constraintCountBuffer[0];
    uint flags = 0;
    ulong bestX = 0ul, bestY = 0ul, bestObjective = 0ul;
    lp_ieee_consider(0ul, 0ul, c0s[gid], c1s[gid], a, b, rhs,
                     constraintCount, bestX, bestY, bestObjective);
    for (uint i = 0; i < constraintCount; ++i) {
        ulong axisX = soft_div64_status(rhs[i], a[i], soft_round_near_even, flags);
        ulong axisY = soft_div64_status(rhs[i], b[i], soft_round_near_even, flags);
        lp_ieee_consider(axisX, 0ul, c0s[gid], c1s[gid], a, b, rhs,
                         constraintCount, bestX, bestY, bestObjective);
        lp_ieee_consider(0ul, axisY, c0s[gid], c1s[gid], a, b, rhs,
                         constraintCount, bestX, bestY, bestObjective);
        for (uint j = i + 1; j < constraintCount; ++j) {
            ulong determinant = soft_mul64_status(a[i], b[j], soft_round_near_even, flags);
            ulong term = soft_mul64_status(a[j], b[i], soft_round_near_even, flags);
            determinant = soft_sub64_status(determinant, term, soft_round_near_even, flags);
            if ((determinant & 0x7ffffffffffffffful) == 0ul) continue;
            ulong xNumerator = soft_mul64_status(rhs[i], b[j], soft_round_near_even, flags);
            term = soft_mul64_status(rhs[j], b[i], soft_round_near_even, flags);
            xNumerator = soft_sub64_status(xNumerator, term, soft_round_near_even, flags);
            ulong yNumerator = soft_mul64_status(a[i], rhs[j], soft_round_near_even, flags);
            term = soft_mul64_status(a[j], rhs[i], soft_round_near_even, flags);
            yNumerator = soft_sub64_status(yNumerator, term, soft_round_near_even, flags);
            ulong x = soft_div64_status(xNumerator, determinant, soft_round_near_even, flags);
            ulong y = soft_div64_status(yNumerator, determinant, soft_round_near_even, flags);
            lp_ieee_consider(x, y, c0s[gid], c1s[gid], a, b, rhs,
                             constraintCount, bestX, bestY, bestObjective);
        }
    }
    solution[gid * 3u] = bestX;
    solution[gid * 3u + 1u] = bestY;
    solution[gid * 3u + 2u] = bestObjective;
}
