# Modeling Brief — Openraft exact-old replication prior

## 1. System overview

Openraft is a Rust Raft implementation. This prior covers about 4.6 KLOC of selected
replication, progress, notification, RPC, snapshot, and neutral-test code. It is a
Category A distributed/message-passing subsystem: RaftCore reserves work, one async
log-replication task runs per target, and a separate task transmits snapshots. The
modeled implementation is exactly `/work/source`; no history or comparison revision
was consulted. A session is the pair of committed leader vote and effective
membership-log ID (`openraft/src/replication/replication_session_id.rs:10-29`).
RaftCore is the authoritative owner of `ProgressEntry`; workers cache committed and
matching positions and report results asynchronously (`openraft/src/replication/mod.rs:83-111`).

## 2. Neutral scenarios

### Scenario 1: Single-inflight log replication and partial continuation

**Mechanism**: RaftCore reserves one range and ID, while the worker may transmit and
acknowledge that range in several prefixes without allocating a new ID.

**Evidence**:

- `ProgressEntry::next_send` refuses a second authoritative inflight and chooses a
  bounded log range (`openraft/src/progress/entry/mod.rs:104-164`).
- A physical read may return a prefix of the logical range
  (`openraft/src/replication/mod.rs:307-342`).
- `Success` and `PartialSuccess` advance worker matching; an unfinished remainder is
  installed as `next_action` with the same inflight ID
  (`openraft/src/replication/mod.rs:387-410,629-668`).

**Affected paths**: `next_send`, `send_to_target`, `process_event`,
`send_log_entries`, `notify_progress`, `update_next_action_to_send`.

**Modeling**: Distinguish authoritative core inflight, worker pending work, active
RPC, sent range, and worker matching. Split receive, send, response, notification,
and core-apply actions at real async/channel boundaries.

**Priority**: High — it is the main normal replication path and is exercised by the
partial-success test.

### Scenario 2: Outcome-classified retry and backoff work folding

**Mechanism**: A payload transport error is returned to RaftCore for fresh work
selection; an `Unreachable` additionally activates the worker's old retry iterator.

**Evidence**:

- Payload errors notify RaftCore; commit-only errors do not
  (`openraft/src/replication/mod.rs:248-270,444-459`).
- RaftCore clears authoritative inflight on an error and routine processing selects
  work again (`openraft/src/engine/handler/replication_handler/mod.rs:275-290`;
  `openraft/src/core/raft_core.rs:738-763`).
- Only `Unreachable` initializes backoff. Once active it survives later timeout,
  network, or remote errors; any protocol reply clears it
  (`openraft/src/replication/mod.rs:218-263`).
- During the wait, events are received and folded but no RPC is sent
  (`openraft/src/replication/mod.rs:516-549`).

**Affected paths**: `main`, `drain_events_with_backoff`, `backoff_drain_events`,
`update_progress`, `trigger_routine_actions`.

**Modeling**: Track `backoffActive`, `waiting`, attempts, wait steps, and event
receipt independently. Delay expiry is nondeterministic; no elapsed-time guarantee
is asserted.

**Priority**: High — it defines exact-old retry behavior and the quantitative
secondary observation boundary.

### Scenario 3: Session filtering and request-level inflight identity

**Mechanism**: Session identity rejects obsolete leader/membership notifications;
inflight identity has a narrower role inside current-session progress updates.

**Evidence**:

- Replication/heartbeat progress is accepted only when both leader vote and
  membership-log ID match current state (`openraft/src/core/raft_core.rs:1565-1592,1746-1767`).
- Inflight mismatch leaves the nested `Inflight` value unchanged
  (`openraft/src/progress/inflight/mod.rs:127-185`).
- Matching/search updates occur outside that nested check, and an outer transport
  error clears current inflight (`openraft/src/progress/entry/update.rs:40-115`;
  `openraft/src/engine/handler/replication_handler/mod.rs:284-290`).

**Affected paths**: `does_replication_session_match`, `update_progress`,
`Updater::update_matching`, `Updater::update_conflicting`, `Inflight::ack/conflict`.

**Modeling**: Give notifications explicit session and inflight fields. Model session
drop atomically with the single-threaded core handler. Do not elevate inflight ID to
a whole-message guard that the exact-old code does not implement.

**Priority**: High — it is the stale-notification boundary.

### Scenario 4: Snapshot handoff at the progress boundary

**Mechanism**: Core selects snapshot when needed logs are purged, while an independent
snapshot task owns retry and later acknowledges the same authoritative inflight ID.

**Evidence**:

- Snapshot is reserved when `searching_end < purge_upto.next_index()`
  (`openraft/src/progress/entry/mod.rs:129-142`).
- Runtime creates a separate reader, network client, task context, and cancel handle
  (`openraft/src/core/raft_core.rs:1954-1973`).
- Snapshot success follows completed installation, sends heartbeat progress, then
  matching progress (`openraft/src/replication/snapshot_transmitter.rs:199-265`).
- Snapshot retry clears backoff for timeout/network/remote errors, unlike the log
  worker (`openraft/src/replication/snapshot_transmitter.rs:91-169`).

**Affected paths**: `next_send`, `ReplicateSnapshot`, `SnapshotTransmitter::spawn`,
`stream_snapshot`, `send_snapshot`, core progress handling.

**Modeling**: Preserve log/snapshot mutual exclusion in authoritative inflight state,
but allow commit-only/heartbeat activity while a snapshot task is active. Keep log
and snapshot retry policy separate.

**Priority**: Medium — source-derived and in scope, but not reached by the selected
fresh trace batch unless an existing neutral test triggers it.

### Scenario 5: Streamed AppendEntries intake and ordered result termination

**Mechanism**: The inbound stream may enqueue requests ahead of replies, while its
result stream returns replies in queue order and stops after conflict or higher vote.

**Evidence**:

- A background task submits requests to RaftCore through a bounded queue; the output
  side awaits stored receivers in order (`openraft/src/raft/stream_append.rs:26-86`).
- Response conversion preserves success/partial matching and turns conflict/higher
  vote into terminal stream errors
  (`openraft/src/raft/message/append_entries_response.rs:68-84`).

**Affected paths**: `raft::stream_append`, `AppendEntriesResponse::into_stream_result`.

**Modeling**: Track queued ranges separately from output termination. Do not infer
that requests not returned to the caller were never submitted.

**Priority**: Medium — it is part of the manifest's neutral stream baseline.

### Scenario 6: Per-target failure isolation

**Mechanism**: Each target owns its task/network/retry state, and learner progress is
not part of the voter quorum grant.

**Evidence**:

- Per-target handles and workers are stored independently
  (`openraft/src/replication/mod.rs:63-111`).
- Initiation iterates targets independently (`openraft/src/engine/handler/replication_handler/mod.rs:315-340`).
- The isolated-learner test verifies leader application is not blocked by the learner
  transport failure (`tests/tests/append_entries/t30_replication_1_voter_to_isolated_learner.rs:11-50`).

**Affected paths**: target progress iteration, worker task, quorum progress.

**Modeling**: Use per-target functions. Cross-target state is changed only by explicit
core actions; retry/wait actions are target-local.

**Priority**: Medium — it prevents a single retry loop from being modeled as a global
protocol stall.

## 3. Modeling recommendations

### 3.1 Model

- Authoritative progress, worker caches, pending work, active RPC, and notification
  queue as distinct states (Scenarios 1–3).
- Protocol reply classes separately from transport error classes (Scenarios 1–2).
- Backoff activation, one wait step, expiry, and success reset; keep attempt/wait
  counters observational (Scenario 2).
- Session filtering and the narrower exact-old inflight-ID semantics (Scenario 3).
- Snapshot reservation/task/result boundary with separate retry state (Scenario 4).
- Stream request queue and terminal result state (Scenario 5).

### 3.2 Do not model

- Serialization, transport framing, scheduler implementation, allocation, payload
  contents, or wall-clock duration, per the binding scope.
- Full Raft election/log safety outside this per-follower boundary.
- `ReplicationState.stream_id` as evolving state: it is initialized to zero but has no
  exact-old transition (`openraft/src/replication/mod.rs:159-168`).
- An unconditional termination property for zero-progress partial replies or recurring
  finite waits; the source provides no such environment guarantee.

## 4. Proposed extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Split progress planes | core/worker matching and inflight, pending, rpcPending | Preserve async boundaries | 1, 3 |
| Retry phase | backoffActive, waiting | Preserve old outcome-specific retry state | 2 |
| Observation overlay | attemptCount, waitCount, partialCount | Auditable discrete counts without time claim | 1, 2 |
| Notification identity | notification session/inflight | Model accept/drop and narrow ID semantics | 3 |
| Snapshot plane | snapshotActive, snapshotBackoff | Preserve separate handoff/retry | 4 |
| Stream plane | streamQueue, streamStopped | Preserve intake/output distinction | 5 |

## 5. Proposed invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| TypeOK | Safety | All state remains in its declared domain | All |
| OnePayloadInflight | Safety | Core has at most one log or snapshot payload per target | 1, 4 |
| SentRangeWellFormed | Safety | Active RPC ranges are ordered and bounded | 1 |
| WorkerMatchWithinSent | Safety | A reply cannot advance worker matching beyond its sent endpoint | 1 |
| PartialContinuationBounded | Safety | Remainder retains ID and original upper endpoint | 1 |
| WaitRequiresBackoff | Safety | Old log wait steps occur only with active backoff | 2 |
| WaitCountBoundedByAttempts | Safety | Observed wait steps never outnumber started attempts | 2 |
| CurrentSessionProgressBounds | Safety | Applied current-session progress preserves matching/search bounds; stale-session handling is a transition rule | 3 |
| SnapshotInflightConsistent | Safety | Active snapshot corresponds to snapshot inflight | 4 |
| StreamTerminalStable | Safety | No output result is consumed after terminal stream error | 5 |
| TargetLocalRetry | Safety | Retry state is a per-target mapping | 6 |

Conditional liveness is documented but is not enabled as an unconditional property:
stable session plus eventual transport recovery and fair scheduling can permit retry;
partial completion additionally needs eventual positive progress.

## 6. Findings pending verification

### 6.1 Model-checkable

None. This exact-old V0 is a neutral prior and contains no candidate finding,
reproduction, predicted violation, or update-directed campaign. The invariants above
are ordinary conformance obligations and are checked together in `MC.cfg`.

### 6.2 Test-verifiable

No new targeted test is introduced. The harness reuses the manifest's ordinary
stream, partial-success, retry, rejoin, and isolated-learner tests.

### 6.3 Code-review-only

None recorded in the frozen prior.

## 7. Reference pointers

- Detailed evidence: `analysis-report.md`
- Core files: `openraft/src/replication/mod.rs`,
  `openraft/src/engine/handler/replication_handler/mod.rs`,
  `openraft/src/core/raft_core.rs`, `openraft/src/progress/entry/update.rs`
- Retry/snapshot: `openraft/src/network/backoff.rs`,
  `openraft/src/replication/snapshot_transmitter.rs`
- Neutral tests: the five paths listed in `/work/input-manifest.json`
