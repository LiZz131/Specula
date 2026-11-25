#!/usr/bin/env bash
# Evidence that every emitted trace field is consumed by Trace.tla:
# lists each pre/post/args key in the fresh traces and the Trace.tla lines
# that read it (as `.<field>`).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
trace_tla="$suite_root/spec/Trace.tla"
status=0
for scope in pre post args; do
  keys=$(cat "$suite_root"/traces/*.ndjson | jq -r ".event.$scope | keys[]" | sort -u)
  for k in $keys; do
    n=$(grep -cE "\.$k\b" "$trace_tla")
    if [ "$n" -eq 0 ]; then echo "UNCONSUMED $scope.$k"; status=1; else echo "consumed $scope.$k ($n refs)"; fi
  done
done
exit $status
