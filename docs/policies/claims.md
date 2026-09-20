# Numerical and performance claim policy

Reserve these phrases for distinct evidence:

- **Approximately 48-bit precision**: a measured error distribution within an
  explicitly documented range.
- **FP64-equivalent matrix accuracy**: a defined matrix error bound and
  adversarial tests; no implied scalar IEEE semantics.
- **Correctly rounded operation**: every non-NaN result matches the specified
  binary64 rounding mode, with separately specified NaN behavior. This is a
  whole-domain property and is established by argument, not by a campaign
  alone.
- **Certified correctly rounded**: each delivered result carries a per-call
  test showing that the distance from the computed value to the rounding
  boundary deciding that result exceeds the implementation's stated evaluation
  error bound, so that result is correctly rounded. A call that fails the test
  is reported as uncertified and never delivered as proven. This is weaker than
  the line above: it does not assert that every argument in the domain
  certifies, only that an argument which would not certify cannot be silently
  mis-rounded. The two phrases are not interchangeable, and the error bound and
  margin must be published with the function. The M9 `exp` layer is the current
  user of this phrase.
- **IEEE-754 binary64 compatible**: the full advertised operation surface,
  conversions, special values, rounding modes, and exception contract pass the
  declared conformance suite.
- **Fastest**: a public protocol and result artifact compare current
  alternatives on the same delivered hardware.
- **First**: an independently reviewable, dated prior-art search supports the
  exact combined scope. Never shorten a combined architecture claim into
  “first software FP64,” “first correctly rounded FP64,” or “first compiler
  lowering”; public implementations predate VF64Metal in each narrower area.

Do not use a microkernel operation rate as application FLOP/s. Distinguish
source presence, validation, measured device execution, solver convergence, and
deployment into CuMetal. Distinguish a per-call certificate from a whole-domain
proof, and distinguish both from bitwise agreement with an oracle over a
corpus.

A certificate bounds evaluation error; it does not detect a defect in the value
being certified. It is evidence alongside a differential campaign, never a
replacement for one.

The project north star is:

> Make numerical software written assuming `double` useful on Apple GPUs by
> letting users choose an explicit precision, range, and semantics contract,
> and prove each contract with reproducible numerical and application evidence.

The current [prior-art audit](../research/prior-art-2026-08-29.md) found no
inspected project with the whole three-mode ISA and automatic-selection stack,
but that bounded result does not prove universal priority. The publication-safe
claim omits “first.”
