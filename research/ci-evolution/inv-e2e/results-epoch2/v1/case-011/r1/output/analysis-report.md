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

# Incremental analysis — Pre-Vote revision (case-011)

## Inputs and isolation

* Old: `/work/old-source` (changed-file snapshot) = `artifact` commit `1adc857`
  ("baseline"); new: `/work/new-source` = `artifact` commit `3ab6cdd`
  ("update"); prior suite `/work/previous/.specula-output` (V0, immutable).
* Evidence came only from these trees, the prior suite, `/work/model-scope.md`,
  `/work/case.json` and the in-tree tests/docs. No history, network research,
  issues or other revisions were consulted. Build dependencies were fetched by
  cargo only.
* The V0 validation summary reported `LIMITED_COVERAGE` with fully consumed
  single-event traces and no findings; its conclusions are treated as
  provisional evidence within those bounds.

## Changed mechanism

The diff (39 files, +1283/−80) adds an optional Pre-Vote round:

1. **Tick** (`core/raft_core.rs:1958-2036`). For a non-leader voter whose vote
   lease plus election timeout expired: if `enable_pre_vote` and more than one
   voter, skip while a fresh pre-candidate round is younger than the election
   timeout, otherwise `reset_greater_log()` and `Engine::pre_elect()`;
   otherwise `Engine::elect()` as before.
2. **`Engine::pre_elect`** (`engine/engine_impl.rs:297-322`). Builds a
   `pre_candidate` (`Candidate` with the effective membership frozen, last log,
   vote `(term+1, self, uncommitted)`), self-grants; a self-quorum (single
   voter) calls `elect()`; otherwise queues `SendPreVote`. Vote, role and
   persistence are untouched.
3. **`SendPreVote`** dispatch (`raft_core.rs:1385-1478,2342-2344`): one RPC per
   other effective voter, no preceding `SaveVote`; transport errors and
   timeouts are dropped (never a grant); responses become
   `Notification::PreVoteResponse { target, resp, candidate_vote }`.
4. **Responder** `Engine::handle_pre_vote_req` (`engine_impl.rs:414-447`):
   reject under an unexpired committed lease (no transfer bypass), reject a
   smaller last log, otherwise `granted = req.vote >= local vote`; never
   mutates state; the runtime replies at once (`raft_core.rs:1551-1562`).
5. **Requester** (`raft_core.rs:1803-1820,2066-2090`; `engine_impl.rs:516-554`):
   the runtime forwards a response only if a pre-candidate exists and its
   leader id equals the response's `candidate_vote`. A grant is tallied; a
   quorum calls `elect()` (term = *current* vote term + 1). A rejection only
   records a greater log; **the responder's vote is never adopted**.
6. **Clearing**: `do_elect` clears `pre_candidate` (`engine_impl.rs:262-264`),
   `become_following` clears it (`vote_handler/mod.rs:242-244`).
   `become_leader` (reached from `establish_leader` and leader restore) and the
   "leading" branch of `update_internal_server_state` do not.
7. Operator API `trigger().elect(pre_vote)` (`raft/trigger.rs:61-63`,
   `raft_core.rs:1683-1696`), runtime toggle `runtime_config().pre_vote(bool)`.

The old real-election path (`do_elect`, `handle_vote_req`, `handle_vote_resp`,
`establish_leader`) is unchanged except the added clearing line.

## Interaction analysis (Chapter 3)

* **Producer → affected → consumer.** A Pre-Vote quorum reaches the unchanged
  persistence and SendVote path through `elect()`. Because `elect()` uses the
  current term, the model checks that an active round always probes
  `vote.term + 1` (`PreCandidateProbesNextTerm`).
* **Higher votes are invisible to Pre-Vote.** Neither side of a Pre-Vote updates
  a vote. In the old code a rejected *real* vote response makes the candidate
  adopt the higher vote (`engine_impl.rs:485-509`), which is how a lagging-term
  node with the most up-to-date log catches up and wins later. With Pre-Vote
  enabled that node never starts a real election (it cannot gather a
  Pre-Vote quorum because peers with higher votes reject it), and the peers
  with higher votes but shorter logs are rejected by its log check. Nothing
  else changes either side's vote while no leader exists → candidate
  liveness defect (Scenario U-S2).
* **Rounds outlive role changes that keep the vote "mine".** A Candidate's tick
  runs `pre_elect` while its real election is still open. If that election then
  succeeds, `establish_leader` → `become_leader` keeps `pre_candidate`; a later
  quorum of (already sent) Pre-Vote grants calls `elect()` on the new Leader
  (Scenario U-S3). The runtime correlation (`does_pre_candidate_vote_match`)
  only compares leader ids, so it does not filter this.
* **Old consumers cancel rounds** via `become_following` (AppendEntries from the
  current leader, granting a vote request, adopting a higher vote response,
  refresh to follower/learner) — covered by traces U-T5/U-T6.
* **Guards read old state:** the responder's lease (installed by
  AppendEntries and by leader establishment) and its last log (extended by
  AppendEntries). V0 did not model either correctly (R-1, R-4).

## Repairs of inherited V0 abstractions (needed by the update)

| Id | V0 defect | Source evidence | Why update-relevant |
|---|---|---|---|
| R-1 | follower last log never advanced by AppendEntries | `engine_impl.rs:586-602`, `following_handler/mod.rs:64-125` | Pre-Vote's log guard is the main reason a peer rejects; without replication no follower can be ahead |
| R-2 | a log append could become durable before the SaveVote queued ahead of it | `raft_core.rs:2265-2305` (FIFO; `save_vote` awaited) | prevents spurious "durable log, older durable vote" restarts that would fabricate low-term/long-log nodes |
| R-3 | tick could fire while the committed vote's lease was valid | `raft_core.rs:1996-2007`, `utime.rs:148-152` | the tick is the producer of `PreElect` |
| R-4 | establishment did not install the leader's own lease | `vote_handler/mod.rs:121-135` (found by trace U-T4) | a leader's lease gates both Pre-Vote and vote grants |

## Decision

`MODEL_CHANGE_REQUIRED`. Artifacts: `spec/base.tla`, `MC.tla`, `Trace.tla`,
`Update.tla` and cfgs; `instrumentation-spec.md`; `brief-coverage.md`;
`spec/changelog.md`; `spec/invariant-evidence.json`.

## Outcome (model checking)

Two update-introduced findings, both from actual TLC counterexamples and both
observed per node on the real Engine (details: `spec/bug-report.md`,
`spec/findings.json`):

* **MC-1 (High)** Pre-Vote livelock — Scenario U-S2 confirmed: a live voter
  majority stays leaderless forever (closure checked exhaustively from the
  witness); the pre-update tick recovers from the same state.
* **MC-2 (Medium)** stale Pre-Vote round demotes a newly established leader —
  Scenario U-S3 confirmed (no faults needed; also over the full `MCNext`).

No reference safety invariant was violated; coverage is bounded
(`LIMITED_COVERAGE`).
