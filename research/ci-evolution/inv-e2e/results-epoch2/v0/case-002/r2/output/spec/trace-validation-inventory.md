# Fresh new-version trace inventory and validation outcomes

Source: updated artifact 2efbdfc + `harness/patches/instrumentation.patch`; command `harness/run.sh` (JDK 11).
Validation: `spec/trace-both.sh <scenario>` = TLC on `Trace.tla` with `Trace.cfg` (existential completion property `TraceMatched`, all reference safety invariants, VIEW `TraceView`) and `Trace-witness.cfg` (full-consumption witness).

| Scenario | Events | sha256[:16] | Completion (Trace.cfg) | Witness (Trace-witness.cfg) | distinct states | Event kinds |
|---|---:|---|---|---|---:|---|
| follower-snap | 22 | 7af8fa05dd1273d8 | PASS (`spec/output/trace-follower-snap.log`) | WITNESS (`spec/output/trace-witness-follower-snap.log`) | 28 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, FollowerRegistered, LearnerSyncCommit, LearnerSyncProposal, NewLeaderAckSent, NewLeaderReceived, PhaseChanged, ProposalQueued, SnapshotInstalled, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateReceived |
| follower-diff | 21 | 69780e036d43a663 | PASS (`spec/output/trace-follower-diff.log`) | WITNESS (`spec/output/trace-witness-follower-diff.log`) | 27 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, FollowerRegistered, LearnerSyncCommit, LearnerSyncProposal, NewLeaderAckSent, NewLeaderReceived, PhaseChanged, ProposalQueued, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateReceived |
| quorum-startup-mutation-shutdown | 103 | 39b561b4f6bf7332 | PASS (`spec/output/trace-quorum-startup-mutation-shutdown.log`) | WITNESS (`spec/output/trace-witness-quorum-startup-mutation-shutdown.log`) | 125 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, ElectionWon, FollowerRegistered, LeaderAckReceived, LeaderCommitted, LeaderProposed, LeaderSyncQueued, NewLeaderAckRead, NewLeaderAckSent, NewLeaderQueued, NewLeaderReceived, PeerRoleChanged, PhaseChanged, ProposalQueued, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateQueued, UpToDateReceived |
| leader-abandon-restart-recovery | 384 | 08933b599cac4161 | PASS (`spec/output/trace-leader-abandon-restart-recovery.log`) | WITNESS (`spec/output/trace-witness-leader-abandon-restart-recovery.log`) | 264787 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, ElectionWon, FollowerRegistered, LeaderAckReceived, LeaderCommitted, LeaderProposed, LeaderSyncQueued, NewLeaderAckRead, NewLeaderAckSent, NewLeaderQueued, NewLeaderReceived, PeerRoleChanged, PhaseChanged, ProposalQueued, SnapshotInstalled, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateQueued, UpToDateReceived |
| diff-sync-uncommitted | 170 | f4390faee3d5bec5 | PASS (`spec/output/trace-diff-sync-uncommitted.log`) | WITNESS (`spec/output/trace-witness-diff-sync-uncommitted.log`) | 422 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, ElectionWon, FollowerRegistered, LeaderAckReceived, LeaderCommitted, LeaderProposed, LeaderSyncQueued, LearnerSyncCommit, LearnerSyncProposal, NewLeaderAckRead, NewLeaderAckSent, NewLeaderQueued, NewLeaderReceived, PeerRoleChanged, PhaseChanged, ProposalQueued, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateQueued, UpToDateReceived |
| diff-commit-after-newleader | 16 | ab7ef28c986c2036 | PASS (`spec/output/trace-diff-commit-after-newleader.log`) | WITNESS (`spec/output/trace-witness-diff-commit-after-newleader.log`) | 21 | AcceptedEpochPersisted, AckSent, CurrentEpochPersisted, FollowerRegistered, LearnerSyncCommit, LearnerSyncProposal, NewLeaderAckSent, NewLeaderReceived, PhaseChanged, ProposalQueued, SyncModeChanged, SyncSelected, TxnAppended, TxnDurable |
| diff-ack-before-newleader-ack | 21 | c74d3cb7e201dc1f | PASS (`spec/output/trace-diff-ack-before-newleader-ack.log`) | WITNESS (`spec/output/trace-witness-diff-ack-before-newleader-ack.log`) | 27 | AcceptedEpochPersisted, AckSent, BroadcastReady, CommitDelivered, CurrentEpochPersisted, FollowerRegistered, LearnerSyncCommit, LearnerSyncProposal, NewLeaderAckSent, NewLeaderReceived, PhaseChanged, ProposalQueued, SyncModeChanged, SyncSelected, TxnAppended, TxnApplied, TxnDurable, UpToDateReceived |

Archived V0 traces (`traces/archived-v0/`): superseded — produced by the old implementation with the prior schema (no `peer`/`info`, no update probes); each prior scenario was rerun on the updated implementation (first four rows).

Update-property oracle on replayed reference behaviors (`TraceOracle.cfg`): `diff-sync-uncommitted` violates `CommittedQuorumDurable` (`spec/output/trace-oracle-diff-sync-uncommitted.log`); `diff-commit-after-newleader` violates `SyncCommitHasPendingProposal` (`spec/output/trace-oracle-diff-commit-after-newleader.log`); `quorum-startup-mutation-shutdown` satisfies all four (`spec/output/trace-oracle-quorum-startup-mutation-shutdown.log`).

## Validation handoff

- Source: artifact commit 2efbdfc (update); harness command `harness/run.sh` (rebased prior harness + 13 update-local probes); build/test JDK 11.
- Semantic spec files changed during validation: yes — `LeaderSyncFollower` (epoch-ACK quorum guard) and `RoleExit` (no drain for INITIAL learners, quiescence guards); Trace.tla completion property and probe-race handling. All 7 fresh traces were re-validated on the final artifacts.
- Archived V0 traces: superseded (old implementation, prior schema); every prior scenario was rerun fresh.
- Update-specific comparisons that are active Trace predicates: NEWLEADER effects (`OnCurrentEpochPersisted`, `OnSyncModeChanged`, `OnProposalQueued` against the `LearnerNewLeader` post-state), ACK order (`AckHeadMatches` in `OnNewLeaderAckRead`/`OnLeaderAckReceived`), pipeline durability (`OnTxnAppended`, `OnTxnDurable`), sync COMMIT handling (`OnLearnerSyncCommit`).
- Not validated by traces: the crash path (no process-crash events in the JUnit scenarios; covered by MC and the MC-1 reproduction); TRUNC mode (no fresh trace selects TRUNC; reachable in MC, canary `NotTruncReached`).

| Reference Action | Fresh traces observing it |
|---|---|
| AppendOne | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| ApplyOne | diff-ack-before-newleader-ack, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| Commit | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| FsyncOne | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| FsyncOne ACK | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LeaderProcessAck | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LeaderReadNewLeaderAck | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LeaderSendNewLeader | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LeaderSendUpToDate | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LeaderSyncFollower | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LearnerAckNewLeader (affected) | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LearnerNewLeader (affected) | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LearnerReadMode | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| LearnerSyncCommit | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap |
| LearnerSyncProposal | diff-ack-before-newleader-ack, diff-commit-after-newleader, diff-sync-uncommitted, follower-diff, follower-snap |
| LearnerUpToDate (affected) | diff-ack-before-newleader-ack, diff-sync-uncommitted, follower-diff, follower-snap, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
| Propose | diff-sync-uncommitted, leader-abandon-restart-recovery, quorum-startup-mutation-shutdown |
