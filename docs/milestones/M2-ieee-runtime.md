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
bitwise NaN payload conversion. The final full-runtime NaN policy and ABI remain
to be frozen.

Operation availability must be explicit. An unsupported exact operation may
fail compilation or dispatch to an exact implementation, but must never
silently use `fast48`.

## Exit criterion

A complete, documented IEEE-754 binary64 software runtime for Metal GPU compute,
including ABI, rounding, exceptions, NaNs, and unsupported-language boundaries.
