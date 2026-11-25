# Bug Report — OpenRaft Pre-Vote update (case-011)

## Summary

- Source under test: artifact `3ab6cdd` (`update`); prior: `1adc857` (`baseline`).
- Update Scenarios tested: U1–U5 (`modeling-brief.md`, Update brief).
- Model-checking findings: **2** (MC-1, MC-2), both reproduced on the real runtime; unresolved property violation D-2 and pre-existing CR-PRE-1 are in `spec/code-review-findings.md`.
- Configs run: see "Campaign results" below and `spec/model-checking-summary.md`.

## Bug 1: Stale Pre-Vote round survives the node's own election win and makes the new Leader call elect()

- **ID**: MC-1
- **Scenario**: U2 (old producer `HandleVoteResponse`/`establish_leader` → changed `HandlePreVoteResponse` quorum branch → old consumer `try_leader_handler`)
- **Severity**: High (availability: a freshly elected leader abandons its term and, in debug builds, its RaftCore panics; no committed-data safety violation was found)
- **Property violated**: `Update!PreVoteRoundNotOutlivedByOwnLeadership` (requirement: `pre_vote.md:3-6,44-49`, `config.rs:402-404`); the implementation-asserted `Update!LeaderObjectVoteNotBehind` (`engine_impl.rs:976-981`) is violated by the same step
- **Config**: `spec/Update_full.cfg` (module `Update`, full `MCNext`, MC.cfg bounds)
- **Counterexample**: 14 states, `spec/output/MC-1_update_full_violation.out` (JSON: `spec/output/MC-1_update_full_violation.cex.json`), found after 5 min 25 s, 2,237,808 distinct states

### Trace summary

1. Node 3's election tick fires (`TickElect`): vote `(1,3)` uncommitted, Candidate, SaveVote + SendVote queued.
2. `PersistVote(3)`: vote durable; local granted `VoteResp(3→3)` emitted.
3. Node 3's election timer fires again while it is still a Candidate; with Pre-Vote enabled the tick runs `pre_elect` (`TickPreVote`): round with probe `(2,3)`, grants `{3}`, `PreVoteReq` to 1 and 2. The real `candidate` is **not** dropped.
4. `SendVoteRequest(3,2)`; node 3 counts its own grant.
5. Node 2 grants the real vote `(1,3)` (reply held until its SaveVote) and answers the Pre-Vote request with a grant (its vote `(1,3)` is uncommitted, so no lease; probe `(2,3)` ≥ `(1,3)`; logs equal).
6. Node 2's real grant arrives: node 3 reaches the term-1 quorum `{3,2}` and becomes **Leader** at `(1,3,committed)` (`establish_leader`). `preCandidateActive[3]` stays TRUE.
7. Node 2's Pre-Vote grant arrives: it matches the round's leader id, `{3,2}` is a quorum, and `handle_pre_vote_resp` calls `elect()`: node 3 abandons term 1 and becomes Candidate at `(2,3)` while its `Leader` object (`leaderActive`) remains.

### Root cause

- `Engine::pre_elect` (`openraft/src/engine/engine_impl.rs:298-322`) creates `pre_candidate` without touching an existing `candidate`; the election tick takes this path for a timed-out Candidate (`core/raft_core.rs:2010-2036`), and so does `ExternalCommand::Elect { pre_vote: true }` (`core/raft_core.rs:1683-1696`).
- `pre_candidate` is cleared only by `do_elect` (`engine_impl.rs:262-264`) and `become_following` (`engine/handler/vote_handler/mod.rs:234-249`). Winning the still-active real election goes through `establish_leader` (`engine_impl.rs:855-881`) → `update_vote(committed)` → `update_internal_server_state` → `become_leader` (`vote_handler/mod.rs:154-162,173-229`), none of which clears it.
- The runtime filter compares only leader ids (`core/raft_core.rs:2067-2090`), so grants for that round are still delivered, and the quorum branch of `handle_pre_vote_resp` calls `self.elect()` unconditionally (`engine_impl.rs:534-540`) — no check that the node is still a would-be candidate (not Leader), unlike the tick (`raft_core.rs:1966-1969`).
- `do_elect` on a Leader leaves `self.leader` in place (`update_internal_server_state` treats the new uncommitted self vote as "leading": nothing to do). The next `trigger_routine_actions` (`core/raft_core.rs:908-925`) calls `try_leader_handler`, whose `debug_assert!(leader.vote >= state.vote)` (`engine_impl.rs:976-981`) fails.

### Implementation evidence

- TLC-validated real-engine trace `traces/stale_prevote_after_win.ndjson` (5 events; event 5: Leader `(2,1,committed)` → Candidate `(3,1)` with `leader_active` still true). Evaluated on the replay: `PreVoteRoundNotOutlivedByOwnLeadership` violated, `LeaderObjectVoteNotBehind` violated (`spec/evidence/E_trace/`); control trace `prevote_resp_quorum_elect` satisfies both.
- Real RaftCore runtime (RaftRouter + memstore), `harness/repro/t13_specula_stale_prevote_repro.rs`, run by `harness/repro/run-repro.sh`, log `spec/output/repro-MC-1-new.log`: node 1 wins term 2, then
  `panicked at openraft/src/engine/engine_impl.rs:977:9: leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`
  in `trigger_routine_actions → try_leader_handler`; `Raft::with_raft_state` then returns `Fatal::Panicked`. The control test (same setup, no Pre-Vote trigger) keeps node 1 Leader at term 2 with a live core.
- Release build (`cargo test --release`, debug assertions off), log `spec/output/repro-MC-1-new-release.log`: node 1 wins term 2, then the live core reports vote `<T3-N1:->`, state `Candidate`, metrics term 3 — the new leader abandoned its term; the control again keeps `<T2-N1:Q>`/Leader. With the Leader object still present but the vote uncommitted, the followers that already hold node 1's term-2 lease reject the term-3 vote requests until the lease expires.

### Reachability in deployments

- Operator path (deterministic): `raft.trigger().elect(true)` on a node that is a Candidate with vote RPCs in flight.
- Automatic path (timing dependent): Pre-Vote enabled, a Candidate's election timer (`election_timeout`, measured from the engine-time vote update) fires before a peer's real vote response arrives; the response must still arrive within the RPC timeout `election_timeout_min` counted from the RPC spawn, which happens only after `save_vote` returns (`core/raft_core.rs:1403,2273-2304`). The window is non-empty when the randomized `election_timeout` is within the vote-persist latency of `election_timeout_min`.
- Old-revision control: not applicable — the old revision has no Pre-Vote (`ExternalCommand::Elect` has no `pre_vote`, no `Engine::pre_elect`/`handle_pre_vote_resp`); the same scenario cannot be expressed. In the old revision a timed-out Candidate's tick calls `elect()` and replaces the candidate, so late responses of the earlier election are filtered.

### Fidelity check (spec-fidelity-checklist.md)

| Counterexample precondition | Implementation guard searched | Result |
|---|---|---|
| A Candidate starts a Pre-Vote round while its real candidate is active | `handle_tick_election` checks Leader, voter, `enable_elect`, timeout, in-flight round (`raft_core.rs:1959-2036`); `ExternalCommand::Elect` checks voter (`:1683-1696`); `pre_elect` checks nothing (`engine_impl.rs:298-322`) | no guard against an active candidate; modeled as is |
| Late real vote grants still counted after the round started | `does_candidate_vote_match` compares the candidate's leader id (`raft_core.rs:2040-2063`); the candidate is unchanged by `pre_elect` | accepted; modeled (`HandleVoteResponse` exact match) |
| Peer grants the Pre-Vote after granting the real vote | lease only for committed votes (`engine_impl.rs:428-431`); `req.vote >= local` (`:445-446`) | grant is legal; modeled by `VoteGrantable` |
| Round survives `establish_leader` | `establish_leader` / `update_vote` / `become_leader` (`engine_impl.rs:855-881`, `vote_handler/mod.rs:106-229`) never clear `pre_candidate` | no clearing; modeled (`PreCleared` only on become_following / do_elect / restart) |
| Pre-Vote grant delivered to the Leader | `does_pre_candidate_vote_match` compares leader ids only (`raft_core.rs:2067-2090`); `handle_pre_vote_resp` has no role check (`engine_impl.rs:526-541`) | accepted; modeled |
| Timing (no time in the model) | RPC ttl `election_timeout_min` (`raft_core.rs:1403`), election timeout from the engine-time vote update | the operator trigger reproduces deterministically on the real runtime; the tick path needs the window described above |

All preconditions survive; the real runtime reproduces the consequence (debug panic, release demotion). Classification: **Case C**.

### Affected code

- `openraft/src/engine/engine_impl.rs:534-540` — quorum branch elects without re-checking role/round validity.
- `openraft/src/engine/engine_impl.rs:855-881` — `establish_leader` keeps `pre_candidate`.
- `openraft/src/engine/handler/vote_handler/mod.rs:173-229` — `become_leader` keeps `pre_candidate`.
- `openraft/src/engine/engine_impl.rs:298-322` — `pre_elect` runs while a real candidate is active.
- `openraft/src/engine/engine_impl.rs:976-981` — assertion that fails afterwards.

### Recommendation

Drop `pre_candidate` whenever the node leaves the would-be-candidate state — at least in `establish_leader`/`become_leader` (or in `update_internal_server_state` for every branch) — and make `handle_pre_vote_resp` ignore responses unless the node is still a non-leader whose vote term equals the probe term − 1. Optionally have `pre_elect` (tick path) skip or drop an in-flight real candidate consistently.

---

## Campaign results

See `spec/model-checking-summary.md` (generated from the logs) for every configuration's outcome, coverage, and limits.

## Not reproduced / not found (all campaigns; generated from spec/output/mc-*.log)

| Run | Config | Mode | Outcome | Violations | Coverage |
|---|---|---|---|---|---|
| canary-grant_response | Update_canary_grant_response.cfg | BFS | VIOLATION (stopped at first) | CanaryNoPreVoteGrantResponse | 34 generated, 12 distinct, queue 5, depth 4 |
| canary-leader_stale_round | Update_canary_leader_stale_round.cfg | BFS | VIOLATION (stopped at first) | CanaryNoLeaderWithStaleRound | 130605 generated, 30353 distinct, queue 19667, depth 9 |
| canary-nonvoter_round | Update_canary_nonvoter_round.cfg | BFS | VIOLATION (stopped at first) | CanaryNoNonVoterWithPreRound | 418438 generated, 96271 distinct, queue 54259, depth 13 |
| canary-prevote_elect | Update_canary_prevote_elect.cfg | BFS | VIOLATION (stopped at first) | CanaryNoPreVoteElect | 39 generated, 14 distinct, queue 4, depth 4 |
| canary-reject_response | Update_canary_reject_response.cfg | BFS | VIOLATION (stopped at first) | CanaryNoPreVoteRejectResponse | 867 generated, 285 distinct, queue 201, depth 7 |
| hunt-leader_object-bfs | MC_hunt_prevote_leader_object.cfg | BFS | VIOLATION (stopped at first) | LeaderObjectVoteNotBehind | 12117283 generated, 2328984 distinct, queue 1269566, depth 16 |
| hunt-leader_object-nofaults | Dbg_lo.cfg | BFS | VIOLATION (stopped at first) | LeaderObjectVoteNotBehind | 1352405 generated, 274093 distinct, queue 139475, depth 15 |
| hunt-prevote_default_rpc-filtered-bfs | MC_hunt_prevote_default_rpc_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 25414570 generated, 4502032 distinct, queue 2485561, depth 15 |
| hunt-prevote_default_rpc-filtered-sim | MC_hunt_prevote_default_rpc_filtered.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 21133192 states checked, 53414 traces |
| hunt-prevote_leader_object-filtered-bfs | MC_hunt_prevote_leader_object_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 21530385 generated, 4078580 distinct, queue 2176220, depth 18 |
| hunt-prevote_leader_object-filtered-sim | MC_hunt_prevote_leader_object_filtered.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 26069014 states checked, 69297 traces |
| hunt-prevote_membership-filtered-bfs | MC_hunt_prevote_membership_filtered.cfg | BFS | VIOLATION (stopped at first) | PreVoteGrantFromTrackedVoter | 10211218 generated, 2493371 distinct, queue 1541982, depth 17 |
| hunt-prevote_membership-filtered-nog-bfs | MC_hunt_prevote_membership_filtered_nog.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 54231050 generated, 12945589 distinct, queue 8110483, depth 19 |
| hunt-prevote_membership-filtered-nog-sim | MC_hunt_prevote_membership_filtered_nog.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 27778833 states checked, 68754 traces |
| hunt-prevote_single_voter-filtered-bfs | MC_hunt_prevote_single_voter_filtered.cfg | BFS | VIOLATION (stopped at first) | PreVoteGrantFromTrackedVoter | 469654 generated, 110227 distinct, queue 59789, depth 15 |
| hunt-prevote_single_voter-filtered-nog-bfs | MC_hunt_prevote_single_voter_filtered_nog.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 81093792 generated, 10179753 distinct, queue 2774682, depth 24 |
| hunt-prevote_single_voter-filtered-nog-sim | MC_hunt_prevote_single_voter_filtered_nog.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 23345786 states checked, 86843 traces |
| hunt-prevote_stale_round-filtered-bfs | MC_hunt_prevote_stale_round_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 23279454 generated, 4596957 distinct, queue 2792277, depth 15 |
| hunt-prevote_stale_round-filtered-sim | MC_hunt_prevote_stale_round_filtered.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 13762389 states checked, 33620 traces |
| std-MC-membership | MC-membership.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 47424150 generated, 7156362 distinct, queue 2239049, depth 23 |
| std-MC | MC.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 78465363 generated, 14550469 distinct, queue 8396335, depth 17 |
| update-discharge | Update_discharge.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 25836896 generated, 4835490 distinct, queue 2843702, depth 14 |
| update-focused-filtered | Update_focused_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 28340622 generated, 5130926 distinct, queue 3303178, depth 14 |
| update-full-filtered-sim | Update_full_filtered.cfg | simulation | LIMITED_COVERAGE (simulation budget) | — | 17712152 states checked, 48019 traces |
| update-full-filtered | Update_full_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 57247493 generated, 10620289 distinct, queue 6128180, depth 18 |
| update-full | Update_full.cfg | BFS | VIOLATION (stopped at first) | PreVoteRoundNotOutlivedByOwnLeadership | 11811353 generated, 2237808 distinct, queue 1342292, depth 15 |
| update-open-filtered | Update_open_filtered.cfg | BFS | LIMITED_COVERAGE (budget), no violation | — | 31141660 generated, 4863056 distinct, queue 3145319, depth 15 |

Canary violations are expected reachability witnesses. Runs without violations are budget-limited unless the queue is 0. Archived superseded/discarded logs (`*.superseded*`, `*.stopped*`, `*.discarded*`) are excluded; see `spec/changelog.md`.
