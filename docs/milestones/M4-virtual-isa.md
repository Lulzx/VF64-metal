# M4 — Virtual FP64 ISA

Define a stable intermediate ISA covering:

- arithmetic and rounding;
- conversions and comparisons;
- exception state;
- vector operations;
- storage ABI and observable bit boundaries.

The ISA describes semantics; a backend may implement an instruction using
pairs, integer software arithmetic, a reduction accumulator, or another proven
mechanism. Mode-specific instructions must not blur their contracts.

Version the ISA and provide machine-readable operation definitions plus
positive and negative conformance tests.

Status: **complete**. VF64 v1.0 is frozen in
[`isa/vf64-v1.md`](../isa/vf64-v1.md), with the
normative machine-readable table in
[`isa/vf64-v1.json`](../isa/vf64-v1.json). The standalone Metal interpreter
executes binary program/input files without a source frontend. Its full
`ieee64` surface passed 31,982,976 level-1 TestFloat result/flag comparisons;
the directed suite covers all 36 opcodes, all three precision modes, sticky
flags, vector/storage operations, and negative validation.

Machine-readable exit evidence:
[`results/m4/2026-08-29-m4-pro-vf64-v1-level1.json`](../../results/m4/2026-08-29-m4-pro-vf64-v1-level1.json).

## Exit criterion

The Metal backend executes the complete virtual ISA independently of source
language.

Exit: **met** for VF64 v1.0 and its declared feature boundary.
