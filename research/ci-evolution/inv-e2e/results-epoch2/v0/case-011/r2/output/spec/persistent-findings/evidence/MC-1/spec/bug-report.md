# Bug Report — OpenRaft (Pre-Vote revision, artifact HEAD 3ab6cdd)

## Summary

- Update Scenarios tested: U1–U6 (see `brief-coverage.md`)
- Bugs found: 1 (MC-1), confirmed and REPRODUCED (`spec/confirmation-MC-1.md`)
- Configs run: see the table at the end and `spec/output/*.log`

## Bug 1: Pre-Vote round survives leader establishment and makes the new Leader re-elect itself

- **Scenario**: U3 (Pre-Vote round × running election × leader establishment)
- **Severity**: High
- **Invariant violated**: `LeaderVoteCoversLocalVote` (`Update.tla`)
- **Config**: `Update.cfg` (also `Update-nofault.cfg`: no crash, no drop)
- **Counterexample**: 15 states, `spec/output/MC-1-counterexample-update-full.log`; fault-free 14 states, `spec/output/update-nofault.log`

### Trace Summary

1. (Update.cfg only) node 1 crashes — irrelevant to the mechanism; the fault-free run shows the same path without it.
2. `TickPreElect(2)`: Pre-Vote round `(1,2)`; node 3 answers granted; `HandlePreVoteResponse` quorum → `ElectEffect`: node 2 Candidate `(1,2)`, real election running.
3. `PersistVote(2)`, self grant, `SendVoteRequest(2,3)`; node 3 grants `(1,2)` (reply pending/persisted → `VoteResp` in flight).
4. `TickPreElect(2)` again while Candidate (election timer expired, role ≠ Leader): Pre-Vote round `(2,2)`, `candidateActive[2]` stays TRUE.
5. Node 3 answers the Pre-Vote `(2,2)` granted (its vote is the uncommitted `(1,2)`, no lease).
6. `HandleVoteResponse(2)` for `(1,2)`: quorum → Leader `(1,2,committed)`, `preCandidateActive[2]` still TRUE.
7. `PersistVote(2)` (committed vote).
8. `HandlePreVoteResponse(2)`: gate matches `(2,2)`, quorum `{2,3}` → `ElectEffect`: `vote[2] = (2,2,uncommitted)`, role Candidate, but `leaderActive[2] = TRUE` with `leaderVote[2] = (1,2,committed)` → `LeaderVoteCoversLocalVote` violated.

### Root Cause

- `RaftCore::handle_tick_election` (`openraft/src/core/raft_core.rs:1959`) skips only `ServerState::Leader`; for a Candidate with Pre-Vote enabled it calls `Engine::pre_elect`.
- `Engine::pre_elect` (`openraft/src/engine/engine_impl.rs:298`) leaves the running `candidate` in place.
- `Engine::establish_leader` (`engine_impl.rs:855`) takes only `candidate`; neither it nor `VoteHandler::become_leader` clears `pre_candidate`.
- `Notification::PreVoteResponse` (`raft_core.rs:1803`) / `does_pre_candidate_vote_match` (`raft_core.rs:2067`) check only that a pre-candidate with the same leader id exists.
- `Engine::handle_pre_vote_resp` (`engine_impl.rs:516`) calls `elect()` on quorum without a role/leader check.
- `Engine::do_elect` (`engine_impl.rs:262`) keeps the Leader object; `RaftCore::trigger_routine_actions` (`raft_core.rs:908-921`) → `Engine::try_leader_handler` (`engine_impl.rs:968-982`) asserts `leader.committed_vote >= state.vote`.

### Affected Code

- `openraft/src/engine/engine_impl.rs:516`: `handle_pre_vote_resp` elects without checking role/leader.
- `openraft/src/engine/engine_impl.rs:855`: `establish_leader` does not clear `pre_candidate`.
- `openraft/src/engine/engine_impl.rs:298`: `pre_elect` runs while a real candidacy is live.
- `openraft/src/core/raft_core.rs:2067`: gate correlates by leader id only.

### Confirmation

REPRODUCED through the real `Raft` API (`harness/repro/t13_specular_mc1_prevote_reelect.rs`): Level 1 (public API, response-delivery delays only) and Level 3 (timer path with slow `save_vote` in the test store), 3/3 each; both controls clean. Observed: `panicked at openraft/src/engine/engine_impl.rs:977:9: leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)` and `client_write -> Fatal(Panicked)`. Details: `spec/confirmation-MC-1.md`.

### Recommendation

Clear `pre_candidate` on leader establishment (and in `become_leader`), and make `handle_pre_vote_resp`/the runtime gate ignore responses unless the node is still a non-leader whose current vote is the one the round was derived from. Optionally do not run a Pre-Vote round while a real candidacy is still live, or drop that candidacy when starting one.

---

## Not Reproduced

All runs: 3 nodes, MaxTerm 2, MaxLogIndex 4, ≤2 elections, ≤2 Pre-Vote rounds, ≤2 membership changes, ≤1 crash, ≤1 drop, ≤5 messages; 30-minute budgets (LIMITED_COVERAGE, not exhaustive). Full inventory: `spec/output/mc-campaign-summary.tsv`.

| Scenario / purpose | Config | Mode | States explored | Result |
|---|---|---|---|---|
| Standard round (prior invariants, new behavior, toggle + admin) | MC.cfg | BFS | 11.6M distinct, level 16 | No violation (budget-limited) |
| same | MC.cfg | simulation d=60 | 58.8M states, 159K traces | No violation |
| Inherited membership companion | MC-membership.cfg | BFS | 5.2M distinct, level 21 | No violation (budget-limited) |
| Pre-Vote disabled regression | MC-prevote-off.cfg | BFS | 14.3M distinct, level 20 | No violation (budget-limited) |
| Prior equivalence (repairs reverted, Pre-Vote off) | regression-prior-equivalence/ | BFS | 640,830 distinct, depth 24, exhaustive | Identical to prior |
| Attribution control for MC-1 (Pre-Vote off, autonomous) | Update-control-off.cfg | BFS | 14.4M distinct, level 20 | `LeaderVoteCoversLocalVote` holds (budget-limited) |
| U1/U2/U4 residual update properties, full MCNext | Update-residual.cfg | BFS | 18.8M distinct, level 21 | No violation (budget-limited) |
| same | Update-residual.cfg | simulation d=60 | 58.2M states, 179K traces | No violation |
| U6 runtime toggle | Update-toggle.cfg | BFS / simulation | 15.1M distinct, level 15 / 15.6M states | No violation |
| Concrete focused (residual) | Update-focused-residual.cfg | BFS / simulation | 11.2M distinct, level 22 / 17.4M states | No violation |
| Open focused with EnvUpdate (U5, residual) | Update-open-residual.cfg | BFS / simulation | 59.8M distinct, level 13 / 197M states, 1.42M traces | No violation (provisional, discharge below) |
| Open focused with EnvUpdate (incl. MC-1 property) | Update-open.cfg | BFS / simulation | 34.4M distinct, level 11 / 250K states | BFS budget-limited; simulation re-finds MC-1 (28 states) |
| Discharge of EnvUpdate by omitted context | Update-discharge.cfg | BFS / simulation | 16.0M distinct, level 17 / 81.5M states | `DischargeEnv` holds (budget-limited) |
| Reachability canaries (6) | Update-canary-*.cfg | BFS | 2–12 state witnesses | All update Scenarios reachable |

Spec fixes during hunting: `EnvUpdate` strengthened (open view only; Case B, rely too weak) — see `spec/changelog.md`.
