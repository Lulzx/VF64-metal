#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vf64-support.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

"$script_dir/build-vf64-support.sh" "$temp_dir/vf64-support.air"
xcrun metal -c "$repo_dir/tests/interop/vf64_support_link.ll" \
    -o "$temp_dir/probe.air"
xcrun air-link "$temp_dir/probe.air" "$temp_dir/vf64-support.air" \
    -o "$temp_dir/linked.air"
xcrun metallib "$temp_dir/linked.air" -o "$temp_dir/probe.metallib"
swift "$repo_dir/tests/interop/VF64SupportRuntime.swift" \
    "$temp_dir/probe.metallib"
