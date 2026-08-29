# Berkeley TestFloat conformance workflow

The M1 acceptance oracle is Berkeley TestFloat Release 3e backed by SoftFloat.
The bootstrap script pins both upstream repositories by commit and builds the
generator and verifier locally under the ignored `.deps/` directory.

```bash
scripts/run-testfloat-m1.sh
```

The current committed artifact is summarized in
[`results/summary.md`](../../results/summary.md), with machine-readable device,
source, oracle, corpus, and policy provenance beside it.

The current bridge accepts `testfloat_gen` function records, batches operands
onto the Metal GPU, and compares returned bits with the generated SoftFloat
result. Supported operations are currently `f64_add`, `f64_sub`, `f64_mul`,
`f64_div`, `f64_sqrt`, and true fused `f64_mulAdd` under all five IEEE rounding
directions.

This is deliberately labeled **result conformance**, not full IEEE conformance:

- non-NaN result bits must match exactly;
- NaNs are compared by class;
- expected TestFloat exception flags are parsed and counted but not yet checked;
- tininess-after-rounding is the current generator default;
- the current level-1 matrices are not the complete M1 release corpus.

TestFloat level 2 has materially different minimum corpus sizes: 40,284,288
cases per binary-operation cell, 26,112 per square-root cell, and
180,795,884,544 per fused-FMA cell. Level-2 campaigns must therefore be
recorded separately and must not be implied by the reproducible level-1 gate.

M2 must extend each GPU result with exception state and freeze signaling-NaN,
payload, default-NaN, and tininess policies before `testfloat_ver -checkNaNs`
and flag conformance can become release gates.

M2 progress: every M1 operation now compares TestFloat invalid,
divide-by-zero, overflow, underflow-after-rounding, and inexact flags in every
rounding mode. The original M1 artifact remains result-only; a separate M2
artifact records the stronger flag-conformance run.
