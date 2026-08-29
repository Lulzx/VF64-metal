# Berkeley TestFloat conformance workflow

The M1 acceptance oracle is Berkeley TestFloat Release 3e backed by SoftFloat.
The bootstrap script pins both upstream repositories by commit and builds the
generator and verifier locally under the ignored `.deps/` directory.

```bash
scripts/run-testfloat-m1.sh
scripts/run-testfloat-m2.sh
```

The first command is the frozen M1 arithmetic gate. The second runs that gate
and then the complete M2 operation surface.

The current committed artifact is summarized in
[`results/summary.md`](../../results/summary.md), with machine-readable device,
source, oracle, corpus, and policy provenance beside it.

Public operation-by-operation counts for both the direct runtime and VF64 ISA
paths are in the checked
[`operation matrix`](../../results/conformance/2026-08-29-m4-pro-operation-matrix.json).
Run `scripts/check-conformance-data.sh` to verify that its 26 operations, 119
policy cells, and 31,982,976 comparisons per path reconcile with the frozen M2
and M4 artifacts.

The current bridge accepts `testfloat_gen` function records, batches operands
onto the Metal GPU, and compares returned bits and exception flags with the
generated SoftFloat result. It covers the M1 arithmetic family plus M2
comparisons, remainder, round-to-integer, integer conversions, and binary16 /
binary32 format conversions.

The committed M1 artifact is deliberately labeled **result conformance**, not
full IEEE conformance:

- non-NaN result bits must match exactly;
- NaNs were compared by class for that frozen artifact;
- exception flags were not checked for that frozen artifact;
- tininess-after-rounding is the current generator default;
- the current level-1 matrices are not the complete M1 release corpus.

TestFloat level 2 has materially different minimum corpus sizes: 40,284,288
cases per binary-operation cell, 26,112 per square-root cell, and
180,795,884,544 per fused-FMA cell. Level-2 campaigns must therefore be
recorded separately and must not be implied by the reproducible level-1 gate.

M2 progress: every M1 operation now compares TestFloat invalid,
divide-by-zero, overflow, underflow-after-rounding, and inexact flags in every
rounding mode. Floating results now compare NaN sign, quiet bit, and payload
bitwise under the pinned ARM-VFPv2 policy. The original M1 artifact remains
result-only; separate M2 evidence records the stronger conformance runs.
