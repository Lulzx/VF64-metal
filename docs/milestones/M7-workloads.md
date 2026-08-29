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
N-body simulation. The cross-mode kernels contain no CPU arithmetic
fallback. CG and GMRES retain CPU scalar/control logic, which is printed and
recorded explicitly; their O(n) vector and matrix arithmetic executes on Metal.

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
The device-resident GMRES follow-up is
[`results/m7/2026-08-29-m4-pro-device-resident-gmres.json`](../../results/m7/2026-08-29-m4-pro-device-resident-gmres.json).
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
