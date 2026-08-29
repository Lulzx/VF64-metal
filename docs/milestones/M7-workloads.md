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

## Exit criterion

Demonstrate workloads that become practically GPU-accelerated on Apple Silicon
because of the stack, with device provenance and no unreported CPU fallback.

