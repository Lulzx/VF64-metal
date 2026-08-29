# Milestone status and evidence ledger

Date: 2026-08-29

No milestone is complete until its linked exit artifacts exist and reproduce.
The status labels below distinguish implemented source from exit evidence.

| Milestone | Status | Current evidence | Earliest blocking exit gap |
| --- | --- | --- | --- |
| M1 exact core | Complete | 31,599,360 level-1 GPU TestFloat result comparisons; zero mismatches; all core ops/modes; machine-readable provenance | none within documented result-bit boundary |
| M2 IEEE runtime | Complete | 31,982,976 level-1 TestFloat result/flag comparisons; exact floating NaN bits; documented source/storage/exception ABI | none within the documented M2 surface |
| M3 precision modes | In progress | frozen contracts; implemented wide48; M4 Pro accuracy and mode benchmarks | second Apple GPU generation plus register/occupancy/spill evidence |
| M4 virtual ISA | Complete | frozen VF64 v1 JSON/binary ABI; standalone Metal interpreter; 31,982,976 TestFloat comparisons through bytecode | none within VF64 v1's declared feature boundary |
| M5 compiler integration | In progress | standalone typed frontend lowers arithmetic, comparisons, selection, and 12 conversions; all explicit policies execute on Metal | CuMetal source/PTX `double` integration and observable-boundary regressions |
| M6 automatic precision | Complete | profiled per-op selector; diagnostics; mixed fast48/wide48 region met 40-bit contract at 1.18x pure ieee64 | none within the declared VF64 accuracy-contract path |
| M7 workloads | In progress | M4 Pro pilot covers CG, GMRES, SpMV, GEMV, GEMM, batched 2D LP, multi-step N-body, plus the legacy CuMetal CUDA pair contract | VF64-integrated CuMetal CUDA path, energy, broader sparse/LP corpora, and cross-device reproduction |
| M8 1.0 | In progress | claim policy, unified release-verification script, and self-hosted M1-M4 workflow matrix | successful public cross-generation runs, all prior exits, stable release, and technical report |

## Evidence rules

- Host `Double` differential testing is a local smoke oracle, not Berkeley
  SoftFloat/TestFloat conformance.
- TestFloat result-only runs do not validate exception flags.
- The M1 artifact compares NaNs by class; current M2 validation compares NaN
  sign, quiet bit, and payload bitwise against ARM-VFPv2 SoftFloat.
- Pair microkernel measurements do not establish application acceleration.
- The final M8 claim remains embargoed until every row is complete.
