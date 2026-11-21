# Specula modeling brief — incremental update (Openraft Engine/RaftCore, leader transfer)

Revision under verification: `update` d7176ef (artifact). Prior: V0 brief for `baseline`
d86101c, retained below as the base brief; this section supersedes it where they differ.

## 0. Update summary

The update adds `Raft::transfer_leader` (`raft/mod.rs:635-703`) and the RaftCore message
`RaftMsg::TransferLeader{from, to}` (`core/raft_msg/mod.rs:98-107`). Its handler
(`core/raft_core.rs:1190-1202`) acts only when the local vote equals `from`: it disables the
lease of that vote (`Leased::disable_lease`, `utime.rs:133-138`) and, if the node is `to`,
calls `Engine::elect()` directly. The lease now carries `lease_enabled`; `touch()` no longer
extends a disabled lease and any `update()` re-enables it (`utime.rs:126-161`).

Disposition: `MODEL_CHANGE_REQUIRED` (see `analysis-report.md`).

## 1b. Model granularity for the update

- TransferLeader is one atomic RaftCore step (`base!TransferLeader`), with its ignored
  branch (`TransferLeaderIgnored`) for vote mismatch; the target branch reuses the exact
  `Engine::elect` body (`base!ElectCore`), including the membership-containment branch.
- The lease is modeled by `leaseEnabled` only; lease *time* stays abstract (a committed vote
  with an enabled lease may or may not reject a vote request; a disabled lease never rejects).
- RaftCore notification order matters for the update: the self vote response is queued
  before remote responses (R8 `selfRespPending`).
- `Candidate::grant_by` for a target outside the candidate quorum set is modeled as a RaftCore
  panic (R3 `panicked`), not silently accepted.

## 2b. Update Scenarios

### U-S1 — transfer to a non-voter (learner) target
Producer: a learner holds the leader's committed vote after replication
(`engine_impl.rs:447-461`). Changed action: TransferLeader with `to = learner` calls `elect()`
(no `is_voter` guard, unlike `raft_core.rs:1207-1213,1452-1455`). Consumers: SaveVote → self
VoteResponse → `Candidate::grant_by(self)` (`candidate.rs:90-96`, progress holds voters only);
SendVote → voters (leases disabled by the same API call) grant; old leader accepts the higher
vote and steps down. Uncertainty: does the learner panic or win? Expected per documentation:
"a learner does not try to elect itself" (`docs/data/vote.md:50-51`).
Model: `MCTransfer`, `MCPersistVote`, `MCVoteResponse`, `MCSendVote`, `MCVoteRequest`.
Properties: U1 `ElectOnlyByVoter`, U2 `NoCorePanic`, U5 `ElectedLeaderWasVoter`.
Trace: `core-learner-*` (real `t14_specula_transfer_to_learner`).

### U-S2 — lease disable, touch, update
Changed action disables the lease of the current vote; same-vote AppendEntries/heartbeats call
`touch()` which must keep it disabled; any vote change (`update()`) re-enables it.
Consumer: vote-request lease check (`engine_impl.rs:305-315`). Properties: U3
`LeaseReenabledOnVoteChange`, U4 `DisabledLeaseOnlyByTransfer`. Traces: `lease-touch`,
`core-t14-n1-c0` (disable then accept), `core-t14-n0-c1` (non-transferred leader still
rejects by lease).

### U-S3 — intended voter transfer and safety across it
Target voter elects at `last_seen.term + 1`; voters with disabled leases grant; the old leader
accepts the higher vote and steps down; the new leader appends its blank and commits.
Properties: U6 `TransferSafety` = `CommittedLogAgreement` ∧ `LeaderCompleteness` ∧
`CandidateGrantSound`. Hunt: `MC_hunt_transfer_voter.cfg`. Trace: `core-t14-*`.

### U-S4 — transfer across membership changes
Removed (absent) target runs `elect()` but `become_following` clears the candidate
(`vote_handler/mod.rs:234-244`); its RequestVote still reaches voters. Leader transferring to
itself becomes leader+candidate (pre-existing coexistence). Hunt:
`MC_hunt_transfer_membership.cfg`; canary `CanaryAbsentElect`.

### U-S5 — crash/restart around a transfer
A fresh `RaftState` re-enables the lease; startup restores leadership only when the node is
contained in membership (`raft_state/mod.rs:369-383`, repair R4). Covered by `MCCrash`/
`MCRestart` in every campaign.

## 5b. Update invariants and properties

`NoCorePanic`, `ElectedLeaderWasVoter`, `LeaderVoteNotSuperseded` (U7, model form of the
`Engine::leader_handler` assertion `leader.committed_vote >= state.vote`, added after the
Chapter 5 reread of the leader-target branch of U-S4) (invariants); `ElectOnlyByVoter`,
`LeaseReenabledOnVoteChange`, `DisabledLeaseOnlyByTransfer` (action properties); new reference
invariant `LeaderCompleteness`. Placement and cfg enablement: `spec/brief-coverage.md`.

## 6b. Code-review-only items for the update

- `transfer_leader` waits for `metrics.vote == from` (flushed vote) and compares only log
  *indexes* with `flushed_log`; on timeout it forwards anyway (`raft/mod.rs:661-701`). Timing
  only; the handler re-checks the in-memory vote. Liveness, not modeled.
- A failed transfer leaves follower leases disabled until the vote changes, so heartbeats of the
  still-alive leader no longer protect it from disruptive candidates (`utime.rs:150-161`).
  Liveness/availability only; the model's lease abstraction already admits every acceptance.
- A transfer whose target is the current leader makes it leader+candidate; the same state is
  reachable before the update via `trigger().elect()` (`raft_core.rs:1207-1213`, "TODO: reject
  if it is already a leader?"). Model checking (U7) and real probes show the leader's RaftCore
  then panics on the `leader_handler` debug assertion: finding MC-2, pre-existing, with a new
  trigger added by the update. Release-mode behavior of appends during that window is
  code-review-only and unverified.

---

# Appendix: V0 modeling brief (exact-old baseline)

# Specula V0 modeling brief: Openraft Engine/Core consensus boundary

Baseline: neutral commit `955ebf13f9c4acf88240775db2b51832c9cbb6a9` in `/work/source`.
This brief is derived only from the immutable exact-old source and the binding scope. No
upstream history, issue material, later revision, or incident hypothesis was used.

## 1. System overview and component map

The bounded subsystem is a Category A crash-fault, message-passing Raft implementation.
`Engine` is a synchronous in-memory state machine: one input updates its shadow `RaftState`
and enqueues FIFO commands (`openraft/src/engine/mod.rs:1-20`,
`openraft/src/engine/engine_output.rs:6-44`). `RaftCore` is the asynchronous adapter. It
drains those commands until a condition blocks, and delegates persistence, RPC, replication,
and state-machine work (`openraft/src/core/raft_core.rs:852-888`, `:1567-1758`). The model
therefore makes an Engine action atomic but separates accepted, submitted, flushed, saved,
sent, committed, and applied effects.

Per node, the modeled state is:

- total-order vote `(term,node,committed)`, greatest seen vote, explicit role, candidate
  snapshot/granters, and established leader state (`openraft/src/vote/vote.rs:21-41`,
  `openraft/src/vote/leader_id/leader_id_adv.rs:14-22`,
  `openraft/src/engine/engine_impl.rs:68-104`);
- logical and durable logs, commit/applied positions, and accepted/submitted/flushed I/O
  (`openraft/src/raft_state/mod.rs:45-85`,
  `openraft/src/raft_state/io_state.rs:15-55`);
- committed and effective membership, including uniform/joint voter sets and learners
  (`openraft/src/raft_state/membership_state/mod.rs:20-41`,
  `openraft/src/membership/membership.rs:16-34`);
- leader-to-peer matching positions, a membership-scoped session, and delayed protocol
  messages (`openraft/src/proposer/leader.rs:18-61`,
  `openraft/src/core/raft_core.rs:1539-1557`).

Payload bytes, metrics, wall-clock timing, framing/serialization, snapshots, log purging,
client retry semantics, read-index optimization, and transport implementation are outside the
model. They do not change the scoped election, replication, membership, or durability rules.

## 2. Neutral scenarios

### S1 — persisted election and delayed responses

1. A current voter starts an election with `last_seen.term + 1` and snapshots its last log,
   effective quorum, and learners (`openraft/src/engine/engine_impl.rs:122-140`, `:221-249`).
2. Its vote changes in memory and `SaveVote` precedes `SendVote`; the local grant is delivered
   only after the save completes (`openraft/src/core/raft_core.rs:1625-1681`).
3. Only replies carrying the exact candidate vote count. A strict uniform majority, or a
   majority in every child of a joint config, establishes leadership
   (`openraft/src/engine/engine_impl.rs:347-401`,
   `openraft/src/quorum/quorum_set_impl.rs:11-23`, `openraft/src/quorum/joint.rs:56-63`).
4. Establishment commits the vote, rebuilds streams, persists the committed vote, and appends a
   blank entry (`openraft/src/engine/engine_impl.rs:642-669`).

### S2 — vote request log freshness and lease rejection

A committed unexpired leader lease rejects first. Otherwise a candidate log must be at least the
local last log under full `LogId` ordering; then a nondecreasing vote is accepted and saved
(`openraft/src/engine/engine_impl.rs:293-343`). A greater seen reply may advance
`last_seen_vote` without changing the locally granted vote (`:347-401`).

### S3 — follower append, conflict, flush-gated success, and commit cap

A follower first accepts the leader vote, requires an exact previous log, truncates a conflicting
suffix, and accepts a consecutive suffix (`openraft/src/engine/engine_impl.rs:408-477`,
`openraft/src/engine/handler/following_handler/mod.rs:58-157`). A successful RPC response is
conditioned on the accepted I/O being flushed (`openraft/src/engine/engine_impl.rs:431-439`).
Follower commit is monotone and capped at its locally accepted log (`following_handler/mod.rs:159-188`).

### S4 — partial replication and leader commit

Each peer has one in-flight request and a monotone matching prefix. A partial success can advance
only part of the sent range and continue the same request (`openraft/src/progress/entry/mod.rs:78-103`,
`openraft/src/engine/handler/replication_handler/mod.rs:121-146`). Only voters contribute to the
effective uniform/joint quorum. The leader advances commit only to a quorum-granted entry owned
by its current leader identity, then queues propagation, durable commit, and apply
(`replication_handler/mod.rs:186-248`).

### S5 — learner addition and voter replacement

Learner-only changes alter node metadata but not voter configs. Voter replacement advances
coherently `C1 -> {C1,C2} -> C2`; each membership log becomes effective as soon as it is accepted,
before durability or commitment (`openraft/src/membership/membership.rs:233-339`,
`openraft/src/quorum/coherent_impl.rs:62`,
`openraft/src/engine/handler/leader_handler/mod.rs:50-93`). A new membership is rejected while the
previous effective membership is not committed
(`openraft/src/raft_state/membership_state/change_handler.rs:42-58`).

### S6 — membership rollback and stale replication session

Follower conflict truncation can revert an uncommitted effective membership to the committed one
(`openraft/src/raft_state/membership_state/mod.rs:153-187`). A response can alter leader progress
only when both vote and effective-membership log ID match its stream session
(`openraft/src/core/raft_core.rs:1539-1557`).

### S7 — crash/restart windows

Crash loses Engine/Core volatile state, queued but unexecuted commands, candidates, leader
progress, and notifications. Completed storage and state-machine effects survive. Restart reads
vote, committed position, log bounds, applied state, and recent membership entries, then creates a
fresh Engine and calls `startup()` (`openraft/src/storage/helper.rs:59-91`, `:173-217`,
`openraft/src/raft/mod.rs:268-273`, `openraft/src/core/raft_core.rs:255-258`). A durable committed
self-vote can restore leadership; an accepted but unflushed membership disappears.

## 3. What the model checks

The base model contains explicit actions for election, vote persistence/request/response,
leader establishment, client and membership append, log submit/flush, append delivery/response,
partial match advance, commit persistence/apply, crash, and restart. Delayed messages may be
dropped. It models a finite server set, bounded terms and log length, but no privileged schedule.

The following code-faithful properties are model checked:

- type/domain preservation and I/O order `durable <= flushed <= submitted <= accepted <= log`;
- vote and commit monotonicity through the action guards;
- a candidate becomes leader only after exact-vote grants satisfy its snapshotted quorum;
- learners never contribute to an election or replication quorum;
- joint quorum requires a strict majority in every child;
- leader commit does not exceed local accepted log and is restricted to a current-leader entry;
- committed membership never follows effective membership and at most one uncommitted membership
  is proposed locally;
- successful append response is possible only after the covered log is flushed;
- stale membership-session responses do not change progress;
- restart reconstructs volatile state only from modeled durable state.

The model does **not** claim linearizability of application payloads, network delivery liveness,
wall-clock lease accuracy, snapshot correctness, or behavior outside the stated subsystem.

## 4. Extension points

- Increase `Server`, `MaxTerm`, `MaxIndex`, and action counters in `MC.cfg`.
- Add snapshot/purge variables if snapshot transfer becomes part of a later scope.
- Refine storage failures into explicit error outcomes rather than crash-before/crash-after
  completion.
- Add fairness only for a separately stated liveness campaign; none is assumed here.
- Extend trace capture to RaftCore workers to validate real storage/RPC callbacks in addition to
  the present real Engine handler boundaries.

## 5. Invariants

`TypeOK`, `IOOrder`, `CommitWithinAccepted`, `MembershipOrder`, `MembershipWellFormed`,
`LearnersExcluded`, `CandidateGrantSound`, `LeaderVoteCommitted`, `MatchWithinLeaderLog`,
`DurableStateBounded`, and `CurrentTermCommit` are defined in `spec/base.tla` and selected by
`spec/MC.cfg`. `CommittedLogAgreement` compares identical committed positions across nodes when
both retain that position.

## 6. Evidence plan

### 6.1 Model-checkable

All invariants above, plus reachability witnesses for candidate, leader, append, partial match,
commit, learner, joint membership, crash, and restart states. These witnesses demonstrate that a
green invariant is not merely due to the associated scenario being unreachable.

### 6.2 Test/trace-checkable

The harness calls the exact-old `Engine` implementation and emits post-state NDJSON for:

- `election.ndjson`: elect, local exact-vote grant, remote exact-vote grant, leader/no-op;
- `vote-request.ndjson`: log-fresh vote acceptance and queued persistence;
- `follower-append.ndjson`: consecutive follower suffix acceptance;
- `learner-membership.ndjson`, `joint-membership.ndjson`, and
  `uniform-membership.ndjson`: all membership forms becoming effective;
- `partial-replication.ndjson`: prefix advances and current-leader-term commit;
- `restart.ndjson`: startup from a recovered committed self-vote.

`spec/Trace.tla` invokes base actions and validates every captured post-state field. Trace
completion is enforced by `TraceMatched` in `Trace.cfg`.

### 6.3 Code-review-only

The exact relation between command completion and third-party storage durability, RPC transport
failure details, wall-clock lease expiry, and state-machine business payload effects remain code
review obligations. The model represents their documented boundary, not their concrete backend.

## 7. Source references and existing neutral tests

Primary implementation locations are cited inline above. Neutral exact-old tests corroborating
the scenarios include:

- `openraft/src/engine/tests/elect_test.rs:38-153` and
  `openraft/src/engine/tests/handle_vote_resp_test.rs:144-225`;
- `openraft/src/engine/handler/following_handler/do_append_entries_test.rs:97-152`;
- `openraft/src/engine/handler/replication_handler/update_matching_test.rs:61-137`;
- `openraft/src/engine/handler/replication_handler/append_membership_test.rs:62-145`;
- `openraft/src/raft_state/membership_state/membership_state_test.rs:95-187`;
- `tests/tests/membership/t11_add_learner.rs:53-199`,
  `t20_change_membership.rs:15-153`, and `t30_elect_with_new_config.rs:25-65`;
- `tests/tests/replication/t10_append_entries_partial_success.rs:11-56`.
