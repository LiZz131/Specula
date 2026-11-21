# Instrumentation specification — OpenRaft updated revision (case-012)

Rebased from the V0 prior (`instrumentation-v0-prior.patch`) onto `artifact` HEAD (`update`, aa05a38). Patch: `harness/patches/instrumentation.patch`; module: `harness/src/specula_trace.rs`.

## 1. Trace event schema

Envelope (Category A, single linear file): `{"tag":"trace","ts":"<ns>","event":{...}}`.

Engine events: `name`, `depth`, `nid`, `pre`, `post`, `args`. `depth` is the nesting depth of instrumented Engine calls (thread-local); `harness/preprocess_trace.py` keeps only `depth == 0` Engine events because nested calls (e.g. `update_progress` inside `leader_append_entries`) are contained in the outer pre/post snapshots.

Snapshot fields (`pre`, `post`):

| JSON field | Source (updated revision) | TLA+ state | Checked by |
|---|---|---|---|
| `term`, `vote_node`, `vote_committed` | `Engine.state.vote` | `currentTerm`, `voteFor`, `voteCommitted` | `EngineSnapshotMatches(Next)` |
| `role` | `Engine.state.server_state` | `role` | same |
| `last_log`, `logs[]` | `RaftState::last_log_id/get_log_id` | `lastLog`, `logTerm` | same |
| `committed` | `RaftState.committed` (index) | `committed` | same |
| `*_mem_index`, `*_mem_term`, `*_configs` | `MembershipState` | committed/effective membership vars | same |
| `leader_active` | `RaftState.leader.is_some()` | `leaderActive` | same |
| `vote_granted` | `Leader.vote_granted_by` | `voteGranted` | `EngineSnapshotMatchesNext` (when active) |
| `progress_configs` | `Leader.progress.quorum_set()` groups | `progress[i].cfg` | `SnapProgress` equality |
| `progress_vector` (ordered `{id,term,node,index}`) | `VecProgress.vector` in real order | `progress[i].order`, `progress[i].val` | `SnapProgress` equality |
| `progress_committed` | `VecProgress.committed` | `progress[i].committed` | `SnapProgress` equality |

`None` log ids are `{"term":0,"index":-1}`; u64 test values `v` are `{"term":0,"index":v}`. Node ids are strings; `node` of a log id is emitted but not compared (the model identifies the leader of a log id by its term).

## 2. Action-to-code mapping

| Event | Spec action | Code (updated revision, before instrumentation) | Trigger |
|---|---|---|---|
| `Elect` | `StartElection` | engine_impl.rs:100-130 | capture on entry; emit on both return paths |
| `HandleVoteResp` | `HandleVoteResp` (candidate side of `GrantVote`) | engine_impl.rs:163-227 | wrapper: capture, call original body, emit (args: target, resp vote, granted) |
| `LeaderAppend` | `LeaderAppendEntries` | engine_impl.rs:236-293 | capture after the empty-input check; emit after `MoveInputCursorBy` (args: count, membership position) |
| `FollowerCommit` | `FollowerCommitEntries` | engine_impl.rs:363-386 | capture on entry; emit after `update_committed` |
| `UpdateCommittedMembership` | `UpdateCommittedMembership` | engine_impl.rs:555-589 | capture before comparisons; emit after server-state update |
| `UpdateEffectiveMembership` | `UpdateEffectiveMembership` | engine_impl.rs:591-615 | capture on entry; emit at end (args: log term/index, configs) |
| `UpdateProgress` | `UpdateProgress` (core of `HandleUpdateMatched`) | engine_impl.rs:617-647 | capture on entry; emit at all three exits (args: target, value) |
| `ProgressUpdate` | pure `VecUpdate` relation | progress/mod.rs:163-207 | capture configs/vector/committed on entry; emit at all three exits |
| `ProgressUpgrade` | pure `UpgradeQuorumSetD` relation | progress/mod.rs:222-232 | capture old progress; emit new progress + `V::default()` |
| `QuorumCheck` | `Quorum` | membership/effective_membership.rs:152-157 | after real `is_quorum` |
| `ReplicationLagCheck` | saturating distance | core/replication_state.rs:53-69 | after evaluation |
| ~~`GreatestMajority`~~ | — | deleted by the update | superseded |

Mandatory update fields: `progress_vector` order, `progress_committed`, `progress_configs`, `leader_active`, `vote_granted`. All are required by `Trace.tla` (no optional checks); negative controls in `traces/negative-controls/` (mutated committed, re-sorted vector, mutated progress committed, mutated vote grants) are rejected by TLC (`spec/output/trace-negative-controls-summary.txt`).

## 3. MC-only actions

`SendAppendEntries`, `DeliverAppendEntries`, `RejectAppendConflict`, the ReplicationState/early-return part of `HandleUpdateMatched` (core/replication.rs:92-141), `GrantVote` voter side, `LoseMessage`, `Crash`, `Recover` remain MC-only as in V0: they run inside async `LeaderState`/`ReplicationCore`/storage code that unit fixtures cannot drive without uninstrumented network/storage activity. Their Engine-level constituents (`UpdateProgress`, `HandleVoteResp`, `FollowerCommit`, `LeaderAppend`) are traced. Recorded as a validation coverage limit.

## 4. Special considerations

- Inert unless `SPECULA_TRACE` and `SPECULA_TRACE_FILE` are set; no production behaviour change (all 101 upstream lib tests pass with the patch, spec/output/instrumented-libtests-untraced.log).
- Crate-private trait bounds added for serialization: `SpeculaValue` on VecProgress values and `SpeculaQuorum` on quorum sets (`progress/mod.rs` impl and `leader/leader.rs` impl), plus a read-only `VecProgress::specula_vector` accessor.
- `harness/src/specula_update_test.rs` adds update scenarios U1-U3 driven only through real Engine entry points.
