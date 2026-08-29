#!/bin/sh
set -eu

usage() {
    printf 'Usage: sudo scripts/capture-energy.sh OUTPUT_DIR -- COMMAND [ARG...]\n' >&2
    exit 2
}

[ "$(id -u)" -eq 0 ] || {
    printf 'capture-energy requires root because powermetrics requires root\n' >&2
    exit 2
}
[ "$#" -ge 3 ] || usage

output_dir=$1
shift
[ "$1" = "--" ] || usage
shift
[ "$#" -gt 0 ] || usage

interval_ms=${VF64_POWER_INTERVAL_MS:-100}
case "$interval_ms" in
    ''|*[!0-9]*|0) printf 'VF64_POWER_INTERVAL_MS must be a positive integer\n' >&2; exit 2 ;;
esac

mkdir -p "$output_dir"
raw="$output_dir/powermetrics.txt"
workload="$output_dir/workload.log"
metadata="$output_dir/metadata.txt"

cleanup() {
    if [ -n "${power_pid:-}" ]; then
        kill -INT "$power_pid" 2>/dev/null || true
        wait "$power_pid" 2>/dev/null || true
    fi
}
trap cleanup EXIT HUP INT TERM

start_epoch=$(date +%s)
powermetrics --samplers cpu_power,gpu_power \
    --sample-rate "$interval_ms" --buffer-size 1 --output-file "$raw" &
power_pid=$!

set +e
"$@" >"$workload" 2>&1
command_status=$?
set -e

kill -INT "$power_pid" 2>/dev/null || true
wait "$power_pid" 2>/dev/null || true
power_pid=
end_epoch=$(date +%s)

{
    printf 'schema=vf64.energy-capture.v1\n'
    printf 'start_epoch=%s\n' "$start_epoch"
    printf 'end_epoch=%s\n' "$end_epoch"
    printf 'wall_seconds=%s\n' "$((end_epoch - start_epoch))"
    printf 'sample_interval_ms=%s\n' "$interval_ms"
    printf 'command_status=%s\n' "$command_status"
    printf 'command='
    printf '%s ' "$@"
    printf '\n'
    system_profiler SPDisplaysDataType | sed -n '1,24p'
    sw_vers
} >"$metadata"

[ -s "$raw" ] || {
    printf 'powermetrics produced no samples: %s\n' "$raw" >&2
    exit 1
}

printf 'energy_capture=pass output=%s command_status=%s\n' \
    "$output_dir" "$command_status"
exit "$command_status"
