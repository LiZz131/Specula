# V1 validation handoff (Validation 4)

- Source: `artifact/` commit `2efbdfc` ("update"), clean; old revision `1414ebf`
  ("baseline") used only for controls (`harness/old-control-source/`).
- Harness command: `timeout 7200s harness/run.sh` (rebased V0 patch + V1 probes;
  JDK 11; per-scenario outer timeouts). Patch dry-run on pristine artifact:
  `spec/output/incremental/harness/patch-dry-run.log` (exit 0).
- Fresh new-version conformance traces (13; all pass `Trace.cfg` with
  `TraceMatched`, records+1 states): follower-snap, follower-diff,
  quorum-startup-mutation-shutdown, leader-abandon-restart-recovery,
  diff-sync-uptodate-failure, follower-diff-bulk-r1..r3,
  repro-u4-no-restart-r1..r3, control-diffsync-leaderwait-r1..r2
  (`spec/output/incremental/runs/final-tv-*.log`; inventory
  `spec/output/incremental/trace-inventory.json`).
- Fault-injected reproduction traces (3, not in the conformance suite):
  `traces/fault-injected-repro/repro-u1-stalled-log-r1..r3.ndjson`.
- Archived V0 traces (5): superseded — each stops at the first event that
  requires the V1 NEWLEADER-ACK probes (`final-archived-*.log`).
- Negative checks (5): rejected at the mutated event (`final-neg*.log`).
- Affected/interaction coverage observed in fresh traces:
  `FollowerProcessNewLeader` (DIFF with logged txns, SNAP, nothing logged),
  `FollowerSendNewLeaderAck`, `LeaderProcessNewLeaderAck` (counted,
  counted-quorum, after-quorum), `LeaderBroadcast` gate, `FollowerProcessUpToDate`,
  `BeginElection` INITIAL exit (`ShutdownSkipped(INITIAL)`, leaked flush, stale
  in-memory vote), `FsyncOne`/`TxnAckSent` after the NEWLEADER ACK.
  Not observed (environment/timing): `rejected-zxid-mismatch` (U3); TRUNC sync;
  learner process crash (emulated only by the stalled-disk reproduction).
- Required update fields compared by active Trace predicates:
  `NewLeaderAckSent.update.{queued*, loggedAtNewLeader, durable*, serverState}`,
  `NewLeaderAckReceived.update.{fromSid, disposition}`,
  `ShutdownSkipped.update.serverState`.
- Semantic spec files changed during validation: `Trace.tla` (interpretation
  repairs listed in `spec/changelog.md`), `Trace.cfg` (MaxEpoch 4). `base.tla`
  changed during checking only by the `Crash` vote-tally repair (before the
  final campaign); no validation result predates that change except the
  round-1 logs kept under `spec/output/incremental/runs-round1/`.
