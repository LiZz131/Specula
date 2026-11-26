# Bug Report — OpenRaft Pre-Vote update (case-011, run incr-4e410cd184be)

## Summary

- Disposition: MODEL_CHANGE_REQUIRED (reported MODEL_UPDATED); source `3ab6cdd` (`update`).
- Scenarios tested: U1–U5 (see `modeling-brief.md`) plus the standard reference round.
- Bugs found: 3 (MC-1, MC-2, MC-3), all reproduced on the updated implementation
  through the public `Raft` API (`spec/confirmation-MC-*.md`).
- All campaigns are bounded; budget-stopped runs are `LIMITED_COVERAGE`, not proofs.

## Bug 1: Timer-started Pre-Vote round survives leader establishment and makes the new leader re-elect

- **Scenario**: U1
- **Severity**: High
- **Invariant violated**: `TickPreVoteRoundNotHeldByLeader` (state) and `LeaderNotPreemptedByTimerPreVote` (action)
- **Config**: `Update_hunt_stale_round.cfg`, `Update_hunt_stale_round_consequence.cfg` (also `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`)
- **Counterexample**: 9 states (`spec/output/upd-hunt-stale-round.log`), 12 states
  (`spec/output/upd-hunt-stale-round-consequence.log`, `spec/output/cex/MC-1-stale-round.json`)

### Trace Summary

1. `ExternalElect(1)`: node 1 Candidate at term 1 (vote (1,1)), SaveVote/SendVote queued.
2. `PersistVote(1)`: own grant emitted. 3. `TickPreElect(1)`: timer fires while Candidate,
   Pre-Vote round (2,1) over {1,2,3}, requests sent. 4–9. vote request reaches node 3, node 3
   grants and persists, node 1 counts {1,3}: Leader at (1,1,committed) — round still active
   (state 9 violates `TickPreVoteRoundNotHeldByLeader`).
10–12. node 1 persists the committed vote; node 3's Pre-Vote grant arrives; quorum
   {1,3} -> `elect()` from the Leader: vote (2,1,uncommitted), role Candidate, Leader object kept.

### Root Cause

`establish_leader` (openraft/src/engine/engine_impl.rs:855-881) takes only
`self.candidate`; its `update_vote(committed)` goes through
`update_internal_server_state -> become_leader` (vote_handler/mod.rs:154-231), which
does not clear `pre_candidate` (only `do_elect` 263-264 and `become_following`
242-244 do). `handle_tick_election` (core/raft_core.rs:1959-2036) starts rounds for
Candidates; the PreVoteResponse gate (raft_core.rs:1803-1820, 2067-2090) only checks
presence and leader id; `handle_pre_vote_resp` calls `elect()` with no role check
(engine_impl.rs:533-541).

### Affected Code

- `openraft/src/engine/engine_impl.rs:855-881`: establish_leader keeps the round
- `openraft/src/engine/handler/vote_handler/mod.rs:154-231`: become_leader keeps the round
- `openraft/src/engine/engine_impl.rs:533-541`: round quorum -> elect() without re-check
- `openraft/src/core/raft_core.rs:1959-2036`: timer pre-vote while Candidate

### Recommendation

Clear `pre_candidate` on leader establishment (and whenever the vote changes), and
re-check role/vote before `elect()` in `handle_pre_vote_resp`.

## Bug 2: Completed Pre-Vote round elects a node that left the voters; its self-grant panics RaftCore

- **Scenario**: U3
- **Severity**: Medium
- **Invariant violated**: `CandidateGrantsWithinFrozenVoters`
- **Config**: `Update_hunt_nonvoter_elect_cont.cfg` (MC-1 properties filtered); also full
  `MCNext` simulation `Update_full_cont1.cfg`
- **Counterexample**: 17 states (`spec/output/upd-hunt-nonvoter-cont.log`); 33 states
  (`spec/output/upd-full-cont1-sim.log`, external-trigger producer)

### Trace Summary

Node 1 becomes Leader with a live Pre-Vote round frozen on {1,2} (MC-1 producer in
the hunt; an explicit `ExternalPreElect` on the leader in the full simulation),
appends the joint config <<{1,2},{2}>>, commits it, appends <<{2}>> (node 1 no longer
a voter), the round's grant arrives -> quorum on the frozen {1,2} -> `ElectEffects`
for a learner-member non-voter: Candidate over {2}; `PersistVote(1)` emits the local
grant; counting it puts node 1 into a candidate's grants outside its quorum set.

### Root Cause

`handle_pre_vote_resp` (engine_impl.rs:515-554) lacks the `is_voter` check that every
old `elect()` caller performs (raft_core.rs:1683-1684, 1971-1974). `do_elect` builds the
candidate over the current voters; the runtime self-grant (raft_core.rs:2290-2302)
reaches `Candidate::grant_by` whose `expect("target not in quorum set")`
(proposer/candidate.rs:107) panics.

### Affected Code

- `openraft/src/engine/engine_impl.rs:515-554`
- `openraft/src/engine/engine_impl.rs:262-289`
- `openraft/src/core/raft_core.rs:2290-2302`
- `openraft/src/proposer/candidate.rs:106-107`

### Recommendation

Re-check voter status before `elect()` in `handle_pre_vote_resp`; drop rounds when
the node leaves the voters.

## Bug 3: Repeated Pre-Vote round counts a delayed grant from a removed node; RaftCore panics

- **Scenario**: U4
- **Severity**: Medium
- **Invariant violated**: `PreVoteGrantsWithinFrozenVoters` (initially found under the
  in-flight form `PreVoteResponseFromFrozenVoter`, see `spec/invariant-evidence.json`)
- **Config**: `Update_hunt_repeat_round_cont.cfg`
- **Counterexample**: 16 states (`spec/output/upd-hunt-repeat-round-cont.log`, `spec/output/cex/repeat-round.json`)

### Trace Summary

ExternalElect(1) and PersistVote(1); ExternalPreElect(1) while Candidate starts round A
(2,1) over {1,2,3}; node 3 grants the vote and round A (grant delayed); node 1 becomes
Leader (round A kept, MC-1 mechanism); AppendJointConfig(1, {1,2}), CommitMembership(1),
AppendUniformConfig(1) [effective {1,2}]; ExternalPreElect(1) starts round B at the same
(2,1) over {1,2}; node 3's round-A grant matches round B's leader id and is counted
although node 3 is not in round B's quorum set (state 16).

### Root Cause

`does_pre_candidate_vote_match` (raft_core.rs:2067-2090) correlates by leader id only,
rounds at an unchanged vote share it (`pre_elect`, engine_impl.rs:297-322), and
`handle_pre_vote_resp` calls `grant_by(&target)` for any granted response
(engine_impl.rs:533-536) -> `expect` panic (candidate.rs:107).

### Affected Code

- `openraft/src/core/raft_core.rs:2067-2090`
- `openraft/src/engine/engine_impl.rs:297-322`, `:533-536`
- `openraft/src/proposer/candidate.rs:106-107`

### Recommendation

Correlate responses with the round instance and ignore grants from outside the
round's quorum set.

---

## Not Reproduced / no violation within bounds

| Scenario | Config | Result |
|---|---|---|
| Reference safety set (standard round) | `MC.cfg`, `MC-membership.cfg` (+ simulation) | no violation; budget-stopped (LIMITED_COVERAGE) |
| U2 side-effect-free pre-vote (`PreVoteStepsDoNotPersist`, `PreVoteElectionAtProbedVote`) | all Update cfgs | no violation; falsifiable (mutants MUT-A/MUT-B violate them) |
| U5 network default grant + crash/restart | `Update_hunt_default_grant*.cfg` | only MC-1 (known); see table |
| Reference properties on the update state space (MC-1..3 filtered) | `Update_*_cont2.cfg` | see table |
| Discharge of `EnvUpdate` for omitted `FlushLog` | `Update_discharge.cfg` | no violation; budget-stopped |

## Spec fixes during validation/hunting

- Prior-model defects repaired: leader lease on establishment, empty-log comparison
  (`LogLE`), tick-only `seen_greater_log` reset (`spec/changelog.md`).
- Property revision: in-flight forms of the two grant-precondition properties were
  replaced by point-of-counting forms after the repaired-model control showed the
  in-flight form rejects a legal state (`spec/invariant-evidence.json`).

## Campaign outcomes

Generated by `harness/summarize-campaigns.py` from the TLC logs (`spec/output/campaign-summary.md`). "budget-stopped" = TLC stopped at its time budget with states left on the queue (LIMITED_COVERAGE); scratch probes, canaries (expected violations) and trace runs are included for completeness; `*-INVALIDATED-prelogfix` runs were stopped after the LogLE repair and are not credited.

| run (spec/output/<run>.log) | cfg | mode | outcome | states | BFS depth |
|---|---|---|---|---|---|
| canary-CanaryNoPreVoteRound | Update_canary_CanaryNoPreVoteRound.cfg | BFS | VIOLATION: Invariant CanaryNoPreVoteRound is violated | 4 distinct, queue 0 | 3 |
| canary-CanaryNoTickRoundWhileCandidate | Update_canary_CanaryNoTickRoundWhileCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoTickRoundWhileCandidate is violated | 206 distinct, queue 166 | 5 |
| canary_CanaryNoGrantedPreVoteResp | Update_canary_CanaryNoGrantedPreVoteResp.cfg | BFS | VIOLATION: Invariant CanaryNoGrantedPreVoteResp is violated | 41 distinct, queue 35 | 4 |
| canary_CanaryNoLeaseRejectedPreVote | Update_canary_CanaryNoLeaseRejectedPreVote.cfg | BFS | VIOLATION: Invariant CanaryNoLeaseRejectedPreVote is violated | 84366 distinct, queue 46349 | 11 |
| canary_CanaryNoNonVoterCandidate | Update_canary_CanaryNoNonVoterCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoNonVoterCandidate is violated | 7388 distinct, queue 3286 | 15 |
| canary_CanaryNoPreVoteElection | Update_canary_CanaryNoPreVoteElection.cfg | BFS | VIOLATION: Action property CanaryNoPreVoteElection is violated | 274 distinct, queue 226 | 5 |
| canary_CanaryNoPreVoteRound | Update_canary_CanaryNoPreVoteRound.cfg | BFS | VIOLATION: Invariant CanaryNoPreVoteRound is violated | 4 distinct, queue 0 | 3 |
| canary_CanaryNoRepeatedRoundOtherConfig | Update_canary_CanaryNoRepeatedRoundOtherConfig.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 1562395 distinct, queue 868539 | 14 |
| canary_CanaryNoRoundClearedByFollowing | Update_canary_CanaryNoRoundClearedByFollowing.cfg | BFS | VIOLATION: Action property CanaryNoRoundClearedByFollowing is violated | 763 distinct, queue 579 | 6 |
| canary_CanaryNoTickRoundWhileCandidate | Update_canary_CanaryNoTickRoundWhileCandidate.cfg | BFS | VIOLATION: Invariant CanaryNoTickRoundWhileCandidate is violated | 119 distinct, queue 97 | 5 |
| mc-membership-INVALIDATED-prelogfix | MC-membership.cfg | BFS | exit 143 |  |  |
| mc-membership | MC-membership.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8743435 distinct, queue 2622839 | 24 |
| mc-standard-INVALIDATED-prelogfix | MC.cfg | BFS | exit 143 |  |  |
| mc-standard-sim | MC.cfg | simulation | no violation (simulation budget: LIMITED_COVERAGE) | 26194968 states, 249092 traces |  |
| mc-standard | MC.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 15076494 distinct, queue 8332562 | 19 |
| probe-P1 | scratch/probe-P1.cfg | BFS | VIOLATION: Invariant P1 is violated | 6062 distinct, queue 2894 | 10 |
| probe-P2 | scratch/probe-P2.cfg | BFS | VIOLATION: Invariant P2 is violated | 718 distinct, queue 464 | 7 |
| probe-P3 | scratch/probe-P3.cfg | BFS | VIOLATION: Invariant P3 is violated | 319 distinct, queue 224 | 6 |
| probe-P4 | scratch/probe-P4.cfg | BFS | VIOLATION: Invariant P4 is violated | 2333 distinct, queue 1239 | 9 |
| probe-P5 | scratch/probe-P5.cfg | BFS | no violation (state space exhausted) | 46592 distinct, queue 0 | 18 |
| probe-P6 | scratch/probe-P6.cfg | BFS | no violation (state space exhausted) | 46592 distinct, queue 0 | 18 |
| trace-append_joint_membership | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-commit_membership | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-establish_leader | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-grant_greater_vote | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_elect_multi | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_elect_single_voter | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_cleared_by_vote_request | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-pre_vote_req_grant | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_req_lease_reject | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_req_stale_log | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_resp_no_round | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-pre_vote_resp_quorum | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-pre_vote_resp_reject_greater_log | Trace.cfg | BFS | no violation (state space exhausted) | 3 distinct, queue 0 | 3 |
| trace-reject_stale_log | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-restart_follower | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| trace-stale_pre_vote_after_leader | Trace.cfg | BFS | no violation (state space exhausted) | 14 distinct, queue 0 | 12 |
| trace-start_election | Trace.cfg | BFS | no violation (state space exhausted) | 2 distinct, queue 0 | 2 |
| upd-discharge | Update_discharge.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 6470776 distinct, queue 3809506 | 15 |
| upd-focused-cont1 | Update_focused_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 9459668 distinct, queue 6244512 | 13 |
| upd-focused-cont2 | Update_focused_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7219986 distinct, queue 4797280 | 13 |
| upd-focused | Update_focused.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 565967 distinct, queue 409577 | 10 |
| upd-full-cont1-sim | Update_full_cont1.cfg | simulation | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 61787 states, 679 traces |  |
| upd-full-cont1 | Update_full_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8861373 distinct, queue 5079289 | 14 |
| upd-full-cont2-sim | Update_full_cont2.cfg | simulation | no violation (simulation budget: LIMITED_COVERAGE) | 28603396 states, 312813 traces |  |
| upd-full-cont2 | Update_full_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 10765210 distinct, queue 6136315 | 16 |
| upd-full | Update_full.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 343978 distinct, queue 232642 | 10 |
| upd-hunt-default-grant-cont2 | Update_hunt_default_grant_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7413970 distinct, queue 3937828 | 13 |
| upd-hunt-default-grant | Update_hunt_default_grant.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 402065 distinct, queue 262451 | 10 |
| upd-hunt-nonvoter-cont | Update_hunt_nonvoter_elect_cont.cfg | BFS | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 22143 distinct, queue 9206 | 18 |
| upd-hunt-nonvoter | Update_hunt_nonvoter_elect.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 715 distinct, queue 213 | 10 |
| upd-hunt-repeat-round-cont-sim | Update_hunt_repeat_round_cont.cfg | simulation | VIOLATION: Invariant CandidateGrantsWithinFrozenVoters is violated | 1209588 states, 18580 traces |  |
| upd-hunt-repeat-round-cont | Update_hunt_repeat_round_cont.cfg | BFS | VIOLATION: Invariant PreVoteGrantsWithinFrozenVoters is violated | 8817426 distinct, queue 5403649 | 18 |
| upd-hunt-repeat-round | Update_hunt_repeat_round.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 36404 distinct, queue 20856 | 11 |
| upd-hunt-stale-round-consequence | Update_hunt_stale_round_consequence.cfg | BFS | VIOLATION: Action property LeaderNotPreemptedByTimerPreVote is violated | 36288 distinct, queue 14840 | 13 |
| upd-hunt-stale-round | Update_hunt_stale_round.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 5161 distinct, queue 2505 | 10 |
| upd-open-cont1 | Update_open_cont1.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 8739467 distinct, queue 5694632 | 14 |
| upd-open-cont2 | Update_open_cont2.cfg | BFS | no violation (budget-stopped: LIMITED_COVERAGE) | 7149034 distinct, queue 4766416 | 13 |
| upd-open | Update_open.cfg | BFS | VIOLATION: Invariant TickPreVoteRoundNotHeldByLeader is violated | 365126 distinct, queue 267683 | 11 |
