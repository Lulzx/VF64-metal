# Cross-generation evidence contract

The manual Apple GPU release workflow runs the same checked-out VF64Metal and
pinned CuMetal revisions on M1, M2, M3, and M4 self-hosted runners. A passing
job emits one directory containing:

- `device-manifest.json` with non-sensitive chip, GPU, OS, workflow, source,
  release-component and precision-mode provenance;
- `release-verification.log` from the unified VF64Metal gate;
- `cumetal-integration.log` from all three CuMetal precision modes.

The manifest stores SHA-256 hashes for both logs. It intentionally excludes the
hardware serial number, platform UUID, provisioning identifier, and user data.

`scripts/check-cross-generation-evidence.sh` fails unless manifests describe at
least two distinct Apple GPU generations, share identical VF64Metal and CuMetal
commits, cover the named M1-through-M7 release-gate components and all three
precision modes, match their detected chip names, and retain unmodified logs.
Component coverage means the corresponding checks ran; it does not mark an
entire milestone complete. The release workflow uses the stricter
`--require=m1,m2,m3,m4` policy and publishes an aggregate JSON summary only
after all four runner jobs pass.

This mechanism defines evidence; it does not create evidence. The M3, M7, and
M8 cross-generation exits remain open until successful public workflow
artifacts exist.
