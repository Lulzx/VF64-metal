#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/vf64-support.XXXXXX")
trap 'rm -rf "$temp_dir"' EXIT HUP INT TERM

"$script_dir/build-vf64-support.sh" "$temp_dir/vf64-support.air"

# The probe is checked-in AIR, so it carries a target triple and an air.version
# from the toolchain that produced it. air-link refuses to link modules whose
# air.version differs, which would make this check fail on any toolchain but
# that one. Read both values from the installed toolchain and stamp them onto a
# copy of the probe; the committed source keeps its original values.
cat > "$temp_dir/air-probe.metal" <<'METAL'
#include <metal_stdlib>
kernel void vf64_air_version_probe(device float *output [[buffer(0)]]) {
    output[0] = 1.0f;
}
METAL
xcrun metal -std=metal3.2 -S -emit-llvm "$temp_dir/air-probe.metal" \
    -o "$temp_dir/air-probe.ll"

triple=$(sed -n 's/^target triple = "\(.*\)"$/\1/p' "$temp_dir/air-probe.ll")
air_version=$(python3 - "$temp_dir/air-probe.ll" <<'AIRVERSION'
import re
import sys

text = open(sys.argv[1]).read()
node = re.search(r"^!air\.version = !\{!(\d+)\}", text, re.M).group(1)
fields = re.search(r"^!%s = !\{([^}]*)\}" % node, text, re.M).group(1)
print(" ".join(re.findall(r"i32 (\d+)", fields)))
AIRVERSION
)

if [ -z "$triple" ] || [ -z "$air_version" ]; then
    printf 'could not read target triple or air.version from the toolchain\n' >&2
    exit 1
fi

major=$(printf '%s\n' "$air_version" | cut -d' ' -f1)
minor=$(printf '%s\n' "$air_version" | cut -d' ' -f2)
patch=$(printf '%s\n' "$air_version" | cut -d' ' -f3)

sed \
    -e "s|^target triple = \".*\"$|target triple = \"$triple\"|" \
    -e "s|\"air.version\"=\"[0-9.]*\"|\"air.version\"=\"$major.$minor\"|" \
    -e "s|!{i32 2, i32 8, i32 0}|!{i32 $major, i32 $minor, i32 $patch}|" \
    "$repo_dir/tests/interop/vf64_support_link.ll" > "$temp_dir/probe.ll"

xcrun metal -c "$temp_dir/probe.ll" -o "$temp_dir/probe.air"
xcrun air-link "$temp_dir/probe.air" "$temp_dir/vf64-support.air" \
    -o "$temp_dir/linked.air"
xcrun metallib "$temp_dir/linked.air" -o "$temp_dir/probe.metallib"
swift "$repo_dir/tests/interop/VF64SupportRuntime.swift" \
    "$temp_dir/probe.metallib"
printf 'vf64_support_air_version=%s.%s.%s triple=%s\n' \
    "$major" "$minor" "$patch" "$triple"
