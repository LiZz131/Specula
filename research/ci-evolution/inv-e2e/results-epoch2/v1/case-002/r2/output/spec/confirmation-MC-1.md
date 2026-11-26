# Confirmation: MC-1 — NEWLEADER ACK sent before the DIFF-synchronized history is durable

- **Source**: MC (actual counterexamples `spec/output/incr/MC-1-U2-counterexample.out`,
  `spec/output/incr/MC-1-U3-counterexample.out`)
- **Novelty**: not determined — issue-tracker / history search is prohibited by this run's blindness contract.
  The supplied source names an earlier ticket in a comment (`Learner.java:748`) that motivated the update; this
  finding is the residual window that the update leaves open, not a re-report of the scenario its new test covers
  (that test only exercises an exception-driven failure after which the not-yet-shut-down SyncThread still flushes).
- **Status**: REPRODUCED (escalation Level 1 timing assistance + fail-stop crash at the counterexample step)
- **Severity**: High
- **Location**: `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:743-760`
- **Source revision**: `artifact/` HEAD 2efbdfc3754df193bce05b9792297c813377cdaf (neutral commit `update`)

## Description
At NEWLEADER the learner persists `currentEpoch`, hands buffered DIFF proposals to
`FollowerZooKeeperServer.logRequest` (enqueue only, `FollowerZooKeeperServer.java:82-89`) and immediately writes
the NEWLEADER ACK (`Learner.java:760`). SyncThread appends/fsyncs later (`SyncRequestProcessor.java:181-249`). The
leader counts the ACK (`Leader.java:1547-1575`), starts serving the history rebuilt from its log
(`Leader.java:593,688`). A crash of the acking follower inside the ACK→fsync window leaves it with the new epoch
but without the transactions; it can win the next election and truncate the old leader, losing a served txn.

## Phase 1: investigation (evidence)
- Code audit: no wait/flush between `logRequest` and `writePacket(ACK)` in the updated NEWLEADER branch; the
  SNAP/TRUNC branch persists its tree synchronously via `zk.takeSnapshot` (`:739-741`), so only buffered
  proposals (DIFF contents and forwarded outstanding proposals) are exposed.
- Developer intent (requirement evidence, not implementation): `Learner.java:748` "make sure sync the uncommitted
  logs before commit them (ACK NEWLEADER)"; `DIFFSyncConsistencyTest.java:124-131` (followers ACK NEWLEADER
  "which makes leader think she has the quorum support") and `:186-201` ("Data inconsistency detected",
  "violation of ZAB").
- Real-run observation without any injection: fresh trace `traces/fresh/diff-sync-consistency.ndjson` (the
  update's own test) — s0 `NewLeaderAckSent` event 82, leader BROADCAST event 84, s0 `TxnDurable` event 94.
- Model: counterexamples above; the seed is reached from `MCInit` by full `MCNext` (`spec/output/incr/canary-seed.log`).

## Phase 2: reproduction
Test: `harness/repro/NewLeaderAckDurabilityReproTest.java`, driver
`harness/repro/test_bug1_newleader_ack_durability.sh <label> <tree>` (copies the test into an uninstrumented
copy of the tree under `controls/repro-<label>/` (removed after the run; outputs preserved), runs
`mvn -B -pl zookeeper-server -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Dtest=NewLeaderAckDurabilityReproTest test`
under `timeout 600s`).

Scenario (real servers, real client API): 3 participants; the leader logs `create /zk<L>` while both followers are
down (same setup as the update's `DIFFSyncConsistencyTest`); followers restart and DIFF-sync it; at the instant a
follower has written its NEWLEADER ACK, its data directory is copied (fail-stop crash image); the leader then serves
`/zk<L>`; all servers stop; followers restart from their crash images without the old leader; the new leader is
asked for `/zk<L>`.

| Level | Tree | Command | Result |
|---|---|---|---|
| 0 (no delay) | updated `artifact/` | `SLOW_APPEND_MS=0 harness/repro/test_bug1_newleader_ack_durability.sh new-level0 artifact` | both followers: `NEWLEADER ACK written; ... durable at ACK = false`; consequence not observed because the image copy finished after SyncThread's flush (`spec/output/incr/repro/repro-new-level0-markers.txt`) |
| 1 (slow log device: 3 s delay in `ZKDatabase.append` of the follower) | updated `artifact/` | `harness/repro/test_bug1_newleader_ack_durability.sh new artifact` | **FAIL = bug triggered** (`repro-new.log`, `repro-new-markers.txt`) |
| control: old revision | `controls/old-pristine` (artifact with `1414ebf` versions of the 2 changed files; identical to `/work/old-source`) | `... old controls/old-pristine` | same failure (pre-existing; update narrowed, not closed, the window) (`repro-old.log`) |
| control: hypothetical flush-before-ACK | `controls/fixed-hypothetical` (`controls/fixed-hypothetical-control.patch`, not upstream code) | `... fixedctl controls/fixed-hypothetical` | PASS: `durable at ACK = true`, `/zk2` present after re-election (`repro-fixedctl.log`) |

Key output (updated tree, Level 1, `spec/output/incr/repro/repro-new-markers.txt`):
```
REPRO: leader 2 logged /zk2 as txn 0x100000002
REPRO: server 0 NEWLEADER ACK written; target txn 0x100000002 durable at ACK = false
REPRO: server 1 NEWLEADER ACK written; target txn 0x100000002 durable at ACK = false
REPRO: leader 2 serves /zk2 (NEWLEADER quorum formed)
REPRO: new leader 1 exists(/zk2) = null
AssertionFailedError: Data inconsistency: /zk2 was served by leader 2 after its NEWLEADER quorum, but is missing
after followers that ACKed NEWLEADER crashed (durable at ACK: false, false) and elected leader 1
```
Expected (correct) behaviour, shown by the flush-before-ACK control: `durable at ACK = true` and the new leader
returns a Stat for `/zk2`.

Match with the counterexample: same order (DIFF buffer → hand-off → NEWLEADER ACK → leader serves → follower crash
before fsync → re-election of a follower with the new epoch → txn missing), same violated property (U3), same code
path (`Learner.java:743-760`). As in the model counterexample, the new leader is one of the followers that ACKed
NEWLEADER and lost the txn; the test keeps the old leader down.

The crash image is the persistent state a fail-stop crash leaves at that instant: the delayed record is still
in the follower's process memory, and `currentEpoch`/`acceptedEpoch` files were already written
(`QuorumPeer.setCurrentEpoch` writes the file before the ACK).

## Attribution
Model: the old-behaviour control violates U3 in 21 steps without any crash (a learner that abandons the sync after its
ACK drops the buffered txn), while the update needs a crash inside the ACK->fsync window (22 steps).
Pre-existing defect (old revision fails the same test with an even wider window: hand-off only after UPTODATE);
the update moved the hand-off before the ACK but did not make the ACK wait for durability. It is therefore a
defect the update attempted to fix and left open.

## Recommendation
Before writing the NEWLEADER ACK, wait until the handed-off proposals have been appended and flushed (for example a
synchronous flush/wait on the follower's `SyncRequestProcessor`), or let the SyncThread emit the NEWLEADER ACK after
the flush. Consider persisting `currentEpoch` only after the synced history is durable.

Full JUnit outputs: `spec/output/incr/repro/surefire/repro-{new,new-level0,old,fixedctl}-*-output.txt`.
