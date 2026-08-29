#!/usr/bin/env bash
set -eo pipefail

required_csv=""
if [[ ${1:-} == --require=* ]]; then
    required_csv=${1#--require=}
    shift
fi
if [[ $# -lt 2 ]]; then
    echo "usage: $0 [--require=m1,m2,...] MANIFEST MANIFEST [...]" >&2
    exit 2
fi

generation_names=()
generation_manifests=()
source_commit=""
cumetal_commit=""

for manifest in "$@"; do
    jq -e '
      .schema_version == 1 and
      .kind == "vf64-apple-gpu-release-evidence" and
      .status == "pass" and
      (.generation | test("^m[1-9][0-9]*$")) and
      (.source_commit | test("^[0-9a-f]{40}$")) and
      (.cumetal_commit | test("^[0-9a-f]{40}$")) and
      (.device.chip | type == "string" and length > 0) and
      (.device.gpu_cores | type == "number" and . > 0) and
      (["fast48", "wide48", "ieee64"] - .verified_modes | length == 0) and
      ([
        "m1_exact_core",
        "m2_runtime",
        "m3_modes_resources",
        "m4_vf64_isa",
        "m5_source_lowering",
        "m6_auto_selection",
        "m7_workload_corpus",
        "cumetal_three_modes"
      ] - .covered_components | length == 0) and
      (.logs.release_verification.sha256 | test("^[0-9a-f]{64}$")) and
      (.logs.cumetal_integration.sha256 | test("^[0-9a-f]{64}$"))
    ' "$manifest" >/dev/null

    generation=$(jq -er '.generation' "$manifest")
    for existing_generation in "${generation_names[@]}"; do
        if [[ $existing_generation == "$generation" ]]; then
            echo "duplicate generation manifest: $generation" >&2
            exit 1
        fi
    done
    generation_names+=("$generation")
    generation_manifests+=("$manifest")

    manifest_source=$(jq -er '.source_commit' "$manifest")
    manifest_cumetal=$(jq -er '.cumetal_commit' "$manifest")
    if [[ -z $source_commit ]]; then
        source_commit=$manifest_source
        cumetal_commit=$manifest_cumetal
    elif [[ $source_commit != "$manifest_source" || $cumetal_commit != "$manifest_cumetal" ]]; then
        echo "manifests do not share pinned VF64Metal and CuMetal commits" >&2
        exit 1
    fi

    expected_chip="M${generation#m}"
    chip=$(jq -er '.device.chip' "$manifest")
    chip_upper=$(printf '%s' "$chip" | tr '[:lower:]' '[:upper:]')
    expected_chip_upper=$(printf '%s' "$expected_chip" | tr '[:lower:]' '[:upper:]')
    if [[ $chip_upper != *"$expected_chip_upper"* ]]; then
        echo "manifest generation $generation does not match chip $chip" >&2
        exit 1
    fi

    manifest_dir=$(CDPATH='' cd -- "$(dirname -- "$manifest")" && pwd)
    for log_key in release_verification cumetal_integration; do
        log_file=$(jq -er --arg key "$log_key" '.logs[$key].file' "$manifest")
        if [[ $log_file == */* || $log_file == .* ]]; then
            echo "unsafe log path in $manifest: $log_file" >&2
            exit 1
        fi
        expected_sha=$(jq -er --arg key "$log_key" '.logs[$key].sha256' "$manifest")
        actual_sha=$(shasum -a 256 "$manifest_dir/$log_file" | awk '{print $1}')
        if [[ $actual_sha != "$expected_sha" ]]; then
            echo "log checksum mismatch: $manifest_dir/$log_file" >&2
            exit 1
        fi
    done
done

if (( ${#generation_names[@]} < 2 )); then
    echo "cross-generation evidence requires at least two distinct Apple generations" >&2
    exit 1
fi

if [[ -n $required_csv ]]; then
    IFS=',' read -r -a required_generations <<<"$required_csv"
    for generation in "${required_generations[@]}"; do
        found=false
        for existing_generation in "${generation_names[@]}"; do
            if [[ $existing_generation == "$generation" ]]; then
                found=true
                break
            fi
        done
        if [[ $found != true ]]; then
            echo "missing required generation: $generation" >&2
            exit 1
        fi
    done
fi

jq -n \
    --arg status pass \
    --arg source_commit "$source_commit" \
    --arg cumetal_commit "$cumetal_commit" \
    --argjson generation_count "${#generation_names[@]}" \
    --arg generations "$(printf '%s\n' "${generation_names[@]}" | sort | paste -sd, -)" \
    '{
      schema_version: 1,
      kind: "vf64-cross-generation-release-evidence",
      status: $status,
      source_commit: $source_commit,
      cumetal_commit: $cumetal_commit,
      generation_count: $generation_count,
      generations: ($generations | split(","))
    }'
