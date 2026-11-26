# Confirmation: CR-2 — processors started at NEWLEADER are not shut down if synchronization then fails

- **Source**: Code Review (no model counterexample; lifecycle/resource behaviour outside the model)
- **Novelty**: not determined (history/issue search prohibited by the blindness contract)
- **Status**: REPRODUCED (Level 0 observations in two real runs)
- **Severity**: Low (leaked request-processor threads; orphaned SyncThread keeps flushing/acking after its learner
  exited and dies with a critical-thread error; introduced by the update)
- **Location**: `zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java:751`
  (`zk.startupWithoutServing()`), `ZooKeeperServer.java:784-786` (`canShutdown()` false in INITIAL),
  `LearnerZooKeeperServer.java:155-159` (shutdown returns early)

## Description
`startupWithoutServing()` starts the session tracker, request processors (FollowerRequestProcessor, CommitProcessor
with its workers, SyncRequestProcessor/SyncThread) and RequestThrottler but leaves state INITIAL. If the learner fails
before `startServing()` (any exception between NEWLEADER and UPTODATE, e.g. CR-1 or a socket timeout), Follower
shutdown calls `LearnerZooKeeperServer.shutdown()`, which returns immediately because `canShutdown()` is false, so
none of these components is stopped. The next role creates new instances sharing the same `ZKDatabase`.

## Reproduction / observation
1. Update's own scenario (harness `diff-sync-consistency`, `DIFFSyncConsistencyTest` with its injected UPTODATE
   failure; log `spec/output/incr/repro/surefire/harness-diff-sync-consistency-DIFFSyncConsistencyTest-output.txt`,
   harness log `spec/output/incr/harness/harness-diff-sync-consistency.log`): myid 0 logs `shutdown Follower` at
   11:25:34.661 with no processor shutdown lines for that instance; at 11:25:34.700 its orphaned SyncThread logs
   `Severe unrecoverable error, from thread : SyncThread:0` (`NullPointerException ... "this.learner.sock" is null`
   in `SendAckRequestProcessor.flush`) and exits with error code 1; same for myid 1 at 11:25:34.713. Fresh trace
   `traces/fresh/diff-sync-consistency.ndjson` shows the orphan's `TxnDurable` (events 94-95) after the learners
   returned to LOOKING (events 85-86, 92-93).
2. CR-1 test on the updated tree (`spec/output/incr/repro/repro2-new-markers.txt`):
   `REPRO-CR2: learner zk state=follower; live request-processor threads 1.5s after the learner exited: 3 [CommitProcessor:0, FollowerRequestProcessor:0, RequestThrottler]`
   and the surefire output shows the same SyncThread critical error.
3. Old revision: request processors are started only after UPTODATE (`zk.startup()`), so a failure in this window
   starts nothing (code argument; old CR-1 control run completes normally).

## Recommendation
Allow shutdown from the INITIAL-but-started state (track "processors started"), or start the processors in a way
that the failure path always stops them.
