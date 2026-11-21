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

# Incremental update analysis (V0 baseline -> update)

## Exact inputs

- Prior suite: `/work/previous/.specula-output/` (V0, exact-old; frozen copy seeded into this run).
- Current source: `artifact/` with neutral commits `baseline` = `d86101c7c585656d90d55e30f2e6c923b0f65e18`
  and `update` = `d7176ef916c7d2e3f2a0eed612875d7ce3e646b1`. Every changed file of `baseline`
  is byte-identical to `/work/old-source`, and every changed file of `update` to `/work/new-source`.
- The prior V0 harness patch (`harness/instrumentation.patch`) still passes `git apply --check`
  on the update tree.
- Category is unchanged: A (crash-fault message-passing Raft). The update adds no thread, task,
  storage or transport mechanism; it adds one RaftCore API message.

## Complete diff projection

| Changed hunk | Behaviour old -> new | Projection on model vocabulary |
|---|---|---|
| `core/raft_msg/mod.rs:98-107,143-145` | new `RaftMsg::TransferLeader{from,to}` + Display | new API input of the RaftCore event loop |
| `core/raft_core.rs:1190-1202` | new branch: if `engine.state.vote == from` then `vote.disable_lease()` and, if `self.id == to`, `engine.elect()` | **new Action** `TransferLeader`; the elect branch calls `Engine::elect` **without** the `is_voter` guard used by every other election path |
| `raft/mod.rs:635-703` | new `Raft::transfer_leader(from,to,flushed_log)`: non-target nodes send the message at once; the target waits (metrics: flushed vote == from and last_log_index >= flushed_log.index, or vote moved past `from`) for at most `election_timeout_min` and **still sends on timeout** | timing only: the Core-level guard is exactly `vote == from`; the wait shortens/lengthens delay and is abstracted as message delay |
| `utime.rs:17,34,63,74,130-138,159-161` | `Leased::disable_lease` sets lease 0 and `lease_enabled=false`; `touch` keeps lease 0 until the next `update`; `update/new` re-enable | lease is already abstracted (V0: "lease arithmetic is abstracted by choosing ReceiveVoteRequest"); a disabled lease only enlarges the set of times when a grant is possible, which V0 already over-approximates. Projected post-state sets unchanged |
| `metrics/raft_metrics.rs:34` | doc comment "last accepted vote" -> "last flushed vote" | documentation; metrics excluded. Confirms `transfer_leader` waits on the flushed vote (`raft_core.rs:560`) |
| `metrics/wait.rs:57`, `utime.rs` Display | formatting | excluded (metrics formatting) |
| `tests/.../t14_transfer_leader.rs`, `main.rs` | new integration test: transfer 0->2, then a stale-vote transfer 2->0 must not elect | neutral update test; reused as an update scenario |

## Call-path check for `Engine::elect` (the only state-changing effect of the update)

All pre-existing callers gate election on voter membership:

- tick election: `core/raft_core.rs:1449-1457` (not leader, `effective().is_voter(&self.id)`);
- `ExternalCommand::Elect`: `core/raft_core.rs:1208` (`effective().is_voter(&self.id)`; else "Node is switched to learner");
- `initialize`: `engine/engine_impl.rs:202-216` after `check_members_contain_me` (`:694-704`, `is_voter`).

The new caller `core/raft_core.rs:1197-1200` checks only `vote == from`. `Engine::elect`
(`engine/engine_impl.rs:223-249`) itself has no membership guard: it creates a candidate with the
node's effective quorum set and learners, updates the local vote to `(last_seen.term+1, self)`,
emits `SaveVote` and `SendVote`, and recomputes the server state. Consequently:

- **voter target** (old and new projected post-state identical to V0 `StartElection`);
- **learner target** (present non-voter): `is_leading` holds (`raft_state/mod.rs:369-371`), so the
  candidate is retained, role becomes `Candidate`, vote requests go to the effective voters
  (`raft_core.rs:1049-1057`), and a quorum of voter grants establishes it as `Leader`
  (`raft_state/mod.rs:345-346`) -- a state never produced by V0 `StartElection`;
- **absent target** (removed node still holding the leader vote): `update_vote` ->
  `become_following` drops candidate and leader (`vote_handler/mod.rs:241-252`), role is
  `Learner`, but `SendVote` is still emitted with a higher term.

Learners hold the leader's committed vote because they receive AppendEntries
(`engine_impl.rs:449-460` -> `vote_handler/mod.rs:126-163`), so `vote == from` is satisfiable on a
learner whenever the caller follows the API instruction "Call this method on every node in the
cluster with the same arguments" (`raft/mod.rs:641-642`). No API-level or Core-level check rejects
a non-voter `to`.

## Disposition

**MODEL_CHANGE_REQUIRED.** The update adds a new modeled Action (`TransferLeader`) and changes the
enablement condition of the election effect: V0 `StartElection` requires `IsVoter(n,n)`, whereas
the new path reaches the same Engine effect on learners and absent nodes. The projected post-state
sets therefore differ for the elect branch. The lease/metrics/formatting hunks project to no change
(see table). Old scenarios needing recheck: S1 (election), S2 (vote request), S5 (learner/voter
membership), S7 (crash between transfer steps).

## Model granularity for the update

- `Engine::elect` becomes the reusable reference operator `Elect(n)` with membership-dependent
  post-state (voter / present learner / absent). `StartElection == IsVoter /\ Elect` keeps the
  tick and `ExternalCommand::Elect` paths. `TransferLeader(n, from, to)` is one atomic RaftCore
  event-loop step (the branch runs synchronously inside `handle_api_msg`, followed by
  `run_engine_commands`, `raft_core.rs:995-1001` (`handle_api_msg` then `run_engine_commands`)).
- `from` is restricted in MC to a committed (leader) vote, as documented for the argument
  (`raft_msg/mod.rs:103-104`); the stale-vote no-op branch is part of the reference and is trace
  validated.
- Lease remains abstract; the non-target branch is a no-op on modeled state.

## Prior-model defects rechecked because the update depends on them

The update's main interaction is a leadership change between real nodes (`old leader -> transfer
target election -> peer grants -> new leader -> commit`). V0 explores only one leader (node 1)
and drives all peers by unconstrained action parameters. Rechecking the abstractions the update
relies on found implementation-backed inconsistencies, repaired in this run:

1. **R1 vote-request freshness** used `reqLast >= LastIndex(n)` (index only). The source compares
   full `LogId` (`engine_impl.rs:317`; `log_id/mod.rs:22-31` derives `Ord` over
   `(leader_id(term,node), index)`). The transfer API explicitly depends on this comparison
   (`raft/mod.rs:658-659`).
2. **R2 forged vote traffic in MC**: any peer could grant any candidate and any request could reach
   any node. Grants are now delivered only from peers that actually accepted the candidate's
   request, requests carry the elect-time `last_log_id`, are sent after `SaveVote`, and go to the
   effective voters at send time (`raft_core.rs:1049-1057,1670-1681`). Duplicate vote delivery no
   longer emits a spurious `SaveVote` (`vote_handler/mod.rs:152-160`).
3. **R3 fabricated follower entries**: `ReceiveAppendDirect` appended `(t, owner)` data entries
   carrying the follower's own config, so follower logs and memberships never mirrored the leader.
   The reference action now receives the actual entries, applies membership entries as
   `append_membership` does (`following_handler/mod.rs:132-145,217-240`,
   `membership_state/mod.rs:137-151`), and recomputes role with the new effective config.
4. **R4 forged replication acks**: `AcknowledgeReplication` could set any peer's match. MC acks now
   consume an actual flush-gated success response carrying the follower's accepted index and the
   leader vote it accepted (`engine_impl.rs:425-439`).

Recorded but not repaired (independent of the update; limits coverage):

- follower conflict truncation and membership rollback (S6) are not modeled by V0's base actions
  although V0's brief lists them; the model's I/O indices are scalar while the implementation's
  I/O ids are `(vote, log_id)`, so truncation cannot be added faithfully without a larger rework.
  Followers therefore only append at their log end (an under-approximation);
- follower commit propagation (`handle_commit_entries`) and `HigherVote` replication notifications
  are not modeled; non-granting vote responses are treated as dropped messages.

## Update scenarios

- **U1 non-voter transfer target** (`raft_core.rs:1197-1200`): learner/absent node with the
  leader vote receives `TransferLeader(to=self)`; expected by the documented rule "a learner does
  not try to elect itself" (`docs/data/vote.md:50-51`) and by every other election path to be
  rejected; implementation elects.
- **U2 stale-vote transfer** (t14 second half): `vote != from` must not change state.
- **U3 voter transfer + commit** (t14 first half): target elects with real grants, old leader steps
  down on the higher vote, the new leader commits; committed prefixes must agree.
- **U4 transfer across crash/restart**: crash of target after `elect` but before `SaveVote`, or of
  the old leader during transfer.

## Code-review notes outside the model's time abstraction

- `transfer_leader` documentation says the target "triggers an election when the expected log
  entries are flushed" (`raft/mod.rs:637-638`) but the timeout branch "still submit[s]"
  (`raft/mod.rs:689-700`) and the Core branch has no log check. Voters still reject a stale
  candidate by `LogId`, so safety is unaffected; effect is a possible extra election (liveness).
- A disabled follower lease is not re-enabled by heartbeats of the same leader
  (`utime.rs:135-161`); if the transfer fails, followers stay lease-less for that leader's term.
  The leader-side lease (`last_quorum_acked`, `docs/data/leader-lease.md`) is not invalidated by
  `TransferLeader`. Both are wall-clock properties outside the modeled scope.

## Incremental run outcome

- Validation: rebased V0 harness plus RaftCore window probes; 34 fresh traces pass real TLC replay
  (`spec/output/validation-summary.md`), and a field-mutation control shows every field is consumed.
- Model checking: see `spec/output/model-checking-summary.md`. Update finding **MC-1**: a learner
  `TransferLeader` target elects and its RaftCore panics on its own vote grant
  (`target not in quorum set`). It is reproduced on the update revision and absent on the baseline
  (`spec/confirmation-MC-1.md`). The absent-target variant elects without panicking and disrupts the
  cluster. Voter-target transfer (U3) and crash interactions (U4) showed no violation within budget.
- Pre-existing, update-independent observation **MC-2** (NEEDS MORE INFO): the persisted `committed` id
  may be ahead of the leader's own durable log in three-voter configurations
  (`spec/bug-report.md`).
