# Confirmation MC-3 — A learner that fails between NEWLEADER and UPTODATE keeps a stale tree under the new epoch; in-process re-election loses a committed transaction

- **Status**: REPRODUCED (bug)
- **Source**: MC (actual counterexample, see "Model-checking evidence") + code review + fresh trace
- **Novelty**: NEW within this run (external issue/history search prohibited by the blind contract)
- **Attribution**: the consequence class pre-exists in the old revision (old control fails the same
  test, there the proposals are never logged); the update's fix (log before the NEWLEADER ACK)
  only helps a learner that is later restarted from disk. In the new revision the failing learner
  is in the new `State.INITIAL`, whose shutdown is a no-op, so its data tree is never
  fast-forwarded and the in-process re-election still elects a leader without the committed
  transaction. The update's own test only checks after a full restart and passes.
- **Severity**: Critical (a transaction committed by an established leader and read by a client
  disappears after a single leader failure plus a learner socket timeout; no process crash needed)
- **Source revision**: `artifact/` commit `update` 2efbdfc3754d

## Mechanism (code)
1. NEWLEADER (Learner.java:739-760, update): `setCurrentEpoch(newEpoch)`; `zk.startupWithoutServing()`
   (ZooKeeperServer.java:673-675 -> State.INITIAL, processors started); DIFF proposals passed to
   `logRequest`; ACK. The leader counts the ACK, establishes the epoch and serves its history.
2. Any exception before UPTODATE completes (here the update test's own fault: SocketTimeoutException
   on UPTODATE) unwinds to `Follower.followLeader`; `Learner.shutdown` -> `zk.shutdown()` returns
   immediately because `canShutdown()` is false in INITIAL (ZooKeeperServer.java:784-805,
   LearnerZooKeeperServer.java:155-159). No `fastForwardDataBase`, processors keep running.
3. DIFF proposals are applied to the tree only via `fzk.commit` after UPTODATE, so the tree stays at
   the pre-sync zxid while `currentEpoch` is already the new epoch; `QuorumPeer.getLastLoggedZxid()`
   (QuorumPeer.java:1257-1262) reports that stale tree position to FLE.
4. If the leader then fails, the surviving learners re-elect in-process; `Leader.lead ->
   zk.loadData()` (ZooKeeperServer.java:480-504) keeps the initialised stale tree, the new leader's
   committed log lacks the transaction, and it is established and served without it.

## Fresh trace evidence (real code, the update's own test)
`traces/update-diff-sync-consistency.ndjson` (DIFFSyncConsistencyTest, instrumented):
s2 establishes epoch 2 with the learners' NEWLEADER ACKs (seq 91/100) and serves 0x100000002;
s1/s0 hit SocketTimeoutException (seq 94/102) and return to LOOKING reporting tree 0x100000001
(seq 95-96/103-104) although their logs force 0x100000002 later (seq 105/106); s1 is elected
(seq 107-108, zxid 0x100000001) and **establishes epoch 3 at seq 124** with that tree. The test only
passes because it then restarts both learners from disk (`DatabaseLoaded` 0x100000002, seq 134-135).
This trace replays through the model's `ExitHist` (no fast-forward from INITIAL); the mutated trace
that reports a fast-forwarded tree is rejected (`negative-neg-initial-exit-fastforward.log`).

## Model-checking evidence
- `Update!EpochHistoryRecoverable`, looking clause (`up /\ role = looking => epochTarget ⊑ DbPos`),
  config `spec/Update-hunt-epoch-nocrash.cfg` (MaxCrash = 0, full MCNext + `GuideEpochs`), see
  `spec/output/mc/hunt-update-epoch-nocrash.log` / `spec/output/cex/hunt-update-epoch-nocrash.json`.
- `Update!LeaderCompleteness` / `Update!CommittedNeverLost` (U-LOSS), config
  `spec/Update-hunt-loss-tight.cfg` (MaxCrash = 0), see `spec/output/mc/hunt-update-loss-tight.log`.
  (Outcome recorded in `spec/bug-report.md`.)

## Reproduction
- Test: `harness/tests/SpeculaReelectionAfterSyncFailureTest.java#testCommittedTxnVisibleAfterInProcessReelection`
  (same fault as DIFFSyncConsistencyTest, but the learners block on UPTODATE until the old leader is
  stopped, then time out once and re-elect in-process; then every surviving server is asked for the
  committed znode).
- New revision: FAIL 3/3 (`repro/new-reelection-run{1,2}.log`,
  `repro/new-capture-testCommittedTxnVisibleAfterInProcessReelection.log`):
  `Committed /zk2 (served by the old leader) is missing at server 0 after in-process re-election
  (new leader 1)`. Server log `repro/surefire/new-testCommittedTxnVisibleAfterInProcessReelection-output.txt`:
  old leader s2 "Getting a diff from the leader 0x100000002" for both learners and the client sees
  /zk2; after failover s1 is LEADING and sends "a diff from the leader 0x100000001";
  `exists(/zk2) = null`.
- Old-revision control: FAIL 3/3 (same assertion) — the defect class predates the update.
- Ledger: `repro/repro-results.ndjson`. (`repro/superseded/` holds a first test version whose
  injection was cleared too late; not counted.)

## Consequence
A client that read /zk2 from the old leader no longer sees it at the new leader/followers (lost
committed write, violates Zab committed-prefix agreement). The orphaned record is still in the
learners' logs and reappears only after a process restart, after which their histories can diverge
from writes accepted in the meantime.

## Recommendation
Treat a failure after NEWLEADER as requiring a database reload (fast-forward or clear-and-reload)
before the next election, i.e. make `shutdown()` effective in State.INITIAL (stop/flush the
processors and fast-forward the tree), and/or make the logged proposals part of the tree before
`setCurrentEpoch`/ACK.
