#!/usr/bin/env bash
# Run a list of "name module cfg workers minutes [extra]" lines in parallel batches; blocks until all finish.
set -uo pipefail
suite_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pids=()
while read -r name module cfg workers minutes extra; do
  [ -z "${name:-}" ] && continue
  case "$name" in \#*) continue;; esac
  TLC_XMX="${TLC_XMX:-12g}" "$suite_root/harness/run-tlc.sh" "$name" "$module" "$cfg" "$workers" "$minutes" $extra > /dev/null 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
