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

Do not use a microkernel operation rate as application FLOP/s. Distinguish
source presence, validation, measured device execution, solver convergence, and
deployment into CuMetal.

The project north star is:

> Make numerical software written assuming `double` useful on Apple GPUs by
> letting users choose an explicit precision, range, and semantics contract,
> and prove each contract with reproducible numerical and application evidence.

