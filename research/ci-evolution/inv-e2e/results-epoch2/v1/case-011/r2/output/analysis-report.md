# Source analysis report (exact-old prior + Pre-Vote update)

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

## U. Update analysis (`baseline` 1adc857 -> `update` 3ab6cdd)

### U.1 Isolation

Only `/work/old-source`, `/work/new-source`, the artifact's two neutral commits, the prior suite,
`/work/model-scope.md`, `/work/case.json` and `/work/input-manifest.json` were used. No history beyond
the two synthetic commits, no issue trackers, no network research. The test comment in
`tests/tests/elect/t12_pre_vote.rs` that names an upstream issue number was not followed.

### U.2 Changed files and their projection onto the model vocabulary

| File | Change | Model projection |
|---|---|---|
| `engine/engine_impl.rs` | new `pre_candidate` field; `new_pre_candidate`, `pre_elect`, `handle_pre_vote_req`, `handle_pre_vote_resp`; `do_elect` clears the round; `vote_handler()` passes the field | **changed**: new state, new Actions, changed `StartElection` effect (`DoElect`) |
| `engine/handler/vote_handler/mod.rs` | `become_following` clears `pre_candidate` | **changed** effects of `HandleVoteRequest` (follow), `HandleVoteResponse` (adopt), `HandleAppendEntries`, `RefreshServerState`; `become_leader` (establishment) does *not* clear it |
| `core/raft_core.rs` | tick: Pre-Vote branch + in-flight rate limit; `ExternalCommand::Elect{pre_vote}`; `RequestPreVote` handler replies with `when: None`; `PreVoteResponse` notification filtered by `does_pre_candidate_vote_match`; `spawn_parallel_vote_requests(kind)`; transport `Err` never a grant | **changed**: `TickElect` guard, new `TickPreElect`/`ExternalPreElect`, request emission atomic with `pre_elect`, correlation key in the response message, loss = `DropMessage` |
| `engine/command.rs`, `command_name.rs` | `SendPreVote` command (network kind, no I/O wait) | captured by atomic request emission; names/indices excluded |
| `core/notification.rs`, `notification_name.rs`, `raft_msg/*.rs` | new notification/message variants, name tables | covered by the message kinds; renumbering excluded (no protocol effect) |
| `proposer/candidate.rs` | `starting_time()` accessor (rate limit) | time abstracted |
| `network/v2/network.rs`, `network/vote_trait.rs` | `pre_vote` RPC; default implementation returns `Ok(granted)` | environment; default-grant networks are outside the bounded model (documented limit) |
| `config/config.rs`, `config_clap_test.rs`, `runtime_config.rs`, `raft/runtime_config_handle.rs` | `enable_pre_vote` option (default off) and runtime toggle | `TickPreVoteModes` |
| `raft/mod.rs`, `raft/api/protocol.rs`, `raft/trigger.rs` | `Raft::pre_vote()` entry; `Trigger::elect(pre_vote)` | `HandlePreVoteRequest`, `ExternalPreElect`/`ExternalElect` |
| `docs/protocol/*.md`, `pre_vote.md` | design text | requirement evidence; D-U2 doc mismatch |
| `engine/mod.rs`, three new engine tests, `tests/tests/**` | new tests; `elect()` call sites changed to `elect(false)` | requirement/test evidence; `elect(false)` is the unchanged `ExternalElect` |

`NO_MODEL_CHANGE` is impossible: the Pre-Vote branches add post-states with a new message kind and new
round state, and old Actions (`StartElection`, the follow paths) acquire a new effect on that state.
With the flag off and no `elect(true)` trigger, the projected behavior equals the old model's: the tick
calls `elect()` exactly as before, and no pre-candidate ever exists (`TickPreVoteModes = {FALSE}` plus a
zero Pre-Vote counter reduces the new model to the old one).

### U.3 Interaction analysis (Chapter 3)

- **Producers of the round**: tick (non-Leader, multi-voter, expired vote, flag on) and `elect(true)`
  (any voter, any role). A *Candidate* is not skipped by the tick (`raft_core.rs:1966-1969` skips only
  `ServerState::Leader`), so a round can start while its own real election at term T is still in
  flight; the round's vote is `(T+1, self)`.
- **Consumers that end the round**: `do_elect` (any real election), `become_following` (any accepted
  vote of another leader, including equal-vote heartbeats, adopted higher votes from vote responses,
  and `refresh_server_state` for a non-leading node), engine reconstruction on restart.
- **Consumer that does not end it**: `establish_leader` (`engine_impl.rs:855-881`) consumes only
  `self.candidate`; its `update_vote(committed)` reaches `become_leader`, which does not touch
  `pre_candidate`. The tick no longer runs for the Leader, but the response path does:
  `Notification::PreVoteResponse` is processed whenever `pre_candidate.is_some()` and the leader id
  matches (`raft_core.rs:1803-1820`), and `handle_pre_vote_resp` calls `elect()` on a quorum with no
  role check (`engine_impl.rs:534-539`).
- **Grants available after establishment**: a peer that granted the term-T real vote holds an
  uncommitted vote `(T, self)` with no lease, so it grants the `(T+1, self)` Pre-Vote until the new
  Leader's first AppendEntries installs the lease (`handle_pre_vote_req`, `engine_impl.rs:425-446`).
  A peer whose vote save is slow answers the queued Pre-Vote after its delayed real-vote reply.
- **Effect**: `do_elect` on the Leader bumps to `(T+1, self, uncommitted)`, persists it, sends
  RequestVote, and changes server state to Candidate (the Leader object is left in place, as with the
  pre-existing `elect(false)` on a leader). Peers that already accepted the term-T leader's
  AppendEntries reject the term-T+1 vote under the lease; others grant it and leadership moves to a new
  term. Either way the cluster loses its fresh leader and the term climbs without any failure — the
  outcome the Pre-Vote documentation says the feature prevents. Election safety is unaffected.
- **Round identity (found in the Chapter 5 reread)**: rounds started from the same local vote share the
  runtime correlation key (leader id `(term+1, self)`), but each freezes its own voter set, and the
  progress tracker contains voters only. A delayed grant for an earlier round from a node that is no longer
  a voter therefore reaches `Candidate::grant_by`'s `expect("target not in quorum set")`
  (`proposer/candidate.rs:106-107`) and panics the RaftCore task. The runtime comment says such stale
  responses "should be ignored" (`raft_core.rs:2066`). The first draft modeled the grant as a silent no-op
  for non-members; the reference now models the panic (`HandlePreVoteResponseNonMember`).
- **Fault boundaries**: crash/restart drops the round (no persistence), drop/delay of Pre-Vote messages
  only affects progress; the query never waits for vote I/O (`raft_core.rs:1551-1562`).
- **Same mechanism at every call site**: the clear-on-follow edit is in the shared `become_following`,
  so all follow paths are covered; the leader paths (`establish_leader`, `become_leader`, startup leader
  restore) are the only self-led transitions and none clears the round.

### U.4 Model repairs of the prior abstraction (separate from the source delta)

- `HandleVoteResponse` leader establishment now sets `leaseValid := TRUE` and the adopt branch sets it
  `FALSE`. Source: `update_vote` installs `config.leader_lease` for a committed vote and a zero lease
  for an uncommitted one (`vote_handler/mod.rs:119-139`). The V0 fixture started from a valid lease and
  masked this; the new interaction trace starts from an expired candidate lease and is rejected
  without the repair (`spec/evidence/repair-lease/summary.txt`). The behavior is unchanged by the
  update; the repair is required to validate the update interaction.
- Harness capture: `candidate_config` is now read from the candidate's real frozen quorum set and
  `seen_greater_log` from `Engine::is_there_greater_log()` instead of the V0 approximations.

- `HandlePreVoteResponse` repair within this run (update semantics, not a V0 defect): a granted response
  from outside the round's frozen voters now stops the node (RaftCore panic) instead of being counted or
  ignored; the earlier draft did not follow `grant_by`'s `expect`.
- `EnvUpdate` rely revisions (open checking only): v2 requires monotone log growth; v3 restricts config
  changes to an active leader with a committed self vote — both are the real guards of the omitted actions
  and are discharged by `Update_discharge*.cfg`.

### U.5 Intentional abstractions retained

- `TickElect` keeps the V0 over-approximation (no expired-lease guard); `TickPreElect` requires it.
- Persistence-blocking of the core loop during `save_vote().await` is modeled only for the request and
  election-start handlers (as in V0); Pre-Vote response handling is admitted during a pending save,
  which over-approximates.
- Two rounds started from the same local vote share a correlation key, so a delayed response from the
  earlier round is accepted by the later one. With an unchanged voter set this only counts an older
  grant (accepted design); with a changed voter set it panics (D-U3, Scenario U-5).
- Followers' membership is not replicated in the model (V0 abstraction): only a leader's own
  `AppendJoint/AppendUniform` change a node's configuration, so the follower variant of U-5 is covered by
  the integration reproduction, and the model covers the leader variant.
- `StartTransferElection` does not propagate the transfer bit into vote requests (V0 abstraction, listed as
  uncovered by the V0 report); it adds no states beyond `ExternalElect`. Independent of this update; not
  repaired here.
