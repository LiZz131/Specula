# Bug Report — OpenRaft Pre-Vote update (incremental run `incr-705b7bab5f0d`)

Source: `artifact/` commit `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` ("update").
Model: `spec/base.tla`, `spec/MC.tla`, `spec/Update.tla`, `spec/UpdateProps.tla`.

## Summary

- Update Scenarios tested: U-A, U-B, U-C, U-D, U-E (`modeling-brief.md` §2U)
- Model-checking findings: 2 (MC-1, MC-2), both reproduced through the public
  `Raft` API on the updated revision (`spec/confirmation-MC-1.md`,
  `spec/confirmation-MC-2.md`).
- Configs with counterexamples: `Update_full.cfg`, `Update_full_cont1.cfg`
  (full `MCNext`, Pre-Vote enabled on all nodes); campaign table in
  `spec/output/campaigns.md`.

## Bug 1: Pre-Vote responses of an earlier round are accepted by a later round of the same term

- **ID**: MC-1
- **Scenario**: U-B (round correlation); consequence U-C (panic)
- **Severity**: High
- **Invariant violated**: `PreVoteStaleResponseIgnored` (action property)
- **Config**: `Update_full.cfg` (UpdateFullSpec = MCSpec, PreVoteNodes = all)
- **Counterexample**: 6 states, `spec/output/cex-update-full-PreVoteStaleResponseIgnored.log`

### Trace Summary

1. `MCTickElect("1")`: node 1's election timer starts Pre-Vote round 1 with
   pre-vote `(term 1, node 1)` over `{1,2,3}`.
2. `SendPreVoteRequests("1")`: requests (round 1) to nodes 2 and 3.
3. `MCTickElect("1")`: the timer restarts the round (round 2). Node 1's vote did
   not change, so round 2 has the same pre-vote / leader id `(1, 1)`.
4. Node 3 answers the *round-1* request: granted.
5. Node 1 receives that round-1 grant. RaftCore's filter compares leader ids
   only, so it is counted by round 2; `{1,3}` is a quorum and node 1 starts a
   real election at term 1. Round 2 itself never received a grant.

Panic-consequence model witness (`PreVoteResponseNeverPanics`, directed hunt
`MC_hunt_prevote_panic_directed.cfg` with state constraint
`HuntOnlyNode1Elects`, a subset of reference behaviors; 16 states,
`spec/output/cex-hunt-PreVoteResponseNeverPanics.log`): node 1 starts a timer
round (round 1, pre-vote `(2,1)`, `{1,2,3}`) as Candidate, wins its election,
replaces the membership by `{1,3}` (joint, commit, uniform, commit), and starts
round 2 with the same pre-vote `(2,1)` over `{1,3}` (`ExternalPreElect`). A
granted round-1 response from node 2 is in flight; delivering it reaches
`grant_by` for a node outside the quorum set. (The unconstrained BFS
`MC_hunt_prevote_panic.cfg` reached depth 18 without it within budget.)

### Root Cause

`pre_elect` derives the hypothetical vote from the unchanged local vote
(`openraft/src/engine/engine_impl.rs:299-301`), so every round started at the
same local term carries the same leader id. `RaftCore::does_pre_candidate_vote_match`
(`openraft/src/core/raft_core.rs:2067-2090`) rejects a response only when
`candidate_vote.leader_id() != my_vote.leader_id()` (`:2078`), although its doc
comment states that a response "for a previous Pre-Vote round ... is stale and
should be ignored" (`:2066`). New same-term rounds are started by the timer
restart rule (`raft_core.rs:2014-2024`), by `Trigger::elect(true)`
(`raft_core.rs:1683-1690`, no rate limit), and after `become_following` dropped
a round (leader contact). `Engine::handle_pre_vote_resp` then counts the grant
with `Candidate::grant_by` (`engine_impl.rs:533-540`), which
`expect("target not in quorum set")`s (`proposer/candidate.rs:107`).

Consequences:
- **RaftCore panic (reproduced)**: if the membership changed between the rounds
  so that the stale responder is not a voter of the later round, `grant_by`
  panics and the node's RaftCore stops (`Fatal::Panicked`), in debug and release
  builds. Reproduced on a Leader that removed a voter between two operator
  `trigger().elect(true)` rounds.
- **Election on stale grants**: a grant issued before the responder regained a
  leader lease can complete a later round, so the node increments its term even
  though the current round would be rejected — the term inflation Pre-Vote is
  meant to prevent.

### Affected Code

- `openraft/src/core/raft_core.rs:2067-2090`: round correlation by leader id only.
- `openraft/src/engine/engine_impl.rs:298-322`: rounds at one term share the leader id.
- `openraft/src/engine/engine_impl.rs:516-554`: tally without round identity.
- `openraft/src/proposer/candidate.rs:106-112`: `grant_by` panics on a non-member.

### Recommendation

Give each Pre-Vote round an identity carried by the request/response (or by the
spawned task, e.g. the Candidate's progress id / starting time) and drop
responses whose identity differs; additionally ignore grants from targets that
are not in the round's quorum set instead of panicking.

## Bug 2: A Pre-Vote round started while Candidate survives leader establishment; the new Leader starts another election

- **ID**: MC-2
- **Scenario**: U-A
- **Severity**: High
- **Invariant violated**: `TimerPreVoteElectionFromFollowerState` (action property)
- **Config**: `Update_full_cont1.cfg` (full MCNext; continuation with MC-1's property disabled)
- **Counterexample**: 13 states, `spec/output/cex-update-full-TimerPreVoteElectionFromFollowerState.log`

### Trace Summary

1. `MCExternalElect("1")`: node 1 becomes Candidate at term 1; vote persisted;
   self grant; vote requests sent.
2. `MCTickElect("1")`: node 1 is still Candidate (not Leader, lease not valid),
   so its election timer runs the Pre-Vote branch: round `(2, 1)` with
   `preByTimer = TRUE`; requests sent.
3. Nodes 2/3 grant the real vote `(1,1)` and the pre-vote `(2,1)`.
4. The real vote response arrives: quorum, `establish_leader`; node 1 is Leader
   at term 1 (`leaderCertified`), but `preCandidateActive` stays TRUE.
5. The Pre-Vote grant arrives: quorum `{1,2}` → `elect()`: the established
   Leader moves to `(2, 1, uncommitted)`, role Candidate.

### Root Cause

The election timer keeps firing for a Candidate
(`openraft/src/core/raft_core.rs:1965-2008`; only Leaders and non-voters skip)
and with Pre-Vote enabled calls `pre_elect` (`:2010-2036`), which leaves the
running `candidate` untouched. `establish_leader`
(`engine_impl.rs:855-880`) and `become_leader` do not drop `pre_candidate`
(only `do_elect` `:264` and `become_following` `vote_handler/mod.rs:244` do).
`handle_pre_vote_resp` calls `elect()` on quorum without checking the node's
current role (`engine_impl.rs:533-540`). `do_elect` keeps the existing `leader`
object because the node is still "leading" (`vote_handler/mod.rs:154-162`), so
`try_leader_handler`'s `debug_assert!(leader.vote >= state.vote)`
(`engine_impl.rs:976-981`) fails on the next leader operation.

Consequences (reproduced): the freshly established Leader steps down and
inflates its term (release build: Candidate at term 3); in debug builds RaftCore
panics on the `try_leader_handler` assertion. The same occurs when an operator
uses `trigger().elect(true)` on a Candidate.

### Affected Code

- `openraft/src/core/raft_core.rs:1959-2036`: timer Pre-Vote branch runs for Candidates.
- `openraft/src/engine/engine_impl.rs:855-880`: `establish_leader` keeps `pre_candidate`.
- `openraft/src/engine/engine_impl.rs:533-540`: quorum → `elect()` without role check.
- `openraft/src/engine/engine_impl.rs:976-981`: invariant tripped by the stale leader.

### Recommendation

Drop `pre_candidate` when the node establishes/becomes Leader (and when a real
election starts by any path), and/or ignore Pre-Vote quorums unless the node is
still a non-leader voter whose vote equals the one the round was started from.

---

## Not Reproduced / No Violation

All runs: `spec/output/campaigns.md` (exact commands in each log header). Runs
stopped by their time budget are LIMITED_COVERAGE.

| Scenario | Config | States explored | Result |
|---|---|---|---|
| Standard reference (Pre-Vote disabled by config; operator Pre-Vote available) | `MC.cfg` BFS 30 min | 19.9M distinct, depth 20 | no violation (budget-limited) |
| Standard reference, simulation follow-up | `MC.cfg` sim 20 min | 42.5M states, 138k traces | no violation |
| V0 membership companion | `MC-membership.cfg` | 299,637 distinct, depth 29, exhausted | no violation |
| Full update (U1, U2, U3, U6, U7 + all base properties) | `Update_full_cont2.cfg` BFS 30 min | 24.3M distinct, depth 19 | no violation (budget-limited) |
| Full update, simulation | `Update_full_cont2.cfg` sim 20 min | 31.8M states, 103k traces | no violation |
| Mixed cluster (Pre-Vote on nodes 1,2 only) | `Update_full_mixed_cont.cfg` BFS 20 min | 13.0M distinct, depth 20 | no violation (budget-limited) |
| Concrete focused (election budget 3) | `Update_focused_cont.cfg` BFS 30 min + sim 15 min | 19.8M distinct, depth 17; 18.4M sim states | no violation |
| Open focused (EnvUpdate rely) | `Update_open_cont.cfg` BFS 30 min | 24.4M distinct, depth 14 | no violation (provisional on discharge) |
| Discharge (omitted context ⊆ EnvUpdate; partition covers MCNext) | `Update_discharge_membership.cfg` / `Update_discharge.cfg` | 299,637 exhausted / 2.96M distinct, depth 16 | no violation (second budget-limited) |
| U-A leader abdication (focused) | `MC_hunt_leader_abdication.cfg` | depth 15 | VIOLATION `TimerPreVoteElectionFromFollowerState` (MC-2 witness) |
| U-B stale round | `MC_hunt_stale_round.cfg` | depth 8 | VIOLATION `PreVoteStaleResponseIgnored` (MC-1 witness) |
| U-C panic, unconstrained | `MC_hunt_prevote_panic.cfg` BFS 30 min + sim 20 min | 14.4M distinct, depth 18; 27.6M sim states | no violation within budget |
| U-C panic, directed | `MC_hunt_prevote_panic_directed.cfg` | depth 17 | VIOLATION `PreVoteResponseNeverPanics` (MC-1 consequence) |
| U-D Pre-Vote × crash/drop | `MC_hunt_prevote_crash_cont.cfg` BFS 20 min | 10.3M distinct, depth 17 | no violation (budget-limited) |

## Spec fixes during this run

See `spec/changelog.md` (R1 absent-log comparison, R2 leader lease on
establishment, R3 tick guards; harness capture fixes).
