# M5 — Compiler integration

Lower source-level `double` into the virtual FP64 ISA with explicit policies:

```text
--fp64=fast48
--fp64=wide48
--fp64=ieee64
```

The compiler should preserve internal pair or exact state across SSA chains and
materialize storage bits only at ABI, aliasing, call, memory, shuffle, or other
observable boundaries.

CuMetal is the first integration target. CUDA-visible `mov.b64`, `uint64_t`,
shared-memory, shuffle, reload, and call behavior are mandatory regression
surfaces.

## Exit criterion

Existing numerical kernels use `double` without manually calling emulation
functions, and each policy is demonstrably routed through its declared backend.

