# Instrumentation specification (updated for `update` d7176ef9, RaftMsg::TransferLeader)

## Event envelope

Every line is one JSON object:

```text
{"tag":"trace","ts":<unix-nanoseconds>,"event":{"name":<action>,"node":<u64>,"args":{...},"state":{...}}}
```

`ts` is a real monotonic-in-file observation timestamp; TLA+ does not use it. A file begins with
`Bootstrap`, which captures the pre-state of the traced node and is consumed by `TraceInit`; each
later line is the post-state after one named real synchronous step.

Two observation layers produce the same envelope and state record:

1. **Engine unit layer** (prior V0 harness, rebased): `openraft/src/engine/specula_trace_tests.rs`
   drives production `Engine` methods directly; one file per scenario.
2. **RaftCore window layer** (new for the update): `openraft/src/specula_trace.rs` (compiled only with
   the cargo feature `specula-trace`) is called from `RaftCore` around the real event-loop steps of a
   live multi-node cluster (`tests` crate, memstore). Each observed step writes its own *window* file
   `<label>-n<node>-<seq>.ndjson` holding `Bootstrap` (state immediately before the step) and the step
   event (state immediately after it, before `run_engine_commands`). Commands in a window are only
   those pushed by the observed step (the Engine output queue length is recorded before the step and
   only the suffix is reported); the Bootstrap line reports `commands: []`.

## Captured state (all events, both layers)

- `node_id`
- `vote_term`, `vote_node`, `vote_committed` (in-memory `engine.state.vote`)
- `last_seen_term`, `last_seen_node`, `last_seen_committed`
- `role`: `Learner`, `Follower`, `Candidate`, or `Leader` (`engine.state.server_state`)
- `logs`: ordered `{term,node,index}` log ids from `LogIdList`
- `last_index` and `commit_index` (`-1` means absent)
- `effective_index`, `committed_membership_index` (`-1` means absent)
- `effective_configs`: ordered JSON arrays, one per voter child
- `learners`
- `candidate`, `granters`, `leader`
- **new:** `candidate_last_term`, `candidate_last_node`, `candidate_last_index`: the candidate's
  snapshotted `last_log_id` (`0/0/-1` when no candidate). Checked whenever `candidate` is true.
- `matches`: peer-to-matching-index records (`-1` means absent)
- `accepted_index`: last accepted log I/O index, or `-1`
- `commands`: set of command kinds pushed by the observed step

Every listed field has a check in `Trace.tla::ValidatePostState`.

## Action mapping

| Trace action | Real call | Layer | Reference action |
|---|---|---|---|
| `Elect` | `Engine::elect` | unit | `Elect` (Engine boundary, no guard) |
| `TransferLeader` | `RaftCore::handle_api_msg(RaftMsg::TransferLeader)` (`core/raft_core.rs:1190-1202`) | window | `HandleTransferLeader` (elect / lease-only / ignored) |
| `VoteRequest` | `Engine::handle_vote_req` (unit) / `RaftCore::handle_vote_request` engine call (window) | both | `ReceiveVoteRequest` or `RejectVoteRequest` |
| `VoteResponse` | `Engine::handle_vote_resp` (unit) / `Notification::VoteResponse` after `does_vote_match` (window) | both | `ReceiveVoteResponse` |
| `VoteResponsePanic` | panic inside `Engine::handle_vote_resp` (`grant_by` `.expect`), pre-state only | both | `CoreVoteResponsePanic` |
| `FollowerAppend` | `Engine::append_entries` | unit | `ReceiveAppend` |
| `LeaderAppend` | `LeaderHandler::leader_append_entries` | unit | `LeaderAppend` |
| `AckReplication` | `ReplicationHandler::update_matching` | unit | `AcknowledgeReplication` |
| `Startup` | `Engine::startup` | unit | `RestartFromRecovered` |

### Arguments

- `TransferLeader`: `from_term`, `from_node`, `from_committed`, `to` (the real message fields).
- `VoteRequest`: `candidate`, `term`, `committed`, **`last_term`, `last_node`**, `last_index` (the
  real request's vote and full `last_log_id`; repair R1 requires the full LogId).
- `VoteResponse`: `peer`, `term`, `owner`, `committed` (the response vote).
- `FollowerAppend`: `owner`, `term`, `prev`, **`entries`**: `[{term,node,index,kind,configs,learners}]`
  where `kind` is `blank`, `normal` or `membership` (repair R3 replays the real entries).
- `LeaderAppend`: `kind`, `configs`, `learners`.
- `AckReplication`: `peer`, `index`.

## Placement and synchronization

- Unit layer: `#[cfg(test)]` module; serial scenarios; one explicit file per test via
  `SPECULA_TRACE_FILE`.
- Window layer: feature-gated (`specula-trace`), active only if `SPECULA_TRACE_DIR` is set. The capture
  runs on the single RaftCore task that owns the Engine, synchronously before/after the observed step,
  so there is no concurrent mutation of the captured state. A process-global atomic sequence number
  makes window file names unique; each file is written and flushed completely by one call.
- RaftCore window points (labels `transfer-elect`, `transfer-lease`, `transfer-ignored`,
  `vote-request`, `vote-response`): `TransferLeader` branch (all three outcomes); `handle_vote_request`
  (peer side of the transfer target's election); `Notification::VoteResponse` (target side, including
  the local self-grant and leader establishment). Window capture for vote request/response starts after the first
  `TransferLeader` message in the process (global arm flag set by the first TransferLeader window;
  `SPECULA_TRACE_WINDOW_ALL=1` disables the filter). A vote-response window is first written as
  `VoteResponsePanic` (pre-state) and overwritten with the real post-state when
  `Engine::handle_vote_resp` returns, so a file left as `VoteResponsePanic` records a real panic.
