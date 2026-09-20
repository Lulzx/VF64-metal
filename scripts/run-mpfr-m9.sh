#!/bin/sh
# M9 differential conformance campaign for correctly rounded exp.
#
# Berkeley TestFloat has no transcendental generators, so this is the M9
# equivalent of run-testfloat-m1.sh: a pinned oracle, a seeded corpus, every
# rounding mode, and one machine-readable artifact under results/m9/.
#
# The run fails closed. A mismatch against MPFR fails, and so does any case the
# kernel could not certify as correctly rounded, because an uncertified case is
# a result whose rounding is not proven even when it happens to be right.
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
generator=$("$script_dir/bootstrap-mpfr.sh" | tail -n 1)
binary="$repo_dir/.build/release/vf64-metal"

cases=${VF64_M9_CASES:-4000000}
seed=${VF64_M9_SEED:-1}
function=${VF64_M9_FUNCTION:-f64_exp}

swift build --package-path "$repo_dir" -c release

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

for rounding in rnear_even rminMag rmin rmax rnear_maxMag; do
    {
        "$generator" "$rounding" boundary
        "$generator" "$rounding" random "$cases" "$seed"
    } | "$binary" transcendental "$function" "$rounding" |
        tee -a "$work/log.txt" | grep '^{' >> "$work/summaries.jsonl"
done

mkdir -p "$repo_dir/results/m9"
sw_vers > "$work/sw_vers.txt"
system_profiler SPDisplaysDataType > "$work/gpu.txt"
# An artifact must never imply it was produced from committed source.
commit=$(git -C "$repo_dir" rev-parse --short HEAD)
if ! git -C "$repo_dir" diff-index --quiet HEAD --; then
    commit="$commit-dirty"
fi
printf '%s\n' "$commit" > "$work/commit.txt"
sed -n 's/^#define MPFR_VERSION_STRING "\([^"]*\)".*/\1/p' \
    "${VF64_MPFR_PREFIX:-/opt/homebrew}/include/mpfr.h" > "$work/mpfr.txt"

artifact=$(python3 "$repo_dir/scripts/summarize-m9-campaign.py" \
    --work "$work" --repo "$repo_dir" --cases "$cases" --seed "$seed" \
    --function "$function")

printf 'm9_exp_conformance=pass\n'
printf 'artifact=%s\n' "$artifact"
