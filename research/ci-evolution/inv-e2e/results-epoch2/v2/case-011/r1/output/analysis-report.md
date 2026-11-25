# Exact-old source analysis report

## Isolation and coverage

Analysis used only `/work/source`, `/work/scope.md`, and
`/work/input-manifest.json` for behavioral evidence. Git history, remotes,
issues, pull requests, release notes/changelogs, papers, internet research,
other revisions, and paths outside the declared workspace inputs were not used.
The mandatory archaeology phase was replaced by code-only structural and deep
analysis as requested.

The analysis covered all binding priority implementation files and their
directly linked vote, storage, quorum, membership-change, following, leader,
and restart helpers. It also read the neutral election, vote-handler,
membership, configuration-election, and follower-restart tests. The baseline
was built in `/work/work-source` with nightly-2025-12-31 because the requested
nightly-2026-03-01 toolchain was not installed and `/opt/rustup` is read-only.
The replacement toolchain completed 478 OpenRaft library tests, 2 election
integration tests, 44 membership tests, and 14 lifecycle tests; preserved logs
are under `spec/output/baseline-*.log`.

## Structural map

- `RaftCore` is the sole engine-state mutator. It processes an API/notification
  event, drains generated commands, and coordinates independently spawned RPC,
  replication, heartbeat, and storage work
  (`openraft/src/core/raft_core.rs:1088-1148,1190-1346`).
- `Engine` synchronously mutates projected protocol state and appends FIFO
  commands; it owns vote, candidate, leader, role, log IDs, and membership
  projections (`openraft/src/engine/engine_impl.rs:60-110`).
- `RaftState` distinguishes projected accepted state from submitted/flushed I/O
  progress (`openraft/src/raft_state/mod.rs:244-279,372-383`).
- `MembershipState` retains only committed and effective membership records,
  consistent with at most one outstanding membership entry
  (`openraft/src/raft_state/membership_state/mod.rs:24-67`).
- `Candidate` freezes vote, log, membership quorum, learners, and grant progress
  (`openraft/src/proposer/candidate.rs:19-42,66-103`).

## Atomicity and persistence

Engine handlers are atomic with respect to other core events, but their storage
and network effects are not. Commands are FIFO except that conditional
responses are moved into wait queues and consecutive compatible append commands
may be merged (`openraft/src/engine/engine_output.rs:49-99,118-128`). Storage
serializes writes; `save_vote` is durable on successful return, whereas log
append is readable on return and durable only at its callback
(`openraft/src/storage/v2/raft_log_storage.rs:27-33,58-107`). Thus the faithful
boundaries are projected mutation, command submission, readable log, durable
flush, and response/network visibility.

Election makes this ordering concrete. `do_elect` increments the term, builds a
candidate from the effective membership and last log, installs an uncommitted
self vote, and queues `SaveVote` before `SendVote`
(`openraft/src/engine/engine_impl.rs:230-253`,
`openraft/src/engine/handler/vote_handler/mod.rs:131-147`). Runtime awaits the
vote save and then enqueues the local granted response; only the later
`SendVote` command starts remote RPCs
(`openraft/src/core/raft_core.rs:2138-2166,2203-2205`). Consequently even the
self-vote is not counted before persistence.

## Vote and message semantics

The selected test configuration uses `leader_id_adv::LeaderId`, ordered by
term then node, and `Vote` orders committed above uncommitted for the same
leader (`openraft/src/engine/testing.rs:38-48`,
`openraft/src/vote/vote.rs:28-35`). A model that asserts one leader per numeric
term would be unfaithful; the complete `(term,node)` ballot is the relevant
identity.

Vote request processing is intentionally ordered:

1. reject a non-transfer request under an unexpired committed leader lease;
2. reject a less-recent candidate log;
3. compare/update the vote.

This is implemented at `openraft/src/engine/engine_impl.rs:285-326`. A transfer
request bypasses only step 1. `update_vote` requires `input >= local`; strict
increase updates projected vote and queues persistence, while equality refreshes
only the volatile lease (`openraft/src/engine/handler/vote_handler/mod.rs:105-149`).
All RPC replies wait on the current vote flush point
(`openraft/src/core/raft_core.rs:1483-1499`). Therefore a lower local vote may
be returned on an early lease/log rejection; the handler and neutral tests make
that exact-old behavior observable.

Successful remote responses are correlated twice: the notification carries the
originating candidate vote and the response must contain the exact active vote
with its granted bit (`openraft/src/core/raft_core.rs:1710-1729,1928-1953`,
`openraft/src/engine/engine_impl.rs:340-354`). Delayed responses for an absent or
different candidate do not grant. A rejected response with a higher log sets a
backoff hint; a higher returned vote is stripped of its committed bit before
local update (`openraft/src/engine/engine_impl.rs:356-389`).

## Quorum and membership

A single config uses strict majority. A joint config is a quorum only if the
same grant iterator contains a strict majority in every component
(`openraft/src/quorum/quorum_set_impl.rs:5-45`). Candidate construction clones
the effective membership, so later replacement of `MembershipState.effective`
does not mutate an election already in progress
(`openraft/src/engine/engine_impl.rs:113-130`). Learners do not contribute.

`MembershipState::append` requires a newer log and performs
`committed := old effective; effective := new`
(`openraft/src/raft_state/membership_state/mod.rs:183-203`). Commit copies
effective to committed only when the local commit frontier reaches its log and
the record is newer (`.../membership_state/mod.rs:121-147`). Conflict
truncation can revert only effective back to committed (`...:205-239`).
Ordinary membership evolution is coherent: uniform old to joint old/new, then
after the first log commits to uniform new
(`openraft/src/membership/membership.rs:280-339`,
`openraft/src/raft/api/management.rs:60-106`).

The effective record governs elections and present voter queries even before
commit. A leader removed by an effective entry deliberately continues leading
until commit and a separately scheduled, vote/config-fenced role refresh
(`openraft/src/engine/engine_impl.rs:479-508`,
`openraft/src/core/raft_core.rs:1660-1685`). Cached role must therefore not be
equated unconditionally with current membership containment.

## Leader establishment and AppendEntries contact

Once the frozen quorum grants, the candidate is consumed and becomes a leader
with a committed vote. Engine state and a blank entry are projected before
runtime effects; command order is rebuild replication, save committed vote,
append the blank, then replicate (`openraft/src/engine/engine_impl.rs:688-716`,
`openraft/src/engine/tests/handle_vote_resp_test.rs:215-238`). Heartbeat workers
do not send until explicitly triggered, so the rebuild does not leak leader
traffic before vote persistence (`openraft/src/core/heartbeat/worker.rs:82-99`).
The log may be replicated once readable and before its durability callback, but
the committed vote is already durable.

AppendEntries first updates the leader vote and following state. The vote save
therefore precedes conflict/log work; success replies wait on the accepted log
I/O flush (`openraft/src/engine/engine_impl.rs:395-437`,
`openraft/src/engine/handler/following_handler/mod.rs:64-109,146-180`). The model
retains ordinary committed-vote contact but abstracts payload contents and
replication backtracking as out of scope.

## Crash and restart

Reconstruction retains saved vote, durable logs/commit, state-machine applied
state, snapshot, and the last two relevant memberships. It loses candidate,
leader objects, grant progress, pending commands/replies, replication tasks,
`seen_greater_log`, I/O staging, and cached role
(`openraft/src/storage/helper.rs:83-223,313-399`,
`openraft/src/engine/engine_impl.rs:102-110`). A persisted pending self vote
restarts as follower/learner rather than resuming the election. A persisted
committed self vote restores leadership by default when membership permits;
startup proposes the missing leader no-op when needed
(`openraft/src/engine/engine_impl.rs:135-181`,
`openraft/src/engine/handler/vote_handler/mod.rs:197-227`).

The restored lease timestamp is reset to now, while its duration is zero. The
neutral follower-restart test verifies no immediate election within one second
and a later term increase within nine seconds, without establishing a formal
fairness guarantee (`tests/tests/life_cycle/t50_follower_restart_does_not_interrupt.rs:10-67`).

## Failure and progress assumptions

- Processes can crash between projected mutation and any later command.
- Successful vote persistence is durable; a failed backend write has no more
  precise atomic guarantee in the interface.
- Dispatched messages may be delayed, reordered, dropped, or duplicated by the
  environment, but are not forged.
- Storage errors terminate the core rather than rolling back projected engine
  state (`openraft/src/core/raft_core.rs:2068-2166`).
- Safety does not require fairness. Eventual election needs ticks/time advance,
  successful storage, scheduler execution, and enough delivered exact-vote
  responses, none of which is unconditional in the source.

## Neutral scenarios selected for tracing

The harness captures post-state around real exact-old methods, not a protocol
simulator: multi-node `elect`, stale-log request rejection, greater-vote grant,
exact-vote quorum establishment, leader membership append, membership commit,
and `startup` from persisted pending/committed states. These correspond to the
binding neutral election comparison, leadership seizure, membership change,
election under current configuration, and restart themes. Each trace carries a
real wall-clock nanosecond timestamp and complete captured state fields.

---

# Update analysis: Pre-Vote revision (synthetic commit `update`)

## U.0 Inputs and identity

- Old source: `/work/old-source` = artifact commit `1adc857` (`baseline`); new
  source: `/work/new-source` = artifact commit `3ab6cdd` (`update`). Both
  snapshots were byte-compared with `git show <rev>:<path>` for every changed
  file (all identical). The prior V0 suite is `/work/previous/.specula-output`
  (immutable); this run edits only `/work/current/.specula-output`.
- Prior validation state: V0 reported `LIMITED_COVERAGE`, no unresolved
  trace or model errors, no findings. Its conclusions are reused only within
  that coverage.
- Category stays **A (distributed/message-passing)**: the update adds one
  RPC, one notification kind, one engine command, and volatile engine state;
  it does not change the single-mutator RaftCore/Engine architecture.
- Toolchain: only `stable` (rustc 1.100.0) is installed here; the repository
  pins `nightly-2026-03-01`, unavailable and not installable (`/opt/rustup` is
  read-only). All builds use `RUSTUP_TOOLCHAIN=stable`. The new-source
  library suite passes 486/486 (`spec/output/baseline-new-openraft-lib.log`;
  V0 old source: 478).

## U.1 The source delta (all 39 changed files read)

Behavior-bearing changes (line numbers in the new tree):

| Site | Old | New |
|---|---|---|
| `engine/engine_impl.rs:95-101,117,149-165` | — | volatile `pre_candidate: Option<Candidate>`; `new_pre_candidate` freezes effective membership + last log |
| `engine/engine_impl.rs:262-264` | `do_elect` | first drops `pre_candidate` |
| `engine/engine_impl.rs:291-322` | — | `pre_elect`: probe vote `(term+1, self, uncommitted)`, self-grant; if self is already a quorum → `elect()`; else push `SendPreVote`. No vote/role change, no `SaveVote` |
| `engine/engine_impl.rs:406-447` | — | `handle_pre_vote_req`: lease check (never transfer), last-log check, `req.vote >= local vote`; no state change, no command |
| `engine/engine_impl.rs:512-554` | — | `handle_pre_vote_resp`: ignore if no pre-candidate; granted → `grant_by(target)`, quorum → `self.elect()` **with no further guard**; rejected → greater responder log sets `seen_greater_log`; never updates the vote |
| `engine/handler/vote_handler/mod.rs:51,244` | `become_following` drops leader, candidate | also drops `pre_candidate` |
| `core/raft_core.rs:1385-1478` | vote RPC fan-out | shared fan-out for Vote/PreVote; transport error is not a grant; `PreVoteResponse` notification carries the probed `candidate_vote` |
| `core/raft_core.rs:1551-1562,1603-1607` | — | `RequestPreVote` → `handle_pre_vote_req`, respond immediately (`when: None`) |
| `core/raft_core.rs:1683-1696` | `ExternalCommand::Elect` → `elect()` if voter | `Elect{pre_vote}`; `pre_vote` → `pre_elect()` (voter check at trigger time only) |
| `core/raft_core.rs:1803-1820,2067-2090` | — | `PreVoteResponse` handled only if a pre-candidate exists and its **leader id** equals the notified `candidate_vote` |
| `core/raft_core.rs:1959-2036` | tick → `elect()` | tick → `pre_elect()` when `enable_pre_vote && voter_count > 1`; skips while a round younger than `election_timeout` is in flight |
| `network/v2/network.rs:141-161`, `network/vote_trait.rs:28-36` | — | default `pre_vote` RPC synthesizes `VoteResponse::new(rpc.vote, None, true)` |
| `config/*.rs`, `raft/runtime_config_handle.rs`, `raft/trigger.rs`, `raft/mod.rs`, `raft/api/protocol.rs` | — | `enable_pre_vote: Option<bool>` (default off), runtime toggle, `trigger().elect(pre_vote)`, public `Raft::pre_vote` |
| `proposer/candidate.rs:90-99` | — | `starting_time()` accessor (rate limit) |

Non-behavioral or out-of-scope changes: `*_name.rs` enum/index renumbering,
`Display`/`PartialEq` arms, docs module wiring, metrics/integration tests that
only add the `pre_vote` argument (`trigger().elect(false)`), the new tests
(`pre_elect_test.rs`, `handle_pre_vote_{req,resp}_test.rs`,
`tests/tests/elect/t12_pre_vote.rs`) and the test router's `pre_vote` RPC
(`tests/tests/fixtures/mod.rs:973-998`). The new `pre_vote.md` is
requirement evidence.

## U.2 Projection onto the model vocabulary and decision

Changed behavior projected onto the V0 vocabulary is **not** equal:

1. New messages (`PreVoteReq`, `PreVoteResp`) and new volatile engine state
   (`pre_candidate`) that later gates a real election.
2. The election tick's projected effect changes when Pre-Vote is enabled:
   the V0 tick always reached `StartElection`; now it reaches a step that
   leaves vote/role unchanged and only emits requests.
3. A **new caller of `Engine::elect()`** (`handle_pre_vote_resp`) that does
   not carry the tick/external guards (not Leader, is voter, timeout
   expired). V0's `StartElection` assumed those guards.
4. `do_elect` and `become_following` now also clear the new state; every V0
   action that reaches `become_following` (vote grant to another node,
   adopting a higher vote from a response, AppendEntries contact, refresh,
   restart) changes its projected post-state.
5. Correctness requirements change: `pre_vote.md` adds "persists nothing and
   changes nothing", "stays a Follower with its term unchanged until a
   quorum responds", and "If a quorum would grant, the node runs the real
   election".

**Disposition: `MODEL_CHANGE_REQUIRED`.**

## U.3 Repairs of the old model found during the update

- `StartElection` reset `seenGreaterLog` for every caller. In both revisions
  only the tick handler resets it (`core/raft_core.rs:2027`, old 1922)
  before calling the engine; `Engine::elect`/`do_elect` do not. V0 never
  validated this (its harness hard-coded `seen_greater_log: false`). Repaired:
  `DoElect` takes the new value from the caller; `TickElect`/`TickPreVote`
  reset, engine-level/external/pre-vote-response callers do not. This is an
  existing-model repair, not part of the source delta.
- The V0 harness captured `candidate_config` as the *effective* config
  (proxy). The real frozen quorum set is reachable through
  `Candidate::progress().quorum_set()`; the rebased harness captures it for
  both candidate and pre-candidate.

## U.4 Update-focused deep analysis (interactions)

Producers/consumers of the changed path, traced through both revisions:

- **Old producer → changed Action → old consumer (Scenario U2).** A
  Candidate whose election timer expires with Pre-Vote enabled calls
  `pre_elect()` (`raft_core.rs:2012-2036`) *without* dropping its real
  `candidate` (`pre_elect` only replaces `pre_candidate`). Late real
  `VoteResponse`s for that candidate still match
  (`does_candidate_vote_match`, `raft_core.rs:2040-2063`), so the node can
  still win and call `establish_leader` (`engine_impl.rs:855-881`), which
  takes `candidate` and reaches `become_leader` through `update_vote`
  (`vote_handler/mod.rs:154-162,173-229`). Neither drops `pre_candidate`.
  Pre-Vote grants for that round (issued by peers whose leases are not yet
  set by the new leader) still match the leader-id filter
  (`raft_core.rs:2067-2090`) and reach `handle_pre_vote_resp`, whose quorum
  branch calls `self.elect()` (`engine_impl.rs:534-540`) with no role check.
  The freshly established Leader therefore abandons its term and starts a
  new election at `term+1`. In V0 this path did not exist: the tick never
  elects for a Leader (`raft_core.rs:1966-1969`, old 1876-1879), and a timed
  out Candidate's tick replaced the candidate (late responses filtered).
  Timing in the implementation: the round starts at `t0 + election_timeout`
  after the election (`is_expired(now, election_timeout)` measured from the
  engine-time vote update), while each real vote RPC is spawned only after
  `save_vote` returns and is bounded by `election_timeout_min`
  (`raft_core.rs:1403`); with `election_timeout` close to its minimum and a
  non-zero vote-persist latency the window is non-empty, and an operator's
  `trigger().elect(true)` opens it deterministically.
- **Changed Action → retry (Scenario U2b).** Rounds restarted at the same
  vote term reuse the probe leader id `(term+1, self)`; the runtime filter
  compares only leader ids, so grants from an earlier round count in a later
  round. RPC timeouts (`ttl = election_timeout_min`) bound response delay
  below the tick's restart interval, but back-to-back external triggers have
  no rate limit. Recorded as code-review defect D-4.
- **Changed Action vs. membership (Scenario U3).** `pre_elect` freezes the
  effective membership; `handle_pre_vote_resp` counts grants against it and
  `elect()` then reads the current effective membership. On followers every
  membership change arrives through `update_vote` → `become_following`,
  which drops the round. Only a node whose vote names itself (Leader, or the
  Candidate of U2) can change membership while holding a round. The voter
  check of `ExternalCommand::Elect` / tick is performed when the round
  starts, not when `elect()` finally runs.
- **Old context → changed Action → crash/recovery.** `pre_candidate` is
  volatile; restart reconstructs an Engine with `pre_candidate: None`
  (`engine_impl.rs:117`). Pre-Vote persists nothing, so there is no new crash
  window; `elect()` reached from the Pre-Vote path keeps V0's SaveVote →
  SendVote ordering.
- **Old Action interrupts the changed path (Scenario U4).** Every accepted
  vote (`update_vote`) that names another node — real vote grant, adopted
  higher response vote, AppendEntries/heartbeat contact, `HigherVote` — and
  `refresh_server_state` for a non-leading node reach `become_following`,
  dropping the round. Rejected requests and Pre-Vote requests do not.
- **Network default (Scenario U5).** The default `pre_vote` grants
  unconditionally (degrades to V0 election); transport errors are not grants
  (`raft_core.rs:1459-1471`). `pre_vote.md:57-63` states the opposite
  (`Unreachable` default treated as a grant) — documentation defect D-3.
- **Persistence/visibility properties.** Pre-Vote requests carry a
  never-persisted vote by design; Pre-Vote grants grant nothing. V0's
  `VoteRequestAfterDurable` / `GrantedResponseAfterDurable` quantify only the
  real kinds and remain the correct requirements (see
  `spec/invariant-evidence.json`).

## U.5 Exclusions retained / added

Timer durations, randomization of `election_timeout`, the round's time-based
rate limit, RPC timeouts, metrics, transport framing, the runtime-config
toggle's memory ordering, and `RaftNetwork` adapters are not modeled. The
tick's rate limit is abstracted to "a new round may replace the old one".
The test router's `pre_vote` (fixtures) is test infrastructure.

## U.6 Validation and model-checking results (this run)

- Validation: 23 fresh traces (7 regenerated V0 scenarios, 16 update
  scenarios) pass real TLC replay with `TraceConsumed` and all Trace.cfg
  invariants on the final model (`spec/output/trace-validation-round5.log`);
  20/20 single-field mutants are rejected. Three V0 model defects were
  repaired (leader lease on establishment, `LogLE` for absent logs,
  `RefreshServerState` leading case); see `spec/changelog.md`.
- **MC-1 confirmed (Scenario U2, defect-ledger D-1).** `Update_full.cfg`
  violates `PreVoteRoundNotOutlivedByOwnLeadership` in 14 states. The same
  behavior appears in the TLC-validated real-engine trace
  `stale_prevote_after_win`, and on the real RaftCore runtime
  (`harness/repro/t13_specula_stale_prevote_repro.rs`): debug build —
  RaftCore panics at `engine_impl.rs:977` (`leader.vote(<T2-N1:Q>) >=
  state.vote(<T3-N1:->)`); release build — the new Leader is demoted to a
  term-3 Candidate. The control without the Pre-Vote trigger keeps the
  Leader. Not expressible on the old revision (no Pre-Vote).
- **Pre-existing (CR-PRE-1).** An operator `trigger().elect()` on the
  current Leader reaches the same retained-Leader-object state and panics
  RaftCore in both revisions (`spec/output/control-elect-on-leader-{old,new}.log`);
  developer-acknowledged by the `TODO: reject if it is already a leader?`
  at `core/raft_core.rs:1685` (old 1618). Not attributed to the update.
- **MC-2 confirmed (Scenario U2b/U3, defect-ledger D-4).** In the
  membership hunt, without any crash, a delayed grant for an earlier Pre-Vote
  round at the same probe leader id is counted in a later round after its
  sender was removed (`PreVoteGrantFromTrackedVoter`,
  `spec/output/MC-2_cross_round_grant_violation.out`). On the real runtime
  (`harness/repro/t15_specula_cross_round_grant_repro.rs`, 3/3 runs) the
  leader's RaftCore panics at `proposer/candidate.rs:107` ("target not in
  quorum set"): `Candidate::new` tracks only the frozen voters
  (`candidate.rs:78`).
- **D-2 unresolved.** `PreVoteElectionByVoter` is violated (MC-1 root cause +
  self-removal; operator `elect(true)` on a Leader + self-removal;
  `spec/output/D-2_*.out`), but only implementation guards say a non-voter
  must not elect while the code documents that a learner may lead.
- **D-3 confirmed (documentation).** `pre_vote.md:57-63` contradicts the
  default `pre_vote` implementation and the `Unreachable` handling (test
  `pre_vote_unreachable_peer_is_not_a_grant` passes).
- No other property violation in any campaign: the standard `MC.cfg` round
  (14.55 M distinct states, depth 17) and the membership companion (7.16 M,
  depth 23) preserve every V0 safety property; the filtered full/focused/open
  checks, the discharge check, the scenario hunts and their simulations are
  clean for the remaining properties (all budget-limited:
  `LIMITED_COVERAGE`). Campaign outcomes: `spec/model-checking-summary.md`.
- Persistent-findings lookup: the `specular` CLI is not installed in this
  environment and the prior V0 suite records no findings, so there was no
  historical record to match or reuse; all findings are new to this run.
