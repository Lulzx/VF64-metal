# M1 — Exact core arithmetic

Implement correctly rounded binary64:

- add and subtract;
- multiply and divide;
- square root;
- true fused FMA with one final rounding;
- all IEEE rounding modes.

The current integer prototype covers add, subtract, multiply, divide, and square
root result bits in all five IEEE rounding directions. True fused FMA and the
complete operation-by-mode TestFloat matrix remain. Existing differential
results are a foundation, not completion of M1.
The reproducible TestFloat workflow and its current result-only limitations are
documented in [the conformance guide](../conformance/testfloat.md). Host
`Double` differential tests are smoke coverage and must not be reported as
SoftFloat/TestFloat evidence.

## Exit criterion

Differential conformance against Berkeley SoftFloat/TestFloat with zero
unexplained mismatches. Results must identify operation, rounding mode, corpus,
device, Metal version, tininess policy, and NaN comparison policy.
