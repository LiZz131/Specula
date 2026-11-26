# Confirmation CR-4 (ledger D-5) — learner failing between NEWLEADER and UPTODATE leaks its processors

- **Source**: Code Review (no MC property; the model represents only its
  history effect: no drain at role exit for an INITIAL learner)
- **Novelty**: not searched (blind run: issue/history research prohibited)
- **Status**: REPRODUCED
- **Severity**: Medium (threads/processors leak on every failed synchronization;
  the in-memory data tree is not fast-forwarded, so the peer votes and later
  leads with a stale last zxid; the orphaned SyncThread keeps writing the shared
  log and writes ACKs to a closed connection)
- **Update attribution**: introduced by the update (old-tree control passes).
- **Location**: `ZooKeeperServer.java:784-786` (`canShutdown()` only RUNNING or
  ERROR) with `quorum/Learner.java:751` (`startupWithoutServing()` leaves INITIAL)
  and `quorum/LearnerZooKeeperServer.java:155-173`.

## Investigation

After NEWLEADER the learner's ZooKeeperServer is started but INITIAL.  Any
failure before `startServing()` (`Learner.java:767`) — socket error, timeout,
or MC-3's NPE — goes through `Follower.followLeader` catch and
`QuorumPeer.run` -> `follower.shutdown()` -> `zk.shutdown()`, which returns
immediately because `canShutdown()` is false: SyncRequestProcessor,
CommitProcessor (+ workers), FollowerRequestProcessor, RequestThrottler and the
session tracker are not stopped, and `zkDb.fastForwardDataBase()` is skipped.
Trace evidence: `traces/diff-sync-uncommitted.ndjson` seq 116-119 (role exit,
then the orphaned SyncThread forces (1,2) and writes an ACK), seq 131 (the peer
then reports data-tree zxid (1,1) while its log has (1,2)).

## Reproduction

`harness/repro/test_bugCR-4_initial_shutdown_leak.sh` — Level 0 fixture: DIFF,
PROPOSAL, COMMIT, NEWLEADER, both ACKs read, connection closed before UPTODATE,
then `Follower.shutdown()` as QuorumPeer does.  New
(`spec/output/repro-leak-fixture-new-surefire-output.txt`):
```
SPECULAR-OBSERVATION after Follower.shutdown(): SyncThread alive=1 CommitProcessor alive=1 (before sync: 0) zk.isRunning=false
request-processor threads leaked after Follower.shutdown() ==> expected: <0> but was: <2>
```
Old control: `SyncThread alive=0 CommitProcessor alive=0`, passes.

An earlier run of the same fixture (closing the connection right after the
first ACK) showed a second effect: the orphaned SyncThread flushed after the
socket was closed, `SendAckRequestProcessor.flush` threw NullPointerException
(`learner.sock` null), and the thread died as a "Severe unrecoverable error"
(that run's log was overwritten when the fixture was tightened).

## Recommendation

Allow `shutdown()` from INITIAL once processors have been set up (e.g. track
"processors started"), or start the processors only after the NEWLEADER ACK
handling cannot fail.
