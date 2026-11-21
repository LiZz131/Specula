# Instrumentation specification

## 1. Trace event schema

The harness writes one NDJSON object per exact-old `Engine` invocation. The outer envelope is:

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
| `candidate_config` | effective config at candidate construction in these non-mutating election fixtures | `candidateConfig` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `lease_valid` | `Leased::lease_info()` and `is_expired()` | `leaseValid` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
| `crashed` | harness boundary metadata for a reconstructed engine before/after `startup()` | `crashed` |

Vote request arguments include `source`, request `vote`, `last_log`, `transfer`, and the returned `response_vote`/`response_granted`. Vote response arguments include `source`, `vote`, `last_log`, and `granted`. Membership append arguments include `target_config`.

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
| `Restart` | `openraft/src/engine/engine_impl.rs:136-181`, snapshot immediately around `startup()` on reconstructed durable state | `Restart`; follower reconstruction collected |

## 3. Special considerations

- Instrumentation exists only under `#[cfg(test)]` and changes no production code path.
- Each scenario runs in its own test process and output file, so append-only `OpenOptions` does not require a cross-thread writer lock. The harness runner deletes only its named generated trace files before a fresh batch.
- Engine commands describe submitted work, not completed durability. The trace therefore records `SaveVote` and `AppendEntries` as pending flags. `Trace.tla` initializes durable shadows from each explicit pre-state and checks the projected transition at this atomic boundary.
- `candidate_config` is captured through the effective membership because the exact-old candidate quorum field is private. Every candidate trace freezes that same config and performs no intervening membership mutation. The TLA+ state keeps the frozen copy independently after initialization.
- The restart pre-state uses `crashed=true` as boundary metadata; exact-old `Engine` itself has no crashed field. The post-state is the direct result of `startup()`.
- `ServerState::Shutdown` is outside the bound and is conservatively serialized as `Follower`; no current harness scenario enters it.


---

# V1 (Pre-Vote update) instrumentation additions

Harness: `harness/src/specula_trace_test.rs`, applied by
`harness/instrumentation.patch` (test-only; `#[cfg(test)]` module under
`openraft/src/engine/tests/`). Every record is one real `Engine` invocation of
the focus node `nid` with full `pre` and `post` snapshots. Multi-event traces
drain the command queue before each event, exactly as RaftCore runs all
commands of an event before the next event; `Trace.tla` replays the runtime
completions between events as guarded silent steps (`SilentRuntime`).

## New/changed state fields (all events)

| JSON field | Source observation | TLA+ state | Check |
|---|---|---|---|
| `pre_candidate_active` | `Engine::pre_candidate_ref().is_some()` (`engine_impl.rs:340-342`) | `preCandidateActive` | pre and post, always |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` | `preCandidateVote` | when active |
| `pre_candidate_last_log` | `pre_candidate.last_log_id()` | `preCandidateLastLog` | when active |
| `pre_candidate_config` | effective membership (frozen copy equal in all scenarios; quorum set is private) | `preCandidateConfig` | when active |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` | when active |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | `sendPreVotePending` | pre and post |
| `seen_greater_log` | `Engine.seen_greater_log` (V0 emitted constant `false`) | `seenGreaterLog` | pre and post |

## New events

| Event | Engine call / trigger | Args | Trace wrapper |
|---|---|---|---|
| `PreElect` | `Engine::pre_elect()` (`engine_impl.rs:298-322`); tick/`Elect{pre_vote:true}` caller | – | `TracePreElect` → `PreElect(nid, FALSE)` |
| `HandlePreVoteRequest` | `Engine::handle_pre_vote_req(req)` (`engine_impl.rs:414-447`) | `source`, `vote`, `last_log`, `response_vote`, `response_last_log`, `response_granted`, `commands_emitted` | `TraceHandlePreVoteRequest`; `PreVoteResponseMatches` compares granted bit, responder vote and last log, and the emitted `PreVoteResp` |
| `HandlePreVoteResponse` | runtime correlation (`raft_core.rs:1815-1816`, reproduced in the harness as `forwarded_by_runtime`) then `Engine::handle_pre_vote_resp` (`engine_impl.rs:516-554`) | `source`, `candidate_vote` (request vote carried by the notification), `vote` (responder vote, informational), `last_log`, `granted`, `forwarded_by_runtime` | `TraceHandlePreVoteResponse` |
| `HandleAppendEntries` | `Engine::append_entries(vote, LogSegment(prev, []))` (`engine_impl.rs:586-600`) | `source`, `vote`, `prev_log`, `accepted` | `TraceHandleAppendEntries` |

`StartElection`, `HandleVoteRequest`, `HandleVoteResponse`,
`AppendJointConfig`, `CommitMembership`, `Restart` are unchanged in name and
arguments. Every event is now checked against its pre-state
(`ValidatePre`) as well as its post-state (`ValidatePost`).

## Silent runtime completions (Trace.tla `SilentRuntime`)

Enabled only while the next record's pre-state shows the corresponding work
as completed: `PersistVote` (`save_vote_pending`), `FlushLog`
(`append_pending`), `SendVoteRequest`/`FinishVoteBroadcast`
(`send_vote_pending`), `SendPreVoteRequest`/`FinishPreVoteBroadcast`
(`send_pre_vote_pending`), `ExpireLease` (`lease_valid`).

## Observation side file

`traces/<case>.ndjson.observation.json` records non-transition observations
(currently: whether `try_leader_handler()` trips its debug assertion after
the U-S4 sequence). It is evidence, not trace input.
