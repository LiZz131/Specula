#!/usr/bin/env bash
cd "$(dirname "$0")"
for c in NotLeaderReached NotBroadcastReached NotDiffReached NotTruncReached NotSnapReached NotMutationReached NotRecoveryReached NotNlLoggedReached NotFollowerBroadcastReached NotCommitAfterNlReached NotAckBeforeNlAckReached NotUpdateDurabilityGap NotReelectReached; do
  TLC_HEAP=6g ./tlc.sh canary-$c Update.tla Canary-$c.cfg 900s -workers 3 > /dev/null 2>&1
  if grep -q "Invariant $c is violated" output/canary-$c.log; then r=WITNESS; else r=NO-WITNESS; fi
  echo "$c $r depth=$(grep -cE '^State [0-9]+:' output/canary-$c.log) $(grep -E 'Progress' output/canary-$c.log | tail -1 | cut -c1-80)" >> output/canary-summary.log
done
