# Upstream Metal FP64 libraries

Date inspected: 2026-08-29

Snapshots:

- `philipturner/metal-float64` at
  [`01306dec`](https://github.com/philipturner/metal-float64/tree/01306dec8f44f4315ad018b2f7b24c162320ffeb),
  dated 2023-05-16.
- `zapccu/Metal64` at
  [`f8ab71d`](https://github.com/zapccu/Metal64/tree/f8ab71d7355fdc298a0e00810b343a83d3ae29a1),
  dated 2026-08-11.
- `guyfischman/metal-softfloat` at
  [`8b6c592`](https://github.com/guyfischman/metal-softfloat/tree/8b6c592e2e383040fe2778bed8dda7904df284b1),
  dated 2026-05-08.
- `yocontra/soft-fp` release 2.0.1 at
  [`fd3b68a`](https://github.com/yocontra/soft-fp/tree/fd3b68a18552631ab29d501c8ceec6a72a3791e2),
  released 2026-08-12.
- `yocontra/AdaptiveCpp` Metal branch at
  [`456ae69`](https://github.com/yocontra/AdaptiveCpp/tree/456ae6910720810f5fe59f160e6707d46bb8e5f0),
  dated 2026-07-05.
- `yukiny0811/EmulatedDouble` at
  [`16283d1`](https://github.com/yukiny0811/EmulatedDouble/tree/16283d1055c41aaa7c4849c9ebfef4301e179d40),
  dated 2026-06-19.

## Comparison

| Dimension | VF64Metal | `metal-softfloat` | `soft-fp` + AdaptiveCpp Metal | `metal-float64` | `Metal64` / `EmulatedDouble` |
| --- | --- | --- | --- | --- | --- |
| Status | Runnable measured stack | Released Metal/Rust package | Released portable runtime; experimental Metal compiler branch | README says planning stage | Header/package implementations |
| Precision modes | `fast48`, `wide48`, `ieee64` | Exact plus unsafe unpacked fast path | Exact; optional FTZ compatibility ABI | Planned exact and FP32 pair | FP32-pair or word-backed manual APIs |
| Full IEEE runtime | Documented M2 surface and per-lane flags | Exact core subset; no flags | Portable runtime yes; Metal integration disables flags | No | No published complete contract |
| Source `double` lowering | Standalone frontend and CuMetal | No | Experimental SYCL lowering | Planned macro alias | No compiler pass |
| Virtual ISA / auto selection | VF64 v1 / implemented | No / no | No / no | No / no | No / no |
| Published validation | Direct GPU TestFloat result+flag corpus | Direct GPU TestFloat core corpus | TestFloat/MPFR portable corpus; small Metal integration test | Resource-presence test | Unit tests or no conformance target found |

The dated [publication-time audit](../prior-art-2026-08-29.md) records the
search method, source boundaries, and claim consequences. In particular,
`metal-softfloat` predates VF64Metal's exact Metal core, while `soft-fp` plus
AdaptiveCpp predates a complete portable runtime and source-level `double`
lowering to Metal.

## Lessons from `metal-float64`

Its strongest ideas are API and packaging decisions:

- redefine `double` and vector aliases at the MSL header boundary;
- separate small inline arithmetic from large dynamic-library functions;
- provide vectorized entry points to amortize calls and code size;
- make 64-bit atomics a distinct lock-based runtime facility;
- expose exact and reduced-precision types as different contracts.

The inspected revision is not a numerical competitor. Its
[`Double.h`](https://github.com/philipturner/metal-float64/blob/01306dec8f44f4315ad018b2f7b24c162320ffeb/Sources/MetalFloat64/include/MetalFloat64/Double.h)
contains storage-only declarations, and the Swift unit test merely checks that
compiled resources exist. VF64Metal should borrow ergonomics, not its theoretical
performance or unfinished conformance claims.

Lock-based atomics may matter for CUDA compatibility, but need forward-progress,
contention, aliasing, address-space, and device-safety tests first.

## Lessons from `Metal64`

`Metal64` supplies a useful API inventory:

- Swift conversions between `Double` and `SIMD2<Float32>`;
- MSL operators around an `f64` type;
- real arithmetic, roots, powers, exp/log, and trigonometry;
- `float4` complex arithmetic;
- CORDIC tables plus iterative and polynomial paths.

Every borrowed function still needs a written error contract, adversarial
differential tests, and Apple-GPU measurements.

Its inspected
[`f64fnc.h`](https://github.com/zapccu/Metal64/blob/f8ab71d7355fdc298a0e00810b343a83d3ae29a1/Sources/Metal64/include/f64fnc.h)
uses Dekker splitting with constant 4097, omits `lo*lo` in multiplication, and
uses one division correction. Its range remains constrained by FP32 limbs. It
is pseudo-double arithmetic, not a demonstrated 53-bit full-range binary64
runtime.

VF64Metal's own dependency-chain result favors explicit `fma()` residuals: the
full residual multiply was about 1.5 times the throughput of its Dekker variant
while retaining `lo*lo`. `Metal64` motivates a tested math/complex layer, not a
replacement core multiply.
