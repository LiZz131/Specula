# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CanaryAbsentElect`, `CanaryCommitAfterTransfer`, `CanaryLeaseDisabled`, `CanaryNonVoterCandidate`, `CanaryOldLeaderDeposed`, `CanaryOmittedApply`, `CanaryOmittedStale`, `CanaryTransferElectedLeader`, `CanaryTransferGrant`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCTransfer |
| 2 | AffectedActions | MCElect |
| 3 | AffectedActions | MCVoteResponse |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 |
|---|---|---:|---:|---|---|---|
| `MC.cfg` | budget used | 12924 | 120.3 | x | x | x |
| `MC_hunt_transfer_learner.cfg` | budget used | 11817 | 120.3 | x | x | x |
| `MC_hunt_transfer_membership.cfg` | budget used | 13154 | 120.3 | x | x | x |
| `MC_hunt_transfer_voter.cfg` | budget used | 9891 | 120.3 | x | x | x |
| `Update_canary_AbsentElect.cfg` | budget used | 16781 | 120.3 | x | x | x |
| `Update_canary_AbsentElect_witness.cfg` | budget used | 13574 | 120.3 | x | x | x |
| `Update_canary_CommitAfterTransfer.cfg` | budget used | 11428 | 120.3 | x | x | x |
| `Update_canary_CommitAfterTransfer_witness.cfg` | budget used | 11490 | 120.3 | x | x | x |
| `Update_canary_LeaseDisabled.cfg` | budget used | 11964 | 120.3 | x | x | x |
| `Update_canary_NonVoterCandidate.cfg` | budget used | 13217 | 120.3 | x | x | x |
| `Update_canary_OldLeaderDeposed.cfg` | budget used | 12240 | 120.3 | x | x | x |
| `Update_canary_OmittedApply.cfg` | budget used | 13245 | 120.3 | x | x | x |
| `Update_canary_OmittedStale.cfg` | budget used | 12025 | 120.3 | x | x | x |
| `Update_canary_TransferElectedLeader.cfg` | budget used | 12885 | 120.3 | x | x | x |
| `Update_canary_TransferGrant.cfg` | budget used | 12842 | 120.3 | x | x | x |
| `Update_discharge.cfg` | budget used | 12760 | 120.3 | x | x | x |
| `Update_focused.cfg` | budget used | 15319 | 120.2 | x | x | x |
| `Update_focused_residual.cfg` | budget used | 15491 | 120.2 | x | x | x |
| `Update_full.cfg` | budget used | 20749 | 120.2 | x | x | x |
| `Update_full_ElectedLeaderWasVoter.cfg` | budget used | 20625 | 120.2 | x | x | x |
| `Update_full_LeaderVoteNotSuperseded.cfg` | budget used | 20336 | 120.2 | x | x | x |
| `Update_full_NoCorePanic.cfg` | budget used | 19802 | 120.2 | x | x | x |
| `Update_full_residual.cfg` | budget used | 20293 | 120.2 | x | x | x |
| `Update_open.cfg` | budget used | 9632 | 120.2 | x | x | x |
| `Update_open_residual.cfg` | budget used | 8999 | 120.2 | x | x | x |
| `Update_preexisting_LeaderVoteNotSuperseded.cfg` | budget used | 19469 | 120.2 | . | x | x |
