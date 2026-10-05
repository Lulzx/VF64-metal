# M7 — Scientific workload proof

Validate the complete stack on:

- CG and GMRES;
- SpMV;
- GEMV and GEMM;
- LP optimization;
- N-body or molecular simulation;
- CuMetal CUDA workloads.

For every applicable workload compare FP32, `fast48`, `wide48`, `ieee64`, and
CPU FP64. Measure speed, numerical error, residual/convergence history, energy,
fallback frequency, and memory behavior. Record sparse formats and matrix
structure rather than reporting one favorable corpus as general coverage.

## Current status

Status: **in progress**. The first Apple M4 Pro pilot now covers CG, GMRES,
SpMV, GEMV, GEMM, batched two-variable LP vertex enumeration, and a 16-step
N-body simulation. The cross-mode kernels contain no CPU arithmetic fallback.
The original CG and GMRES paths retain CPU scalar/control logic, which is
printed and recorded explicitly; device-resident follow-ups move CG scalars and
GMRES convergence/scalars onto Metal while retaining final CPU validation.

The measured corpus demonstrates practical wins for the current shapes,
including 7.89x CPU for `fast48` GEMM at 41.28 p01 accuracy bits and 4.36x CPU
for the `fast48` LP batch at 46.43 p01 objective bits. CG and GMRES meet their
declared convergence tolerances. A later single-command-buffer CG schedule
moves reductions and alpha/beta to GPU and preserves the 1.453e-12 residual.
The matching GMRES schedule moves Arnoldi reductions, Hessenberg/Givens scalar
updates, normalization, back-substitution, and vector assembly onto Metal. Its
five-run median improves 37.10x over the synchronized GPU path while preserving
the 2.712e-11 residual, though it remains 0.66x the scalar CPU baseline.

Machine-readable evidence:
[`results/m7/2026-08-29-m4-pro-workload-pilot.json`](../../results/m7/2026-08-29-m4-pro-workload-pilot.json).
The device-resident scheduling follow-up is
[`results/m7/2026-08-29-m4-pro-device-resident-scheduling.json`](../../results/m7/2026-08-29-m4-pro-device-resident-scheduling.json).
The current CG follow-up removes the CPU-reference iteration count. Metal
selects convergence at iteration 11 and snapshots the solution with a
1.453e-12 true residual. In that artifact all 200 candidate iterations were pre-encoded, so
it proves device-side convergence selection but not dispatch cancellation:
[`results/m7/2026-08-29-m4-pro-device-selected-cg.json`](../../results/m7/2026-08-29-m4-pro-device-selected-cg.json).
The device-resident GMRES follow-up is
[`results/m7/2026-08-29-m4-pro-device-resident-gmres.json`](../../results/m7/2026-08-29-m4-pro-device-resident-gmres.json).
A second GMRES follow-up removes the CPU-reference iteration count: Metal
selects convergence at iteration 10, stores the matching 2.712e-11 residual,
and drives back-substitution and solution assembly. In that artifact all 32 candidate
columns were pre-encoded, so it proves device-side convergence selection but not
dispatch cancellation:
[`results/m7/2026-08-29-m4-pro-device-selected-gmres.json`](../../results/m7/2026-08-29-m4-pro-device-selected-gmres.json).
A 2026-10-05 follow-up removes the remaining scheduling and codec costs.
CG and GMRES now submit candidate iterations in short command-buffer chunks
and stop once a finished chunk carries the device-written convergence word,
so 15 of 200 CG iterations and 11 of 32 GMRES columns are encoded. The host
still never supplies an iteration count. Both solvers decode the matrix once
and keep solver-internal vectors as decoded shadows of their binary64 storage
values; solution bits, selected iterations, and residual bits are identical to
the earlier fused kernels. N-body force kernels give each body a SIMD group
and stay bitwise identical in every mode, and long-row reduced-mode SpMV/GEMV
use coalesced SIMD-per-row kernels. An interleaved A/B on the same host
measured 8.65x for device-selected CG, 6.26x for device-selected GMRES,
8.18x for `fast48` GEMV, and 3.22x for `ieee64` N-body force. The host was
heavily loaded by unrelated work, so these are relative results, not a new
baseline:
[`results/m7/2026-10-05-m4-pro-dispatch-and-codec-ab.json`](../../results/m7/2026-10-05-m4-pro-dispatch-and-codec-ab.json).
A single-threadgroup GMRES schedule was also tried and rejected. It ran the
whole restart cycle in one threadgroup with barriers instead of dispatches,
and reproduced the chunked results bit for bit, but its best GPU time was
4.50 ms against 2.60 ms for the chunked schedule on the same loaded host. One
GPU core lacks the pair-arithmetic throughput the distributed schedule gets
from all sixteen. At 8,192 unknowns, device-selected GMRES remains bounded by
the latency of its dependent modified Gram-Schmidt dispatches.

The cross-mode CSR corpus adds periodic, symmetric positive-definite, and
nonsymmetric matrix structures:
[`results/m7/2026-08-29-m4-pro-sparse-corpus.json`](../../results/m7/2026-08-29-m4-pro-sparse-corpus.json).
The structured LP follow-up covers well-conditioned, near-parallel, redundant,
and row-scaled constraint systems. Across 16,384 problems per mode it produced
zero infeasible results; `fast48` retained at least 46.43 p01 objective bits
and beat CPU FP64 on three of four structures:
[`results/m7/2026-08-29-m4-pro-lp-corpus.json`](../../results/m7/2026-08-29-m4-pro-lp-corpus.json).

The checksum-pinned external Matrix Market follow-up runs a structural matrix
(`bcsstk01`) and a power-network matrix (`494_bus`) from the NIST
Harwell-Boeing collection. Both execute in all four modes with no CPU arithmetic
fallback; `ieee64` is bit-identical to the CPU SpMV reference. These small
matrices are numerical/application-structure evidence, not acceleration wins:
[`results/m7/2026-08-29-m4-pro-external-matrix-market.json`](../../results/m7/2026-08-29-m4-pro-external-matrix-market.json).

The CuMetal CUDA `fp64_precision` workload now passes on the same device under
`fast48`, `wide48`, and `ieee64`, including arithmetic, comparisons, libdevice
FMA/square root/min/max, remainder, rounding, shared-memory and shuffle
reductions, store/reload, and `uint64_t` aliasing. The current integrated proof
is recorded with M5:
[`results/m5/2026-08-29-m4-pro-cumetal-vf64.json`](../../results/m5/2026-08-29-m4-pro-cumetal-vf64.json).
The earlier reduced-pair-only run remains as historical evidence:
[`results/m7/2026-08-29-m4-pro-cumetal-legacy-fp64.json`](../../results/m7/2026-08-29-m4-pro-cumetal-legacy-fp64.json).

An unmodified HiGHS 1.15.1 `CUPDLP_GPU` build supplies the general sparse LP
solver path. On Netlib `afiro` with presolve disabled, `wide48` and `ieee64`
both pass the frozen status/objective/residual gate and record more than 2,600
Apple-GPU launches. `fast48` reaches Optimal with a 3.1e-8 objective difference
but fails the stricter residual-parity gate: its dual residual is 10.5x the CPU
residual against a 10x limit. The `ieee64` solve is explicitly mixed because
translated CUDA kernels are exact while cuSPARSE SpMV is still a labeled
reduced-precision library substitution:
[`results/m7/2026-08-29-m4-pro-highs-afiro-vf64.json`](../../results/m7/2026-08-29-m4-pro-highs-afiro-vf64.json).

This is not the M7 exit. Energy measurements and cross-device reproduction
remain open.
The non-privileged `powermetrics` GPU-power probe failed with its explicit
superuser requirement; no runtime-derived energy estimate is substituted.
`scripts/capture-energy.sh` freezes the privileged collection method and
preserves raw CPU/GPU samples, workload output, command status, interval, and
device/OS provenance. It intentionally fails before collection without root.

## Exit criterion

Demonstrate workloads that become practically GPU-accelerated on Apple Silicon
because of the stack, with device provenance and no unreported CPU fallback.
