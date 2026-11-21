# Negative controls (synthetic mutations — NOT validation traces)

Each file is a fresh new-version trace with exactly one deliberate mutation,
used only to show that `spec/Trace.tla` consumes the corresponding fields and
ordering. They must be REJECTED (TraceMatched violated / no full match).

| File | Source trace | Mutation |
|---|---|---|
| neg-ack-before-log.ndjson | follower-diff | NewLeaderAckSent swapped before ProposalQueued (pre-update ordering) |
| neg-startup-running.ndjson | follower-diff | ZkStartup aux INITIAL -> RUNNING |
| neg-wrong-logged-txn.ndjson | follower-diff | ProposalQueued txnCounter 2 -> 3 |
| neg-ack-stale-epoch.ndjson | diff-sync-consistency | first NewLeaderAckSent state.currentEpoch -> 0 |
