# M2 — Complete IEEE-754 runtime

Add the runtime surface around M1:

- conversions;
- comparisons;
- remainder and round-to-integer operations;
- subnormals, infinities, and signed zero;
- quiet/signaling NaN behavior;
- exception flags;
- a documented tininess policy.

Current progress: M1 core exception flags and the complete six-operation
TestFloat comparison family pass on the Metal GPU. Conversions, remainder,
round-to-integer, and the final NaN payload policy remain.

Operation availability must be explicit. An unsupported exact operation may
fail compilation or dispatch to an exact implementation, but must never
silently use `fast48`.

## Exit criterion

A complete, documented IEEE-754 binary64 software runtime for Metal GPU compute,
including ABI, rounding, exceptions, NaNs, and unsupported-language boundaries.
