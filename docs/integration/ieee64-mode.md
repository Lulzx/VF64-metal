# Separate exact-binary64 mode

Retiring the reduced-precision/range warning requires a different arithmetic
representation. The current harness prototypes integer binary64 add and
multiply using `ulong`, `mulhi`, `clz`, explicit normalization, and
round-to-nearest-even.

On the measured M4 Pro, 32-operation dependency chains gave:

| Operation | Pair-resident | Integer exact prototype | Slowdown |
| --- | ---: | ---: | ---: |
| add | 122,053 M/s | 27,843 M/s | 4.38x |
| multiply | 203,360 M/s | 16,854 M/s | 12.07x |

The integer operations matched host bits for 215,172 cases each, with NaNs
compared by class. This does not complete an exact mode; see
[M1](../milestones/M1-exact-core.md) and
[M2](../milestones/M2-ieee-runtime.md).

Do not expose `--fp64=ieee64` or a `soft` equivalent until every emitted FP64
operation either has exact declared semantics or fails explicitly. Silent pair
fallback would make the mode contract false.

