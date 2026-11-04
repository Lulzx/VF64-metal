# Precision mode contracts

These contracts define the M3 numerical modes independently of future compiler
flags. All observable global-memory values use one packed IEEE binary64 `ulong`;
reduced representations may remain resident only between observable boundaries.

## `fast48`

`fast48` is the canonical `float2 {hi, lo}` expansion implemented by `emu_f64`.

- Precision: approximately 48 significant bits for ordinary normalized
  operands. Precision degrades near the binary32 underflow edge.
- Range: finite inputs must be representable inside the binary32 finite range.
  Binary64 subnormals, magnitudes below the supported envelope, and magnitudes
  above `Float.greatestFiniteMagnitude` are out of range and set the codec range
  flag. Intermediate arithmetic can still underflow or overflow in binary32.
- Rounding: constituent binary32 operations use nearest-even. The mode is not
  correctly rounded binary64.
- Operations: add, subtract, multiply, divide, and multiply-add. Multiply-add
  retains the high-product residual but is not an IEEE fused binary64 FMA.
- Special values: signed zero and infinities are retained at boundaries. NaNs
  are quieted and retain sign plus the high 22 payload bits. IEEE exception
  flags are not provided.
- Resident ABI: two 32-bit limbs (`float2`, 8 bytes). Global observable storage
  remains a packed 64-bit value.

The shortened multiplication and one-correction division implementations are
research variants, not the frozen `fast48` default.

## `wide48`

`wide48` stores a canonical FP32 expansion significand plus an explicit signed
scale exponent.

- Precision: approximately 48 significant bits. The committed validation gate
  requires at least 44 p01 relative-error bits for arithmetic and 46 for codec
  round trips; the current M4 Pro corpus exceeds 47 bits for every operation.
- Range: the entire finite binary64 input range, including subnormals, can be
  decoded. Packing rounds to the nearest-even binary64 boundary; a reduced-
  precision value near the top edge may round to infinity.
- Rounding: constituent binary32 operations use nearest-even. Add/sub align
  significands by exponent, multiply/divide combine exponents, and results are
  renormalized. This is not correctly rounded binary64.
- Operations: add, subtract, multiply, divide, and multiply-add. Multiply-add is
  multiply followed by add at wide48 precision, not a fused operation.
- Special values: native binary32 special handling; NaN sign/payload capacity
  matches `fast48`; no IEEE exception flags.
- Resident ABI: `{float hi, float lo, int exponent, uint reserved}` (16 bytes).
  The reserved word is zero. Observable global storage remains packed binary64.

## `ieee64`

`ieee64` is the integer software runtime documented in
[`ieee64.md`](ieee64.md). It preserves all binary64 bits and range, implements
the complete M2 surface, all five rounding modes, sticky exceptions,
after-rounding tininess, bitwise ARM-VFPv2 NaN behavior, and true fused FMA.
Its resident representation is one 64-bit `ulong`.

## Transcendental functions

The M9 correctly rounded functions (`exp` through `atanh`, listed in
[`ieee64.md`](ieee64.md#explicitly-unsupported-surface)) have an `ieee64`
contract only: as Metal source-level `soft_<name>_status` calls, and as the
flag-free linkable support symbols `vf64_<name>_rne` and `vf64_<name>_round`
described in the [API/ABI contract](../release/api-abi.md#linkable-metal-support-abi).
They are not VF64 v1 operations in any mode.

Apart from the explicit `wide48` hypot helper below, `fast48` and `wide48`
have no transcendental contract. A request for another
transcendental function in a reduced mode must be refused, never satisfied by
a reduced-precision evaluation or by quietly switching to the `ieee64` call.
`vf64-compile` refuses every M9 function name under `--fp64=fast48`, `wide48`,
`ieee64`, and `auto` with a dedicated diagnostic, since VF64 v1 has no opcode
to lower it to, and `scripts/check-cli-api.sh` gates that refusal. CuMetal
does not meet this contract yet: it evaluates CUDA double transcendentals at
binary32 precision in every mode (see the
[support matrix](../release/support-matrix.md)).

## Materialization and finite-only rules

A reduced value must be packed before global or externally visible storage,
integer/bit reinterpretation, an untyped call, atomics, or an unsupported
operation. Loads split or scale once and may remain resident through a
straight-line region. Residency changes cost only; it never strengthens the
mode's numerical contract.

A finite-only kernel may omit special-value branches only when its interface or
compiler guard proves finite, in-range inputs and defines overflow behavior.
The finite-only property must be visible in its name or metadata; it cannot be
silently substituted for a general mode operation.

## Reduced hypot support helper

`wide_hypot` and the linkable `vf64_wide_hypot(ulong, ulong)` compute an
reduced-precision Euclidean norm, `sqrt(x*x + y*y)`, from two `wide48`
operands. This helper adds no VF64 bytecode opcode or source-compiler lowering.
`fast48` has no hypot helper.

Both squares, their sum and the square root retain the explicit integer
exponent until the final binary64 pack. A finite binary64 input has a scale
between -1074 and 1023 (normalization can increase the latter by one). Squaring
therefore needs scales only between -2148 and 2049; addition can increase the
scale once more. These fit in the signed 32-bit exponent. The significands
remain normalized floating-point expansions, so intermediate binary64 overflow
or underflow cannot occur. Very small summands can be discarded by `wide_add`:
when its scale difference exceeds 60, the squared contribution is less than
2^-60 of the larger square, changing the exact norm by less than 2^-61 relative.
This range argument does not prove a total rounding-error bound.

Infinity takes precedence over NaN, both zero inputs produce positive zero,
and other finite inputs produce a nonnegative result. NaN payload preservation
and IEEE exception flags are not provided. Final subnormal and overflow
behavior follows `wide_pack64`, including the existing reduced-precision
uncertainty at the overflow edge.

The accuracy validation accepts the existing pinned MPFR hypot vectors through
`vf64-metal wide-hypot`. It compares against MPFR nearest-even binary64 results
for the original binary64 inputs, so this gate includes input decoding error
as well as arithmetic and output packing error. It uses a relative tolerance
of 2^-44, allowing one binary64 ulp where larger,
and treats results within that tolerance of the overflow boundary separately.
This is a corpus validation threshold, not a proven worst-case error bound or
a correct-rounding claim. The normal `validate` command includes the committed
MPFR smoke vectors. A full seeded run can reuse the oracle generator:

```sh
generator=$(scripts/bootstrap-mpfr.sh)
"$generator" f64_hypot rnear_even boundary | .build/release/vf64-metal wide-hypot
"$generator" f64_hypot rnear_even random 1000000 1 | .build/release/vf64-metal wide-hypot
```

The arithmetic uses the project's existing expansion primitives; no external
implementation is incorporated. The mathematical background is the
[double-word arithmetic analysis of Joldes, Muller and Popescu (2017)](https://doi.org/10.1145/3121432)
and the [Euclidean norm and double-word square-root analysis of Lefèvre,
Louvet, Muller, Picot and Rideau (2023)](https://doi.org/10.1145/3568672).
Their bounds are not asserted for this implementation without checking their
algorithmic and floating-point assumptions.
