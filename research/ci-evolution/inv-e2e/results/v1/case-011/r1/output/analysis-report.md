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

# V1 incremental update analysis (Pre-Vote revision)

## U.1 Exact inputs and isolation

- Old source: `/work/old-source` (changed-file snapshot) = synthetic commit
  `baseline` `1adc857f05fc8632eca18a7ce636f9c489dd5038` of
  `artifact/`; new source: `/work/new-source` = synthetic commit `update`
  `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (39 files, +1283/-80). The
  new-source snapshot is byte-identical to the artifact for the inspected
  engine files (e.g. `engine_impl.rs` sha256 prefix `32038c5fb47ca309`).
- Prior suite: `/work/previous/.specula-output` (V0, exact-old, no findings,
  `LIMITED_COVERAGE`, no unresolved trace errors reported).
- Only the supplied old/new trees, the neutral two-commit diff, the prior
  suite, and `/work` inputs were used. No history, issue, network research,
  fixed revision or oracle was consulted. Network use was limited to cargo
  fetching ordinary crate dependencies.
- Category is unchanged: **A (distributed / message passing)**. The update
  adds one RPC kind and one engine state object but does not change the
  single-mutator RaftCore/Engine architecture.

## U.2 What changed (behavioural projection)

| Changed code | Old behaviour | New behaviour | Model projection |
|---|---|---|---|
| `Engine::pre_elect` + `new_pre_candidate` (`engine_impl.rs:149-165,298-322`) | absent | Builds a pre-candidate `(term+1, self, uncommitted)` from the effective membership and last log, self-grants, elects at once on a self quorum, otherwise queues `SendPreVote`. vote/role/lease/candidate untouched. | New action `PreElect`, new state `preCandidate*`, `sendPreVotePending` |
| `RaftCore::handle_tick_election` (`raft_core.rs:1981-2035`) | Expired non-leader voter calls `elect()` | When `enable_pre_vote` (runtime `AtomicBool`) and >1 voter: `pre_elect()`; rate-limited by the in-flight round's start time; else `elect()` | `TickElect` restricted, new `TickPreElect`; `PreVoteSetting` constant; rate limit abstracted (timing) |
| `ExternalCommand::Elect{pre_vote}` (`raft_core.rs:1683-1697`, `trigger.rs:45-63`) | `Elect` always `elect()` | Caller chooses `pre_elect()` or `elect()` | New `ExternalPreElect` |
| `Command::SendPreVote` + `spawn_parallel_vote_requests(kind)` (`command.rs:138-142`, `raft_core.rs:1385-1478,2342-2344`) | absent | Spawns `pre_vote` RPCs to current effective voters; `Ok(resp)` → `Notification::PreVoteResponse{candidate_vote}`; errors/timeouts dropped (not grants) | `SendPreVoteRequest`/`FinishPreVoteBroadcast`; errors = message loss |
| `RaftMsg::RequestPreVote` → `handle_pre_vote_request` → `Engine::handle_pre_vote_req` (`raft_core.rs:1551-1562`, `engine_impl.rs:414-447`) | absent | Lease (no transfer bypass) → last-log → `req.vote >= vote`; no mutation; `Respond{when: None}` | `HandlePreVoteRequest` (pure; immediate response) |
| `Notification::PreVoteResponse` + `does_pre_candidate_vote_match` + `Engine::handle_pre_vote_resp` (`raft_core.rs:1803-1820,2066-2090`, `engine_impl.rs:516-554`) | absent | Drop unless a pre-candidate exists with the same leader id; grant → `grant_by`, quorum → `elect()`; reject → `set_greater_log` if responder log greater; never updates vote | `HandlePreVoteResponse` |
| `do_elect` clears `pre_candidate` (`engine_impl.rs:263-264`) | n/a | real election supersedes the round | `DoElect` clears pre-vote state |
| `become_following` clears `pre_candidate` (`vote_handler/mod.rs:244`) | n/a | every following transition (vote request grant, AppendEntries, rejected-vote adoption, refresh) drops the round | `PreVoteClearedIf` in `HandleVoteRequest`, `HandleVoteResponse`(adopt), `HandleAppendEntries`, `RefreshServerState`; `Restart` (new Engine) |
| `Candidate::starting_time` (`candidate.rs:93-99`) | n/a | used only by the tick rate limit | timing, abstracted |
| config/metrics/name tables/tests | n/a | `enable_pre_vote: Option<bool>` (default off), `RuntimeConfigHandle::pre_vote`, enum indices, doc page, tests switch `elect()` → `elect(false)` | config → `PreVoteSetting`; names/metrics excluded |

Unchanged but re-examined because the new state crosses them:
`establish_leader` (`engine_impl.rs:855-881`) and `become_leader`
(`vote_handler/mod.rs:166-231`) do **not** clear `pre_candidate`; `pre_elect`
does **not** clear `candidate`. Hence a Candidate can hold a live candidacy
(term T) and a pre-vote round (T+1) at once, and if the candidacy wins the
node becomes Leader while still holding the round.

## U.3 Disposition

**MODEL_CHANGE_REQUIRED.** The projected post-state sets differ for the tick
branch (with the runtime flag set a tick no longer bumps the term), new
message kinds and a new local state object exist, and `do_elect` /
`become_following` gained a side effect. The default configuration
(`enable_pre_vote = None` → off) keeps the exact-old tick behaviour, but the
flag is a public, runtime-toggleable configuration and
`trigger().elect(true)` is available regardless of it, so the new behaviour
is inside the election scope of the suite.

## U.4 Prior-model defects found and repaired (independent of the source delta)

1. **Absent-log ordering** (`base!LogLE`). V0 compared `Option<LogId>::None`
   records including a per-node `node` field, so `None` of node 2 was not
   `<=` `None` of node 1. From the 3-voter initial state no remote vote (or
   pre-vote) could ever be granted; V0 `MC.cfg` therefore never reached a
   3-voter Leader (its coverage shows `MCAppendJointConfig: 0:0`). Repaired to
   the source ordering (`log_id/mod.rs:18-61`: `None == None`). Evidence E13.
2. **Leader lease on establishment** (`base!HandleVoteResponse`). `update_vote`
   installs the leader lease for a committed vote and a zero lease for an
   uncommitted one (`vote_handler/mod.rs:126-136`); V0 left `leaseValid`
   unchanged. Exposed by the multi-event trace `candidate_pre_vote_then_leader`
   (a real candidate has a zero lease; V0's fixture used an artificial 500 ms
   lease on an uncommitted vote). Repaired.
3. **`seen_greater_log` reset** was applied to every election start; the
   source resets it only in `handle_tick_election` (`raft_core.rs:2026-2027`).
   Moved to the tick path. V0's harness serialised a constant `false`; the V1
   harness records the real flag.
4. Recorded, not repaired (outside the update): `SendVoteRequest` always sends
   `transfer = FALSE`, so the leadership-transfer lease bypass is never
   exercised in MC (V0 already listed it as uncovered); `RoleFrom`/`InConfig`
   approximate `membership.contains` (learners) by voter membership.

## U.5 Update scenarios and risk analysis

- **U-S1 Pre-vote request purity and guard order.** Producer: a remote
  `SendPreVote`; affected: `handle_pre_vote_req`; consumer: the requester's
  tally. Expectation (docs `pre_vote.md:31-38`, `raft/mod.rs:936-948`): lease
  (always honoured), last log, then vote order; nothing changes locally.
- **U-S2 Pre-vote quorum starts the real election.** `pre_elect` →
  responses → `elect()`; the election must use the probed vote
  `(term+1, self)` and the frozen pre-vote quorum.
- **U-S3 Cancellation by old context.** A granted vote request,
  AppendEntries, refresh to following, a direct election, or restart drop the
  round; delayed responses are then ignored by the runtime.
- **U-S4 Pre-vote round × leader establishment (interaction).** Tick (or a
  cautious manual trigger) fires on a **Candidate** whose candidacy is still
  live (tick skips only Leaders, `raft_core.rs:1966`). The round survives
  establishment of that candidacy (`establish_leader` keeps it). When the
  round's quorum arrives, `handle_pre_vote_resp` calls `elect()` on an
  established Leader: the vote becomes `(T+1, self, uncommitted)`, server
  state becomes Candidate, while `Engine.leader` keeps the term-T leader
  object (`update_internal_server_state` → `is_leading` → no
  `become_following`). The next `try_leader_handler()` (heartbeat, client
  write) violates its debug assertion `leader.committed_vote >= state.vote`
  (`engine_impl.rs:977-982`). Requirements against this: `pre_vote.md:3-5`
  (a round a follower runs *before* starting a real election),
  `pre_vote.md:14-20` and `trigger.rs:47-56` (Pre-Vote must not disrupt a
  healthy leader), `raft_core.rs:1964-1969` (automatic elections never start
  on a Leader). Timing premise for the tick path: the term-T vote response
  must arrive after the election timer fired but within the vote RPC timeout
  (`election_timeout_min`), i.e. vote persistence/dispatch latency must exceed
  `election_timeout - election_timeout_min`; the manual
  `trigger().elect(true)` path on a Candidate has no such constraint.
- **Reviewed and dismissed (code review):** pre-vote rounds of the same term
  share one leader id, so `does_pre_candidate_vote_match` (whose comment says
  previous-round responses "should be ignored") cannot distinguish a delayed
  grant of an earlier round at the same term. Such a grant answers the
  identical question `(T+1, self)` with a last log that can only have grown,
  and tick restarts are at least `election_timeout >= election_timeout_min =`
  RPC timeout apart, so a stale grant is no staler than a delayed in-round
  grant. Not modelled as a separate property; no finding.
- **Documentation inconsistency (not behavioural):** `pre_vote.md`
  "Backward compatibility" says the default `pre_vote` returns `Unreachable`
  and that `Unreachable` counts as a grant; the code's default synthesises a
  granted `Ok` response (`network/v2/network.rs:141-161`) and transport
  errors are explicitly *not* grants (`raft_core.rs:1376-1383,1458-1472`,
  regression test `t12_pre_vote::pre_vote_unreachable_peer_is_not_a_grant`).
  The synthesized-grant fallback (network without `pre_vote`) is excluded
  from the transport model: it is equivalent to pre-vote disabled for that
  sender.

## U.6 Exclusions

Election-timeout rate limiting of pre-vote rounds, RPC timeouts (as loss),
metrics/notification/command name tables, config parsing, serialization, and
the network default-impl fallback remain outside the model; their effect on
modeled state is either timing (abstracted to nondeterminism) or loss.
