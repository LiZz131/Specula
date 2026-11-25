# Confirmation — MC-2: Pre-Vote round started while Candidate survives leader establishment

- **Source**: MC (actual counterexample `spec/output/cex-update-full-TimerPreVoteElectionFromFollowerState.log`, property `TimerPreVoteElectionFromFollowerState`, config `Update_full_cont1.cfg`)
- **Novelty**: NEW (no prior Specular record; blind run, external trackers not consulted)
- **Status**: REPRODUCED
- **Severity**: High
- **Location**: `openraft/src/core/raft_core.rs:1959-2036` (tick Pre-Vote branch for Candidates), `openraft/src/engine/engine_impl.rs:855-880` (`establish_leader` keeps `pre_candidate`), `openraft/src/engine/engine_impl.rs:533-540` (quorum → `elect()`), `openraft/src/engine/engine_impl.rs:976-981` (`try_leader_handler` invariant)
- **Source revision**: `artifact/` `3ab6cddc34a5bf127747434bb41e20a1b9ef7769`

## Description

A Candidate's election timer (or `trigger().elect(true)`) starts a Pre-Vote
round while its real election is still running. If the real election then wins,
`establish_leader` keeps `Engine.pre_candidate`; when the round's grants arrive,
`handle_pre_vote_resp` calls `elect()` and the freshly established Leader starts
another election at term+1, stepping down. The old `leader` object is kept by
`do_elect`, so `try_leader_handler`'s `debug_assert!(leader.vote >= state.vote)`
fails in debug builds.

## Trigger scenario (model counterexample, 13 states)

External elect → Candidate (1,1) → timer Pre-Vote round (2,1) while Candidate →
real vote quorum → Leader at term 1 with pre-candidate still active → Pre-Vote
grant → quorum → `elect()` → (2,1) Candidate.

## Investigation (Phase 1)

- Timer fires for Candidates: only `ServerState::Leader` and non-voters skip
  (`raft_core.rs:1965-1974`); a Candidate's uncommitted vote has zero lease, so
  the tick runs after `election_timeout` (`:1997-2008`) and with Pre-Vote
  enabled runs `pre_elect` (`:2010-2036`), which does not touch `candidate`.
- `pre_candidate` is cleared only by `do_elect` (`engine_impl.rs:264`),
  `become_following` (`vote_handler/mod.rs:244`), and Engine re-creation.
- Developer intent: `docs/protocol/pre_vote.md:3-5` (a follower's round before it
  increments its term), `pre_vote.md:44-45` (requester stays a Follower until a
  quorum responds), `config/config.rs:400-404` (prevents disrupting a healthy
  leader), `engine_impl.rs:976-981` (`debug_assert!` leader.vote >= state.vote).
- Engine-level code observation: harness trace
  `traces/candidate_prevote_establish.ndjson` (validated by `Trace.tla`;
  trace-lens witness `spec/evidence/trace-lens/candidate_prevote_establish.log`)
  — the test asserts `establish_leader keeps the pre-candidate` and that the
  Leader's vote becomes `(3,1)`.
- Timer-path timing: the real-vote RPC is bounded by `ttl =
  election_timeout_min` while the timer fires after `election_timeout ∈
  [min, max)`, so the timer variant needs vote persistence/notification delays
  that exceed `election_timeout - election_timeout_min`; the operator variant
  (`trigger().elect(true)` on a Candidate) has no timing constraint.

## Reproduction (Phase 2)

- **Test**: `harness/repro/t13_specular_pre_vote_repro.rs::repro_mc2_pre_vote_round_survives_leader_establishment`
  (integration test through the public `Raft` API and `RaftRouter` RPC hooks;
  asserts the correct behavior and FAILS when the defect triggers).
- **Steps**: 3-node cluster with `enable_pre_vote=Some(true)`; old leader n0
  isolated, leases expire; n1 `trigger().elect(false)` → Candidate at T2 (n2's
  grant held); n1 `trigger().elect(true)` while Candidate → Pre-Vote round T3
  (n2's grant held); release the T2 vote → n1 Leader at T2; release the T3
  Pre-Vote grant.
- **Result**: REPRODUCED.
  - Debug build (`harness/repro/repro-current.log`): log shows
    `id=1 becomes leader`, then `a quorum would grant the vote; starting a real election`,
    `id=1 steps down from leader`, then
    `panicked at openraft/src/engine/engine_impl.rs:977:9: leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`;
    `n1.with_raft_state() => Err(Panicked)`.
  - Release build (`harness/repro/repro-current-release.log`):
    `after pre-vote grant: state=Candidate term=3 vote=<T3-N1:->` — the
    established Leader abandoned leadership and inflated its term.
  - Excerpt: `harness/repro/repro_mc2_pre_vote_round_survives_leader_establishment.excerpt.log`.
- **Old-revision control**: not applicable — no Pre-Vote round exists in the old
  revision. (The stale-leader-object assertion is also reachable in the old
  revision only through an explicit operator `elect()` on a Leader, which the
  old code marks `TODO: reject if it is already a leader?`; the update adds an
  automatic path from a round started before the node became Leader.)

## Consequence

Leadership loss and term inflation right after a successful election — the
disruption Pre-Vote is meant to prevent; RaftCore panic in debug builds.

## Recommendation

Clear `pre_candidate` in `establish_leader`/`become_leader` (and whenever a
real election starts), and ignore Pre-Vote quorums unless the node is still a
non-leader voter at the vote the round was started from.
