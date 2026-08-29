#!/bin/bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 3 ]]; then
  echo "usage: $0 OUTPUT_JSON [RAW_TRACE] [TEMPLATE_NAME]" >&2
  exit 2
fi

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
output_json="$1"
raw_trace="${2:-$repo_root/.build/vf64-traces/performance-counters.trace}"
template_name="${3:-${VF64_METAL_COUNTER_TEMPLATE:-VF64 Performance Limiters}}"
binary="$repo_root/.build/release/vf64-metal"

if [[ ! -x "$binary" ]]; then
  echo "error: missing release binary; run swift build -c release" >&2
  exit 1
fi
if [[ -e "$raw_trace" ]]; then
  echo "error: trace path already exists: $raw_trace" >&2
  exit 1
fi
if ! xcrun xctrace list templates | grep -Fxq "$template_name"; then
  echo "error: missing Instruments template '$template_name'" >&2
  echo "see docs/benchmarks/metal-counter-template.md" >&2
  exit 1
fi

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$(dirname "$raw_trace")" "$(dirname "$output_json")"

xcrun xctrace record \
  --template "$template_name" \
  --output "$raw_trace" \
  --no-prompt \
  --target-stdout "$work_dir/bench.log" \
  --launch -- "$binary" bench

xcrun xctrace export --input "$raw_trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-info"]' \
  --output "$work_dir/counter-info.xml"
xcrun xctrace export --input "$raw_trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="gpu-counter-value"]' \
  --output "$work_dir/counter-values.xml"
xcrun xctrace export --input "$raw_trace" \
  --xpath '/trace-toc/run[@number="1"]/data/table[@schema="metal-gpu-intervals"]' \
  --output "$work_dir/gpu-intervals.xml"
xcrun xctrace export --input "$raw_trace" --toc --output "$work_dir/toc.xml"

python3 "$repo_root/scripts/summarize-metal-counters.py" \
  "$work_dir/counter-info.xml" \
  "$work_dir/counter-values.xml" \
  "$work_dir/gpu-intervals.xml" > "$work_dir/counters.json"

if ! grep -q 'Counter Set: Performance Limiters' "$work_dir/toc.xml"; then
  echo "error: trace did not record the Performance Limiters counter set" >&2
  exit 1
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
RAW_TRACE="$raw_trace" TEMPLATE_NAME="$template_name" \
python3 - "$work_dir/counters.json" "$output_json" <<'PY'
import json
import os
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    counters = json.load(source)

result = {
    "schema": "vf64-metal-performance-counters-v1",
    "captured_at_utc": os.environ["CAPTURED_AT"],
    "source_commit": os.environ["SOURCE_COMMIT"],
    "device": os.environ["DEVICE_NAME"],
    "os_version": os.environ["OS_VERSION"],
    "xcode_version": os.environ["XCODE_VERSION"],
    "capture": {
        "tool": "xctrace",
        "template": os.environ["TEMPLATE_NAME"],
        "counter_set": "Performance Limiters",
        "workload": "vf64-metal bench",
        "raw_trace_path": os.environ["RAW_TRACE"],
        "raw_trace_content_tree_sha256": os.environ["TRACE_SHA256"],
    },
    "performance_counters": counters,
    "limitations": [
        "Counters are device-level; concurrent GPU work can contribute during VF64 intervals.",
        "Raw .trace bundles are local build artifacts; the published JSON is checksum-bound to one.",
    ],
}

with open(sys.argv[2], "w", encoding="utf-8") as output:
    json.dump(result, output, indent=2, sort_keys=True)
    output.write("\n")
PY

echo "wrote $output_json"
echo "raw trace: $raw_trace"
