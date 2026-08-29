# M6 — Automatic precision selection

Introduce:

```text
--fp64=auto
```

The compiler selects `fast48`, `wide48`, or `ieee64` per operation or region
using static constraints, exponent-span information, runtime profiling, or an
explicit hybrid. Every decision must have a safe fallback and be observable in
diagnostic output.

The optimizer must target a declared application-level accuracy or convergence
contract, not merely minimize local ulp error.

## Exit criterion

Mixed execution meets its declared accuracy/convergence contract while
outperforming pure software binary64 on the same delivered Apple GPU.

