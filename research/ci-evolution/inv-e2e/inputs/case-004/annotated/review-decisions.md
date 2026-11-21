# Review decisions, one row per block

The standard I used for evidence types: a comment is `comment`/`contract` when it states a rule, a definition beyond the code, a guarantee to callers, an invariant or a reason. It is `impl` when it only describes what the code it is attached to does: an action, a step, or a one-line summary of the function.

| Property | Old status | New status | Intent changed | Evidence lines retyped / removed / added | Reason |
|---|---|---|---|---|---|
| TypeOK | model-internal | model-internal | yes | none | "Every model variable stays inside its declared domain" overstated the formula, which constrains 22 of the 37 variables (none of the durable, candidate-term/node/config, granter, leader-config/grant, committed-config, pending-vote or stale-response variables) and also bounds the log pointers; I rewrote the intent to match the formula and added a pointer to where the shared conjuncts' evidence lives. |
| IOOrder | requirement | requirement | no | none | All quotes found; log_pointers.md:27/24/15, io_progress.rs:25, 942ec78b, command.rs:76 (command-interface doc, kept) and the SaveCommitted-before-Apply test cover every conjunct. |
| CommitWithinAccepted | requirement | requirement | no | none | log_pointers.md:27-28 state committed ≤ submitted ≤ accepted for every node; I re-ran the 90c29ccb / 5a8b6758 history trail and it holds. |
| MembershipOrder | requirement | requirement | no | none | membership_state/mod.rs:23-29, effective-membership.md:16, extended-membership.md:89 and helper.rs:176 state committed-then-effective; the test at :133 asserts it. |
| MembershipWellFormed | mixed | mixed | no | arrows narrowed (not retyped): error.rs:610, change_handler.rs:29 | Both quotes say a new membership is non-empty or has a voter, not that every voter config is non-empty; the clause split stays correct. |
| LearnersExcluded | requirement | requirement | no | none | membership.rs:32/102/145 define learners as nodes in no voter config. |
| CandidateGrantSound | requirement | requirement | no | retyped comment→impl: engine_impl.rs:642, proposer/candidate.rs:106 | 642 is the one-line summary of `establish_leader`; 106 narrates the `into_committed()` call below it. raft_state/mod.rs:375, leader.rs:25, vote.md:59, raft-essentials.md:53 and three tests still support the intent. |
| LeaderVoteCommitted | requirement | requirement | no | retyped comment→impl: vote_handler/mod.rs:178 | Summary line of `become_leader`; lines 179-181 say it is not the election path, so it cannot support the "only" its arrow claimed. leader.rs:25-27, raft_state/mod.rs:375, 36d2c115 and the tests remain. |
| MatchWithinLeaderLog | mixed | mixed | no | added doc log_pointers.md:31 and log_pointers.md:27; arrow of progress/entry/mod.rs:33 narrowed; clause `leader-progress` split into `target-progress` + `self-progress` | The intent and formula include the leader's own entry (`p = n`), but every cited non-impl line was about followers/targets; the added lines come from a file already cited and cover the self entry. The :33 comment defines `searching_end`, not `matching`. |
| DurableStateBounded | requirement | requirement | no | retyped comment→impl: vote_handler/mod.rs:119 | It describes what `update_vote` does (grant, then persist); vote.md:16 (with its save_vote pseudocode) and storage/v2.rs:35 still support the vote part, and the committed part is unchanged. |
| CurrentTermCommit | requirement | requirement | no | none | replication_handler/mod.rs:198/221/224, raft_state/mod.rs:56, log_pointers.md:17 and the update_matching test state the leader-term commit rule; vote.md:16 gives monotonicity; the note honestly explains the ≤ narrowing. |
| CommittedLogAgreement | requirement | requirement | no | none | raft-essentials.md:82/84, extended-membership.md:154, log_replication.md:5/114, leader_id.md:48 and leader_id_adv.rs:11 together state committed-prefix agreement. |
| TraceMatched | model-internal | model-internal | no | none | Trace-completeness check; I re-verified the note's search (no `ndjson`/`TraceLog` in source/). |
| MCTypeOK | alias → TypeOK | alias → TypeOK | no | none | Correct one-line alias pointer (`MCTypeOK == TypeOK`). |
| MCIOOrder | alias → IOOrder | alias → IOOrder | no | none | Correct one-line alias pointer. |
| MCCommitWithinAccepted | alias → CommitWithinAccepted | alias → CommitWithinAccepted | no | none | Correct one-line alias pointer. |
| MCMembershipOrder | alias → MembershipOrder | alias → MembershipOrder | no | none | Correct one-line alias pointer. |
| MCMembershipWellFormed | alias → MembershipWellFormed | alias → MembershipWellFormed | no | none | Correct one-line alias pointer. |
| MCLearnersExcluded | alias → LearnersExcluded | alias → LearnersExcluded | no | none | Correct one-line alias pointer. |
| MCCandidateGrantSound | alias → CandidateGrantSound | alias → CandidateGrantSound | no | none | Correct one-line alias pointer. |
| MCLeaderVoteCommitted | alias → LeaderVoteCommitted | alias → LeaderVoteCommitted | no | none | Correct one-line alias pointer. |
| MCMatchWithinLeaderLog | alias → MatchWithinLeaderLog | alias → MatchWithinLeaderLog | no | none | Correct one-line alias pointer. |
| MCDurableStateBounded | alias → DurableStateBounded | alias → DurableStateBounded | no | none | Correct one-line alias pointer. |
| MCCurrentTermCommit | alias → CurrentTermCommit | alias → CurrentTermCommit | no | none | Correct one-line alias pointer. |
| MCCommittedLogAgreement | alias → CommittedLogAgreement | alias → CommittedLogAgreement | no | none | Correct one-line alias pointer. |

## Borderline comment-type calls kept as `comment`

The same standard applied in the other direction. These quotes sit on or near code but state a rule, definition, guarantee or reason, so I kept them as `comment`:

- `replication_handler/mod.rs:224`: "Only when … it is committed" states the commit rule.
- `membership.rs:198`: lists the validity criteria.
- `change_handler.rs:29`: "This function ensures that …" is a guarantee to callers.
- `command.rs:76`: documents the semantics of the Engine→Runtime `Apply` command; there is no implementing code next to it.
- `raft_state/mod.rs:375`: "granted by a quorum" is a meaning the code does not check.
- `progress/entry/mod.rs:33`: a field definition.
