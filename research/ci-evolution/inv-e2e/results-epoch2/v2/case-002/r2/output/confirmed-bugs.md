# Confirmation Report

Reproduced bugs: 3; other unresolved findings: 0; other dispositions: 0.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | CR-2 | REPRODUCED | yes |
| 3 | CR-3 | REPRODUCED | yes |

## Entry 1: NEWLEADER ACK is sent before the DIFF-synced transactions are durable

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: Learner.syncWithLeader (NEWLEADER) only enqueues the buffered sync proposals to the asynchronous SyncRequestProcessor via FollowerZooKeeperServer.logRequest and then writes the NEWLEADER ACK; the leader counts that ACK toward the quorum that makes it commit and serve its whole loaded history.
- **Trigger scenario**: A transaction durable only on the re-elected leader is transferred by DIFF; the learners ACK NEWLEADER, the leader starts serving it, and the acking learners crash before their SyncRequestProcessor fsync while the old leader is unavailable.
- **Impact**: A new leader is elected without the transaction that clients already read, and the old leader's only copy is truncated when it rejoins (lost committed write).
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/output/mc/update-full-bfs-r3.log>), [evidence 4](<spec/output/mc/update-hunt-durable-final.log>), [evidence 5](<spec/output/mc/update-hunt-durable-2s-r3.log>), [evidence 6](<spec/output/mc/update-hunt-loss-witness-r3.log>), [evidence 7](<spec/evidence/E1-CQD/tlc.log>), [evidence 8](<spec/evidence/repro/NewLeaderAckDurabilityReproTest.java>), [evidence 9](<spec/evidence/repro/logs/bug1-summary.log>)

## Entry 2: Learner failure between NEWLEADER and UPTODATE leaks an INITIAL ZooKeeperServer

- **Finding ID**: CR-2
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: The update starts the learner's request processors at NEWLEADER with startupWithoutServing (state INITIAL), but ZooKeeperServer/LearnerZooKeeperServer.shutdown skip a server that is not RUNNING or ERROR, so a learner that fails before UPTODATE never stops those processors or fast-forwards its data tree.
- **Trigger scenario**: A learner fails (e.g. read timeout) after handling NEWLEADER and before startServing, then re-joins.
- **Impact**: Each failed sync leaks the abandoned server's processor threads (3 failures left 3 extra CommitProcessor threads; none on the old revision); the leaked SyncThread keeps writing the shared log after the peer left the session and the peer's election vote uses a data tree older than its durable log (observed in a real trace).
- **Evidence**: [evidence 1](<spec/confirmation-CR-2.md>), [evidence 2](<spec/evidence/repro/LearnerInitialStateLeakReproTest.java>), [evidence 3](<spec/evidence/repro/logs/bug2-summary.log>), [evidence 4](<traces/diff-sync-uncommitted-log.ndjson>)

## Entry 3: A proposal ACK can be consumed as the NEWLEADER ACK

- **Finding ID**: CR-3
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: The SyncRequestProcessor started at NEWLEADER can write a proposal ACK before the learner thread writes the NEWLEADER ACK; LearnerHandler treats the first ACK after NEWLEADER as the NEWLEADER ACK and waitForNewLeaderAck drops a mismatched zxid without counting the learner.
- **Trigger scenario**: Learners DIFF-sync a proposal from a new leader and their learner thread is delayed before writing the NEWLEADER ACK.
- **Impact**: The leader misses its NEWLEADER quorum although every learner acked; activation waited for a learner sync timeout and re-sync (about 22 s versus under 4 s on the old revision).
- **Evidence**: [evidence 1](<spec/confirmation-CR-3.md>), [evidence 2](<spec/evidence/repro/NewLeaderAckOrderReproTest.java>), [evidence 3](<spec/evidence/repro/logs/bug3-summary.log>)

## Validation limits

- All TLC campaigns are finite-bound: canonical MC/base runs are exhaustive only up to the inherited level-23 state constraint; the full update BFS stopped at its CommittedQuorumDurable counterexample, focused/open/discharge BFS runs stopped at their 30-minute budget (on a superset transition relation) and were followed by 30-minute simulations on the final model (LIMITED_COVERAGE, not proofs).
- The stale data-tree election vote of CR-2 is not represented in the model (votes use durable history); it is evidenced by a real trace only.
- CR-3 (proposal ACK consumed as NEWLEADER ACK) is a liveness/availability issue outside the safety model; confirmed only by reproduction.
- The MC-1 reproduction uses a test-fixture fsync hold (slow disk) and SIGKILL-equivalent data-directory images; without a slow disk the window was not hit in 3 natural-timing runs.
- JDK 21 / in-process multi-server JUnit environment, as in the prior run.
