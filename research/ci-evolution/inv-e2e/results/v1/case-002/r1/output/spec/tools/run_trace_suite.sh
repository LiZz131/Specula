#!/usr/bin/env bash
# Full trace regression for the current suite. Usage: tools/run_trace_suite.sh <tag>  (run from spec/)
set -uo pipefail
tag="$1"; ledger="output/trace-suite-$tag.ndjson"; : > "$ledger"
for t in follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-consistency repro-initial-state-failure; do
  start=$(date -u +%FT%TZ)
  cfg=Trace.cfg; [ "$t" = repro-initial-state-failure ] && cfg=Trace-conformance.cfg
  res=$(./tools/run_trace.sh "$t" "$tag" "$cfg")
  log="output/trace-$tag-$t.log"
  ok=false; grep -q "Model checking completed. No error has been found." "$log" && ok=true
  q=$(grep -o "[0-9,]* states left on queue" "$log" | tail -1)
  ev=$(grep -c '"tag":"trace"' "../traces/$t.ndjson")
  jq -cn --arg cfg "$cfg" --arg t "$t" --arg log "spec/$log" --arg start "$start" --arg q "$q" --argjson ok $ok --argjson ev $ev \
    --arg sha "$(sha256sum ../traces/$t.ndjson | cut -c1-64)" \
    '{trace:$t, events:$ev, sha256:$sha, log:$log, started:$start, trace_matched_and_invariants_ok:$ok, queue:$q, cfg:$cfg, properties:["TraceMatched","HistoryPositionsMonotonicExceptRecovery"]}' >> "$ledger"
  echo "$res"
done
