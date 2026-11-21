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

---

# Incremental update: `update` d7176ef9 adds `RaftMsg::TransferLeader`

Disposition: **MODEL_CHANGE_REQUIRED** (evidence: `analysis-report.md`, "Incremental update
analysis"). Category unchanged (A). The sections below extend sections 2-6 above; where they differ,
these sections describe the current model.

## U-scenarios (update-focused)

### U1 - non-voter transfer target (affected action -> old consumer)

`Raft::transfer_leader(from, to, flushed_log)` (raft/mod.rs:635-703) sends
`RaftMsg::TransferLeader{from,to}`; RaftCore checks only `engine.state.vote == from`, disables the
vote lease and, if `self.id == to`, calls `Engine::elect()` (core/raft_core.rs:1190-1202). Every
older trigger checks `is_voter` first (raft_core.rs:1449-1457, 1206-1214; engine_impl.rs:694-704).
A learner holds the leader's committed vote (it receives AppendEntries), so a learner `to` elects.
Old consumer: SaveVote completion delivers the local self-grant (raft_core.rs:1670-1682) to
`Candidate::grant_by`, whose progress contains voters only and which calls
`.expect("target not in quorum set")` (proposer/candidate.rs:57-71, 86-92). Expected by
`docs/data/vote.md:50-51` ("a learner does not try to elect itself"): no election.
Model: `base!HandleTransferLeader` -> `base!Elect` (no guard) -> `base!CoreVoteResponsePanic`.
Properties: `Update!ElectionInitiatorIsVoter`, `Update!CandidateIsVoterOfSnapshot`,
`Update!NoCorePanic`.

### U2 - stale `from`

`vote != from` must leave the node unchanged (t14 second half). Model:
`base!TransferLeaderIgnored`; validated by the real window `t14 .../transfer-ignored-n1`.

### U3 - voter transfer, old leader supersession, commit by the new leader

`old leader -> TransferLeader(to=voter) -> Elect -> peer grants (lease disabled) -> establish ->
replicate/commit`. Model: repaired closed-world vote and append traffic (R1-R4). Properties:
reference `CommittedLogAgreement` (unaffected control), `CandidateGrantSound`; canaries
`CanaryTransferVoterLeader`, `CanaryOldLeaderSuperseded`, `CanaryTransferLeaderCommits`.

### U4 - crash around the transfer

Crash of the target after `Elect` but before `SaveVote` completes, or of the old leader; restart
from durable vote/log. Canary `CanaryCrashBeforeSaveVote`; hunt `Update_hunt_U4_crash.cfg`.

## Model changes (summary; details in `spec/changelog.md`)

- `Elect` (Engine::elect, membership-dependent post-state), `StartElection == IsVoter /\ Elect`,
  `HandleTransferLeader` (3 branches), `CoreVoteResponsePanic`, `ReceiveVoteReject`,
  `RejectVoteRequest`, `ReceiveAppend` (actual entries, membership effect).
- Repairs of V0 abstractions used by the update: R1 full-LogId vote freshness, R2/R4 closed-world
  network (`voteReqs`, `voteResps`, `appendResps`; no forged grants/acks), R3 real follower entries,
  fresh leader progress, member-only leader restore on restart.
- Lease stays abstract: `disable_lease` only enlarges when a grant may happen, which the model
  already allows at any time.

## Properties (current)

Reference (`base.tla`, `MC.cfg`): the 12 V0 invariants, kept (evidence `spec/invariant-evidence.json`).
Update (`Update.tla`): `ElectionInitiatorIsVoter` (action), `CandidateIsVoterOfSnapshot`,
`NoCorePanic`; discharge `DischargeContext`, `PartitionComplete`; reachability canaries.

## Exclusions and limits (update)

- Wall-clock lease semantics of `disable_lease`/`touch` and the transfer API's metrics wait/timeout
  are excluded (time abstracted); recorded as code-review notes in the analysis report.
- Follower conflict truncation/membership rollback, follower commit propagation and `HigherVote`
  notifications remain unmodeled (pre-existing V0 limits; followers only append at their log end).

## Evidence plan (update)

- Trace: unit `elect-learner`, `elect-absent`, `follower-membership`, `vote-request-logid`; RaftCore
  windows `t14-transfer-to-voter`, `t99-transfer-to-learner` (see `spec/output/validation-summary.md`).
- MC: `MC.cfg` (standard), `Update_full*.cfg`, `Update_focused*.cfg`, `Update_open.cfg`,
  `Update_discharge.cfg`, `Update_canary_*.cfg`, `Update_hunt_U1_absent*.cfg`, `Update_hunt_U3_voter.cfg`,
  `Update_hunt_U4_crash.cfg`, `Update_open_voter.cfg`, `Update_focused_voter.cfg`, `Update_full_voter.cfg`.
