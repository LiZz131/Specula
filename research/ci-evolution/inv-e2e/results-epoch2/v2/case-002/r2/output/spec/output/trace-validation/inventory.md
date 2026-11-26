# Fresh trace inventory (updated implementation 2efbdfc)

Harness: `harness/run.sh` (SPECULAR_REUSE_WORK_SOURCE=1), patch `harness/patches/instrumentation.patch`; run log `spec/output/harness-run-2.log`, summary `spec/output/harness-summary.log`.
Final replay: round r9 of `spec/run-trace-validation.sh` (re-run on the final model; r7 was the initial gate) (Trace.tla/Trace.cfg, TraceMatched + 8 invariants), logs `spec/output/trace-validation/r9/`.

| trace | events | sha256 | r9 TLC result | update events (count) |
|---|---:|---|---|---|
| `traces/diff-sync-uncommitted-log.ndjson` | 136 | `f54e6436c74ffae9…` | pass (137 states, depth 137, 0 queued) | SyncProposalBuffered:2, SyncCommitBuffered:2, NewLeaderAck:5, NewLeaderAckCounted:6 |
| `traces/follower-diff.ndjson` | 18 | `f68a0e44d184b377…` | pass (19 states, depth 19, 0 queued) | SyncProposalBuffered:1, SyncCommitBuffered:1, NewLeaderAck:1 |
| `traces/follower-snap.ndjson` | 19 | `268d50200329f113…` | pass (20 states, depth 20, 0 queued) | SyncProposalBuffered:1, SyncCommitBuffered:1, NewLeaderAck:1 |
| `traces/leader-abandon-restart-recovery.ndjson` | 277 | `8949f2fdb5e83b7a…` | pass (278 states, depth 278, 0 queued) | NewLeaderAck:6, NewLeaderAckCounted:6 |
| `traces/quorum-startup-mutation-shutdown.ndjson` | 74 | `79a1e472bd889d48…` | pass (75 states, depth 75, 0 queued) | NewLeaderAck:1, NewLeaderAckCounted:2 |

Archived V0 (old-implementation) traces are kept unchanged under `traces/archived-v0/` and are superseded by the fresh traces of the same scenarios (the V0 `BroadcastReady` probe point no longer exists in the updated source; V0 traces lack `event.peer`). `traces/run1-superseded/` holds the first fresh run whose `NewLeaderAckSent` probe was emitted after the ACK write (moved before the write for a race-free leader/learner order).

Negative mutations (must be rejected): `spec/evidence/trace-mutations/M1..M4`, logs `spec/output/trace-validation/negative/` (second run, after the r7 ack-set fix): M1 V0-style logging after UPTODATE → rejected at `NewLeaderAck`; M2 sync mode not reset before ACK → rejected at `NewLeaderAck`; M3 ack counted without learner ACK → rejected at `NewLeaderAckCounted`; M4 leader broadcast without ack quorum → rejected at `PhaseChanged`.

Implementation witness (not a conformance check): `TraceUpdate.cfg` evaluates `Update!CommittedQuorumDurable` on replayed states; violated at state 91 of `diff-sync-uncommitted-log` (leader serves (1,2) durable only on itself). The two Zab1_0Test fixture traces also report it because the scripted fixture leader has no durable history in the trace — not evidence.
