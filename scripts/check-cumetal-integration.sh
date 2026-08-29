#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
cumetal_root=${CUMETAL_ROOT:-"$repo_dir/../cumetal"}
build_dir=${CUMETAL_BUILD_DIR:-"$cumetal_root/build-release"}
test_name=functional_cuda_projects_fp64_precision

if [ ! -f "$cumetal_root/CMakeLists.txt" ]; then
    printf 'CuMetal checkout not found: %s\n' "$cumetal_root" >&2
    exit 2
fi

vf64_commit=$(git -C "$repo_dir" rev-parse HEAD)
pinned_commit=$(git -C "$cumetal_root/third_party/VF64-metal" rev-parse HEAD)
if ! git -C "$repo_dir" diff --quiet "$pinned_commit" "$vf64_commit" -- \
    Sources/VF64Metal/Shaders; then
    printf 'CuMetal VF64-metal shader pin is stale: current %s, pinned %s\n' \
        "$vf64_commit" "$pinned_commit" >&2
    exit 1
fi

cmake -S "$cumetal_root" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" --target cumetal_runtime -j "$(sysctl -n hw.logicalcpu)"

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vf64-cumetal.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

for mode in fast48 wide48 ieee64; do
    output="$tmp_dir/$mode.log"
    CUMETAL_FP64_MODE=$mode ctest --test-dir "$build_dir" \
        -R "^${test_name}$" --output-on-failure -V >"$output" 2>&1
    grep -q 'PASS: fp64 emulation meets the ~48-bit significand contract' "$output"
    case "$mode" in
        fast48)
            grep -q 'provenance=generic_ptx_lowering_fp64_emulated semantic_quality=reduced_precision_fp64' "$output"
            ;;
        wide48)
            grep -q 'provenance=generic_ptx_lowering_fp64_wide48 semantic_quality=reduced_precision_fp64' "$output"
            ;;
        ieee64)
            grep -q 'provenance=generic_ptx_lowering_fp64_ieee64 semantic_quality=exact' "$output"
            ;;
    esac
    printf 'cumetal_vf64_mode=%s result=pass\n' "$mode"
done

printf 'cumetal_commit=%s\n' "$(git -C "$cumetal_root" rev-parse HEAD)"
printf 'vf64_commit=%s\n' "$vf64_commit"
printf 'vf64_pinned_commit=%s\n' "$pinned_commit"
printf 'cumetal_vf64_integration=pass\n'
