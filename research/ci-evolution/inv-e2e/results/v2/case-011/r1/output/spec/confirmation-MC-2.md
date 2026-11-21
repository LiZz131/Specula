# Confirmation MC-2 — Pre-Vote responses of an earlier round are counted by a later round with the same probe; after a membership change grant_by panics

- **Status**: REPRODUCED (end-to-end through RaftCore, 3/3 runs)
- **Source**: model-checking (`StalePreVoteResponseIgnored`, consequence `PreVoteResponseNeverPanics`, Scenario U4)
- **Revision**: artifact commit `update` 3ab6cdd
- **Attribution**: introduced by the update (Pre-Vote rounds, `does_pre_candidate_vote_match`,
  `handle_pre_vote_resp` do not exist in `baseline`; old-version control not compatible).

## Mechanism

A Pre-Vote round does not change the local vote, so every round started at the same term probes the same
leader id `(term+1, self)` (`engine_impl.rs:297-322`). RaftCore drops a `PreVoteResponse` only when no
pre-candidate exists or the probed **leader id** differs (`raft_core.rs:1815-1816`,
`does_pre_candidate_vote_match`, `raft_core.rs:2067-2090`), although the function's own comment states
"If a Pre-Vote response is for a previous Pre-Vote round, it is stale and should be ignored"
(`raft_core.rs:2066`). A response of an earlier round therefore advances the current round
(`engine_impl.rs:534-539`). If the membership changed between the rounds, the responder may be outside
the current round's frozen quorum set; `Candidate::grant_by` then panics
(`proposer/candidate.rs:107`: `expect("target not in quorum set")`) and the RaftCore task dies.

Timer-only rounds are protected by timing (each Pre-Vote RPC times out after `election_timeout_min`, a new
timer round starts only after `election_timeout` — modeled as the `PreElect` timeout drop, changelog
Round 2). Operator rounds (`Raft::trigger().elect(true)`, `ExternalCommand::Elect { pre_vote: true }`,
`raft_core.rs:1683-1696`) have no such rate limit and are the exposed path.

## Model counterexamples

- `spec/output/MC-2_StalePreVoteResponseIgnored_cex.out` (`MC_hunt_U4_prevote_stale_round.cfg`, 6 states):
  node 2 timer round 1 (probe term 1) → operator round 2 (same probe) → node 3 answers the round-1
  request → node 2 counts it in round 2 and starts an election.
- `spec/output/MC-2_StalePreVoteResponseIgnored_fullMCNext_cex.out` (`Update.cfg`, complete MCNext, 7 states).
- Panic consequence: `spec/output/MC-2_PreVoteResponseNeverPanics_cex.out` (`MC_hunt_U4c_prevote_panic_operator.cfg`,
  16 states): node 1 (Candidate) gets an operator Pre-Vote round, wins its election (the round survives),
  node 3 grants the probe, the leader replaces {1,2,3} by {1,2} (joint, commit, uniform), a second operator
  round over {1,2} receives node 3's round-1 grant and the core panics. The model reaches membership change
  only through the leader's own appends; the follower-side path is the end-to-end reproduction below.

## Reproduction

- Engine level: `harness/src/specula_trace_test.rs::specula_observe_prevote_grant_from_non_member` →
  `spec/output/harness-observe_prevote_grant_from_non_member.log` (`probe_reused: true`, panic at
  `proposer/candidate.rs:107:59 target not in quorum set`).
- End-to-end RaftCore (Level 1, network delay hook only):
  `harness/src/t91_specula_repro_prevote_stale_round_panic.rs` (installed as
  `tests/tests/elect/t91_specula_repro_prevote_stale_round_panic.rs`).
  Command: `cd artifact && RUSTUP_TOOLCHAIN=stable cargo test -p tests --test elect t91_specula -- --nocapture`.
  Setup: voters {0,1,2,3}, timers off, leader heartbeats off so leases expire; node 1's Vote-kind RPCs to
  node 0 unreachable; node 3's first Pre-Vote grant to node 1 delivered 400 ms late (below the 500 ms RPC
  timeout). Steps: `n1.trigger().elect(true)` (round A over {0,1,2,3}); `n0.change_membership({0,1,2})`;
  `n1.trigger().elect(true)` (round B over {0,1,2}, same probe); node 3's round-A grant arrives.
  Logs: `spec/output/repro-MC-2-run{1,2,3}.log`, timelines `spec/output/repro-MC-2-run{1,2,3}-timeline.txt`.
  Observed every run: RaftCore of node 1 panics at `openraft/src/proposer/candidate.rs:107:59`
  (`target not in quorum set`); `trigger().heartbeat()` returns `Err(Panicked)`.

## Consequence

A delayed, legitimately produced network response crashes the Raft node (in every build: `expect`, not a
debug assertion). Without a membership change the stale grant is silently counted, so a round can start a
real election on answers given to an earlier round.

## Trigger conditions

Two operator Pre-Vote rounds at the same term with a response of the first still in flight (< RPC
timeout), and, for the crash, a membership change removing the responder between the rounds.
