#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 OUTPUT_JSON [RAW_TRACE]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_json="$1"
raw_trace="${2:-$repo_root/.build/vf64-traces/resource-bench.trace}"
binary="$repo_root/.build/release/vf64-metal"

if [[ ! -x "$binary" ]]; then
  echo "error: missing release binary; run swift build -c release" >&2
  exit 1
fi
if [[ -e "$raw_trace" ]]; then
  echo "error: trace path already exists: $raw_trace" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$(dirname "$raw_trace")" "$(dirname "$output_json")"

xcrun xctrace record \
  --template "Metal System Trace" \
  --output "$raw_trace" \
  --no-prompt \
  --target-stdout "$work_dir/bench.log" \
  --launch -- "$binary" bench

xcrun xctrace export --input "$raw_trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-application-encoders-list"]' \
  --output "$work_dir/encoders.xml"
xcrun xctrace export --input "$raw_trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="graphics-compiler-spill-events"]' \
  --output "$work_dir/spills.xml"
xcrun xctrace export --input "$raw_trace" --toc --output "$work_dir/toc.xml"

swift "$repo_root/scripts/summarize-metal-trace.swift" \
  "$work_dir/encoders.xml" "$work_dir/spills.xml" > "$work_dir/spills.json"

unmapped="$(plutil -extract unmapped_spill_event_count raw -o - "$work_dir/spills.json")"
if [[ "$unmapped" != "0" ]]; then
  echo "error: $unmapped vf64-metal spill events could not be mapped to labeled encoders" >&2
  exit 1
fi

counter_set="unknown"
if grep -q 'Counter Set: (null)' "$work_dir/toc.xml"; then
  counter_set="none"
fi

trace_sha256="$(
  cd "$raw_trace"
  find . -type f -print0 | sort -z | xargs -0 shasum -a 256 | shasum -a 256 | awk '{print $1}'
)"
source_commit="$(git -C "$repo_root" rev-parse HEAD)"
device_name="$(system_profiler SPDisplaysDataType | awk -F': ' '/Chipset Model/{print $2; exit}')"
os_version="$(sw_vers -productVersion)"
xcode_version="$(xcodebuild -version | paste -sd ' ' -)"
captured_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

SOURCE_COMMIT="$source_commit" DEVICE_NAME="$device_name" OS_VERSION="$os_version" \
XCODE_VERSION="$xcode_version" CAPTURED_AT="$captured_at" TRACE_SHA256="$trace_sha256" \
RAW_TRACE="$raw_trace" COUNTER_SET="$counter_set" \
python3 - "$work_dir/spills.json" "$output_json" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    spills = json.load(source)

result = {
    "schema": "vf64-metal-resource-trace-v1",
    "captured_at_utc": os.environ["CAPTURED_AT"],
    "source_commit": os.environ["SOURCE_COMMIT"],
    "device": os.environ["DEVICE_NAME"],
    "os_version": os.environ["OS_VERSION"],
    "xcode_version": os.environ["XCODE_VERSION"],
    "capture": {
        "tool": "xctrace",
        "template": "Metal System Trace",
        "counter_set": os.environ["COUNTER_SET"],
        "workload": "vf64-metal bench",
        "raw_trace_path": os.environ["RAW_TRACE"],
        "raw_trace_content_tree_sha256": os.environ["TRACE_SHA256"],
    },
    "compiler_spills": spills,
    "physical_registers": {"available": False},
    "resident_occupancy": {"available": False},
    "limitations": [
        "The standard command-line Metal System Trace template did not select a GPU counter set.",
        "The trace exposes compiler spill events but not physical register allocation.",
        "Raw .trace bundles are local build artifacts; the published JSON is checksum-bound to one.",
    ],
}

with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(result, output, indent=2, sort_keys=True)
    output.write("\n")
PY

echo "wrote $output_json"
echo "raw trace: $raw_trace"
