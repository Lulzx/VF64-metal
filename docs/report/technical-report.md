# Virtual FP64 for Apple GPUs

Date: 2026-08-29  
Status: current technical report; not a 1.0 claim

## Abstract

This project implements binary64 arithmetic on Apple GPUs without native FP64
ALUs. It provides three numerical modes: a finite-range FP32 pair (`fast48`), a
scaled full-range pair (`wide48`), and a correctly rounded integer software
runtime (`ieee64`). VF64 v1 exposes those modes through a source-independent
virtual ISA, while a standalone typed frontend supports explicit policies and
profile-guided automatic selection. CuMetal lowers unchanged CUDA/PTX `double`
through the same support architecture under all three explicit modes.

On one 16-core Apple M4 Pro, the documented M1/M2 runtime and VF64 backend pass
31,982,976 Berkeley TestFloat result-and-flag comparisons. A mixed automatic
region satisfies a 40-bit accuracy contract at 1.18x the pure `ieee64` rate.
Scientific pilots show large wins for some dense and batched workloads, while
synchronous Krylov solvers and division-heavy N-body kernels remain slower than
the scalar CPU baseline. The evidence remains single-generation and has no
authorized power measurement.

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
Nine representative pipelines report SIMD width 32, the full 1,024-thread
single-threadgroup limit, and zero static threadgroup bytes. Public Metal does
not expose physical-register, spill-byte, or resident-occupancy measurements on
this device, and the report does not infer them from AIR.

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
| batched 2D LP `fast48` | 46.43 p01 objective bits; zero infeasible | 4.36x pilot; 0.92x-2.77x structured follow-up |
| N-body force `fast48` | 40.67 p01 bits | 0.96x |
| CG `fast48`, device-resident schedule | 11 iterations; 1.453e-12 residual | 1.06x |
| GMRES `fast48` | 10 iterations; 2.712e-11 residual | 0.04x |

A 16-step device-resident `fast48` symplectic-Euler N-body simulation matches the CPU
trajectory to 4.109e-15 relative state error and reproduces its 3.340e-6
relative energy drift, but runs at 0.44x CPU for the measured 256-body shape.

The CG result uses one command buffer for SpMV, reductions, alpha/beta, and
vector updates. It uses the CPU baseline's fixed iteration count and validates
only after completion; device-side convergence and early exit remain open.

CuMetal now executes the unchanged CUDA contract probe through `fast48`,
`wide48`, and `ieee64`. The gate covers arithmetic, true fused FMA, square root,
conversions, comparisons, min/max, remainder, rounding, shared memory, shuffle,
reload, aliasing, cache hits, and mode-specific provenance.

Two checksum-pinned NIST Matrix Market matrices add structural-engineering and
power-network SpMV; exact `ieee64` results are bit-identical on both, though the
small shapes do not amortize dispatch overhead. Unmodified HiGHS 1.15.1 PDLP on
Netlib `afiro` passes its status/objective/residual gate under `wide48` and the
mixed `ieee64` path with more than 2,600 Apple-GPU launches each. `fast48`
reaches Optimal but misses the frozen dual-residual parity gate by 5%. The
`ieee64` whole solve is not claimed exact because cuSPARSE SpMV remains an
explicit reduced-precision library substitution.

## Open validity and release gates

- M3 needs a second Apple GPU generation and defensible register, occupancy,
  and spill evidence.
- M7 needs authorized energy measurement and cross-device reproduction.
- M8 needs successful public cross-generation runs and a stable external
  release. The dated prior-art audit is complete, but does not establish
  universal priority.

The `powermetrics` GPU-power probe requires superuser access on the measured
host, so energy is reported unavailable rather than estimated from runtime.

## Claim status

The final “first complete virtual FP64 architecture” statement is not supported
by the bounded prior-art search. Public projects predate VF64Metal's exact Metal
core, complete portable runtime, and compiler-lowered `double` as separate
claims. The current evidence supports a descriptive “a complete virtual FP64
architecture” statement once all remaining release gates close.
The current evidence supports narrower claims: a complete documented M2
software runtime under its declared TestFloat policy, a complete VF64 v1 ISA
surface, an automatic accuracy-contract demonstration, and partial scientific
workload proof on one delivered Apple GPU.

## Reproducibility

Run `scripts/verify-release.sh` for the unified local gate. Machine-readable
provenance and measurements are under `results/m1` through `results/m7`.
Cross-generation workflow source exists, but successful runner artifacts do
not yet exist.
