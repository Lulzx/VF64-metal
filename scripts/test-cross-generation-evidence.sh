#!/usr/bin/env bash
set -euo pipefail

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
test_dir=$(mktemp -d)
trap 'rm -rf -- "$test_dir"' EXIT

source_commit=1111111111111111111111111111111111111111
cumetal_commit=2222222222222222222222222222222222222222

make_fixture() {
    local generation=$1
    local chip=$2
    local directory="$test_dir/$generation"
    mkdir -p "$directory"
    printf 'release_verification=pass\n' >"$directory/release-verification.log"
    printf 'cumetal_integration=pass\n' >"$directory/cumetal-integration.log"
    local release_sha
    local cumetal_sha
    release_sha=$(shasum -a 256 "$directory/release-verification.log" | awk '{print $1}')
    cumetal_sha=$(shasum -a 256 "$directory/cumetal-integration.log" | awk '{print $1}')
    jq -n \
        --arg generation "$generation" \
        --arg chip "$chip" \
        --arg source_commit "$source_commit" \
        --arg cumetal_commit "$cumetal_commit" \
        --arg release_sha "$release_sha" \
        --arg cumetal_sha "$cumetal_sha" \
        '{
          schema_version: 1,
          kind: "vf64-apple-gpu-release-evidence",
          status: "pass",
          generation: $generation,
          source_commit: $source_commit,
          cumetal_commit: $cumetal_commit,
          device: {chip: $chip, gpu_cores: 16},
          covered_components: [
            "m1_exact_core",
            "m2_runtime",
            "m3_modes_resources",
            "m4_vf64_isa",
            "m5_source_lowering",
            "m6_auto_selection",
            "m7_workload_corpus",
            "cumetal_three_modes"
          ],
          verified_modes: ["fast48", "wide48", "ieee64"],
          logs: {
            release_verification: {file: "release-verification.log", sha256: $release_sha},
            cumetal_integration: {file: "cumetal-integration.log", sha256: $cumetal_sha}
          }
        }' >"$directory/device-manifest.json"
}

make_fixture m3 "Apple M3 Max"
make_fixture m4 "Apple M4 Pro"

"$script_dir/check-cross-generation-evidence.sh" --require=m3,m4 \
    "$test_dir/m3/device-manifest.json" \
    "$test_dir/m4/device-manifest.json" >/dev/null

printf 'tampered\n' >>"$test_dir/m3/release-verification.log"
if "$script_dir/check-cross-generation-evidence.sh" \
    "$test_dir/m3/device-manifest.json" \
    "$test_dir/m4/device-manifest.json" >/dev/null 2>&1; then
    echo "tampered evidence unexpectedly passed" >&2
    exit 1
fi

printf 'cross_generation_evidence_contract=pass\n'
