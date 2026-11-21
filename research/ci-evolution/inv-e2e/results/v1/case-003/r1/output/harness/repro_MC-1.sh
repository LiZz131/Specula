#!/usr/bin/env bash
# Reproduce Specula finding MC-1 on a CometBFT source tree (no instrumentation).
# usage: harness/repro_MC-1.sh [source-tree] [log]
#   exit 0  -> test PASSED: unchanged VEH update accepted, restart OK (no MC-1)
#   exit 1  -> test FAILED: MC-1 present (rejection + restart replay failure)
#   other   -> build/timeout problem
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
src="${1:-$here/../artifact}"
log="${2:-$here/../spec/output/repro-MC-1.log}"
dst="$src/internal/state/specula_mc1_repro_test.go"
cp "$here/repro/specula_mc1_repro_test.go" "$dst"
trap 'rm -f "$dst"' EXIT
{
  echo "# source: $src ($(git -C "$src" rev-parse --short HEAD 2>/dev/null || echo unknown))"
  echo "# command: (cd $src && timeout 10m go test -mod=readonly ./internal/state -run '^TestSpeculaMC1UnchangedVoteExtensionsEnableHeight\$' -count=1 -v)"
  (cd "$src" && timeout 10m go test -mod=readonly ./internal/state -run '^TestSpeculaMC1UnchangedVoteExtensionsEnableHeight$' -count=1 -v 2>&1)
  rc=$?
  echo "# exit: $rc"
} > "$log" 2>&1
rc=$(grep -o '^# exit: [0-9]*' "$log" | grep -o '[0-9]*$')
grep -E "SPECULA_MC1|^--- |^(ok|FAIL)" "$log"
exit "$rc"
