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
| M5 compiler integration | Designed only | CuMetal boundary and residency plan | source `double` lowering through each declared policy |
| M6 automatic precision | Complete | profiled per-op selector; diagnostics; mixed fast48/wide48 region met 40-bit contract at 1.18x pure ieee64 | none within the declared VF64 accuracy-contract path |
| M7 workloads | Proposed | workload matrix documented | reproducible delivered-device workload corpus and CPU baselines |
| M8 1.0 | Not started | claim policy documented | all prior exits, cross-generation CI, stable release and public report |

## Evidence rules

- Host `Double` differential testing is a local smoke oracle, not Berkeley
  SoftFloat/TestFloat conformance.
- TestFloat result-only runs do not validate exception flags.
- The M1 artifact compares NaNs by class; current M2 validation compares NaN
  sign, quiet bit, and payload bitwise against ARM-VFPv2 SoftFloat.
- Pair microkernel measurements do not establish application acceleration.
- The final M8 claim remains embargoed until every row is complete.
