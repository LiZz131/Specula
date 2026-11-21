#!/usr/bin/env bash
# Run several bounded TLC jobs concurrently and wait for all of them.
# Each arg: "Module|cfg|tag|mode|minutes|workers[|depth]"
out_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pids=()
for job in "$@"; do
  IFS='|' read -r m c t mode mins w d <<<"$job"
  "$out_dir/harness/run_tlc.sh" "$m" "$c" "$t" "$mode" "$mins" "$w" "${d:-100}" > "$out_dir/spec/output/.batch-$t.txt" 2>&1 &
  pids+=($!)
done
for p in "${pids[@]}"; do wait "$p"; done
for job in "$@"; do IFS='|' read -r m c t _ <<<"$job"; cat "$out_dir/spec/output/.batch-$t.txt"; rm -f "$out_dir/spec/output/.batch-$t.txt"; done
