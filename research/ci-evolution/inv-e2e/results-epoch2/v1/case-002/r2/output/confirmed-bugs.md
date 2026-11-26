# Confirmation Report

Reproduced bugs: 4; other unresolved findings: 0; other dispositions: 0.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | CR-1 | REPRODUCED | yes |
| 3 | CR-2 | REPRODUCED | yes |
| 4 | CR-3 | REPRODUCED | yes |

## Entry 1: NEWLEADER ACK is sent before the DIFF-synchronized history is durable

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: Learner.syncWithLeader hands buffered proposals to FollowerZooKeeperServer.logRequest, which only enqueues to SyncRequestProcessor, and writes the NEWLEADER ACK without waiting for append/fsync; currentEpoch is already persisted.
- **Trigger scenario**: A leader with an uncommitted logged txn is re-elected; a follower DIFF-syncs it, ACKs NEWLEADER (counted toward the quorum, leader serves the txn) and crashes before SyncThread forces the log; it restarts with the new epoch and, with another server lacking the txn, elects a new leader.
- **Impact**: A transaction the previous leader already served after its NEWLEADER quorum is missing at the next leader (lost or truncated cluster-wide).
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/bug-report.md>), [evidence 3](<spec/output/incr/MC-1-U3-counterexample.out>), [evidence 4](<spec/output/incr/MC-1-U2-counterexample.out>), [evidence 5](<spec/output/incr/repro/repro-new.log>), [evidence 6](<spec/output/incr/repro/repro-old.log>), [evidence 7](<spec/output/incr/repro/repro-fixedctl.log>), [evidence 8](<harness/repro/NewLeaderAckDurabilityReproTest.java>), [evidence 9](<spec/evidence/trace-props/tlc-NewLeaderAckDurable-diff-sync-consistency.log>)

## Entry 2: COMMIT between NEWLEADER and UPTODATE dereferences an empty packetsNotCommitted (NPE)

- **Finding ID**: CR-1
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: The update clears packetsNotCommitted at NEWLEADER; the COMMIT branch dereferences packetsNotCommitted.peekFirst() without a null check.
- **Trigger scenario**: The leader forwards a PROPOSAL before NEWLEADER (startForwarding precedes NEWLEADER) and its COMMIT after NEWLEADER but before UPTODATE.
- **Impact**: NullPointerException in Learner.syncWithLeader; the learner abandons synchronization and cannot join until a retry avoids the interleaving.
- **Evidence**: [evidence 1](<spec/confirmation-CR-1.md>), [evidence 2](<spec/output/incr/repro/repro2-new.log>), [evidence 3](<spec/output/incr/repro/repro2-old.log>), [evidence 4](<harness/repro/CommitAfterNewLeaderReproTest.java>)

## Entry 3: Request processors started at NEWLEADER are not shut down when synchronization fails before UPTODATE

- **Finding ID**: CR-2
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: startupWithoutServing starts the processors but leaves state INITIAL; LearnerZooKeeperServer.shutdown returns early because canShutdown() is false.
- **Trigger scenario**: Any learner failure between NEWLEADER and startServing (e.g. CR-1 or the read timeout injected by DIFFSyncConsistencyTest).
- **Impact**: Leaked FollowerRequestProcessor/CommitProcessor/RequestThrottler threads; the orphaned SyncThread keeps flushing and dies with a critical-thread error writing to the closed learner socket.
- **Evidence**: [evidence 1](<spec/confirmation-CR-2.md>), [evidence 2](<spec/output/incr/repro/repro2-new-markers.txt>), [evidence 3](<spec/output/incr/harness/harness-diff-sync-consistency.log>), [evidence 4](<traces/fresh/diff-sync-consistency.ndjson>)

## Entry 4: A SyncThread per-txn ACK can overtake the NEWLEADER ACK

- **Finding ID**: CR-3
- **Status**: REPRODUCED
- **Source**: Code Review
- **Confirmation**: Current confirmation.
- **Description**: The update starts SyncRequestProcessor/SendAckRequestProcessor and hands off txns before the learner thread writes the NEWLEADER ACK; LearnerHandler treats the first ACK after NEWLEADER as the NEWLEADER ACK.
- **Trigger scenario**: The learner thread is delayed longer than one append+fsync between logRequest and writing the NEWLEADER ACK.
- **Impact**: Leader.waitForNewLeaderAck rejects the ACK as from a different epoch and the real NEWLEADER ACK is ignored; the leader does not form its NEWLEADER quorum and stalls until the init limit.
- **Evidence**: [evidence 1](<spec/confirmation-CR-3.md>), [evidence 2](<spec/output/incr/repro/repro3-new.log>), [evidence 3](<spec/output/incr/repro/repro3-old.log>), [evidence 4](<harness/repro/NewLeaderAckOrderReproTest.java>)

## Validation limits

- All model checking is bounded (3 servers, 1 txn, up to 3 epochs, 2 crashes, 1 drop/snapshot); BFS runs stopped at 30-minute budgets with non-empty queues, so no-violation results are LIMITED_COVERAGE, not proofs.
- The deep U2/U3 witnesses (depth 25/38 from Init) were not reached by BFS or simulation from Init; they were found from a seed state that full MCNext reaches from Init (canary-seed.log) and re-found with full MCNext from that seed.
- Open/discharge checking is not applicable: Update.tla defines no EnvUpdate; focused relations are restrictions of MCNext.
- Not modeled: late joiners to a broadcasting leader, observers, reconfiguration, exception/liveness paths (handled by code review CR-1..CR-3); zxid order approximated by log length; FLE votes persist across rounds; TRUNC does not roll back the visible committed/applied state.
- Fresh traces did not exercise SyncProposalApplied, the TRUNC directive, or a crash inside the ACK-to-fsync window (the reproduction test covers the crash window).
- Known-status (issue/history) searches for the findings were not performed because the run is blind; novelty is undetermined.
- Only JDK 21 was available; the hypothetical flush-before-ACK control is a local patch, not an upstream fix.
