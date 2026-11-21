# Exact-old code analysis report

## Isolation and method

Analysis used only `/work/source`, `/work/scope.md`, and `/work/input-manifest.json`. The source is
the neutral single commit `955ebf13f9c4acf88240775db2b51832c9cbb6a9`; no remote or historical
behavioral source was consulted. The work was split into code-only election, replication, and
membership passes, then reconciled against Engine/RaftCore command ordering. Category: A
(distributed/message-passing), non-BFT.

## Structural findings

`Engine` owns the complete synchronous consensus calculation, while `RaftCore` realizes commands
as asynchronous storage, network, and state-machine operations. A handler call is an atomic model
step; every command completion is a separate step. The queue is FIFO and a command whose
condition is unmet returns to the head (`openraft/src/engine/engine_output.rs:6-44`,
`openraft/src/core/raft_core.rs:852-888`). This is the decisive atomicity boundary for the suite.

The vote is a total order in the default build: leader IDs order lexicographically by term and
node ID, with `committed` breaking an otherwise equal vote (`openraft/src/vote/vote.rs:21-41`,
`openraft/src/vote/leader_id/leader_id_adv.rs:14-22`). `last_seen_vote` may be ahead of the granted
state vote. Candidate quorum and learners are snapshotted at election start. The implementation
deliberately permits candidate and leader objects to coexist while a leader seeks a higher vote
(`openraft/src/engine/engine_impl.rs:73-101`, `:122-140`).

Leader logical append precedes I/O: log IDs are assigned, the in-memory log and accepted I/O move,
and an effective membership immediately changes before `AppendInputEntries` is durable
(`openraft/src/engine/handler/leader_handler/mod.rs:50-93`). Follower success is flush-gated.
Commit is separately propagated, saved, and applied
(`openraft/src/engine/handler/replication_handler/mod.rs:219-248`,
`openraft/src/core/raft_core.rs:1708-1713`).

Membership has committed and effective values. Effective is the latest locally accepted
membership; commit promotes it, while conflict truncation may revert it. A joint configuration is
a conjunction of strict majorities and learners are outside all voter children
(`openraft/src/raft_state/membership_state/mod.rs:20-41`, `:82-187`,
`openraft/src/quorum/joint.rs:56-89`). A removed leader intentionally remains active until the
removing membership is committed and applied (`openraft/src/core/raft_core.rs:1296-1316`).

## Failure model

Messages may be delayed, reordered, duplicated, or dropped. Nodes fail by crash-stop followed by
optional restart; Byzantine behavior is excluded. Crash preserves only completed durable vote,
log, commit, and state-machine effects. It loses Engine state, candidate/leader progress, queued
commands, worker handles, and incomplete callbacks. Storage calls and RPCs are not assumed atomic
with their originating Engine event.

## Modeled abstractions

Log payload is reduced to `blank`, `data`, `learner`, `joint`, or `uniform`, retaining leader ID,
index, voter children, and learners. Network data is reduced to vote and append messages carrying
the comparison/session fields used by the exact-old code. Time is reduced to nondeterministic
election enablement; lease duration arithmetic is not modeled. Snapshot/purge and metrics are out
of scope.

## Risks intentionally retained

- an in-memory vote or membership can be ahead of durable state;
- a successful follower response cannot precede flush;
- a higher observed vote can affect the next election without changing the granted vote;
- partial success advances only a prefix;
- old replication sessions cannot affect new membership progress;
- joint membership may survive a crash between the two public API calls;
- a leader can be removed from voters yet remain leader long enough to finish the change.

No known-incident hypothesis or future-change assumption was introduced. The model-checking bounds
are exploration limits and cannot establish proof.


---

# Incremental update analysis (current run, case-004 `update` commit)

## Inputs and identity

- Prior suite: `/work/previous/.specula-output` (exact-old V0, baseline `955ebf1…` in its own
  numbering). Its trace validation and bounded MC were reported `LIMITED_COVERAGE`, without
  unresolved errors; no prior findings exist.
- Current source: `artifact/` branch `experiment`, commits `d86101c baseline` → `d7176ef update`.
  `git diff baseline update` equals `diff -r /work/old-source /work/new-source` (8 files).
- Category unchanged: A (crash-fault Raft, message passing). No archaeology outside `/work` was
  performed (blind task); history reasoning uses only the two neutral commits.

## Changed behavior, projected onto the model vocabulary

| Change (new source) | Behavior before → after | Projection on model |
|---|---|---|
| `core/raft_msg/mod.rs:98-107`, `core/raft_core.rs:1190-1202` new `RaftMsg::TransferLeader{from,to}` handler | absent → if `engine.state.vote_ref() == from`: `vote.disable_lease()`; and if `self.id == to`: `engine.elect()` | **new action** `TransferLeader`. Target branch reaches `Engine::elect()` **without** the `is_voter` guard used by the two pre-existing callers (`ExternalCommand::Elect`, `raft_core.rs:1206-1214`; `handle_tick_election`, `raft_core.rs:1454-1457`). Non-voters (learners) can now become candidates — a projected post-state the old model (`StartElection` guard `IsVoter(n,n)`) could not reach. Non-target / mismatching branch: lease only → stutter on modeled variables. |
| `utime.rs:14-161` `lease_enabled`, `disable_lease`, `touch` honours it, `update` re-enables | `reset_lease` was dead code → lease can be forced to 0 until the next vote change | Lease/time is abstracted in the prior model (`ReceiveVoteRequest` may always grant; election timeout is nondeterministic). Disabling a lease only removes a *rejection* outcome that the model already never forces, so no projected state changes. Liveness/timing effect is out of scope (scope excludes precise time). |
| `raft/mod.rs:635-703` `Raft::transfer_leader(from,to,flushed_log)` API | absent → non-target: send msg; target: wait (metrics `vote==from` and `last_log_index>=flushed_log`, timeout `election_timeout_min`), give up only if vote moved past `from`, otherwise (also on timeout) send msg | Environment producer of `TransferLeader`. The wait only delays/suppresses delivery; RaftCore re-checks `vote == from` (`raft_core.rs:1194`), so arbitrary delivery time of a matching message over-approximates it. |
| `metrics/raft_metrics.rs:34` doc, `metrics/wait.rs:57` Display format, `utime.rs` Display | formatting/doc only | excluded (metrics formatting). Note: `metrics.vote` is already the *flushed* vote (`raft_core.rs:560`) and `last_log_index` the in-memory last log (`raft_core.rs:561`); the doc fix does not change behavior. |
| `tests/tests/client_api/t14_transfer_leader.rs` | new integration test (voter target; stale `from` rejected) | used as an update trace scenario |

Call-path check: `RaftMsg::TransferLeader` is produced only by `Raft::transfer_leader`
(`raft/mod.rs:654,700`) and consumed only by `RaftCore::handle_api_msg` (`raft_core.rs:1190`).
`Engine::elect()` itself (`engine_impl.rs:219-249`) is unchanged and has no voter check; its other
callers keep their guards; `Engine::initialize` calls it after `check_members_contain_me`.

What `elect()` does on a non-voter (unchanged code, newly reachable): `new_candidate` snapshots the
effective quorum set (voters only) and learners (`engine_impl.rs:123-140`); `update_vote` then calls
`update_internal_server_state` — a learner is `contains()`ed in membership, so `is_leading` holds and
the candidate survives with `ServerState::Candidate` (`raft_state/mod.rs:332-383`); an absent node is
not leading, so `become_following` drops the candidate (`vote_handler/mod.rs:168-176,240-250`) while
`SendVote` is still emitted. Vote requests go to the effective voters except self
(`raft_core.rs:1049-1058`); the self-grant does not count for a learner because the quorum set has
only voters. A learner candidate whose log is fresh and whose voters accept (lease expired or
disabled by the same transfer) therefore establishes itself as **Leader** (`is_leader` only needs
`contains`, `raft_state/mod.rs:381-383`).

## Disposition

**MODEL_CHANGE_REQUIRED.** The update adds an Action (`TransferLeader`) with a new enablement
condition for the election transition: post-states with a learner candidate (and subsequently a
learner leader) are newly reachable. The lease change projects to no modeled change (recorded above).

## Prior-model defects that the update's verification depends on (repairs, not source deltas)

1. `ReceiveVoteRequest` compared only the last log *index*; the code compares the full `LogId`
   `(term,node_id,index)` (`engine_impl.rs:318`). Transfer targets with an equal-length but older
   log must be rejected; the index-only check would admit unsafe grants after a second election.
2. `MC.tla` delivered vote responses from any peer whether or not it had granted, vote requests with
   a hard-coded term 1 / candidate 1, follower appends from a hard-coded leader `(1,1)`, and
   replication acks for entries the follower never received. These over-approximations were
   harmless with one election but make any multi-election (transfer) check meaningless. They are
   replaced by message-faithful MC framing (grant log after vote flush — `raft_core.rs:1112-1122`,
   requests published by `SendVote` to effective voters — `raft_core.rs:1049-1108`, appends copied
   from a live leader's submitted log, acks only for a flushed matching prefix — flush-gated
   `Respond`). Inbound messages are processed only after the node's queued vote commands ran
   (single RaftCore loop: `run_engine_commands` executes `SaveVote`/`SendVote` inline,
   `raft_core.rs:1670-1712`).
3. `StartElection` modeled `Engine::elect` *and* the RaftCore voter guard in one action. It is split
   into `Elect` (Engine) and `StartElection` (tick/`ExternalCommand::Elect` guard), so that
   `TransferLeader` reuses `Elect` without copying its body.

Independent observation (not caused by the update, recorded for separate work): when a Leader
calls `elect()` (pre-existing `trigger().elect()`, now also `transfer_leader(to = leader)`), the
Leader object survives while `state.vote` becomes an uncommitted higher vote; `leader_handler()`
then carries `debug_assert!(leader.committed_vote >= state.vote)` (`engine_impl.rs:765-770`), which
such a state violates if a client write arrives. The model keeps the prior guard
`voteCommitted[n]` on `LeaderAppend`; this path is not explored further here.

## Update results (Validation and Model Checking)

- Validation back-edges: (1) code observation of U2 showed that the learner candidate's
  self-grant panics in `Candidate::grant_by` (`candidate.rs:92`); `base` gained `panicked` and
  `CandidateGrantPanic`. (2) Canary-witness review: the self grant is always handled before remote
  grants (FIFO notifications), MC framing repaired. (3) U1 hunt with 3 voters exposed a prior-model
  defect: `SaveCommit` ignored serialized write-IO (`storage/v2.rs:33-35`); repaired. Details in
  `spec/changelog.md`.
- **MC-1 (Case C, update-introduced)**: `TransferLeader` with a learner target makes the learner
  campaign (`ElectionByVoterOnly` violated, 12-state counterexample) and then crash its RaftCore
  (`NoRaftCorePanic`, 16 states). Reproduced on a clean d7176ef worktree; the guarded pre-existing
  path is fine on both revisions. See `spec/bug-report.md`, `spec/findings.json`.
- **CR-2 (pre-existing, code review)**: Leader calling `elect()` (now also via
  `transfer_leader(to = leader)`) then a client write trips a debug assertion; reproduced on both
  revisions via `trigger().elect()`; not introduced by the update.
- No violation of the kept core-safety properties (CommittedLogAgreement, CandidateGrantSound,
  LeaderVoteCommitted, CurrentTermCommit, I/O and durability bounds) in the bounded campaigns
  (LIMITED_COVERAGE; see `spec/output/model-checking-summary.md`).
