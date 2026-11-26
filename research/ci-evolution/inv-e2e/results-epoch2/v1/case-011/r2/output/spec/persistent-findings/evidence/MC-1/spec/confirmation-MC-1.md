# Confirmation — MC-1: a Pre-Vote round survives leader establishment and displaces the new leader

- **Source**: MC (actual counterexample, `Update_full.cfg`, property `PreVoteElectionPremiseCurrent`,
  `spec/output/MC-1_update_full_PreVoteElectionPremiseCurrent.out`, 12 states)
- **Revision**: artifact `update` 3ab6cdd (the changed-file snapshot `/work/new-source`)
- **Update attribution**: introduced by the update — the Pre-Vote round (`Engine.pre_candidate`) and its
  quorum-triggered `elect()` do not exist in `baseline` 1adc857.
- **Status**: **REPRODUCED** (escalation Level 1 — timing assistance in the test network only)
- **Severity**: Medium (availability/leadership stability; no committed-data safety violation observed or claimed)
- **Novelty**: no prior Specular record (`specular findings lookup` returned `[]`); external issue
  trackers and history were not searched because the blind-run isolation contract forbids them
  (`/work/input-manifest.json`), so novelty against upstream reports is undetermined.

## Phase 1 — Investigation (evidence)

### Code audit and call chain
1. Producer of the round while Candidate: `RaftCore::handle_tick_election` skips only
   `ServerState::Leader` (`openraft/src/core/raft_core.rs:1966-1969`); with Pre-Vote enabled and
   multi-voter it calls `Engine::pre_elect` (`raft_core.rs:2010-2035`). `Trigger::elect(true)` →
   `ExternalCommand::Elect { pre_vote: true }` calls it for any voter in any role
   (`raft_core.rs:1683-1695`, `raft/trigger.rs:45-63` (`elect` at :61)).
2. `Engine::pre_elect` builds `(vote.term+1, self, uncommitted)` and stores a new
   `pre_candidate` (`engine_impl.rs:298-322`); the Candidate's real election object
   `self.candidate` is untouched.
3. Old consumer: `Engine::handle_vote_resp` → `establish_leader` (`engine_impl.rs:450-470,855-881`)
   takes only `self.candidate`; its `update_vote(committed)` → `update_internal_server_state` →
   `become_leader` (`vote_handler/mod.rs:153-162,171-229`) — **no reset of `pre_candidate`**.
   The only resets are `do_elect` (`engine_impl.rs:263-264`) and `become_following`
   (`vote_handler/mod.rs:241-244`).
4. Affected consumer: `Notification::PreVoteResponse` is handled whenever `pre_candidate.is_some()`
   and the leader id matches (`raft_core.rs:1803-1820,2067-2090`); `handle_pre_vote_resp` grants and,
   on quorum, calls `self.elect()` with no role/vote check (`engine_impl.rs:516-540`).
5. `do_elect` on the Leader: vote → `(T+1, self, uncommitted)` + `SaveVote` + `SendVote`; the
   Leader object stays (`is_leading` path does nothing, `vote_handler/mod.rs:153-162`).
6. Next routine action: `RaftCore::trigger_routine_actions` → `Engine::try_leader_handler`
   (`engine_impl.rs:968-985`) hits `debug_assert!(leader.committed_vote >= state.vote)`.

### Reachability and trigger scenario
Peer P grants the real vote for `(T, X)`; P's vote is now uncommitted, so it has no leader lease and
grants the `(T+1, X)` Pre-Vote as well (`engine_impl.rs:425-446`). X's round therefore collects a
quorum from responses computed before X's first AppendEntries reaches P; when such a grant is
delivered after X won term T, X abandons term T.
- Deterministic public-API trigger: X is Candidate with its real vote responses in flight and the
  application calls `Trigger::elect(true)` (a "cautious" election), then the Pre-Vote replies arrive
  after the real-vote replies (ordinary network delay/reordering, within the RPC timeout).
- Timer trigger (production default when `enable_pre_vote` is set): X's election timer fires while it
  is still Candidate and a real-vote reply is still within its RPC timeout
  (`ttl = election_timeout_min`, `raft_core.rs:1402`), i.e. the reply arrives after the timer but
  within the window opened by X's own vote-persistence latency. Timing-dependent; not separately
  reproduced here.
- Safeguards checked: the runtime leader-id filter (`does_pre_candidate_vote_match`) does not help —
  the response matches the still-registered round; the tick's Leader skip does not apply to the
  response path; `establish_leader`/`become_leader` do not reset the round.

### Developer-knowledge evidence (in-tree only)
- `docs/protocol/pre_vote.md:4-6`: "Pre-Vote is an optional round that a follower runs **before** it
  increments its term and starts a real election."; `:40-46`: "the requester does not change its own
  state while pre-voting: it stays a Follower with its term unchanged until a quorum responds."
- `config/config.rs:397-404`: Pre-Vote "prevents a node that cannot currently win ... from inflating
  its term and disrupting a healthy leader".
- `core/raft_msg/external_command.rs:32-37` / `raft/trigger.rs:52-56`: with `pre_vote = true` "an
  incautious trigger does not disrupt a live leader".
- `engine_impl.rs:263` comment: "A real election supersedes any in-flight Pre-Vote round." — the reset
  exists for real elections started *after* a round, not for a real election that was already in
  flight when the round started.
- `tests/tests/elect/t12_pre_vote.rs` and the three new engine tests do not cover a round that
  coexists with an in-flight real election. No comment accepts this behavior.

## Phase 2 — Reproduction

- Test: `spec/repro/test_bugMC-1_pre_vote_after_establish.rs` (installed as
  `tests/tests/elect/t13_specular_repro_pre_vote_after_establish.rs` by `spec/repro/MC-1-repro.patch`).
- Escalation **Level 0** (pure black box) is not deterministic: ordering of the real-vote and
  Pre-Vote replies is left to the scheduler. **Level 1**: a test-only router knob delays only the
  *delivery* of replies the target already produced (300 ms real vote, 1200 ms Pre-Vote; RPC timeout
  2000 ms). No production code changed; no state injected; elections/heartbeats are triggered through
  `Raft::trigger()` and `set_network_error` (the old leader becomes unreachable).
- Schedule: 3 voters {0,1,2}, node 0 leader at term 1 → node 0 unreachable, leases expire →
  `n1.trigger().elect(false)` (Candidate, term 2) → 50 ms later, still Candidate,
  `n1.trigger().elect(true)` (round at term 3) → node 1 becomes Leader at term 2 and node 2 follows it
  → the delayed Pre-Vote grant arrives. This is the counterexample's action order (TickPreElect while
  Candidate, peer grants both, HandleVoteResponse wins, HandlePreVoteResponseElect).
- Command: `spec/repro/run-MC-1-repro.sh` (= `RUSTUP_TOOLCHAIN=nightly-2026-03-01 timeout 30m cargo test
  -p tests --test elect t13_specular_repro -- --test-threads=1 --nocapture`, then the same with
  `--release`).

### Output — debug build (`spec/repro/MC-1-repro-debug.log`; also `-run2`, `-run3`: 3/3)
```
thread 'tokio-rt-worker' (15121) panicked at openraft/src/engine/engine_impl.rs:977:9:
leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)
SPECULAR-REPRO: leader_term=2 core_alive=false n1.state=Leader n1.term=2 n1.vote=<T2-N1:Q> n2.state=Follower n2.term=2 n2.current_leader=Some(1)
```
Backtrace (`spec/repro/MC-1-repro-backtrace.log`): `Engine::try_leader_handler` ←
`RaftCore::trigger_routine_actions` ← `RaftCore::runtime_loop`. Node 1's RaftCore terminated right
after the stale quorum moved its vote to term 3; node 2 still reports node 1 as leader.

### Output — release build (`spec/repro/MC-1-repro-release.log`)
```
SPECULAR-REPRO: leader_term=2 core_alive=true n1.state=Candidate n1.term=3 n1.vote=<T3-N1:-> n2.state=Follower n2.term=2 n2.current_leader=Some(1)
SPECULAR-REPRO: +500ms core_alive=true n1.state=Candidate n1.term=3 n1.vote=<T3-N1:-> n2.current_leader=Some(1) n2.vote=<T2-N1:Q>
```
The leader elected at term 2 abandoned leadership (Candidate at term 3) with no failure after its
win; node 2 holds the term-2 leader's lease and rejects the term-3 vote, so the cluster has no working
leader for at least the lease.

### Control (same revision, same schedule, no Pre-Vote round)
```
SPECULAR-REPRO-CONTROL: leader_term=2 n1.state=Leader n1.term=2
SPECULAR-REPRO-CONTROL: leader_term=2 n1.state=Leader n1.term=2
```
Old-revision control: not applicable — `baseline` has no Pre-Vote round and `Trigger::elect()` takes no
argument; the mechanism is introduced by the update.

### Attribution of the two observed consequences
- The trigger is new: in `baseline` nothing runs `elect()` on an established leader unless the
  application explicitly calls `Trigger::elect()` on it (`/work/old-source/openraft/src/core/raft_core.rs:1616-1620`,
  "TODO: reject if it is already a leader?"). With the update, a stale Pre-Vote quorum does it without
  any election request to the leader.
- The debug-build panic is the downstream effect of `elect()` running on a Leader: `do_elect` leaves the
  Leader object in place and the existing `debug_assert` in `try_leader_handler`
  (`/work/old-source/openraft/src/engine/engine_impl.rs:811-815`, unchanged) fires on the next routine
  action. That handling is pre-existing; the release-build consequence (abdication, term bump, leaderless
  window) does not depend on it.

## Verdict
**REPRODUCED.** Reachable through public APIs with ordinary message delay; consumer-visible consequence:
the newly elected leader abandons its term (term inflation and a leaderless window — the disruption the
Pre-Vote documentation says the feature prevents) and, in builds with debug assertions, its RaftCore
panics. The model counterexample, the engine trace (`traces/pre_vote_after_establish.ndjson`, validated),
and the integration run show the same action sequence and code path.

**Recommendation**: cancel the Pre-Vote round when a real election wins — e.g. reset
`pre_candidate` in `establish_leader`/`become_leader` — and/or have `handle_pre_vote_resp` ignore
quorums when the node is no longer in the state the round probed (still a non-leader at the probed vote).
