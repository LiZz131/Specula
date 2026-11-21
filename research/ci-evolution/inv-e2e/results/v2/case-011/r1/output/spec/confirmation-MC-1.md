# Confirmation MC-1 — A timer Pre-Vote round outlives the node's own leader establishment and demotes the new leader

- **Status**: REPRODUCED (end-to-end through RaftCore, 3/3 runs, deterministic with timing assistance)
- **Source**: model-checking (`TimerPreVoteElectsOnlyNonLeader`, Scenario U2)
- **Revision**: artifact commit `update` 3ab6cdd (test-only instrumentation applied by `harness/apply-instrumentation.sh`)
- **Attribution**: introduced by the update. The Pre-Vote state (`Engine::pre_candidate`) and the
  `handle_pre_vote_resp` → `elect()` path do not exist in `baseline`; the old-version control is not
  compatible (no `Config::enable_pre_vote`, no `trigger().elect(bool)`), so no old-version run is possible.

## Mechanism

1. `RaftCore::handle_tick_election` (`openraft/src/core/raft_core.rs:1959-2036`) skips only Leaders and
   non-voters; on a **Candidate** whose election has not finished within the election timeout it calls
   `Engine::pre_elect()` when Pre-Vote is enabled. `pre_elect` (`engine_impl.rs:297-322`) creates
   `pre_candidate` for the probe `(term+1, self)` and leaves the running `candidate` untouched.
2. Delayed vote grants for the *original* election arrive; `handle_vote_resp` → `establish_leader`
   (`engine_impl.rs:855-881`) → `update_vote` → `become_leader` (`vote_handler/mod.rs:172-228`). Neither
   clears `pre_candidate` (only `do_elect`, `engine_impl.rs:264`, and `become_following`,
   `vote_handler/mod.rs:244`, do).
3. Pre-Vote grants (given while peers still held the uncommitted candidate vote) pass the RaftCore
   correlation, which compares only the probed leader id (`raft_core.rs:1815-1816,2067-2090`), and
   `handle_pre_vote_resp` (`engine_impl.rs:534-539`) calls `self.elect()` with no leader/voter re-check.
4. `do_elect` → `update_vote(term+1, self, uncommitted)` → `update_internal_server_state` takes the
   `is_leading` branch, which does nothing (`vote_handler/mod.rs:154-161`): the node becomes a Candidate at
   term+1 **while the Leader object of the previous term remains**. The next `try_leader_handler()` call
   (heartbeat tick, `raft_core.rs:1851-1857,2126`; client write, `raft_core.rs:587`) violates its contract
   `leader.vote >= state.vote` (`engine_impl.rs:977-982`).

## Requirement evidence (non-implementation)

- `raft_core.rs:1964-1968`: the timer must not start an election on a Leader ("skip election, already a leader").
- `docs/protocol/pre_vote.md:3-6,21-26`: Pre-Vote is run by a follower before its election and exists to stop a
  healthy leader from being disrupted.
- `config/config.rs:397-404`: the real election is the follower timer's deferred continuation.
- `engine_impl.rs:977-982`: contract `leader.vote >= state.vote` while a Leader object exists.

## Model counterexample

`spec/output/MC-1_TimerPreVoteElectsOnlyNonLeader_cex.out` (copy of `mc-hunt-U2-bfs.log`, cfg
`MC_hunt_U2_prevote_leader.cfg`, 13 states): node 1 starts an election (term 1) and persists it; the timer
starts a Pre-Vote round on the Candidate (probe term 2); node 2 grants the real vote; node 1 becomes Leader
(term 1, committed) with the round still live; node 2 grants the probe; the Pre-Vote quorum makes node 1 a
Candidate at term 2 with `leaderActive` still TRUE. Full-reference admission: `spec/output/mc-Update-full-U2.log`
(see bug-report). Trace evidence: `traces/prevote_stale_round_after_leadership.ndjson` replays exactly this
transition in the implementation (TLC: `TimerPreVoteElectsOnlyNonLeaderStep = FALSE`,
`spec/evidence/E-U2-sep/tlc.log`).

## Reproduction

- Engine level (Level 0 entry points, state built through real engine calls):
  `harness/src/specula_trace_test.rs::specula_observe_stale_prevote_on_leader` →
  `spec/output/harness-observe_stale_prevote_on_leader.log`: leader established while the pre-candidate is
  live; after the late grant `server_state=Candidate`, `vote=<T3-N1:->`, Leader object `<T2-N1:Q>` retained,
  `try_leader_handler` panics `leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`.
- End-to-end RaftCore (Level 1, timing assistance only):
  `harness/src/t90_specula_repro_stale_prevote_leader.rs` (installed as
  `tests/tests/elect/t90_specula_repro_stale_prevote_leader.rs`).
  Command: `cd artifact && RUSTUP_TOOLCHAIN=stable cargo test -p tests --test elect t90_specula_repro -- --nocapture`.
  Setup: 3 voters, `enable_pre_vote = Some(true)`, election timeout 500–600 ms, heartbeat 100 ms; node 2's
  timer disabled; node 1's `save_vote` takes 400 ms (test-store hook `BlockOperation::DelaySaveVote`, a slow
  fsync); the network hook delays vote/Pre-Vote grant responses by 450 ms (below the 500 ms RPC timeout);
  leader 0 is isolated. Logs: `spec/output/repro-MC-1-run{1,2,3}.log`, timelines
  `spec/output/repro-MC-1-run{1,2,3}-timeline.txt`.
  Observed every run: `trigger pre-vote` while `state=Candidate` → `id=1 becomes leader` (T2) →
  `state=Leader handle_pre_vote_resp: a quorum would grant the vote; starting a real election` →
  `vote is changing from <T2-N1:Q> to <T3-N1:->` → `id=1 steps down from leader` → RaftCore panic
  `openraft/src/engine/engine_impl.rs:977:9: leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`;
  subsequent API calls return `Fatal::Panicked`.

## Consequence

A freshly elected, healthy leader abandons its term because of a Pre-Vote round that started before it
became leader: the cluster loses its leader and the term climbs — the disruption Pre-Vote is documented to
prevent. In debug builds RaftCore panics at the next heartbeat/write; in release builds the node is a
Candidate at term+1 that still drives a Leader object of the previous term.

## Trigger conditions

Pre-Vote enabled (non-default); the Candidate's election must outlast its election timeout and still win:
the vote responses must arrive after the timer fired but within the vote RPC timeout
(`election_timeout_min`). This needs vote persistence / command-drain latency larger than
`election_timeout - election_timeout_min` plus the tick phase (here a 400 ms `save_vote`).
