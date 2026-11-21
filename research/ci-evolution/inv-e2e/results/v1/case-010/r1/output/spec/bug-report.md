# Bug Report — ZooKeeper Zab, incremental case-010 (`baseline` -> `update`)

All results are bounded TLC exploration of the final reference model (3 servers, `MaxTxn=2`, `MaxEpoch<=2`, at most 1 crash, 1-2 learner exits) and are evidence, not proof. Every finding below has a saved counterexample log in `spec/output/counterexamples/final/` and an attribution control that runs the same scenario with the exact-old `Learner.shutdown` semantics (`LearnerShutdownSemantics = "PRIOR"`).

## Summary

- Update Scenarios: UPD-1 (SNAP exit, the update's intended fix), UPD-2 (TRUNC sibling), UPD-3 (learner log processor no longer drained on exit).
- Findings: 3 (MC-1 introduced by the update; MC-2 and MC-3 pre-existing and not closed by the update).
- UPD-1 is **fixed** by the update in the model: `Update-hunt-snap.cfg` exhaustively explores the scenario (144,904 distinct states, depth 46) with no violation of any property, while the PRIOR control violates `ExitedLearnerMemoryBackedByLog` (depth 17) and `RecoverableHistoryComplete` (depth 25). The real old revision fails the update's own test (`testDiffSyncAfterSnap`: "node 0 should exist") and its trace reproduces a recovered log `[11]` missing txns 1-10; the new revision passes and recovers `[1..11]`.
- Configs: see `spec/output/verification-summary-update.md` for the complete campaign table.

## Bug 1: Learner exit no longer drains or stops the follower log processor (update-introduced)

- **ID**: MC-1
- **Scenario**: UPD-3
- **Severity**: Medium (deterministic thread leak; the data consequence needs a crash or log-reopen race after the exit)
- **Invariant violated**: `RecoverableHistoryComplete` (also `DurableReplayOrdered`, `RecoverableCommittedPrefix`)
- **Config**: `Update-hunt-leak-gap.cfg` (and `Update-hunt-trunc-gap.cfg`, `Update-hunt-leak-order.cfg`, `Update-hunt-leak-prefix.cfg`)
- **Counterexample**: `spec/output/counterexamples/final/MC-1_leaked-log-processor_committed-gap_UPDATED.log` (17 states), `MC-1_leaked-log-processor_unflushed-applied_committed-gap_UPDATED.log` (21 states), `MC-1_leaked-log-processor_replay-order_UPDATED.log`, `MC-1_leaked-log-processor_stale-before-committed_UPDATED.log`
- **Control**: `Update-control-prior-leak-gap.cfg` (PRIOR) explores the same scenario exhaustively (238,362 distinct states, depth 45) with no `RecoverableHistoryComplete` violation (`MC-1_control_PRIOR_no-committed-gap_exhaustive.log`).

### Trace Summary

Shortest variant (`...unflushed-applied_committed-gap_UPDATED.log`): leader s1 proposes txns 1 and 2; follower s3 receives 1, commits and applies it to its DataTree while its own WAL flush of 1 is still queued in its `SyncRequestProcessor`. s3's learner exits while serving (I/O error or leader socket failure). With the update, `Learner.shutdown` calls `zk.shutdown(false)`; the follower `SyncRequestProcessor` is not shut down, so txn 1 stays in a leaked queue, while the fast-forwarded in-memory baseline still contains txn 1 (it was applied). s3 re-joins; the leader sees s3's last zxid 1 in its committed log and sends DIFF; s3 logs and flushes txn 2. s3's recoverable log is now `<<2>>` without committed txn 1, and only the leaked thread can still write txn 1. If s3 crashes (or the leaked append fails) before that, restart replays `[2]`, `lastProcessedZxid` = 2, and the leader never re-sends txn 1: s3 permanently lacks a committed txn. Variant 2 (`...committed-gap_UPDATED.log`): the re-join is a TRUNC (leader committed but had not applied 1), the log is truncated, and the leaked thread later appends stale txn 2 into the truncated log (`<<2>>`, missing committed 1). Variants 3/4: a leaked stale record lands after the next lifecycle's records (`<<1,2,1>>`), so restart replay re-applies an old txn after a newer one.

Reproduction of the mechanism on real code (`harness/repro-mc1.sh`, `spec/confirmation-MC-1.md`): `SpeculaTraceScenarioTest#testServingLearnerExitStopsSyncProcessor` fails on the new revision (`{SyncThread:0=2, SyncThread:1=2}` after one learner exit) and passes on the old revision.

### Root Cause

`Learner.shutdown()` now calls `zk.shutdown(boolean)` (`Learner.java:864`). `ZooKeeperServer.shutdown(boolean)` (`ZooKeeperServer.java:803-858`) is not overridden by `LearnerZooKeeperServer`, whose `shutdown()` override (`LearnerZooKeeperServer.java:154-173`) is the only place that calls `syncProcessor.shutdown()` (`SyncRequestProcessor.java:251-270`: enqueue REQUEST_OF_DEATH, join, flush). The old call `zk.shutdown()` dispatched to that override, so the follower's queued writes were appended and fsynced before the learner exit returned. Now the `SyncRequestProcessor` thread (sharing the peer's `zkDb`/txn log) keeps running indefinitely after the exit, and `QuorumPeer.shutdown()` (`QuorumPeer.java:1538-1570`) likewise no longer drains it before `zkDb.close()`. The same bypass affects `ObserverZooKeeperServer.shutdown()` (`ObserverZooKeeperServer.java:131-140`).

Real-code observation (same probes, same test, both revisions): after one leader loss the new revision has two live `SyncThread:<sid>` threads per surviving follower and leaked threads survive `QuorumPeer` shutdown (`spec/output/harness/upd-serving-exit-v3.surefire-output.txt`: `after-leader-loss {SyncThread:0=2, SyncThread:1=2}`, `after-shutdown {SyncThread:0=2, SyncThread:1=1, SyncThread:2=1}`); the old revision has one per server and none after shutdown (`spec/output/harness/old-control-upd-serving-exit-org.apache.zookeeper.server.quorum.SpeculaTraceScenarioTest-output.txt`). The fresh trace `traces/upd-serving-exit-v3d.ndjson` records `LearnerShutdown` with `served=true, leakedNow=true`; the old-revision trace records `leakedNow=false`.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:860-865`: new `zk.shutdown(self.getSyncMode().equals(SNAP))` call (bypasses the subclass override).
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/LearnerZooKeeperServer.java:154-173`: `shutdown()` override that stops `syncProcessor`; no `shutdown(boolean)` override.
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/ZooKeeperServer.java:803-858`: `shutdown(boolean)` (fast-forward before any drain; no processor shutdown for learners).
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:156-270`: leaked thread keeps appending to the shared log.

### Recommendation

Make the learner shutdown path stop and drain the learner's `SyncRequestProcessor` for both values of `fullyShutDown` (e.g. override `shutdown(boolean)` in `LearnerZooKeeperServer`/`ObserverZooKeeperServer`, or keep calling `shutdown()` and perform the SNAP clear separately), and drain before fast-forwarding so the in-memory baseline and the log agree.

---

## Bug 2: TRUNC-mode learner exit before NEWLEADER keeps an unpersisted in-memory image (pre-existing; not covered by the update)

- **ID**: MC-2
- **Scenario**: UPD-2
- **Severity**: Medium (requires TRUNC followed by in-sync COMMIT and a learner failure before NEWLEADER)
- **Invariant violated**: `ExitedLearnerMemoryBackedByLog`, `RecoverableHistoryComplete`
- **Config**: `Update-hunt-trunc-noleak.cfg`, `Update-hunt-trunc-noleak-gap.cfg` (UPDATED); controls `Update-control-prior-trunc.cfg`, `Update-control-prior-trunc-noleak-gap.cfg` (PRIOR) violate the same properties.
- **Counterexample**: `MC-2_trunc-exit_unpersisted-memory_UPDATED_noleak.log` (17 states), `MC-2_trunc-exit_committed-gap_UPDATED_noleak.log` (26 states); PRIOR: `MC-2_control_PRIOR_trunc-exit_committed-gap_noleak.log` (25 states).

### Trace Summary

Follower s2 logs and ACKs txn 1, then crashes and restarts (log `<<1>>`). Leader s1 has committed txn 1 but not yet applied it, so s2's last zxid is above `maxCommittedLog`: the leader sends TRUNC to 0 and then PROPOSAL+COMMIT for txn 1 from `toBeApplied`. s2 truncates its log, applies txn 1 directly to memory (TRUNC keeps `writeToTxnLog=false` until NEWLEADER) and fails before NEWLEADER. `syncMode` is TRUNC, so the update's guard does not clear the database; s2 re-joins with in-memory last zxid 1, receives DIFF, logs txn 2, and its recoverable log is `<<2>>` without committed txn 1.

### Root Cause

Both SNAP and TRUNC defer persistence of the sync image to the NEWLEADER snapshot (`Learner.java:553-555`, `611-614`, `656-665`, `739-741`), but the update clears the database only for SNAP (`Learner.java:864`). TRUNC followed by in-sync COMMITs is sent when the peer is ahead of the leader's committed log and the leader has committed-but-unapplied proposals (`LearnerHandler.java:852-857`; `Leader.java:1292-1302`).

### Affected Code

- `Learner.java:587-598,656-665` (TRUNC branch and in-memory apply), `Learner.java:864` (SNAP-only guard).

### Recommendation

Treat any sync that applied records in memory before the NEWLEADER snapshot (`snapshotNeeded` true: SNAP or TRUNC) as requiring a full shutdown/clear on exit.

---

## Bug 3: Fast-forward before drain leaves re-sent or stale records ahead of committed history in a follower log (pre-existing)

- **ID**: MC-3
- **Scenario**: UPD-3 (attribution control)
- **Severity**: Medium (crash-window dependent in the old revision)
- **Invariant violated**: `DurableReplayOrdered`, `RecoverableCommittedPrefix`
- **Config**: `Update-control-prior-leak.cfg`, `Update-control-prior-leak-prefix.cfg` (PRIOR); the same properties are violated under UPDATED (MC-1 variants).
- **Counterexample**: `MC-3_PRIOR_drain-after-fastforward_replay-order.log` (15 states), `MC-3_PRIOR_drain-after-fastforward_stale-before-committed.log` (18 states).

### Trace Summary

Follower s2 has txns 1 and 2 queued and unflushed when its learner exits while serving. In the old revision `LearnerZooKeeperServer.shutdown()` first fast-forwards the DataTree from the log (txns 1 and 2 not yet on disk) and only then drains the queue, so 1 and 2 reach the log but not memory. s2 re-joins with an older baseline, the leader re-sends txn 1 and s2 appends it again: the log becomes `<<1,2,1>>` while txn 2 is not yet committed. A crash in this window replays txn 1 after txn 2 (restoring older state with `lastProcessedZxid` = 2), or keeps a never-committed record before committed ones if txn 2 is later lost.

### Root Cause

`LearnerZooKeeperServer.shutdown()` calls `super.shutdown()` (which fast-forwards, `ZooKeeperServer.java:841-852`) before `syncProcessor.shutdown()` (`LearnerZooKeeperServer.java:161-170`); restart replay applies every later WAL record in file order (`FileTxnSnapLog.java:317-368`).

### Affected Code

- `LearnerZooKeeperServer.java:154-173`, `ZooKeeperServer.java:841-852`, `FileTxnSnapLog.java:317-368`.

### Recommendation

Drain the learner log processor before fast-forwarding the database, so the advertised baseline includes every record written by the old lifecycle.

---

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| UPD-1 SNAP exit (UPDATED) | `Update-hunt-snap.cfg` | 144,904 distinct, depth 46 (complete) | no violation (all properties) |
| Standard core | `MC.cfg` | 65,206 distinct, depth 46 (complete) | no violation |
| Inherited recovery/snapshot schedules | `MC-recovery-complete.cfg`, `MC-snapshot-complete.cfg` | 25,240 / 744 distinct (complete) | no violation |
| Full / residual / open / discharge | see `spec/output/verification-summary-update.md` | budget-limited | no violation beyond MC-1..MC-3 classes (LIMITED_COVERAGE) |

Independent observation (not pursued, pre-existing, outside the update): the TRUNC-to-`maxCommittedLog` path truncates a record that the follower already ACKed and that may count toward the commit quorum while the leader has not yet applied it, temporarily reducing the number of durable copies of a committed txn (visible in the MC-2 counterexample, steps 8-16).
