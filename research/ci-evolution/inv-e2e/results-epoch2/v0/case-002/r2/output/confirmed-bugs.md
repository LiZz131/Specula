# Confirmation Report

Reproduced bugs: 5; other unresolved findings: 0; other dispositions: 0.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | MC-2 | REPRODUCED | yes |
| 3 | MC-3 | REPRODUCED | yes |
| 4 | CR-4 | REPRODUCED | yes |
| 5 | CR-5 | REPRODUCED | yes |

## Entry 1: NEWLEADER quorum commits a DIFF history that acknowledging learners have only enqueued

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: At NEWLEADER the learner persists currentEpoch and only enqueues the DIFF proposals to the asynchronous SyncRequestProcessor before writing the NEWLEADER ACK that commits the leader's initial history.
- **Trigger scenario**: Leader re-elected with an uncommitted logged txn DIFF-syncs both learners; they ACK NEWLEADER and crash before their SyncThread forces the txn; the learners then elect a new leader.
- **Impact**: A transaction the old leader served after the NEWLEADER quorum is missing on the new leader (committed data lost).
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/output/update-focused-durability-bfs.log>), [evidence 3](<spec/output/update-seeded-durability-bfs.log>), [evidence 4](<spec/output/trace-oracle-diff-sync-uncommitted.log>), [evidence 5](<harness/repro/test_bugMC-1_durability.sh>), [evidence 6](<harness/src/SpecularReproTest.java>), [evidence 7](<spec/output/repro-durability-cluster-new-surefire-output.txt>), [evidence 8](<spec/output/repro-durability-cluster-old-surefire-output.txt>)

## Entry 2: SyncRequestProcessor ACK written before the NEWLEADER ACK is consumed as the NEWLEADER ACK

- **Finding ID**: MC-2
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: The update starts the learner pipeline (startupWithoutServing) before the learner thread writes the NEWLEADER ACK, so a forced proposal's ACK can be the first packet LearnerHandler reads after NEWLEADER.
- **Trigger scenario**: DIFF sync with at least one proposal; the learner thread is delayed between logRequest and the NEWLEADER ACK write (GC pause, preemption, or a large DIFF batch).
- **Impact**: Leader.waitForNewLeaderAck discards the ACK as from a different epoch; the re-elected leader fails to establish its epoch and times out, and an established leader loses that proposal ACK.
- **Evidence**: [evidence 1](<spec/confirmation-MC-2.md>), [evidence 2](<spec/output/update-focused-bfs.log>), [evidence 3](<spec/output/update-hunt-ackorder-sim.log>), [evidence 4](<harness/repro/test_bugMC-2_ackorder_cluster.sh>), [evidence 5](<harness/repro/test_bugMC-2_ackorder_fixture.sh>), [evidence 6](<harness/src/SpecularUpdateScenariosTest.java>), [evidence 7](<harness/src/SpecularReproTest.java>), [evidence 8](<spec/output/repro-ackorder-cluster-new-surefire-output.txt>), [evidence 9](<spec/output/repro-ackorder-cluster-old-surefire-output.txt>), [evidence 10](<traces/diff-ack-before-newleader-ack.ndjson>), [evidence 11](<spec/output/repro-ackorder-fixture-new-surefire-output.txt>), [evidence 12](<spec/output/repro-ackorder-fixture-old-surefire-output.txt>)

## Entry 3: COMMIT received after NEWLEADER for a proposal buffered before it throws NullPointerException

- **Finding ID**: MC-3
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: The update clears packetsNotCommitted at NEWLEADER while the unchanged sync-loop COMMIT handler dereferences packetsNotCommitted.peekFirst() without a null check.
- **Trigger scenario**: A learner (re)joins an established leader while writes are in flight: outstanding PROPOSALs are forwarded before NEWLEADER and their COMMIT after it.
- **Impact**: NullPointerException in Learner.syncWithLeader aborts synchronization; the learner returns to LOOKING and cannot join under load.
- **Evidence**: [evidence 1](<spec/confirmation-MC-3.md>), [evidence 2](<spec/output/update-hunt-npe-sim.log>), [evidence 3](<spec/output/update-focused-npe-bfs.log>), [evidence 4](<harness/repro/test_bugMC-3_npe_cluster.sh>), [evidence 5](<harness/repro/test_bugMC-3_npe_fixture.sh>), [evidence 6](<harness/src/SpecularReproTest.java>), [evidence 7](<harness/src/SpecularUpdateScenariosTest.java>), [evidence 8](<spec/output/repro-npe-cluster-old-surefire-output.txt>), [evidence 9](<spec/output/repro-npe-cluster-r3-new-surefire-output.txt>), [evidence 10](<spec/output/repro-npe-cluster-new-run2-surefire-output.txt>), [evidence 11](<spec/output/repro-npe-fixture-new-surefire-output.txt>), [evidence 12](<spec/output/repro-npe-fixture-old-surefire-output.txt>)

## Entry 4: Learner failing between NEWLEADER and UPTODATE leaks its request processors

- **Finding ID**: CR-4
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: startupWithoutServing leaves the learner server INITIAL and canShutdown() accepts only RUNNING or ERROR, so Follower.shutdown() after a failure before UPTODATE does not stop the started processors.
- **Trigger scenario**: Connection loss, timeout or exception after NEWLEADER and before UPTODATE, followed by the normal Follower.shutdown().
- **Impact**: SyncThread and CommitProcessor threads keep running after shutdown, the data tree is not fast-forwarded, and the orphaned SyncThread keeps writing the shared log and ACKs to a dead connection.
- **Evidence**: [evidence 1](<spec/confirmation-CR-4.md>), [evidence 2](<harness/repro/test_bugCR-4_initial_shutdown_leak.sh>), [evidence 3](<harness/src/SpecularUpdateScenariosTest.java>), [evidence 4](<spec/output/repro-leak-fixture-new-surefire-output.txt>), [evidence 5](<spec/output/repro-leak-fixture-old-surefire-output.txt>), [evidence 6](<traces/diff-sync-uncommitted.ndjson>)

## Entry 5: Pre-Zab1.0 synchronization never starts the learner server

- **Finding ID**: CR-5
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: The UPTODATE-only (pre-Zab1.0) path now calls zk.startServing() without the startupWithoutServing() that only the NEWLEADER branch performs.
- **Trigger scenario**: A leader speaking the pre-Zab1.0 protocol (NEWLEADER in discovery, UPTODATE without NEWLEADER in the sync loop).
- **Impact**: NullPointerException in Learner.syncWithLeader; the learner never reaches a running BROADCAST state.
- **Evidence**: [evidence 1](<spec/confirmation-CR-5.md>), [evidence 2](<harness/repro/test_bugCR-5_prezab10.sh>), [evidence 3](<harness/src/SpecularUpdateScenariosTest.java>), [evidence 4](<spec/output/repro-prezab10-fixture-new-surefire-output.txt>), [evidence 5](<spec/output/repro-prezab10-fixture-old-surefire-output.txt>)

## Validation limits

- All TLC runs are budget-limited (30 min each); no state space was exhausted. MC.cfg BFS reached depth 28 (16.9M distinct states), Update-full BFS depth 28 (17.5M), focused BFS depth 29, discharge depth 22; simulation follow-ups are recorded in spec/model-checking-campaign.md.
- The full-MCNext counterexample for MC-1 starts from seeded epoch-2 states whose reachability is shown by canary NotUpdateDurabilityGap and by replaying the real diff-sync-uncommitted trace; the data-loss consequence (CommittedAgreement) was not reached by model checking within budget and is shown only by the implementation reproduction.
- Open-spec (EnvUpdate) results are claimed only for a fixed established epoch; epoch creation is covered only by the full MCNext checks.
- The leaked SyncThread of CR-4 is modeled only for its history effect; quiescence guards on ElectLeader and LeaderSyncFollower assume it drains before an election completes.
- MC-1 and MC-2 reproductions use Level 1 timing assistance (delayed follower SyncThread plus crash emulation; delayed NEWLEADER-ACK write); MC-3 (deterministic fixture; real cluster triggers in 4 of 5 runs), CR-4 and CR-5 are Level 0.
- Builds and tests used JDK 11 (prior run used JDK 21). Observers, dynamic reconfiguration and the pre-Zab1.0 protocol remain outside the model scope.
- Novelty was not assessed: issue-tracker and history research is prohibited in this blind run.
