#!/usr/bin/env bash
# Real TLC trace validation of every retained fresh trace (TraceMatched temporal property,
# full ValidatePostState). Usage: validate_traces.sh [label]   (label prefixes the log names)
set -u
root="$(cd "$(dirname "$0")/.." && pwd)"
spec="$root/spec"; out="$spec/output/trace-validation${1:+-$1}"; mkdir -p "$out"
summary="$out/summary.tsv"; : > "$summary"
run_one() {
  local trace="$1" cfg="$2" name="$3"
  local log="$out/$name.log"
  JSON="$trace" "$root/scripts/tlc.sh" "$spec" Trace.tla "$cfg" "$log" 600 -deadlock -workers 1 >/dev/null 2>&1
  local rc=$?
  local verdict=FAIL
  if grep -q "Model checking completed. No error has been found." "$log" && grep -q "Finished checking temporal properties" "$log"; then verdict=PASS; fi
  local n=$(grep -c . "$trace")
  printf '%s\t%s\t%s\t%s\t%s\n' "$verdict" "$name" "$n" "$rc" "${trace#$root/}" >> "$summary"
}
export -f run_one; export root spec out summary
{
  for t in "$root"/traces/*.ndjson; do echo "$t Trace.cfg unit-$(basename "$t" .ndjson)"; done
  for t in "$root"/traces/window/*/*.ndjson; do d=$(basename "$(dirname "$t")"); echo "$t Trace_window.cfg win-$d-$(basename "$t" .ndjson)"; done
} | xargs -P 8 -L 1 bash -c 'run_one "$0" "$1" "$2"'
sort -k2 "$summary" -o "$summary"
cut -f1 "$summary" | sort | uniq -c
