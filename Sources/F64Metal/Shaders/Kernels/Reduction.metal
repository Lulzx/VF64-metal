inline emu_f64 from_float2(float2 value) {
    return make_emu(value.x, value.y);
}

inline float2 to_float2(emu_f64 value) {
    return float2(value.hi, value.lo);
}

kernel void dot_partial_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device float2 *partials [[buffer(2)]], constant uint &count [[buffer(3)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint group [[threadgroup_position_in_grid]],
    uint threads [[threads_per_threadgroup]])
{
    emu_f64 acc0 = make_emu(0.0f, 0.0f);
    emu_f64 acc1 = make_emu(0.0f, 0.0f);
    emu_f64 acc2 = make_emu(0.0f, 0.0f);
    emu_f64 acc3 = make_emu(0.0f, 0.0f);
    uint base = group * threads * 4 + tid;
    bool ignored;
    if (base < count) acc0 = mul_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored));
    base += threads;
    if (base < count) acc1 = mul_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored));
    base += threads;
    if (base < count) acc2 = mul_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored));
    base += threads;
    if (base < count) acc3 = mul_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored));
    scratch[tid] = to_float2(add_ff(add_ff(acc0, acc1), add_ff(acc2, acc3)));
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (uint offset = threads >> 1; offset > 0; offset >>= 1) {
        if (tid < offset) {
            scratch[tid] = to_float2(add_ff(from_float2(scratch[tid]), from_float2(scratch[tid + offset])));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) partials[group] = scratch[0];
}

kernel void dot_partial_serial_kernel(
    device const ulong *a [[buffer(0)]], device const ulong *b [[buffer(1)]],
    device float2 *partials [[buffer(2)]], constant uint &count [[buffer(3)]],
    threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]],
    uint group [[threadgroup_position_in_grid]],
    uint threads [[threads_per_threadgroup]])
{
    emu_f64 acc = make_emu(0.0f, 0.0f);
    uint base = group * threads * 4 + tid;
    bool ignored;
    if (base < count) acc = fma_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored), acc);
    base += threads;
    if (base < count) acc = fma_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored), acc);
    base += threads;
    if (base < count) acc = fma_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored), acc);
    base += threads;
    if (base < count) acc = fma_ff(unpack_binary64(a[base], ignored), unpack_binary64(b[base], ignored), acc);
    scratch[tid] = to_float2(acc);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threads >> 1; offset > 0; offset >>= 1) {
        if (tid < offset) scratch[tid] = to_float2(add_ff(from_float2(scratch[tid]), from_float2(scratch[tid + offset])));
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) partials[group] = scratch[0];
}

kernel void reduce_partial_kernel(
    device const float2 *input [[buffer(0)]], device float2 *output [[buffer(1)]],
    constant uint &count [[buffer(2)]], threadgroup float2 *scratch [[threadgroup(0)]],
    uint tid [[thread_index_in_threadgroup]], uint group [[threadgroup_position_in_grid]],
    uint threads [[threads_per_threadgroup]])
{
    emu_f64 acc0 = make_emu(0.0f, 0.0f);
    emu_f64 acc1 = make_emu(0.0f, 0.0f);
    emu_f64 acc2 = make_emu(0.0f, 0.0f);
    emu_f64 acc3 = make_emu(0.0f, 0.0f);
    uint base = group * threads * 4 + tid;
    if (base < count) acc0 = from_float2(input[base]);
    base += threads;
    if (base < count) acc1 = from_float2(input[base]);
    base += threads;
    if (base < count) acc2 = from_float2(input[base]);
    base += threads;
    if (base < count) acc3 = from_float2(input[base]);
    scratch[tid] = to_float2(add_ff(add_ff(acc0, acc1), add_ff(acc2, acc3)));
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint offset = threads >> 1; offset > 0; offset >>= 1) {
        if (tid < offset) scratch[tid] = to_float2(add_ff(from_float2(scratch[tid]), from_float2(scratch[tid + offset])));
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) output[group] = scratch[0];
}

kernel void pack_partial_kernel(
    device const float2 *input [[buffer(0)]], device ulong *output [[buffer(1)]])
{
    output[0] = pack_binary64(from_float2(input[0]));
}
