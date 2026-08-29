# M3 — High-performance precision modes

Stabilize three distinct contracts:

- `fast48`;
- `wide48`;
- `ieee64`.

Optimize pair residency, register use, packing boundaries, vector operations,
reductions, and explicitly named finite-only paths. Residency is performance
only and must not change a mode's accuracy/range claim.

`wide48` requires a frozen range and special-value contract before its physical
encoding becomes ABI. Candidate representations should first be tested against
real exponent-span traces.

## Exit criterion

Each mode has a frozen numerical contract and reproducible cross-device
benchmarks, including numerical error, materialization count, registers,
occupancy, spills, time, and device provenance.

