# Numerical and performance claim policy

Reserve these phrases for distinct evidence:

- **Approximately 48-bit precision**: a measured error distribution within an
  explicitly documented range.
- **FP64-equivalent matrix accuracy**: a defined matrix error bound and
  adversarial tests; no implied scalar IEEE semantics.
- **Correctly rounded operation**: every non-NaN result matches the specified
  binary64 rounding mode, with separately specified NaN behavior.
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
deployment into CuMetal.

The project north star is:

> Make numerical software written assuming `double` useful on Apple GPUs by
> letting users choose an explicit precision, range, and semantics contract,
> and prove each contract with reproducible numerical and application evidence.

The current [prior-art audit](../research/prior-art-2026-08-29.md) found no
inspected project with the whole three-mode ISA and automatic-selection stack,
but that bounded result does not prove universal priority. The publication-safe
claim omits “first.”
