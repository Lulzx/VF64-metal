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
local validation, M2/M4 TestFloat, benchmarks, and scientific workloads. A
manual self-hosted workflow declares M1, M2, M3, and M4 Apple GPU runner labels
and preserves each verification log.

An evidence-linked [technical report draft](../report/technical-report-draft.md)
summarizes the current architecture, methodology, results, and open gates. It
does not publish the embargoed final claim.

Workflow source is not CI evidence. No runner availability or successful
cross-generation run is claimed until public run artifacts exist. M3, M5, and
M7 exits also remain open, so tagging 1.0 and publishing the final claim are
premature.

## Exit criterion

All prior milestone exits remain reproducible from a tagged release.

Only then is the final claim supportable:

> **The first complete virtual FP64 architecture for Apple GPUs: correctly
> rounded IEEE-754 binary64, faster reduced-precision modes, a virtual FP64 ISA,
> and compiler-managed precision selection.**

“First” must be rechecked against the public landscape immediately before
publication. “Complete” refers only to the documented runtime and ISA surface.
