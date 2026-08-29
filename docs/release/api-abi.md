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

## Linkable Metal support ABI

Source-language backends can build `vf64-support.air` with
`scripts/build-vf64-support.sh`. The module exports 32 exact, unmangled
`vf64_*` symbols over raw IEEE binary64 bits: the six core operations in
round-to-nearest-even and explicit-rounding forms, remainder,
round-to-integer, six comparisons, all twelve conversions, and the two
rounding-independent widening conversions. Six `vf64_wide_*` symbols expose
the frozen `wide48` core-arithmetic contract with full binary64 input range,
for 38 support symbols in total.

Backends issue direct AIR calls and statically link the support module with
`air-link`; Metal visible-function-table calls are a different ABI and are not
used. The functions intentionally do not return exception flags because CUDA
source arithmetic has no exposed per-thread IEEE status register. VF64 bytecode
continues to provide the complete sticky-flag ABI.

The support ABI accepts rounding values from the VF64 v1 C ABI and returns
integer or raw-bit results. Storage remains ordinary eight-byte IEEE binary64
at every observable boundary. `scripts/check-vf64-support.sh` verifies all 38
symbols, performs an AIR static link, creates a Metal pipeline, and executes
arithmetic, comparison, and conversion probes on the GPU.

## Standalone runner API

`vf64-metal version --json` reports the tool and VF64 ABI versions without
creating a Metal device. VF64 ABI 1.0 stabilizes these standalone commands:

```text
vf64-compile --fp64=<fast48|wide48|ieee64|auto> --lanes=N ... SOURCE PROGRAM
vf64-profile --slots=N --lanes=N INPUT PROFILE
vf64-run PROGRAM INPUT OUTPUT FLAGS
```

The binary layouts of `PROGRAM`, `INPUT`, `OUTPUT`, and `FLAGS`, validation
rules, and exit convention (zero success, nonzero error) are part of this
compiler/backend API. Additive diagnostic text is not stable. New required
arguments, changed file layouts, or changed semantics require a new API/ABI
version. `scripts/check-cli-api.sh` freezes the machine-readable version
response and runs inside the release gate.

This stabilizes the VF64 compiler/backend C, standalone file/command API, named
linkable Metal support entry points, and CuMetal's mode-selection contract.
Internal Swift types, unnamed Metal helpers, and benchmark commands are not
stable for 1.0.
