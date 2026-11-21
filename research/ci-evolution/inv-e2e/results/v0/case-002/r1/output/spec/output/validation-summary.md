# Validation summary (incremental, case-002)

Source: artifact commit `update` 2efbdfc3754d; harness `harness/run.sh` (rebased V0 patch + update probes).
Spec: `spec/Trace.tla` + `spec/Trace.cfg` (Server s0..s2, Txn {0..7,1000}, MaxEpoch 4, `TraceMatched`).

## Fresh new-version trace inventory and final replay (stable candidate)

| Trace | Records | SHA-256 | Test exit | TLC result | States | Log |
|---|---:|---|---:|---|---|---|
| traces/follower-diff.ndjson | 20 | 73dcf346b7bec6f9… | 0 | PASS (TraceMatched, natural completion) | 25 states generated, 25 distinct states found, 0 states left on queue | spec/output/trace-validation/final-follower-diff.log |
| traces/follower-snap.ndjson | 21 | bb95539dd5d14bf5… | 0 | PASS (TraceMatched, natural completion) | 26 states generated, 26 distinct states found, 0 states left on queue | spec/output/trace-validation/final-follower-snap.log |
| traces/leader-abandon-restart-recovery.ndjson | 286 | 1006affd0c2d9c02… | 0 | PASS (TraceMatched, natural completion) | 299 states generated, 299 distinct states found, 0 states left on queue | spec/output/trace-validation/final-leader-abandon-restart-recovery.log |
| traces/quorum-startup-mutation-shutdown.ndjson | 75 | 865eb0657cab8a84… | 0 | PASS (TraceMatched, natural completion) | 78 states generated, 78 distinct states found, 0 states left on queue | spec/output/trace-validation/final-quorum-startup-mutation-shutdown.log |
| traces/update-commit-after-newleader.ndjson | 16 | 82ed210876738875… | 1 | PASS (TraceMatched, natural completion) | 20 states generated, 20 distinct states found, 0 states left on queue | spec/output/trace-validation/final-update-commit-after-newleader.log |
| traces/update-diff-sync-consistency.ndjson | 160 | ec03cb63fc5c3381… | 0 | PASS (TraceMatched, natural completion) | 174 states generated, 174 distinct states found, 0 states left on queue | spec/output/trace-validation/final-update-diff-sync-consistency.log |
| traces/update-newleader-ack-durability.ndjson | 16 | be545fc91faba056… | 1 | PASS (TraceMatched, natural completion) | 20 states generated, 20 distinct states found, 0 states left on queue | spec/output/trace-validation/final-update-newleader-ack-durability.log |

## Negative (mutated) traces — must be rejected

| Mutation | Result | Log |
|---|---|---|
| ../traces/negative/neg-commit-buffer-nonempty.ndjson | REJECTED (exit 13) | spec/output/trace-validation/negative-neg-commit-buffer-nonempty.log |
| ../traces/negative/neg-nlack-pending.ndjson | REJECTED (exit 13) | spec/output/trace-validation/negative-neg-nlack-pending.log |
| ../traces/negative/neg-initial-exit-fastforward.ndjson | REJECTED (exit 13) | spec/output/trace-validation/negative-neg-initial-exit-fastforward.log |

## Archived V0 traces

All five V0 traces (`traces/archived-v0/`, hashes equal the V0 manifest) are **superseded**: they record the old
ordering (proposals logged and server started after UPTODATE). Replay of two of them against the
updated model stops exactly at that ordering:

- ../traces/archived-v0/follower-diff.ndjson: exit 13 (spec/output/trace-validation/archived/v0-follower-diff.log)
- ../traces/archived-v0/quorum-startup-mutation-shutdown.ndjson: exit 13 (spec/output/trace-validation/archived/v0-quorum-startup-mutation-shutdown.log)

## Update coverage

| Affected/interaction action | Fresh trace evidence | Compared fields |
|---|---|---|
| LearnerProposal | follower-diff, follower-snap, update-*, diff-sync, leader-abandon | buffer sizes post-state |
| LearnerCommit (incl. NPE branch) | follower-diff, follower-snap, update-commit-after-newleader (NPE), diff-sync | buffer sizes pre-state; NPE branch -> FollowerException |
| LearnerNewLeader | all sync traces | currentEpoch' |
| LearnerStartupWithoutServing | all sync traces | syncMode NONE before ACK; tree zxid |
| LearnerLogPending | follower-diff, update-newleader-ack-durability, diff-sync | head of pnc, queued' |
| LearnerAckNewLeader | all sync traces | pending=0, committed=Len(pcm) |
| LearnerUpToDate | all completing syncs | applied' (tree zxid) |
| LearnerLogAfterUpToDate / LearnerCommitAfterUpToDate | follower-snap, follower-diff | queued'/committed' |
| INITIAL-state exit (ExitHist, no fast-forward) | update-diff-sync-consistency (SocketTimeoutException at UPTODATE) | tree zxid at LOOKING (negative check proves non-vacuous) |
| In-JVM restart (DatabaseLoaded) | diff-sync, leader-abandon, quorum | recovered' |

Not observed in fresh traces (no Trace predicate credited): leader-side LearnerHandler packet production
(`SelectSync` stream contents, `LeaderQueueNewLeader`, `LeaderQueueUpToDate`, `LeaderReceiveNewLeaderAck`) — packets are
supplied by `TraceDeliverPacket`; TRUNC mode; crash (process kill) — covered by model checking only.

Validation changed semantic spec files: Trace.tla/Trace.cfg and harness only; base.tla/MC.tla/Update.tla were not changed by validation (see `spec/changelog.md` Round 1).
