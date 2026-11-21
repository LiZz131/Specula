# Modeling brief coverage audit

This audit reads the frozen brief and actual cfg/spec files. The binding V0 scope
prohibits candidate findings and targeted campaigns, so there are no `MC_hunt_*`
configs. All ordinary conformance invariants are enabled together in `MC.cfg`; later
reachability configs establish non-vacuity without predicting a violation.

## Scenarios

| Brief scenario | Base actions/state | Trace events | Checked by |
|---|---|---|---|
| 1. Partial continuation | `ReceiveLogs`, `SendAppend`, `AppendSuccess`, `AppendPartial`, split core progress | receive/send/reply; exact core step is internal | `MC.cfg`, partial trace, reachability witness |
| 2. Retry/backoff | `AppendRpcError`, `BeginBackoff`, `EndBackoff`, `ResetBackoffAfterReply` | RPC error/begin/end/reset | `MC.cfg`, retry trace, reachability witness |
| 3. Session/inflight | notification sequence, `CoreHandleProgress`, `ChangeCoreSession` | response producers; core application is unlogged | `MC.cfg`, session reachability witness |
| 4. Snapshot handoff | `StartSnapshot`, attempt/error/backoff/success | snapshot start/attempt/success reached | `MC_snapshot.cfg`, snapshot trace, reachability witness |
| 5. Stream intake/output | `StreamEnqueue`, `StreamResult` | enqueue/result | `MC_stream.cfg`, three stream traces, reachability witness |
| 6. Per-target isolation | all task/retry state is `[Target -> ...]` | target-filtered files | structural model; isolated-learner trace |

## Safety invariants

| Brief invariant | Defined | Enabled |
|---|---|---|
| `TypeOK` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `OnePayloadInflight` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `SentRangeWellFormed` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `WorkerMatchWithinSent` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `PartialContinuationBounded` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `WaitRequiresBackoff` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `WaitCountBoundedByAttempts` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `CurrentSessionProgressBounds` | `ProgressBounds` plus the current/stale branches of `CoreHandleProgress` | `MC.cfg`, `Trace.cfg` |
| `SnapshotInflightConsistent` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| `StreamTerminalStable` | `base.tla` | `MC.cfg`, `Trace.cfg` |
| Target-local retry | state is per-target by type and every retry action updates one function element | `MCTypeOK`, action structure |

`ProgressBounds` is an additional structural check derived from exact-old
`ProgressEntry::validate` and is enabled in both configs.

## Findings

Brief §6.1 is intentionally empty. There is no candidate finding needing a hunt cfg.
The model checker is used only for bounded consistency/safety and non-vacuity checks.
Dedicated `reach-*.log` runs intentionally violate negated witness predicates; these
expected counterexamples demonstrate reachability and are not findings.

## Known coverage limits before execution

- `MC.cfg` checks log/core/session behavior; `MC_snapshot.cfg` and
  `MC_stream.cfg` isolate the two independent planes to avoid a vacuous or
  prohibitively large Cartesian product.
- Integer, attempt, notification-depth, and stream-depth bounds are finite search
  controls and must be reported as `LIMITED_COVERAGE`.
- Fresh traces cover full/partial append success, stream success/conflict/higher,
  network and unreachable errors, one log-backoff begin, task closure, and snapshot
  start/attempt/success. They do not directly cover timeout/remote errors, log
  backoff expiry/reset, snapshot transport error/backoff, or real core session-drop
  post-state.
- The model does not assert unconditional retry or partial-progress liveness.
