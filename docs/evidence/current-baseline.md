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
conformance. A separate
pinned TestFloat result bridge
now covers add, subtract, multiply, divide, and square root; its exception flags
are not yet checked. FMA, conversions, comparisons, rounding support for the
remaining operations, exception state, and complete TestFloat coverage remain
absent.

On the same M4 Pro on 2026-08-29, Berkeley TestFloat Release 3e level 1
generated 46,464 cases for each add/subtract/multiply/divide and rounding-mode
cell, plus 768 cases for each square-root and rounding-mode cell. All 25 cells
passed result-bit comparison with zero mismatches. The covered
rounding directions were nearest-even, toward zero, toward negative, toward
positive, and nearest-away. NaNs were compared by class and exception flags
were parsed but not checked, so this is not the M1 exit artifact.

In 32-operation dependency chains, integer add was 4.38 times slower and
integer multiply 12.07 times slower than the pair-resident path.

## Current interpretation

- The pair path is the performance track.
- The integer path is the conformance track.
- A complete `ieee64` mode must not be exposed while unsupported operations can
  silently fall back to the pair representation.
- Device, OS/Metal version, corpus, timing method, and result artifacts must
  accompany future performance claims.
