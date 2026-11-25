# Confirmation MC-2 — INITIAL-state shutdown skipped; stale in-memory DB votes and leads

- Status: **REPRODUCED** (no fault injection beyond the update test's own UPTODATE read failure)
- Source revision: commit 2efbdfc ("update"); old control: commit 1414ebf ("baseline").
- Model: `spec/output/cex/MC-2_CertifiedRetainedByLaterLeaders_noCrash_huntU1.out` (39 states,
  no crash), `MC-2_VotingHistoryCoversDurable_*.out`, `MC-2_PipelinePrefix_MCcfg*.out`.

## Code path
`zk.startupWithoutServing()` leaves `State.INITIAL` (`ZooKeeperServer.java:673-675`);
a failure before UPTODATE → `QuorumPeer.run` finally → `follower.shutdown()` →
`Learner.shutdown` → `zk.shutdown()`; `canShutdown()` is false for INITIAL
(`ZooKeeperServer.java:784-786`), so `LearnerZooKeeperServer.shutdown` (`:155-159`) and
`ZooKeeperServer.shutdown` (`:803-807`) return before `fastForwardDataBase` and
`syncProcessor.shutdown()`. The peer then votes with `getLastLoggedZxid()` = in-memory
position (`QuorumPeer.java:1257-1262`) and, if elected, `Leader.lead → loadData()` keeps the
initialized in-memory DB (`ZooKeeperServer.java:480-503`).

## Observations
`traces/diff-sync-uptodate-failure.ndjson` lines 88-109 and `traces/repro-u4-no-restart-r1.ndjson`
lines 88-129: `ShutdownSkipped(INITIAL)`; leaked `SyncThread` writes `TxnDurable (1,2)` and
`TxnAckSent` while the peer is LOOKING; the peer reports in-memory (1,1); it wins with
`ElectionWon (1,1)` and its DIFF advertises (1,1). TLC: `spec/evidence/E5` (P5 FALSE).

## Reproduction
Command: `SKIP_PREPARE=1 SCENARIOS="repro-u4-no-restart-r1 repro-u4-no-restart-r2 repro-u4-no-restart-r3" harness/run.sh`
(test `harness/repro/SpeculaU4ReproTest.java`: update test scenario up to "leader can see
/zk2", then only the old leader is stopped and the followers re-elect in-process).
Result: 3/3 `Data inconsistency detected! Server 1 (elected without restart) should have a view of /zk2!`
(`spec/output/incremental/harness/repro-u4-no-restart-r{1,2,3}.log`), e.g.
`SPECULA-U4-REPRO oldLeader=2 newLeader=1 oldLeaderServedNode=true newLeaderHasNode=false`.
Old revision: also fails 1/1 (`old-control-repro-u4-r1.log`) — the loss on this path predates
the update and is not fixed by it; the leaked processors and the log-vs-memory divergence
(the new leader's log holds (1,2) behind its served history) are introduced by the update.
