# Modeling brief coverage self-audit (updated suite, case-012)

Filled from the actual cfg files (`spec/output/cfg-static-preflight.log` resolves every cfg name).

## Scenario coverage

| Brief scenario | Base/MC actions | Hunting / update config | Trace evidence (fresh, new revision) |
|---|---|---|---|
| 1. Acknowledged progress and commit (V0) | `SendAppendEntries`, `DeliverAppendEntries`, `HandleUpdateMatched`, `UpdateProgressResult`/`VecUpdate` | `MC_hunt_s1_progress.cfg` | `progress`, `update_progress`, `u2_uniform_commit`, `quorum` |
| 2. Effective membership (V0) | `ProposeMembership` (SafeNext), `LeaderAppendEntries` membership steps, promotion | `MC_hunt_s2_membership.cfg`, `MC_reach_membership.cfg` | `leader_membership_append`, `leader_membership_no_voter_change`, `leader_membership_to_1`, `membership_update`, `update_effective_membership_leader` |
| 3. Follower commit cap (V0) | `DeliverAppendEntries`, `FollowerCommitEntries` | `MC_hunt_s3_follower_commit.cfg` | `follower_commit`, `u3_follower_no_advance` |
| 4. Ordinary elections (V0) | `StartElection`, `GrantVote`, `HandleVoteResp` | `MC_hunt_s4_election.cfg`, `MC_reach_leader.cfg` | `election`, `u1_*`/`u2_*` (Elect + HandleVoteResp) |
| U1. Progress order × membership upgrade | `LeaderAppendEntries`, `UpgradeQuorumSet`, `HandleUpdateMatched` | `Update_full*.cfg`, `Update_focused*.cfg`, `Update_open*.cfg`, `Update_hunt_u1_deep.cfg`, `MC5_u1_divergence.cfg`, canaries `Update_reach_{JointCommit,UpgradedProgress,TwoAboveCommitted}` | `u1_joint_commit_order`, `progress_upgrade`, `leader_membership_*` |
| U2. Ordinary progress commit | `ClientAppend`, `HandleUpdateMatched` | `Update_hunt_u2_uniform.cfg`, `Update_reach_LeaderProgressCommit.cfg` | `u2_uniform_commit`, `leader_fast_commit`, `update_progress` |
| U3. Follower promotion on advance | `DeliverAppendEntries`, `FollowerCommitEntries` | `Update_hunt_u3_follower.cfg`, `Update_reach_FollowerPromotion.cfg` | `u3_follower_no_advance`, `follower_commit` |
| U4. Vote counting on progress quorum set | `StartElection`, `GrantVote`, `HandleVoteResp` | `Update_hunt_u4_election.cfg`, `Update_reach_ElectedByVotes.cfg` | `election`, `u1_*`, `u2_*` |

## Invariant wiring

| Invariant | Defined | Enabled in |
|---|---|---|
| TypeOK / MCTypeOK | base / MC | every cfg; Trace.cfg |
| ElectionSafety (control) | base | MC.cfg, hunts s1-s4, Update_full*, focused/open, u2-u4, u1_deep |
| ActiveLeaderHasCommittedVote | base | MC.cfg, s4, u4 |
| CommitWithinLocalLog | base | MC.cfg, s1-s3, Update_full*, focused/open, u2, u3, u1_deep |
| CommittedLogAgreement | base | MC.cfg, s1, s3, Update_full*, focused/open, u2, u3, u1_deep, MC5_u1_divergence |
| CommitWitnessSound / UpdCommitWitnessSound | base / Update | s1, s2, Update_full(_cws), Update_focused(_cws), Update_open, u2 |
| MembershipOrder | base | MC.cfg, s2, Update_full*, focused/open, u3, u1_deep; Trace.cfg |
| OneOutstandingMembership | base | s2, Update_full.cfg, Update_focused_control, u3, Trace_keep.cfg (crash-free configs only; see changelog) |
| ProgressCommittedSupported | Update | Update_full(_pcs), Update_focused, Update_open, u2 |
| ProgressSortedAboveCommitted | Update | Update_full(_sorted), Update_focused, Update_open, u2 |
| ProgressCommittedGreatest | Update | Update_full*, focused/open (+control), u2, u3, u1_deep |
| ProgressWithinAcks | Update | Update_full*, focused/open (+control), u2, u3, u4, u1_deep |
| EnvRelyHolds / DischargeContext | Update | Update_open*.cfg / Update_discharge.cfg |

No invariant is `TRUE` or a TypeOK alias. Reachability canaries are expected violations and are not counted as findings.

## Bound disclosure

All configs use 3 servers (5 in the directed MC5 run), small term/index/action budgets and `MessageBufferBound` (≤4 messages); results are LIMITED_COVERAGE. Symmetry reduction is disabled because VecProgress order depends on node ids.
