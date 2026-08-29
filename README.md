# f64-metal

A runnable research harness for efficient emulated FP64 on Apple Metal.

Metal has no `double` scalar type. This project compares two implementations
over IEEE-754 binary64 bit storage (`ulong`): CuMetal-style normalized FP32
pairs, and full-range integer software binary64. The pair target is CuMetal's
current contract: approximately 48 significand bits, binary32's exponent
envelope, deterministic split/pack behavior, and explicit special values.

## Run

Requirements: macOS 15 or newer, Swift 6, and a Metal-capable Apple GPU.

```bash
swift build -c release
.build/release/f64-metal validate
.build/release/f64-metal bench
.build/release/f64-metal all
scripts/run-testfloat-m1.sh
scripts/run-testfloat-m2.sh
scripts/run-testfloat-m4.sh
```

The Metal library is compiled at runtime with safe floating-point semantics.
Error-free transforms also disable implicit contraction; multiplication uses
explicit `fma()` where fusion is required.

## What is implemented

- A named `{ hi, lo }` type with no implicit high-limb conversion.
- Integer binary64 split/pack codecs with round-to-nearest-even.
- Idempotence checks over repeated split/pack cycles.
- Accurate add, subtract, multiply, divide, and emulated FMA.
- One- and two-correction division variants.
- Full, shortened, and Dekker-split multiplication variants.
- Binary64-boundary AXPY.
- Pair-resident multi-stage dot reduction using transient `float2` buffers.
- NaN, infinity, signed-zero, and exponent-envelope tests.
- Binary64-boundary, pair-streaming, and compute-bound microbenchmarks.
- Integer software-binary64 add, multiply, divide, and square root with full
  exponent/subnormal range.
- Integer software-binary64 subtraction through the exact add core.
- Exact 53x53-bit products using `mulhi(ulong, ulong)` and 128-bit rounding.

## Verified result on this machine

Apple M4 Pro, 16 GPU cores, Metal 4, 2026-08-27:

```text
codec       precision bits p01 49.12, median 51.44; idempotent
add         precision bits p01 47.96, median 50.89
multiply    precision bits p01 47.45, median 49.96
divide      precision bits p01 47.39, median 49.89
fma         precision bits p01 47.41, median 50.38
dot         50.97 bits against a compensated CPU reference
specials    add/mul NaN, Inf, and signed-zero matrix passed
exact add   bit-exact RNE against the host over 215,172 directed/random cases
exact sub   bit-exact RNE against the host over 215,172 directed/random cases
exact mul   bit-exact RNE against the host over 215,172 directed/random cases
exact div   bit-exact RNE against the host over 215,172 directed/random cases
exact sqrt  bit-exact RNE against the host over 215,172 directed/random cases
TestFloat   add/sub/mul/div passed 46,464 cases/mode; sqrt passed 768/mode
fused FMA   passed 6,133,248 TestFloat result cases in each of 5 rounding modes
```

In a compute-bound 32-multiplication dependency chain, the same run measured:

```text
full FMA residual, including lo*lo     203,001 million emulated ops/s
short FMA residual, omitting lo*lo     317,801 million emulated ops/s
Dekker operand splitting               133,705 million emulated ops/s
```

These are comparative microkernel rates, not claimed application FLOP/s. GPU
frequency and system contention make the streaming measurements variable; the
runner reports the median of repeated GPU-timestamped command buffers.

The full-range integer path measured against pair-resident arithmetic as:

```text
32-operation chain       FP32 pair       integer binary64     slowdown
add                       122,053 M/s       27,843 M/s           4.38x
multiply                  203,360 M/s       16,854 M/s          12.07x
```

One-operation streaming kernels can make integer add/multiply look competitive
or faster because the pair boundary kernel includes binary64 split/pack work and
the workload is dominated by memory. The dependency-chain result isolates the
arithmetic cost and is the relevant comparison for pair-resident CuMetal code.

## Conclusions

1. Explicit FMA product residuals are the right default. The full variant was
   about 1.5x the throughput of Dekker splitting in the dependency-chain test.
2. Omitting `lo*lo` was about 2.4x Dekker's throughput and passed this random
   corpus at effectively the same p01 precision, but it can change the last
   retained bit. It remains an experimental relaxed mode, not the strict default.
3. A second quotient correction improved division p01 from 46.86 to 47.39 bits.
   Whether that half-bit is worth the extra multiply/subtract depends on the
   solver and should be selected as a policy.
4. Four independent dot accumulators did not outperform a serial four-product
   accumulator on this M4 Pro. Larger per-thread tiles may behave differently;
   use occupancy and dependency measurements rather than assuming more
   accumulators are always faster.
5. Keeping pairs resident is solely a performance optimization. Codec
   idempotence proves that removing joins does not add significand bits or
   extend the exponent range.
6. `mulhi` makes the 106-bit product straightforward, but does not make full
   software multiply close to pair multiply here. Classification, subnormal
   normalization, 128-bit shifting, and exact rounding leave integer multiply
   about 12x slower in an ALU-bound chain.

## Exact software binary64 runtime

`soft_add64`, `soft_sub64`, `soft_mul64`, `soft_div64`, `soft_sqrt64`, and
`soft_fma64` operate directly on IEEE binary64 bit patterns.
They implement:

- All 53 significand bits.
- The complete normal and subnormal exponent range.
- All five IEEE rounding directions.
- Signed zero, infinity, invalid-operation NaN, overflow, and underflow results.
- Exact 53x53 multiplication from the low product and `mulhi` high product.

The default validation corpus includes exponent/fraction boundary
cross-products,
rounding boundaries, both signs, zeros, subnormals, maximum finite values,
infinities, signaling/quiet NaNs, and 131,072 arbitrary bit-pattern pairs.
Non-NaN results must match host binary64 bits exactly; NaNs must match class.
This is a smoke oracle, not Berkeley TestFloat. The separate pinned TestFloat
workflow validates M1 result bits for add, subtract, multiply, divide, square
root, and true fused FMA in all five IEEE rounding directions. The consolidated
M2 workflow additionally checks exception flags and the complete documented
runtime surface. True fused FMA uses an exact 106-bit product in a 128-bit
aligned accumulator and rounds only after the addend has been combined.

M1 exact arithmetic and the documented M2 runtime surface are complete under
their committed level-1 TestFloat policies. The consolidated M2 run covers
31,982,976 result-and-flag comparisons with zero mismatches. Floating NaN
results match the pinned ARM-VFPv2 policy bit-for-bit; tininess is detected
after rounding.

The complete TestFloat binary64 comparison family is also implemented: quiet
equality, signaling equality, ordered less-than/less-or-equal, and quiet ordered
variants. All six operations match result and invalid-flag behavior over 46,464
cases each.

`roundToInt` supports all five rounding directions and both exactness policies.
All ten TestFloat cells pass, including signed zero, infinities, NaNs, and
conditional inexact flags.

IEEE remainder uses exact integer long division and nearest-even quotient
selection. Its 46,464-case TestFloat result/invalid-flag corpus passes with zero
mismatches.

Unsigned and signed 32/64-bit integer-to-binary64 conversions support every
rounding direction. All 20 TestFloat cells pass, including 64-bit discarded-bit
rounding and inexact flags.

The four binary64-to-integer directions pass all rounding and exactness
policies. Invalid conversions follow the documented ARM-VFPv2 SoftFloat
saturation values; 40 TestFloat cells pass with zero result/flag mismatches.

Binary16 and binary32 interchange with binary64 is implemented. Narrowing
supports every rounding mode and flags; widening is exact. Cross-format NaN
payloads are compared bit-for-bit against the pinned SoftFloat policy.

VF64 v1 is a source-independent virtual instruction format with 36 arithmetic,
rounding, comparison, conversion, exception, vector, and storage opcodes. Its
standalone Metal bytecode backend passes the complete 31,982,976-case M2
TestFloat matrix through the ISA with exact results and flags.

The VF64 source compiler accepts `double` expressions with explicit
`--fp64=fast48`, `wide48`, or `ieee64` policies. `--fp64=auto` consumes measured
input exponent profiles and an accuracy-bit contract, emits per-operation
selection diagnostics, and has a safe `ieee64` fallback. Its committed mixed
M4 Pro proof met 43.86 p01 bits for a 40-bit contract while running 1.18× faster
than the identical pure software-binary64 region.

The first scientific workload pilot covers CG, GMRES, SpMV, GEMV, GEMM,
batched 2D LP, and N-body force evaluation. On the measured M4 Pro, `fast48`
GEMM reached 7.38x the scalar CPU FP64 reference at 41.28 p01 accuracy bits;
exact `ieee64` GEMM reached 4.30x with bit-identical outputs. M7 remains open
for CuMetal CUDA workloads, energy, broader corpora, multi-step simulation,
and cross-device evidence.

## Deliberate limitations

- Finite values outside binary32's normal exponent range are flagged by the
  codec. They are not silently advertised as supported FP64.
- Binary64 subnormals are outside the pair envelope.
- NaNs remain NaNs, but binary64 payloads are reduced to the payload capacity of
  the FP32 leading limb and repacked as quiet NaNs.
- The FP32-pair path is ~48-bit arithmetic, not correctly rounded binary64.
- The exact runtime has a stable VF64 v1 virtual ISA and a standalone source
  compiler; integration into CuMetal's source/PTX `double` path remains M5 work.
- Transcendentals and FP64 atomics are outside this harness.

See [the documentation index](docs/README.md) for the research record, milestone
specification, and the highest-value path from these experiments into CuMetal.
