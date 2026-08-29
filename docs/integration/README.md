# CuMetal integration

CuMetal already emits accurate FP32-pair arithmetic. Its primary near-term cost
is representation churn: each FP64 PTX register assignment packs the pair into
binary64 bits and the next arithmetic instruction decodes it again.

Removing that churn cannot improve numerical quality. Binary64 storage is wider
than the pair payload, so pair residency preserves the existing approximately
48-bit, binary32-range contract.

Integration notes:

- [Pair-resident compiler representation](representation.md)
- [Observable materialization boundaries](boundaries.md)
- [Incremental implementation phases](implementation-phases.md)
- [Validation and benchmark gates](verification.md)
- [Separate exact-binary64 mode](ieee64-mode.md)

