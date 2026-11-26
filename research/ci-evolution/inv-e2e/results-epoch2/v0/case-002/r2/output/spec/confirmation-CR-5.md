# Confirmation CR-5 (ledger D-4) — pre-Zab1.0 synchronization never starts the learner server

- **Source**: Code Review
- **Novelty**: not searched (blind run: issue/history research prohibited)
- **Status**: REPRODUCED
- **Severity**: Low (only a leader speaking the pre-Zab1.0 protocol — NEWLEADER in
  discovery, UPTODATE without a NEWLEADER in the sync loop — triggers it;
  outside the Zab1.0 modeling scope)
- **Update attribution**: introduced by the update (old-tree control passes).
- **Location**: `quorum/Learner.java:711-725` (UPTODATE with isPreZAB1_0),
  `:764-786` (`zk.startServing()` without a prior `startupWithoutServing()`,
  then `fzk.logRequest` with no SyncRequestProcessor).

## Reproduction

`harness/repro/test_bugCR-5_prezab10.sh` — Level 0 fixture (pre-1.0 leader wire
sequence).  New (`spec/output/repro-prezab10-fixture-new-surefire-output.txt`):
`java.lang.NullPointerException at ...Learner.syncWithLeader(Learner.java:781)`,
`SPECULAR-OBSERVATION pre-1.0 sync: zabState=SYNCHRONIZATION`, test fails.  Old
control: `zabState=BROADCAST zk.isRunning=true`, passes.

## Recommendation

Call `startupWithoutServing()` on the pre-1.0 UPTODATE path (or `startup()` when
the server was never started) before `startServing()`.
