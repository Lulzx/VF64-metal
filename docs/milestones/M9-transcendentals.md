# M9 — Correctly rounded transcendental layer

Status: **P1 complete for `exp`; P2 (tranche A), P3 (tranche B), P4
(tranche C), P5 (surface reconciliation), and P6 (ISA and ABI decision)
complete.**

What exists: a wide evaluation core, a correctly rounded `exp`, a pinned MPFR
oracle, and one published campaign of 20,008,875 result and exception-flag
comparisons across five rounding modes with zero mismatches and zero
uncertified results
([artifact](../../results/m9/2026-09-20-apple-m4-pro-exp-level1.json)).
Tranche A adds `exp2`, `expm1`, `log`, `log2`, `log1p`, `cbrt`, and `hypot`,
each with its own published campaign (see
[Tranche A, as shipped](#tranche-a-as-shipped)). Tranche B adds `pow`,
`atan`, `atan2`, `asin`, and `acos`, likewise (see
[Tranche B, as shipped](#tranche-b-as-shipped)). Tranche C adds `sin`, `cos`,
`tan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, and `atanh`, likewise (see
[Tranche C, as shipped](#tranche-c-as-shipped)). No claim is made beyond what
each function's published proof-obligation state establishes.

M2 supplies the exact binary64 arithmetic core and deliberately stops there.
[`runtime/ieee64.md`](../runtime/ieee64.md) records that the runtime implements
no transcendental functions, [`isa/vf64-v1.md`](../isa/vf64-v1.md) records that
v1 has none by design, and the
[support matrix](../release/support-matrix.md) marks the whole family
unsupported with no contract in the runtime or ISA. Closing that gap changes
three frozen surfaces, so it is a separate milestone with its own exit
evidence rather than an extension of M2.

## Contract

Every function in this milestone is **correctly rounded**, in the sense the
[claim policy](../policies/claims.md) already fixes: every non-NaN result
matches the specified binary64 rounding mode, with separately specified NaN
behavior. IEEE-754-2019 clause 9.2 only *recommends* correct rounding for these
operations; this project chooses it because the rest of the `ieee64` stack is
defended that way, and a one-ulp library would be the first surface here whose
accuracy cannot be stated as a bound.

Per function, the milestone must publish before the function is claimed:

- the set of rounding modes the claim covers;
- the special-value table (±0, ±∞, subnormal argument and result, sNaN/qNaN,
  exactly representable arguments such as `exp(0)`, `log(1)`, `sin(0)`);
- the exception-flag behavior, using the M2 sticky-flag convention and the
  existing `thread uint &flags` calling pattern;
- its **proof obligation status**, defined below.

The certificate is part of the calling contract, not a debug aid.
`soft_exp64_certified` returns it by reference; `soft_exp64_status` folds it
into flag bit 5, a VF64 extension outside the five IEEE exceptions, so that a
caller using flags alone still cannot mistake an unproven result for a proven
one. Only the flag-free convenience wrappers discard it, under the same rule
M2 already applies to its own flag-free wrappers.

Reduced-precision transcendentals are out of scope. `fast48` and `wide48` have
no transcendental contract and must refuse rather than downgrade, matching M2's
existing rule that an unsupported exact operation may fail compilation or
dispatch, but must never silently use `fast48`.

Also out of scope: complex functions, decimal formats, binary32/binary16
transcendentals, and `errno`-style or trapping behavior.

## Proof obligation, and where the claim stops

This is the hard part of the milestone, not the coding.

M1 and M2 reach "correctly rounded" through near-exhaustive Berkeley TestFloat
campaigns over an argument space the generator covers well. No comparable
generator exists for transcendentals, and no test campaign can establish
"every result" for a function over the full binary64 domain. Each function
therefore lands in exactly one of three states, and the state is published with
the function:

1. **Proven.** The implementation's evaluation error is bounded below the
   distance to the rounding boundary for every argument in the domain, using a
   published hardest-to-round search for that function and range plus a checked
   error bound for the implementation itself. Only this state may be described
   as a correctly rounded operation without qualification.
2. **Bounded-domain proven.** The above holds on a stated sub-domain; outside
   it the function is either rejected or falls back to a path with its own
   stated status. The claim names the sub-domain.
3. **Certified per call**, the state for which the claim policy reserves the
   phrase "certified correctly rounded". The implementation carries its own
   evaluation error bound and, for each call, compares the distance from its
   computed value to the rounding boundary that decides the result against
   that bound. A result
   that clears the bound is correctly rounded, and the fact is established by
   that call rather than assumed from a table. A result that does not clear it
   is reported as uncertified rather than delivered as proven. This is what
   `exp` ships as. It does not establish that every argument in the domain
   certifies; it establishes that an argument which would not certify cannot
   be silently mis-rounded.
4. **Tested only.** Bitwise agreement with the reference oracle on the declared
   corpus, with no error bound and no certificate. This is *not* a
   correct-rounding claim under the claim policy and must be published as "no
   proven worst-case bound", the same way M1 refuses to claim flags it did not
   test.

No function ships in state 4 while its documentation implies state 1. If a
function cannot reach states 1 through 3, shipping it at all is a separate
decision, not a default.

State 3 is what makes P1 shippable without a hardest-to-round search: the
implementation cannot return a rounding it has not proven for that specific
argument. Reaching state 1 for `exp` still requires the search, and that is
open work, not a closed item.

## Method

### Internal evaluation format

Do not layer double-double arithmetic over `soft_add64` / `soft_mul64`. Each of
those already performs full unpacking, special-case handling, normalization,
and rounding, and every one of those steps is wasted inside a polynomial
evaluation whose intermediates are known-finite and never observed.

Instead evaluate in one normalized wide type — sign, integer exponent, and a
128-bit significand — built on the primitives that already exist in
[`Shaders/IEEE/Arithmetic.metal`](../../Sources/VF64Metal/Shaders/IEEE/Arithmetic.metal):
`soft_u128`, `soft_add128`, `soft_sub128`, `soft_shift_left128`, and the
128-bit product already formed inside `soft_mul64_status`. Round exactly once,
at the end, reusing `round_shift_u128_status` and the M2 multiply tail so that
rounding modes, subnormal handling, the overflow result, tininess after
rounding, and the flag convention are inherited rather than restated.

One case is owned rather than inherited. `round_shift_u128_status` treats every
discard distance of 128 or more as below the halfway point, which is correct
for its M2 callers, whose 128-bit operand is a product sitting low in the word,
and wrong for a wide significand normalized to bit 127, where a distance of
exactly 128 means the value is at or above halfway. M2 is unaffected; the wide
conversion handles that distance itself.

A portability note worth keeping: shifting a 64-bit limb by 64 is undefined,
and on this GPU it returns the operand unshifted rather than zero. That cost a
debugging cycle in P1 and silently injected a 2^-55 relative error that the
certification test did not catch, because a wrong value can still sit far from
a rounding boundary. Certification bounds evaluation error; it does not detect
a bug that changes the value being certified. The MPFR campaign is what caught
it, which is the argument for keeping both.

### Ziv strategy, bounded

Two steps were specified, never an unbounded loop. P1 shipped the wide step
only. That was an analysis decision, not a measured one, and it should be read
as such: the wide path is a fixed 30-term Horner evaluation with no
data-dependent control flow, so a fast path would add a branch and a
divergence cost to skip work that is already bounded and uniform. No cost
measurement exists for either arrangement yet. Tranches B and C also
shipped the wide step only, including `pow`'s 192-bit logarithm and the
trigonometric reduction, so the fast path stays open until a rate can be
measured on an idle host.

A kernel that cannot terminate is not shippable, so "keep widening until it
rounds" is not an option here.

### `exp`, as shipped

The reduction is a Cody-Waite split: `k = round(x / ln2)`, and `ln2_hi` carries
40 significant bits so that `k * ln2_hi` is exact in a 128-bit significand for
every reachable `|k| < 2^11`, and `x - k * ln2_hi` is exact as well, being a
multiple of 2^-54 below 2^11. Only the `k * ln2_lo` term is inexact, and it
contributes below 2^-155.

`exp(r)` is a 30-term Taylor sum by Horner in the wide format. The truncated
tail is below 2^-160 at `|r| <= ln2/2`, and the 60 truncating wide operations
contribute below 2^-121, so evaluation error stays under 2^-120. The
certification margin covers 2^-116, sixteen times the bound, so the margin is
not load-bearing on a tight analysis. Scaling by 2^k is an exponent
adjustment and is exact.

Three regions are decided in closed form rather than evaluated:

- `|x| < 2^-60`, where `exp(x)` lies strictly inside the interval between the
  binary64 neighbours of 1 and is never exactly 1 for nonzero `x`, so the
  result follows from the rounding mode and the sign of `x`. Without this the
  directed modes would be systematically uncertifiable across a whole region,
  since representing `1 + 2^-1074` needs more than 128 bits;
- `|x| >= 1024`, which overflows or falls below half the smallest subnormal;
- the binary64 special values.

Constants are generated by `tools/m9/generate-exp-constants.py` from an
arbitrary-precision computation, not transcribed.

### Tranche A, as shipped

Seven functions join `exp`, in all five rounding modes, with the same calling
convention: `soft_<name>_certified` returns the certificate by reference,
`soft_<name>_status` folds an uncertified result into flag bit 5, and the
flag-free forms discard both.

| Function | Method | Error bound | Proof-obligation state |
| --- | --- | --- | --- |
| `exp2` | `k = round(x)`, `r = x - k` exact, `exp(r ln2)` on the `exp` polynomial | 2^-119.9 | 3, certified per call |
| `expm1` | direct series `x * sum x^n/(n+1)!` for \|x\| < 1/2; `exp(x) - 1` above | 2^-118.6 | 3, certified per call |
| `log` | `x = m 2^e`, `m` in [sqrt2/2, sqrt2), `2 atanh((m-1)/(m+1))` + `e ln2` | 2^-121 | 3, certified per call |
| `log2` | as `log`, scaled by 1/ln2, plus `e` | 2^-121 | 3, certified per call |
| `log1p` | `u = 1 + x` (exact below 2^75), then as `log`, with `m - 1 = x` exactly when `e = 0` | 2^-121 | 3, certified per call |
| `cbrt` | integer `R = floor(cbrt(N 2^108))`, confirmed by exact 256-bit cubes | exact decision | 1, proven |
| `hypot` | integer `R = floor(sqrt(4S))` for the exact `S = x^2 + y^2`, confirmed by exact 256-bit squares | exact decision | 1, proven |

The bounds are derived in the shader sources: `Shaders/Math/ExpVariants.metal`,
`Shaders/Math/Log.metal`, and `Shaders/Math/Algebraic.metal`. Each certified
bound sits at least 5x inside the 2^-116 certification margin. The log family
divides through a new wide reciprocal, three Newton steps from an FP32 seed
with relative error below 2^-125. Its constants come from
`tools/m9/generate-log-constants.py`, truncated exactly like the `exp`
constants.

`cbrt` and `hypot` reach state 1 without a hardest-to-round search, because
they are algebraic. Wide arithmetic only guesses an integer root `R`, and
exact integer arithmetic then confirms `R^k <= T < (R+1)^k`. `R` has at least
54 bits, so every binary64 rounding boundary is a whole number of units of
`R`, and `R` plus a sticky bit for an inexact root rounds exactly as the true
root does. That includes the real ties `hypot` reaches: an odd 54-bit
hypotenuse of two 53-bit legs is exactly halfway between two binary64 values.
A guess the bounded correction cannot confirm would be reported uncertified;
none was.

Exact results are decided in closed form in every certified function, because
a value on the binary64 grid cannot be certified in a directed mode:
`exp2(k)` for integer `k` (including the one exact midpoint, `exp2(-1075)`),
`log(1)`, `log2(2^e)`, and the zero arguments. Results within 2^-60 relative
of a binary64 value are also decided in closed form, as for `exp`: `expm1`
and `log1p` near zero, `expm1` below -45, and `hypot` when the exponent gap
exceeds 30.

Each function's campaign ran 4,000,000 seeded random arguments per rounding
mode plus its boundary corpus, in all five modes, at source commit `d10ab14`
against MPFR 4.2.2. Every campaign had zero mismatches in result bits and
flags, and zero uncertified results:

| Function | Comparisons | Evidence |
| --- | ---: | --- |
| `cbrt` | 20,111,100 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-cbrt-level1.json) |
| `exp2` | 20,016,930 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-exp2-level1.json) |
| `expm1` | 20,005,650 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-expm1-level1.json) |
| `hypot` | 20,008,600 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-hypot-level1.json) |
| `log` | 20,018,410 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-log-level1.json) |
| `log1p` | 20,002,730 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-log1p-level1.json) |
| `log2` | 20,018,410 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-log2-level1.json) |

The same run re-executed `exp` after its polynomial and tiny-argument code was
factored out for reuse, and it reproduced the published 20,008,875 comparisons
with zero mismatches
([artifact](../../results/m9/2026-10-05-apple-m4-pro-exp-level1.json)).

Two lessons from tranche A:

- The GPU found an oracle bug. The first ties-away campaign for `exp2`
  disagreed at `x = -1075`. The kernel returned the smallest subnormal, which
  is correct, because 2^-1075 is exactly halfway between it and zero. The
  oracle returned zero: its 256-bit midpoint test ran inside the binary64
  exponent range, where 2^-1075 underflows. The test now widens MPFR's
  exponent range. This is the converse of P1's lesson, where MPFR caught a
  kernel bug: neither side is trusted alone.
- The 64-bit shift hazard recurred. `soft_shift_left128` serves distances
  below 64 only, and placing a 54-bit root at bit 127 needs up to 74.
  `Algebraic.metal` adds a full-range shift instead of relying on the old one.

### Tranche B, as shipped

Five functions, with the same calling convention and all five rounding modes.
`atan2` and `pow` take two operands, through the same binary kernel entry
points as `hypot`.

| Function | Method | Error bound | Proof-obligation state |
| --- | --- | --- | --- |
| `atan` | `atan(c) + atan((w-c)/(1+wc))`, `c = j/16` tabulated, 14-term odd series at \|t\| <= 1/32; `pi/2 - atan(1/w)` above 1 | 2^-120 | 3, certified per call |
| `atan2` | `atan` of the wide quotient of the smaller over the larger magnitude, then quadrant by `pi/2` and `pi` | 2^-120 | 3, certified per call |
| `asin` | `atan(x / sqrt((1-x)(1+x)))`, the factors exact | 2^-120 | 3, certified per call |
| `acos` | `atan(sqrt((1-x)(1+x)) / x)`, `pi - ...` for x < 0 | 2^-120 | 3, certified per call |
| `pow` | `2^(y log2 x)`: `log2` of the reduced argument in a 192-bit format, `y e` exact, `exp2` on the `exp` polynomial; exact cases in integers | 2^-119.8 | 3, certified per call; exact cases decided exactly |

The bounds are derived in `Shaders/Math/Atan.metal` and
`Shaders/Math/Pow.metal`; constants come from
`tools/m9/generate-atan-constants.py` and
`tools/m9/generate-pow-constants.py`.

`pow` is the first function that needs more than 128 bits. `y log2 x` turns a
relative error in `log2 m` into an absolute error in the exponent `z` that is
amplified by up to `|z| < 2^11`, so a 128-bit `log2` would leave only about
2^-117 against the 2^-116 margin. `Shaders/Math/Wide3.metal` adds a 192-bit
truncating format (multiply, add, Newton reciprocal) used only for
`log2 m`, which comes out within 2^-186. The rest of `pow` stays on the 128-bit
core.

`pow` is also not transcendental everywhere. With `x = X 2^E`, `X` odd, and
`y = n / 2^k`, `x^y` is a dyadic rational exactly when `X` is a perfect
`2^k`-th power and `2^k` divides `E`, which needs `k <= 5` once `X > 1`, and
`y > 0`. Those cases, and powers of two raised to any `y` with `E y` an
integer, are computed in integers and rounded exactly, including the real
midpoints they reach (`pow(x, 2)` of a 27-bit odd `x`, for example). Every
other result is irrational or not dyadic, so it is neither representable nor a
midpoint, and certification applies. Special values follow IEEE 754-2019
9.2.1; a signaling NaN raises invalid and propagates even in `pow(sNaN, 0)`
and `pow(1, sNaN)`, where a quiet NaN would give 1.

Closed forms cover the results within half an ulp of a known value: `atan`
and `asin` for \|x\| < 2^-27, where the cubic offset is below half an ulp;
`pow` when \|y log2 x\| < 2^-60; and `atan2` for x > 0 with \|y/x\| < 2^-55,
where the exact quotient is rounded by exact integer division because
`atan(q)` lies strictly between `q` and the next boundary toward zero.
Results beyond the overflow and underflow thresholds are decided directly.

Each campaign ran 4,000,000 seeded random arguments per rounding mode plus its
boundary corpus, in all five modes, at source commit `78f03f0` against MPFR
4.2.2. Each had zero mismatches in result bits and flags and zero uncertified
results:

| Function | Comparisons | Evidence |
| --- | ---: | --- |
| `acos` | 20,002,170 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-acos-level1.json) |
| `asin` | 20,002,170 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-asin-level1.json) |
| `atan` | 20,004,455 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-atan-level1.json) |
| `atan2` | 20,010,315 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-atan2-level1.json) |
| `pow` | 20,066,670 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-pow-level1.json) |

The `pow` corpus is stratified for the cases that break implementations: `x`
within 2^-13 of 1 with \|y\| up to 2^60, integer `y`, perfect squares and
fourth powers with dyadic `y`, `y log2 x` at the overflow and underflow
thresholds, and powers of two across the whole exponent range. Two mutation
checks confirm the corpus reaches the exact paths: disabling `pow`'s exact
cases, or the exact-division adjustment in `atan2`'s small-quotient path,
makes the campaign fail.

One lesson from tranche B: certification is a statement about distance to
rounding boundaries, so a stand-in value has to stay away from them too. The
first `pow` overflow path saturated to exactly `2^4096`, which is on the grid,
and the directed modes reported it uncertified although the delivered result
was right. It now saturates to `(1.5 + 2^-65) 2^4096`, off every boundary.

### Tranche C, as shipped

Nine functions, with the same calling convention and all five rounding modes.

| Function | Method | Error bound | Proof-obligation state |
| --- | --- | --- | --- |
| `sin`, `cos` | Payne-Hanek to `r = x - q pi/2`, \|r\| <= pi/4, then 16- and 17-term Taylor sums in `r^2` | 2^-124.3 | 3, certified per call |
| `tan` | `sin r / cos r`, or `-cos r / sin r` for odd `q` | 2^-122.8 | 3, certified per call |
| `sinh` | 14-term odd series for \|x\| < 1/2; `(E - 1/E) / 2`, `E = exp(\|x\|)`, above | 2^-118.8 | 3, certified per call |
| `cosh` | `(E + 1/E) / 2` | 2^-119.9 | 3, certified per call |
| `tanh` | `E / (E + 2)`, `E = expm1(2\|x\|)`, for \|x\| < 1/4; `(e - 1) / (e + 1)`, `e = exp(2\|x\|)`, above | 2^-119 | 3, certified per call |
| `asinh` | `log1p(\|x\| + x^2 / (1 + sqrt(1 + x^2)))` | 2^-120.5 | 3, certified per call |
| `acosh` | `log1p(d + sqrt(d (x + 1)))`, `d = x - 1` exact | 2^-120.5 | 3, certified per call |
| `atanh` | `log1p(2\|x\| / (1 - \|x\|)) / 2`, `1 - \|x\|` exact | 2^-120.5 | 3, certified per call |

The bounds are derived in `Shaders/Math/Trig.metal` and
`Shaders/Math/Hyperbolic.metal`; the trigonometric constants come from
`tools/m9/generate-trig-constants.py`. The hyperbolic family reuses the `exp`
polynomial, the `expm1` series, and the `log` reduction, and adds a `log1p`
for a wide argument. Every argument of `log1p` is built from positive terms
only, so none of the inverse functions cancels, and a relative error in that
argument passes into the result at most one to one.

Payne-Hanek reduction multiplies the 53-bit significand by five 64-bit words
of 2/pi, chosen by the argument's exponent from a 20-word (1280-bit, 160-byte)
table in the `constant` address space. Every word before the five contributes
a multiple of 4 to `x 2/pi`, so it cannot change the quadrant or the fraction.
The 384-bit product is exact, and the words left out after the five cost under
2^-202 absolute. The error bound is relative, so it needs a floor on \|r\|.
The generator supplies one: a continued-fraction search over every binary64
exponent shows that `x 2/pi` is never within 2^-61.5 of an integer for
`x >= pi/4`, so \|r\| > 2^-60.9. The closest argument, 6381956970095103 2^797,
is the one in the published worst-case literature. The omitted words therefore
cost under 2^-140.5 relative, and `r` is within 2^-125.4. The search also
writes the 3069 arguments closest to a multiple of pi/2, one or more per
exponent, into `tools/m9/trig_worst_cases.h`, which the oracle's reduction-stress
corpus uses.

Closed forms:

- \|x\| < 2^-27, nonzero: `sin`, `tan`, `sinh`, `tanh`, `asinh`, and `atanh`
  lie within x^2/3 of `x` on a known side, and `cos` and `cosh` lie within
  2^-55 of 1 on a known side.
- `tanh` for \|x\| >= 22, which lies within 2^-62 of ±1.
- A cosine branch after reduction with \|r\| < 2^-27, where the result lies
  strictly between ±(1 - 2^-55) and ±1. The hardest arguments put `cos r`
  within 2^-122.8 of 1, inside the 2^-116 certification margin, so it could
  never be certified in a directed mode, although the delivered result was
  already right.
- `acosh(1) = 0`, the poles `atanh(±1)` (divide-by-zero), and the domain
  errors.

`sinh` and `cosh` at \|x\| >= 1024 overflow by range. The wide format cannot
overflow, so below that the final rounding delivers overflow. No other result
of a nonzero argument is representable or a midpoint, by
Lindemann-Weierstrass.

Each campaign ran 4,000,000 seeded random arguments per rounding mode plus its
boundary corpus, in all five modes, at source commit `1c84069` against MPFR
4.2.2. Each had zero mismatches in result bits and flags and zero uncertified
results:

| Function | Comparisons | Evidence |
| --- | ---: | --- |
| `acosh` | 20,008,075 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-acosh-level1.json) |
| `asinh` | 20,008,075 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-asinh-level1.json) |
| `atanh` | 20,008,075 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-atanh-level1.json) |
| `cos` | 20,030,030 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-cos-level1.json) |
| `cosh` | 20,003,895 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-cosh-level1.json) |
| `sin` | 20,030,030 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-sin-level1.json) |
| `sinh` | 20,003,895 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-sinh-level1.json) |
| `tan` | 20,030,030 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-tan-level1.json) |
| `tanh` | 20,003,895 | [artifact](../../results/m9/2026-10-05-apple-m4-pro-tanh-level1.json) |

The trigonometric corpus is stratified for reduction: arguments within 1024
ulps of `k pi/2` for `k < 2^20`, the 3069 hardest-to-reduce arguments and
their neighbours, and every exponent through 2^1023. The hyperbolic corpora
cover the series and closed-form thresholds, the overflow threshold near
710.48, and arguments near 1 for `acosh` and `atanh`. The closed form for a
cosine branch is reached: without it, the boundary corpus alone has
uncertified `sin` and `cos` results in the directed modes, at those hardest
arguments.

Two lessons from tranche C:

- The shared core had a carry bug. `soft_wide_add` detected a carry out of
  bit 127 by comparing high limbs only, so it lost the carry when both high
  limbs were all ones and the low limbs carried into them. The sum then came
  out half its true value. `acosh` at x = 2^65 reached it: there `d =
  2^65 - 1` and `sqrt(d (x + 1))` is just below 2^65. Every function shares the
  adder, but no tranche A or B corpus had produced two such significands in
  one addition. The fix compares all 128 bits.
  After it, all thirteen tranche A, tranche B, and `exp` campaigns were re-run
  at `1c84069` and reproduced their published comparison counts with zero
  mismatches and zero uncertified results. The artifacts linked in the
  tranche A and B tables now record that commit; the original runs at
  `d10ab14` and `78f03f0` remain in the history of commits `20e03e1` and
  `d3f679e`.
- Certification can fail on the reduction side as well. The hardest
  arguments reduce correctly, with \|r\| near 2^-61. But `cos r` is then
  within 2^-122.8 of 1, inside the 2^-116 margin, and a correct result was
  reported uncertified. That is the tranche B lesson again: a value pinned near
  a rounding boundary by the mathematics needs a closed form, not a tighter
  bound.

### Argument reduction

`exp` as shipped needs no table: Cody-Waite plus a Taylor sum keeps the
reduction local. A table-driven variant, which shortens the series by
splitting the reduction further, was not needed to meet the error budget and
was not built. The `log` family uses a `sqrt2`-centred split and an `atanh`
series instead. The trigonometric family uses Payne-Hanek against 1280 bits of
2/π (see [Tranche C, as shipped](#tranche-c-as-shipped)), a 160-byte table in
the `constant` address space. M3 already has labeled Metal trace evidence
showing interpreter-only 560-byte compiler spill events; the table's register
and spill consequences have not been measured, and the public Metal interfaces
on M4 Pro do not expose spill bytes (see the
[support matrix](../release/support-matrix.md)), so none is claimed.

### Cost, stated up front

One correctly rounded transcendental evaluation will cost hundreds to low
thousands of integer operations per lane, and a Ziv fallback taken by one lane
is paid by its whole SIMD group. This layer is an accuracy path, not a
throughput path. Fallback rate and divergence must be reported. Per the claim
policy, a microkernel evaluation rate is not an application rate and must never
be published as one.

## Oracle and conformance

Berkeley TestFloat cannot gate this milestone: it has no transcendental
generators. The M9 gate is a new differential campaign against MPFR.

- `scripts/bootstrap-mpfr.sh` pins GMP and MPFR by exact version and checksum,
  the way [`bootstrap-testfloat.sh`](../../scripts/bootstrap-testfloat.sh)
  pins SoftFloat and TestFloat by commit.
- `scripts/run-mpfr-m9.sh` generates references at sufficient working precision
  and rounds them using MPFR's ternary value, so the reference is the correctly
  rounded result, not a high-precision approximation of it.
- Comparison is bitwise on results and on sticky flags, with an explicitly
  documented NaN comparison policy, matching M2 rather than M1.

Corpora, all seeded and recorded in the artifact:

1. uniform random over the full exponent range;
2. boundary-dense: overflow and underflow thresholds, subnormal arguments and
   results, signed zeros, infinities, quiet and signaling NaNs, and exactly
   representable cases;
3. published hardest-to-round arguments for each function and range;
4. reduction stress: near multiples of π/2 for the trigonometric family, near 1
   for `log`/`log1p`, near 0 for `expm1`, and near the `pow` special-case grid.

Artifacts follow the existing provenance rules — source hash, device, OS and
Metal version, command line, corpus seed, comparison counts, timestamp source —
and land in `results/m9/`.

## Upstream reuse

The correctly rounded binary64 landscape is not empty: CORE-MATH, its crlibm
predecessor, the RLIBM line of work, and the published hardest-to-round tables
from Lefèvre and Muller are the relevant upstreams. What is reusable here is
the *algorithm, table, and worst-case data*, not the code: every one of those
implementations assumes hardware binary64 with a hardware FMA, and the
evaluation kernel has to be retargeted onto the wide soft format regardless.

Two gates before any of it is used:

- license and provenance verified per upstream and recorded, not assumed;
- the [prior-art audit](../research/prior-art-2026-08-29.md) extended with a
  new dated section covering correctly rounded GPU transcendentals, before any
  claim of scope or novelty is made.

## ISA and ABI impact

VF64 v1 is frozen and states that new behavior requires a version or a declared
feature bit, and [`include/vf64/vf64.h`](../../include/vf64/vf64.h) is a frozen
public surface checked by `check-vf64-abi.sh`.

- **Option A, recommended for the first tranche.** Metal source-level functions
  only — `soft_exp64_status` and siblings, following the M2 naming and
  signature convention. No new opcodes, no ABI change, no version bump.
  `vf64-compile` fails closed on transcendental source constructs. CuMetal
  does not: as of CuMetal `f4bbc8a`, its PTX lowering evaluates the libdevice
  double transcendentals (`__nv_exp`, `__nv_sin`, `__nv_pow`, and the rest)
  through binary32 `air.fast_*` calls in every fp64 mode, `ieee64` included.
  CuMetal documents this in its `docs/fp64-policy.md` and records a module
  caveat, but the caveat reaches only a comment in the generated MSL, and the
  call is not refused. The precision-mode contract forbids that downgrade, so
  this is an open CuMetal gap, not an M9 surface.
- **Option B, deferred.** A `VF64_FEATURE_TRANSCENDENTAL` feature bit plus an
  opcode range, which is a VF64 v2 surface with its own ISA JSON, interpreter,
  ABI-freeze, and conformance work. Do not start this before Option A has
  published evidence for at least one function.

### P6 decision

**Option B is rejected for now. Option A stands, and the next surface step is
an additive extension of the linkable Metal support ABI, not the bytecode.**

The decision rests on who consumes each surface, because the cost P6 was meant
to weigh has still not been measured (see [Open questions](#open-questions)):

- **No bytecode consumer needs a transcendental opcode.** The VF64 v1 bytecode
  is reached through `vf64-compile`, `vf64-run`, and the TestFloat ISA
  harness. CuMetal, the only integration with a real demand for CUDA `double`
  transcendentals, lowers through the [linkable support
  module](../release/api-abi.md#linkable-metal-support-abi) by AIR static
  link and never executes VF64 bytecode. Opcodes would serve no caller that
  exists today.
- **Option B taxes every interpreted program.** The interpreter is one Metal
  function that dispatches every opcode. Twenty-two transcendentals in that
  dispatch put the wide 128- and 192-bit evaluation state, and the 160-byte
  2/π table, in the same function as straight-line `add` and `mul`. M3
  already has labeled trace evidence of interpreter-only 560-byte compiler
  spill events with today's 36 opcodes. Public Metal reflection cannot show
  what the larger function would cost (every pipeline here reports 1024
  maximum threads per threadgroup, and spill bytes are not exposed), so that
  risk cannot be bounded, and P6 does not take it on unmeasured.
- **Option B is a new major surface.** It needs a new version or a feature bit,
  a v2 ISA JSON, interpreter and validator changes, a C header change behind
  `check-vf64-abi.sh`, and a TestFloat-ISA-style conformance campaign per
  opcode. Nothing above would justify that cost yet.

The support ABI is where demand exists, and an addition there is additive:
existing symbols and their meaning do not change, the bytecode version and C
header are untouched, and a consumer built against a module without the new
symbols fails at `air-link` rather than silently falling back. The shape,
built after the decision:

- `vf64_<name>_rne(ulong ...)` and `vf64_<name>_round(ulong ..., uint
  rounding)` for each of the 22 functions, over raw binary64 bits, following
  the existing core-operation pair. The `_round` forms take the VF64 v1
  rounding encoding.
- Flag-free, like the rest of the support ABI, because CUDA exposes no
  per-thread IEEE status. That discards the certificate, so the support-ABI
  contract must be stated per proof state. `cbrt` and `hypot` are correctly
  rounded for every argument. The other twenty are correctly rounded wherever
  the certificate holds, which covers every one of the 440,402,485 published
  comparisons. Where it does not hold, the derived error bound (no worse than
  2^-116 relative) still places the delivered result on one of the two
  binary64 neighbours of the exact value, so it is faithfully rounded. That
  last statement follows from the bound alone. It is untested, because no
  campaign has produced an uncertified case.
- `scripts/build-vf64-support.sh` checks all 82 symbols, up from 38.
  `scripts/check-vf64-m9-support.sh`, part of the release gate, links
  conformance kernels that reach the 44 symbols only as unresolved externals,
  as CuMetal would. It then runs the pinned MPFR smoke vectors for all 22
  functions in five rounding modes through them and compares result bits.
  `VF64_M9_PATH=support scripts/run-mpfr-m9.sh` runs the full MPFR corpus
  through the same symbols and writes to `results/m9/support/`. That gates the
  support path directly, not by inference from the `soft_*_status` path. It
  compares result bits only, because this ABI returns no flags or
  certificate.

Reopen Option B only if a bytecode consumer appears that needs these
functions, and only after an idle-host cost capture and an interpreter-pressure
comparison exist.

## Phases

- **P1 — infrastructure and one function. Complete.** Wide evaluation format
  (`Shaders/Math/WideFloat.metal`), pinned MPFR oracle
  (`scripts/bootstrap-mpfr.sh`, then `tools/m9/exp_ref.c`, now
  `tools/m9/m9_ref.c`), stratified corpus
  generator, and `exp` (`Shaders/Math/Exp.metal`) in all five rounding modes
  rather than the one planned. Exit met: 20,008,875 comparisons, zero
  mismatches, zero uncertified, published artifact, proof-obligation state 3.
- **P2 — tranche A. Complete.** `exp2`, `expm1`, `log`, `log2`, `log1p`,
  `cbrt`, and `hypot` in all five rounding modes. The generalized oracle
  `tools/m9/m9_ref.c` replaces `exp_ref.c` and emits a byte-identical `exp`
  corpus. Exit met: 140,181,830 comparisons across the seven functions,
  zero mismatches, zero uncertified, one artifact per function. `cbrt` and
  `hypot` are proven (state 1); the other five are certified per call
  (state 3).
- **P3 — tranche B. Complete.** `pow`, `atan`, `atan2`, `asin`, and `acos`
  in all five rounding modes, with a 192-bit format for `pow`'s logarithm.
  Exit met: 100,085,780 comparisons across the five functions, zero
  mismatches, zero uncertified, one artifact per function. All five are
  certified per call (state 3); `pow`'s exact and midpoint results are
  decided exactly.
- **P4 — tranche C. Complete.** `sin`, `cos`, and `tan` with Payne-Hanek
  reduction over the whole binary64 domain, and `sinh`, `cosh`, `tanh`,
  `asinh`, `acosh`, and `atanh`, in all five rounding modes. Exit met:
  180,126,000 comparisons across the nine functions, zero mismatches, zero
  uncertified, one artifact per function. All nine are certified per call
  (state 3).
- **P5 — surface reconciliation. Complete.** The `ieee64` operation surface
  ([`runtime/ieee64.md`](../runtime/ieee64.md)) and the
  [support matrix](../release/support-matrix.md) list all 22 functions with
  their proof states. The [conformance guide](../conformance/testfloat.md)
  documents the MPFR campaign. The
  [precision-mode contracts](../runtime/precision-modes.md#transcendental-functions)
  state that `fast48` and `wide48` refuse. `vf64-compile` now rejects every M9
  name in all four `--fp64` modes with a dedicated diagnostic, gated by
  `check-cli-api.sh`. The checked
  [M9 function matrix](../../results/conformance/2026-10-05-m4-pro-m9-function-matrix.json)
  (22 functions, 110 policy cells, 440,402,485 comparisons) is reconciled row
  by row against the per-function artifacts by `check-conformance-data.sh`.
  CuMetal is not reconciled: it still evaluates CUDA double transcendentals
  at binary32 precision in every mode (see
  [ISA and ABI impact](#isa-and-abi-impact)). That fed into P6 and is not a
  P5 exit.
- **P6 — ISA and ABI decision. Complete.** Option B is rejected for now on
  consumer and interpreter-pressure grounds, without a measured cost, which
  still does not exist. The decision's follow-on, additive
  `vf64_<name>_rne` and `vf64_<name>_round` support-ABI symbols for CuMetal,
  is built and gated (see [P6 decision](#p6-decision)).

## Open questions

Settled by P1:

- **Wide format width.** 128-bit. The error budget lands at 2^-120 against a
  certification margin at 2^-116, so 192 bits buys nothing for `exp`.
  (Tranche B reopened it for one step only: `pow`'s logarithm is 192-bit.
  Tranche C did not: Payne-Hanek forms a 384-bit fixed-point product and
  keeps 128 bits of the fraction, which leaves `r` within 2^-125.4.)
- **Ziv fast path.** Not used for `exp`, by analysis rather than measurement
  (see above). Open, and worth measuring properly, in later tranches.
- **Proof-obligation states.** Four states, with state 3 added because P1
  showed a per-call certificate is both implementable and stronger than a
  tested-only claim. The [claim policy](../policies/claims.md) now reserves
  "certified correctly rounded" for that form and records that it is weaker
  than the whole-domain phrase.

Settled by P2:

- **Proof state per function in tranche A.** `cbrt` and `hypot` are state 1
  in all five modes, by an exact rounding decision. `exp2`, `expm1`, `log`,
  `log2`, and `log1p` are state 3 in all five modes. Algebraic functions need
  no worst-case search, so tranche B's `pow`, which is transcendental in
  general but algebraic on some subdomains, should split its claim the same
  way.

Settled by P3:

- **Proof state per function in tranche B.** All five are state 3. `pow`
  splits its claim as P2 predicted: the rational results it can reach are
  decided exactly, and only the irrational or non-dyadic remainder relies on
  the per-call certificate.

Settled by P4:

- **Proof state per function in tranche C.** All nine are state 3. None is
  algebraic on any subdomain beyond its zero and unit arguments, so there is
  no exact split like `pow`'s. The trigonometric reduction itself is proven
  over the whole domain: the continued-fraction bound on \|x mod pi/2\| is a
  closed computation, not a sample.

Still open:

- Whether any certified function should reach state 1 or 2, and whether a
  hardest-to-round search for `pow`, whose worst cases over two arguments are
  not known, is feasible at all.
- Whether a hardest-to-round search for `exp` is worth running to move it from
  state 3 to state 1, or whether the per-call certificate is the better
  permanent answer for a GPU runtime.
- What the delivered cost actually is. No phase from P1 to P4 published a
  rate. Tranches A, B, and C landed while the measurement host carried heavy
  unrelated CPU and GPU load, which made timings unreliable, so the measurement moves to an
  idle-host capture. The claim policy's rule still applies: a microkernel
  rate is not an application rate.

## Exit criterion

Unchanged by P1. A documented, correctly rounded binary64 transcendental
surface for Metal GPU compute, with per-function rounding-mode, special-value,
exception-flag, and proof-obligation status, gated by a reproducible MPFR
differential campaign with zero unexplained mismatches.

No function is claimed as correctly rounded beyond what its own published proof
obligation supports, and no transcendental result is presented as evidence for
`fast48` or `wide48`, which remain without a transcendental contract.
