# Ozaki-II and “FP8 is All You Need”

Primary source: Satoshi Matsuoka,
[arXiv:2606.06510v3](https://arxiv.org/abs/2606.06510v3), updated 2026-07-03.

## Result in one sentence

The paper is strategically relevant to VF64Metal because it makes adaptive
precision and on-chip fusion central, but it is not a portable Apple
implementation or a scalar IEEE-754 solution.

## Proposed algorithm

Ozaki Scheme II emulates a high-accuracy matrix product in three phases:

1. Scale rows and columns by exactly invertible powers of two and round them to
   bounded integers.
2. Compute products under `r` pairwise-coprime moduli on low-precision matrix
   engines.
3. Reconstruct each integer result with Garner's Chinese Remainder Theorem and
   rescale it.

If the modulus product exceeds twice the maximum scaled integer-product
magnitude, reconstruction is unique. The required `r` depends on operand
dynamic range and should not be assumed constant for every input.

## Corrected v3 cost

The FP8 projections choose `r = 12`, but the corrected compute multiplier is
`3r + 1 = 37` FP8 MMAs, not 12. The factor of three comes from the Karatsuba
structure used to emulate signed INT9 residue products on FP8. The paper says
the earlier draft overstated the dense compute ceiling by about three times.

This is a useful research rule for VF64Metal: count substrate emulation,
conversion, reconstruction, and materialization—not only the obvious logical
arithmetic.

## Accuracy boundary

The paper reports FP64-equivalent matrix accuracy and cites roughly 2–10
binary64 ulps for bounded-condition inputs. That does not establish:

- correctly rounded scalar binary64 operations;
- NaN, infinity, signed-zero, subnormal, or exception semantics;
- directed rounding modes or bitwise reproducibility;
- convergence of an iterative solver;
- robustness on extreme dynamic range or ill-conditioned inputs.

The paper acknowledges these limits and proposes adaptive precision or native
FP64 fallback. Its use of FP32 plus Kahan compensation for some reductions also
precludes interpreting “FP64 accuracy” as full IEEE behavior.

## Tensor-Memory Equilibrium model

The paper separates:

- `alpha`: compute inflation;
- `beta`: memory-traffic inflation from decomposition, spills, and materialized
  intermediates;
- `gamma`: reconstruction and pipeline latency.

The headline depends on `beta` remaining near one. For projected B300 SpMV,
beating native B300 FP64 needs `beta <= 1.23`; staying within 10% of the memory
roof needs `beta <= 1.10`.

Version 3 calculates that a Hopper-style register-file design requires about 90
registers per thread at `r = 12`. Occupancy-driven spilling gives `beta` around
1.24–1.39, outside the SpMV budget. Its proposed resolution uses
Blackwell-specific shared-memory operand flow and dedicated TMEM accumulators,
reducing ordinary register use to about 36 per thread.

This supports the general principle that decomposed intermediates must remain
on-chip. It also makes the proposed sparse dataflow NVIDIA-specific.

## Projection boundary

The paper projects about 1.2x SpMV, 3x stencil, 24x batched GEMV, and 104x dense
GEMM on B300. It explicitly leaves implementation and silicon validation to
follow-on work. These are model outputs, not benchmarks.

Sparse results depend on layout. Blocked-ELL padding contributes directly to
`beta`; a cited typical finite-element shape has padding near two, halving
effective operational intensity. Irregular corpora need hybrid formats and real
measurements.

## What transfers to VF64Metal

- Add `alpha`/`beta`/`gamma` accounting to every emulation backend.
- Extend pair residency into whole-kernel on-chip residency.
- Measure exponent span per tile or row and select precision adaptively.
- Treat an Ozaki/CRT matrix path as a backend, separate from scalar modes.
- Require solver convergence and end-to-end time, not GEMM throughput alone.

## What does not transfer directly

- FP8 tensor MMA is not presently exposed by the checked Metal SDK.
- Blackwell TMEM has no observed public Metal counterpart.
- Matrix-level accuracy cannot replace exact scalar `ieee64` operations.
- The paper's B300 projections say nothing directly about Apple-GPU speed.

