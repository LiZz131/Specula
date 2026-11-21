# Instrumentation specification — OpenRaft incremental run (ce863f4 → aa05a38)

Rebased from the V0 instrumentation. Probe code lives in
`harness/patches/instrumentation.patch` (applied to an isolated copy
`work-source/` of the updated tree; the `artifact/` tree is never modified).

## 1. Trace event schema

Every line:

```json
{"tag":"trace","ts":"<epoch-ns>","depth":<n>,"event":{"name":"<action>", ...}}
```

`depth` (new) is the nesting level of instrumented calls on the emitting thread
(RAII guard `specula_trace::enter()`); the preprocessor keeps `depth = 0` only,
because the update makes instrumented helpers call each other
(`leader_append_entries → update_progress → VecProgress::update → is_quorum`).
`Trace.tla` also filters `line.depth = 0`.

Engine events carry `nid`, `pre`, `post`, `args`. Snapshot fields:

| JSON field | Source | TLA+ state |
|---|---|---|
| `term`, `vote_node`, `vote_committed` | `Engine.state.vote` | `currentTerm`, `voteFor`, `voteCommitted` |
| `role` | `state.server_state` | `role` |
| `last_log`, `logs[]` | `last_log_id`, `get_log_id` | `lastLog`, `logTerm` |
| `committed` (+ `committed_term`, informational) | `state.committed` | `committed` |
| `*_mem_index`, `*_mem_term`, `*_configs` | `MembershipState` | membership variables |
| `leader_some` (**new**) | `state.leader.is_some()` | `leaderSome` |
| `vote_granted` (**new**) | `Leader.vote_granted_by` | `voteGranted` |
| `progress.vector` (**new**, ordered) | `Leader.progress.vector` | `progVec` (order and values) |
| `progress.committed` (**new**) | `Leader.progress.committed` | `progCommitted` |
| `progress.qs` (**new**) | `Leader.progress.quorum_set` | `progQS` |

Progress values: `{"kind":"none"}` (= 0), `{"kind":"log","t":T,"n":"N","i":I}`
(= `LV(T,I)`), `{"kind":"raw","raw":V}` for the `u64` unit-test progress. Field
`n` is consumed by `Trace!LogIdNodeConsistent` (a current-term log id must
belong to the vote's node — the premise of the (term,index) encoding).
Values and quorum sets are rendered by `Any` downcasting, so no production
trait bound changes (the V0 `Display` bounds do not compile against
`Option<LogId>` values and were removed in the rebase).

## 2. Action-to-code mapping

| Event | Spec action | Code (updated tree) | Capture | Args |
|---|---|---|---|---|
| `Elect` | `StartElection` | `engine_impl.rs` `Engine::elect` (both returns) | entry / each return | — |
| `HandleVoteResp` (**new**) | `HandleVoteResp` | `Engine::handle_vote_resp` (wrapper around unchanged body) | entry / exit | `target`, `vote{term,node,committed}`, `granted` |
| `LeaderAppend` | `LeaderAppendEntries` | `Engine::leader_append_entries` | before empty check / after commands | `count`, `membership_position` (first membership entry, 1-based in batch, `-1` none), `membership_configs` (**new**) |
| `UpdateProgress` (**new**) | `UpdateProgressAction` (= `EngineUpdateProgress`) | `Engine::update_progress` (wrapper) | entry / exit | `target`, `value` (log id) |
| `UpdateEffectiveMembership` (**new**) | `UpdateEffectiveMembershipAction` (= `EngineUpdateEffective`) | `Engine::update_effective_membership` (wrapper) | entry / exit | `log_term`, `log_index`, `configs` |
| `FollowerCommit` | `FollowerCommitEntries` | `Engine::follower_commit_entries` | entry / after `update_committed` | `leader_commit`, `prev_log`, `last_entry` as log-id values (**format changed**) |
| `UpdateCommittedMembership` | `UpdateCommittedMembership` | `Engine::update_committed_membership` | entry / exit | unchanged |
| `ProgressUpdate` | `ProgressUpdateValue` (= `PUpdate`) | `VecProgress::update` (wrapper around unchanged body) | entry / exit | `target`, `value`; `pre`/`post` = `{vector,committed,qs}` (**format changed**) |
| `ProgressUpgrade` (**new**) | `ProgressUpgradeAction` (= `PUpgrade`) | `VecProgress::upgrade_quorum_set` (wrapper) | entry / exit | `qs` |
| `QuorumCheck` | `Quorum` | `EffectiveMembership::is_quorum` | after evaluation | unchanged |
| `ReplicationLagCheck` | lag relation | `core/replication_state.rs::is_matched_upto_date` | after evaluation | unchanged |
| ~~`GreatestMajority`~~ | — | `Membership::greatest_majority_value` **deleted by the update** | — | superseded |

Every Engine step checks the full `pre` snapshot against the replayed state
(`EngineSnapshotMatches`) and the full `post` snapshot (`EngineSnapshotMatchesNext`),
including vector order, cached committed and quorum set of the leader progress.

## 3. Not directly traced (environment limitation)

`SendAppendEntries`, `DeliverAppendEntries`, `RejectAppendConflict`,
`HandleUpdateMatched` (LeaderState part: `ReplicationState.matched` update and
the `matched <= committed` early return), `GrantVote` (voter side),
`LoseMessage`, `Crash`, `Recover` run in the asynchronous RaftCore/LeaderState
runtime with storage/network tasks. The selected unit environments call the
Engine directly; the Engine part of `HandleUpdateMatched`
(`Engine::update_progress`) and the candidate part of `GrantVote`
(`Engine::handle_vote_resp`) are traced. Same limitation class as V0 (L2).

## 4. Special considerations

- Tracing is inert unless `SPECULA_TRACE` and `SPECULA_TRACE_FILE` are set.
- Multi-fixture tests (several engines in one test) are split by the
  preprocessor at fixture boundaries (`pre` ≠ previous `post`) into
  `<name>-seg<k>.ndjson`; each segment replays from its own captured pre-state.
- `update_effective_membership_test::test_update_effective_membership_at_index_0_is_allowed`
  builds an effective membership older than the committed one; it is replayed
  with `Trace_fixture.cfg` (no `MembershipOrder`). Control:
  `output/trace-control-control_learner_under_Trace_cfg.log` shows the fixture's
  initial state violates `MembershipOrder`.
- No event is hand-written; `harness/run.sh` regenerates every trace.
