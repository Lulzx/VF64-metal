# Apple Metal capability boundary

Checked 2026-08-29 using Xcode's macOS 26.5 SDK public Metal headers.

## Observed API surface

`MTLTensorDataType` exposes FP32, FP16, bfloat16, signed and unsigned
8/16/32-bit integer types, plus signed and unsigned 4-bit tensor storage. No FP8
tensor data type was present. No Blackwell-like public Tensor Memory (TMEM)
facility was found in the inspected Metal framework headers.

These observations are deliberately narrow:

- a tensor storage type does not prove accelerated matrix execution;
- INT8 matrix support would not automatically guarantee exact INT32
  accumulation or the modular behavior Ozaki II requires;
- absence from the public API does not prove absence from the physical GPU;
- cooperative-tensor and machine-learning paths still require compile/run
  probes on each Apple GPU family.

## Required substrate probes

1. Find the fastest public INT8, INT4, FP16, BF16, and FP32 matrix primitive.
2. Characterize accumulator width, saturation, and rounding experimentally.
3. Test whether residue generation, matrix accumulation, and reconstruction can
   remain in one dispatch without global-memory intermediates.
4. Measure threadgroup memory, registers, occupancy, spills, and end-to-end
   throughput.
5. Compare the complete path against pair-FMA kernels after all conversion and
   reconstruction costs.

An `ozaki` backend remains research-only until those gates pass.

