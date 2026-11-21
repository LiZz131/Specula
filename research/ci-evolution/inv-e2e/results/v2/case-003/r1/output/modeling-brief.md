# Modeling Brief: CometBFT state execution and recovery — updated revision (case-003)

> Incremental update over the V0 exact-old brief. Source delta: `ConsensusParams.ValidateUpdate` rewrite (types/params.go:208-262), commit `401753b` over `9dd6e50`. Disposition: `MODEL_CHANGE_REQUIRED` (see `analysis-report.md`, "Incremental update analysis"). Sections marked *[updated]* or *[new]* changed in this run; the rest is the V0 brief, rechecked against the new tree.

## 1. System Overview

- **System**: supplied exact-old CometBFT tree; Go; 5,027 lines in the binding source-map files.
- **Category**: Category A (distributed/message-passing). CometBFT, the ABCI application, block store, and state store cross distinct synchronous and durable boundaries and may report different heights after a crash (`scope.md`; `internal/state/execution.go:253-299`).
- **Modeled protocol**: execution, persistence, and startup replay for a decided block, with consensus-parameter updates returned by `FinalizeBlock`.
- **Architectural choice**: the block, latest `FinalizeBlockResponse`, application state, and CometBFT state are persisted in a fixed order rather than one transaction (`internal/consensus/state.go:1781-1827`; `internal/state/execution.go:253-299`).
- **Concurrency/atomicity**: ABCI calls are synchronous at this boundary, but process crash may occur between block-store save, response save, application `Commit`, and state-store save (`spec/abci/abci++_app_requirements.md:271-299,899-950`).
- **Threat boundary**: crash/restart and application/state/store height skew only. Byzantine voting, transaction contents, evidence gossip, and cryptography are excluded by `scope.md`.
- **Evidence policy**: code-only analysis of the supplied old/new trees and their neutral two-commit diff. Archaeology, history, issues, advisories, upstream material, and any fixed revision were not consulted.

## 2. Scenarios

### Scenario 1: Parameter update validation and installation *[updated]*

**Mechanism**: `FinalizeBlock` may return a complete or partial consensus-parameter update; the candidate is applied to a copy, checked by `ValidateBasic` and `ValidateUpdate`, and installed only if both checks succeed.

**Evidence**:
- `types/params.go:143-205` enforces the basic parameter domain.
- `types/params.go:208-262` (updated) enforces the nine-row enable-height decision table; acceptance now depends on the current enable height E, the proposed U and the block height h (old: lines 208-229).
- `types/params.go:256-286` copies the existing parameter record and replaces each non-nil subrecord in full.
- `internal/state/execution.go:611-631` applies, validates, and records a successful change for height `H+1`; error returns preserve the input state.

**Affected code paths**: `ConsensusParams.Update`, `ConsensusParams.ValidateBasic`, `ConsensusParams.ValidateUpdate`, `updateState`, `BlockExecutor.ApplyBlock`.

**Suggested modeling approach**:
- Variables: `activeParam`/`persistedParam` as `[rest, ve]` records, `pendingParam`/`responseParam` as update records `[present, rest, abciPresent, abci]`, `lastParamChange`, `validationOutcome`, `rejectRule` *[updated]*.
- Actions: `FinalizeBlock`, `SaveFinalizeBlockResponse`, `UpdateStateAccepted`, `UpdateStateRejected` (guards: `ValidateBasic` then `ValidateUpdateRow`).
- Granularity: split at response persistence and validation because a crash or rejection is externally distinguishable there.

**Priority**: High.  
**Rationale**: It is the binding state transition, and rejection must not install the candidate even though the response can already be durable.

### Scenario 2: Ordered durable boundaries during block application

**Mechanism**: block storage precedes application finalization; the response is saved before state mutation; application `Commit` precedes CometBFT state save.

**Evidence**:
- `internal/consensus/state.go:1781-1817` durably stores the decided block and WAL end-height before `ApplyBlock`.
- `internal/state/execution.go:219-256` calls `FinalizeBlock` and saves its response before validation/state update.
- `internal/state/execution.go:278-299` stages the next state, commits the app, and only then saves the state.
- `internal/state/store.go:562-601` synchronously persists the latest response specifically for crash recovery.
- `internal/state/store.go:204-243` synchronously saves state and the next-height consensus-parameter record in one database batch.

**Affected code paths**: consensus `finalizeCommit`, block-store `SaveBlock`, `BlockExecutor.ApplyBlock`, `BlockExecutor.Commit`, state-store `Save`.

**Suggested modeling approach**:
- Variables: `blockStoreHeight`, `appHeight`, `stateStoreHeight`, `stateHeight`, `responseHeight`, `phase`.
- Actions: `SaveBlock`, `ApplyBlockStart`, `FinalizeBlock`, `SaveFinalizeBlockResponse`, `CommitApp`, `SaveState`, `Crash`.
- Granularity: one action per old-tree durable boundary; in-memory validation/update may be one transition because no restart can observe its intermediate assignments.

**Priority**: High.  
**Rationale**: these are the exact crash windows consumed by startup recovery.

### Scenario 3: Height-matrix startup replay

**Mechanism**: startup chooses app-only replay, real-app last-block replay, saved-response/mock last-block replay, or no replay according to the application, block-store, and state-store heights.

**Evidence**:
- `node/node.go:304-361` starts the application, runs the handshake before normal services, then reloads any replay-mutated state.
- `node/setup.go:187-203` constructs and invokes the handshaker.
- `internal/consensus/replay.go:240-277` obtains the application's durable height using `Info` and invokes `ReplayBlocks`.
- `internal/consensus/replay.go:358-438` rejects/panics on unsupported height relationships and distinguishes the supported cases.
- `internal/consensus/replay.go:441-501` uses `ExecCommitBlock` for historical app-only replay and reserves the final block for state mutation when required.
- `internal/consensus/replay.go:504-521` reuses the real `ApplyBlock` path for a state-mutating replay.

**Affected code paths**: `NewNode`, `doHandshake`, `Handshaker.Handshake`, `ReplayBlocks`, `replayBlocks`, `replayBlock`, `ExecCommitBlock`.

**Suggested modeling approach**:
- Variables: the three durable heights, `phase`, `replayMutatesState`, and the persisted response/parameter value.
- Actions: `BeginHandshake`, `ReplayAppBlock`, `SelectRealReplay`, `SelectMockReplay`, `CompleteHandshake`.
- Granularity: app-only replay is one action per block; final state-mutating replay re-enters the same split ApplyBlock actions as normal execution.

**Priority**: High.  
**Rationale**: this is the exact-old recovery decision table and its supported cases are neutral V0 properties.

### Scenario 4: Enable-height lifecycle and its unchanged consumers *[new]*

**Mechanism**: the rewritten `ValidateUpdate` decides which enable-height transitions are installed; unchanged consumers read the enable height for *past* heights at different times (block save, restart reconstruction, block-sync serving), so every accepted transition must keep the enabled/disabled status of already-decided heights unchanged, and protocol-permitted transitions must not be rejected (a rejection halts the chain).

**Evidence**:
- `types/params.go:208-262` decision table (rows 1-9); `types/params.go:73-83` `VoteExtensionsEnabled`.
- `internal/consensus/state.go:1786` saves an extended commit iff enabled at the block height under the params in effect; `internal/consensus/state.go:589-600` reconstructs `LastCommit` at restart from the *current* params; `internal/blocksync/reactor.go:219` serves past heights using the current params.
- `spec/abci/abci++_app_requirements.md:762-777,1121-1133`; `spec/abci/abci++_comet_expected_behavior.md:269-281`.
- `.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md`: the update targets validation-caused chain halts.

**Affected code paths**: `ConsensusParams.ValidateUpdate`, `updateState`, `BlockExecutor.ApplyBlock`, `State.finalizeCommit`, `State.reconstructLastCommit`.

**Suggested modeling approach**: `veHist` (durable per stored height) appended by `SaveBlock`; properties `VEHistoryStable`, `VEEnableMonotone`, `StartupLastCommitConsistent`, `AcceptedVEUpdateRespectsRules`, `PermittedVEUpdateNotRejected`, `UnchangedVEUpdateNotRejected`; hunt `Update_hunt_scenario4_ve_lifecycle.cfg` (5 heights, 7 enable-height values, no faults).

**Priority**: High. **Rationale**: directly changed mechanism; both a safety consumer (history stability) and a liveness-critical rejection path.

### Scenario 5: Enable-height update across a crash and the replay re-validation *[new]*

**Mechanism**: a response carrying an enable-height update is durable before validation; after a crash, mock replay (app committed) or real replay (app not committed) re-runs `updateState` on the saved/re-executed update with the persisted params, and a rejected update is re-executed and rejected again on every restart.

**Evidence**: `internal/state/execution.go:252-256,279-282,295-299`; `internal/consensus/replay.go:403-433,505-521`; real traces `replay_mock_ve_update`, `replay_real_ve_update`, `replay_real_ve_unchanged_rejected`.

**Suggested modeling approach**: existing `Crash`, `SelectMockReplay`, `SelectRealReplay`, FinalizeBlock determinism guard; canaries `ve_update_mock_replay`, `ve_update_real_replay`; hunt `Update_hunt_scenario5_ve_recovery.cfg` (3 crashes, app rollback).

**Priority**: High. **Rationale**: old context → changed action → crash/recovery interaction.

## 3. Modeling Recommendations

### 3.1 Model

| What | Why | How |
|---|---|---|
| Parameter record `[rest, ve]` *[updated]* | Scenario 1/4: validity now depends on the enable height and block height; other fields need only identity and basic validity | `rest` = fingerprint of all non-ABCI fields (symbolic `ValidRest`), `ve` = explicit integer; update record keeps Abci presence (an unchanged Abci value differs from an absent one) |
| Per-height enable-height history *[new]* | Scenario 4 consumers read the enable height for past heights | `veHist`, appended by `SaveBlock`; traces read the state-store params history |
| Volatile versus persisted state | Scenarios 1–2 contain visible crash windows | separate `stateHeight/activeParam` from `stateStoreHeight/persistedParam` |
| Persisted latest FinalizeBlock response | mock replay depends on it | `responseHeight` and `responseParam` survive `Crash` |
| All old height cases | Scenario 3 is branch-driven | explicit app-only, real, mock, and already-synced actions |
| Crash and app reporting an older durable height | both are accepted old-tree inputs | bounded MC wrappers; no arbitrary store corruption |

### 3.2 Do Not Model

| What | Why |
|---|---|
| Transactions and transaction results | excluded by scope; only result-count failure is relevant outside this state abstraction |
| Validator-set transitions | separate two-height mechanism and excluded from the parameter-focused V0 |
| Byzantine votes/rounds/evidence/crypto | expressly outside the neutral boundary |
| Application hash bytes | replay equality checks are represented by successful/failed case selection; hash algorithm is application-specific |
| Pruning internals | only the old height admissibility guard is relevant; deletion policy is outside the lifecycle |
| State sync | startup state sync bypasses this handshake and is excluded by the binding recovery objective |

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Parameter staging | `pendingParam`, `validationOutcome` | distinguish accepted and rejected candidates | 1 |
| Dual state view | `stateHeight`, `stateStoreHeight`, `activeParam`, `persistedParam` | expose pre-save crash behavior | 1, 2 |
| Durable response | `responseHeight`, `responseParam` | support saved-response/mock replay | 2, 3 |
| Startup case phase | `phase`, `replayMutatesState` | ensure normal startup follows an accepted branch | 3 |
| Reachability markers | `coverage` | preserve non-vacuity witnesses without changing implementation semantics | 1–3 |

## 5. Proposed Invariants

V0 invariants are kept (ParameterUpdateReflected modified: validity clause = `ValidateBasic(activeParam)`, installed value = `ApplyUpdate(persisted, pending)`). New update properties live in `UpdateProps.tla` (owned by `Update.tla`):

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `VEHistoryStable` | Safety | enable status of every stored height is the same under its own params and the current in-memory/saved params | 4, 5 |
| `VEEnableMonotone` | Safety | once a stored height requires extensions all later stored heights do | 4 |
| `StartupLastCommitConsistent` | Safety | restart reconstruction never needs an extended commit that was not stored | 4, 5 |
| `AcceptedVEUpdateRespectsRules` | Safety | accepted updates never disable/modify a reached height and only set 0 or a future height | 1, 4 |
| `PermittedVEUpdateNotRejected` | Safety (halt) | protocol-permitted enable-height updates are not rejected | 1, 4 |
| `UnchangedVEUpdateNotRejected` | Safety (halt), contested | an unchanged enable height re-sent is not rejected | 1, 4 |

V0 table:

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | heights, phases, parameter identities, and metadata remain well typed | all |
| `SuccessfulApplyAdvancesExactlyOne` | Safety | staged successful application is exactly one height beyond persisted state | 2 |
| `RejectedUpdateDoesNotInstall` | Safety | rejection leaves volatile height/parameter equal to persisted values | 1 |
| `PersistedHeightRelationships` | Safety | state/app never exceed block store and block store is at most one ahead of state | 2, 3 |
| `ParameterUpdateReflected` | Safety | an accepted non-empty update becomes active and records `H+1` | 1 |
| `NormalPhaseIsSynchronized` | Safety | normal startup/operation exposes equal app, block-store, and state-store heights | 3 |
| `RecoveryNormalOnlySupported` | Safety | handshake completion is possible only after old-tree replay establishes synchronized heights | 3 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

| ID | Description | Expected invariant violation if wrong | Scenario |
|---|---|---|---|
| V0-MC-1 | Can every crash cut between block save, response save, app commit, and state save recover without violating the persisted height matrix? | `PersistedHeightRelationships`, `NormalPhaseIsSynchronized` | 2, 3 |
| V0-MC-2 | Can an invalid parameter candidate become active or persisted after its response has already been saved? | `RejectedUpdateDoesNotInstall`, `ParameterUpdateReflected` | 1, 2 |
| V0-MC-3 | Do app-only, real-last-block, mock-last-block, and already-synced startup cases reach normal only after synchronization? | `RecoveryNormalOnlySupported`, `NormalPhaseIsSynchronized` | 3 |

### 6.2 Test-Verifiable

| ID | Description | Suggested test approach |
|---|---|---|
| V0-T-1 | Full parameter field validation and replacement semantics | run the binding `types.TestConsensusParams*` tests |
| V0-T-2 | State/response parameter persistence and lookup | run the binding state save/load tests |
| V0-T-3 | Concrete recovery paths | run the four binding handshake replay families |

### 6.1b Model-Checkable (update) *[new]*

| ID | Description | Expected invariant violation if wrong | Scenario |
|---|---|---|---|
| U-MC-1 | Can an accepted enable-height transition change the enabled status of an already-decided height (retroactive enable/disable)? | `VEHistoryStable`, `StartupLastCommitConsistent`, `VEEnableMonotone` | 4, 5 |
| U-MC-2 | Can a protocol-permitted enable/cancel/reschedule be rejected (halt), including after crash re-validation? | `PermittedVEUpdateNotRejected` | 4, 5 |
| U-MC-3 | Can an application that re-sends the unchanged enable height halt the chain? | `UnchangedVEUpdateNotRejected` (contested requirement) | 4 |

Results: U-MC-1 and U-MC-2 — no violation in any campaign; U-MC-3 — counterexample (MC-1, `spec/bug-report.md`).

### 6.3 Code-Review-Only

| ID | Description | Suggested action |
|---|---|---|
| V0-CR-1 | `ExecCommitBlock` intentionally bypasses historical CometBFT state mutation because old state is unavailable (`internal/consensus/replay.go:449-455`) | preserve as an explicit abstraction boundary, not a defect claim |
| U-CR-1 *[new]* | The update's own changelog/tests target validation-caused halts, yet row 6 halts on an unchanged reached height that the old code accepted; the updated unit test encodes the rejection | carried as MC-1 with the requirement conflict stated (no separate code-review finding) |
| U-CR-2 *[new]* | `updated == nil` guard in row 1 is unreachable from `updateState` (caller checks non-nil) | no action; recorded |
| U-CR-3 *[new]* | Row 2 (`must be positive`) is unreachable from `updateState` because `ValidateBasic` rejects a negative candidate first | no action; trace `ve_negative` shows the `basic` rejection |

## 7. Reference Pointers

- Full analysis report: `analysis-report.md` (V0 sections + "Incremental update analysis")
- Update lens: `spec/Update.tla`, `spec/UpdateProps.tla`; evidence: `spec/invariant-evidence.json`
- Binding scope: `/work/scope.md`
- Core sources: `types/params.go`, `internal/state/execution.go`, `internal/state/state.go`, `internal/state/store.go`, `internal/consensus/replay.go`, `internal/consensus/state.go`, `node/node.go`, `node/setup.go`, `proxy/app_conn.go`, `proto/cometbft/abci/v1/types.proto`, `spec/abci/abci++_app_requirements.md`
- No historical or external references were used (V0 and this update).
