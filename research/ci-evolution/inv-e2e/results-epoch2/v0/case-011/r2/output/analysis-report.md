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

# §U. Incremental update analysis — Pre-Vote revision (run incr-b919e9f909ea)

## U.0 Inputs and isolation

- Old: `/work/old-source` (changed-file snapshot) and prior suite `/work/previous/.specular-output` (V0, baseline commit recorded as `b41ce98…` in its validation summary).
- New: `artifact/` (two neutral synthetic commits `baseline`→`update`, HEAD `3ab6cdd`), 39 changed files (`/work/case.json`).
- Only the supplied old/new sources and the synthetic diff were analysed. No history, network research, or other revision was used. Build dependencies were fetched by cargo only.
- Toolchain: the requested `nightly-2026-03-01` is now installed and was used (the prior had to substitute `nightly-2025-12-31`).

## U.1 Changed mechanism (source evidence)

The update adds an optional **Pre-Vote** round before a real election:

| Change | Evidence (new tree) |
|---|---|
| New proposer state `Engine::pre_candidate` (a `Candidate` quorum tracker for the hypothetical next-term vote) | `openraft/src/engine/engine_impl.rs` (`pre_candidate` field, `new_pre_candidate`) |
| `Engine::pre_elect`: vote `(term+1, self, uncommitted)`, snapshot effective membership + last log, self-grant; single voter → `elect()` at once; else queue `Command::SendPreVote`. No vote/role/candidate/leader change. | `engine_impl.rs: pre_elect` |
| `Engine::handle_pre_vote_req`: lease check (never bypassed), last-log check, grant = `req.vote >= local vote`; no state change, no command | `engine_impl.rs: handle_pre_vote_req` |
| `RaftCore::handle_pre_vote_request`: reply with `Respond { when: None }` (no I/O wait) | `core/raft_core.rs` |
| `Engine::handle_pre_vote_resp`: ignore if no pre-candidate; granted → `grant_by`, quorum → `elect()`; rejected with greater log → `set_greater_log()`; never updates vote; **no role/leader/candidate check** | `engine_impl.rs: handle_pre_vote_resp` |
| Runtime gate: `Notification::PreVoteResponse` forwarded only while a pre-candidate exists whose leader id equals the request's | `raft_core.rs: does_pre_candidate_vote_match` |
| `do_elect` clears `pre_candidate`; `VoteHandler::become_following` clears it | `engine_impl.rs: do_elect`; `engine/handler/vote_handler/mod.rs` |
| Tick: Leader/non-voter/disabled skip unchanged; multi-voter requires `local_vote.is_expired(now, election_timeout)`; then `pre_vote = enable_pre_vote && voter_count > 1` → `pre_elect()` (skip if a fresh round started < election_timeout ago) else `elect()` | `raft_core.rs: handle_tick_election` |
| `ExternalCommand::Elect { pre_vote }` / `trigger().elect(pre_vote)`: only a voter check | `raft_core.rs`, `raft/trigger.rs` |
| Runtime flag `RuntimeConfig::enable_pre_vote` (toggleable), config `enable_pre_vote: Option<bool>` default off | `config/*.rs`, `raft/runtime_config_handle.rs` |
| Network `pre_vote` RPC (default impl synthesizes a grant); transport errors are not grants | `network/v2/network.rs`, `network/vote_trait.rs`, `raft_core.rs: spawn_parallel_vote_requests` |
| Metrics/name enums, docs, tests | `notification_name.rs`, `raft_msg_name.rs`, `docs/protocol/pre_vote.md`, tests |

Not model-relevant (projected post-states unchanged): metrics/name enums, `RaftMsgName` index shifts, `Display`/tracing, clap parsing, test-only renames `elect()`→`elect(false)`, election-timeout computation hoisted before the voter-count branch (same values).

Documentation inconsistency (no model effect): `docs/protocol/pre_vote.md` says an `Unreachable` Pre-Vote response counts as a grant, while `spawn_parallel_vote_requests` and the new test `pre_vote_unreachable_peer_is_not_a_grant` treat every transport error as a non-grant. Recorded as code-review information only.

## U.2 Disposition: `MODEL_CHANGE_REQUIRED`

The update adds new protocol messages (Pre-Vote request/response), new per-node state (`pre_candidate`), a new election entry point, changes the enablement of an existing Action (the timer no longer calls `elect()` directly when Pre-Vote is on and there are >1 voters), and changes effects of existing Actions (`do_elect`, `become_following`, restart clear the pre-candidate). Projection onto the old vocabulary is not equal: e.g. a Candidate whose election timed out no longer replaces its candidacy with a new term but keeps it while probing.

Granularity: same as V0 (engine-event atomicity; persistence and dispatch staged; asynchronous message set with drop/reorder). Pre-Vote dispatch is atomic with `pre_elect` (no persistence precedes it; crash before dispatch ≡ crash after dispatch + undelivered messages, both ignored after restart since `pre_candidate` is in-memory only).

## U.3 Update Scenarios

- **U1 — Pre-Vote round start / side-effect freedom.** `TickPreElect`/`ExternalPreElect` → `PreElect`; peers' `HandlePreVoteRequest`. Expectation (doc + code): no vote/role/lease/persistence change on either side. Single-voter: immediate `elect()`.
- **U2 — Pre-Vote grant rule and lease.** Responder rejects under a live committed lease (no transfer bypass), on a stale candidate log, or when `req.vote < local vote`. Grant is computed exactly like the real vote rule but without side effects.
- **U3 — Pre-Vote round × running election × leader establishment (old producer → affected → old consumer).** A Candidate whose election timer expires (the tick only skips `ServerState::Leader`) starts a Pre-Vote round while the real candidacy stays alive. `handle_vote_resp` can still win the old term (`establish_leader` consumes only `candidate`, not `pre_candidate`). A delayed granted Pre-Vote response is then forwarded by the runtime gate (same leader id) and `handle_pre_vote_resp` calls `elect()` on the established Leader. `do_elect` does not clear `leader` (update_internal_server_state takes the `is_leading` branch), so the engine holds a Leader object at `(T, self, committed)` while `state.vote = (T+1, self, uncommitted)`. Consumer: `Engine::try_leader_handler` asserts `leader.committed_vote >= state.vote` (debug), the timer path promises never to elect on a Leader, and the Pre-Vote doc promises that a healthy leader is not disrupted. Property: `Update!LeaderVoteCoversLocalVote`.
- **U4 — Cancellation by old consumers.** Granting another candidate's vote, accepting AppendEntries from another leader, role refresh to follower, and restart clear the pre-candidate (`become_following`, `Engine::new`). Stale responses are dropped by the runtime gate.
- **U5 — Membership change during a Pre-Vote round.** Frozen pre-candidate config vs. later effective-config changes; covered by the open spec's `EnvUpdate` (membership evolution on any node).
- **U6 — Runtime toggle.** `PreVoteSetting = {FALSE, TRUE}` gives the union of both tick branches.

## U.4 Prior-model defects found and repaired (source unchanged; recorded separately)

1. `LogLE` treated two absent logs (`NoLog(i)`, `NoLog(j)`) as incomparable; Rust `Option::None == None`. Consequence in the prior suite: no vote between nodes with empty logs could be granted, so multi-voter elections from the initial state were unreachable in `MC.cfg` (the prior's multi-voter leadership properties were largely vacuous). Found by update reachability canaries. Repaired in `base.tla`.
2. `HandleVoteResponse` left `leaseValid` unchanged on establishment; `update_vote` with a committed vote installs the leader lease (and a zero lease when adopting a stripped higher vote). Masked in the prior trace by a fixture that pre-set a lease. Found by the fresh interaction trace. Repaired in `base.tla`.
3. `seen_greater_log` was hard-coded `false` in the prior harness; now emitted from `Engine::is_there_greater_log()`.

Both model repairs widen/realign reachable behavior; the prior's MC state counts are therefore not comparable with the new runs.

## U.5 Exclusions (unchanged scope rationale)

Metrics, precise timeout values and the in-flight-round restart timer, transport framing, serialization, RPC error kinds (only grant/non-grant matters; transport errors are non-grants ≡ dropped responses), application payloads. The default `pre_vote` network implementation (synthesized grant) is outside the modeled network (it is equivalent to a peer that always grants, i.e. Pre-Vote disabled from the requester's viewpoint).
