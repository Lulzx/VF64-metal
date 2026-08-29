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

## Exit criterion

The Metal backend executes the complete virtual ISA independently of source
language.

