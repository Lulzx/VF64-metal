# VF64-metal

A virtual FP64 architecture for Apple Metal: correctly rounded software
binary64, faster reduced-precision modes, a virtual ISA, and compiler-managed
precision selection.

## Start here

- [Documentation index](docs/README.md)
- [Milestones M1-M8](docs/milestones/README.md)
- [Current milestone status](docs/evidence/milestone-status.md)
- [Reproducible results](results/summary.md)
- [Technical report draft](docs/report/technical-report-draft.md)

## Build and run

Requirements: macOS 15 or newer, Swift 6, and a Metal-capable Apple GPU.

```bash
swift build -c release
.build/release/vf64-metal validate
.build/release/vf64-metal bench
.build/release/vf64-metal all
scripts/verify-release.sh
```

The executable also provides `vf64-compile`, `vf64-profile`, and `vf64-run`.
See the [source compiler](docs/compiler/source-language.md) and
[public API/ABI](docs/release/api-abi.md) for their stable interfaces.
`resources --json` emits the public Metal pipeline-resource evidence used by
M3 without presenting threadgroup capacity as resident occupancy.

## Implementation

- [Swift and Metal runtime](Sources/VF64Metal/main.swift) - FP32-pair modes,
  exact IEEE-754 binary64, benchmarks, the VF64 backend, and workload drivers.
- [Public C ABI](include/vf64/vf64.h) - stable VF64 v1 constants and layouts.
- [VF64 ISA specification](docs/isa/vf64-v1.md) and
  [machine-readable schema](docs/isa/vf64-v1.json).
- [Example AXPY source](examples/axpy.vf64) and
  [automatic-precision profile](examples/axpy-profile.json).
- [ABI and AIR-link tests](tests/) for C layout and Metal support integration.

## Numerical contracts

- [`fast48`, `wide48`, and `ieee64`](docs/runtime/precision-modes.md)
- [Complete IEEE-754 binary64 runtime](docs/runtime/ieee64.md)
- [Precision-stack architecture](docs/architecture/precision-stack.md)
- [Apple Metal capability boundary](docs/platform/apple-metal-capabilities.md)
- [Claim and publication policy](docs/policies/claims.md)

`fast48` and `wide48` are reduced-precision modes, not binary64. Pair residency
is a performance optimization only. Observable storage remains eight-byte IEEE
binary64, while the exact `ieee64` path supplies correctly rounded operations,
IEEE special values, exception flags, and all rounding modes documented by the
runtime contract.

## Compiler and CuMetal integration

- [Source-language lowering](docs/compiler/source-language.md)
- [CuMetal integration index](docs/integration/README.md)
- [Representation](docs/integration/representation.md)
- [Materialization boundaries](docs/integration/boundaries.md)
- [`ieee64` mode](docs/integration/ieee64-mode.md)
- [Implementation phases](docs/integration/implementation-phases.md)
- [Verification](docs/integration/verification.md)

Both the standalone source compiler and CuMetal's CUDA/PTX lowering accept
source-level `double` under explicit `fast48`, `wide48`, or `ieee64` policies.
The standalone compiler additionally supports `auto` selection.

## Evidence

- [Measured M4 Pro baseline](docs/evidence/current-baseline.md)
- [Berkeley TestFloat method](docs/conformance/testfloat.md)
- [Operation-by-operation conformance data](results/conformance/)
- [Milestone evidence artifacts](results/)
- [Research notes and upstream survey](docs/research/README.md)
- [Remaining experiments](docs/roadmap/experiments.md)

M1, M2, M4, M5, and M6 are complete under their documented exit criteria.
M3, M7, and M8 remain open where cross-generation hardware, energy, or release
proof is still required. The
[status ledger](docs/evidence/milestone-status.md) is authoritative.

## Reproducibility scripts

- `bootstrap-testfloat.sh` - fetch and pin Berkeley SoftFloat/TestFloat.
- `run-testfloat-m1.sh`, `run-testfloat-m2.sh`, `run-testfloat-m4.sh` - exact
  arithmetic, complete-runtime, and ISA differential conformance.
- `build-vf64-support.sh`, `check-vf64-support.sh` - build and validate the
  linkable Metal support module.
- `check-vf64-abi.sh`, `check-cli-api.sh` - freeze public ABI/API surfaces.
- `check-cumetal-integration.sh` - verify all three CuMetal FP64 modes.
- `fetch-matrix-market.sh` - fetch the checksum-pinned external sparse corpus.
- `check-conformance-data.sh` - reconcile published conformance artifacts.
- `verify-release.sh` - run the consolidated local release gate.

## Release

- [M8 release criteria](docs/milestones/M8-release.md)
- [Public API and ABI](docs/release/api-abi.md)
- [Apple GPU release workflow](.github/workflows/apple-gpu-release.yml)

The 1.0 claim remains embargoed until every milestone exit is reproduced and
the public priority claim is rechecked.
