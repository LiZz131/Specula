# Modeling-brief coverage (update revision)

Filled from the actual cfg files in this directory.

## Update Scenarios (brief §2b)

| Scenario | Reference actions | Properties | Enabled in cfg | Fresh real trace | Reachability evidence |
|---|---|---|---|---|---|
| U-S1 learner target | `TransferLeader`→`ElectCore`, `PersistVote`, `ReceiveVoteResponse` (R3), `SendVoteRequests`, `ReceiveVoteRequest` | U1 `ElectOnlyByVoter`, U2 `NoCorePanic`, U5 `ElectedLeaderWasVoter` | `Update_full.cfg`, `Update_full_NoCorePanic.cfg`, `Update_full_ElectedLeaderWasVoter.cfg`, `Update_focused.cfg`, `Update_open.cfg`, `MC_hunt_transfer_learner.cfg`; U5 also in all `*_residual.cfg` | `core-learner-n3-c0` (TransferLeader → VoteResponsePanic), `core-learner-n{0,1,2}-*` | `CanaryNonVoterCandidate`; MC-1 counterexamples |
| U-S2 lease disable/touch/update | `TransferLeader` (non-target), `ReceiveAppend` (touch/update), `ReceiveVoteRequest` (R5), `Restart` | U3 `LeaseReenabledOnVoteChange`, U4 `DisabledLeaseOnlyByTransfer` | every `Update_*` cfg (except canaries/discharge) and every `MC_hunt_transfer_*` cfg | `lease-touch`, `core-t14-n1-c0`, `core-learner-n{0,1,2}-*`, `core-t14-n0-c1` (lease rejection) | `CanaryLeaseDisabled` |
| U-S3 voter transfer safety | `TransferLeader`, election actions, `LeaderAppend`, `ReceiveAppend`, `AcknowledgeReplication` | U6 = `CommittedLogAgreement` ∧ `LeaderCompleteness` ∧ `CandidateGrantSound` | `MC.cfg`, all `Update_*` (non-canary), `MC_hunt_transfer_voter.cfg` | `core-t14-*` | `CanaryTransferElectedLeader`, `CanaryOldLeaderDeposed`, `CanaryCommitAfterTransfer(_witness)`, `CanaryTransferGrant` |
| U-S4 membership × transfer, leader target | `MCJoint`, `MCUniform`, `ElectCore` absent branch and leader branch | reference + U3/U4; U7 `LeaderVoteNotSuperseded` | `MC_hunt_transfer_membership.cfg`; U7: `Update_full_LeaderVoteNotSuperseded.cfg`, `Update_preexisting_LeaderVoteNotSuperseded.cfg` | leader target: real probes `spec/output/probe-leader-self-elect-*.log` (no hook trace); absent target: none | `CanaryAbsentElect(_witness)`; MC-2 counterexamples |
| U-S5 crash/restart | `Crash`, `Restart` (R4) | all of the above | all MC/Update cfgs (`CrashLimit = 1`) | `restart` (startup) | MC action coverage |

## V0 Scenarios (brief appendix §2) — retained

| Brief item | Base action/state | Fresh trace | MC evidence | Status |
|---|---|---|---|---|
| S1 election | `StartElection`(`ElectCore`), `ReceiveVoteResponse` | `election`, `core-*-VoteResponse` | MC.cfg | covered |
| S2 vote request | `ReceiveVoteRequest` / `RejectVoteRequest` | `vote-request`, core VoteRequest events | MC.cfg | covered (now network-linked, R1) |
| S3 follower append | `ReceiveAppend(Direct)` | `follower-append`, `lease-touch` | MC.cfg | covered |
| S4 partial replication | `AcknowledgeReplication` | `partial-replication` | MC.cfg | covered (acks linked, R2) |
| S5 membership | `LeaderAppend` membership kinds, follower adoption (R2) | three membership traces | MC.cfg; membership hunt | covered |
| S6 rollback/session | `DropStaleResponse` | none (Core callback layer) | MC.cfg | model checked only (V0 limit retained) |
| S7 crash/restart | `Crash`, `Restart`, `RestartFromRecovered` | `restart` | MC.cfg | covered |
| Snapshot/purge, payload, metrics | excluded | — | — | out of scope |

## Invariants (brief §5 / §5b) → cfg

All V0 invariants plus `LeaderCompleteness` are enabled in `MC.cfg` and every non-canary
`Update_*`/`MC_hunt_*` cfg. `NoCorePanic` and `ElectedLeaderWasVoter`: `Update_full.cfg`,
`Update_focused.cfg`, `Update_open.cfg`, isolation cfgs, learner/voter hunts;
`ElectedLeaderWasVoter` also in all residual cfgs. `ElectOnlyByVoter`: `Update_full.cfg`,
`Update_focused.cfg`, `Update_open.cfg`, learner/voter hunts. `DischargeContext`:
`Update_discharge.cfg`.

## Known gaps

- No real removed-node (absent) transfer trace; U-S4 absent-target behavior is model-checked
  and code-reviewed only.
- Follower conflict truncation and follower commit propagation remain unmodeled (V0 limits);
  R2 appends only when the follower log is a prefix of the leader log.
- Lease time is abstract; the flag is modeled and trace-validated, not the duration.
