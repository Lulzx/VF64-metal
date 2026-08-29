# Observable materialization boundaries

Pack a valid pair before:

- global, shared, local, or parameter stores;
- `mov.b64`, integer reinterpretation, or 64-bit aliasing;
- calls through the current untyped bit-slot ABI;
- atomics and compare-and-swap;
- unsupported operations that require packed representation;
- control-flow merges until pair-valued phi handling exists.

An FP64 load from a boundary splits once and marks the pair valid.

Warp shuffle can initially pack, shuffle two 32-bit storage halves, and split.
Direct limb shuffling is faster but should land only after tests prove identical
CUDA-visible bits at the next observable boundary.

