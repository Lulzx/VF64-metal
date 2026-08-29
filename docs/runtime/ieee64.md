# Exact binary64 Metal runtime contract

This document freezes the M2 source-level runtime contract. It is not the M4
virtual instruction encoding or the eventual M8 stable external ABI.

## Value and storage ABI

- A binary64 value is one Metal `ulong` containing the 64 IEEE-754 interchange
  bits. No native Metal floating type is used to transport or store it.
- Device and constant buffers use an 8-byte element stride and at least 8-byte
  alignment. Arrays are arrays of `ulong`, with no pair encoding.
- Binary32 and binary16 values cross this API as raw bits in the low 32 or 16
  bits of a `ulong`. Integer conversion results use the low 32 or 64 bits; signed
  results use two's-complement encoding.
- Results retain signed zero, infinities, subnormals, and the NaN policy below.

The implementation is compiled from
`Sources/F64Metal/Shaders/IEEE/Arithmetic.metal`. Callers include that source
before their kernels and keep exact values packed as `ulong` at every observable
boundary.

## Rounding and exception state

Rounding mode values are:

| Value | Meaning |
| ---: | --- |
| `0` | nearest, ties to even |
| `1` | toward zero |
| `2` | toward negative infinity |
| `3` | toward positive infinity |
| `4` | nearest, ties away from zero |

The caller owns a thread-local `uint flags`, initializes it to zero when a new
exception scope begins, and passes it by `thread uint &`. Operations OR raised
exceptions into the existing value, so a sequence naturally produces sticky
state. Flag bits are:

| Bit | Value | Exception |
| ---: | ---: | --- |
| 0 | `1` | inexact |
| 1 | `2` | underflow |
| 2 | `4` | overflow |
| 3 | `8` | divide by zero |
| 4 | `16` | invalid |

Tininess is detected after rounding. Exact conversion and round-to-integer
entry points take an `exact` Boolean: discarded nonzero bits raise `inexact`
only when it is true. There are no traps; the caller may store, combine, or
ignore sticky flags.

## Operation surface

The status functions below are the M2 source API. Every floating result is raw
binary64 bits unless another format is named.

| Family | Entry point | Notes |
| --- | --- | --- |
| arithmetic | `soft_add64_status`, `soft_sub64_status`, `soft_mul64_status`, `soft_div64_status` | two operands, rounding mode, flags |
| square root | `soft_sqrt64_status` | one operand, rounding mode, flags |
| fused multiply-add | `soft_fma64_status` | computes `a * b + c` with one rounding |
| equality | `soft_equal64_status` | quiet or signaling selected by argument |
| ordering | `soft_less64_status` | less-than / less-or-equal and quiet / signaling selected by arguments |
| round to integral value | `soft_round_to_int64_status` | rounding mode and exactness argument |
| IEEE remainder | `soft_remainder64_status` | nearest-even integral quotient; independent of rounding mode |
| unsigned/signed integer to binary64 | `soft_uint_to_f64_status` | magnitude plus sign, rounding mode |
| binary64 to integer | `soft_f64_to_int_status` | signedness, 32/64 width, rounding mode, exactness |
| binary64 to binary16/32 | `soft_f64_to_format_status` | instantiated with `(5,10,15)` or `(8,23,127)` |
| binary16/32 to binary64 | `soft_format_to_f64_status` | exact widening with the same format tuples |

The convenience arithmetic functions without `_status` use nearest-even and
discard exception state. They are valid only when the caller's contract does
not observe flags.

Invalid binary64-to-integer conversions use the pinned ARM-VFPv2 SoftFloat
results: NaNs map to zero; positive overflow maps to the target maximum;
negative signed overflow maps to the target minimum; negative values converted
to unsigned map to zero. `invalid` is raised and `inexact` is suppressed.

## NaNs and special values

The exact policy is the pinned SoftFloat ARM-VFPv2 specialization:

- signaling NaNs raise `invalid` and become quiet;
- a signaling operand is preferred over a quiet operand, with the first operand
  winning when both signal;
- otherwise the first NaN operand is propagated;
- FMA applies SoftFloat's `a`, `b`, then `c` propagation order;
- invalid operations with no NaN operand return `0x7ff8000000000000`;
- narrowing and widening preserve every payload bit representable in the
  destination, the sign, and set the destination quiet bit.

Arithmetic preserves the full normal and subnormal binary64 range. Exact zero
signs, overflow selection, and underflow results follow the active rounding
mode.

## Explicitly unsupported surface

The M2 runtime does not implement transcendental functions, decimal formats,
binary128, FP64 atomics, total ordering, or language/compiler lowering. A
caller must implement or reject those operations explicitly. It must never
substitute the reduced-range `fast48` pair path for an exact operation.

Kernel buffer indices in `Shaders/Kernels/Exact.metal` belong to the validation
harness, not this runtime contract. M4 will define the independent virtual ISA
and its stable dispatch/storage ABI.
