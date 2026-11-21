# Instrumentation Specification — case-003 updated revision

Rebased from the V0 specification. Event names, trigger points and the
single-file Category A strategy are unchanged; the state snapshot now carries
structured parameter/update records, the rejection rule, and the per-height
enable-height history required by `base.tla` / `Trace.tla`.

## 1. Trace event schema

Every line is one JSON object written by `internal/speculatrace.Emit`:

```json
{"tag":"trace","ts":0,"event":{"name":"ActionName","nid":"node","state":{},"msg":{}}}
```

`ts` is a real Unix-nanosecond time (ignored by the model). Events are
mutex-serialized and synced per line. With `SPECULA_TRACE_FILE` unset every hook
is a no-op.

### Value encodings (mandatory)

| Encoding | JSON | TLA+ | Go source |
|---|---|---|---|
| parameter record | `{"rest": <sha256>, "ve": <int>}` | `[rest, ve]` | `sm.SpeculaParam(cp)`: `rest` = fingerprint of `cp` with `ABCI` zeroed; `ve` = `cp.ABCI.VoteExtensionsEnableHeight` |
| update record | `{"present": bool, "rest": <sha256 or "none">, "abciPresent": bool, "abci": <int>}` | `Updates` / `NoUpdate` | `sm.SpeculaUpdate(cur, upd)`: `present` = `upd != nil`; `rest` = rest of `cur.Update(upd)`; `abciPresent` = `upd.Abci != nil`; `abci` = `upd.Abci.VoteExtensionsEnableHeight` (0 if absent) |
| enable-height history | `[ve_1, …, ve_B]` | `veHist` | `sm.SpeculaVEHistory(stateStore, B)`: `stateStore.LoadConsensusParams(m).ABCI.VoteExtensionsEnableHeight` for m = 1..B; -1 if missing |
| rejection rule | `"none" | "basic" | "r2" | "r4" | "r6" | "r8" | "unclassified"` | `rejectRule` | `sm.SpeculaRejectRule(err)` classifies the `updateState` error by its wrapping/message |

### State snapshot (`event.state`, every event, post-action)

| Trace field | TLA+ variable | Source |
|---|---|---|
| `blockStoreHeight` | `blockStoreHeight` | `BlockStore.Height()` |
| `appHeight` | `appHeight` | shadow initialized from `Info.LastBlockHeight`, advanced after commit/replay |
| `stateStoreHeight` | `stateStoreHeight` | persisted `State.LastBlockHeight` |
| `stateHeight` | `stateHeight` | in-memory `State.LastBlockHeight` |
| `activeParam` | `activeParam` | parameter record of in-memory `State.ConsensusParams` |
| `persistedParam` | `persistedParam` | parameter record of persisted `State.ConsensusParams` |
| `lastParamChange` | `lastParamChange` | in-memory `LastHeightConsensusParamsChanged` |
| `persistedLastParamChange` | `persistedLastParamChange` | persisted `LastHeightConsensusParamsChanged` |
| `responseHeight` | `responseHeight` | shadow set after `SaveFinalizeBlockResponse` or recovered at handshake |
| `responseParam` | `responseParam` | update record of the saved response's `ConsensusParamUpdates` |
| `phase` | `phase` | lifecycle phase at the hook |
| `replayMutatesState` | `replayMutatesState` | true while the final block is replayed through `ApplyBlock` |
| `pendingBlockHeight` | `pendingBlockHeight` | block under application, else 0 |
| `pendingParam` | `pendingParam` (and `updatePresent = pendingParam.present`) | update record returned by `FinalizeBlock`, else `NoUpdate` |
| `validationOutcome` | `validationOutcome` | `none` / `accepted` / `rejected` |
| `rejectRule` *(new)* | `rejectRule` | rejection rule on `UpdateStateRejected`, else `none` |
| `veHist` *(new)* | `veHist` | enable-height history of stored heights 1..`blockStoreHeight` |

### Message fields

| Event | Message fields |
|---|---|
| `BlockStored`, `ApplyBlockStart`, `SaveFinalizeBlockResponse`, `CommitApp`, `SaveState`, `ReplayAppBlock`, `HandshakeComplete` | `height` |
| `FinalizeBlock`, `UpdateStateAccepted`, `UpdateStateRejected` | `height`, `updatePresent`, `proposedParam` (update record) |
| `HandshakeStart` | `appHeight`, `blockStoreBase`, `blockStoreHeight`, `stateStoreHeight` |
| `ReplayStateBlockStart` | `height`, `mode` (`real`/`mock`) |

`FinalizeBlock.msg.proposedParam` is the action argument of `FinalizeBlock(p)`;
all `state` fields are compared by `ValidatePostState` after every event.

## 2. Action-to-code mapping (unchanged trigger points)

| Spec action / event | Code location (instrumented copy) | Trigger point |
|---|---|---|
| `SaveBlock` / `BlockStored` | `internal/state/execution.go` `ApplyBlock` entry | caller already saved the block; suppressed during replay |
| `ApplyBlockStart` | `ApplyBlock` entry | before `validateBlock` |
| `FinalizeBlock(p)` | after `proxyApp.FinalizeBlock` (execution.go:218-234) | `p` = `SpeculaUpdate(state.ConsensusParams, resp.ConsensusParamUpdates)` |
| `SaveFinalizeBlockResponse` | after `store.SaveFinalizeBlockResponse` (execution.go:254) | response shadow set to `p` |
| `UpdateStateAccepted` | after `updateState` returns nil (execution.go:279) | in-memory state installed |
| `UpdateStateRejected` | `updateState` error branch (execution.go:280-282) | `rejectRule` = `SpeculaRejectRule(err)` |
| `CommitApp` | after `blockExec.Commit` (execution.go:285) | app shadow = block height |
| `SaveState` | after `store.Save` (execution.go:297) | phase `handshake` during replay |
| `BeginHandshake` / `HandshakeStart` | `Handshaker.Handshake` after `Info` (replay.go:242-252) | trace reset; response shadow recovered via `SpeculaUpdate(initialState.ConsensusParams, saved.ConsensusParamUpdates)` when B = S+1 |
| `ReplayAppBlock` | after `ExecCommitBlock` in `replayBlocks` | — |
| `SelectRealReplay` / `SelectMockReplay` / `ReplayStateBlockStart` | before final-block `replayBlock` (replay.go:403-433) | `mode` |
| `CompleteHandshake` / `HandshakeComplete` | after successful replay and state reload | — |

`Crash`, `AppReportsOlderHeight`, `AbortRejectedApply`, and `EnvironmentStutter`
remain model-only (no executable boundary); a crash is injected in the
recovery scenarios by a failing state-store `Save` or a failing app `Commit` and
is observed only through the next `HandshakeStart` snapshot.

## 3. Special considerations

- `rest` excludes the ABCI subrecord so that the enable height is compared
  explicitly; all other fields remain a complete-value fingerprint.
- `abciPresent` is mandatory: an absent Abci subrecord and one repeating the
  current value install the same parameters but take different
  `ValidateUpdate` branches (row 1 vs row 6/9).
- `veHist` is read from the state store's per-height params history, i.e. the
  params in effect at each stored height (what `finalizeCommit` used for its
  extended-commit decision). Extended-commit storage itself is not observed.
- The `veHist` probe recovers from a panic raised by a mocked state store in
  test fixtures and then emits an empty history, which Trace.tla rejects; the
  probe never alters a functional path.
- `SpeculaRejectRule` matches the updated error texts; an unknown error yields
  `unclassified`, which no model action produces (trace mismatch, not silence).
