# M3 — High-performance precision modes

Stabilize three distinct contracts:

- `fast48`;
- `wide48`;
- `ieee64`.

Optimize pair residency, register use, packing boundaries, vector operations,
reductions, and explicitly named finite-only paths. Residency is performance
only and must not change a mode's accuracy/range claim.

The numerical and resident-layout contracts are frozen in
[`runtime/precision-modes.md`](../runtime/precision-modes.md). `wide48` now has
a scaled-pair implementation and full-range validation. Single-device accuracy
and throughput evidence is recorded in
[`results/m3/2026-08-29-m4-pro-modes.json`](../../results/m3/2026-08-29-m4-pro-modes.json).

Current status: **in progress**. The M4 Pro artifact is reproducible, but a
second Apple GPU generation and compiler register/spill evidence are still
required by the cross-device exit criterion.

## Exit criterion

Each mode has a frozen numerical contract and reproducible cross-device
benchmarks, including numerical error, materialization count, registers,
occupancy, spills, time, and device provenance.
