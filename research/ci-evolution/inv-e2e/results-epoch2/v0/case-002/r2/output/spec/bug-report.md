# Bug Report — Apache ZooKeeper Zab, incremental run incr-13b3a238967b (updated source 2efbdfc)

## Summary

- Update Scenarios tested: U-DUR, U-ACK, U-NPE, U-SPLIT (+ U-LEAK code review)
- Model-checking bugs found: 3 (MC-1, MC-2, MC-3)
- Configs producing counterexamples: Update-focused-durability.cfg,
  Update-open.cfg, Update-focused.cfg (ack order), Update-hunt-ackorder.cfg (full
  MCNext, simulation), Update-hunt-npe.cfg (full MCNext, simulation),
  TraceOracle.cfg (reference behaviors replaying real traces)
- All exploration is budget-limited (LIMITED_COVERAGE); no exhaustive pass is claimed.

## Bug 1: NEWLEADER quorum commits a DIFF history that the acknowledging learners have only enqueued

- **Scenario**: U-DUR
- **Severity**: Critical
- **Invariant violated**: `CommittedQuorumDurable` (UpdateProps.tla)
- **Config**: `Update-focused-durability.cfg` (concrete focused), `Update-open.cfg`;
  full-reference admission: `TraceOracle.cfg` on `traces/diff-sync-uncommitted.ndjson`
- **Counterexample**: 10 states, `spec/output/update-focused-durability-bfs.log`
  (also `spec/output/update-open-bfs.log`); real-trace reference behavior:
  `spec/output/trace-oracle-diff-sync-uncommitted.log` (violation at event 114)

### Trace Summary

1. Seeded epoch-2 window: leader s1 has epoch-1 entry t1 forced (uncommitted),
   learner s2 does not; both registered for epoch 2.
2. `LeaderSyncFollower(s1,s2,DIFF)` queues DIFF, PROPOSAL(t1), COMMIT(t1);
   `LeaderSendNewLeader` queues NEWLEADER.
3. s2 consumes DIFF, PROPOSAL, COMMIT (deferred: writeToTxnLog), then
   `LearnerNewLeader(s2)`: currentEpoch := 2 (persisted), pipeline started,
   t1 *enqueued* (queued) — not appended, not forced.
4. `LearnerAckNewLeader(s2)`; `LeaderReadNewLeaderAck(s1,s2)` counts it;
   `LeaderBroadcast(s1)` commits the initial history <<t1>> (NEWLEADER quorum
   {s1,s2}) and serves it.
5. Final state: t1 committed (globalCommitted) but durable only at s1.

The real execution `diff-sync-uncommitted` shows the same window: s1 writes the
NEWLEADER ACK (seq 108), the leader reads it (110) and is broadcasting (115)
while s1 forces (1,2) only at seq 118.

### Root Cause

`Learner.syncWithLeader` (updated, `Learner.java:743-760`) persists
`currentEpoch` and calls `fzk.logRequest` for the buffered proposals, but
`FollowerZooKeeperServer.logRequest` (`:80-89`) only enqueues to the
SyncRequestProcessor; the NEWLEADER ACK is written immediately
(`Learner.java:760`), before `SyncRequestProcessor.flush` (`:227-252`) forces
anything.  The leader then treats the NEWLEADER quorum as the commit of its
initial history (`Leader.lead:663-712`).  A learner crash in that window loses
the entries, and because FLE ranks `currentEpoch` first
(`FastLeaderElection.totalOrderPredicate`), such a learner can win the next
election and truncate the committed entries everywhere.

### Affected Code

- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743-760`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/FollowerZooKeeperServer.java:80-89`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/SyncRequestProcessor.java:227-252`
- `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Leader.java:663-712`

### Recommendation

At NEWLEADER, append and force (`ZKDatabase.append` + `commit`) the buffered
proposals synchronously before persisting `currentEpoch` and before writing the
NEWLEADER ACK (and only then hand them to the commit path), or make the ACK wait
for the SyncRequestProcessor flush of those entries.

---

## Bug 2: SyncRequestProcessor ACK written before the NEWLEADER ACK is consumed as the NEWLEADER ACK

- **Scenario**: U-ACK
- **Severity**: High
- **Invariant violated**: `NewLeaderAckFirst`
- **Config**: `Update-focused.cfg` / `Update-focused-ackorder.cfg` (focused BFS),
  `Update-hunt-ackorder.cfg` (full MCNext, simulation)
- **Counterexample**: 10 states `spec/output/update-focused-bfs.log`; 58 states
  full model `spec/output/update-hunt-ackorder-sim.log`

### Trace Summary

Focused: DIFF sync with one entry; `LearnerNewLeader(s2)` enqueues it and starts
the pipeline; `AppendOne(s2)`, `FsyncOne(s2)` write ACK(t1) on the learner
stream; `LeaderReadNewLeaderAck(s1,s2)` reads ACK(t1) as the NEWLEADER ACK and
does not count s2.  Full model: the same with an established leader whose
forwarded outstanding proposals are logged at NEWLEADER; the swallowed ACK is a
proposal ACK the leader never counts.

### Root Cause

`zk.startupWithoutServing()` (`Learner.java:751`) starts
SyncRequestProcessor -> SendAckRequestProcessor before the learner thread writes
the NEWLEADER ACK (`:760`) on the same stream.  `LearnerHandler.run:609-623`
reads the first packet after NEWLEADER and hands any ACK to
`Leader.waitForNewLeaderAck:1547-1588`, which logs "different epoch" and returns
without counting it.  The real NEWLEADER ACK later reaches `processAck`, which
ignores zero-counter zxids.  Epoch establishment can then time out; for an
established leader the proposal ACK is lost.

### Affected Code

- `.../quorum/Learner.java:751-760`
- `.../quorum/SendAckRequestProcessor.java:40-59`
- `.../quorum/LearnerHandler.java:609-623`
- `.../quorum/Leader.java:1547-1588`

### Recommendation

Write the NEWLEADER ACK before starting the pipeline / before any proposal can
be acknowledged (or defer SendAckRequestProcessor output until after the
NEWLEADER ACK), or make the leader skip proposal ACKs while waiting for the
NEWLEADER ACK.

---

## Bug 3: COMMIT received after NEWLEADER for a proposal buffered before it throws NullPointerException

- **Scenario**: U-NPE
- **Severity**: High
- **Invariant violated**: `SyncCommitHasPendingProposal`
- **Config**: `Update-hunt-npe.cfg` (full MCNext, simulation); also
  `TraceOracle.cfg` on `traces/diff-commit-after-newleader.ndjson`
- **Counterexample**: 60 states, `spec/output/update-hunt-npe-sim.log`

### Trace Summary

Leader s3 establishes epoch 2 (s1 via SNAP), broadcasts and proposes t2, t1.
Learner s2's handler registered for forwarding earlier (`LeaderSyncFollower(s3,s2,DIFF)`),
so PROPOSAL(t2), PROPOSAL(t1) precede NEWLEADER on s2's stream; COMMIT(t2)
follows NEWLEADER.  s2 buffers both proposals, `LearnerNewLeader(s2)` logs and
clears the buffer, then `LearnerSyncCommit(s2)` finds the buffer empty.

### Root Cause

The update adds `packetsNotCommitted.clear()` (`Learner.java:757`) while the
unchanged COMMIT case still does `pif = packetsNotCommitted.peekFirst();
pif.hdr.getZxid()` (`:645-646`) without a null check.  Leader.startForwarding
legitimately queues outstanding PROPOSALs before NEWLEADER and their COMMITs
after it.

### Affected Code

- `.../quorum/Learner.java:643-669`, `:757`

### Recommendation

Do not clear the buffer, or keep the logged proposals available for matching
commits (null-check `pif` and fall through to `packetsCommitted.add` when
`writeToTxnLog`).

---

## Not Reproduced / budget-limited runs

| Scenario / property | Config | States explored | Result |
|---|---|---|---|
| Reference properties (standard convergence) | MC.cfg | BFS depth 28, 16.9M distinct (4.56M queued); simulation 102.5M states / 1.72M traces | no violation within budget (LIMITED_COVERAGE) |
| All update properties over complete MCNext | Update-full.cfg | BFS depth 28, 17.5M distinct (4.75M queued) | no violation within BFS budget; simulation follow-up found NewLeaderAckFirst (Bug 2) |
| U-SPLIT `DeferredCommitMatchesPending` | Update-focused-split.cfg; Update-hunt-split.cfg; Update-open-split.cfg | focused BFS depth 29 (9.1M distinct); full sim 13.9M states; open BFS depth 24 (39.9M distinct) | no violation within budget (LIMITED_COVERAGE) |
| Reference properties, focused window | Update-focused-reference.cfg | BFS depth 29, 9.2M distinct | no violation within budget |
| Data-loss consequence `CommittedAgreement` | Update-seeded-agreement.cfg (complete MCNext from seeded states) | simulation 29.5M states / 672k traces | not reached within budget; consequence reproduced in the implementation (Bug 1, `confirmation-MC-1.md`) |
| Discharge of the open rely | Update-discharge.cfg | BFS depth 22, 11.7M distinct | no violation within budget (after the rely frame fix) |

Full campaign table: `model-checking-campaign.md`.

## Spec adjustments during hunting

- Update.tla `EnvJoin` frame fixed (ghost `rollbackAuthorized`); reference
  unchanged.  No invariant was weakened.
