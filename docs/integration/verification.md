# CuMetal verification gates

The existing strict FP64 runner remains the numerical acceptance boundary:

- error remains within the documented approximately 48-bit contract;
- `pack(split(x))` remains stable at every observable boundary;
- signed zero, infinities, and NaNs retain their declared behavior;
- `mov.b64` and `uint64_t` aliases retain identity;
- global store/reload, shared memory, and warp shuffle remain covered.

Add collapse tests with long arithmetic-only chains and IR assertions proving
that adjacent pair operations no longer contain codec sequences.

Measure:

1. split/pack sequences per PTX instruction chain;
2. add/mul/div chain time without global traffic in the loop;
3. registers, occupancy, and spills;
4. HiGHS/cuPDLP residual and convergence behavior;
5. end-to-end sparse solver time.

The expected gain comes from removed codecs, not added precision.

