# Confirmation Report

Reproduced bugs: 3; other unresolved findings: 0; other dispositions: 0.

| Entry | Finding | Status | Counts as final bug? |
|---|---|---|---|
| 1 | MC-1 | REPRODUCED | yes |
| 2 | MC-2 | REPRODUCED | yes |
| 3 | MC-3 | REPRODUCED | yes |

## Entry 1: Timer-started Pre-Vote round survives leader establishment and makes the new leader re-elect

- **Finding ID**: MC-1
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: handle_tick_election starts a Pre-Vote round for a Candidate whose election timed out; establish_leader/become_leader do not clear pre_candidate, and handle_pre_vote_resp calls elect() on the round's quorum without re-checking role or vote.
- **Trigger scenario**: With enable_pre_vote, a candidate's real election outlives its election timeout (e.g. slow vote persistence); the timer starts a Pre-Vote round at term+1; the real quorum then makes it Leader; the round's quorum arrives afterwards.
- **Impact**: The established leader starts a new election at term+1 without any external request or higher term: leadership is abandoned and the term inflates; the stale Leader object (vote behind state.vote) trips the try_leader_handler assertion (RaftCore panic in debug builds) and, in release builds, the cluster stayed leaderless with the term inflating.
- **Evidence**: [evidence 1](<spec/confirmation-MC-1.md>), [evidence 2](<spec/output/upd-hunt-stale-round-consequence.log>), [evidence 3](<spec/output/upd-hunt-stale-round.log>), [evidence 4](<spec/repro/t90_specular_pre_vote_repro.rs>), [evidence 5](<spec/repro/test_bug1_mc1_stale_timer_pre_vote.sh>), [evidence 6](<spec/repro/specular_mc1_timer_pre_vote_round_preempts_new_leader.run2.log>), [evidence 7](<spec/repro/specular_mc1_timer_pre_vote_round_preempts_new_leader.release.log>), [evidence 8](<spec/repro/specular_mc1_timer_pre_vote_round_preempts_new_leader.fixctl.log>), [evidence 9](<traces/stale_pre_vote_after_leader.ndjson>)

## Entry 2: Completed Pre-Vote round elects a node that left the voters; its self-grant panics RaftCore

- **Finding ID**: MC-2
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: handle_pre_vote_resp calls elect() without the is_voter check performed by every old elect() caller; do_elect then builds a candidate over voters that exclude the node and the runtime's local self-grant reaches Candidate::grant_by, whose expect panics.
- **Trigger scenario**: A Pre-Vote round is in flight on a leader (explicit trigger().elect(true), or a stale timer round from MC-1) while the leader removes itself from the voters (kept as learner); the round's grants arrive after the change.
- **Impact**: RaftCore panics ('target not in quorum set') and the node stops serving (Fatal::Panicked), in debug and release builds.
- **Evidence**: [evidence 1](<spec/confirmation-MC-2.md>), [evidence 2](<spec/output/upd-hunt-nonvoter-cont.log>), [evidence 3](<spec/output/upd-full-cont1-sim.log>), [evidence 4](<spec/repro/t90_specular_pre_vote_repro.rs>), [evidence 5](<spec/repro/test_bug2_mc2_nonvoter_elect_panic.sh>), [evidence 6](<spec/repro/specular_mc2_pre_vote_round_elects_removed_voter.run2.log>), [evidence 7](<spec/repro/specular_mc2_pre_vote_round_elects_removed_voter.backtrace.log>), [evidence 8](<spec/repro/specular_mc2_pre_vote_round_elects_removed_voter.release.log>)

## Entry 3: Repeated Pre-Vote round at the same hypothetical vote counts a delayed grant from a removed node; RaftCore panics

- **Finding ID**: MC-3
- **Status**: REPRODUCED
- **Source**: MC
- **Confirmation**: Current confirmation.
- **Description**: Rounds started at an unchanged vote probe the same (term+1, self); the PreVoteResponse gate correlates by leader id only, and handle_pre_vote_resp calls grant_by for any granted response, which panics for a node outside the new round's quorum set.
- **Trigger scenario**: Round A over {0,1,2}; node 1's grant is delayed; node 1 is removed from the voters; round B is started at the same vote over {0,2}; node 1's round-A grant arrives within the RPC timeout.
- **Impact**: RaftCore panics ('target not in quorum set') and the node stops serving, in debug and release builds.
- **Evidence**: [evidence 1](<spec/confirmation-MC-3.md>), [evidence 2](<spec/output/upd-hunt-repeat-round-cont.log>), [evidence 3](<spec/repro/t90_specular_pre_vote_repro.rs>), [evidence 4](<spec/repro/test_bug3_mc3_repeated_round_removed_grant_panic.sh>), [evidence 5](<spec/repro/specular_mc3_repeated_pre_vote_round_accepts_removed_node_grant.run2.log>), [evidence 6](<spec/repro/specular_mc3_repeated_pre_vote_round_accepts_removed_node_grant.backtrace.log>), [evidence 7](<spec/repro/specular_mc3_repeated_pre_vote_round_accepts_removed_node_grant.release.log>)

## Validation limits

- All TLC campaigns are bounded (3 nodes, 2 in one hunt; terms <= 2-3; log index <= 3-4; bounded elections, pre-vote rounds, membership changes, crashes, drops, messages) and most BFS runs stopped at their time budget with states left on the queue (LIMITED_COVERAGE), followed by bounded simulation; no exhaustive pass or proof is claimed.
- Membership learners and follower-side membership changes are not modelled; the non-voter election outcome is a nondeterministic union, and the follower variant of MC-3 is covered only by source analysis.
- The engine-level harness captures the frozen candidate/pre-candidate quorum through the effective membership (private field); no traced scenario changes membership after a round starts.
- Timer, lease and RPC-timeout behaviour are abstracted as enablement nondeterminism; their effect is exercised only by the runtime reproductions.
- MC-1's runtime reproduction needs timing assistance (slow vote persistence emulated in the test store plus RPC hook delays); a pure black-box Level-0 attempt did not hit the window.
- Old-revision controls are not runnable because the Pre-Vote API does not exist in the old revision; attribution to the update rests on source comparison.
- External issue trackers were not consulted (blinded run); novelty is NEW with respect to the supplied tree only.
