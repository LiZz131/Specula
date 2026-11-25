# Bug Report — Apache ZooKeeper Zab, revision `update` (case-002)

Source: neutral commit `update` (`2efbdfc3754df193bce05b9792297c813377cdaf`) in
`artifact/`. Paths below are relative to
`zookeeper-server/src/main/java/org/apache/zookeeper/server/`.

## Summary

- Scenarios tested: V0 S1-S4 (standard/hunt cfgs) and update Scenarios U1-U2 (U3 is code-review only)
- Model-checking findings: 2 (MC-1, MC-2), both on the path changed by the update
- Configs with counterexamples: `Update-hunt-diff-ack.cfg`, `Update-hunt-diff-ack-followup.cfg`,
  `evidence/witness-lost-commit/Phase1.cfg` + `Phase2.cfg` / `Phase2-crash.cfg`,
  `evidence/E3prefix-focus.cfg` (continuation of a validated real trace)
- Every counterexample step is an `MCNext` step (focused views are strict subsets of the
  complete reference). Campaign coverage and outcomes: `spec/output/mc/campaign-summary.md`.

## Bug 1: NEWLEADER ACK is written before the DIFF-synchronized transactions are durable (MC-1)

- **Scenario**: U-Scenario 1 (NEWLEADER ACK vs. durability of the DIFF payload)
- **Severity**: High
- **Invariant violated**: `UpdNewLeaderAckAfterDurable` (action property); consequences
  `UpdEstablishedHistoryDurableOnQuorum` and, with one fail-stop crash, `UpdLeaderCompleteness`
- **Config**: `Update-hunt-diff-ack.cfg` (2 servers, MaxEpoch 2), `Update-hunt-diff-ack-followup.cfg`;
  crash consequence `evidence/witness-lost-commit/Phase2-crash.cfg`
- **Counterexample**: 31 states `spec/output/mc/MC-1_counterexample_UpdNewLeaderAckAfterDurable.log`;
  34 states `spec/output/mc/MC-1_counterexample_UpdEstablishedHistoryDurableOnQuorum.log`;
  Init-rooted crash consequence = `MC-2_witness_phase1_Init_to_S.log` (34 states) followed by
  `MC-1_witness_phase2_crash_S_to_violation.log`.

### Trace Summary

1. Epoch 1: s1 is elected, s2 synchronizes (empty DIFF) and s1 activates.
2. s1 proposes t1 and forces it locally (s2 never receives it); both peers return to LOOKING.
   s1's RUNNING shutdown drains and fast-forwards, so s1's database holds t1.
3. Epoch 2: s1 (longest history) is re-elected. LearnerHandler selects DIFF for s2; s2 buffers
   t1 (`CompleteSync`), persists currentEpoch, clears the sync mode and starts its processors in
   State.INITIAL (`ClearSyncMode`), hands t1 to `logRequest` (`LogSyncProposal`, queued only)
   and writes the NEWLEADER ACK (`AckNewLeader`) while `durable[s2] = <<>>` (violation of
   `UpdNewLeaderAckAfterDurable`, state 31).
4. s1 counts the ACK and activates epoch 2 (`LeaderBroadcast`), committing and serving t1, while
   only s1 holds t1 durably (violation of `UpdEstablishedHistoryDurableOnQuorum`, state 34).
5. Crash consequence (Phase2-crash): s2 crashes before its SyncThread forces t1, restarts with an
   empty log, gets s3's vote (currentEpoch 2 > 0), activates epoch 3 with an empty history:
   t1, committed and visible in epoch 2, is lost (`UpdLeaderCompleteness`).

The same order is observed in the real implementation: all four fresh
`traces/follower-diff*.ndjson` runs log `ProposalQueued -> NewLeaderAckSent -> TxnAppended ->
TxnDurable`, and in `traces/diff-sync-uncommitted-log.ndjson` leader s2 enters BROADCAST
(seq 96) before either counted learner forces (1,2) (seq 101-102). Evaluated with TLC in
`spec/evidence/tlc-E1.log`, `tlc-E2.log`, `spec/output/trace/evidence-*.log`.

### Root Cause

`Learner.syncWithLeader` (NEWLEADER case, `quorum/Learner.java:748-760`) calls
`fzk.logRequest` for every buffered packet and then immediately writes the NEWLEADER ACK.
`FollowerZooKeeperServer.logRequest` (`quorum/FollowerZooKeeperServer.java:82-89`) only adds the
request to `pendingTxns` and enqueues it on the `SyncRequestProcessor`; the append
(`SyncRequestProcessor.java:181`) and the force (`SyncRequestProcessor.java:227-249`,
`ZKDatabase.commit`) run later on the SyncThread. Nothing waits for that flush. The leader
treats a NEWLEADER-ACK quorum as permission to activate and serve its whole history
(`quorum/Leader.java:660-712, 1547-1586`). The update's own comment states the intended
obligation ("make sure sync the uncommitted logs before commit them (ACK NEWLEADER)",
`Learner.java:748`), as do `zookeeperInternals.md:119, 194`.

### Affected Code

- `quorum/Learner.java:748-760`: logRequest loop followed by the NEWLEADER ACK without a flush barrier
- `quorum/FollowerZooKeeperServer.java:82-89`: logRequest only enqueues
- `server/SyncRequestProcessor.java:181, 227-249`: asynchronous append/force
- `quorum/Leader.java:1547-1586, 660-712`: activation on NEWLEADER-ACK quorum

### Recommendation

Make the NEWLEADER ACK conditional on durability of everything handed to `logRequest` before
it (e.g. flush/force the SyncRequestProcessor queue synchronously, or write the ACK from the
SyncRequestProcessor after the corresponding flush), and order it after the proposal ACKs.

---

## Bug 2: a learner that fails between NEWLEADER and UPTODATE keeps a stale in-memory database; a later leader activates without committed transactions (MC-2)

- **Scenario**: U-Scenario 2 (failure in the new INITIAL window)
- **Severity**: Critical (silent loss of an acknowledged, client-visible write; no crash needed)
- **Invariant violated**: `UpdLeaderCompleteness`
- **Config**: `evidence/witness-lost-commit/Phase1.cfg` then `Phase2.cfg` (Init-rooted);
  `evidence/E3prefix-focus.cfg` (continuation of the validated real trace state)
- **Counterexample**: `spec/output/mc/MC-2_witness_phase1_Init_to_S.log` (34 states) followed by
  `spec/output/mc/MC-2_witness_phase2_S_to_violation.log` (16 states);
  `spec/output/mc/MC-2_counterexample_UpdLeaderCompleteness_from_trace_prefix.log` (16 states from
  cursor 103 of `traces/diff-sync-uncommitted-log.ndjson`).

### Trace Summary

1. Phase 1 as in Bug 1 steps 1-4: epoch-2 leader s1 activates with t1 committed; learner s2 has
   ACKed NEWLEADER with t1 only queued and its server is in State.INITIAL.
2. s2 leaves `syncWithLeader` before UPTODATE (in the real test: socket timeout at UPTODATE).
   The update also makes this exit more likely without any injected fault: it moved
   `sock.setSoTimeout(self.tickTime * self.syncLimit)` in front of the NEWLEADER ACK
   (`quorum/Learner.java:749`; previously after UPTODATE), while the leader may wait up to
   `initLimit * tickTime` for its NEWLEADER quorum before UPTODATE is sent
   (`quorum/Leader.java:1575-1584`, `LearnerHandler.java:634-648`); an early-ACKing learner
   times out reading UPTODATE whenever the quorum takes longer than syncLimit ticks.
   `Follower.shutdown -> LearnerZooKeeperServer.shutdown` returns immediately because
   `canShutdown()` is false in INITIAL: the SyncRequestProcessor is not drained by the shutdown
   path and the database is not fast-forwarded. s2's leaked SyncThread may still force t1, but
   s2's in-memory database (vote zxid, leader history) does not contain it.
3. s2 and s3 elect s2 (s3 votes for currentEpoch 2 > 0; s1 is partitioned or still believes it
   leads epoch 2). `Leader.lead` does not reload an initialized database; s2 activates epoch 3
   with an empty history after s3's NEWLEADER ACK. t1, committed and served in epoch 2, is absent
   from the new leader's committed history.

Real-execution evidence: `traces/diff-sync-uncommitted-log.ndjson` seq 97-102 (s0/s1 go LOOKING
after NEWLEADER, then their SyncThreads force (1,2), while their peer probes keep reporting
lastLoggedZxid (1,1)); the first rebased run `traces/superseded-r1/diff-sync-uncommitted-log.ndjson`
seq 98 shows s1 actually elected LEADING with (1,1). The regression test passes only because it
restarts every peer, which reloads the database from disk.

### Root Cause

`zk.startupWithoutServing()` (new, `quorum/Learner.java:751`; `ZooKeeperServer.java:673-704`)
starts the request processors but leaves the server in State.INITIAL until UPTODATE
(`ZooKeeperServer.java:677-680`). On a failure in that window the shutdown path is skipped
(`ZooKeeperServer.java:784-786`, `quorum/LearnerZooKeeperServer.java:155-159`), so
`zkDb.fastForwardDataBase()` (`ZooKeeperServer.java:836-850`) never runs. Votes use
`QuorumPeer.getLastLoggedZxid()` = the in-memory lastProcessedZxid (`quorum/QuorumPeer.java:1257-1262`),
and a new leader serves its initialized in-memory database without reloading
(`quorum/Leader.java:592`, `ZooKeeperServer.loadData`). Combined with Bug 1 (the ACK that let the
old leader activate did not imply durability or in-memory installation), the committed history
is not carried into the next epoch.

### Affected Code

- `quorum/Learner.java:749-760`: syncLimit read timeout and processors (State.INITIAL) set before the ACK
- `server/ZooKeeperServer.java:673-704, 784-786, 803-850`: INITIAL state and skipped shutdown/fast-forward
- `quorum/LearnerZooKeeperServer.java:155-173`: early return from shutdown
- `quorum/QuorumPeer.java:1257-1262`; `quorum/Leader.java:592`: in-memory zxid used for votes and activation

### Recommendation

Ensure a learner that leaves after starting its processors still drains its SyncRequestProcessor
and fast-forwards (or reloads) its database before it votes or leads (e.g. allow shutdown from
INITIAL), in addition to making the NEWLEADER ACK durable (Bug 1).

---

## Code-review candidate (not a model-checking finding)

CR-1 (U-Scenario 3, liveness): the SyncThread started at NEWLEADER can write `ACK(zxid)` for a
DIFF proposal before the learner thread writes ACK(NEWLEADER); `LearnerHandler` treats the first
ACK as the NEWLEADER ACK (`LearnerHandler.java:610-623`) and `waitForNewLeaderAck` drops a
mismatched zxid without counting the learner (`Leader.java:1555-1563`). Not modeled; probe
`NewLeaderAckMismatch` never fired in the collected runs. Recorded in `modeling-brief.md`.

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| S1-S4 standard safety (final artifacts) | `MC.cfg` (`mc-standard-final`) | 33,727,671 distinct, depth 30 bound, 7,542,420 queued | no violation, budget-limited (LIMITED_COVERAGE) |
| S1-S4 standard safety (pre-repair) | `MC.cfg` (`mc-standard-r1`) | 56,514,298 distinct, depth 30, 6,141,983 queued | no violation, budget-limited |
| S1-S4 standard safety, simulation | `MC-sim.cfg` | 812,831 traces, depth 80 | no violation (simulation) |
| S1-S4, 2 servers, 1 epoch | `MC-small.cfg` | 65,480 distinct, exhausted (depth 39) | no violation |
| U1/U2 remaining properties, 2 servers, full MCNext | `Update-full-followup-2s.cfg` | 607,117 distinct, exhausted (depth 54) | no violation (MaxEpoch 2 cannot express U2) |
| U1/U2 remaining properties, 3 servers, full MCNext | `Update-full-followup.cfg` | 17,654,974 distinct, depth 27, queue open | no violation, budget-limited |
| same, concrete focus / open focus | `Update-focused-followup.cfg` / `Update-open-followup.cfg` | 17,494,415 (depth 28) / 17,421,253 (depth 19) distinct | no violation, budget-limited |
| discharge of EnvUpdate | `Update-discharge.cfg` | 13,830,742 distinct, depth 25 | no violation, budget-limited |
| full MCNext simulation (MaxEpoch 2 / 3) | `Update-full-followup-sim.cfg` / `Update-full-followup-e3-sim.cfg` | 98,497 / 53,357 traces | no violation (random walks did not reach the MC-2 path) |
| lost-commit scenario, simulation | `Update-hunt-lost-commit-sim.cfg` | 90,279 traces, depth 80 | no hit within budget; MC-2 witness obtained by the two-phase actor-restricted search |

Reachability canaries (all reached on the final artifacts): election, sync, apply, crash+restart
(`MC-hunt-*-final`), DIFF payload, sync-window logRequest, NEWLEADER ACK, ACK before durable,
UPTODATE, activation with history (`upd-canary-*-final`), later leader after a commit (MC-2
witness). Full table: `spec/output/mc/campaign-summary.md`.

## Spec fixes during checking

Recorded in `spec/changelog.md`: during the campaigns one Case-B repair was made
(`CompleteSync` TRUNC/SNAP certified prefix, exposed by a `PipelinePrefix` counterexample in
`upd-full-followup-2s-r1`); affected runs were stopped and rerun, the full trace regression
(r5, 8/8) passed, and both findings were re-derived on the repaired model. `Update.tla`'s
`EnvUpdate` was rewritten in constructive form and `ApplyOne` moved to the concrete interaction
set before the open/discharge runs that are reported.
