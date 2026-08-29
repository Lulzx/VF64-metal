# M8 — 1.0 and research claim

Release requirements:

- cross-generation device CI;
- reproducible benchmark and conformance corpora;
- stable API, virtual ISA, and storage ABI;
- a technical report;
- public operation-by-operation conformance data;
- explicit supported-device and unsupported-feature matrices.

## Current status

Status: **in progress; release infrastructure only**. The repository now has a
single [`scripts/verify-release.sh`](../../scripts/verify-release.sh) gate for
local validation, M2/M4 TestFloat, pipeline resources, benchmarks, synthetic and
checksum-pinned external scientific workloads. A manual self-hosted workflow
declares M1, M2, M3, and M4 Apple GPU runner labels, checks out the frozen
CuMetal integration commit, reruns all three compiler modes, and preserves both
verification logs. Each runner emits a privacy-scoped, checksum-bound
[device evidence manifest](../release/cross-generation-evidence.md); a separate
job rejects missing generations, mixed source revisions, incomplete mode or
release-component coverage, mislabeled chips, and altered logs before
publishing a cross-generation summary.

An evidence-linked [technical report](../report/technical-report.md) summarizes
the current architecture, methodology, results, and open gates. It does not
publish the embargoed final claim.

The dated [prior-art audit](../research/prior-art-2026-08-29.md) closes the
landscape-review task. It found earlier exact Metal arithmetic, a complete
portable binary64 runtime, and experimental source-level SYCL `double` lowering
to Metal. It found no inspected implementation of the complete three-mode
virtual ISA plus automatic-selection stack, but does not treat search absence
as proof of priority.

VF64 v1's compiler/backend boundary is published as a versioned
[C and standalone runner API/ABI](../release/api-abi.md) with compiled
layout/constants and machine-readable version gates. Its named linkable Metal
support entry points are also frozen. Internal Swift/Metal helpers and benchmark
commands are not declared stable.

The public [operation-by-operation conformance matrix](../../results/conformance/2026-08-29-m4-pro-operation-matrix.json)
reconciles all 26 runtime operations and 119 policy cells with the frozen M2
direct-runtime and M4 VF64-ISA runs. Its consistency check is part of release
verification. This closes the data-publication item, not the cross-generation
or release gates.

The [supported-device and feature matrix](../release/support-matrix.md) marks
only the measured M4 Pro as a development candidate, keeps unmeasured M1-M4
targets explicitly unvalidated, and records unsupported runtime, compiler, ISA,
and observability features. It must be regenerated from successful runner
artifacts before 1.0.

Workflow source is not CI evidence. No runner availability or successful
cross-generation run is claimed until public run artifacts exist. M3 and M7
exits also remain open, so tagging 1.0 and publishing the final claim are
premature.

As of 2026-08-29, the GitHub repository reports zero registered self-hosted
runners. Dispatching the workflow would only create indefinitely queued jobs,
so no run is presented as evidence.

## Exit criterion

All prior milestone exits remain reproducible from a tagged release.

Only then is this descriptive claim supportable:

> **A complete virtual FP64 architecture for Apple GPUs: correctly
> rounded IEEE-754 binary64, faster reduced-precision modes, a virtual FP64 ISA,
> and compiler-managed precision selection.**

“First” is not supported by the current bounded search and requires an
independent publication-time review if reintroduced. “Complete” refers only to
the documented runtime and ISA surface.
