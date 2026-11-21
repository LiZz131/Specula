# Instrumentation specification — exact-old Openraft replication

## 1. Trace event schema

Category A single-file NDJSON. Every line is emitted by running instrumented real
code and has a real epoch-nanosecond timestamp:

```json
{"tag":"trace","ts":"<epoch-nanos>","event":{"name":"<Action>","nid":"<leader-or-node>","target":"<target>","session":"<display session>","msg":{...},"state":{...}}}
```

`SPECULA_TRACE_FILE` selects the file. `SPECULA_TRACE_TARGET` optionally restricts
events to one display-form target, reducing unrelated cluster interleavings without
altering protocol execution. Node IDs and sessions are strings; log IDs are reduced
to indexes with `-1` for `None`.

State fields are event-specific so every captured value is checked by `Trace.tla`:

- Worker: `active`, `local_commit`, `remote_match`, `pending_kind`, `pending_prev`,
  `pending_last`, `pending_inflight`, `rpc_pending`, `sent_kind`, `sent_prev`,
  `sent_last`, `sent_inflight`, `backoff_active`, `waiting`, `last_outcome`.
- Core: `core_match`, `core_searching_end`, `core_inflight_kind`,
  `core_inflight_id`, `core_inflight_prev`, `core_inflight_last`.
- Counters: `attempt_count`, `wait_count`, `partial_count`,
  `snapshot_attempt_count`, `snapshot_wait_count`.
- Stream/snapshot: `stream_stopped`, `last_stream_outcome`, `snapshot_active`,
  `snapshot_backoff`.

The counters are instrumentation-only observations and never feed protocol control
flow; they only select emitted values when tracing is enabled.

## 2. Action-to-code mapping

### `TaskSpawn`

- Code: `openraft/src/replication/mod.rs:123-180`
- Trigger: after the worker state is constructed and immediately before spawn.
- Message: none.
- State: `active=true`, copied local commit/remote match, copied core match.
- TLA+: `SpawnReplication`.

### `ReceiveLogs`

- Code: `openraft/src/replication/mod.rs:594-625`
- Trigger: after `Replicate::Data` replaces `next_action`.
- Message: logical `prev`, `last`, `inflight`.
- State: complete pending action fields.
- TLA+: `ReceiveLogs`.

### `ReceiveCommitted`

- Code: `openraft/src/replication/mod.rs:598-613`
- Trigger: after cached commit and optional commit-only action update.
- Message: `committed`.
- State: local commit plus complete pending fields.
- TLA+: `ReceiveCommitted`.

### `SendAppend`

- Code: `openraft/src/replication/mod.rs:304-365`
- Trigger: after actual prefix read and request construction, immediately before the
  awaited network call.
- Message: actual physical `last`.
- State: active RPC, sent range/kind/id, incremented attempt count.
- TLA+: `SendAppend`.

### `AppendSuccess`

- Code: `openraft/src/replication/mod.rs:387-399`
- Trigger: after heartbeat/progress enqueue and remainder calculation.
- Message: none; the matching endpoint is validated from captured worker state.
- State: inactive RPC, worker matching, complete pending fields, `last_outcome`.
- TLA+: `AppendSuccess`.

### `AppendPartial`

- Code: `openraft/src/replication/mod.rs:400-410,629-668`
- Trigger: after progress enqueue and remainder calculation.
- Message: returned matching index.
- State: inactive RPC, worker matching, complete pending fields, outcome, incremented
  partial count.
- TLA+: `AppendPartial`.

### `AppendConflict`

- Code: `openraft/src/replication/mod.rs:426-439`
- Trigger: after heartbeat and conflict progress are enqueued.
- Message: none; the model uses the already captured sent previous index.
- State: inactive RPC and conflict outcome.
- TLA+: `AppendConflict`.

### `AppendHigherVote`

- Code: `openraft/src/replication/mod.rs:226-241,412-425`
- Trigger: at terminal higher-vote handling after the notification is sent.
- Message: outcome only; vote payload is excluded from the replication-progress model.
- State: `active=false`, inactive RPC, higher outcome.
- TLA+: `AppendHigherVote`.

### `AppendRpcError`

- Code: `openraft/src/replication/mod.rs:248-270`
- Trigger: after error classification/backoff initialization and optional payload
  progress enqueue.
- Message: `error_kind` in `timeout|unreachable|network|remote`.
- State: inactive RPC, backoff-active state, outcome.
- TLA+: `AppendRpcError`.

### `BackoffReset`

- Code: `openraft/src/replication/mod.rs:218-222`
- Trigger: after a successful protocol-reply cycle clears a previously active backoff.
- State: `backoff_active=false`.
- TLA+: `ResetBackoffAfterReply`.

### `BackoffBegin` / `BackoffEnd`

- Code: `openraft/src/replication/mod.rs:280-290,516-549`
- Trigger: immediately after consuming a duration / when the wait future expires.
- Message: `delay_ms` on begin.
- State: waiting flag and incremented `wait_count` on begin; cleared flag on end.
- TLA+: `BeginBackoff` / `EndBackoff`.

### Unlogged `CoreHandleProgress`

- Code: `openraft/src/core/raft_core.rs:1565-1574,1746-1767`.
- Rationale: a core hook after the awaited channel send can race with the worker's
  response hook and would not give a stable single-file order.
- Replay: every response action appends the exact modeled notification, and
  `Trace.tla` eagerly executes the exact single-threaded `CoreHandleProgress`
  transition without consuming a trace line before processing the next observation.
- Limitation: real core post-state is not directly captured; session-drop semantics
  are covered by bounded model checking and a dedicated reachability witness.

### `SnapshotStart`

- Code: `openraft/src/replication/snapshot_transmitter.rs:69-94`
- Trigger: after transmitter construction and immediately before task spawn.
- Message: snapshot inflight ID.
- State: active snapshot and authoritative snapshot inflight.
- TLA+: `StartSnapshot`.

### `SnapshotAttempt`

- Code: `openraft/src/replication/snapshot_transmitter.rs:91-100`
- Trigger: immediately before `read_and_send_snapshot`.
- State: incremented snapshot attempt count.
- TLA+: `BeginSnapshotAttempt`.

### `SnapshotRpcError`

- Code: `openraft/src/replication/snapshot_transmitter.rs:134-147`
- Trigger: after exact error-specific snapshot backoff update.
- Message: error class.
- State: snapshot backoff state.
- TLA+: `SnapshotRpcError`.

### `SnapshotBackoff`

- Code: `openraft/src/replication/snapshot_transmitter.rs:149-167`
- Trigger: after consuming a snapshot backoff duration.
- Message: delay in ms.
- State: incremented snapshot wait count.
- TLA+: `BeginSnapshotBackoff`.

### `SnapshotSuccess`

- Code: `openraft/src/replication/snapshot_transmitter.rs:199-227`
- Trigger: after completed install and both progress sends, immediately before return.
- Message: snapshot metadata matching index.
- State: transmitter inactive and snapshot backoff cleared.
- TLA+: `SnapshotSuccess`.

### `TaskClose`

- Code: `openraft/src/replication/mod.rs` main-loop drain error paths.
- Trigger: when the worker observes its event channel close.
- State: worker inactive.
- TLA+: `CloseTask`.

### `StreamEnqueue`

- Code: `openraft/src/raft/stream_append.rs:52-71`
- Trigger: after AppendEntries is submitted to RaftCore and before its response receiver
  is sent to the ordered output queue.
- Message: request range.
- State: none; the base action and later head-match validate ordering.
- TLA+: `StreamEnqueue`.

### `StreamResult`

- Code: `openraft/src/raft/stream_append.rs:74-86`
- Trigger: after response conversion and terminal decision.
- Message: outcome and returned/conflict index.
- State: stream terminal flag and last output outcome.
- TLA+: `StreamResult`.

## 3. Special considerations

- The trace writer is a mutex-protected process-global file. Category A RPC/storage
  operations are async and much slower than the probe; the target filter prevents
  irrelevant worker contention in collected files.
- `AppendSuccess/Partial/Conflict` precede the main loop's backoff reset in code.
  `BackoffReset` is emitted separately and only when a backoff was active.
- Core progress can originate from log or snapshot workers in this suite. Replay
  never invents a notification: only a modeled producer action appends one, and the
  internal core step consumes the queue head.
- Stream queue length is not read from the asynchronous channel. Replay checks queue
  mutation through ordered range preconditions and validates the terminal state; this
  is the one documented weak capture.
- The neutral snapshot-success run reached start, attempt, success, and subsequent
  incremental log continuation. Snapshot transport-error/backoff probes remain
  unreached and are reported as a trace-coverage limitation.
