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

The standalone [`VF64 source compiler`](../compiler/source-language.md)
lowers typed arithmetic, comparisons, selection, and all twelve VF64 conversion
directions through executable bytecode. Arithmetic and comparison/selection are
executed under each explicit precision policy; conversions validate result bits
and exception flags. Last-use allocation reduces a 96-operation source chain to
two physical VF64 registers while preserving exact results and sticky flags.
Evidence:
[`results/m5/2026-08-29-m4-pro-typed-source-compiler.json`](../../results/m5/2026-08-29-m4-pro-typed-source-compiler.json).

The exact runtime is also exported as a statically linkable AIR support
module with 38 raw-bit entry points. Its build, symbol, AIR-link,
pipeline-creation, and GPU execution gate is `scripts/check-vf64-support.sh`.
CuMetal now lowers ordinary CUDA/PTX `double` into that support ABI. Its
three-mode gate compiles and executes one unchanged CUDA source under `fast48`,
`wide48`, and `ieee64`, and checks mode-specific launch provenance. The probe
covers arithmetic chains, fused FMA, square root, conversions, comparisons,
min/max, remainder, rounding, global/shared storage, shuffle, reload, and
`uint64_t` aliasing. Evidence:
[`results/m5/2026-08-29-m4-pro-cumetal-vf64.json`](../../results/m5/2026-08-29-m4-pro-cumetal-vf64.json).

The reproducible integration gate is `scripts/check-cumetal-integration.sh`.

## Exit criterion

Existing numerical kernels use `double` without manually calling emulation
functions, and each policy is demonstrably routed through its declared backend.

Exit: **met** on the recorded Apple M4 Pro path.
