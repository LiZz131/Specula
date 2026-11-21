# Requirement-evidence ledger

Model: `spec-original/` (CometBFT consensus-parameter update and crash replay), annotated copy in `out/spec-annotated/`.

Scope: every operator after `INVARIANT(S)` / `PROPERTY(IES)` in the 16 `.cfg` files (no commented-out property lines exist), giving 16 distinct properties. There is no `Update.tla`. None of the in-scope properties is a pure alias (`A == B`). The `NeverReached*` canaries are negations of the `Reached*` helpers (`NeverReachedX == ~ReachedX`), so each canary gets its own block and the helpers get none.

| Property | Module | Status | Evidence types | Intent (one line) |
|---|---|---|---|---|
| PersistedHeightRelationships | base.tla | requirement | comment, history, protocol, impl | Saved state ≤ block store ≤ saved state + 1, and app committed height ≤ block store. |
| SuccessfulApplyAdvancesExactlyOne | base.tla | requirement | protocol, test, impl | Between an accepted state update and its save, the new state is at the block's height, exactly one above the last saved state. |
| RejectedUpdateDoesNotInstall | base.tla | requirement | comment, contract, history, impl | A parameter update that fails validation does not advance the state or change its consensus params or change height. |
| ParameterUpdateReflected | base.tla | requirement | protocol, comment, test, history, impl | An accepted update is valid, becomes the state's consensus params, and records change height H+1. |
| NormalPhaseIsSynchronized | base.tla | requirement | protocol, test, history, comment, contract, impl | In normal operation between heights, app = block store = saved state, and the in-memory state equals the saved state. |
| RecoveryNormalOnlySupported | base.tla | requirement | protocol, contract, comment, test, impl | After a restart starts the handshake, normal operation resumes only after the handshake completes with app and saved state caught up with the block store. |
| TypeOK | base.tla | model-internal | none | Every model variable stays inside its declared domain. |
| MCTypeOK | MC.tla | model-internal | none | TypeOK, plus the model-checking counters stay within their bounds. |
| NeverReachedAcceptedUpdate | MC.tla | model-internal | none | Reachability canary (expected to be violated): an accepted parameter update can be reached. |
| NeverReachedRejectedUpdate | MC.tla | model-internal | none | Reachability canary (expected to be violated): a rejected parameter update can be reached. |
| NeverReachedCrash | MC.tla | model-internal | none | Reachability canary (expected to be violated): a crash can be reached. |
| NeverReachedAppOnlyReplay | MC.tla | model-internal | none | Reachability canary (expected to be violated): app-only handshake replay can be reached. |
| NeverReachedRealReplay | MC.tla | model-internal | none | Reachability canary (expected to be violated): real-app replay of the last block can be reached. |
| NeverReachedMockReplay | MC.tla | model-internal | none | Reachability canary (expected to be violated): mock-app replay of the last block can be reached. |
| NeverReachedHandshakeComplete | MC.tla | model-internal | none | Reachability canary (expected to be violated): handshake completion can be reached. |
| TraceMatched | Trace.tla | model-internal | none | Trace validation consumes every event in the recorded trace. |

## Counts by status

| Status | Count |
|---|---|
| requirement | 6 |
| impl-abstraction | 0 |
| mixed | 0 |
| unknown | 0 |
| model-internal | 10 |
| **total** | **16** |

## Strength of evidence (my assessment, weakest first)

1. **NormalPhaseIsSynchronized**, the clause "in-memory state equals saved state" (stateHeight, activeParam, lastParamChange). The only support is API doc comments (`ApplyBlock` "saves the new state", `Store.Save` "overwrites the previous state with the updated one") and the `node.go` comment explaining why the state is reloaded after the handshake. No spec text supports it. The height clause has spec and test evidence.
2. **SuccessfulApplyAdvancesExactlyOne**. The protocol equation `state(h+1) <- Execute(state(h), …)` supports "one above the state the block ran on". That this input state is the *saved* state is supported only by code.
3. **RecoveryNormalOnlySupported**. The spec grammar and the handshake tests support "normal after replay, synced". The "handshake completed" part is supported only indirectly (the spec's order of recovery steps, plus the `finalizeCommit` comment).
4. **ParameterUpdateReflected**, the validity clause. Support comes from per-parameter "Must have" rules in the spec, a commit message (0bc539924), and unit tests of `ValidateUpdate`. No test sends an invalid update through `updateState`.
5. **PersistedHeightRelationships**, **RejectedUpdateDoesNotInstall**. Several independent source comments plus spec or history text state these directly.
