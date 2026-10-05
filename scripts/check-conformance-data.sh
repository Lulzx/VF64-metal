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

m9_matrix="$repo_dir/results/conformance/2026-10-05-m4-pro-m9-function-matrix.json"

jq -e '
  (.functions | length) == .totals.functions and
  ([.functions[].function] | unique | length) == .totals.functions and
  ([.functions[].policy_cells] | add) == .totals.policy_cells and
  ([.functions[].result_comparisons] | add) == .totals.result_comparisons and
  (all(.functions[]; .mismatches == 0 and .uncertified_results == 0 and .policy_cells == 5)) and
  ([.functions[] | select(.proof_obligation_state == "proven-correctly-rounded")] | length) == .totals.proven_functions and
  ([.functions[] | select(.proof_obligation_state == "certified-correctly-rounded")] | length) == .totals.certified_functions and
  (.evidence.source_commit | test("dirty") | not) and
  .totals.functions == 22 and
  .totals.policy_cells == 110 and
  .totals.result_comparisons == 440402485 and
  .totals.mismatches == 0 and
  .totals.uncertified_results == 0 and
  ([.functions[].support_result_comparisons] | add) == .totals.support_result_comparisons and
  ([.functions[].support_mismatches] | add) == .totals.support_mismatches and
  (all(.functions[]; .support_result_comparisons == .result_comparisons and .support_mismatches == 0)) and
  (.support_path.source_commit | test("dirty") | not) and
  .totals.support_result_comparisons == 440402485 and
  .totals.support_mismatches == 0
' "$m9_matrix" >/dev/null

# Every matrix row must agree with the per-function artifact it cites.
m9_commit=$(jq -r '.evidence.source_commit' "$m9_matrix")
jq -c '.functions[]' "$m9_matrix" | while IFS= read -r row; do
    artifact="$repo_dir/$(printf '%s' "$row" | jq -r '.artifact')"
    jq -e --argjson row "$row" --arg commit "$m9_commit" '
      .milestone == "M9" and
      .status == "pass" and
      .source_commit == $commit and
      .policy.function == $row.function and
      .policy.proof_obligation_state == $row.proof_obligation_state and
      .policy.evaluation_error_bound_relative == $row.evaluation_error_bound_relative and
      .policy.certification_margin_relative == $row.certification_margin_relative and
      (.policy.rounding_modes | length) == $row.policy_cells and
      .total_result_comparisons == $row.result_comparisons and
      .unexplained_mismatches == $row.mismatches and
      .uncertified_results == $row.uncertified_results and
      ([.rounding_modes[] | .mismatches] | add) == 0 and
      ([.rounding_modes[] | .uncertified] | add) == 0
    ' "$artifact" >/dev/null
done

# The support-path rows must agree with their own artifacts: flag-free, so
# result bits only, from one clean commit.
m9_support_commit=$(jq -r '.support_path.source_commit' "$m9_matrix")
jq -c '.functions[]' "$m9_matrix" | while IFS= read -r row; do
    artifact="$repo_dir/$(printf '%s' "$row" | jq -r '.support_artifact')"
    jq -e --argjson row "$row" --arg commit "$m9_support_commit" '
      .milestone == "M9" and
      .status == "pass" and
      .source_commit == $commit and
      .policy.function == $row.function and
      .policy.exception_flags_checked == false and
      .uncertified_results == null and
      (.result_scope | test("support ABI")) and
      (.policy.rounding_modes | length) == $row.policy_cells and
      .total_result_comparisons == $row.support_result_comparisons and
      .unexplained_mismatches == $row.support_mismatches and
      ([.rounding_modes[] | .mismatches] | add) == 0
    ' "$artifact" >/dev/null
done

m9_total=$(jq -r '.totals.result_comparisons' "$m9_matrix")

printf 'conformance_data=pass operations=26 cells=119 comparisons_per_path=%s m9_functions=22 m9_cells=110 m9_comparisons=%s m9_support_comparisons=%s\n' "$matrix_total" "$m9_total" "$(jq -r '.totals.support_result_comparisons' "$m9_matrix")"
