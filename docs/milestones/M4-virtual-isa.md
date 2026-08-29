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

VF64 v1.0 is now frozen in [`isa/vf64-v1.md`](../isa/vf64-v1.md), with the
normative machine-readable table in
[`isa/vf64-v1.json`](../isa/vf64-v1.json). Backend execution and conformance
tests are the remaining M4 work.

## Exit criterion

The Metal backend executes the complete virtual ISA independently of source
language.
