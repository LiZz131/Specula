# Instrumentation Specification — Specula V1 (incremental update)

V1 rebases the V0 harness onto the updated source. Event names, trigger points
and the state-snapshot timing are unchanged; the parameter projection is
refined so that `Trace.tla` can check the updated `ConsensusParams.ValidateUpdate`
(`types/params.go:208-261`). Changed items are marked **[V1]**.

## 1. Trace event schema

Every line is one JSON object written by `internal/speculatrace.Emit`:

```json
{"tag":"trace","ts":0,"event":{"name":"ActionName","nid":"node","state":{},"msg":{}}}
```

`ts` is a real Unix-nanosecond observation time. It is deliberately ignored by
the model. `nid` is constant because the scoped subsystem is one node's durable
block/application/state lifecycle. Events are mutex-serialized and synced after
each line. When `SPECULA_TRACE_FILE` is unset, all hooks are no-ops.

The `event.state` object is a full post-action snapshot:

| Trace field | TLA+ variable | Exact-old implementation source |
|---|---|---|
| `blockStoreHeight` | `blockStoreHeight` | `BlockStore.Height()` |
| `appHeight` | `appHeight` | shadow initialized from `Info.LastBlockHeight`, advanced only after commit/replay |
| `stateStoreHeight` | `stateStoreHeight` | `stateStore.Load().LastBlockHeight` |
| `stateHeight` | `stateHeight` | current `sm.State.LastBlockHeight` |
| `activeParam` | `activeParam` | **[V1]** `{body, veh}`: `body` = SHA-256 fingerprint of the in-memory `ConsensusParams` with `ABCI` zeroed (Block/Evidence/Validator/Version), `veh` = exact `ABCI.VoteExtensionsEnableHeight` (`speculatrace.ParamRecord`) |
| `persistedParam` | `persistedParam` | **[V1]** same `{body, veh}` projection of the persisted value |
| `lastParamChange` | `lastParamChange` | `LastHeightConsensusParamsChanged` in memory |
| `persistedLastParamChange` | `persistedLastParamChange` | the same field in the loaded state |
| `responseHeight` | `responseHeight` | shadow updated after `SaveFinalizeBlockResponse` or recovered during handshake |
| `responseParam` | `responseParam` | **[V1]** update descriptor of the saved response (see below) |
| `phase` | `phase` | lifecycle phase at the hook |
| `replayMutatesState` | `replayMutatesState` | true only while the final block is replayed through `ApplyBlock` |
| `pendingBlockHeight` | `pendingBlockHeight` | current block under application, otherwise 0 |
| `pendingParam` | `pendingParam` | **[V1]** update descriptor of the in-flight response, `{"present": false}` when none |
| `validationOutcome` | `validationOutcome` | `none`, `accepted`, or `rejected` |

**[V1] Update descriptor** (`speculatrace.UpdateRecord(cur, upd)`): `{"present": false}`
for a nil `ConsensusParamUpdates`; otherwise `{"present": true, "body": <fingerprint
of the non-ABCI part of cur.Update(upd)>, "abciPresent": upd.Abci != nil, "veh":
upd.Abci.VoteExtensionsEnableHeight (0 when absent)}`. `Trace.tla!ToUpdate` maps it
to base's `NoParam` / `[body, abci]` (with `abci = NoAbci` when `abciPresent` is
false); `ToParam` maps `{body, veh}` records. `NoParam`/`NoAbci` are TLC model
values in `Trace.cfg`, so integers, strings and markers are never compared as
mixed TLC types.

Event-specific message fields are:

| Event | Message fields |
|---|---|
| `BlockStored` | `height` |
| `ApplyBlockStart` | `height` |
| `FinalizeBlock` | `height`, `updatePresent`, `proposedParam` (descriptor), **[V1]** `proposedBodyValid` |
| `SaveFinalizeBlockResponse` | `height` |
| `UpdateStateAccepted` | `height`, `updatePresent`, `proposedParam` (descriptor) |
| `UpdateStateRejected` | `height`, `updatePresent`, `proposedParam`, **[V1]** `stage` (`basic`/`update`/`other`), `error` |
| `CommitApp` | `height` |
| `SaveState` | `height` |
| `HandshakeStart` | `appHeight`, `blockStoreBase`, `blockStoreHeight`, `stateStoreHeight` |
| `ReplayAppBlock` | `height` |
| `ReplayStateBlockStart` | `height`, `mode` (`real` or `mock`) |
| `HandshakeComplete` | `height` |

## 2. Action-to-code mapping

All line numbers below refer to the V0 instrumented copy; **[V1]** the hook positions are unchanged by symbol (V1 adds a few lines inside the same hooks, so absolute line numbers in the instrumented copy drift by a few lines; the uninstrumented updated source is line-identical to the old one in `execution.go` and `replay.go`). The underlying
operation is source-derived from the byte-identical immutable tree.

| Spec action / event | Instrumented location | Trigger point and snapshot |
|---|---|---|
| `SaveBlock` / `BlockStored` | `internal/state/execution.go:216-226` | At `ApplyBlock` entry, after its caller has durably saved the block; suppressed for replay, whose stored block is already represented by `ReplayStateBlockStart`. |
| `ApplyBlockStart` / `ApplyBlockStart` | `internal/state/execution.go:223-226` | Immediately after the entry snapshot and before block validation/finalization. |
| `FinalizeBlock(p)` / `FinalizeBlock` | `internal/state/execution.go:248-258` | After successful ABCI `FinalizeBlock`; `p` is the complete updated parameter fingerprint or `NoParam`. |
| `SaveFinalizeBlockResponse` / same | `internal/state/execution.go:281-289` | After the state store save returns successfully. |
| `UpdateStateAccepted` / same | `internal/state/execution.go:325-329` | After exact-old `updateState` validates and installs all response changes in memory. |
| `UpdateStateRejected` / same | `internal/state/execution.go:314-319` | On `updateState` error and before `ApplyBlock` returns it; no commit/state save follows. |
| `CommitApp` / same | `internal/state/execution.go:340-345` | After exact-old `Commit` succeeds and the application height shadow advances. |
| `SaveState` / same | `internal/state/execution.go:357-365` | After the new state has been durably saved; remains in `handshake` phase during final-block replay. |
| `BeginHandshake` / `HandshakeStart` | `internal/consensus/replay.go:254-276` | After ABCI `Info` has supplied the application height and before the recovery decision. The trace file is reset here to exclude fixture setup. |
| `ReplayAppBlock` / same | `internal/consensus/replay.go:523-529` | After one `ExecCommitBlock` completes on the app-only replay path. Core state remains unchanged. |
| `SelectRealReplay` / `ReplayStateBlockStart` | `internal/consensus/replay.go:448`, `535`, `570-578` | Before final-block `replayBlock` with the real app. |
| `SelectMockReplay` / `ReplayStateBlockStart` | `internal/consensus/replay.go:467`, `570-578` | Before final-block `replayBlock` with the saved response-backed mock app. |
| `CompleteHandshake` / `HandshakeComplete` | `internal/consensus/replay.go:296-303` | After recovery succeeds and the state store is reloaded. |

`Crash`, `AppReportsOlderHeight`, and `EnvironmentStutter` are model-only
environment actions. They do not correspond to an executable call boundary,
so they have no runtime event and are used only by `MC.tla`. `AbortRejectedApply`
is represented by trace termination immediately after `UpdateStateRejected`; it
has no additional implementation operation to observe.

## 2b. [V1] Update-critical fields and their consuming Trace predicates

| Field | Emitted at | Consumed by (`Trace.tla`) | Non-vacuity evidence |
|---|---|---|---|
| `activeParam.veh`, `persistedParam.veh` | every event | `ValidatePostState` (`ToParam`), and as `c` in `base!ValidateUpdateOK` | mutant M4 (installed `veh` altered) rejected |
| `proposedParam` / `pendingParam` `.abciPresent`, `.veh` | `FinalizeBlock`, `UpdateState*`, every event | `FinalizeBlock(ToUpdate(...))`, `ProposedMatchesPending`, `ValidatePostState`; `u` in `ValidateUpdateOK` | mutant M1 (u rewritten to h) rejected |
| `stage` | `UpdateStateRejected` | `UpdateStateRejected(logline.event.msg.stage)` guard split (execution.go:617-625) | mutant M2 (stage relabelled) rejected |
| accept/reject event identity | `UpdateStateAccepted` / `UpdateStateRejected` | enabled only if `UpdateAccepted` holds / fails | mutant M3 (rejection relabelled as acceptance) rejected |
| `proposedBodyValid` | `FinalizeBlock` | `TraceValidBodies` (only independent evidence) | mutant M5 (valid body flagged invalid) rejected |
| `responseParam` (restart) | `HandshakeStart` | `TraceInit`, deterministic `FinalizeBlock` guard, `ValidatePostState` | mutant M6 rejected |

`proposedBodyValid` is computed by `speculatrace.BodyValid`: the real
`ValidateBasic` on `cur.Update(upd)` with the enable height neutralized to 0 —
i.e. exactly the non-ABCI part of `ValidateBasic` (`types/params.go:145-206`;
the only ABCI check is `:188-190`). `stage` is computed by
`speculatrace.RejectStage` by re-evaluating the real `ValidateBasic` and
`ValidateUpdate` on the unchanged input state after `updateState` returned an
error.

## 3. Special considerations

- Parameters are never sampled by selected subfield. A stable fingerprint of
  the complete serialized value prevents a hidden update from being treated as
  equality while keeping TLC's data domain finite.
- Application height and saved-response identity are not jointly exposed by a
  production getter at every hook. The opt-in package maintains those two
  shadow observations, initializes them from ABCI `Info`/the state store during
  handshake, and updates them only after the corresponding exact-old operation.
- `ApplyBlock` is reused during final-block recovery. A replay flag avoids
  falsely emitting a new durable block save and keeps the state save in the
  handshake phase until `HandshakeComplete`.
- The harness runs one scenario per Go process and file. This removes
  cross-test event interleaving; the writer mutex handles intra-process calls.
- The instrumentation ignores emission failures at production call sites so
  tracing cannot replace or alter functional error paths. Harness setup treats
  failure to create the file as a test failure.
- **[V1]** Recovery scenarios write the node-start + block-1 phase to
  `SPECULA_TRACE_PREFIX_FILE` and the restart to `SPECULA_TRACE_FILE`
  (Handshake resets the active file). A state-save failure is injected by a
  `sm.Store` wrapper (crash cut after `Commit`, before `Save`) to reach the mock
  replay case through real code.
- `Trace.tla` validates every captured state field after every event and has no
  silent fallback transition. `TraceMatched` plus fairness ensures a prefix is
  not reported as a successful trace.

