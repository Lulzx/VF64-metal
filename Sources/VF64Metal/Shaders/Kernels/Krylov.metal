// Device-resident fast48 Krylov stages over decoded shadows.
//
// The separate Workloads.metal kernels store every vector as binary64 and
// decode it again on each read, so one CG iteration decodes each matrix value
// once and each SpMV input element once per nonzero. A shadow is the FP32
// pair `unpack_binary64(pack_binary64(v))`: exactly the operand those kernels
// would decode from the stored word. Writing it once preserves every
// arithmetic result bit for bit while removing the redundant decodes.
//
// Dot partials keep dot_partial_kernel's four-element lane layout and tree,
// and the final stage reproduces one reduce_partial_kernel group followed by
// pack_partial_kernel, so reductions also match the unfused kernels exactly.

inline float2 krylov_storage_round(emu_f64 value) {
    bool ignored;
    return to_float2(unpack_binary64(pack_binary64(value), ignored));
}

inline float2 krylov_lane_partial(
    emu_f64 acc0, emu_f64 acc1, emu_f64 acc2, emu_f64 acc3)
{
    return to_float2(add_ff(add_ff(acc0, acc1), add_ff(acc2, acc3)));
}

inline float2 krylov_tree_reduce(
    threadgroup float2 *scratch, float2 value, uint tid, uint threads)
{
    scratch[tid] = value;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threads >> 1; offset > 0; offset >>= 1) {
        if (tid < offset) {
            scratch[tid] = to_float2(add_ff(
                from_float2(scratch[tid]), from_float2(scratch[tid + offset])
            ));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    return scratch[0];
}

// One threadgroup: the last reduce_partial_kernel level plus the pack.
// A single partial is packed directly, as the unfused path never reduces it.
inline ulong krylov_final_dot(
    device const float2 *partials, uint count, threadgroup float2 *scratch,
    uint tid, uint threads)
{
    if (count == 1u) return pack_binary64(from_float2(partials[0]));
    emu_f64 acc[4];
    for (uint k = 0; k < 4u; ++k) {
        uint index = tid + k * threads;
        acc[k] = index < count ? from_float2(partials[index]) : make_emu(0.0f, 0.0f);
    }
    float2 total = krylov_tree_reduce(
        scratch, krylov_lane_partial(acc[0], acc[1], acc[2], acc[3]), tid, threads
    );
    return pack_binary64(from_float2(total));
}

kernel void krylov_decode_fast48_kernel(
    device const ulong *input [[buffer(0)]],
    device float2 *output [[buffer(1)]],
    constant uint &count [[buffer(2)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = to_float2(unpack_binary64(input[gid], ignored));
}

// spmv_fast48_kernel over a decoded matrix and input shadow.
kernel void krylov_spmv_fast48_kernel(
    device const uint *rowOffsets [[buffer(0)]],
    device const uint *columns [[buffer(1)]],
    device const float2 *values [[buffer(2)]],
    device const float2 *input [[buffer(3)]],
    device float2 *output [[buffer(4)]],
    constant uint &rowCount [[buffer(5)]],
    uint row [[thread_position_in_grid]])
{
    if (row >= rowCount) return;
    emu_f64 accumulator = make_emu(0.0f, 0.0f);
    for (uint entry = rowOffsets[row]; entry < rowOffsets[row + 1u]; ++entry) {
        accumulator = fma_ff(
            from_float2(values[entry]), from_float2(input[columns[entry]]),
            accumulator
        );
    }
    output[row] = krylov_storage_round(accumulator);
}

// dot_partial_kernel over shadows.
kernel void krylov_dot_partial_fast48_kernel(
    device const float2 *a [[buffer(0)]],
    device const float2 *b [[buffer(1)]],
    device float2 *partials [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint group [[threadgroup_position_in_grid]],
    uint threads [[threads_per_threadgroup]])
{
    emu_f64 acc[4];
    for (uint k = 0; k < 4u; ++k) {
        uint index = group * threads * 4u + tid + k * threads;
        acc[k] = index < count
            ? mul_ff(from_float2(a[index]), from_float2(b[index]))
            : make_emu(0.0f, 0.0f);
    }
    float2 total = krylov_tree_reduce(
        scratch, krylov_lane_partial(acc[0], acc[1], acc[2], acc[3]), tid, threads
    );
    if (tid == 0) partials[group] = total;
}

// Final dot reduction packed into an arbitrary destination word.
kernel void krylov_dot_pack_fast48_kernel(
    device const float2 *partials [[buffer(0)]],
    device ulong *output [[buffer(1)]],
    constant uint &partialCount [[buffer(2)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint threads [[threads_per_threadgroup]])
{
    ulong packed = krylov_final_dot(partials, partialCount, scratch, tid, threads);
    if (tid == 0) output[0] = packed;
}

// vector_scale_fast48_kernel over shadows.
kernel void krylov_scale_fast48_kernel(
    device const ulong *scale [[buffer(0)]],
    device const float2 *input [[buffer(1)]],
    device float2 *output [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    output[gid] = krylov_storage_round(mul_ff(
        unpack_binary64(scale[0], ignored), from_float2(input[gid])
    ));
}

// pAp = dot; alpha = rr / pAp (scalar_div_fast48_kernel).
kernel void cg_alpha_fast48_kernel(
    device const float2 *partials [[buffer(0)]],
    device const ulong *residualSquared [[buffer(1)]],
    device ulong *pAp [[buffer(2)]],
    device ulong *alpha [[buffer(3)]],
    constant uint &partialCount [[buffer(4)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint threads [[threads_per_threadgroup]])
{
    ulong packed = krylov_final_dot(partials, partialCount, scratch, tid, threads);
    if (tid != 0) return;
    bool ignored;
    pAp[0] = packed;
    alpha[0] = pack_binary64(div_ff(
        unpack_binary64(residualSquared[0], ignored),
        unpack_binary64(packed, ignored)
    ));
}

// cg_update_x_r_fast48_kernel. x keeps its binary64 storage because the
// device snapshot publishes it; r is solver-internal and kept as a shadow.
kernel void cg_update_x_r_shadow_fast48_kernel(
    device const ulong *alpha [[buffer(0)]],
    device const float2 *p [[buffer(1)]],
    device const float2 *ap [[buffer(2)]],
    device ulong *x [[buffer(3)]],
    device float2 *r [[buffer(4)]],
    constant uint &count [[buffer(5)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 scale = unpack_binary64(alpha[0], ignored);
    emu_f64 pv = from_float2(p[gid]);
    x[gid] = pack_binary64(fma_ff(scale, pv, unpack_binary64(x[gid], ignored)));
    r[gid] = krylov_storage_round(
        fma_ff(neg_ff(scale), from_float2(ap[gid]), from_float2(r[gid]))
    );
}

// nextRR = dot; convergence selection (cg_check_convergence_fast48_kernel);
// beta = nextRR / rr (scalar_div_fast48_kernel).
kernel void cg_check_beta_fast48_kernel(
    device const float2 *partials [[buffer(0)]],
    device const ulong *residualSquared [[buffer(1)]],
    device ulong *nextResidualSquared [[buffer(2)]],
    device const ulong *initialResidualSquared [[buffer(3)]],
    device uint *completed [[buffer(4)]],
    device ulong *convergedResidualSquared [[buffer(5)]],
    device ulong *beta [[buffer(6)]],
    constant uint &partialCount [[buffer(7)]],
    constant uint &iteration [[buffer(8)]],
    constant uint &maximumIterations [[buffer(9)]],
    constant float &tolerance [[buffer(10)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint threads [[threads_per_threadgroup]])
{
    ulong packed = krylov_final_dot(partials, partialCount, scratch, tid, threads);
    if (tid != 0) return;
    bool ignored;
    nextResidualSquared[0] = packed;
    emu_f64 rr = unpack_binary64(packed, ignored);
    emu_f64 initial = unpack_binary64(initialResidualSquared[0], ignored);
    float threshold = tolerance * tolerance * (initial.hi + initial.lo);
    bool reachedTolerance = rr.hi + rr.lo <= threshold;
    if (completed[0] == 0u && (reachedTolerance || iteration == maximumIterations)) {
        completed[0] = iteration;
        convergedResidualSquared[0] = packed;
    }
    beta[0] = pack_binary64(div_ff(rr, unpack_binary64(residualSquared[0], ignored)));
}

// cg_snapshot_solution_fast48_kernel followed by cg_update_p_fast48_kernel.
kernel void cg_snapshot_update_p_fast48_kernel(
    device const uint *completed [[buffer(0)]],
    device const ulong *x [[buffer(1)]],
    device ulong *solution [[buffer(2)]],
    device const ulong *beta [[buffer(3)]],
    device const float2 *r [[buffer(4)]],
    device float2 *p [[buffer(5)]],
    constant uint &iteration [[buffer(6)]],
    constant uint &count [[buffer(7)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    if (completed[0] == iteration) solution[gid] = x[gid];
    bool ignored;
    p[gid] = krylov_storage_round(fma_ff(
        unpack_binary64(beta[0], ignored), from_float2(p[gid]), from_float2(r[gid])
    ));
}

// gmres_orthogonalize_fast48_kernel over shadows.
kernel void gmres_orthogonalize_shadow_fast48_kernel(
    device const ulong *coefficient [[buffer(0)]],
    device const float2 *basis [[buffer(1)]],
    device float2 *work [[buffer(2)]],
    constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    emu_f64 h = unpack_binary64(coefficient[0], ignored);
    work[gid] = krylov_storage_round(
        fma_ff(neg_ff(h), from_float2(basis[gid]), from_float2(work[gid]))
    );
}

// x += sum_k y[k] basis_k over the device-selected columns, in the order and
// with the per-step storage rounding of successive axpy_kernel dispatches.
kernel void gmres_assemble_fast48_kernel(
    device const ulong *y [[buffer(0)]],
    device const float2 *basis [[buffer(1)]],
    device ulong *x [[buffer(2)]],
    device const uint *completed [[buffer(3)]],
    constant uint &count [[buffer(4)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    bool ignored;
    ulong value = x[gid];
    uint columns = completed[0];
    for (uint k = 0; k < columns; ++k) {
        value = pack_binary64(fma_ff(
            unpack_binary64(y[k], ignored),
            from_float2(basis[ulong(k) * count + gid]),
            unpack_binary64(value, ignored)
        ));
    }
    x[gid] = value;
}

