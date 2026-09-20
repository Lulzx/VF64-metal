# M9 — Correctly rounded transcendental layer

Status: **P1 complete for `exp`; tranches A through C not started.**

What exists: a wide evaluation core, a correctly rounded `exp`, a pinned MPFR
oracle, and one published campaign of 20,008,875 result and exception-flag
comparisons across five rounding modes with zero mismatches and zero
uncertified results
([artifact](../../results/m9/2026-09-20-apple-m4-pro-exp-level1.json)).
Nothing beyond `exp` is implemented, and no claim is made beyond what the
per-call certification below establishes.

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
measurement exists for either arrangement yet. The fast path stays open for
tranches B and C, where the wide step is more expensive, and the question
should be settled there with numbers.

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

### Argument reduction

`exp` as shipped needs no table: Cody-Waite plus a Taylor sum keeps the
reduction local. A table-driven variant, which shortens the series by
splitting the reduction further, was not needed to meet the error budget and
was not built. The `log` family will need its own reduction study. The
trigonometric
family needs Payne-Hanek against roughly 1280 bits of 2/π for large arguments,
which puts a real constant table in the `constant` address space. M3 already
has labeled Metal trace evidence showing interpreter-only 560-byte compiler
spill events; table placement and its register and spill consequences must be
*measured* on device, not assumed.

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
  signature convention. No new opcodes, no ABI change, no version bump. The
  compiler and CuMetal paths fail closed on transcendental source constructs.
- **Option B, deferred.** A `VF64_FEATURE_TRANSCENDENTAL` feature bit plus an
  opcode range, which is a VF64 v2 surface with its own ISA JSON, interpreter,
  ABI-freeze, and conformance work. Do not start this before Option A has
  published evidence for at least one function.

## Phases

- **P1 — infrastructure and one function. Complete.** Wide evaluation format
  (`Shaders/Math/WideFloat.metal`), pinned MPFR oracle
  (`scripts/bootstrap-mpfr.sh`, `tools/m9/exp_ref.c`), stratified corpus
  generator, and `exp` (`Shaders/Math/Exp.metal`) in all five rounding modes
  rather than the one planned. Exit met: 20,008,875 comparisons, zero
  mismatches, zero uncertified, published artifact, proof-obligation state 3.
- **P2 — tranche A.** `exp2`, `expm1`, `log`, `log2`, `log1p`, `cbrt`, `hypot`
  — the functions needing no Payne-Hanek reduction — across every rounding mode
  the proof obligation supports.
- **P3 — tranche B.** `pow`, `atan`, `atan2`, `asin`, `acos`.
- **P4 — tranche C.** `sin`, `cos`, `tan` with Payne-Hanek, then the hyperbolic
  and inverse-hyperbolic family.
- **P5 — surface reconciliation.** Update the `ieee64` operation surface, the
  support matrix row, the conformance guide, the precision-mode contracts
  (reduced modes refuse), and the operation-matrix reconciliation checked by
  `check-conformance-data.sh`.
- **P6 — ISA and ABI decision.** Evaluate Option B against measured P1–P4 cost.

## Open questions

Settled by P1:

- **Wide format width.** 128-bit. The error budget lands at 2^-120 against a
  certification margin at 2^-116, so 192 bits buys nothing for `exp`. Tranche C
  may reopen this: Payne-Hanek reduction has a different budget.
- **Ziv fast path.** Not used for `exp`, by analysis rather than measurement
  (see above). Open, and worth measuring properly, in later tranches.
- **Proof-obligation states.** Four states, with state 3 added because P1
  showed a per-call certificate is both implementable and stronger than a
  tested-only claim. The [claim policy](../policies/claims.md) now reserves
  "certified correctly rounded" for that form and records that it is weaker
  than the whole-domain phrase.

Still open:

- Which rounding modes carry a published worst-case bound per function, and
  which functions consequently ship in state 1, 2, or 3.
- Whether a hardest-to-round search for `exp` is worth running to move it from
  state 3 to state 1, or whether the per-call certificate is the better
  permanent answer for a GPU runtime.
- What the delivered cost actually is. P1 published no rate for `exp` and no
  claim about it; measurement belongs with the tranche A work, under the claim
  policy's rule that a microkernel rate is not an application rate.

## Exit criterion

Unchanged by P1. A documented, correctly rounded binary64 transcendental
surface for Metal GPU compute, with per-function rounding-mode, special-value,
exception-flag, and proof-obligation status, gated by a reproducible MPFR
differential campaign with zero unexplained mismatches.

No function is claimed as correctly rounded beyond what its own published proof
obligation supports, and no transcendental result is presented as evidence for
`fast48` or `wide48`, which remain without a transcendental contract.
