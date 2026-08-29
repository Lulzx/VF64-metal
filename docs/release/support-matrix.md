# Supported-device and feature matrix

Date: 2026-08-29  
Release status: pre-1.0

This matrix separates build intent from measured support. A device is not a
validated release target merely because SwiftPM accepts its OS version or Metal
can compile the shaders.

## Devices

| Platform | Build intent | Measured status | 1.0 status |
| --- | --- | --- | --- |
| Apple M4 Pro, 16-core GPU, macOS 26.7, Metal 4 | Yes | Full local release gate passes; all committed performance and workload measurements come from this device | Candidate; requires tagged-release reproduction |
| Other Apple M4 variants | Yes | Not measured | Unvalidated |
| Apple M3 family | Yes | Workflow target declared; no registered runner artifact | Unvalidated |
| Apple M2 family | Yes | Workflow target declared; no registered runner artifact | Unvalidated |
| Apple M1 family | Yes | Workflow target declared; no registered runner artifact | Unvalidated |
| Future Apple GPU generations | Not assumed | Not measured | Unsupported until independently validated |
| Intel Mac or AMD/Intel Mac GPU | No | Not measured | Unsupported; project targets Apple GPUs |
| iOS, iPadOS, tvOS, visionOS | No package target | Not measured | Unsupported |
| Non-Apple operating systems or GPUs | No | Host-only portable runner is not provided | Unsupported |

The package requires macOS 15 or newer and Swift 6. Those are compile-time
requirements, not evidence for every GPU shipped with those systems. The
cross-generation release workflow becomes support evidence only when its
checksum-bound public artifacts pass the
[aggregation contract](cross-generation-evidence.md).

## Numerical and execution features

| Surface | Status | Boundary |
| --- | --- | --- |
| Exact add/sub/mul/div/sqrt/true FMA | Implemented and TestFloat-gated | `ieee64`; five rounding modes |
| Conversions, comparisons, remainder, round-to-integer | Implemented and TestFloat-gated | Documented M2 operation set |
| Subnormals, infinities, signed zero, NaN/sNaN, tininess | Implemented and TestFloat-gated | ARM-VFPv2 NaN policy; tininess after rounding |
| Sticky IEEE exception flags | Implemented in VF64 bytecode | Per lane; not exposed by the linkable AIR support ABI or CuMetal source arithmetic |
| `fast48` | Implemented | Approximately 48 bits; binary32 finite range; nearest-even constituents; no IEEE flags |
| `wide48` | Implemented | Approximately 48 bits over binary64 finite range; nearest-even constituents; no IEEE flags |
| VF64 v1 vector execution | Implemented | One Metal thread per lane; 32 raw vector registers; slot-major storage |
| Source-level `double` | Implemented on declared surfaces | Straight-line VF64 language and CuMetal's tested CUDA/PTX subset; not a general C++, Swift, Fortran, or SYCL frontend |
| `--fp64=auto` | Implemented in standalone compiler | Profile and accuracy-bound selection; not integrated into CuMetal |
| Control flow and function calls in VF64 v1 | Unsupported | V1 is straight-line with `select` and `halt` only |
| Transcendental functions | Unsupported | No sin/cos/exp/log/pow contract in runtime or ISA |
| FP64 atomics | Unsupported | No atomic opcode or lock runtime |
| General BLAS, LAPACK, sparse, or solver API | Unsupported | Repository contains measured kernels and workload pilots, not a library-compatible API |
| Physical register, spill-byte, resident-occupancy counters | Unavailable | Public Metal interfaces inspected on M4 Pro do not expose them; no values are inferred |
| Energy results | Unavailable | Collection script requires authorized root `powermetrics`; no measurement has been published |

## ABI scope

VF64 v1 bytecode, the C serialization constants, standalone file/command
interfaces, named AIR support symbols, and observable eight-byte binary64
storage are the proposed stable 1.0 boundary. Internal Swift helpers, unnamed
Metal functions, benchmark commands, and result timings are not stable APIs.

The exact compatibility details are normative in the
[API/ABI contract](api-abi.md), [VF64 v1 specification](../isa/vf64-v1.md), and
[precision-mode contracts](../runtime/precision-modes.md).
