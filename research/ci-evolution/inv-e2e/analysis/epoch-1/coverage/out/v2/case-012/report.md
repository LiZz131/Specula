# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CommitWitnessSound_new`, `NotReachCommitWitness`, `NotReachLeader`, `NotReachOutstandingMembership`, `NotReachProgressUpgrade`, `NotReachReelectedWitness`, `NotReachTwoCommitted`, `NotReachTwoLeaders`, `NotReachUnpromoted`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCStartElection |
| 2 | AffectedActions | MCGrantVote |
| 3 | AffectedActions | MCClientAppend |
| 4 | AffectedActions | MCProposeMembership |
| 5 | AffectedActions | MCHandleUpdateMatched |
| 6 | AffectedActions | MCDeliverAppendEntries |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---:|---:|---|---|---|---|---|---|
| `MC.cfg` | budget used | 11387 | 120.3 | x | x | x | . | x | x |
| `MC_hunt_s1_progress.cfg` | budget used | 11341 | 120.3 | x | x | x | . | x | x |
| `MC_hunt_s2_membership.cfg` | budget used | 12332 | 120.3 | x | x | . | x | x | x |
| `MC_hunt_s3_follower_commit.cfg` | budget used | 11477 | 120.3 | x | x | x | . | x | x |
| `MC_hunt_s4_election.cfg` | budget used | 16202 | 120.3 | x | x | . | . | x | x |
| `MC_hunt_u1_append_commit.cfg` | budget used | 8691 | 120.3 | x | x | x | x | x | x |
| `MC_hunt_u2_reelection.cfg` | budget used | 13349 | 120.3 | x | x | x | . | x | x |
| `MC_hunt_u3_follower_promotion.cfg` | budget used | 12765 | 120.3 | x | x | x | x | x | x |
| `MC_reach_commit.cfg` | budget used | 11243 | 120.3 | x | x | x | . | x | x |
| `MC_reach_ev_TwoCommitted.cfg` | budget used, retried | 45367 | 360.5 | x | x | x | . | x | x |
| `MC_reach_ev_TwoLeaders.cfg` | budget used, retried | 45315 | 360.5 | x | x | x | . | x | x |
| `MC_reach_leader.cfg` | budget used, retried | 49007 | 360.5 | x | x | . | . | x | x |
| `MC_reach_membership.cfg` | budget used, retried | 44253 | 360.5 | x | x | . | x | x | x |
| `MC_reach_u1_append_commit.cfg` | budget used | 8671 | 120.3 | x | x | x | x | x | x |
| `MC_reach_u2_reelection.cfg` | budget used | 13766 | 120.3 | x | x | x | . | x | x |
| `MC_reach_u3_follower_promotion.cfg` | budget used | 12573 | 120.3 | x | x | x | x | x | x |
| `MC_reach_u4_upgrade.cfg` | budget used, retried | 44061 | 360.4 | x | x | . | x | x | x |
| `MC_scale.cfg` | budget used | 14386 | 120.2 | x | x | x | x | x | x |
| `Update_discharge.cfg` | budget used | 15332 | 120.2 | x | x | x | x | x | x |
| `Update_focused.cfg` | budget used | 10865 | 120.2 | x | x | x | x | x | x |
| `Update_full.cfg` | budget used | 14036 | 120.2 | x | x | x | x | x | x |
| `Update_open.cfg` | budget used | 10139 | 120.2 | x | x | x | x | x | x |
