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

