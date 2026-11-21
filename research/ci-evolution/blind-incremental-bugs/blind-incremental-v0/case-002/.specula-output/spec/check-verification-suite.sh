#!/usr/bin/env bash
set -euo pipefail

output_root=/work/prior/.specula-output
spec_root="$output_root/spec"
manifest="$spec_root/verification-suite-manifest.json"
ledger="$spec_root/output/repair-suite/command-results.ndjson"

jq empty "$manifest" "$output_root/provenance-manifest.json" \
    "$spec_root/findings.json" "$spec_root/output/repair-suite/event-coverage.json"

test "$(jq -r '.trace_validation.status' "$manifest")" = PASSED
test "$(jq -r '.canonical_model_checking.status' "$manifest")" = PASSED
test "$(jq -s 'all(.[]; .exit_code == 0 and .no_error)' "$ledger")" = true
test "$(jq -s '(map(.kind)|rindex("trace-validation")) < (map(.kind)|index("canonical-base-bfs")) and (map(.kind)|rindex("trace-validation")) < (map(.kind)|index("canonical-mc-bfs"))' "$ledger")" = true

while IFS=$'\t' read -r path expected records log log_expected; do
    actual=$(sha256sum "$output_root/$path" | awk '{print $1}')
    test "$actual" = "$expected"
    log_actual=$(sha256sum "$output_root/$log" | awk '{print $1}')
    test "$log_actual" = "$log_expected"
    expected_states=$((records + 1))
    rg -q "^${expected_states} states generated, ${expected_states} distinct states found, 0 states left on queue\\.$" "$output_root/$log"
    rg -q 'Model checking completed\. No error has been found\.' "$output_root/$log"
done < <(jq -r '.trace_validation.items[] | [.path,.sha256,.records,.log,.log_sha256] | @tsv' "$manifest")

while IFS=$'\t' read -r section log expected generated distinct depth; do
    actual=$(sha256sum "$output_root/$log" | awk '{print $1}')
    test "$actual" = "$expected"
    rg -q "^${generated} states generated, ${distinct} distinct states found, 0 states left on queue\\.$" "$output_root/$log"
    rg -q "^The depth of the complete state graph search is ${depth}\\.$" "$output_root/$log"
    rg -q 'Model checking completed\. No error has been found\.' "$output_root/$log"
done < <(jq -r '.canonical_model_checking | to_entries[] | select(.key == "base" or .key == "mc") | [.key,.value.log,.value.log_sha256,.value.states_generated,.value.distinct_states,.value.depth] | @tsv' "$manifest")

while IFS=$'\t' read -r path expected; do
    actual=$(sha256sum "$output_root/$path" | awk '{print $1}')
    test "$actual" = "$expected"
done < <(jq -r '[
    [.specification.base.module, .specification.base.module_sha256],
    [.specification.base.config, .specification.base.config_sha256],
    [.specification.trace.module, .specification.trace.module_sha256],
    [.specification.trace.config, .specification.trace.config_sha256],
    [.specification.mc.module, .specification.mc.module_sha256],
    [.specification.mc.config, .specification.mc.config_sha256]
  ] | .[] | @tsv' "$manifest")

test "$(find "$spec_root" -type d \( -name states -o -name '.tlc-*' -o -name '.states-*' \) -print -quit)" = ""
if ps -eo args | rg -q '[t]lc2\.TLC'; then
    exit 1
fi
test ! -e "$spec_root/output/repair-suite/.negative-accepted-epoch.ndjson"
test "$(jq -r '.coverage.negative_state_validation.expected_rejection_observed' "$manifest")" = true
test "$(jq -r '.findings | length' "$spec_root/findings.json")" = 0

printf 'verification suite self-check passed\n'
