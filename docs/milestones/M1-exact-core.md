# M1 — Exact core arithmetic

Status: **complete** for the documented result-bit conformance boundary.

Implement correctly rounded binary64:

- add and subtract;
- multiply and divide;
- square root;
- true fused FMA with one final rounding;
- all IEEE rounding modes.

The current integer prototype covers add, subtract, multiply, divide, square
root, and true fused FMA result bits in all five IEEE rounding directions. The
committed level-1 operation-by-mode TestFloat matrix has zero result mismatches
and reproducible provenance. Level-2 campaigns are supplemental rather than the
reproducible M1 gate; M2 owns flags and detailed NaN semantics.

Exit evidence:

- [`results/summary.md`](../../results/summary.md);
- [`2026-08-29-m4-pro-level1.json`](../../results/m1/2026-08-29-m4-pro-level1.json).

The M1 boundary compares every non-NaN result bit and compares NaNs by class.
Tininess is configured after rounding. Exception flags, signaling-NaN behavior,
and payload policy are explicitly M2 and are not claimed here.
The reproducible TestFloat workflow and its current result-only limitations are
documented in [the conformance guide](../conformance/testfloat.md). Host
`Double` differential tests are smoke coverage and must not be reported as
SoftFloat/TestFloat evidence.

## Exit criterion

Differential conformance against Berkeley SoftFloat/TestFloat with zero
unexplained mismatches. Results must identify operation, rounding mode, corpus,
device, Metal version, tininess policy, and NaN comparison policy.
