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

Status: **complete** for the VF64 source compiler and delivered M4 Pro. The
frontend accepts `--fp64=auto`, consumes a measured slot exponent profile and
declared accuracy bits, propagates conservative exponent intervals and an
accumulated reduced-operation error budget, and emits a JSON decision record
for every arithmetic instruction. Missing finite/range proof, an exhausted
error budget, or a contract above the reduced floor falls back to `ieee64`.

The exit workload used 22 dependent operations per lane and selected five
`fast48` plus seventeen `wide48` operations. It achieved 43.86 p01 bits against
a declared 40-bit contract and ran 1.18× faster than the identical pure
`ieee64` program. Evidence:
[`results/m6/2026-08-29-m4-pro-auto-mixed-chain.json`](../../results/m6/2026-08-29-m4-pro-auto-mixed-chain.json).

## Exit criterion

Mixed execution meets its declared accuracy/convergence contract while
outperforming pure software binary64 on the same delivered Apple GPU.

Exit: **met** for the declared accuracy-contract path.
