# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CommitWitnessSound`, `NotReachCommitWitness`, `NotReachJointQuorumCommit`, `NotReachLeader`, `NotReachLeaderNotFirst`, `NotReachOutstandingMembership`, `NotReachProgressCommit`, `NotReachReelectedLeaderProgress`, `NotReachUpgradedWithFollowerProgress`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCStartElection |
| 2 | AffectedActions | MCGrantVote |
| 3 | AffectedActions | MCLeaderWriteBlank |
| 4 | AffectedActions | MCClientAppend |
| 5 | AffectedActions | MCProposeMembership |
| 6 | AffectedActions | MCHandleUpdateMatched |
| 7 | AffectedActions | MCDeliverAppendEntries |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---:|---:|---|---|---|---|---|---|---|
| `MC.cfg` | budget used | 3630 | 120.7 | x | x | x | x | . | x | x |
| `MC_hunt_s1_progress.cfg` | budget used | 3402 | 120.3 | x | x | x | x | . | x | x |
| `MC_hunt_s2_membership.cfg` | budget used | 3181 | 120.6 | x | x | x | . | x | x | x |
| `MC_hunt_s2_membership_residual.cfg` | budget used | 3447 | 120.7 | x | x | x | . | x | x | x |
| `MC_hunt_s3_follower_commit.cfg` | budget used | 3529 | 120.6 | x | x | x | x | . | x | x |
| `MC_hunt_s4_election.cfg` | budget used | 3632 | 120.6 | x | x | x | . | . | x | x |
| `MC_reach_commit.cfg` | budget used | 3607 | 120.7 | x | x | x | x | . | x | x |
| `MC_reach_leader.cfg` | budget used, retried | 11763 | 360.7 | x | x | x | . | . | x | x |
| `MC_reach_membership.cfg` | budget used, retried | 12191 | 360.7 | x | x | x | . | x | x | x |
| `MC_scale.cfg` | budget used | 3819 | 120.7 | x | x | x | x | x | x | x |
| `Update_discharge.cfg` | budget used | 3497 | 120.4 | x | x | x | x | x | x | x |
| `Update_focused.cfg` | budget used | 7764 | 120.5 | x | x | x | x | x | x | x |
| `Update_focused_residual.cfg` | budget used | 7982 | 120.7 | x | x | x | x | x | x | x |
| `Update_full.cfg` | budget used | 3399 | 120.5 | x | x | x | x | x | x | x |
| `Update_full_residual.cfg` | budget used | 4120 | 120.5 | x | x | x | x | x | x | x |
| `Update_hunt_u1_consequence.cfg` | budget used | 3334 | 120.4 | x | x | x | . | x | x | x |
| `Update_hunt_u1_membership_progress.cfg` | budget used | 3022 | 120.2 | x | x | x | . | x | x | x |
| `Update_hunt_u2_membership_client_loss.cfg` | budget used | 2995 | 120.2 | x | x | x | x | x | x | x |
| `Update_hunt_u2_membership_client_loss_residual.cfg` | budget used | 3107 | 120.3 | x | x | x | x | x | x | x |
| `Update_hunt_u4_reelection_crash.cfg` | budget used | 3737 | 120.3 | x | x | x | x | x | x | x |
| `Update_hunt_u4_reelection_crash_residual.cfg` | budget used | 3606 | 120.2 | x | x | x | x | x | x | x |
| `Update_open.cfg` | budget used | 3676 | 120.2 | x | x | x | x | x | x | x |
| `Update_open_residual.cfg` | budget used | 3512 | 120.3 | x | x | x | x | x | x | x |
| `Update_reach_JointQuorumCommit.cfg` | budget used, retried | 12088 | 360.4 | x | x | x | . | x | x | x |
| `Update_reach_LeaderNotFirst.cfg` | budget used, retried | 11961 | 360.4 | x | x | x | . | x | x | x |
| `Update_reach_ProgressCommit.cfg` | budget used, retried | 11242 | 360.4 | x | x | x | . | x | x | x |
| `Update_reach_ReelectedLeaderProgress.cfg` | budget used, retried | 11783 | 360.4 | x | x | x | . | . | x | x |
| `Update_reach_UpgradedWithFollowerProgress.cfg` | budget used, retried | 11816 | 360.4 | x | x | x | . | x | x | x |
