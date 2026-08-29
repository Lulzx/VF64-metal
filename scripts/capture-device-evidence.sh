#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 5 ]]; then
    echo "usage: $0 OUTPUT_DIR GENERATION RELEASE_LOG CUMETAL_LOG CUMETAL_COMMIT" >&2
    exit 2
fi

output_dir=$1
generation=$(printf '%s' "$2" | tr '[:upper:]' '[:lower:]')
release_log=$3
cumetal_log=$4
cumetal_commit=$5

if [[ ! $generation =~ ^m[1-9][0-9]*$ ]]; then
    echo "invalid Apple GPU generation: $generation" >&2
    exit 2
fi
if [[ ! $cumetal_commit =~ ^[0-9a-f]{40}$ ]]; then
    echo "CuMetal commit must be a full lowercase SHA-1" >&2
    exit 2
fi
for log in "$release_log" "$cumetal_log"; do
    if [[ ! -s $log ]]; then
        echo "missing or empty verification log: $log" >&2
        exit 1
    fi
done
if ! grep -q '^release_verification=pass$' "$release_log"; then
    echo "release log does not contain the success sentinel" >&2
    exit 1
fi
if ! grep -q '^cumetal_vf64_integration=pass$' "$cumetal_log"; then
    echo "CuMetal log does not contain the success sentinel" >&2
    exit 1
fi
if ! grep -q "^cumetal_commit=$cumetal_commit$" "$cumetal_log"; then
    echo "CuMetal log does not match the pinned commit" >&2
    exit 1
fi
for mode in fast48 wide48 ieee64; do
    if ! grep -q "^cumetal_vf64_mode=$mode result=pass$" "$cumetal_log"; then
        echo "CuMetal log is missing passing mode: $mode" >&2
        exit 1
    fi
done

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
source_commit=$(git -C "$repo_dir" rev-parse HEAD)
if [[ -n ${GITHUB_SHA:-} && $source_commit != "$GITHUB_SHA" ]]; then
    echo "checked-out commit does not match GITHUB_SHA" >&2
    exit 1
fi

hardware_json=$(system_profiler SPHardwareDataType -json)
display_json=$(system_profiler SPDisplaysDataType -json)
chip=$(jq -er '.SPHardwareDataType[0].chip_type' <<<"$hardware_json")
machine_model=$(jq -er '.SPHardwareDataType[0].machine_model' <<<"$hardware_json")
gpu_name=$(jq -er '.SPDisplaysDataType[0].sppci_model // .SPDisplaysDataType[0]._name' <<<"$display_json")
gpu_cores=$(jq -er '.SPDisplaysDataType[0].sppci_cores | tonumber' <<<"$display_json")
metal_family=$(jq -er '.SPDisplaysDataType[0].spdisplays_mtlgpufamilysupport' <<<"$display_json")

expected_chip="M${generation#m}"
chip_upper=$(printf '%s' "$chip" | tr '[:lower:]' '[:upper:]')
expected_chip_upper=$(printf '%s' "$expected_chip" | tr '[:lower:]' '[:upper:]')
if [[ $chip_upper != *"$expected_chip_upper"* ]]; then
    echo "runner label $generation does not match detected chip $chip" >&2
    exit 1
fi

mkdir -p "$output_dir"
cp "$release_log" "$output_dir/release-verification.log"
cp "$cumetal_log" "$output_dir/cumetal-integration.log"
release_sha=$(shasum -a 256 "$output_dir/release-verification.log" | awk '{print $1}')
cumetal_sha=$(shasum -a 256 "$output_dir/cumetal-integration.log" | awk '{print $1}')

manifest_tmp="$output_dir/device-manifest.json.tmp"
jq -n \
    --arg generation "$generation" \
    --arg source_commit "$source_commit" \
    --arg cumetal_commit "$cumetal_commit" \
    --arg chip "$chip" \
    --arg machine_model "$machine_model" \
    --arg gpu_name "$gpu_name" \
    --argjson gpu_cores "$gpu_cores" \
    --arg metal_family "$metal_family" \
    --arg os_version "$(sw_vers -productVersion)" \
    --arg os_build "$(sw_vers -buildVersion)" \
    --arg repository "${GITHUB_REPOSITORY:-local}" \
    --arg workflow_run_id "${GITHUB_RUN_ID:-local}" \
    --arg workflow_run_attempt "${GITHUB_RUN_ATTEMPT:-local}" \
    --arg release_sha "$release_sha" \
    --arg cumetal_sha "$cumetal_sha" \
    '{
      schema_version: 1,
      kind: "vf64-apple-gpu-release-evidence",
      status: "pass",
      generation: $generation,
      source_commit: $source_commit,
      cumetal_commit: $cumetal_commit,
      workflow: {
        repository: $repository,
        run_id: $workflow_run_id,
        run_attempt: $workflow_run_attempt
      },
      device: {
        chip: $chip,
        machine_model: $machine_model,
        gpu_name: $gpu_name,
        gpu_cores: $gpu_cores,
        metal_family: $metal_family,
        os_version: $os_version,
        os_build: $os_build
      },
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
        release_verification: {
          file: "release-verification.log",
          sha256: $release_sha
        },
        cumetal_integration: {
          file: "cumetal-integration.log",
          sha256: $cumetal_sha
        }
      }
    }' >"$manifest_tmp"
mv "$manifest_tmp" "$output_dir/device-manifest.json"
jq . "$output_dir/device-manifest.json"
