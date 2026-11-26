# Instrumentation specification

## 1. Trace event schema

The harness writes one NDJSON object per `Engine` invocation on the update revision (rebased from the exact-old V0 harness; module `engine::tests::specular_trace_test`, env `SPECULAR_TRACE_PATH`). The outer envelope is:

```json
{"tag":"trace","ts_unix_ns":"...","event":{"name":"...","nid":"1","pre":{},"post":{},"args":{}}}
```

`tag` is always `trace`; `ts_unix_ns` is a fresh wall-clock timestamp encoded as a string; `nid` and every node ID are strings matching the TLA+ `Server` domain. Each file currently contains one transition so its fixture pre-state is explicit rather than inferred from a previous scenario.

State field mapping:

| JSON field | Exact-old source observation | TLA+ state |
|---|---|---|
| `role` | `eng.state.server_state` | `role[nid]` |
| `vote.{term,node,committed}` | `eng.state.vote_ref()` | `vote[nid]` |
| `last_log` | `LogStateReader::last_log_id()` | `lastLog[nid]` |
| `committed_config`, `committed_config_index` | `membership_state.committed()` | `committedConfig`, `committedConfigIndex` |
| `effective_config`, `effective_config_index` | `membership_state.effective()` | `effectiveConfig`, `effectiveConfigIndex` |
| `candidate_active`, `candidate_vote`, `grants` | `candidate_ref()`, `vote_ref()`, `granters()` | `candidateActive`, `candidateVote`, `grants` |
| `candidate_config` | the candidate's frozen quorum set `candidate.progress().quorum_set()` (V0 used the effective config) | `candidateConfig` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `lease_valid` | `Leased::lease_info()` and `is_expired()` | `leaseValid` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
| `crashed` | harness boundary metadata for a reconstructed engine before/after `startup()` | `crashed` |
| `pre_candidate_active` (**mandatory, update**) | `eng.pre_candidate_ref().is_some()` | `preCandidateActive[nid]` |
| `pre_candidate_vote` (**mandatory, update**) | `pre_candidate_ref().vote_ref()` (state vote when absent) | `preCandidateVote[nid]` (checked when active) |
| `pre_candidate_config` (**mandatory, update**) | frozen quorum set `pre_candidate.progress().quorum_set().get_joint_config()` | `preCandidateConfig[nid]` (checked when active) |
| `pre_grants` (**mandatory, update**) | `pre_candidate_ref().granters()` | `preGrants[nid]` (checked when active) |
| `send_pre_vote_pending` (**mandatory, update**) | queued `CommandName::SendPreVote` | at `PreElect`: one `PreVoteReq` per frozen voter other than `nid` in `messages'` (the runtime executes it in the same drain) |
| `seen_greater_log` | `Engine::is_there_greater_log()` (V0 emitted a constant `false`) | `seenGreaterLog[nid]` |

Vote request arguments include `source`, request `vote`, `last_log`, `transfer`, and the returned `response_vote`/`response_granted`. Pre-Vote request arguments have the same fields; `response_vote` is the responder's own vote in the RPC body (compared with the responder's model vote) and `response_granted` is compared with the model's `PreVoteResp.granted`. Pre-Vote response arguments include `source`, `vote` (the pre-candidate vote the response answers — RaftCore's `candidate_vote` correlation key), `response_vote` (informational; not consumed by `handle_pre_vote_resp`), `last_log`, and `granted`. Vote response arguments include `source`, `vote`, `last_log`, and `granted`. Membership append arguments include `target_config`.

## 2. Action-to-code mapping

| Spec action | Exact-old code location and trigger | Harness event / status |
|---|---|---|
| `StartElection` | `openraft/src/engine/engine_impl.rs:217-253`, snapshot around `elect()` or `elect_by_leadership_transfer()` | `StartElection`; collected for timer/external form |
| `PersistVote` | `openraft/src/core/raft_core.rs:2138-2166`, completion of awaited `SaveVote` | represented by pending command boundary; no standalone V0 trace |
| `SendVoteRequest`, `FinishVoteBroadcast` | `openraft/src/core/raft_core.rs:1360-1428,2203-2205`, runtime dispatch of queued `SendVote` | represented by `send_vote_pending`; no standalone V0 trace |
| `HandleVoteRequest` | `openraft/src/engine/engine_impl.rs:273-326`, snapshot immediately around `handle_vote_req()` | `HandleVoteRequest`; stale-log rejection and greater-vote grant collected |
| `HandleVoteResponse` | `openraft/src/engine/engine_impl.rs:330-389`, snapshot immediately around `handle_vote_resp()` | `HandleVoteResponse`; exact quorum establishment collected |
| `AppendJointConfig`, `AppendUniformConfig` | `openraft/src/engine/handler/leader_handler/mod.rs:56-109` and membership append in `raft_state/membership_state/mod.rs:183-203` | `AppendJointConfig` collected; uniform phase model-checked but not traced |
| `CommitMembership` | `openraft/src/raft_state/mod.rs:333-353` and `membership_state/mod.rs:121-147`, snapshot around `update_local_committed()` | `CommitMembership`; collected |
| `RefreshServerState` | `openraft/src/engine/handler/server_state_handler/mod.rs`, after committed membership changes | state effect represented; no standalone V0 trace |
| `FlushLog` | runtime storage completion for queued `AppendEntries` | represented by `append_pending`; no standalone V0 trace |
| `SendAppendEntries`, `HandleAppendEntries` | runtime replication dispatch and `engine_impl.rs` append handling | modeled and model-checked; no standalone V0 trace |
| `ExpireLease` | time-dependent `Leased::is_expired()` guard in `engine_impl.rs:285-300` | captured as `lease_valid`; no standalone V0 trace |
| `DropMessage` | environment/network loss, not an implementation call | model-checking only |
| `Crash` | process failure boundary, not an `Engine` method | pre-restart boundary metadata only |
| `Restart` | `openraft/src/engine/engine_impl.rs:166-200`, snapshot immediately around `startup()` on reconstructed durable state | `Restart`; follower reconstruction collected |
| `PreElect` (update) | `openraft/src/engine/engine_impl.rs:291-322` `pre_elect()`; tick branch `raft_core.rs:2010-2035`, external `raft_core.rs:1683-1695` | `PreElect`; follower, single-voter, and Candidate-context rounds collected |
| `HandlePreVoteRequest` (update) | `openraft/src/engine/engine_impl.rs:406-447` `handle_pre_vote_req()`; reply `raft_core.rs:1551-1562` (`when: None`) | `HandlePreVoteRequest`; grant, lease reject, log reject, empty-log grant collected; post-state must equal pre-state |
| `HandlePreVoteResponse{Elect,Tally,Reject,Stale}` (update) | `openraft/src/engine/engine_impl.rs:511-554` `handle_pre_vote_resp()` after `raft_core.rs:1803-1820` filter | `HandlePreVoteResponse`; quorum->elect, greater-log reject, and the post-establishment quorum collected; `Tally`/`Stale` model-checked only |

## 3. Special considerations

- Instrumentation exists only under `#[cfg(test)]` and changes no production code path.
- Each scenario runs in its own test process and output file, so append-only `OpenOptions` does not require a cross-thread writer lock. The harness runner deletes only its named generated trace files before a fresh batch.
- Engine commands describe submitted work, not completed durability. The trace therefore records `SaveVote` and `AppendEntries` as pending flags. `Trace.tla` initializes durable shadows from each explicit pre-state and checks the projected transition at this atomic boundary.
- `candidate_config` is captured through the effective membership because the exact-old candidate quorum field is private. Every candidate trace freezes that same config and performs no intervening membership mutation. The TLA+ state keeps the frozen copy independently after initialization.
- The restart pre-state uses `crashed=true` as boundary metadata; exact-old `Engine` itself has no crashed field. The post-state is the direct result of `startup()`.
- `ServerState::Shutdown` is outside the bound and is conservatively serialized as `Follower`; no current harness scenario enters it.


## 4. Update instrumentation (Pre-Vote revision)

- Trigger points are the engine boundaries of the new methods; the runtime's `SendPreVote` execution and correlation filter are represented as documented above. Multi-event traces (`pre_candidate_cleared_by_vote`, `pre_vote_after_establish`) do not drain the engine command queue between events, so the pending-command flags of every event are the accumulated, not-yet-completed commands; no model completion action (`PersistVote`, `FlushLog`) runs between those events.
- `pre_vote_after_establish` is the producer -> affected -> old consumer -> affected interaction: `PreElect` while Candidate, `HandleVoteResponse` (wins; the round survives), `HandlePreVoteResponse` (quorum -> `elect()` from the Leader).
- Every mandatory field is compared by an active `Trace.tla` predicate (`ValidatePost`, `TracePreElect`, `TraceHandlePreVoteRequest`); six targeted field mutations are rejected (`spec/evidence/trace-mutations/summary.txt`).
