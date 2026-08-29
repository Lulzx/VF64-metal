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
declared convergence tolerances but are currently slowed by synchronous
dispatch and scalar readback.

Machine-readable evidence:
[`results/m7/2026-08-29-m4-pro-workload-pilot.json`](../../results/m7/2026-08-29-m4-pro-workload-pilot.json).

This is not the M7 exit. CuMetal CUDA workloads, energy measurements, broader
LP and sparse matrices, and cross-device reproduction remain open.
The non-privileged `powermetrics` GPU-power probe failed with its explicit
superuser requirement; no runtime-derived energy estimate is substituted.

## Exit criterion

Demonstrate workloads that become practically GPU-accelerated on Apple Silicon
because of the stack, with device provenance and no unreported CPU fallback.
