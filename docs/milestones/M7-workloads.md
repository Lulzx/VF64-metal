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
moves reductions and alpha/beta to GPU, preserves the 1.453e-12 residual, and
measures 1.06x CPU; GMRES remains slowed by synchronous scalar readback.

Machine-readable evidence:
[`results/m7/2026-08-29-m4-pro-workload-pilot.json`](../../results/m7/2026-08-29-m4-pro-workload-pilot.json).
The device-resident scheduling follow-up is
[`results/m7/2026-08-29-m4-pro-device-resident-scheduling.json`](../../results/m7/2026-08-29-m4-pro-device-resident-scheduling.json).
The cross-mode CSR corpus adds periodic, symmetric positive-definite, and
nonsymmetric matrix structures:
[`results/m7/2026-08-29-m4-pro-sparse-corpus.json`](../../results/m7/2026-08-29-m4-pro-sparse-corpus.json).

The existing CuMetal CUDA `fp64_precision` workload also passes on the same
device under `CUMETAL_FP64_MODE=emulate`, including pair round trips,
shared-memory and shuffle reductions, store/reload, and `uint64_t` aliasing.
That is legacy reduced-pair compatibility evidence, not VF64 integration:
[`results/m7/2026-08-29-m4-pro-cumetal-legacy-fp64.json`](../../results/m7/2026-08-29-m4-pro-cumetal-legacy-fp64.json).

This is not the M7 exit. VF64-integrated CuMetal CUDA workloads, energy
measurements, external/application sparse matrices, broader LP corpora, and
cross-device reproduction remain open.
The non-privileged `powermetrics` GPU-power probe failed with its explicit
superuser requirement; no runtime-derived energy estimate is substituted.

## Exit criterion

Demonstrate workloads that become practically GPU-accelerated on Apple Silicon
because of the stack, with device provenance and no unreported CPU fallback.
