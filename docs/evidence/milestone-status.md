# Milestone status and evidence ledger

Date: 2026-08-29

No milestone is complete until its linked exit artifacts exist and reproduce.
The status labels below distinguish implemented source from exit evidence.

| Milestone | Status | Current evidence | Earliest blocking exit gap |
| --- | --- | --- | --- |
| M1 exact core | Complete | 31,599,360 level-1 GPU TestFloat result comparisons; zero mismatches; all core ops/modes; machine-readable provenance | none within documented result-bit boundary |
| M2 IEEE runtime | Complete | 31,982,976 level-1 TestFloat result/flag comparisons; exact floating NaN bits; documented source/storage/exception ABI | none within the documented M2 surface |
| M3 precision modes | In progress | frozen contracts; implemented wide48; M4 Pro accuracy/mode benchmarks; public pipeline limits; labeled Xcode trace with interpreter-only 560-byte compiler spill events; fail-closed performance-counter probe | second Apple GPU generation plus physical-register and resident-occupancy evidence; Xcode 26.6 advertises but does not emit the requested counter rows on M4 Pro |
| M4 virtual ISA | Complete | frozen VF64 v1 JSON/binary ABI; standalone Metal interpreter; 31,982,976 TestFloat comparisons through bytecode | none within VF64 v1's declared feature boundary |
| M5 compiler integration | Complete | CuMetal lowers unchanged CUDA `double` through fast48, wide48, and ieee64; arithmetic, conversions, comparisons, rounding, storage, shuffle, aliasing, cache, and provenance pass on M4 Pro | none within the declared source/PTX operation surface |
| M6 automatic precision | Complete | profiled per-op selector; diagnostics; mixed fast48/wide48 region met 40-bit contract at 1.18x pure ieee64 | none within the declared VF64 accuracy-contract path |
| M7 workloads | In progress | M4 Pro pilot covers CG, GMRES, synthetic and external CSR, GEMV/GEMM, structured LP, N-body, three-mode CuMetal CUDA, and unmodified HiGHS PDLP; GPU-selected CG/GMRES convergence matches 1.453e-12/2.712e-11 residuals without CPU iteration counts and now stops submission after the device selection (8.65x/6.26x relative A/B under host load, bitwise-identical results) (`wide48`/mixed `ieee64` HiGHS pass; `fast48` residual-parity failure documented) | energy and cross-device reproduction |
| M8 1.0 | In progress | claim policy, dated prior-art audit, explicit support/feature matrix, expanded release gate, self-hosted M1-M4 workflow with pinned CuMetal integration, stable public C/runner ABI, current technical report, and checked operation-by-operation conformance data | zero runners currently registered; successful public cross-generation runs, all prior exits, and stable release |
| M9 transcendentals | In progress | P1 through P6 closed: correctly rounded `exp`, `exp2`, `expm1`, `log`, `log2`, `log1p`, `cbrt`, `hypot`, `pow`, `atan`, `atan2`, `asin`, `acos`, `sin`, `cos`, `tan`, `sinh`, `cosh`, `tanh`, `asinh`, `acosh`, and `atanh` on Metal in five rounding modes; 440,402,485 MPFR result/flag comparisons across the twenty-two functions with zero mismatches and zero uncertified results; `cbrt` and `hypot` proven by exact rounding decision, the rest certified per call, with `pow`'s exact and midpoint results decided exactly and `sin`/`cos`/`tan` reduced over the whole binary64 domain; checked 22-function MPFR matrix and compiler refusal in every mode; P6 rejects transcendental opcodes for now; 44 additive `vf64_<name>_rne`/`_round` support-ABI symbols gated on the GPU by pinned MPFR smoke vectors | full-corpus support-ABI campaigns; CuMetal wiring to the new `vf64_<name>_rne`/`_round` symbols, since it still lowers CUDA double transcendentals to binary32 in every mode; an idle-host cost measurement; a hardest-to-round search, or an accepted certification state, for full-domain claims on the certified functions |

## Evidence rules

- Host `Double` differential testing is a local smoke oracle, not Berkeley
  SoftFloat/TestFloat conformance.
- TestFloat result-only runs do not validate exception flags.
- The M1 artifact compares NaNs by class; current M2 validation compares NaN
  sign, quiet bit, and payload bitwise against ARM-VFPv2 SoftFloat.
- Pair microkernel measurements do not establish application acceleration.
- M9 is not a 1.0 gate. Its row must not be read as blocking or extending M8.
- An M9 result is claimed correctly rounded only where the kernel certified it;
  the campaign fails rather than delivering an uncertified result as proven.
- The final M8 claim remains embargoed until every M1-M8 row is complete.
