# Reproducible result summary

## M1 exact core arithmetic

Status: **complete** for result-bit conformance; M2 semantic state is excluded.

The 2026-08-29 Apple M4 Pro run passed 31,599,360 binary64 result comparisons
against Berkeley TestFloat/SoftFloat with zero unexplained mismatches.

Covered operations:

- add, subtract, multiply, and divide: 46,464 cases per rounding mode;
- square root: 768 cases per rounding mode;
- true fused FMA: 6,133,248 cases per rounding mode;
- five IEEE rounding directions for every operation.

Reproduce with:

```bash
scripts/run-testfloat-m1.sh
```

Machine-readable provenance and policy are in
[`m1/2026-08-29-m4-pro-level1.json`](m1/2026-08-29-m4-pro-level1.json).

This is result-bit conformance with NaNs compared by class. It does not claim
M2 exception-flag, signaling-NaN, or payload conformance.

## M2 complete IEEE-754 runtime

Status: **complete** for the documented M2 runtime surface.

At source commit `d96094a`, `scripts/run-testfloat-m2.sh` passed 31,982,976
level-1 result and exception-flag comparisons on the Apple M4 Pro. This covers
the six exact arithmetic operations, comparisons, remainder, round-to-integer,
signed/unsigned 32/64-bit integer conversions, and binary16/binary32
interchange. Floating NaN results match ARM-VFPv2 sign, quiet bit, and payload
bitwise. Tininess is detected after rounding.

Machine-readable evidence:
[`m2/2026-08-29-m4-pro-full-runtime-level1.json`](m2/2026-08-29-m4-pro-full-runtime-level1.json).

The earlier core-only flag artifact remains as historical incremental evidence.
Level 2 exhaustive campaigns are not implied by this level-1 exit.

## M3 precision modes

The `fast48`, `wide48`, and `ieee64` numerical contracts are frozen. A new
scaled-pair `wide48` implementation covers the full binary64 input exponent
range and measured 47.19 or more p01 accuracy bits for add, subtract, multiply,
divide, and multiply-add on its committed corpus.

On the M4 Pro, the resident 32-operation multiply chain measured 203,514 M/s
for `fast48`, 48,851 M/s for `wide48`, and 13,388 M/s for `ieee64`. These are
comparative microkernel rates. The machine-readable single-device artifact is
[`m3/2026-08-29-m4-pro-modes.json`](m3/2026-08-29-m4-pro-modes.json).

M3 remains in progress: cross-generation evidence and register/spill reporting
are not available from this run.

## M4 VF64 virtual ISA

Status: **complete** for VF64 v1.0.

VF64 defines a fixed little-endian header/instruction encoding, 36 opcodes,
32 raw vector registers, packed storage, three precision modes, and sticky
per-lane exception state. The standalone Metal interpreter accepts binary
program/input files independently of a source-language frontend.

At source commit `2827f2d`, all 119 M2 operation/policy cells were regenerated
and executed through VF64 bytecode. The resulting 31,982,976 exact result-bit
and flag comparisons passed with zero mismatches. Directed validation also
covers every opcode, all three modes, negative programs, and standalone file
round trips. Evidence:
[`m4/2026-08-29-m4-pro-vf64-v1-level1.json`](m4/2026-08-29-m4-pro-vf64-v1-level1.json).

## M5 compiler integration

Status: **in progress**.

The standalone typed source frontend lowers `double` expressions under
explicit `fast48`, `wide48`, and `ieee64` policies into executable VF64
bytecode. It is not yet integrated into CuMetal's source/PTX path, so existing
CUDA kernels cannot yet use virtual `double` without a separate compilation
step. Observable-boundary regressions for `mov.b64`, `uint64_t`, shared memory,
shuffle, reload, and calls remain required.

## M6 automatic precision

Status: **complete** for the VF64 compiler's declared accuracy-contract path.

The profiled selector propagates finite exponent intervals and an accumulated
error budget, emits per-operation diagnostics, and falls back to `ieee64` when
proof is absent or the budget is exhausted. A 1,048,576-lane, 22-operation
dependency region selected five `fast48` and seventeen `wide48` operations.
It measured 43.86 p01 accuracy bits against a required 40 and 6,962 Mops/s
against 5,876 Mops/s for pure `ieee64`, a 1.18× speedup on the M4 Pro.

Evidence:
[`m6/2026-08-29-m4-pro-auto-mixed-chain.json`](m6/2026-08-29-m4-pro-auto-mixed-chain.json).

## M7 scientific workload proof

Status: **in progress**.

The first M4 Pro pilot covers CG, GMRES, SpMV, GEMV, GEMM, batched 2D LP, and
multi-step N-body simulation. `fast48` GEMM measured 7.89x the scalar CPU FP64
reference at 41.28 p01 accuracy bits; the batched LP workload measured 4.36x at
46.43 p01 objective bits with zero infeasible outputs. Exact `ieee64` GEMM was
bit-identical to the fused CPU reference and measured 4.61x CPU.

CG matched the CPU iteration count and reached a 1.453e-12 relative residual;
GMRES reached 2.712e-11 with an identical matched CPU FP64 result. Both
currently lose to CPU because every iteration synchronously returns scalar
control data. Those host-control boundaries are reported rather than hidden.

Evidence:
[`m7/2026-08-29-m4-pro-workload-pilot.json`](m7/2026-08-29-m4-pro-workload-pilot.json).

The 16-step `fast48` N-body simulation matched the CPU trajectory to 4.109e-15
relative state error and reproduced its 3.340e-6 energy drift.

M7 remains open for CuMetal CUDA workloads, energy, broader LP and sparse
corpora, and cross-device reproduction.
