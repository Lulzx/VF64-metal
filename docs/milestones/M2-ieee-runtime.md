# M2 — Complete IEEE-754 runtime

Add the runtime surface around M1:

- conversions;
- comparisons;
- remainder and round-to-integer operations;
- subnormals, infinities, and signed zero;
- quiet/signaling NaN behavior;
- exception flags;
- a documented tininess policy.

Current progress: M1 core exception flags, the complete six-operation TestFloat
comparison family, and round-to-integer under every rounding/exactness policy
pass on the Metal GPU. IEEE remainder also passes its result/flag matrix.
Signed and unsigned 32/64-bit integer-to-binary64 conversions pass every
rounding mode. Binary64-to-integer conversions also pass every rounding and
exactness policy. Binary16/binary32 narrowing and widening also pass, including
bitwise NaN payload conversion. Floating-result operations now also pass
bitwise NaN comparison against the pinned ARM-VFPv2 SoftFloat specialization.
The remaining M2 exit work is to freeze and document the complete runtime ABI.

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
