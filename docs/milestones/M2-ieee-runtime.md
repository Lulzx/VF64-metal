# M2 — Complete IEEE-754 runtime

Add the runtime surface around M1:

- conversions;
- comparisons;
- remainder and round-to-integer operations;
- subnormals, infinities, and signed zero;
- quiet/signaling NaN behavior;
- exception flags;
- a documented tininess policy.

Status: **complete** at source commit `d96094a` plus the consolidated exit
artifact. M1 core exception flags, the complete six-operation TestFloat
comparison family, and round-to-integer under every rounding/exactness policy
pass on the Metal GPU. IEEE remainder also passes its result/flag matrix.
Signed and unsigned 32/64-bit integer-to-binary64 conversions pass every
rounding mode. Binary64-to-integer conversions also pass every rounding and
exactness policy. Binary16/binary32 narrowing and widening also pass, including
bitwise NaN payload conversion. Floating-result operations now also pass
bitwise NaN comparison against the pinned ARM-VFPv2 SoftFloat specialization.
The source-level value, storage, rounding, exception, conversion, and
unsupported-operation contract is documented in
[`runtime/ieee64.md`](../runtime/ieee64.md). The consolidated Apple M4 Pro
level-1 run compared 31,982,976 results and flags with zero mismatches; its
machine-readable provenance is in
[`results/m2/2026-08-29-m4-pro-full-runtime-level1.json`](../../results/m2/2026-08-29-m4-pro-full-runtime-level1.json).

## NaN contract

The exact runtime follows the pinned SoftFloat ARM-VFPv2 specialization:

- every signaling NaN raises `invalid` and is quieted;
- if either binary operand is signaling, its quieted payload is selected, with
  the first operand winning when both signal;
- otherwise the first NaN operand is propagated;
- subtraction propagates the original operands without changing a NaN sign;
- invalid operations without a NaN operand return `0x7ff8000000000000`;
- FMA applies the same rule in SoftFloat's `a`, `b`, then `c` propagation order;
- format conversions preserve the representable sign and payload bits and set
  the destination quiet bit.

Operation availability must be explicit. An unsupported exact operation may
fail compilation or dispatch to an exact implementation, but must never
silently use `fast48`.

## Exit criterion

A complete, documented IEEE-754 binary64 software runtime for Metal GPU compute,
including ABI, rounding, exceptions, NaNs, and unsupported-language boundaries.

Exit: **met** for the documented M2 surface and level-1 conformance policy.
