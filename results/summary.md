# Reproducible result summary

## M1 exact core arithmetic

Status: **complete** for result-bit conformance; M2 semantic state is excluded.

The 2026-08-29 Apple M4 Pro run passed 31,599,360 binary64 result comparisons
against Berkeley TestFloat/SoftFloat with zero unexplained mismatches.

Covered operations:

- add, subtract, multiply, and divide: 46,464 cases per rounding mode;
- square root: 768 cases per rounding mode;
- true fused FMA: 6,133,248 cases per rounding mode;
- five IEEE rounding directions for every operation.

Reproduce with:

```bash
scripts/run-testfloat-m1.sh
```

Machine-readable provenance and policy are in
[`m1/2026-08-29-m4-pro-level1.json`](m1/2026-08-29-m4-pro-level1.json).

This is result-bit conformance with NaNs compared by class. It does not claim
M2 exception-flag, signaling-NaN, or payload conformance.

## M2 core exception state

The same 31,599,360 operation/mode cases now pass result and exception-flag
comparison at source commit `d856d8b`. This covers invalid, divide-by-zero,
overflow, underflow with tininess detected after rounding, and inexact.

Machine-readable evidence:
[`m2/2026-08-29-m4-pro-core-flags-level1.json`](m2/2026-08-29-m4-pro-core-flags-level1.json).

Since that core-flags artifact, comparisons, remainder, round-to-integer,
integer conversions, and binary16/binary32 conversions have passed their
level-1 TestFloat matrices. Floating-result operations also pass bitwise NaN
sign, quiet-bit, and payload comparison against the ARM-VFPv2 specialization.
M2 remains incomplete until the full runtime ABI is frozen and a consolidated
machine-readable exit artifact is committed.
