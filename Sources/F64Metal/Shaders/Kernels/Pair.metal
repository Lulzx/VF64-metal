kernel void pair_add_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(add_ff(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_mul_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(mul_ff(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_mul_short_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(mul_ff_short(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_mul_dekker_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(mul_ff_dekker(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_div_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(div_ff(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_div_one_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid < count) output[gid] = to_float2(div_ff_one_correction(from_float2(a[gid]), from_float2(b[gid])));
}

kernel void pair_mul_chain_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    emu_f64 value = from_float2(a[gid]);
    emu_f64 factor = from_float2(b[gid]);
    for (uint i = 0; i < 32; ++i) value = mul_ff(value, factor);
    output[gid] = to_float2(value);
}

kernel void pair_add_chain_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    emu_f64 value = from_float2(a[gid]);
    emu_f64 term = from_float2(b[gid]);
    for (uint i = 0; i < 32; ++i) value = add_ff(value, term);
    output[gid] = to_float2(value);
}

kernel void pair_mul_short_chain_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    emu_f64 value = from_float2(a[gid]);
    emu_f64 factor = from_float2(b[gid]);
    for (uint i = 0; i < 32; ++i) value = mul_ff_short(value, factor);
    output[gid] = to_float2(value);
}

kernel void pair_mul_dekker_chain_kernel(
    device const float2 *a [[buffer(0)]], device const float2 *b [[buffer(1)]],
    device float2 *output [[buffer(2)]], constant uint &count [[buffer(3)]],
    uint gid [[thread_position_in_grid]])
{
    if (gid >= count) return;
    emu_f64 value = from_float2(a[gid]);
    emu_f64 factor = from_float2(b[gid]);
    for (uint i = 0; i < 32; ++i) value = mul_ff_dekker(value, factor);
    output[gid] = to_float2(value);
}

