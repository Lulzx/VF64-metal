# Milestone status and evidence ledger

Date: 2026-08-29

No milestone is complete until its linked exit artifacts exist and reproduce.
The status labels below distinguish implemented source from exit evidence.

| Milestone | Status | Current evidence | Earliest blocking exit gap |
| --- | --- | --- | --- |
| M1 exact core | Complete | 31,599,360 level-1 GPU TestFloat result comparisons; zero mismatches; all core ops/modes; machine-readable provenance | none within documented result-bit boundary |
| M2 IEEE runtime | In progress | core flags, comparisons, remainder, round-to-integer, integer and f16/f32 format conversions pass TestFloat; NaN results match ARM-VFPv2 bitwise | freeze and document the complete runtime ABI |
| M3 precision modes | Research prototype | measured FP32-pair and integer add/mul kernels | frozen `fast48`, `wide48`, `ieee64` contracts and cross-device artifacts |
| M4 virtual ISA | Designed only | semantic scope documented | versioned machine-readable ISA and independent backend tests |
| M5 compiler integration | Designed only | CuMetal boundary and residency plan | source `double` lowering through each declared policy |
| M6 automatic precision | Proposed | policy shape documented | implemented selector, diagnostics, accuracy contract and speedup proof |
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
