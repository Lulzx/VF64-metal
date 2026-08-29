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
The reproducible `resources --json` probe records public pipeline limits for
nine representative arithmetic, reduction, and GEMM kernels:
[`results/m3/2026-08-29-m4-pro-metal-resources.json`](../../results/m3/2026-08-29-m4-pro-metal-resources.json).
Every measured pipeline reports SIMD width 32, the full 1,024-thread
single-threadgroup limit, and zero static threadgroup memory.

Current status: **in progress**. The M4 Pro artifact is reproducible, but a
second Apple GPU generation and compiler register/spill evidence are still
required by the cross-device exit criterion.

The standalone source compiler now performs last-use allocation to the VF64
register file; its 96-operation dependency-chain regression uses two virtual
ISA registers. This is compiler/ISA residency evidence only. On this device,
public Metal pipeline reflection exposes SIMD width, maximum threads per
threadgroup, and static threadgroup memory, while the only public counter set is
`timestamp`. It exposes no physical-register, spill-byte, or resident-occupancy
measurement. AIR disassembly is intermediate representation, not physical GPU
ISA, so it is deliberately not used as a substitute. Those measurements and a
second Apple GPU generation remain part of the M3 exit.

## Exit criterion

Each mode has a frozen numerical contract and reproducible cross-device
benchmarks, including numerical error, materialization count, registers,
occupancy, spills, time, and device provenance.
