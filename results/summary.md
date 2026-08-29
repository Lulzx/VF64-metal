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

## M2 complete IEEE-754 runtime

Status: **complete** for the documented M2 runtime surface.

At source commit `d96094a`, `scripts/run-testfloat-m2.sh` passed 31,982,976
level-1 result and exception-flag comparisons on the Apple M4 Pro. This covers
the six exact arithmetic operations, comparisons, remainder, round-to-integer,
signed/unsigned 32/64-bit integer conversions, and binary16/binary32
interchange. Floating NaN results match ARM-VFPv2 sign, quiet bit, and payload
bitwise. Tininess is detected after rounding.

Machine-readable evidence:
[`m2/2026-08-29-m4-pro-full-runtime-level1.json`](m2/2026-08-29-m4-pro-full-runtime-level1.json).

The earlier core-only flag artifact remains as historical incremental evidence.
Level 2 exhaustive campaigns are not implied by this level-1 exit.
