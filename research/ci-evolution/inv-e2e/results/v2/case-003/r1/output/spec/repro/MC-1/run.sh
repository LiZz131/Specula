#!/usr/bin/env bash
# Run the MC-1 reproduction against a CometBFT source tree.
#   usage: run.sh <source-tree> [log-file]
# Copies the self-contained test into <tree>/internal/state, runs it with a
# 10-minute outer timeout, and removes it again. Exit status is the go test status
# (non-zero = the unchanged enable height was rejected, i.e. MC-1 reproduced).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tree="$(cd "$1" && pwd)"; log="${2:-/dev/stdout}"
dst="$tree/internal/state/specula_mc1_repro_test.go"
cp "$here/specula_mc1_repro_test.go" "$dst"
trap 'rm -f "$dst"' EXIT
{
  echo "+ cd $tree && timeout 10m go test -mod=readonly ./internal/state -run '^TestSpeculaMC1' -count=1 -v"
  echo "+ tree types/params.go sha256: $(sha256sum "$tree/types/params.go" | cut -d' ' -f1)"
  (cd "$tree" && timeout 10m go test -mod=readonly ./internal/state -run '^TestSpeculaMC1' -count=1 -v 2>&1 \
     | grep -E '^(=== RUN|\s*--- (PASS|FAIL)|PASS|FAIL|ok|\s+Error:|\s+Error Trace:|\s+Messages:|.*vote extensions|.*VoteExtensions)')
  rc=${PIPESTATUS[0]}
  echo "exit_code: $rc"
} > "$log" 2>&1
exit $(grep -o 'exit_code: [0-9]*' "$log" | grep -o '[0-9]*$')
