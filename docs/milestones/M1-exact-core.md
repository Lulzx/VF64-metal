# M1 — Exact core arithmetic

Implement correctly rounded binary64:

- add and subtract;
- multiply and divide;
- square root;
- true fused FMA with one final rounding;
- all IEEE rounding modes.

The current integer prototype covers add, subtract, multiply, divide, square
root, and true fused FMA result bits in all five IEEE rounding directions. The
committed level-1 operation-by-mode TestFloat matrix has zero result mismatches
and reproducible provenance. Broader release corpus policy and the boundary
between M1 result conformance and M2 flags/NaN semantics remain to be frozen.
The reproducible TestFloat workflow and its current result-only limitations are
documented in [the conformance guide](../conformance/testfloat.md). Host
`Double` differential tests are smoke coverage and must not be reported as
SoftFloat/TestFloat evidence.

## Exit criterion

Differential conformance against Berkeley SoftFloat/TestFloat with zero
unexplained mismatches. Results must identify operation, rounding mode, corpus,
device, Metal version, tininess policy, and NaN comparison policy.
