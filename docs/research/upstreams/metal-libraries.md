# Upstream Metal FP64 libraries

Date inspected: 2026-08-29

Snapshots:

- `philipturner/metal-float64` at
  [`01306dec`](https://github.com/philipturner/metal-float64/tree/01306dec8f44f4315ad018b2f7b24c162320ffeb),
  dated 2023-05-16.
- `zapccu/Metal64` at
  [`f8ab71d`](https://github.com/zapccu/Metal64/tree/f8ab71d7355fdc298a0e00810b343a83d3ae29a1),
  dated 2026-08-11.

## Comparison

| Dimension | VF64Metal | `metal-float64` | `Metal64` |
| --- | --- | --- | --- |
| Status | Runnable measured harness | README says planning stage | Header/package implementation |
| Fast representation | Normalized FP32 pair | Planned `float32x2_t` | `float2` high/low |
| Full-range path | Exact add/multiply prototype | Planned integer-backed types | None found |
| Basic arithmetic | add/sub/mul/div/FMA | Storage stubs | add/sub/mul/div/sqrt |
| Transcendentals | Not implemented | Planned | Broad real/complex surface |
| Validation | Directed/random GPU-host corpus | Resource-presence test | No automated test target found |
| Performance | GPU-timestamped M4 Pro results | Theoretical table | No benchmark evidence found |

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

