# Confirmation CR-2: learner failure between NEWLEADER and UPTODATE leaks an INITIAL server

- **Source**: code review of the update (Chapter 3 Scenario U3), corroborated by
  the fresh real trace `traces/diff-sync-uncommitted-log.ndjson`. No model
  counterexample (the stale data-tree vote is outside the model's vocabulary:
  votes use `durable`).
- **Revision**: new `2efbdfc` (`repro/work-new`), old control `1414ebf` (`repro/work-old`).
- **Novelty**: NEW in this run's inputs (persistent findings lookup empty).
- **Status**: **REPRODUCED** (level 0/1: the failure injection is the one the
  update's own `DIFFSyncConsistencyTest` uses — a `SocketTimeoutException` after
  reading UPTODATE, emulating a network timeout; no system logic changed).
- **Severity**: Medium.

## Mechanism (updated source)

1. NEWLEADER: `zk.startupWithoutServing()` (`quorum/Learner.java:751`) starts the
   session tracker, request throttler, `FollowerRequestProcessor`,
   `CommitProcessor` and `SyncRequestProcessor` threads with state `INITIAL`
   (`ZooKeeperServer.java:673-704`, `quorum/FollowerZooKeeperServer.java:69-78`)
   and hands the DIFF proposals to the SyncRequestProcessor (`:752-757`).
2. Any failure before `zk.startServing()` (`:767`) — e.g. a read timeout on
   UPTODATE — leaves `Follower.followLeader`, and `QuorumPeer.run` calls
   `follower.shutdown()` → `Learner.shutdown` → `zk.shutdown()`.
3. `LearnerZooKeeperServer.shutdown` / `ZooKeeperServer.shutdown(boolean)`
   return immediately because `canShutdown()` is true only for RUNNING/ERROR
   (`quorum/LearnerZooKeeperServer.java:155-158`, `ZooKeeperServer.java:784-786, 803-807`).
   The processors are never stopped and `zkDb.fastForwardDataBase()` (`:845`)
   is skipped.
4. In the old code the processors were started only after UPTODATE, so the
   same failure left nothing running and nothing queued.

Consequences: (a) each failed sync attempt leaks the processor threads (and the
abandoned server object that they reference); (b) the leaked SyncThread keeps
appending/fsyncing the shared transaction log after the peer left the session;
(c) the peer's data tree is not fast-forwarded, so its election vote
(`QuorumPeer.getLastLoggedZxid`, data tree) understates its durable log.

## Evidence

Real trace (`traces/diff-sync-uncommitted-log.ndjson`, updated implementation):
event 86 s1 `NewLeaderAck`, 91-92 s1 back to LOOKING (injected UPTODATE
failure), **93 `SyncThread:1 TxnDurable (1,2)` after the peer left the
session**; 102-103 s1 `PeerRoleChanged leading` / `ElectionWon` with vote zxid
**(1,1)** although (1,2) is durable in its log. (Trace replay passes after the
data-tree interpretation fix, `spec/changelog.md` r2-r4.)

Reproduction: `repro/LearnerInitialStateLeakReproTest.java`, driver
`repro/test_bug2_learner_initial_state_leak.sh` (each Maven run under
`timeout 900s`). One follower misses a committed write (so it DIFF-syncs) and
then fails three consecutive NEWLEADER…UPTODATE windows; after it finally
follows again the test counts live processor threads of that peer.

| revision | runs | `CommitProcessor:<victim>` threads alive | result |
|---|---|---|---|
| new 2efbdfc | 2 | **4** (1 live session + 3 leaked) | FAIL `leaked CommitProcessor instances of abandoned learner servers: 4` |
| old 1414ebf | 1 | 1 | pass |

Output (`repro/logs/bug2-summary.log`):

```
which=new commit=2efbdfc run=1 mvn_exit=1 REPRO-OBSERVATION victim=0 failures_injected=3 sync_threads_before=0 sync_threads_after=1 commit_threads_after=4 ... peer_state=FOLLOWING  leaked CommitProcessor instances of abandoned learner servers: 4
which=old commit=1414ebf run=1 mvn_exit=0 REPRO-OBSERVATION victim=0 failures_injected=3 sync_threads_before=0 sync_threads_after=1 commit_threads_after=1 ... Tests run: 1, Failures: 0
```

The data-tree/log gap was not observable at the test's measurement point (the
peer had already re-synced and reloaded); it is evidenced by the real trace
above, not by this test.

Recommendation: shut down an INITIAL learner server whose processors were
started (e.g. let `canShutdown()` accept a started-but-not-serving state, or
track processor startup separately), so its processors stop and its database
is fast-forwarded/reloaded before the next election.
