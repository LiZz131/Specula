#!/usr/bin/env bash
# Reachability canaries: each run is EXPECTED to report a violation (witness).
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workers="${1:-4}"; minutes="${2:-15}"
cd "$suite_root/spec"
for cfg in Canary-*.cfg; do
  n="canary-${cfg%.cfg}"; n="${n/canary-Canary-/canary-}"
  "$suite_root/harness/run-tlc.sh" "$n" Update "$cfg" "$workers" "$minutes" > /dev/null 2>&1
  log="$suite_root/spec/output/$n.log"
  if grep -qE "is violated" "$log"; then
     echo "WITNESS $cfg: $(grep -oE '(Invariant|Action property) [A-Za-z]+ is violated' "$log" | head -1); states=$(grep -c '^State ' "$log")"
  elif grep -q "No error has been found" "$log"; then echo "UNREACHED $cfg (exhaustive)"; else echo "INCONCLUSIVE $cfg (budget)"; fi
done
