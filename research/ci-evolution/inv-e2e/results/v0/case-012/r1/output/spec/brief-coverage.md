# Modeling brief coverage self-audit (incremental run ce863f4 → aa05a38)

V0 audit retained below the line for history; this section supersedes it for
the current suite. All tables were filled by reading the actual cfg files.

## Scenario coverage

| Scenario | Base/MC actions | Checking configs | Fresh trace evidence |
|---|---|---|---|
| S1 acknowledged progress → commit (V0) | `SendAppendEntries`, `DeliverAppendEntries`, `HandleUpdateMatched` (now via `EngineUpdateProgress`) | `MC_hunt_s1_progress(.cfg, _residual)` | `progress`, `update_progress*`, `quorum` |
| S2 effective membership (V0) | `ProposeMembership` (next_safe), `EngineUpdateEffective`, `UpdateCommitted` | `MC_hunt_s2_membership(.cfg, _residual)` | `leader_membership_append`, `membership_update`, `update_effective_*` |
| S3 follower commit cap (V0) | `DeliverAppendEntries`, `FollowerCommitEntries` | `MC_hunt_s3_follower_commit.cfg` | `follower_commit*` |
| S4 elections (V0) | `StartElection`, `GrantVote`, `HandleVoteResp` (trace) | `MC_hunt_s4_election.cfg` | `election`, `elect_multi-seg*`, `vote_resp-seg*` |
| U1 cached VecProgress commit | `PUpdate`, `EngineUpdateProgress`, `HandleUpdateMatched`, `LeaderAppendEntries` | `Update_hunt_u1_membership_progress`, `Update_hunt_u1_consequence`, `Update_full`, `Update_focused`, `Update_open` | `progress`, `progress_upgrade`, `update_progress`, `membership_change_then_acks` |
| U2 progress bounded by replication | `HandleUpdateMatched` early return, `LeaderWriteBlank`, `Crash` | `Update_hunt_u2_membership_client_loss(.cfg, _residual)` | `leader_fast_commit*`, `update_progress_no_leader` |
| U3 membership change rebuilds progress | `ProposeMembership` → `EngineUpdateEffective` → `PUpgrade` | `Update_hunt_u1_*`, `Update_full*` | `update_effective_leader`, `progress_upgrade`, `membership_change_then_acks`, `leader_fast_commit_*` |
| U4 progress lifecycle | `StartElection`, `GrantVote`, `Deliver/RejectAppend*`, `Crash` | `Update_hunt_u4_reelection_crash(.cfg, _residual)` | `elect_multi-seg*`, `vote_resp-seg*` |

## Invariant wiring (computed from cfg files)

| Property | #cfgs | Enabled in |
|---|---:|---|
| MCTypeOK | 20 | MC, MC_hunt_s1_progress, MC_hunt_s1_progress_residual, MC_hunt_s2_membership, MC_hunt_s2_membership_residual, MC_hunt_s3_follower_commit, MC_hunt_s4_election, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| ElectionSafety | 20 | MC, MC_hunt_s1_progress, MC_hunt_s1_progress_residual, MC_hunt_s2_membership, MC_hunt_s2_membership_residual, MC_hunt_s3_follower_commit, MC_hunt_s4_election, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| ActiveLeaderHasCommittedVote | 15 | MC, MC_hunt_s4_election, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| CommitWithinLocalLog | 19 | MC, MC_hunt_s1_progress, MC_hunt_s1_progress_residual, MC_hunt_s2_membership, MC_hunt_s2_membership_residual, MC_hunt_s3_follower_commit, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| CommittedLogAgreement | 17 | MC, MC_hunt_s1_progress, MC_hunt_s1_progress_residual, MC_hunt_s3_follower_commit, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| MembershipOrder | 16 | MC, MC_hunt_s2_membership, MC_hunt_s2_membership_residual, MC_scale, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| OneOutstandingMembershipDurable | 14 | MC_hunt_s2_membership, MC_hunt_s2_membership_residual, Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| CommitWitnessSound | 9 | MC_hunt_s1_progress, MC_hunt_s2_membership, Update_focused, Update_full, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u4_reelection_crash, Update_open |
| ProgressCommittedSound | 7 | Update_focused, Update_full, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u4_reelection_crash, Update_open |
| ProgressSortedAboveCommitted | 6 | Update_focused, Update_full, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u4_reelection_crash, Update_open |
| ProgressWithinReplication | 12 | Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
| ProgressTracksEffective | 12 | Update_focused, Update_focused_residual, Update_full, Update_full_residual, Update_hunt_u1_consequence, Update_hunt_u1_membership_progress, Update_hunt_u2_membership_client_loss, Update_hunt_u2_membership_client_loss_residual, Update_hunt_u4_reelection_crash, Update_hunt_u4_reelection_crash_residual, Update_open, Update_open_residual |
`OneOutstandingMembership` (V0) is no longer enabled anywhere: replaced by
`OneOutstandingMembershipDurable` (Case A, see changelog). `ProgressSortedAboveCommitted`,
`ProgressCommittedSound`, `CommitWitnessSound` are omitted only from the
`*_residual.cfg` variants, which exist to explore past finding MC-1.

## Non-vacuity / reachability canaries (expected violations = witnesses)

| Canary | Config | Witness log |
|---|---|---|
| NotReachLeader | `MC_reach_leader.cfg` | `output/mc-reach-leader.log` |
| NotReachCommitWitness | `MC_reach_commit.cfg` | `output/mc-reach-commit.log` |
| NotReachOutstandingMembership | `MC_reach_membership.cfg` | `output/mc-reach-membership.log` |
| NotReachLeaderNotFirst (U1/U3 tie order) | `Update_reach_LeaderNotFirst.cfg` | `output/upd-reach-leadernotfirst.log` |
| NotReachUpgradedWithFollowerProgress (U3) | `Update_reach_UpgradedWithFollowerProgress.cfg` | `output/upd-reach-upgraded.log` |
| NotReachJointQuorumCommit (U1/U3) | `Update_reach_JointQuorumCommit.cfg` | `output/upd-reach-jointcommit.log` |
| NotReachProgressCommit (U1/U2) | `Update_reach_ProgressCommit.cfg` | `output/upd-reach-progresscommit.log` |
| NotReachReelectedLeaderProgress (U4) | `Update_reach_ReelectedLeaderProgress.cfg` | `output/upd-reach-reelected.log` |

No property is `TRUE`, a TypeOK alias, or guarded off in every cfg. Bounds and
outcomes per run: `validation-summary.md`. All results are LIMITED_COVERAGE.

---

# Modeling brief coverage self-audit

## Scenario coverage

| Brief scenario | Base/MC actions | Hunting config | Trace evidence |
|---|---|---|---|
| 1. Acknowledged progress and commit | `SendAppendEntries`, `DeliverAppendEntries`, `HandleUpdateMatched`, `ProgressUpdateValue` | `MC_hunt_s1_progress.cfg` | `progress.ndjson`, `greatest_majority.ndjson`, `quorum.ndjson` |
| 2. Effective membership | `ProposeMembership`, atomic membership promotion in `HandleUpdateMatched`/delivery | `MC_hunt_s2_membership.cfg` | `leader_membership_append.ndjson`, `membership_update.ndjson`, joint quorum/calculation traces |
| 3. Follower commit cap | `DeliverAppendEntries`, `FollowerCommitEntries`, conflict response | `MC_hunt_s3_follower_commit.cfg` | `follower_commit.ndjson` |
| 4. Ordinary elections | `StartElection`, `GrantVote` | `MC_hunt_s4_election.cfg` | `election.ndjson` |

## Invariant wiring

| Brief invariant | Defined | MC wrapper | Enabled |
|---|---|---|---|
| TypeOK | `base.tla` | `MCTypeOK` | every cfg |
| ElectionSafety | `base.tla` | direct | MC and hunts 1/2/3/4 |
| ActiveLeaderHasCommittedVote | `base.tla` | direct | MC and hunt 4 |
| CommitWithinLocalLog | `base.tla` | direct | MC and hunts 1/2/3 |
| CommittedLogAgreement | `base.tla` | direct | MC and hunts 1/3 |
| CommitWitnessSound | `base.tla` | direct | hunts 1/2 (intentionally commented in convergence MC.cfg) |
| MembershipOrder | `base.tla` | direct | MC and hunt 2 |
| OneOutstandingMembership | `base.tla` | direct | hunt 2 (intentionally commented in convergence MC.cfg) |

## §6.1 question coverage and non-vacuity evidence

| Question | Trigger setup | Oracle | Config/evidence |
|---|---|---|---|
| MC-PRIOR-1 | election, append, send/deliver/ack with optional loss | witness quorum + committed agreement | hunt 1 completed at 30,034 distinct states; `mc-reach-commit-final.log` reaches a witness |
| MC-PRIOR-2 | propose symmetric joint/uniform configurations | membership order/outstanding guard | hunt 2 completed at 80,705 distinct states; `mc-reach-membership-final.log` reaches an outstanding effective membership |
| MC-PRIOR-3 | AppendEntries delivery with leader commit and bounded local last | local-log bound/agreement | hunt 3 completed at 12,831 distinct states; its `MCNext` delivery branch has positive coverage |
| MC-PRIOR-4 | competing ordinary elections with crash/recovery | election safety/committed-vote bit | hunt 4 completed at 30,606 distinct states with positive crash/recover coverage; `mc-reach-leader-final.log` reaches a leader |

No invariant is `TRUE`, a TypeOK alias, or guarded off in all affected configs. The final main and four hunt runs all report `Model checking completed. No error has been found.` with zero states left. Reachability runs intentionally check negated reach predicates and produce the expected counterexamples; those logs are evidence only and are not model failures. Conflict-rejection and negative-ack branches remain unexercised in the converged tight bounds and are explicitly part of the overall limited-coverage classification.

## Bound disclosure

- Converged main: 3 servers, term bound 1, index bound 0, one election and one client append, no membership/fault introduction; 12,831 distinct states.
- Scenario hunts independently enable membership, one message loss, or up to three elections plus one crash/recovery as needed. Each is exhaustive only within its own configuration.
- `MC_scale.cfg` uses term/index bound 2 and broader action/fault budgets. Its preserved 600-second run explored 10,347,332 distinct states without a reported invariant violation but retained 6,580,486 queued states, so it is evidence only—not a completed check.
- These state-space and environment bounds are `LIMITED_COVERAGE`, never proof.
