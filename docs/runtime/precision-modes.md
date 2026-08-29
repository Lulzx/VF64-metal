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
