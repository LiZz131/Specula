#!/usr/bin/env bash
# Run a list of TLC campaigns sequentially and append outcomes to
# spec/output/campaign-summary.txt.
# usage: run-campaigns.sh <workers> <heap> "<Module>:<cfg>:<label>:<seconds>[:extra args]" ...
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workers="$1"; heap="$2"; shift 2
summary="$suite_root/spec/output/campaign-summary.txt"
for spec in "$@"; do
  IFS=':' read -r module cfg label secs extra <<< "$spec"
  # shellcheck disable=SC2086
  SPECULA_TLC_WORKERS="$workers" SPECULA_TLC_HEAP="$heap" "$suite_root/harness/run-tlc.sh" "$module" "$cfg" "$label" "$secs" $extra
  rc=$?
  log="$suite_root/spec/output/mc-$label.log"
  verdict=$(grep -m1 -E "^Error: (Invariant|Action property|Temporal properties|The behavior|Deadlock)|is violated" "$log" | head -1)
  stats=$(grep -E "states generated, .* distinct states found" "$log" | tail -1)
  [ -z "$stats" ] && stats=$(grep -E "^Progress" "$log" | tail -1)
  depth=$(grep -E "depth of the complete state graph|The number of states generated|traces|mean length" "$log" | tail -1)
  echo "$(date -u +%FT%TZ) | $label | $module/$cfg | rc=$rc | ${verdict:-no violation} | $stats | $depth" >> "$summary"
done
