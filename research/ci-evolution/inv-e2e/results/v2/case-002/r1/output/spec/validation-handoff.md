# Validation handoff (incremental run)

- **Source**: artifact commit `update` 2efbdfc3754df193bce05b9792297c813377cdaf
  (old: `baseline` 1414ebfb1d16fd81abc38550a96950d919ecf805).
- **Harness command**: `timeout 3600s /work/current/.specula-output/harness/run.sh`
  (rebased prior harness; patch `harness/patches/instrumentation.patch`; logs
  `spec/output/update/harness-*.log`, summary `spec/output/update/harness-summary.txt`).
- **Validation changed semantic spec files**: yes (memHist, leave semantics,
  leader flush order) - all recorded in `spec/changelog.md` Round I1.

## Fresh trace inventory (updated source, second collection)

| Trace | Records | Scenario type | Trace.tla (TraceMatched) | TraceSync.tla |
|---|---:|---|---|---|
| traces/follower-snap.ndjson | 20 | prior regression | pass (final-trace-follower-snap) | n/a (post-NEWLEADER proposal outside TraceSync scope) |
| traces/follower-diff.ndjson | 19 | prior regression, U1 | pass | pass (final-tracesync-follower-diff) |
| traces/quorum-startup-mutation-shutdown.ndjson | 75 | prior regression | pass | n/a |
| traces/leader-abandon-restart-recovery.ndjson | 283 | prior regression | pass | n/a |
| traces/update-diff-sync-consistency.ndjson | 161 | visible-diff test, U1/U4 | pass | n/a |
| traces/update-observe-ack-durability.ndjson | 19 | update observation U1 | pass | pass |
| traces/update-observe-commit-after-newleader.ndjson | 15 | update observation U3 | pass (observer only; late join outside reference scope) | n/a |

Each pass is a completed TLC run with `TraceMatched` and zero states left
(depth = records + 1); logs `spec/output/update/final-trace-<name>.log`,
`final-tracesync-<name>.log`; ledger `spec/output/update/command-results.ndjson`.

## Coverage of affected actions

| Action | Observed in fresh trace | Compared by |
|---|---|---|
| ReceiveSyncPayload | SyncSelected + SyncProposalReceived (follower-diff, update-*) | TraceSync (action), Trace (buffer size/entry) |
| PersistCurrentEpoch | CurrentEpochPersisted | both |
| ClearSyncMode (moved) | SyncModeChanged(NONE) before NewLeaderAckSent | Trace (state.syncMode at ACK), TraceSync (action) |
| AckNewLeader | NewLeaderAckSent / NewLeaderAckWritten (logged, running, disk position) | Trace + TraceSync (exact durable field) |
| EnterBroadcast | BroadcastReady (running=true, pending) | both |
| LeaderBroadcast (interaction) | NewLeaderAckCounted + leader PhaseChanged(broadcast) | Trace (peer ACK order); TraceSync constrained silent step |
| BeginElection from INITIAL (interaction) | update-diff-sync-consistency 87-88, 103-104 followed by leaked TxnDurable | Trace (memHist/position checks) |

Gaps: crash inside the ACK/fsync window was not injected in a real run (model
only); late join (U3) is outside the reference's sync scope and is covered by
direct code observation (CR-1).

## Archived traces

- `traces/archived-v0/*` (exact-old harness): superseded - the BroadcastReady
  probe now requires the update `detail`, and the old NEWLEADER ordering was
  removed by the update (`spec/output/update/archived-v0-follower-diff.log`).
- `traces/superseded-capture-r1/*`: first updated-source collection with the
  late `NewLeaderAckSent` probe (capture-timing defect); replaced.

## Gate

Complete fresh suite passes on the stable candidate (final-* logs) before the
model-checking campaign (`spec/run-campaigns.sh`).
