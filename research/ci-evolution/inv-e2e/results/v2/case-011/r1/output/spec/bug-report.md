# Bug Report — OpenRaft Pre-Vote revision (incremental run)

## Summary

- Source: artifact commit `update` 3ab6cdd (Pre-Vote feature) vs `baseline` 1adc857.
- Update Scenarios tested: U1–U6 (`modeling-brief.md`, update section).
- Bugs found: 2 (both model-checking counterexamples, both reproduced end-to-end on the new revision).
- Configs run: see the campaign table below (all budget-limited: `LIMITED_COVERAGE`).

## Bug 1: A timer Pre-Vote round outlives the node's own leader establishment and demotes the new leader

- **ID**: MC-1
- **Scenario**: U2
- **Severity**: High
- **Property violated**: `TimerPreVoteElectsOnlyNonLeader` (`spec/UpdateProps.tla`)
- **Configs**: `MC_hunt_U2_prevote_leader.cfg` (13 states), `Update-full-U2.cfg` (complete MCNext, 14 states)
- **Counterexamples**: `spec/output/MC-1_TimerPreVoteElectsOnlyNonLeader_cex.out`,
  `spec/output/MC-1_TimerPreVoteElectsOnlyNonLeader_fullMCNext_cex.out`
- **Trace evidence**: `traces/prevote_stale_round_after_leadership.ndjson` (TLC evaluates the property to FALSE
  on the replayed implementation transition: `spec/evidence/E-U2-sep/tlc.log`)
- **Reproduction**: `spec/confirmation-MC-1.md` (end-to-end RaftCore test, 3/3 runs)

### Trace Summary (full-MCNext counterexample)

1. Node 2's election timer starts a real election (term 1) and persists its vote; node 2 sends vote requests.
2. Node 2's timer fires again while it is still a **Candidate**; with Pre-Vote enabled it starts a Pre-Vote
   round for the probe (term 2, node 2) — the running candidate is untouched.
3. A peer grants node 2's real vote; node 2 reaches quorum and becomes **Leader** (term 1, committed). The
   Pre-Vote round is still live (establish_leader/become_leader do not clear it).
4. The same peer (still holding the uncommitted term-1 vote, no lease) grants the term-2 Pre-Vote.
5. Node 2 counts the grant, reaches the Pre-Vote quorum and calls `elect()`: it becomes a Candidate at term 2
   while its Leader object of term 1 remains (`leaderActive` stays TRUE).

### Root Cause

- `openraft/src/core/raft_core.rs:1959-2036` (`handle_tick_election`): on a Candidate the timer calls
  `pre_elect()`; `engine_impl.rs:297-322` keeps the running candidate.
- `openraft/src/engine/engine_impl.rs:855-881` (`establish_leader`) and
  `engine/handler/vote_handler/mod.rs:172-228` (`become_leader`) do not clear `pre_candidate`; only
  `do_elect` (`engine_impl.rs:264`) and `become_following` (`vote_handler/mod.rs:244`) do.
- `openraft/src/core/raft_core.rs:1815-1816,2067-2090`: the response is accepted on leader-id equality alone.
- `openraft/src/engine/engine_impl.rs:534-539` (`handle_pre_vote_resp`): `elect()` without the leader/voter/
  enable_elect checks every other `elect()` caller performs.
- `vote_handler/mod.rs:154-161`: the `is_leading` branch keeps the Leader object; `engine_impl.rs:977-982`
  (`try_leader_handler`) asserts `leader.vote >= state.vote`, which the heartbeat tick reaches next.

### Affected Code

- `openraft/src/engine/engine_impl.rs:516-554` — Pre-Vote quorum calls `elect()` unconditionally.
- `openraft/src/engine/engine_impl.rs:855-881`, `openraft/src/engine/handler/vote_handler/mod.rs:172-228` — leadership
  established without cancelling the Pre-Vote round.
- `openraft/src/core/raft_core.rs:1959-2036` — timer starts Pre-Vote on a Candidate.

### Recommendation

Cancel the Pre-Vote round whenever the node becomes Leader (or whenever the vote/leadership changes,
e.g. in `establish_leader`/`become_leader`), and re-check the trigger preconditions (not Leader, voter,
`enable_elect`) before `handle_pre_vote_resp` calls `elect()`.

---

## Bug 2: Pre-Vote responses of an earlier round are counted by a later round with the same probe; after a membership change `grant_by` panics

- **ID**: MC-2
- **Scenario**: U4
- **Severity**: Medium
- **Property violated**: `StalePreVoteResponseIgnored` (`spec/UpdateProps.tla`); consequence property
  `PreVoteResponseNeverPanics`
- **Configs**: `MC_hunt_U4_prevote_stale_round.cfg` (6 states), `Update.cfg` (complete MCNext, 7 states),
  `MC_hunt_U4c_prevote_panic_operator.cfg` (`PreVoteResponseNeverPanics`, 16 states)
- **Counterexamples**: `spec/output/MC-2_StalePreVoteResponseIgnored_cex.out`,
  `spec/output/MC-2_StalePreVoteResponseIgnored_fullMCNext_cex.out`,
  `spec/output/MC-2_PreVoteResponseNeverPanics_cex.out`
- **Reproduction**: `spec/confirmation-MC-2.md` (end-to-end RaftCore test, 3/3 runs, RaftCore panics)

### Trace Summary (hunt counterexample)

1. Node 2 starts a Pre-Vote round (round 1) for the probe (term 1, node 2).
2. An operator Pre-Vote (`trigger().elect(true)`) on node 2 starts round 2 for the **same** probe.
3. Node 3 answers round 1's request with a grant.
4. Node 2 counts that round-1 grant in round 2, reaches quorum and starts a real election.

Panic counterexample (16 states): node 1 gets an operator round while it is a Candidate, wins its election
(the round survives, as in MC-1), node 3 grants the probe, the leader replaces {1,2,3} by {1,2}, a second
operator round over {1,2} receives node 3's round-1 grant and `grant_by` panics (node 1 crashes). The
end-to-end reproduction shows the same crash on a follower whose membership changed through replication.

### Root Cause

- `openraft/src/core/raft_core.rs:2066-2090` (`does_pre_candidate_vote_match`): correlation by probed leader id
  only, contradicting its own comment "If a Pre-Vote response is for a previous Pre-Vote round, it is stale and
  should be ignored."
- `openraft/src/engine/engine_impl.rs:297-322`: a round never changes the vote, so rounds at the same term share
  the probe; `openraft/src/core/raft_core.rs:1683-1696`: operator rounds are not rate limited.
- `openraft/src/proposer/candidate.rs:107`: `grant_by` `expect`s quorum-set membership.

### Affected Code

- `openraft/src/core/raft_core.rs:1803-1820,2067-2090`
- `openraft/src/engine/engine_impl.rs:534-539`
- `openraft/src/proposer/candidate.rs:106-112`

### Recommendation

Identify a Pre-Vote round by more than the probed vote (e.g. the pre-candidate's progress id / start time
carried in the notification) and ignore responses of other rounds; make `handle_pre_vote_resp` ignore
targets outside the round's quorum set instead of panicking.

---

## Campaigns

| Campaign | Config (module Update unless MC) | Mode | Budget | Outcome | Coverage |
|---|---|---|---|---|---|
| MC-membership | MC-membership.cfg | bfs | 30m | no violation (budget-limited) | 5236772 distinct, depth 22, queue 1777796 |
| MC-standard | MC.cfg | bfs | 30m | no violation (budget-limited) | 15927777 distinct, depth 17, queue 8583486 |
| Update-discharge-sim | Update-discharge.cfg | sim | 30m | no violation (budget-limited) | 23211242 states checked, 73110 traces, mean length 27 |
| Update-discharge | Update-discharge.cfg | bfs | 30m | no violation (budget-limited) | 2026313 distinct, depth 14, queue 1250509 |
| Update-focused-residual-sim | Update-focused-residual.cfg | sim | 30m | no violation (budget-limited) | 16615589 states checked, 191760 traces, mean length 33 |
| Update-focused-residual | Update-focused-residual.cfg | bfs | 30m | no violation (budget-limited) | 7549951 distinct, depth 17, queue 3620853 |
| Update-full-U2 | Update-full-U2.cfg | bfs | 30m | VIOLATION TimerPreVoteElectsOnlyNonLeader (14-state trace) | 5172975 distinct, depth 14, queue 3009039 |
| Update-full | Update.cfg | bfs | 30m | VIOLATION StalePreVoteResponseIgnored (7-state trace) | 2388 distinct, depth 8, queue 1963 |
| Update-open-residual-sim | Update-open-residual.cfg | sim | 30m | no violation (budget-limited) | 40631662 states checked, 225713 traces, mean length 27 |
| Update-open-residual | Update-open-residual.cfg | bfs | 30m | no violation (budget-limited) | 5443242 distinct, depth 13, queue 3434069 |
| Update-residual-sim | Update-residual.cfg | sim | 30m | no violation (budget-limited) | 22128469 states checked, 69664 traces, mean length 31 |
| Update-residual | Update-residual.cfg | bfs | 30m | no violation (budget-limited) | 7653534 distinct, depth 15, queue 4388877 |
| hunt-U2-bfs | MC_hunt_U2_prevote_leader.cfg | bfs | 30m | VIOLATION TimerPreVoteElectsOnlyNonLeader (13-state trace) | 221660 distinct, depth 15, queue 105796 |
| hunt-U4-stale-bfs | MC_hunt_U4_prevote_stale_round.cfg | bfs | 30m | VIOLATION StalePreVoteResponseIgnored (6-state trace) | 1353 distinct, depth 6, queue 1133 |
| hunt-U4b-panic-bfs | MC_hunt_U4b_prevote_panic.cfg | bfs | 30m | no violation (budget-limited) | 6317276 distinct, depth 15, queue 3293620 |
| hunt-U4b-panic-sim | MC_hunt_U4b_prevote_panic.cfg | sim | 30m | no violation (budget-limited) | 27257172 states checked, 102798 traces, mean length 22 |
| hunt-U4c-panic-operator-bfs | MC_hunt_U4c_prevote_panic_operator.cfg | bfs | 30m | VIOLATION PreVoteResponseNeverPanics (16-state trace) | 4850462 distinct, depth 18, queue 2966091 |
| hunt-U5-bfs | MC_hunt_U5_prevote_fallback.cfg | bfs | 30m | no violation (budget-limited) | 5745445 distinct, depth 16, queue 3290316 |
| hunt-U5-sim | MC_hunt_U5_prevote_fallback.cfg | sim | 30m | no violation (budget-limited) | 44310150 states checked, 132419 traces, mean length 27 |

Notes:
- `rc=127`/"No error has been found" with a non-empty queue = stopped at the configured 30-minute exploration
  budget (`-Dtlc2.TLC.stopAfter`), i.e. `LIMITED_COVERAGE`, not an exhaustive pass.
- After a property produced a counterexample, the remaining properties were checked in `*-residual` configs
  so that exploration continues.
- Focused/open specs run with deadlock reporting disabled (bounded counters create terminal states).

## Not Reproduced / no violation

| Scenario | Config | Result |
|---|---|---|
| U1 side-effect-free round | `Update-residual.cfg`, `Update-focused-residual.cfg`, `Update-open-residual.cfg` (+ simulations) | `PreVoteRoundPersistsNothing`: no violation within budget |
| U3 quorum hands over to election | `Update-residual.cfg` (+ simulation), all prior invariants | `PreVoteProbeMatchesElection`, `PreCandidateProbeIsNextTerm`, prior invariants: no violation within budget |
| U4 panic with timer + operator rounds mixed | `MC_hunt_U4b_prevote_panic.cfg` (BFS + simulation) | no violation within budget (BFS diameter 15; the operator-only `MC_hunt_U4c` found it at depth 16) |
| U5 fallback grant / runtime toggle | `MC_hunt_U5_prevote_fallback.cfg` (BFS + simulation) | `PreVoteResponseNeverPanics`, `PreVoteProbeMatchesElection`, `PreVoteRoundPersistsNothing`: no violation within budget |
| U6 cancellation paths | traces + all Update cfgs | no violation |
| prior safety properties | `MC.cfg`, `MC-membership.cfg`, every Update cfg | no violation within budget |
| open/discharge | `Update-open-residual.cfg`, `Update-discharge.cfg` (BFS + simulation) | no violation; `DischargeContext` holds on explored states |

## Spec fixes during checking

- Case B: `LogLE` treated two absent logs as different (prior defect; made multi-voter elections unreachable).
- Case B: timer-started rounds now drop the node's earlier Pre-Vote traffic (RPC timeout ≤ round restart
  interval); the first `Update-full` counterexample relied on it and is kept under `spec/output/superseded/`.
- Trace-driven: lease effects of winning/adopting in `HandleVoteResponse`.
