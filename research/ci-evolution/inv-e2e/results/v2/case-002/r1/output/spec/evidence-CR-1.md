# CR-1: COMMIT of a pre-NEWLEADER proposal after NEWLEADER crashes the learner (NPE)

Source: code review of the update + direct code observation (no model
counterexample: the reference synchronizes only with a leader in its
SYNCHRONIZATION phase, so a late join with outstanding proposals is outside the
model's sync scope).

## Mechanism (updated source)

- `Learner.syncWithLeader` NEWLEADER branch now ends with
  `packetsNotCommitted.clear()` (new-source Learner.java:757) before
  ACK(NEWLEADER).
- The COMMIT case still dereferences the buffer head unconditionally:
  `pif = packetsNotCommitted.peekFirst(); if (pif.hdr.getZxid() == qp.getZxid() && ...)`
  (Learner.java:643-646).
- Legal leader packet order for a learner joining an ESTABLISHED leader:
  `LearnerHandler.syncFollower` -> `Leader.startForwarding` queues the
  outstanding proposals (PROPOSAL only, Leader.java:1308-1317) and registers
  the handler as a forwarding follower BEFORE `NEWLEADER` is queued
  (LearnerHandler.java:591-605, 920); UPTODATE is queued only after the handler has
  read the NEWLEADER ACK (LearnerHandler.java:613-648). A `Leader.commit` of an
  outstanding proposal in that window reaches the learner after NEWLEADER and
  before UPTODATE.
- With no newer PROPOSAL in between, `peekFirst()` returns null -> NPE ->
  `Follower.followLeader` catches it, closes the socket, the learner returns to
  LOOKING (and, per MC-2, its started processors leak). Under sustained write
  load a restarting learner can fail to rejoin repeatedly.

## Observation (real code)

Test: `artifact/zookeeper-server/src/test/java/org/apache/zookeeper/server/quorum/SpeculaUpdateObservationTest.java#commitOfStreamedProposalAfterNewLeader`
(follower conversation; packets DIFF, PROPOSAL 0x100000002, NEWLEADER, read
ACK, COMMIT 0x100000002, UPTODATE).

Command (from `harness/run.sh`):
`JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64 timeout 300s mvn -B -pl zookeeper-server -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip -Dspecula.trace.file=/work/current/.specula-output/traces/update-observe-commit-after-newleader.ndjson -Dspecula.trace.scenario=update-observe-commit-after-newleader -DfailIfNoTests=false -Dtest=SpeculaUpdateObservationTest#commitOfStreamedProposalAfterNewLeader test`

Updated source (artifact commit `update`):
- `traces/update-observe-commit-after-newleader.ndjson.observation.json`:
  `"outcome":"follower-dropped-connection:EOFException"`,
  `"followerLastProcessedZxid":"0x0"`, `"outstandingApplied":false`.
- `spec/output/update/surefire/org.apache.zookeeper.server.quorum.SpeculaUpdateObservationTest-output.txt`:
  `java.lang.NullPointerException: Cannot read field "hdr" because "pif" is null
  at org.apache.zookeeper.server.quorum.Learner.syncWithLeader(Learner.java:655)`
  (instrumented line; new-source line 646).
- Trace: the last learner event is `SyncCommitReceived` with `detail.pending=0`
  immediately after `NewLeaderAckSent` (logged=1); the leaked `SyncThread:0`
  still appends/fsyncs and ACKs 0x100000002 afterwards.

Exact-old control (same test, `old-control/tree` = `git archive baseline`,
`old-control/run-old-control.sh`):
- `old-control/old-commitOfStreamedProposalAfterNewLeader.observation.json`:
  `"outcome":"follower-acknowledged-uptodate"`, `"followerLastProcessedZxid":"0x100000002"`,
  `"outstandingApplied":true`; no NullPointerException in
  `old-control/old-commitOfStreamedProposalAfterNewLeader-surefire-output.txt`.

Attribution: introduced by the update (the `clear()` added at NEWLEADER).
Severity: Medium (availability; the learner cannot complete synchronization,
and the abort triggers MC-2's INITIAL-state shutdown path).
