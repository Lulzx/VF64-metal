# Precision-stack architecture

## Separate contracts from mechanisms

User-facing modes describe numerical behavior:

| Mode | Contract |
| --- | --- |
| `fast48` | Approximately 48 significand bits in the binary32 exponent envelope |
| `wide48` | Similar precision with a wider, explicitly specified exponent contract |
| `ieee64` | Complete binary64 behavior for the advertised runtime surface |

Pair arithmetic, integer softfloat, compensated reductions, and future
Ozaki/CRT tiles are implementation mechanisms. A matrix backend with an
FP64-scale error bound must not silently turn a reduced mode into an IEEE claim.

## Policy shape

```text
CUDA/HPC source
      |
precision-policy compiler
      |
      +-- scalar expressions: fast48 | wide48 | ieee64
      +-- reductions: pair | reproducible/exact accumulator
      +-- matrix tiles: pair-FMA | future Ozaki/CRT backend
      |
Apple Metal
```

An adaptive policy can select per expression, tile, or row:

```text
safe precision and range         -> fast48
adequate precision, wider range  -> wide48
profitable matrix primitive      -> tile backend
exceptional or semantic hard case -> ieee64
```

## Residency rule

Current CuMetal pair residency removes split/pack churn in scalar chains. The
same rule should extend to kernels: decomposed state may live in registers or
threadgroup memory, but should reach global memory only at a real ABI or
semantic boundary.

Observable boundaries include `mov.b64`/`uint64_t` aliases, memory stores and
reloads, calls, shuffle operations, unsupported instructions, and control-flow
merges until pair-valued phi handling exists.

Placement must be measured:

- registers for short scalar chains;
- threadgroup memory for tiled or reused state;
- external memory only at observable boundaries.

