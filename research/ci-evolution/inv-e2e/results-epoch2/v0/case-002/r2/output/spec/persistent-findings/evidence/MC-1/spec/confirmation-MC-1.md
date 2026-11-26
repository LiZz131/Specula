# Confirmation MC-1 — NEWLEADER quorum commits a DIFF history the learners have only enqueued

- **Source**: MC (counterexamples: `spec/output/update-focused-durability-bfs.log`,
  `spec/output/update-open-bfs.log`; full-reference behavior replaying a real
  execution: `spec/output/trace-oracle-diff-sync-uncommitted.log`)
- **Novelty**: not searched (blind run: issue/advisory research prohibited).  The
  updated source states the intended contract at `quorum/Learner.java:748`
  ("make sure sync the uncommitted logs before commit them (ACK NEWLEADER)").
- **Status**: REPRODUCED
- **Severity**: Critical (a transaction served by the leader after the NEWLEADER
  quorum is lost cluster-wide)
- **Update attribution**: pre-existing mechanism, *not fixed* by the update.  The
  update moves the enqueue before the NEWLEADER ACK (so a graceful learner
  failure now persists the entries through the orphaned SyncThread — the
  update's own `DIFFSyncConsistencyTest` passes on the new tree, see
  `spec/output/harness-diff-sync-uncommitted.log`), but the ACK still precedes
  the force and `currentEpoch` is persisted before the entries.
- **Location**: `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743-760`;
  `quorum/FollowerZooKeeperServer.java:80-89` (logRequest only enqueues);
  `SyncRequestProcessor.java:227-252` (force happens later on another thread);
  `quorum/Leader.java:663-712` (NEWLEADER quorum starts serving the initial history).

## Investigation (Phase 1)

Code path: LearnerHandler DIFF -> learner buffers PROPOSAL/COMMIT (writeToTxnLog,
`Learner.java:614,656-669`) -> NEWLEADER: `setCurrentEpoch(newEpoch)` (`:743`,
file write), `zk.startupWithoutServing()` (`:751`), `fzk.logRequest` per buffered
proposal (`:752-756`, `pendingTxns.add` + `syncProcessor.processRequest`, no
wait), `writePacket(ACK(newLeaderZxid), true)` (`:760`).  The leader counts that
ACK (`LearnerHandler.run:609-623`, `Leader.waitForNewLeaderAck`) and starts
serving its loaded log as committed (`Leader.lead:663-712`).  Nothing between
`:752` and `:760` waits for `SyncRequestProcessor.flush` (`ZKDatabase.commit`).
Because `FastLeaderElection.totalOrderPredicate` ranks peerEpoch (currentEpoch)
before zxid, a learner that crashed in the window has the *new* epoch and a
*shorter* log, can be elected, and TRUNCs the committed entries on the others.
Real-execution evidence: `traces/diff-sync-uncommitted.ndjson` seq 108 (ACK
written), 110 (leader reads it), 115 (leader BROADCAST), 118 (entry (1,2) forced
at the learner).

## Reproduction (Phase 2)

Test: `harness/repro/test_bugMC-1_durability.sh` ->
`SpecularReproTest#testServedTxnSurvivesFollowerCrashAfterNewLeaderAck`
(`harness/src/SpecularReproTest.java`).  Escalation level: **1** (timing
assistance: the follower SyncThread start is delayed, no logic change) plus
crash emulation (the follower processes are killed after the NEWLEADER ACK; the
delayed SyncThread dies with them).  Setup = the update's own
`DIFFSyncConsistencyTest` phase 1 (leader logs `/zk2` while both followers are
down, is re-elected in a new epoch and DIFF-syncs it).

Command: `harness/repro/test_bugMC-1_durability.sh` (runs `harness/repro.sh
durability-cluster ... both`).  New tree log `spec/output/repro-durability-cluster-new.log`,
`spec/output/repro-durability-cluster-new-surefire-output.txt`:

```
SPECULAR-OBSERVATION old leader 2 serves /zk2: true; delayed follower SyncThreads=2
SPECULAR-OBSERVATION new leader 1 (epoch 3) sees /zk2: false
SpecularReproTest.testServedTxnSurvivesFollowerCrashAfterNewLeaderAck:332 Data inconsistency: /zk2 was served after the NEWLEADER quorum but is lost ==> expected: not <null>
Tests run: 1, Failures: 1, Errors: 0, Skipped: 0
```

The old leader served `/zk2` (so the NEWLEADER quorum committed it); after the
crash the new leader (epoch 3) does not have it.  Expected (Zab): a transaction
exposed after the NEWLEADER quorum survives the loss of the old leader.

Old-tree control (`spec/output/repro-durability-cluster-old*.txt|log`): same
failure (`delayed follower SyncThreads=0`: the old learner logs only after
UPTODATE), confirming the mechanism pre-dates the update.

Match with the counterexample: same Actions (DIFF sync, LearnerNewLeader enqueues,
LearnerAckNewLeader, LeaderReadNewLeaderAck, LeaderBroadcast, learner crash
before FsyncOne), same property (`CommittedQuorumDurable`), consequence of the
reference property `CommittedAgreement` (a different entry is committed at the
position after re-election).

## Recommendation

Force the buffered proposals to the transaction log synchronously at NEWLEADER
(append + commit) *before* `setCurrentEpoch` and before writing the NEWLEADER
ACK; or delay the ACK until the SyncRequestProcessor has flushed them.
