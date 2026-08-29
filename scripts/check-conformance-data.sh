#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
matrix="$repo_dir/results/conformance/2026-08-29-m4-pro-operation-matrix.json"
m2="$repo_dir/results/m2/2026-08-29-m4-pro-full-runtime-level1.json"
m4="$repo_dir/results/m4/2026-08-29-m4-pro-vf64-v1-level1.json"

jq -e '
  (.operations | length) == .totals.operations and
  ([.operations[].operation] | unique | length) == .totals.operations and
  ([.operations[].policy_cells] | add) == .totals.policy_cells and
  ([.operations[].comparisons] | add) == .totals.comparisons_per_execution_path and
  (all(.operations[]; .comparisons == (.policy_cells * .cases_per_cell))) and
  (all(.operations[]; .direct_runtime_mismatches == 0 and .vf64_isa_mismatches == 0)) and
  .totals.operations == 26 and
  .totals.policy_cells == 119 and
  .totals.comparisons_per_execution_path == 31982976
' "$matrix" >/dev/null

matrix_total=$(jq -r '.totals.comparisons_per_execution_path' "$matrix")
m2_total=$(jq -r '.total_result_and_flag_comparisons' "$m2")
m4_total=$(jq -r '.testfloat.result_and_flag_comparisons' "$m4")
m4_cells=$(jq -r '.testfloat.operation_policy_cells' "$m4")

test "$matrix_total" = "$m2_total"
test "$matrix_total" = "$m4_total"
test "$m4_cells" = "119"

printf 'conformance_data=pass operations=26 cells=119 comparisons_per_path=%s\n' "$matrix_total"
