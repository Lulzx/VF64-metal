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

Current progress: the standalone [`VF64 source compiler`](../compiler/source-language.md)
lowers typed arithmetic, comparisons, selection, and all twelve VF64 conversion
directions through executable bytecode. Arithmetic and comparison/selection are
executed under each explicit precision policy; conversions validate result bits
and exception flags. Last-use allocation reduces a 96-operation source chain to
two physical VF64 registers while preserving exact results and sticky flags.
Evidence:
[`results/m5/2026-08-29-m4-pro-typed-source-compiler.json`](../../results/m5/2026-08-29-m4-pro-typed-source-compiler.json).

This remains a straight-line standalone frontend. CuMetal source/PTX
integration and its observable-boundary regression suite remain required before
M5 can close.

## Exit criterion

Existing numerical kernels use `double` without manually calling emulation
functions, and each policy is demonstrably routed through its declared backend.
