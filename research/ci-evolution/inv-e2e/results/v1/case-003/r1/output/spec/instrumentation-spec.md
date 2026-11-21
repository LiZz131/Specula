# Instrumentation Specification — V1 incremental (updated source 401753b)

This revises the V0 mapping. Unchanged event names, trigger points and the
NDJSON envelope are retained; the parameter encoding and the fields needed
by the changed `ValidateUpdate` decision are new (marked **V1**).

## 1. Trace event schema

Every line is one JSON object written by `internal/speculatrace.Emit`:

```json
{"tag":"trace","ts":0,"event":{"name":"ActionName","nid":"node","state":{},"msg":{}}}
```

`ts` is a real Unix-nanosecond observation time and is ignored by the model.
`nid` is constant (one node's durable lifecycle). Events are mutex-serialized
and synced after each line. With `SPECULA_TRACE_FILE` unset all hooks are
no-ops.

**V1 parameter record.** Every parameter value is a JSON object

```json
{"other": "<sha256 of the complete ConsensusParams JSON with ABCI.VoteExtensionsEnableHeight forced to 0>",
 "veh": <ABCI.VoteExtensionsEnableHeight>}
```

and "no parameter" is `{"other":"NoOther","veh":0}` (TLA+ `NoParam`). The
split keeps the non-ABCI fields symbolic and complete (no sampled subfield)
while exposing the integer that `ValidateUpdate` reads.

The `event.state` object is a full post-action snapshot:

| Trace field | TLA+ variable | Implementation source |
|---|---|---|
| `blockStoreHeight` | `blockStoreHeight` | `BlockStore.Height()` |
| `appHeight` | `appHeight` | shadow initialized from `Info.LastBlockHeight`, advanced only after commit/replay |
| `stateStoreHeight` | `stateStoreHeight` | `LastBlockHeight` of the persisted state passed to/loaded by the hook |
| `stateHeight` | `stateHeight` | current `sm.State.LastBlockHeight` |
| `activeParam` | `activeParam` | **V1 record** of the in-memory `State.ConsensusParams` |
| `persistedParam` | `persistedParam` | **V1 record** of the persisted `State.ConsensusParams` |
| `activeOtherValid` | (classifies `activeParam.other` w.r.t. `ValidOthers`) | **V1** `ValidateBasic()` of the active params with VEH forced to 0 |
| `lastParamChange` | `lastParamChange` | `LastHeightConsensusParamsChanged` in memory |
| `persistedLastParamChange` | `persistedLastParamChange` | same field of the persisted state |
| `responseHeight` | `responseHeight` | shadow updated after `SaveFinalizeBlockResponse` or recovered at handshake |
| `responseParam` | `responseParam` | **V1 record** of `state.ConsensusParams.Update(resp.ConsensusParamUpdates)` or NoParam |
| `responseAbciPresent` | `responseAbciPresent` | **V1** `resp.ConsensusParamUpdates != nil && resp.ConsensusParamUpdates.Abci != nil` |
| `phase` | `phase` | lifecycle phase at the hook |
| `replayMutatesState` | `replayMutatesState` | true only while the final block is replayed through `ApplyBlock` |
| `pendingBlockHeight` | `pendingBlockHeight` | block under application, otherwise 0 |
| `pendingParam` | `pendingParam` | **V1 record** of the proposed complete parameters, otherwise NoParam |
| `pendingAbciPresent` | `pendingAbciPresent` | **V1** `updates.Abci != nil` for the block under application |
| `validationOutcome` | `validationOutcome` | `none`, `accepted`, or `rejected` |

Event-specific message fields:

| Event | Message fields |
|---|---|
| `BlockStored` | `height` |
| `ApplyBlockStart` | `height` |
| `FinalizeBlock` | `height`, `updatePresent`, `proposedParam`, **V1** `abciPresent`, **V1** `proposedOtherValid` |
| `SaveFinalizeBlockResponse` | `height` |
| `UpdateStateAccepted` | `height`, `updatePresent`, `proposedParam`, **V1** `abciPresent` |
| `UpdateStateRejected` | `height`, `updatePresent`, `proposedParam`, **V1** `abciPresent`, **V1** `reason` (`basic` / `update` / `other`), **V1** `error` |
| `CommitApp` | `height` |
| `SaveState` | `height` |
| `HandshakeStart` | `appHeight`, `blockStoreBase`, `blockStoreHeight`, `stateStoreHeight` |
| `ReplayAppBlock` | `height` |
| `ReplayStateBlockStart` | `height`, `mode` (`real` or `mock`) |
| `HandshakeComplete` | `height` |

`reason` is derived from the error that `updateState` wrapped:
`"validating new consensus params:"` (`execution.go:619`) → `basic`,
`"updating consensus params:"` (`execution.go:624`) → `update`.

## 2. Action-to-code mapping

Line numbers refer to the uninstrumented updated source (`artifact/` at
401753b); the hooks are applied by `harness/patches/instrumentation.patch`.

| Spec action / event | Code location | Trigger point and snapshot |
|---|---|---|
| `SaveBlock` / `BlockStored` | `internal/state/execution.go:211-213` | At `ApplyBlock` entry after the caller saved the block; suppressed during replay. |
| `ApplyBlockStart` / same | `execution.go:211-216` | After the entry snapshot, before block validation/finalization. |
| `FinalizeBlock(p, abci)` / `FinalizeBlock` | `execution.go:218-234` | After successful ABCI `FinalizeBlock`; `p` = record of `state.ConsensusParams.Update(updates)` (`types/params.go:289-318`) or NoParam; `abci` = `updates.Abci != nil`. |
| `SaveFinalizeBlockResponse` / same | `execution.go:253-256` | After the response save returns. |
| `UpdateStateAccepted` / same | `execution.go:279-282` (calls `:585-652`) | After `updateState` returns without error. |
| `UpdateStateRejectedBasic` / `UpdateStateRejected` (`reason=basic`) | `execution.go:617-620` | `updateState` error from `nextParams.ValidateBasic()`; no commit/save follows. |
| `UpdateStateRejectedVE` / `UpdateStateRejected` (`reason=update`) | `execution.go:622-625` → `types/params.go:219-261` | `updateState` error from `ValidateUpdate`; no commit/save follows. |
| `CommitApp` / same | `execution.go:285-288` | After `Commit` succeeds; app height shadow advances. |
| `SaveState` / same | `execution.go:297-299` | After the new state is durably saved; stays in `handshake` phase during final-block replay. |
| `BeginHandshake` / `HandshakeStart` | `internal/consensus/replay.go:241-251` | After ABCI `Info` and before the recovery decision; trace file is reset here to exclude fixture setup. |
| `ReplayAppBlock` / same | `replay.go:476-489` | After one `ExecCommitBlock` on the app-only path. |
| `SelectRealReplay` / `ReplayStateBlockStart` (`mode=real`) | `replay.go:409-415`, `:491-498` | Before final-block `replayBlock` with the real app. |
| `SelectMockReplay` / `ReplayStateBlockStart` (`mode=mock`) | `replay.go:417-433` | Before final-block `replayBlock` with the saved-response mock app. |
| `CompleteHandshake` / `HandshakeComplete` | `replay.go:268-275` | After recovery succeeds and the state store is reloaded. |

`Crash`, `AppReportsOlderHeight`, and `EnvironmentStutter` are model-only
environment actions. `AbortRejectedApply` is represented by trace termination
immediately after `UpdateStateRejected` (the production caller panics or the
handshake returns its error); a following restart is a separate trace that
begins with `HandshakeStart`.

## 3. Mandatory V1 checks in `Trace.tla`

- `FinalizeBlockIfLogged` passes the logged `proposedParam` and `abciPresent`
  to `FinalizeBlock(p, abci)`, which enforces `p.veh = activeParam.veh` when
  `abci = FALSE` and replay determinism against the saved response.
- `UpdateStateAcceptedIfLogged` / `UpdateStateRejectedIfLogged` require the
  logged proposal to equal the model's pending record and dispatch on
  `reason`; the accept/reject decision itself is computed by the reference
  (`ValidateUpdateRow`) and is never read from the trace.
- `ValidatePostState` compares every state field above, including
  `pendingAbciPresent`, `responseAbciPresent`, and the VEH inside every
  parameter record.
- `ValidOthers` is reconstructed only from `activeOtherValid` and
  `proposedOtherValid`; it covers the non-ABCI part of `ValidateBasic`.

## 4. Special considerations

- Parameter identity remains complete: `other` hashes all non-ABCI fields;
  `veh` carries the only ABCI field present in this revision
  (`types/params.go:68-71`).
- App height and saved-response identity are shadow observations initialized
  from ABCI `Info`/the state store at handshake and updated only after the
  corresponding operation, as in V0.
- `ApplyBlock` is reused during final-block recovery; the replay flag
  suppresses `BlockStored` and keeps `SaveState` in the `handshake` phase.
- One scenario per Go process and trace file. Emission failures are ignored at
  production call sites so tracing never adds a functional error path.
