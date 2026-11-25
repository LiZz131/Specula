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

# Update analysis — incremental run `incr-705b7bab5f0d`

## Inputs and isolation

- Old: `/work/old-source` (changed-file snapshot) and the V0 suite in
  `/work/previous/.specular-output`. New: `artifact/` commit
  `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` ("update", parent `1adc857`
  "baseline"); `/work/new-source` is the changed-file snapshot of it.
- Only the supplied old/new source, the neutral two-commit diff, and the prior
  suite were used. No upstream history, issues, PRs, or internet material.
  (The new test file `tests/tests/elect/t12_pre_vote.rs` mentions an upstream
  issue number in a comment; it was not looked up.)
- Category unchanged: **A (distributed / message-passing)**. The update adds a
  new RPC and a new engine sub-state; it does not change the concurrency
  architecture (single RaftCore mutator, spawned RPC tasks, FIFO notifications).

## Decision gate (Chapter 1)

Disposition: **MODEL_CHANGE_REQUIRED**. Projected onto the prior vocabulary,
the update changes modeled behavior in every one of these ways:

| Changed branch (new source) | Old projected effect | New projected effect |
|---|---|---|
| `handle_tick_election` (`core/raft_core.rs:1959-2036`), `enable_pre_vote && voters > 1` | timer always runs `elect()` (vote/term change, SaveVote, SendVote) | timer runs `pre_elect()`: no vote/role/lease change, new pre-candidate state, new `SendPreVote` command; restart of a stale round |
| `ExternalCommand::Elect { pre_vote }` (`:1683-1693`) | `elect()` | `pre_elect()` or `elect()` |
| `Engine::pre_elect` (`engine/engine_impl.rs:298-322`) | — | new state `pre_candidate` (vote term+1, frozen membership, last log, grants), self grant, single-voter shortcut to `elect()` |
| `RaftMsg::RequestPreVote` → `handle_pre_vote_req` (`:414-446`, `raft_core.rs:1551-1562`) | — | new message kind; lease/log/vote checks; immediate response, no state change |
| `Notification::PreVoteResponse` → `does_pre_candidate_vote_match` → `handle_pre_vote_resp` (`raft_core.rs:1803-1820,2067-2090`; `engine_impl.rs:516-554`) | — | tally; quorum → `elect()`; reject + greater log → `seen_greater_log` |
| `do_elect` (`:262-264`) | — | drops `pre_candidate` |
| `VoteHandler::become_following` (`vote_handler/mod.rs:244`) | drops leader, candidate | also drops `pre_candidate` (affects every `update_vote` caller) |
| `spawn_parallel_vote_requests(kind)` (`raft_core.rs:1385-1478`) | vote RPC; transport error logged | same for both kinds; a Pre-Vote transport error is not a grant |

Excluded concrete details (effects preserved in the model): election-timeout
durations and the "fresh round" rate limit (abstracted to "a tick may restart a
round"), the RPC `ttl`, network-default `pre_vote` implementation (equivalent to
an always-granting responder; not modeled separately), metrics/notification
names, clap/serde config plumbing, and the RuntimeConfig toggle (modeled by the
constant `PreVoteNodes`; a runtime flip is a choice between the two timer paths).

## Update mechanism and code facts used by the model

1. **Round identity.** `pre_elect` builds the pre-vote from the *current* vote:
   `(vote.term + 1, self)` (`engine_impl.rs:299-301`). Because `pre_elect`
   never changes `vote`, every round started at the same local term has the
   same leader id. RaftCore forwards a response if a pre-candidate exists and
   `candidate_vote.leader_id() == pre_candidate.vote.leader_id()`
   (`raft_core.rs:2067-2090`), although its doc comment says a response "for a
   previous Pre-Vote round ... is stale and should be ignored" (`:2066`).
   New rounds at the same term arise from the timer restart rule
   (`:2014-2024`), from operator `trigger().elect(true)` (no rate limit), and
   after `become_following` dropped a round (e.g. leader contact).
2. **Tally precondition.** `Candidate::grant_by` panics with
   `expect("target not in quorum set")` when the responder is not a voter of the
   round's frozen membership (`proposer/candidate.rs:106-112`). A stale grant
   from a node removed between two rounds therefore panics RaftCore.
3. **Round lifetime.** The pre-candidate is dropped only by `do_elect`,
   `become_following`, and Engine re-creation. `establish_leader` /
   `become_leader` do not drop it (`engine_impl.rs:855-880`,
   `vote_handler/mod.rs:172-228`). The election timer keeps firing for a
   Candidate (`raft_core.rs:1965-2008`: only Leaders/non-voters skip), so a
   Candidate whose election takes longer than `election_timeout` starts a
   Pre-Vote round *while its real election is still running*; operators can do
   the same with `trigger().elect(true)`.
4. **Win path.** `handle_pre_vote_resp` calls `elect()` on quorum with no role,
   voter, or vote-change check (`engine_impl.rs:533-540`). `do_elect` installs
   `(vote.term+1, self)`; `update_internal_server_state` keeps an existing
   `leader` object when the node is still leading
   (`vote_handler/mod.rs:154-162`), so a Leader that runs it keeps a stale
   leader object; `try_leader_handler` asserts
   `leader.vote >= state.vote` (`engine_impl.rs:976-981`, `debug_assert!`).
5. **Responder.** `handle_pre_vote_req` checks lease (no transfer bypass), then
   last log, then `req.vote >= local vote`, and changes nothing; RaftCore
   responds without an IO condition (`raft_core.rs:1551-1562`).

## Pre-existing reference defects repaired (separate from the source delta)

- **R1 `LogLE` on absent log ids** (`base.tla` `LogEq`). `NoLog(i)` records the
  node id as a placeholder, so two `None` last-log ids compared unequal and every
  vote/pre-vote request between empty-log nodes was rejected. In code
  `None >= None` (`engine_impl.rs:379,434`). Consequence in V0: no 3-voter
  election could succeed from `Init` in `MC.cfg` (leader-related properties were
  vacuous there; only the 1-voter companion exercised them). Evidence: fresh
  trace `grant_vote_empty_logs` is rejected by the V0 model
  (`spec/evidence/E-LogNone/prior-model-grant_vote_empty_logs.log`) and accepted
  by the repaired model; canary `CanaryNoCertifiedLeader` now violated.
- **R2 leader lease after establishment.** `establish_leader → update_vote`
  installs the committed self vote with `leader_lease`
  (`vote_handler/mod.rs:124-137`); V0 left `leaseValid` unchanged. Exposed by
  `candidate_prevote_establish` event 9.
- **R3 tick guards.** The timer requires an expired vote lease and skips a single
  voter with an active candidate; only the timer path resets
  `seen_greater_log` (`raft_core.rs:1959-2036`). V0 allowed ticks under a valid
  lease (over-approximation that would create spurious Pre-Vote disruption).
- **R4 harness capture.** V0 hard-coded `seen_greater_log=false` and recorded the
  effective membership as `candidate_config`; both now read real engine state.

## Update Scenarios (detailed in modeling-brief.md §2U)

- U-A: timer/external Pre-Vote round started while Candidate → real election
  wins → round quorum → new Leader runs another election.
- U-B: two rounds at the same local term → earlier-round response counted by the
  later round.
- U-C: U-B plus a membership change removing the responder → `grant_by` panic.
- U-D: Pre-Vote × crash/restart × lease × message loss (side-effect freedom).
- U-E: unchanged consumers (`become_following`, `do_elect`) cancel a round.

## Results summary

See `spec/bug-report.md` (model-checking findings MC-1, MC-2 with saved
counterexamples), `spec/confirmation-MC-1.md`, `spec/confirmation-MC-2.md`
(real-interface reproductions), and `spec/changelog.md`.
