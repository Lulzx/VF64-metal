# Berkeley TestFloat conformance workflow

The M1 acceptance oracle is Berkeley TestFloat Release 3e backed by SoftFloat.
The bootstrap script pins both upstream repositories by commit and builds the
generator and verifier locally under the ignored `.deps/` directory.

```bash
scripts/run-testfloat-m1.sh
```

The current bridge accepts `testfloat_gen` function records, batches operands
onto the Metal GPU, and compares returned bits with the generated SoftFloat
result. Supported operations are currently `f64_add`, `f64_sub`, and `f64_mul`
under all five IEEE rounding directions.

This is deliberately labeled **result conformance**, not full IEEE conformance:

- non-NaN result bits must match exactly;
- NaNs are compared by class;
- expected TestFloat exception flags are parsed and counted but not yet checked;
- tininess-after-rounding is the current generator default;
- division, square root, and fused FMA remain blocking M1 operations.

M2 must extend each GPU result with exception state and freeze signaling-NaN,
payload, default-NaN, and tininess policies before `testfloat_ver -checkNaNs`
and flag conformance can become release gates.
