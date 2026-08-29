# CuMetal implementation phases

## Phase 1 — Straight-line blocks

Cache pairs by PTX register within one basic block. Invalidate at labels,
branches, calls, barriers, destination overwrites, and observable boundaries.

## Phase 2 — Pair register slots

Represent each emulated FP64 register with two float slots and track whether
bits or limbs are authoritative. Extend retention across ordinary control flow.

## Phase 3 — Operation fusion

Lower `fma.rn.f64` and recognized multiply-add sequences with a dedicated pair
FMA. Do not pack the product before adding the third operand.

## Phase 4 — Explicit performance variants

Potential research policies:

```text
strict    full lo*lo multiplication, two-correction division
balanced  full multiplication, one-correction division
fast      omit lo*lo, one-correction division
```

These are emulated variants and must not overload a `native` or `ieee64` name.

