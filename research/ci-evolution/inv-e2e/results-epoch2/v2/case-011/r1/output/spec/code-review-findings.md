# Code-review findings (update run, case-011)

These complement `spec/bug-report.md` (model-checking finding MC-1). IDs map
to the defect ledger in `modeling-brief.md` / `defect-ledger.json`.

## CR-PRE-1 — Operator election trigger on the current Leader keeps a stale Leader object (pre-existing)

- Sites: `openraft/src/core/raft_core.rs:1683-1696` (new; old 1616-1626, with
  `TODO: reject if it is already a leader?` at new 1685 / old 1618),
  `openraft/src/engine/engine_impl.rs:262-289` (`do_elect`),
  `openraft/src/engine/engine_impl.rs:976-981` (assertion; old 811-816).
- Trigger: `raft.trigger().elect()` (old API) / `elect(false)` (new API) on
  the node that is currently Leader.
- Observation (real runtime, RaftRouter + memstore, debug build):
  `harness/repro/t14_specula_elect_on_leader_{old,new}.rs`;
  `spec/output/control-elect-on-leader-old.log` — panic at
  `engine_impl.rs:811`, core `Err(Panicked)`;
  `spec/output/control-elect-on-leader-new.log` — panic at
  `engine_impl.rs:977`, core `Err(Panicked)`.
- Model: violates `Update!LeaderObjectVoteNotBehind` through `ExternalElect`
  on a Leader (e.g. `spec/output/mc-update-full-filtered.superseded-filter-semantics.log`).
- Attribution: present in both revisions; **not introduced by the update**.
  MC-1 reaches the same failing state without any operator election on a
  Leader (`spec/output/MC-1_leader_object_attribution.out`: elections only
  through Pre-Vote).
- Status: REPRODUCED (both revisions). Severity: Medium (operator misuse
  path; developer-acknowledged TODO).

## D-3 — Pre-Vote protocol documentation contradicts the implementation (update)

- Site: `openraft/src/docs/protocol/pre_vote.md:57-63` says the default
  `RaftNetworkV2::pre_vote` returns `Unreachable` and that "A node treats an
  `Unreachable` Pre-Vote response as a grant".
- Implementation: the default synthesizes a grant,
  `Ok(VoteResponse::new(rpc.vote, None, true))`
  (`network/v2/network.rs:158-161`, `network/vote_trait.rs:34-36`); transport
  errors including `Unreachable` are never counted
  (`core/raft_core.rs:1459-1471`); `config.rs:417` agrees with the code.
- Test evidence: `tests/tests/elect/t12_pre_vote.rs:231-272`
  (`pre_vote_unreachable_peer_is_not_a_grant`) passes on the updated source
  (`spec/output/baseline-new-elect.log:181`), i.e. `Unreachable` is not a grant.
- Consequence: an implementor following the protocol doc may return
  `Unreachable` from an unimplemented `pre_vote`, expecting a grant; their
  node then can never assemble a Pre-Vote quorum when Pre-Vote is enabled.
- Status: REPRODUCED (documentation/implementation mismatch confirmed by
  inspection and the passing test). Severity: Low.

## D-4 → MC-2 — Pre-Vote responses are correlated only by probe leader id (confirmed)

- Promoted to model-checking finding **MC-2** (`spec/bug-report.md`, Bug 2):
  counterexample `spec/output/MC-2_cross_round_grant_violation.out` (no crash);
  real-runtime reproduction `harness/repro/t15_specula_cross_round_grant_repro.rs`,
  `spec/output/repro-D-4-new*.log` (3/3 panics at `proposer/candidate.rs:107`).
- Note: an earlier simulation counterexample
  (`spec/output/D-4_PreVoteGrantFromTrackedVoter_single_voter_sim.out`) used a
  crash/restart between the rounds; the implementation cannot deliver an RPC
  response to a restarted process (it returns to the dead incarnation's
  future), so that particular path is a model over-approximation of response
  delivery; MC-2 rests on the crash-free counterexample and the real runtime.

## D-2 — Voter check only at round start (unresolved)

- Model checking violated `PreVoteElectionByVoter` (status `unknown`) in two ways:
  - `spec/output/D-2_PreVoteElectionByVoter_membership.out` (BFS, 15 states;
    also by simulation, `..._membership_sim.out`): the MC-1 root cause (a round
    started as Candidate survives the win) followed by the Leader removing
    itself (joint → uniform `{3}`); the stale grant then makes the non-voter
    call `elect()` (term bump; `become_following` drops the new candidate, but
    `do_elect` has already queued `SendVote`, `engine_impl.rs:280-286`).
  - `spec/output/D-2_PreVoteElectionByVoter_single_voter.out` (BFS, 12
    states): an operator `trigger().elect(true)` on the Leader passes the
    voter check (`core/raft_core.rs:1683-1696`), the Leader removes itself,
    and the later Pre-Vote quorum elects a non-voter.
- Requirement: only implementation guards ("skip election, not a voter",
  `raft_core.rs:1971-1974`); the code also documents that a learner may lead
  (`engine_impl.rs:656-658`). Per the divergence rules this stays
  **unresolved** (no property edit, no defect claim); the first variant is
  covered by MC-1's fix. Status: NEEDS MORE INFO.
