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

# Incremental update analysis: Pre-Vote (this run)

## Inputs and isolation

- Old: `/work/old-source` (changed-file snapshot) and the `baseline` commit
  `1adc857` of `artifact/`; new: `/work/new-source` and the `update` commit
  `3ab6cddc34a5bf127747434bb41e20a1b9ef7769`. The full neutral diff
  (`git diff HEAD~1 HEAD` in `artifact/`, 39 files, +1283/-80) was read; every
  changed function in `engine_impl.rs`, `vote_handler/mod.rs`, `raft_core.rs`,
  `candidate.rs`, `config.rs`, `runtime_config.rs`, `network/*`, `raft/*`, the
  new engine unit tests and `tests/tests/elect/t12_pre_vote.rs` were read with
  their callers (`handle_tick_election`, `handle_raft_msg`, notification
  handling, `establish_leader`, `update_vote`/`become_leader`/`become_following`,
  `startup`, `try_leader_handler`).
- No history, issues, network research, or other revision was consulted.
- The prior V0 suite was reused as semantic evidence; two of its abstractions were
  found defective (see "Model repairs").

## Behavior before and after (projection onto the model vocabulary)

| Changed branch | Old behavior | New behavior | Projected effect | Disposition |
|---|---|---|---|---|
| `handle_tick_election`, multi-voter, flag off (default `None`) | `elect()` | `elect()` (timeout computation moved, same value) | equal | unchanged branch, re-modeled as `TickElect` with repaired guards |
| `handle_tick_election`, multi-voter, flag on | `elect()` | skip if a fresh round is in flight, else `reset_greater_log(); pre_elect()` | new state (tracker), new messages, no vote change | new Action `TickPreElect` |
| `handle_tick_election`, single voter | `elect()` (skip while candidate) | same | equal | `TickElect` |
| `ExternalCommand::Elect` | `elect()` | `Elect { pre_vote }`: `pre_elect()` or `elect()` | new branch | `ExternalPreElect`, `ExternalElect` |
| `Engine::do_elect` | new candidate, SaveVote, SendVote | additionally `pre_candidate = None` | tracker cleared | `DoElectCore` |
| `Engine::pre_elect` | absent | tracker with `(term+1, self)`, frozen effective config, self grant; single voter -> `elect()`; else `SendPreVote` | new | `PreElect` |
| `RaftCore::handle_pre_vote_request` / `Engine::handle_pre_vote_req` | absent | lease (no transfer bypass) -> last log -> `req.vote >= vote`; no mutation; reply not flush-gated | new message handling, no state change | `HandlePreVoteRequest` |
| `Notification::PreVoteResponse` / `handle_pre_vote_resp` | absent | ignore unless tracker present and leader id matches; grant -> tally -> quorum -> `elect()` (no role check); reject -> greater-log hint only | new transition into the existing election | `HandlePreVoteResponse` |
| `VoteHandler::become_following` | clears leader, candidate | also clears tracker | tracker cleared in every following transition | `HandleVoteRequest`, `HandleVoteResponse` (adopt), `HandleAppendEntries`, `RefreshServerState` |
| `establish_leader` / `become_leader` | candidate consumed | unchanged: tracker NOT cleared | tracker survives leadership | `HandleVoteResponse` win (unchanged) |
| `Engine::new` | no tracker | `pre_candidate: None` | tracker lost on restart | `Restart` |
| `spawn_parallel_vote_requests(kind)` | vote only | vote or pre-vote; `Err` not counted as a grant | transport; network errors = loss | `DropMessage` / no response |
| `RaftNetworkV2::pre_vote` default | absent | synthesized granted response | adapter behavior | excluded (transport) |
| names/metrics/docs/clap/test renames | — | — | none | excluded |

Some changed branches alter modeled state, messages, enablement, and the
existing election action's callers, so the disposition is `MODEL_CHANGE_REQUIRED`.

## Update-focused analysis (Chapter 3)

Interaction paths examined on the explicit draft:

1. *old producer -> changed Action -> old consumer*: tick on a Candidate
   (unchanged Leader-only skip) -> `pre_elect` -> responses -> `elect()`. Because
   `establish_leader` (unchanged) keeps the tracker, the Pre-Vote quorum can arrive
   after the node became Leader. `handle_pre_vote_resp` has no role check and
   `does_pre_candidate_vote_match` compares only the leader id of the tracker.
   This yields Scenario U2 and the property `TickPreVoteNeverDeposesLeader`.
2. *changed Action -> old Action*: `elect()` on a node that still holds a Leader
   object: `update_vote` -> `update_internal_server_state` -> `is_leading` -> no-op,
   so `self.leader` is kept while `vote` becomes an uncommitted self vote of a
   higher term; RaftCore's next `trigger_routine_actions -> try_leader_handler`
   hits `debug_assert!(leader.vote >= state.vote)` (engine_impl.rs:967-982). The
   same mechanism existed before only via an operator `trigger().elect()` on a
   Leader (`raft_core.rs` "TODO: reject if it is already a leader?").
3. *old context -> changed Action*: the responder's lease guard is the same as the
   real vote's except for the transfer bypass. Equal-vote and last-log checks
   match `handle_vote_req` (total order for `leader_id_adv`).
4. *changed Action -> retry*: rounds at an unchanged term share the leader id
   `(term+1, self)`; delayed grants of an earlier round are counted in a later one
   (D-5). No harmful consequence found.
5. *changed Action -> liveness*: a rejected Pre-Vote never updates the local vote.
   A node with the freshest log but a stale term can never pass Pre-Vote against
   peers with a higher (uncommitted) vote, and those peers fail its log check.
   With pre-vote enabled on all nodes nothing else raises its term (no leader, no
   real vote request). See D-2; demonstrated with an engine-level simulation of 3
   live nodes out of 5. Not model-checkable at the current granularity because
   followers never receive log entries in the model and AppendEntries rejection
   (HigherVote) is not modeled.
6. *crash/recovery*: the tracker is volatile; a restarted node ignores delayed
   responses. Covered by `Restart` and the `restart_drops_pre_round` trace.
7. *membership*: the tracker freezes the effective (joint) config; requests use
   the effective voters at dispatch (equal, since dispatch happens in the same
   RaftCore iteration). Covered by U5.

## Model repairs (independent of the source delta)

1. `LogLE` treated two absent logs with different node tags as unequal. With all
   logs empty no 3-voter election could ever succeed; the prior V0 primary
   `MC.cfg` never reaches a Leader (`spec/output/v0-vacuity-noleader.log`: the
   invariant "no Leader" holds over all 640,830 V0 states). Repaired with
   `LogEq` (None == None). Found by this run's reachability canaries.
2. Leader establishment installs the leader's own vote lease (`leaseValid' = TRUE`).
3. Timer guards: single-voter skip while a candidate exists; multi-voter tick
   only after lease expiry.
4. `ExternalCommand::Elect` does not reset `seen_greater_log`.
5. Harness: real `seen_greater_log` and real frozen candidate quorum captured.

Remaining V0 limitation (not repaired, outside the update): `SendVoteRequest`
always sends `transfer = FALSE`.

## Reproduction evidence (summary; details in `spec/bug-report.md`)

- Engine level (`openraft/src/engine/tests/specula_repro_test.rs`): D-1 and D-2
  tests fail on the updated revision; the direct-election control passes
  (`spec/output/repro-engine.log`).
- Integration level (`tests/tests/elect/t91_*`, `t92_*`): both the operator-started
  and the timer-only variants end with node 1 deposed from leadership at term t+1
  by its own stale round and RaftCore panicking
  (`spec/output/repro-integration*.log`, `spec/output/repro-integration-timer-timeline.txt`).

## Completeness review (Chapter 5) and final spec diff

Source -> model: every changed engine/RaftCore branch in the projection table maps
to a reference Action; the only unmodeled changed behaviors are transport-level
(`RaftNetworkV2::pre_vote` default grant, RPC errors = loss) and naming/metrics/docs.
Model -> source: in states with a live tracker the complete `Next` was checked for
paths the implementation cannot take; two were found and repaired (responses
crossing a restart; and, inherited, empty logs comparing unequal). The retained
abstraction that an election waits for a pending vote save is documented in
`DoElectCore`.

Final spec diff against the prior (`/work/previous/.specula-output/spec`):
- source-driven: `PreVoteSetting`, Pre-Vote tracker variables and ghost, message
  kinds, `PreClearIf`, `DoElectCore`/`DoElect`, `PreElect`, `TickPreElect`,
  `ExternalPreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`, tracker
  clearing in `HandleVoteRequest`/`HandleVoteResponse`/`HandleAppendEntries`/
  `RefreshServerState`/`Restart`, MC wrappers/counters, Trace fields/wrappers,
  `Update.tla` and cfgs;
- repairs: `LogEq`, leader lease on establishment, timer guards, external elect
  without greater-log reset, Restart purge of old-incarnation Pre-Vote exchanges.

## Findings of this run

- MC-1 (`spec/bug-report.md` Bug 1): stale timer Pre-Vote round deposes the new
  Leader; RaftCore panics in debug builds. Reproduced (engine, integration
  operator-started and timer-only).
- MC-2 (`spec/bug-report.md` Bug 2, `spec/reproduction-MC-2.md`): delayed grant from
  a node removed between same-term rounds hits `Candidate::grant_by`'s `expect`;
  RaftCore panics. Reproduced (engine leader/follower variants, integration t93).
- CR-1 (`spec/code-review-CR-1.md`): Pre-Vote term stall with a live majority.
  Reproduced end-to-end (t94) with a passing direct-election control and a passing
  old-revision engine control.
- CR-2: documentation (`docs/protocol/pre_vote.md`) contradicts the code on the
  default `pre_vote` and on `Unreachable` counting as a grant.
