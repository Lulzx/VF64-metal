# Current F64Metal evidence

Date: 2026-08-29

## FP32-pair track

The `{hi, lo}` representation has approximately 48 significand bits and the
binary32 exponent envelope. It includes add, subtract, multiply, divide,
emulated FMA, codecs, special-value handling, pair-resident dot reduction, and
multiple arithmetic variants.

On an Apple M4 Pro with 16 GPU cores, Metal 4, measured 2026-08-27:

| Operation | p01 precision | Median precision |
| --- | ---: | ---: |
| add | 47.96 bits | 50.89 bits |
| multiply | 47.45 bits | 49.96 bits |
| divide | 47.39 bits | 49.89 bits |
| FMA | 47.41 bits | 50.38 bits |

The codec measured 49.12 p01 and 51.44 median precision bits and was
idempotent. Pair residency is a speed optimization only; it cannot add
precision or range.

## Integer binary64 track

`soft_add64`, `soft_sub64`, `soft_mul64`, `soft_div64`, and `soft_sqrt64`
matched the host's round-to-nearest-even result in 215,172 directed and random
cases per operation, with NaNs compared by class. This host-oracle smoke corpus
is evidence for those five operations only and is not Berkeley TestFloat
conformance. A separate pinned TestFloat result bridge now covers add,
subtract, multiply, divide, square root, and true fused FMA; its exception flags
are not yet checked. Conversions, comparisons, exception state, and complete
release TestFloat coverage remain absent.

On the same M4 Pro on 2026-08-29, Berkeley TestFloat Release 3e level 1
generated 46,464 cases for each add/subtract/multiply/divide and rounding-mode
cell, plus 768 cases for each square-root and rounding-mode cell. All 25 cells
passed result-bit comparison with zero mismatches. The covered
rounding directions were nearest-even, toward zero, toward negative, toward
positive, and nearest-away. NaNs were compared by class and exception flags
were parsed but not checked, so this is not the M1 exit artifact.

True fused `f64_mulAdd` passed 6,133,248 level-1 cases in each of the same five
rounding directions (30,666,240 result comparisons total) with zero mismatches.
The implementation retains the exact 106-bit product in a 128-bit aligned
accumulator and performs one final rounding after adding the third operand.

The M2 comparison surface passed 46,464 TestFloat cases for each of `f64_eq`,
`f64_le`, `f64_lt`, `f64_eq_signaling`, `f64_le_quiet`, and `f64_lt_quiet`.
Results and invalid flags matched in all 278,784 comparisons, including signed
zero and quiet/signaling NaN cases.

`f64_roundToInt` passed 768 TestFloat cases in each rounding direction under
both `exact` and `notexact` policies. All 7,680 result/flag comparisons matched;
the exact policy raises inexact when fractional bits are discarded.

`f64_rem` passed 46,464 TestFloat result/flag cases. The implementation computes
the modulus exactly, selects the nearest quotient with ties-to-even, and
preserves the dividend sign on an exact-zero remainder.

`ui32`, `i32`, `ui64`, and `i64` conversions to binary64 passed all five
rounding directions: 372 cases per 32-bit cell and 756 per 64-bit cell, for
11,280 result/flag comparisons with zero mismatches.

Binary64 conversion to the same four integer targets passed 768 cases in every
rounding/exactness cell: 30,720 result/flag comparisons. NaNs and overflows use
the pinned ARM-VFPv2 SoftFloat saturation results and raise invalid.

Binary64 narrowing to binary32 and binary16 passed 768 TestFloat cases in each
of five rounding modes. Exact widening passed 600 binary32 and 408 binary16
cases. Cross-format NaN payloads and signaling invalid flags matched bitwise.

In 32-operation dependency chains, integer add was 4.38 times slower and
integer multiply 12.07 times slower than the pair-resident path.

## Current interpretation

- The pair path is the performance track.
- The integer path is the conformance track.
- A complete `ieee64` mode must not be exposed while unsupported operations can
  silently fall back to the pair representation.
- Device, OS/Metal version, corpus, timing method, and result artifacts must
  accompany future performance claims.
