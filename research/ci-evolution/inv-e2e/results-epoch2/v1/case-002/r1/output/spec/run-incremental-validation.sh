#!/usr/bin/env bash
# V1 final trace-validation gate (Validation 3 §4) + negative mutations +
# archived-trace dispositions + update-property code observations.
cd /work/current/.specula-output/spec
R=./run-tlc.sh
TAG=${TAG:-final}
CONFORMANCE="follower-snap follower-diff quorum-startup-mutation-shutdown leader-abandon-restart-recovery diff-sync-uptodate-failure follower-diff-bulk-r1 follower-diff-bulk-r2 follower-diff-bulk-r3 repro-u4-no-restart-r1 repro-u4-no-restart-r2 repro-u4-no-restart-r3 control-diffsync-leaderwait-r1 control-diffsync-leaderwait-r2"
for t in $CONFORMANCE; do JSON=../traces/$t.ndjson WORKERS=1 $R $TAG-tv-$t Trace.tla Trace.cfg 600s; done
for n in neg1-queued-mismatch neg2-syncmode-before-ack neg3-initial-skip-while-running neg4-quorum-claim neg5-no-initial-skip; do JSON=../traces/negative/$n.ndjson WORKERS=1 $R $TAG-$n Trace.tla Trace.cfg 300s; done
for t in follower-diff follower-snap follower-snap-attempt-001 quorum-startup-mutation-shutdown leader-abandon-restart-recovery; do JSON=../traces/archived-v0/$t.ndjson WORKERS=1 $R $TAG-archived-$t Trace.tla Trace.cfg 300s; done
for p in NewLeaderAckImpliesDurableSync CertifiedDurableOnQuorum VotingHistoryCoversDurable NewLeaderAckIsFirstAck; do
  for t in follower-diff follower-diff-bulk-r1 diff-sync-uptodate-failure repro-u4-no-restart-r1 control-diffsync-leaderwait-r1 leader-abandon-restart-recovery quorum-startup-mutation-shutdown; do
    JSON=../traces/$t.ndjson WORKERS=1 $R $TAG-ev-$p-$t TraceUpdateEvidence.tla TraceEvidence-$p.cfg 600s
  done
done
