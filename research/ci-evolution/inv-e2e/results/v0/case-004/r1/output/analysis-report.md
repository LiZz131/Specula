# Code analysis report — incremental run (update revision)

## Inputs and isolation

- Old: `baseline` d86101c (= V0 prior's exact-old source); new: `update` d7176ef
  (`artifact/`, two neutral synthetic commits). Changed files are exactly those listed in
  `/work/case.json`; the immutable snapshots `/work/old-source`, `/work/new-source` match the
  artifact diff.
- Prior suite `/work/previous/.specula-output` (V0): trace validation and bounded MC were
  complete and `LIMITED_COVERAGE`; no prior findings, no unresolved errors.
- Only the supplied sources, prior suite, scope and tools were used. No history, issue, or
  network research. Network was used only by cargo to fetch ordinary crate dependencies.
- Category unchanged: A (message-passing, crash-fault Raft). The update adds an API message,
  not a new concurrency architecture.

## Update reconnaissance (Chapter 1)

| Changed site | Old behavior | New behavior | Projection onto the model vocabulary |
|---|---|---|---|
| `core/raft_msg/mod.rs:98-107` | — | `RaftMsg::TransferLeader{from: Vote, to: NodeId}` | new Engine input at the RaftCore boundary |
| `core/raft_core.rs:1190-1202` | — | `if vote == from { vote.disable_lease(); if self.id == to { engine.elect() } }` | **changed enablement of the modeled election** (elect without `is_voter`, not-Leader, `enable_elect` guards) + lease flag change |
| `utime.rs:17,31-76,126-161` | `reset_lease` (dead code); `touch` always sets the lease | `lease_enabled` flag; `disable_lease` sets lease 0 and disables; `update`/constructors re-enable; `touch` keeps a disabled lease at 0 | new discrete state consumed by vote-request lease rejection (`engine_impl.rs:305-315`) and election timeout (`raft_core.rs:1475-1484`) |
| `raft/mod.rs:635-703` | — | public `Raft::transfer_leader(from, to, flushed_log)`: non-target forwards at once; target waits for `metrics.vote == from && last_log_index >= flushed_log` up to `election_timeout_min`, then forwards anyway (also on timeout); gives up only if the vote moved past `from` | environment: TransferLeader can reach any node at any time; the handler re-checks the vote |
| `metrics/raft_metrics.rs:34`, `metrics/wait.rs:57` | doc comment / Debug formatting | doc comment / Display formatting | none (metrics excluded) |
| `tests/tests/client_api/*` | — | new test `t14_transfer_leader` | evidence/scenario source only |

Call-path check of `Engine::elect()` callers in the new tree:

- `handle_tick_election` (`raft_core.rs:1441-1488`): not Leader, `is_voter`, `enable_elect`, timeout.
- `ExternalCommand::Elect` (`raft_core.rs:1207-1213`): `is_voter` (comment "Node is switched to learner").
- `Engine::initialize` (`engine_impl.rs:191-218`): only after `check_members_contain_me` (voter).
- **new** `RaftMsg::TransferLeader` (`raft_core.rs:1197-1199`): only `vote == from`.

**Disposition: `MODEL_CHANGE_REQUIRED`.** The update changes the enablement of the modeled
election action (a non-voter, an absent node, or the current leader can now run `elect()` on a
public API input), and adds the lease flag whose `touch`/`update` semantics are observable
Engine state. The lease *duration/time* stays excluded: with the model's nondeterministic
expiry the old projected post-states of vote-request handling are unchanged by the flag, but the
flag itself is modeled, trace-validated, and constrained by update properties.

## Update-focused analysis (Chapter 3)

Mechanism trace through unchanged code (all in the new tree):

1. `Engine::elect()` (`engine_impl.rs:223-249`) builds `Candidate::new(now, vote, last_log_id,
   membership.to_quorum_set(), learner_ids)`. `Candidate::new` creates
   `progress: VecProgress::new(quorum_set, [], ..)` — **voters only, learners dropped**
   (`proposer/candidate.rs:62-75`).
2. `update_vote(new_vote)` → `update_internal_server_state()`: the candidate is kept when
   `is_leading` = *contained in membership* (voter **or learner**) and voted for self
   (`raft_state/mod.rs:369-371`); an absent node instead `become_following()` clears it.
3. RaftCore executes `SaveVote` → after `save_vote` it sends
   `Notification::VoteResponse{target: self.id, resp: VoteResponse::new(vote, None)}`
   (`raft_core.rs:1669-1681`), then `SendVote` to the effective voters (`raft_core.rs:1049-1100`).
   All vote responses use the same FIFO notification channel, so the self response is
   processed first.
4. `does_vote_match` passes (candidate vote = sender vote); `handle_vote_resp(self.id)` →
   `candidate.grant_by(&self.id)` → `self.progress.update(target, true).expect("target not in
   quorum set")` (`candidate.rs:90-96`) → **panic for a learner** → RaftCore task dies,
   `Raft` APIs return `Fatal::Panicked`.
5. Meanwhile the learner's RequestVote (term `last_seen+1`) reached the voters; their leases
   were disabled by the same transfer call, so they grant and the old leader steps down; the
   candidate no longer exists, so the cluster is leaderless until an ordinary election timeout.

The two pre-existing callers make this path unreachable in the old code (guard `is_voter`).
The design documentation states the guarded behavior as a property: "follower and learner in
Openraft is almost the same. The only difference is a learner does not try to elect itself"
(`docs/data/vote.md:50-51`).

Update Scenarios (detailed in `modeling-brief.md` §2b):

- **U-S1** transfer to a learner (old producer: learner replication; changed action: transfer
  elect; old consumer: self grant / remote grants / old leader step-down).
- **U-S2** lease disable → `touch` on same-vote heartbeats keeps it disabled → `update` on a
  vote change re-enables (old producer: append/vote handling; consumer: vote-request lease check).
- **U-S3** intended voter transfer: elect by the target, old leader deposed by the vote request,
  new leader commits; safety across the transfer (committed-log agreement, leader completeness).
- **U-S4** transfer across membership changes: absent (removed) target runs `elect()` and falls
  back to following; leader transfer to itself (leader+candidate coexistence, pre-existing).
- **U-S5** crash/restart around a transfer: lease re-enabled by a fresh `RaftState`; leadership
  restored only when contained in membership (R4).

Properties (placement in `spec/Update.tla` unless noted): U1 `ElectOnlyByVoter`, U2
`NoCorePanic`, U3 `LeaseReenabledOnVoteChange`, U4 `DisabledLeaseOnlyByTransfer`, U5
`ElectedLeaderWasVoter`, U6 `TransferSafety` (= reference `CommittedLogAgreement`,
`LeaderCompleteness` [new reference property], `CandidateGrantSound`).

Inherited abstractions rechecked (repairs R1–R8 in `spec/changelog.md`): the V0 vote exchange,
replication/ack linkage, restart leadership, and self-response ordering were too weak or wrong
for the update's interactions and were repaired in the reference; the source delta disposition
is unchanged by these repairs.

Prior finding lineage: V0 froze no findings; nothing to reuse. No persistent-findings registry
(`specula` CLI) is installed in this environment.

## Outcome (see `spec/bug-report.md`)

- **MC-1 (REPRODUCED, update-introduced):** `transfer_leader(.., to = learner)` panics the
  learner's RaftCore (`candidate.rs:92` "target not in quorum set") and deposes the healthy
  leader. Model counterexamples for U1/U2; real-trace replay of the panic; uninstrumented
  reproduction 5/5; baseline and same-revision `trigger().elect()` controls are guarded.
- **MC-2 (REPRODUCED in debug-assertion builds, pre-existing, new trigger):**
  `transfer_leader(.., to = current leader)` (and, before the update, `trigger().elect()` on the
  leader) makes the Leader re-elect while keeping its Leader object; `Engine::leader_handler`'s
  assertion `leader.committed_vote >= state.vote` then panics the leader's RaftCore
  (`engine_impl.rs:765`). Model U7 counterexamples on both triggers; probes on both revisions.
- Remaining update/reference properties: no violation within the recorded bounded campaigns
  (`LIMITED_COVERAGE`, not proof).

---

# Appendix: V0 analysis report (exact-old baseline, retained for lineage)

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

