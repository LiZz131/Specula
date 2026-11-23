# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CommitWitnessSound`, `NotReachCommitWitness`, `NotReachElectedByVotes`, `NotReachFollowerPromotion`, `NotReachJointCommit`, `NotReachLeader`, `NotReachLeaderProgressCommit`, `NotReachOutstandingMembership`, `NotReachTwoAboveCommitted`, `NotReachUpgradedProgress`, `UpdCommitWitnessSound`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | ClientAppendFocus | MCClientAppend |
| 2 | ProposeMembershipFocus | MCProposeMembership |
| 3 | HandleUpdateMatchedFocus | MCHandleUpdateMatched |
| 4 | ElectionFocus | MCStartElection |
| 5 | ElectionFocus | MCGrantVote |
| 6 | FollowerFocus | MCDeliverAppendEntries |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---:|---:|---|---|---|---|---|---|
| `MC.cfg` | budget used | 8003 | 120.3 | x | . | x | x | x | x |
| `MC_hunt_s1_progress.cfg` | budget used | 7710 | 120.3 | x | . | x | x | x | x |
| `MC_hunt_s2_membership.cfg` | budget used | 6434 | 120.3 | . | x | x | x | x | x |
| `MC_hunt_s3_follower_commit.cfg` | budget used | 9785 | 120.3 | x | . | x | x | x | x |
| `MC_hunt_s4_election.cfg` | budget used | 12136 | 120.3 | . | . | x | x | x | x |
| `MC_reach_commit.cfg` | budget used | 9799 | 120.3 | x | . | x | x | x | x |
| `MC_reach_leader.cfg` | budget used, retried | 39768 | 360.5 | . | . | x | x | x | x |
| `MC_reach_membership.cfg` | budget used, retried | 25628 | 360.5 | . | x | x | x | x | x |
| `MC_scale.cfg` | budget used | 5407 | 120.3 | x | x | x | x | x | x |
| `Update_discharge.cfg` | budget used | 8631 | 120.3 | x | x | x | x | x | x |
| `Update_focused.cfg` | budget used | 7254 | 120.3 | x | x | x | x | x | x |
| `Update_focused_control.cfg` | budget used | 4917 | 120.3 | x | x | x | x | x | x |
| `Update_focused_cws.cfg` | budget used | 7272 | 120.3 | x | x | x | x | x | x |
| `Update_full.cfg` | budget used | 5083 | 120.3 | x | x | x | x | x | x |
| `Update_full_control.cfg` | budget used | 5103 | 120.3 | x | x | x | x | x | x |
| `Update_full_cws.cfg` | budget used | 5152 | 120.3 | x | x | x | x | x | x |
| `Update_full_faults.cfg` | budget used | 8881 | 120.3 | x | x | x | x | x | x |
| `Update_full_faults_control.cfg` | budget used | 8598 | 120.3 | x | x | x | x | x | x |
| `Update_full_pcs.cfg` | budget used | 5110 | 120.2 | x | x | x | x | x | x |
| `Update_full_sorted.cfg` | budget used | 7293 | 120.3 | x | x | x | x | x | x |
| `Update_hunt_u1_deep.cfg` | budget used | 4096 | 120.2 | x | x | x | x | x | x |
| `Update_hunt_u2_uniform.cfg` | budget used | 5052 | 120.3 | x | . | x | x | x | x |
| `Update_hunt_u3_follower.cfg` | budget used | 7990 | 120.3 | x | x | x | x | x | x |
| `Update_hunt_u4_election.cfg` | budget used | 11927 | 120.3 | . | . | x | x | x | x |
| `Update_open.cfg` | budget used | 12419 | 120.2 | x | x | x | x | x | x |
| `Update_open_control.cfg` | budget used | 12370 | 120.2 | x | x | x | x | x | x |
| `Update_reach_ElectedByVotes.cfg` | budget used | 6899 | 120.3 | x | x | x | x | x | x |
| `Update_reach_FollowerPromotion.cfg` | budget used | 6128 | 120.3 | x | x | x | x | x | x |
| `Update_reach_JointCommit.cfg` | budget used | 7162 | 120.3 | x | x | x | x | x | x |
| `Update_reach_LeaderProgressCommit.cfg` | budget used | 6810 | 120.2 | x | x | x | x | x | x |
| `Update_reach_TwoAboveCommitted.cfg` | budget used | 6719 | 120.2 | x | x | x | x | x | x |
| `Update_reach_UpgradedProgress.cfg` | budget used | 7248 | 120.3 | x | x | x | x | x | x |
