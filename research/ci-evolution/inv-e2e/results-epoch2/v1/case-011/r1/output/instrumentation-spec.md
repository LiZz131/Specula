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

## 4. Incremental revision (Pre-Vote) — rebased harness

Harness source: `harness/src/specula_trace_test.rs` (applied by
`harness/instrumentation.patch` to `work-source/`, a copy of `artifact/` at
`3ab6cdd`). The V0 patch (`harness/instrumentation-v0.patch`) failed only on
`openraft/src/engine/mod.rs` context drift (new `pre_elect_test` etc. modules);
the trace module itself was reused and extended.

### 4.1 New/changed state fields (mandatory in every event, pre and post)

| JSON field | Source observation | TLA+ state | Checked by |
|---|---|---|---|
| `pre_candidate_active` | `Engine::pre_candidate_ref().is_some()` | `preActive` | `ValidatePost`, `ValidatePre`, `TraceInit` |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` | `preVote` | same (when active) |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` | same (when active) |
| `pre_candidate_config` | `pre_candidate.progress().quorum_set().get_joint_config()` (real frozen quorum) | `preConfig` | `ValidatePost`, `TraceInit` |
| `candidate_config` | now the real frozen candidate quorum (V0 used the effective config as a proxy) | `candidateConfig` | unchanged checks |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | new `PreVoteReq` from the node in this step | `ValidatePost` |
| `append_behind_vote` | queued `AppendEntries` after a queued `SaveVote` (FIFO order) | `appendBehindVote` (R-2) | `ValidatePost`, `ValidatePre`, `TraceInit` |
| `seen_greater_log` | `Engine::is_there_greater_log()` (V0 hard-coded `false`) | `seenGreaterLog` | unchanged checks |

### 4.2 New/changed events

| Event | Code location / trigger | Args | Trace wrapper |
|---|---|---|---|
| `PreElect` | around `Engine::pre_elect()` (`engine_impl.rs:297-322`) | `send_pre_vote {present, vote, last_log}`, `send_vote {...}` captured from the queued commands | `TracePreElect` → `base!PreElect`; checks every `PreVoteReq` to each other voter |
| `HandlePreVoteRequest` | around `Engine::handle_pre_vote_req()` (`engine_impl.rs:414-447`) | `source, vote, last_log, transfer, response_vote, response_granted, response_last_log` | `TraceHandlePreVoteRequest` → `base!HandlePreVoteRequest`; checks the exact `PreVoteResp` |
| `HandlePreVoteResponse` | around `Engine::handle_pre_vote_resp()` (`engine_impl.rs:516-554`) | `source, vote, last_log, granted, round` (`round` = `candidate_vote` that `raft_core.rs:1803-1820` correlates on) | `TraceHandlePreVoteResponse` → `base!HandlePreVoteResponse` |
| `HandleAppendEntries` | around `Engine::append_entries()` (`engine_impl.rs:586-602`) | `source, vote, last_log, ok` | `TraceHandleAppendEntries` → `base!HandleAppendEntries` (R-1) |
| `StartElection`, `HandleVoteRequest`, `HandleVoteResponse` | unchanged; update scenarios add `send_vote` | as V0 | as V0 + `SendVoteMatches` |

### 4.3 Multi-event capture and runtime completion

Update scenarios are multi-event on one node. After each captured transition
the harness drains the engine output, as `RaftCore::run_engine_commands` does
(`save_vote` awaited, `SendVote`/`SendPreVote` dispatched, `AppendEntries`
submitted and flushed; `raft_core.rs:2265-2344`). The next event's pre-state is
therefore checked by `ValidatePre`, and `Trace.tla` reaches it with silent
`PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast`, `FlushLog` steps that
are enabled only while the model still has that command pending and the next
captured pre-state shows it completed. The self vote response that the
runtime emits after `SaveVote` (`raft_core.rs:2292-2300`) is captured as a
`HandleVoteResponse` event with `source = self`.

### 4.4 Scenario inventory (fresh, new version)

| Trace | Events | Actions exercised | Scenario |
|---|---|---|---|
| `start_election`, `reject_stale_log`, `grant_greater_vote`, `establish_leader`, `append_joint_membership`, `commit_membership`, `restart_follower` | 1 each | V0 regression set (setups unchanged) | V0 1–5 |
| `grant_empty_logs` | 2 | HandlePreVoteRequest(grant), HandleVoteRequest(strict grant) between empty logs | repair R-5 |
| `prevote_quorum_elect` | 2 | PreElect, HandlePreVoteResponse(wins)→DoElect | U-S1 |
| `prevote_reject_higher_vote` | 3 | PreElect, HandlePreVoteResponse(reject, higher vote), PreElect | U-S2 |
| `prevote_request_branches` | 3 | HandlePreVoteRequest: reject by vote, reject by log, grant | U-S2, U-S5 |
| `prevote_request_lease` | 1 | HandlePreVoteRequest: reject by lease | U-S5 |
| `candidate_prevote_then_establish` | 5 | StartElection, HandleVoteResponse(self), PreElect, HandleVoteResponse(wins), HandlePreVoteResponse(wins on a Leader) + silent PersistVote/SendVoteRequest/FinishVoteBroadcast/FlushLog | U-S3 |
| `prevote_cleared_by_append` | 2 | PreElect, HandleAppendEntries (clears pre-candidate, adopts log) | U-S4, R-1 |
| `prevote_cleared_by_vote_grant` | 2 | PreElect, HandleVoteRequest(strict grant, clears) | U-S4 |
| `prevote_single_voter` | 1 | PreElect self-quorum → DoElect | U-S1 |

Not traced (model-checked only): `TickElect` runtime wrapper (timing),
`ExternalPreElect` (runtime voter check + `PreElect`), `RefreshServerState`,
`Crash`, `DropMessage`, `ExpireLease`, `SendAppendEntries`, uniform membership
append. The runtime correlation filter (`does_pre_candidate_vote_match`) is
not exercised by the engine-level harness; traces always carry the matching
`round`.

### 4.5 Code observations (not traces)

`harness/src/specula_observation_test.rs` (same patch) drives the real Engine
handlers of several nodes in-process for the model-checking findings:
`specula_observe_prevote_livelock`, `specula_observe_old_path_recovers`,
`specula_observe_leader_demoted_by_stale_prevote`. Run with
`harness/run-observations.sh`; output `spec/output/observations.log`.
