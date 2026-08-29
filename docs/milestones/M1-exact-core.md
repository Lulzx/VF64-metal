# M1 — Exact core arithmetic

Implement correctly rounded binary64:

- add and subtract;
- multiply and divide;
- square root;
- true fused FMA with one final rounding;
- all IEEE rounding modes.

The current integer prototype covers round-to-nearest-even add and multiply
only. Existing differential results are a foundation, not completion of M1.

## Exit criterion

Differential conformance against Berkeley SoftFloat/TestFloat with zero
unexplained mismatches. Results must identify operation, rounding mode, corpus,
device, Metal version, tininess policy, and NaN comparison policy.

