# Confirmation MC-2 — NEWLEADER is ACKed (and currentEpoch persisted) before the synchronised history is durable

- **Status**: ENV_LIMITED (real defect; the harmful outcome needs a process/power crash inside a
  millisecond window, which this JUnit environment cannot inject without a graceful shutdown)
- **Source**: MC (actual counterexamples) + code review
- **Novelty**: NEW within this run (external issue/history search prohibited by the blind contract)
- **Attribution**: pre-existing in the old revision (old control fails the same check); the update
  narrows the window (proposals are queued before the ACK instead of after UPTODATE) but does not
  close it, contrary to the update's own comment at Learner.java:748
  ("make sure sync the uncommitted logs before commit them (ACK NEWLEADER)").
- **Severity**: High (committed-transaction loss after a crash of an ACKing learner followed by
  leader failure; requires a crash in the window)
- **Source revision**: `artifact/` commit `update` 2efbdfc3754d

## Mechanism (code)
- `quorum/Learner.java:739-746`: `self.setCurrentEpoch(newEpoch)` writes the epoch file before
  the DIFF proposals are logged.
- `quorum/Learner.java:752-760` (update): `fzk.logRequest(...)` only appends to `pendingTxns` and
  enqueues to SyncRequestProcessor (`FollowerZooKeeperServer.java:82-89`); the ACK of NEWLEADER is
  written immediately afterwards. The force happens later in `SyncRequestProcessor.flush`
  (`SyncRequestProcessor.java:216-245`).
- `quorum/Leader.java:1547-1586` counts that ACK towards the NEWLEADER quorum; after
  `startZkServer` the leader serves its whole loaded history as committed.
- FLE orders votes by peer epoch (= currentEpoch) first (`FastLeaderElection.totalOrderPredicate`),
  so a restarted learner with the new epoch but without the history can win against a server that
  holds the committed history in an older epoch; it then TRUNCs/omits that history.

## Model-checking counterexamples (full MCNext + guidance constraints only)
- `Update!EpochHistoryRecoverable` (crash clause), `spec/Update-hunt-epoch.cfg`, depth 30,
  `spec/output/mc/hunt-update-epoch.log`, `spec/output/cex/hunt-update-epoch.json`: s1 commits-less
  proposal t1 forced only at s1 in epoch 1; s1 re-elected epoch 2 with s3; s3 consumes PROPOSAL t1,
  COMMIT t1, NEWLEADER (`LearnerNewLeader`: currentEpoch 2) and crashes before t1 is logged/forced
  -> crashed s3 has currentEpoch 2 and an empty log while epoch 2's history is <<t1>>.
- `Update!NewLeaderAckDurable`, `spec/Update-hunt-dur.cfg`, depth 38,
  `spec/output/mc/hunt-update-dur.log`: `LearnerAckNewLeader` fires while `syncTarget` is not a
  prefix of `durable` (the logged entry is still in `queued`).
- Reference/Update mapping: `base!LearnerNewLeader`, `base!LearnerLogPending`,
  `base!LearnerAckNewLeader` (affected), `base!FsyncOne`, `base!Crash`, `base!LeaderBroadcast`
  (interaction); Scenarios U-DUR, U-EPOCH.

## Trace evidence (real code, fresh)
- `traces/follower-diff.ndjson`: `ProposalQueued(0x100000002)` seq 11, `NewLeaderAcked` seq 12,
  `TxnAppended` seq 14, `TxnDurable` only at seq 20 (after the session ended).
- `traces/update-diff-sync-consistency.ndjson`: `NewLeaderAcked` seq 91/100 precede
  `TxnDurable` seq 105/106 for 0x100000002 at both learners.

## Reproduction
- Test: `harness/tests/SpeculaSyncUpdateTest.java#testNewLeaderAckOnlyAfterDiffTxnDurable`.
  The learner's `ZKDatabase.commit()` (the fsync of SyncRequestProcessor.flush) is delayed by a
  latch (slow disk); the fixture leader sends DIFF, PROPOSAL x, COMMIT x, NEWLEADER and, when it
  reads the NEWLEADER ACK, inspects the learner's data directory with a fresh FileTxnSnapLog.
- New revision: FAIL 3/3 — `NEWLEADER was ACKed (currentEpoch=1) while the DIFF transaction
  0x100000001 was not yet on disk (disk last=0xffffffffffffffff)` (`repro/new-dur-run{1,2,3}.log`).
- Old-revision control: FAIL 3/3 (same assertion; the old code ACKs before even queueing)
  (`repro/old-dur-run{1,2,3}.log`).
- A correct learner would withhold the ACK until x is forced (the test accepts that outcome).
- Ledger: `repro/repro-results.ndjson`.

## Environment limitation
The data-loss consequence needs the learner process to die (kill -9, OOM, power loss) between the
ACK and the force, plus loss of the old leader. The JUnit QuorumPeer harness only offers graceful
shutdown, which drains/flushes (or, in the INITIAL state, leaves the flushing thread running), so
the crash image cannot be produced in-process; the reproduction demonstrates the persisted state
(currentEpoch advanced, history absent) at the moment the leader counts the ACK.

## Recommendation
Make the synchronised proposals durable (flush the SyncRequestProcessor / wait for the force)
before persisting the new current epoch and before sending the NEWLEADER ACK.
