# VF64 public API and ABI

VF64 v1.0 is the stable binary interface between source compilers and the
Metal virtual-FP64 backend. The normative machine-readable specification is
[`docs/isa/vf64-v1.json`](../isa/vf64-v1.json); the public C declaration is
[`include/vf64/vf64.h`](../../include/vf64/vf64.h).

The stable surface includes:

- magic and version `0x56463634` / `0x00010000`;
- 32-byte little-endian program headers and instructions;
- all 36 opcode values;
- rounding, exactness, precision-mode, and exception-bit encodings;
- slot-major 64-bit storage and 32-bit per-lane flag masks;
- a maximum of 32 VF64 registers and zero v1 feature bits.

Unknown versions, feature bits, opcodes, or reserved control bits fail
validation. Backward-compatible documentation corrections do not change the
version. Any layout, opcode meaning, storage encoding, or validation-rule change
requires a new VF64 version; new optional behavior requires a declared feature
bit or a new version.

The C header describes serialized fields, not native host structs to be copied
blindly on big-endian systems. VF64 files are always little-endian. Callers must
write/read explicit little-endian words when the host is not little-endian.

Run `scripts/check-vf64-abi.sh` to compile and execute the C layout/constants
gate. `scripts/verify-release.sh` includes this check before device validation.

This stabilizes the VF64 compiler/backend ABI. It does not declare the
standalone CLI, internal Swift types, Metal helper functions, or CuMetal
integration hooks stable for 1.0.
