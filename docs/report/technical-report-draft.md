# Virtual FP64 for Apple GPUs — technical report draft

Date: 2026-08-29  
Status: pre-release evidence draft; not a 1.0 claim

## Abstract

This project implements binary64 arithmetic on Apple GPUs without native FP64
ALUs. It provides three numerical modes: a finite-range FP32 pair (`fast48`), a
scaled full-range pair (`wide48`), and a correctly rounded integer software
runtime (`ieee64`). VF64 v1 exposes those modes through a source-independent
virtual ISA, while a standalone typed frontend supports explicit policies and
profile-guided automatic selection.

On one 16-core Apple M4 Pro, the documented M1/M2 runtime and VF64 backend pass
31,982,976 Berkeley TestFloat result-and-flag comparisons. A mixed automatic
region satisfies a 40-bit accuracy contract at 1.18x the pure `ieee64` rate.
Scientific pilots show large wins for some dense and batched workloads, while
synchronous Krylov solvers and division-heavy N-body kernels remain slower than
the scalar CPU baseline.

## Architecture

Packed storage is always one IEEE-754 binary64 bit pattern. `fast48` keeps a
normalized `{hi, lo}` FP32 pair within the binary32 normal exponent range.
`wide48` adds an explicit scale to retain the binary64 finite range. `ieee64`
uses integer significand arithmetic, explicit rounding, and sticky exception
state. Pair or exact state remains resident inside VF64 arithmetic regions and
is materialized at observable storage boundaries.

VF64 v1 fixes a little-endian binary header, 36 opcodes, 32 raw vector
registers, three precision modes, per-instruction rounding, and per-lane sticky
flags. The Metal interpreter executes bytecode independently of the source
frontend.

## Conformance methodology

Berkeley TestFloat Release 3e and SoftFloat Release 3e are pinned by commit and
built with the ARM-VFPv2 policy. M1 covers add, subtract, multiply, divide,
square root, and true fused FMA under five rounding directions. M2 adds result
and flag validation for comparisons, remainder, round-to-integer, integer
conversions, and binary16/binary32 interchange. M4 regenerates the same cells as
VF64 bytecode and executes them through the standalone interpreter.

| Gate | Comparisons | Result |
| --- | ---: | --- |
| M1 exact arithmetic | 31,599,360 | zero unexplained mismatches |
| M2 complete documented runtime | 31,982,976 | zero result/flag mismatches |
| M4 VF64 v1 backend | 31,982,976 | zero result/flag mismatches |

These are level-1 TestFloat campaigns under the documented policy, not claims
of exhaustive input enumeration.

## Precision modes and automatic selection

The M4 Pro mode corpus measures at least 47.19 p01 accuracy bits for `wide48`
arithmetic. A resident 32-operation multiply chain measures 203,514 Mops/s for
`fast48`, 48,851 Mops/s for `wide48`, and 13,388 Mops/s for `ieee64`.

The automatic selector consumes measured exponent profiles, propagates range
and error bounds, and falls back to `ieee64` when proof is absent. Its committed
22-operation region selects five `fast48` and seventeen `wide48` operations,
measures 43.86 p01 bits against a required 40, and runs at 6,962 Mops/s versus
5,876 Mops/s for pure `ieee64`.

## Scientific workload pilot

The following measurements come from one Apple M4 Pro run. GPU entries use
median Metal elapsed time over five kernel trials; solver entries use host wall
time including synchronous control. CPU references are scalar Swift FP64 and
are workload baselines, not tuned BLAS comparisons.

| Workload and mode | Accuracy or convergence | Speed versus CPU FP64 |
| --- | --- | ---: |
| SpMV `wide48` | 46.75 p01 bits | 1.02x |
| GEMV `fast48` | 40.66 p01 bits | 1.26x |
| GEMM `fast48` | 41.28 p01 bits | 7.89x |
| GEMM `ieee64` | bit-identical | 4.61x |
| batched 2D LP `fast48` | 46.43 p01 objective bits; zero infeasible | 4.36x |
| N-body force `fast48` | 40.67 p01 bits | 0.96x |
| CG `fast48` | 11 iterations; 1.453e-12 residual | 0.08x |
| GMRES `fast48` | 10 iterations; 2.712e-11 residual | 0.04x |

A 16-step `fast48` symplectic-Euler N-body simulation matches the CPU
trajectory to 4.109e-15 relative state error and reproduces its 3.340e-6
relative energy drift, but runs at 0.05x CPU because every step is synchronously
dispatched.

The existing CuMetal CUDA reduced-pair contract probe also passes shared
memory, shuffle, reload, aliasing, and precision sentinels. That probe does not
execute VF64 and is not compiler-integration evidence.

## Open validity and release gates

- M3 needs a second Apple GPU generation and defensible register, occupancy,
  and spill evidence.
- M5 needs CuMetal source/PTX `double` lowering through VF64 with observable
  storage-boundary regressions.
- M7 needs VF64-integrated CUDA workloads, authorized energy measurement, and
  broader sparse and LP corpora.
- M8 needs successful public cross-generation runs, a stable external release,
  and a publication-time prior-art search.

The `powermetrics` GPU-power probe requires superuser access on the measured
host, so energy is reported unavailable rather than estimated from runtime.

## Claim status

The final “first complete virtual FP64 architecture” statement is embargoed.
The current evidence supports narrower claims: a complete documented M2
software runtime under its declared TestFloat policy, a complete VF64 v1 ISA
surface, an automatic accuracy-contract demonstration, and partial scientific
workload proof on one delivered Apple GPU.

## Reproducibility

Run `scripts/verify-release.sh` for the unified local gate. Machine-readable
provenance and measurements are under `results/m1` through `results/m7`.
Cross-generation workflow source exists, but successful runner artifacts do
not yet exist.
