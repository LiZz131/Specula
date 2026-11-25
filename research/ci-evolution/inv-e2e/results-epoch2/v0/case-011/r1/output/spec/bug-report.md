# Bug Report — OpenRaft election with Pre-Vote (incremental run, case-011)

## Summary

- Source under test: `artifact/` synthetic commit `update` (`3ab6cddc34a5bf127747434bb41e20a1b9ef7769`).
- Update Scenarios tested: U1-U5 (see `modeling-brief.md`); V0 Scenarios 1-5 re-checked by the standard configs.
- Model-checking bugs found: 2 (MC-1, MC-2). Code-review findings recorded in `modeling-brief.md` section 6 (CR-1 liveness stall, CR-2 documentation), not model-checking findings.
- Configs run: 21 campaign runs (BFS and simulation) plus 8 reachability canaries; see "Campaign results" below.

## Bug 1: A timer-started Pre-Vote round survives leader establishment and deposes the new Leader

- **Scenario**: U2 (Pre-Vote round lifecycle vs real election and leadership)
- **Severity**: High
- **Invariant violated**: `TickPreVoteNeverDeposesLeader` (action property, `spec/Update.tla`)
- **Config**: `spec/MC_hunt_prevote_leader.cfg` (module `Update`); also reproduced by `Update-full.cfg` over the complete `MCNext` (see campaign table)
- **Counterexample**: 14 states, `spec/output/MC_hunt_prevote_leader_violation.out` (BFS, 4,237,363 distinct states, depth 16 when found)
- **Update attribution**: introduced by the update (crosses the new Actions `TickPreElect` and `HandlePreVoteResponse`; the unchanged `establish_leader` does not drop the new tracker).

### Trace Summary

Three voters {1,2,3}, `PreVoteSetting = "Enabled"`, no operator trigger, no crash, no drop.

1. State 2 `MCTickPreElect(1)`: node 1's timer starts a Pre-Vote round for term 1; requests to 2 and 3.
2. States 3-4: node 2 grants; node 1 reaches the Pre-Vote quorum and calls `elect()` -> Candidate at term 1 (tracker dropped by `do_elect`).
3. State 5 `MCTickPreElect(1)`: node 1's election has not finished; the timer (which skips only Leaders) starts a new Pre-Vote round for term 2 on the Candidate. Requests to 2 and 3.
4. States 6-9: node 1 persists its vote and sends `VoteReq(term 1)` to node 2; node 2 grants and persists (vote `(1,1)` uncommitted).
5. States 10-11: node 1 receives its own and node 2's grants -> `establish_leader` -> Leader with committed vote `(1,1)`. The term-2 Pre-Vote tracker is still live.
6. States 12-13: node 1 persists the committed vote. Node 2 handles the term-2 Pre-Vote request: its vote `(1,1)` is uncommitted (no lease), log equal, `(2,1) >= (1,1)` -> grant.
7. State 14: the delayed grant reaches node 1. RaftCore's filter only checks that a tracker exists with the same leader id; `handle_pre_vote_resp` counts the grant, reaches the quorum `{1,2}` and calls `elect()`: the Leader becomes Candidate at term 2.

### Root Cause

- `RaftCore::handle_tick_election` skips only a cached Leader and runs a Pre-Vote round on a Candidate whose election outlived the election timeout (`openraft/src/core/raft_core.rs:1966-1969, 2010-2035`).
- `Engine::pre_elect` creates the tracker without touching the running Candidate (`openraft/src/engine/engine_impl.rs:291-322`).
- The tracker is dropped only by `do_elect` (`engine_impl.rs:262-264`), `become_following` (`engine/handler/vote_handler/mod.rs:234-249`), and restart. Winning the real election goes through `establish_leader -> update_vote -> update_internal_server_state -> become_leader`, which does not drop it (`engine_impl.rs:855-881`, `vote_handler/mod.rs:154-162,172-229`).
- `Notification::PreVoteResponse` is filtered only by tracker presence and leader id (`raft_core.rs:1803-1820, 2066-2090`), and `Engine::handle_pre_vote_resp` calls `self.elect()` on quorum with no role or leadership check (`engine_impl.rs:526-541`).
- `elect()` on a node that holds a Leader object keeps `self.leader` (`update_internal_server_state` treats the new uncommitted self vote as `is_leading` and does nothing), leaving a Leader object with the old committed vote next to a higher uncommitted vote. RaftCore's next `trigger_routine_actions -> try_leader_handler` then fails `debug_assert!(leader.vote >= state.vote)` (`engine_impl.rs:967-982`).

### Consequence

- The Leader that just won term t+1 abandons it and runs an election at t+2. Its followers hold a fresh lease for t+1 and reject the t+2 vote, so the cluster has no leader at least until those leases expire — the leader disruption Pre-Vote is documented to prevent (`docs/protocol/pre_vote.md`; `Config::enable_pre_vote` doc).
- In debug builds RaftCore panics (`Fatal::Panicked`) and the node stops serving; observed in both integration reproductions. Release-build behavior with the retained Leader object was not evaluated.

### Reproduction on the implementation (updated revision `3ab6cdd`)

| Evidence | Command / file | Observed |
|---|---|---|
| Trace validation of each transition of the path | `traces/candidate_pre_round_survives_leadership.ndjson`, `traces/leader_pre_vote_win.ndjson`; `spec/output/trace-*.log` | the implementation keeps the tracker on the new Leader and elects at term+1 on the delayed grant; both replay against the model |
| Engine-level test | `harness/run-repro.sh` -> `specula_repro_stale_pre_vote_round_deposes_leader` (`spec/output/repro-engine.log`) | FAILS: `left: Leader, right: Candidate` |
| Integration, operator-started round | `tests/tests/elect/t91_specula_stale_pre_vote_round.rs` (`spec/output/repro-integration.log`) | node 1 Leader at term 2, then RaftCore panic `leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`; probe returns `Err(Panicked)` |
| Integration, election-timer only | `tests/tests/elect/t92_specula_stale_pre_vote_round_timer.rs` (`spec/output/repro-integration-timer.log`, timeline `spec/output/repro-integration-timer-timeline.txt`) | `trigger pre-vote` (T2) -> election T2 -> `trigger pre-vote` while Candidate (T3) -> `a quorum granted my vote` -> Leader T2 -> delayed `PreVoteResponse` -> `starting a real election` T3 -> `steps down from leader` -> RaftCore panic |

Timing precondition for the timer path: the Candidate's real election must outlive the election timeout while its vote responses still arrive within the vote RPC timeout (`election_timeout_min`), i.e. vote-save latency plus vote RPC latency must exceed the randomized election timeout. The t92 test obtains this with a 600 ms vote save and 500 ms vote RPC under a ~1000 ms timeout; `Trigger::elect(true)` on a Candidate (t91) reaches the same path without timing constraints.

Old-revision attribution: the old revision has no Pre-Vote round; its timer re-elects a Candidate directly, which drops the old candidate, so a late grant of the superseded election is ignored. The retained-Leader-object mechanism existed before only behind an operator `trigger().elect()` on a Leader.

### Affected Code

- `openraft/src/engine/engine_impl.rs:526-541`: `handle_pre_vote_resp` calls `elect()` on quorum without checking role/leadership.
- `openraft/src/engine/engine_impl.rs:855-881`: `establish_leader` keeps `pre_candidate`.
- `openraft/src/core/raft_core.rs:2010-2035`: the timer starts Pre-Vote rounds on a Candidate.
- `openraft/src/core/raft_core.rs:1803-1820, 2066-2090`: the response filter checks only tracker presence and leader id.

### Recommendation

Drop the Pre-Vote tracker whenever the node becomes Leader (e.g. in `establish_leader`/`become_leader`), and make `handle_pre_vote_resp` (or the RaftCore filter) ignore responses unless the node is still a non-leader whose vote is the one the round was started from.

---

## Bug 2: A delayed Pre-Vote grant from a node removed between two same-term rounds panics RaftCore

- **Scenario**: U5 (frozen Pre-Vote quorum vs membership evolution), interacting with U2
- **Severity**: Medium (RaftCore panic, also in release builds; needs a second Pre-Vote round at the same term started by `Trigger::elect(true)` and a delayed grant)
- **Invariant violated**: `PreVoteTrackerWellFormed` (every counted grant belongs to the round's frozen voter set; the implementation `expect`s exactly this in `Candidate::grant_by`)
- **Config**: `spec/MC_hunt_prevote_stale_grant_tight.cfg` (BFS, 3,312,276 distinct states, depth 20 when found) and `spec/Update-full-noU2.cfg` (complete `MCNext`, TLC simulation, depth bound 60)
- **Counterexample**: 17 states, `spec/output/MC_hunt_prevote_stale_grant_tight_violation.out` (BFS-shortest in that cfg); 31 states over the complete MCNext, `spec/output/Update-full-noU2_sim_violation.out`
- **Update attribution**: introduced by the update (Pre-Vote rounds at one term reuse the leader id; real elections never do).

### Trace Summary (17-state BFS counterexample, node 1)

1. State 2 `MCExternalPreElect(1)`: an operator `Trigger::elect(true)`; the round reaches its quorum and node 1 becomes Candidate at term 1 (states 3-4).
2. State 5 `MCTickPreElect(1)`: the timer starts a round `(2,1)` on the Candidate with frozen config {1,2,3}.
3. States 6-12: node 2 grants the real term-1 vote and the round-`(2,1)` Pre-Vote (its grant stays in flight); node 1 becomes Leader and keeps the round (MC-1 state).
4. States 13-15: Leader 1 appends the joint config `<<{1,2,3},{1,3}>>`, commits it, and appends the uniform config `<<{1,3}>>` (node 2 removed).
5. State 16 `MCExternalPreElect(1)`: an operator `Trigger::elect(true)` starts a new round; the vote is unchanged, so it probes `(2,1)` again with frozen config `<<{1,3}>>`.
6. State 17: node 2's delayed grant is counted (grants {1,2}, node 2 outside the config) -> `PreVoteTrackerWellFormed` violated; the implementation panics in `Candidate::grant_by`.

### Trace Summary (31-state counterexample over the complete MCNext, node 2)

1. States 5-14: node 2 starts a direct election at term 1 (Runtime flag off at that tick) and node 1 grants it.
2. State 15 `MCTickPreElect(2)`: node 2's timer starts a Pre-Vote round `(2,2)` while still Candidate; frozen config {1,2,3}; requests to 1 and 3.
3. States 18-19: nodes 3 and 1 grant the Pre-Vote; the responses stay in flight.
4. State 21: node 2 wins its term-1 election and becomes Leader; the round is kept (MC-1 state).
5. States 22-26: Leader 2 appends the joint config `<<{1,2,3},{1,2}>>`, flushes, commits it, and appends the uniform config `<<{1,2}>>` (node 3 removed).
6. State 27 `MCExternalPreElect(2)`: an operator `Trigger::elect(true)` on node 2 starts a new round; its vote is unchanged (term 1), so the round probes `(2,2)` again, now with frozen config `<<{1,2}>>`.
7. State 31: node 3's delayed grant for the first round is delivered; RaftCore's filter compares only the leader id `(2,2)`, so it is counted: the tracker's grants become {2,3} with 3 outside its config.

### Root Cause

- `Engine::pre_elect` always probes `(vote.term + 1, self)`, so rounds at an unchanged term share a leader id (`engine_impl.rs:298-303`).
- `does_pre_candidate_vote_match` compares only `leader_id` (`raft_core.rs:2066-2090`); it cannot distinguish rounds.
- `handle_pre_vote_resp` calls `grant_by(&target)` (`engine_impl.rs:534-535`) and `Candidate::grant_by` does `self.progress.update(target, true).expect("target not in quorum set")` (`proposer/candidate.rs:105-107`); `VecProgress::update_with` returns `Err` for an id outside the frozen quorum set (`progress/vec_progress.rs:177-189`).

### Reproduction on the implementation (updated revision `3ab6cdd`)

| Evidence | Observed |
|---|---|
| `specula_repro_stale_pre_vote_grant_leader_variant` (engine; the counterexample shape) | panics at `openraft/src/proposer/candidate.rs:107:59: target not in quorum set` (`spec/output/repro-engine-stale-grant.log`) |
| `specula_repro_stale_pre_vote_grant_from_removed_member` (engine; follower variant, membership change via `Engine::append_entries`) | same panic |
| `tests/tests/elect/t93_specula_stale_pre_vote_grant_removed_member.rs` (4 nodes, follower variant, `change_membership([0,1,2])`, delayed grant of node 3) | RaftCore of node 1 panics at `candidate.rs:107` (`target not in quorum set`); probe `Err(Panicked)` (`spec/output/repro-integration-stale-grant.log`) |

Reachability limits: a timer-only path is blocked because the timer restarts a round only after `election_timeout` (>= the Pre-Vote RPC timeout `election_timeout_min`); a follower's config changes only through AppendEntries, and every heartbeat drops a follower's live round (the integration test disables heartbeats; with heartbeats the grant must land within one heartbeat gap, see `spec/output/repro-integration-stale-grant-heartbeat-attempt.txt`). Details: `spec/reproduction-MC-2.md`.

### Affected Code

- `openraft/src/proposer/candidate.rs:105-107`: `grant_by` panics on an unknown granter.
- `openraft/src/core/raft_core.rs:2066-2090`: the filter compares only the leader id.
- `openraft/src/engine/engine_impl.rs:298-322, 534-535`: rounds reuse `(term+1, self)`; grants counted without a membership check.

### Recommendation

Correlate responses with the specific round (e.g. a round id or the round's starting time carried in the notification), and ignore grants from nodes outside the round's quorum set instead of `expect`ing membership.

---

## Campaign results

All runs: TLC 2026.11.06, `harness/run-tlc.sh` (outer `timeout`, states under
`/dev/shm/specula-e2e-case-011/`, removed after each run), logs `spec/output/<run>.log`,
summary `spec/output/campaign-summary.json`. BFS runs have a 30-minute budget
(20 for focused/open), simulations 20 minutes with depth bound 60. A run marked
LIMITED_COVERAGE explored the listed states without a violation and is not an
exhaustive pass. Runs on the pre-repair model (`invalid-vacuous-*`: no election could
succeed; `*-prerepair`: Restart artifact) are listed for provenance only; "no
violation" runs made before the Restart repair remain valid because the repair only
removes behaviors.

| Run | Cfg | Mode | Status | Distinct | Depth | Queue left | Violated / trace |
|---|---|---|---|---|---|---|---|
| mc-standard | MC.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 14,315,098 | 16 | 7,859,902 | - |
| mc-membership | MC-membership.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 7,675,374 | 23 | 2,341,889 | - |
| sim-mc-standard | MC.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 26,905,845 checked / 294,977 traces | mean len 41, bound 60 | - | - |
| update-full | Update-full.cfg | BFS | VIOLATION | 4,386,936 | 13 | 2,585,421 | TickPreVoteNeverDeposesLeader (13 states) |
| update-full-noU2 | Update-full-noU2.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 21,452,958 | 16 | 11,594,404 | - |
| sim-update-full-noU2 | Update-full-noU2.cfg | simulation | VIOLATION | 8,002,533 checked / 87,693 traces | mean len 41, bound 60 | - | PreVoteTrackerWellFormed (31 states) |
| sim-update-full-noU2-noMC2 | Update-full-noU2-noMC2.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 60,295,516 checked / 661,345 traces | mean len 35, bound 60 | - | - |
| update-full-enabled | Update-full-enabled.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 17,960,781 | 19 | 10,470,020 | - |
| sim-update-full-enabled | Update-full-enabled.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 21,700,039 checked / 293,788 traces | mean len 43, bound 60 | - | - |
| update-focused | Update-focused.cfg | BFS | VIOLATION | 5,254,540 | 13 | 3,056,771 | TickPreVoteNeverDeposesLeader (12 states) |
| update-open | Update-open.cfg | BFS | VIOLATION | 4,980,338 | 13 | 2,925,782 | TickPreVoteNeverDeposesLeader (12 states) |
| update-discharge | Update-discharge.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 6,905,721 | 13 | 3,946,275 | - |
| hunt-prevote-leader | MC_hunt_prevote_leader.cfg | BFS | VIOLATION | 4,237,363 | 16 | 2,032,083 | TickPreVoteNeverDeposesLeader (14 states) |
| hunt-prevote-term | MC_hunt_prevote_term.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 13,862,983 | 15 | 7,214,172 | - |
| sim-hunt-prevote-term | MC_hunt_prevote_term.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 22,129,714 checked / 281,721 traces | mean len 43, bound 60 | - | - |
| hunt-prevote-membership | MC_hunt_prevote_membership.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 9,377,310 | 20 | 3,838,822 | - |
| sim-hunt-prevote-membership | MC_hunt_prevote_membership.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 64,041,586 checked / 1,036,369 traces | mean len 37, bound 60 | - | - |
| hunt-prevote-stale-grant | MC_hunt_prevote_stale_grant.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 10,720,816 | 19 | 6,118,095 | - |
| sim-hunt-prevote-stale-grant | MC_hunt_prevote_stale_grant.cfg | simulation | LIMITED_COVERAGE (time budget, no violation) | 28,008,777 checked / 370,587 traces | mean len 35, bound 60 | - | - |
| hunt-prevote-stale-grant-tight | MC_hunt_prevote_stale_grant_tight.cfg | BFS | VIOLATION | 3,312,276 | 20 | 2,046,878 | PreVoteTrackerWellFormed (17 states) |
| hunt-prevote-restart | MC_hunt_prevote_restart.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 15,245,205 | 14 | 7,871,295 | - |
| canary-leader-tick-round | Canary-leader-tick-round.cfg | BFS | VIOLATION | 53,740 | 12 | 25,786 | CanaryNoLeaderWithTickPreRound (11 states) |
| canary-joint-round | Canary-joint-round.cfg | BFS | VIOLATION | 47 | 7 | 21 | CanaryNoJointPreVoteRound (6 states) |
| canary-rejected-resp | Canary-rejected-resp.cfg | BFS | VIOLATION | 251 | 5 | 216 | CanaryNoRejectedPreVoteResponse (4 states) |
| canary-PreVoteElection | Canary-PreVoteElection.cfg | BFS | VIOLATION | 669 | 6 | 573 | CanaryNoPreVoteElection (4 states) |
| canary-LeaseRejectedPreVote | Canary-LeaseRejectedPreVote.cfg | BFS | VIOLATION | 193,278 | 11 | 106,829 | CanaryNoLeaseRejectedPreVote (10 states) |
| canary-PreVoteCancelledByFollowing | Canary-PreVoteCancelledByFollowing.cfg | BFS | VIOLATION | 4,148 | 7 | 3,193 | CanaryNoPreVoteCancelledByFollowing (6 states) |
| canary-GreaterLogFromPreVote | Canary-GreaterLogFromPreVote.cfg | BFS | VIOLATION | 427,687 | 12 | 221,781 | CanaryNoGreaterLogFromPreVote (11 states) |
| canary-PreVoteAfterRestart | Canary-PreVoteAfterRestart.cfg | BFS | VIOLATION | 304 | 5 | 270 | CanaryNoPreVoteAfterRestart (5 states) |
| invalid-vacuous-mc-standard | MC.cfg | BFS | OTHER (exit 143) | 14,009,561 | 16 | 6,547,798 | - |
| invalid-vacuous-mc-membership | MC-membership.cfg | BFS | OTHER (exit 143) | 8,965,475 | 24 | 2,695,846 | - |
| hunt-prevote-membership-prerepair | MC_hunt_prevote_membership.cfg | BFS | VIOLATION | 158,616 | 14 | 85,393 | PreVoteTrackerWellFormed (13 states) |
| hunt-prevote-restart-prerepair | MC_hunt_prevote_restart.cfg | BFS | LIMITED_COVERAGE (time budget, no violation) | 11,241,913 | 14 | 6,063,450 | - |

Canary runs are expected violations: each witnesses that an update Scenario is
reachable (U1 Pre-Vote election, U2 Leader holding a timer round, U3 lease and
rejected responses, U4 cancellation by following and restart, U5 joint round).

## Not Reproduced

| Scenario / property | Config(s) | Explored | Result |
|---|---|---|---|
| U1 `SelfTermIncreaseNeedsPreVoteQuorum` | `Update-full-enabled.cfg`, `MC_hunt_prevote_leader.cfg`, `MC_hunt_prevote_term.cfg` | BFS 17.96M / 4.24M / 13.86M distinct + 2 simulations | No violation (LIMITED_COVERAGE) |
| U3 `PreVoteRequestIsReadOnly`, `PreElectLeavesVoteUnchanged` | all Update and hunt cfgs | see table | No violation (LIMITED_COVERAGE) |
| U2/U4 `PreVoteProbeIsNextTerm` | all Update and hunt cfgs | see table | No violation (LIMITED_COVERAGE) |
| Preserved V0 invariants | `MC.cfg`, `MC-membership.cfg`, all Update/hunt cfgs | BFS 14.32M / 7.68M distinct + simulation | No violation (LIMITED_COVERAGE) |
| Discharge of `EnvUpdate` for omitted membership/flush context | `Update-discharge.cfg` | BFS 6.91M distinct | No violation (LIMITED_COVERAGE) |
| CR-1 Pre-Vote term stall (liveness) | not model-checkable (followers never receive log entries in the model; no HigherVote step-down) | — | Not testable in the model; reproduced end-to-end by `t94` (`spec/code-review-CR-1.md`) |

## Spec fixes during model checking

- `LogLE` (V0 defect: empty logs with different node tags compared unequal, so no
  3-voter election could succeed; the V0 primary config never reaches a Leader).
- `Restart` discards the old incarnation's Pre-Vote exchanges (Case B artifact).
- Earlier, during harness construction: leader lease on establishment, timer guards,
  no greater-log reset on external elections.
See `spec/changelog.md`.
