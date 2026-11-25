# Instrumentation specification (updated for the Pre-Vote revision)

Category A, single-file linear traces, one focus node per scenario. The
harness is test-only (`#[cfg(test)]` module `engine::tests::specula_trace_test`)
and drives real `Engine` methods; it changes no production code path.

## 1. Trace event schema

Envelope (one NDJSON line per engine invocation):

```json
{"tag":"trace","ts_unix_ns":"...","event":{"name":"...","nid":"1","pre":{},"post":{},"args":{}}}
```

`ts_unix_ns` is a fresh wall-clock timestamp (string). Node IDs are strings in
the TLA+ `Server` domain. A file may contain several events for the same
focus node. The first event's `pre` seeds `TraceInit`; every later event's
`pre` is compared with the model state before its action (`Trace!ValidatePre`).
Between two events the harness executes the queued engine commands as
`RaftCore::run_command` would (drop `SaveVote` = vote persisted, `SendVote` =
requests spawned, `AppendEntries` = log flushed); `Trace.tla` replays those
with the silent `PersistVote`, `SendVoteRequest`/`FinishVoteBroadcast`, and
`FlushLog` steps, each enabled only when the next `pre` shows the flag
cleared.

State fields (captured in `pre` and `post` by `state_json`):

| JSON field | Source observation | TLA+ state |
|---|---|---|
| `role` | `eng.state.server_state` | `role[nid]` |
| `vote.{term,node,committed}` | `eng.state.vote_ref()` | `vote[nid]` |
| `last_log` | `LogStateReader::last_log_id()` | `lastLog[nid]` |
| `committed_config`, `committed_config_index` | `membership_state.committed()` | `committedConfig`, `committedConfigIndex` |
| `effective_config`, `effective_config_index` | `membership_state.effective()` | `effectiveConfig`, `effectiveConfigIndex` |
| `lease_valid` | `Leased::lease_info()` / `is_expired(now, 0)` | `leaseValid` |
| `candidate_active`, `candidate_vote`, `grants` | `candidate_ref()`, `vote_ref()`, `granters()` | `candidateActive`, `candidateVote`, `grants` |
| `candidate_config` | **updated**: real frozen quorum set `candidate.progress().quorum_set().get_joint_config()`; effective config when no candidate | `candidateConfig` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
| `seen_greater_log` | **updated**: `eng.is_there_greater_log()` (V0 hard-coded `false`) | `seenGreaterLog` |
| `crashed` | harness boundary metadata around `startup()` | `crashed` |
| `pre_candidate_active` | **new**: `pre_candidate_ref().is_some()` | `preCandidateActive` |
| `pre_candidate_vote` | **new**: `pre_candidate.vote_ref()` | `preCandidateVote` (checked when active) |
| `pre_grants` | **new**: `pre_candidate.granters()` | `preGrants` (checked when active) |
| `pre_candidate_config` | **new**: `pre_candidate.progress().quorum_set().get_joint_config()` | `preCandidateConfig` (checked when active) |
| `send_pre_vote_pending` | **new**: queued `CommandName::SendPreVote` | compared with "this event added PreVoteReq messages from nid" |

`preRoundFromLeader` is a model history variable and is not captured.

## 2. Action-to-code mapping

| Spec action | Code location / trigger | Event name / args | Status |
|---|---|---|---|
| `StartElection` | `engine/engine_impl.rs:249-289`, around `elect()` | `StartElection` `{transfer}` | regression + update traces |
| `TickPreVote` / `ExternalPreElect` (`PreElect`) | `engine/engine_impl.rs:291-322`, around `pre_elect()`; tick form also calls `reset_greater_log()` first (`core/raft_core.rs:2027-2032`) | `StartPreVote` `{trigger: "tick"|"external", req_vote, req_last_log}` (request content read from the queued `SendPreVote`) | new |
| `HandlePreVoteRequest` | `engine/engine_impl.rs:406-447`, around `handle_pre_vote_req()` | `HandlePreVoteRequest` `{source, vote, last_log, response_vote, response_last_log, response_granted}` | new |
| `HandlePreVoteResponse{Ignored,Grant,Elect,Reject}` | `engine/engine_impl.rs:512-554`, around `handle_pre_vote_resp()`; the harness passes only responses the runtime filter (`core/raft_core.rs:1803-1820`) would deliver, i.e. `candidate_vote` = the round's probe | `HandlePreVoteResponse` `{source, vote, last_log, granted, candidate_vote}` | new |
| `HandleVoteRequest` | `engine/engine_impl.rs:350-404` | `HandleVoteRequest` `{source, vote, last_log, transfer, response_vote, response_granted}` | regression + U4 |
| `HandleVoteResponse` | `engine/engine_impl.rs:449-510` | `HandleVoteResponse` `{source, vote, last_log, granted}` | regression + U2 |
| `HandleAppendEntries` | `engine/engine_impl.rs:586-600`, around `append_entries()` with an empty segment at the local last log (heartbeat) | `HandleAppendEntries` `{source, vote, prev_log}` | new (U4) |
| `PersistVote` | `core/raft_core.rs:2273-2304`: harness drops `SaveVote`, then feeds the runtime's local `VoteResponse(vote, None, true)` as a `HandleVoteResponse` event when a candidate exists | silent in `Trace.tla` | between events |
| `SendVoteRequest`, `FinishVoteBroadcast` | `core/raft_core.rs:2339-2341` (`SendVote`) | silent | between events |
| `FlushLog` | storage append callback | silent | between events |
| `AppendJointConfig`, `CommitMembership`, `Restart` | unchanged from V0 | unchanged | regression |
| `DefaultPreVoteRpcGrant` | `network/v2/network.rs:158-161` (network, not engine) | model-checking only | — |
| `AppendUniformConfig`, `SendAppendEntries`, `RefreshServerState`, `ExpireLease`, `DropMessage`, `Crash` | unchanged from V0 | model-checking only | — |

## 3. Special considerations

- The runtime glue between events (command execution, local self-vote
  response) is reproduced in the harness exactly as `run_command` does it and
  is documented per scenario; the engine state is always read from the real
  engine.
- `HandlePreVoteResponse` events bypass `RaftCore`'s notification filter by
  construction; the harness only delivers responses whose `candidate_vote`
  equals the current probe, mirroring `does_pre_candidate_vote_match`.
- `pre_candidate_config`/`candidate_config` use the real frozen quorum set
  (`Progress::quorum_set`), not the effective config proxy used by V0.
- `ServerState::Shutdown` is serialized as `Follower`; no scenario enters it.
- Mandatory update fields (`pre_candidate_*`, `pre_grants`,
  `send_pre_vote_pending`, real `seen_greater_log`) are required by
  `Trace!StateMatches`/`ValidatePost`; archived V0 traces lack them and are
  superseded by fresh regenerations of the same scenarios.
