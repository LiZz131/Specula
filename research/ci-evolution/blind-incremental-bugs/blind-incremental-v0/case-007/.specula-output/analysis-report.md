# Exact-old code analysis report — case-007

## Authority and method

Behavioral evidence came only from `/work/source`, `/work/scope.md`, and
`/work/input-manifest.json`. The history/issue/reference-comparison phase was omitted
by experiment instruction. No Git log, upstream reference, issue tracker, paper,
release note, internet source, fixed tree, or alternate case output was inspected.
The source contains one neutral baseline commit; it was used only later as the base
for an instrumentation diff in `/work/work-source`.

The selected boundary is Category A and non-BFT. File-complete deep analysis covered
the manifest's replication, core, progress, retry, RPC, snapshot files and five
neutral tests, plus direct helpers needed to establish `Inflight`, session,
notification, stream, and fixture semantics. Baseline `cargo test -p openraft --lib`
passed 311 tests; its log is preserved under `spec/output/`.

## Structural result

```text
single-threaded RaftCore / Engine
  ProgressEntry[target] = matching + searching_end + authoritative inflight(id)
       |
       +-- logs --> Command::Replicate --> per-target ReplicationCore channel
       |                                  receive/coalesce
       |                                  read prefix from log store
       |                                  unary AppendEntries RPC + timeout
       |                                  heartbeat/progress notifications
       |
       +-- snapshot --> Command::ReplicateSnapshot --> separate transmitter
                                                   read current snapshot
                                                   full_snapshot + cancellation
                                                   heartbeat/progress notifications

notifications --> atomic session check in RaftCore --> progress update
              --> routine per-target work selection
```

The architecture intentionally separates authoritative core progress from worker
caches. RaftCore reserves one payload per target (`progress/entry/mod.rs:104-164`),
then a target task processes work sequentially (`replication/mod.rs:78-111,183-278`).
Snapshot transfer is a distinct task and network client (`raft_core.rs:1954-1973`).

## State and identity

- Session identity is `(committed leader vote, effective membership log ID)`
  (`replication_session_id.rs:10-29`).
- Core progress holds `matching`, `inflight`, `searching_end`, and an optional
  log-reversion allowance (`progress/entry/mod.rs:21-46`).
- Worker state holds session/target context, optional current inflight ID, channel,
  network, optional backoff iterator, log reader, cached committed/matching, and
  `next_action` (`replication/mod.rs:83-111`).
- Core inflight, queued events, worker pending action, active RPC, and snapshot task
  are different atomicity planes and must not be collapsed.
- `ReplicationState.stream_id`, `purged`, `local.last`, `remote.committed`, and its
  `searching_end` have no active transition in the exact-old worker; the model does
  not invent behavior for them (`replication_state.rs:14-39`).

## Exact work and RPC flow

`next_send` first suppresses a second inflight. It selects a snapshot if the possible
matching range is below the purge boundary; otherwise it selects a bounded log range
and allocates a fresh ID (`progress/entry/mod.rs:112-164`). Runtime dispatch sends
log work over the target channel or spawns a snapshot transmitter
(`replication_handler/mod.rs:343-363`; `raft_core.rs:1950-1973`).

The worker blocks for one event when idle and then nonblocking-drains. During
backoff it receives/folds events while sending no RPC. A committed update advances
the cached committed position and creates a commit-only action only when no action
is pending. Payload work replaces a pending commit-only action
(`replication/mod.rs:516-627`).

For logs, the worker takes the pending action, reads at most the requested range,
builds an AppendEntries request from session vote, actual sent prefix, cached commit,
and entries, then awaits one unary RPC under an outer timeout equal to the heartbeat
interval (`replication/mod.rs:184-214,304-379`). It cannot process its channel during
the read/RPC await; RaftCore can continue independently.

Protocol outcomes are distinct:

- `Success` acknowledges the actual sent endpoint.
- `PartialSuccess(m)` acknowledges `m`; if below the logical endpoint, the worker
  immediately retains a remainder with the same inflight ID.
- `Conflict` acknowledges leadership/contact, reports the sent previous log as a
  conflict, and does not advance matching.
- `HigherVote` notifies core and terminates the log worker.

Anchors: `append_entries_response.rs:20-53`; `replication/mod.rs:387-440,629-668`.
Heartbeat progress and replication progress are separate awaited sends. Heartbeat
timing is outside the scoped state; the response action records the latter progress
send (`replication/mod.rs:387-410,426-437`).

## Exact-old retry policy

A payload RPC error is stringified and sent to RaftCore with its inflight ID; a
commit-only RPC error is not reported as replication progress
(`replication/mod.rs:248-270,444-459`). Core checks the session, clears authoritative
inflight on error, and later routine work selection allocates a fresh ID
(`raft_core.rs:1565-1574`; `replication_handler/mod.rs:275-290`;
`raft_core.rs:738-763`). Therefore transport retry is a core round trip, not worker
resend of the old request object.

`Unreachable` lazily creates a network-provided `Backoff`. Later `Unreachable`
outcomes reuse it. Timeout/network/remote errors do not initialize it and, if already
active, do not clear it. Any protocol reply handled as `Ok(())`, including conflict,
clears it (`replication/mod.rs:218-263`). Each wait consumes one iterator duration;
the default is constant 500 ms and exhaustion defensively uses 500 ms
(`network/backoff.rs:6-24`; `network/v2/network.rs:156-169`;
`replication/mod.rs:280-287`).

This supports a discrete observation of attempts and wait steps, not a universal
time, retry-count, or completion bound. A zero-progress `PartialSuccess(prev)` is
permitted by inclusive response bounds, so completion needs an environmental
progress assumption (`append_entries_response.rs:24-41`; `replication/mod.rs:643-668`).

Snapshot retry is intentionally different. It retries locally and re-reads the
current snapshot. `Unreachable` creates/continues snapshot backoff, while
timeout/network/remote explicitly clear it for an immediate next iteration
(`snapshot_transmitter.rs:91-197`). This is modeled separately from log backoff.

## Progress and stale notification semantics

Core accepts replication/heartbeat progress only when both session components match
current state. The check and update occur synchronously in the single core handler
(`raft_core.rs:1565-1592,1746-1767`). This is the strong stale boundary.

Inflight ID has narrower exact-old semantics. `Inflight::ack/conflict` ignore a
mismatched ID for the nested inflight mutation (`progress/inflight/mod.rs:127-185`).
Their callers update outer matching/search state after that check, and an outer RPC
error resets inflight without consulting the supplied ID
(`progress/entry/update.rs:40-115`; `replication_handler/mod.rs:284-290`). The model
preserves this control flow and does not claim whole-message rejection by inflight ID.

## Snapshot boundary

When snapshot is selected, authoritative inflight is `Snapshot(id)`. Runtime spawns
an independent task using the current session and target. `full_snapshot` returns
only after complete transfer/install or rejection; a non-higher response is followed
by heartbeat progress and then matching progress for the snapshot metadata endpoint
(`network/v2/network.rs:115-138`; `snapshot_transmitter.rs:199-265`). A current-ID
ack clears snapshot inflight, after which incremental selection can resume.

Log replication is not the snapshot task. Commit-only AppendEntries and dedicated
heartbeat activity can interleave with snapshot transfer. Cancellation is observed
during network transfer and backoff, while `get_snapshot().await` is not raced with
cancel (`snapshot_transmitter.rs:149-177,202-212`).

## Neutral tests and what they establish

- `t10_stream_append`: ordered success outputs and terminal conflict/higher-vote
  outputs. Requests can be queued ahead; output termination does not prove later
  input was never submitted (`raft/stream_append.rs:26-86`).
- `t10_append_entries_partial_success`: partial-prefix continuation and later
  progress when quota is raised. It does not establish retry delay.
- `t50_append_entries_backoff`: an Unreachable target plus coarse global RPC-count
  bounds. It establishes ordinary throttling evidence, not an exact per-target delay
  or attempt threshold.
- `t50_append_entries_backoff_rejoin`: removed-node restart and catch-up. Fixture
  removal clears the set-Unreachable flag and missing routing yields NetworkError, so
  it is not deterministic evidence of sustained Unreachable backoff.
- `t30_replication_1_voter_to_isolated_learner`: leader progress is not blocked by a
  learner NetworkError. Its restoration block sends zero new writes and does not by
  itself assert learner catch-up.

These limitations determine coverage labels; they are not converted into findings
or special schedules.

## Failure assumptions and exclusions

Modeled outcomes are success, partial success, conflict, higher vote, timeout,
unreachable, network error, remote error, storage closure, and session rollover when
the exact-old code exposes them. Crash recovery, full transport internals, payload
contents, serialization, allocator/scheduler behavior, and full-cluster election/log
safety are outside this subsystem boundary. Fair scheduling and eventual transport
or partial progress are explicit conditions for any liveness statement.
The ordinary V0 configuration uses the exact-old default
`allow_log_reversion = false`: a conflict below the known matching boundary is
an invalid peer/environment response (a debug assertion in the exact-old core).
The base model retains the enabled-option reset branch through the
`AllowLogReversion` constant.

## Frozen quantitative observation contract

Before any update input, the prior defines only these auditable counts:

- `attemptCount`: increment at each unary AppendEntries call.
- `partialCount`: increment on each partial reply.
- `waitCount`: increment when one old log-backoff iterator item is consumed.
- Snapshot attempts/waits are separate if reached.

No threshold distinguishes acceptable from unacceptable behavior. Model bounds are
finite exploration controls and are reported as limited coverage, never proof.
