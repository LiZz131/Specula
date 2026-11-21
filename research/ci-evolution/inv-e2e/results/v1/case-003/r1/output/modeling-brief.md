# Modeling Brief: CometBFT state execution and recovery — V1 incremental update

V1 status: updated for the source update `9dd6e50` (baseline) → `401753b`
(update), which rewrites `ConsensusParams.ValidateUpdate`
(`types/params.go:208-261`). Disposition: **MODEL_CHANGE_REQUIRED** (see
`analysis-report.md` §1-§3). Sections marked V1 supersede the V0 text kept
below; V0 Scenarios 1-3 remain in force with the noted rechecks.

## V1-1. System overview delta

- Category stays **A** (single node; app, block store and state store advance
  at separate durable boundaries). No concurrency or persistence-order change.
- Changed mechanism: the accept/reject decision for a FinalizeBlock
  consensus-parameter update now depends on the current
  `VoteExtensionsEnableHeight` `P`, whether `updates.Abci` is present, the
  updated value `U`, and the height `h` of the block being finalized.
- Consequence boundary (unchanged code): a rejection happens after the
  FinalizeBlock response is durable (`internal/state/execution.go:253-256`),
  makes `ApplyBlock` fail (`:279-282`), panics consensus/block sync
  (`internal/consensus/state.go:1834-1836`,
  `internal/blocksync/reactor.go:530-533`), and recurs on every restart
  because real/mock final-block replay re-runs the same validation
  (`internal/consensus/replay.go:399-433`). A rejection is therefore a chain
  halt, not a soft error.

## V1-2. Update Scenarios

### Scenario U1: Enable vote extensions from the disabled state (row 7)
- **Path**: old producer (app FinalizeBlock returns `Abci{U > h}` with `P = 0`)
  → changed `UpdateStateAccepted` → old consumers `CommitApp`, `SaveState`,
  next `SaveBlock`.
- **Evidence**: `types/params.go:249-252` (new nil) vs
  `9dd6e50:types/params.go:223-228` (old error); contract
  `spec/abci/abci++_app_requirements.md:1118-1131`.
- **Uncertainty**: is the new acceptance installed with `lastParamChange = h+1`
  and persisted; does any other path still reject it?
- **Properties**: `EnableFromDisabledNotRejected` (new), `ParameterUpdateReflected`,
  `NormalPhaseIsSynchronized` (kept). **Trace**: `ve_enable_future`.

### Scenario U2: Re-sent unchanged enable height after it is reached (row 6)
- **Path**: old producer (an app forwarding its complete parameter set; in-tree
  pattern `state_test.go:TestConsensusParamsChangesSaveLoad` uses
  `cp.ToProto()`, and `ToProto` always sets `Abci`, `types/params.go:320-341`)
  with `P = U > 0`, `P <= h` → changed `UpdateStateRejectedVE` →
  `AbortRejectedApply` (panic) → crash/recovery → `SelectRealReplay` or
  `SelectMockReplay` → same rejection.
- **Evidence**: new row 6 `types/params.go:243-248`; removed old equality
  short-cut `9dd6e50:types/params.go:212-214`; contract
  `abci++_app_requirements.md:776-777,783-790,800-807`; old test
  `old-source/types/params_test.go:196-204`; contested by new test data
  `new-source/types/params_test.go:168-169`.
- **Uncertainty**: does the implementation reject a byte-identical parameter
  value, and does restart replay re-reject it (permanent halt)?
- **Properties**: `UnchangedVENotRejected` (new, bug candidate E1).
  **Traces**: `ve_echo_reached`, `ve_echo_restart_apply`,
  `ve_echo_restart_handshake`.

### Scenario U3: Cancel a not-yet-reached enable height (row 5)
- `P > h`, `U = 0`: new nil (`types/params.go:240-241`), old error
  (`9dd6e50:types/params.go:215-217`). Properties `VEReachedImmutable`
  (antecedent false), `ParameterUpdateReflected`. **Trace**: `ve_disable_future`.

### Scenario U4: Reached enable height is frozen (rows 4, 8)
- `P > 0`, `P <= h`, `U != P` must be rejected; requirement
  `abci++_app_requirements.md:760-777`. Property `VEReachedImmutable`.
  **Traces**: `ve_disable_reached`, `ve_move_reached`.

### Scenario U5: Only future enable heights are accepted (rows 6, 7, 9)
- Requirement `abci++_app_requirements.md:776,1126-1129`. Property
  `VEChangeOnlyToFuture`. **Traces**: `ve_enable_current`, `ve_move_future`,
  `ve_echo_future`, `ve_echo_disabled` (row 3), `ve_negative` (row 2 masked by
  `ValidateBasic`, `execution.go:617-620`).

### Scenario U6: Changed decision across crash windows and replay
- `old context → changed action → crash/recovery`: a VE change accepted at `h`,
  app committed, crash before `SaveState` → mock replay re-validates the saved
  response with the same `(P, h)`; a VE change rejected at `h` → real replay
  re-rejects. Properties: all update properties plus
  `NormalPhaseIsSynchronized`, `RecoveryNormalOnlySupported`. MC:
  `Update_hunt_recovery.cfg`, canary `Update_reach_mock_replay_ve_change.cfg`.
  Trace: `ve_echo_restart_handshake` (real replay re-rejection); prior
  `replay_real`/`replay_mock` traces (unchanged-path regression).

### Scenario U7: Changed action → changed action
- Block 1 enables at `h_e = 2` (row 7); block 2 at `h = 2` forwards the
  unchanged set (row 6). **Trace**: `ve_enable_then_echo`. MC:
  `Update_hunt_unchanged.cfg` (three heights).

## V1-3. Modeling decisions (supersede V0 §3.1 parameter row)

| What | Why | How |
|---|---|---|
| Parameter record `[other, veh]` | ValidateUpdate reads only VEH; everything else stays symbolic | `Params == [other: Others, veh: VEHeights]` |
| `ValidateBasic` = `other \in ValidOthers /\ veh >= 0` | `types/params.go:145-205`; VEH clause `:188-190` | `ValidateBasicOK` |
| Row-faithful `ValidateUpdateRow` | the update is a decision table | `base.tla` nested IF, one branch per row |
| `updates.Abci` presence | row 1; `Update` keeps VEH when absent (`params.go:314-316`) | `FinalizeBlock(p, abci)`, `pendingAbciPresent`, `responseAbciPresent` |
| Split rejection | different code paths/inputs (`execution.go:617-620` vs `:622-625`) | `UpdateStateRejectedBasic`, `UpdateStateRejectedVE` |
| Trace computes the decision | V0 derived `ValidParams` from observed acceptances | `Trace.tla` reconstructs only the non-ABCI basic validity |

Exclusions unchanged from V0 §3.2. Additional exclusion: rolling binary
upgrades across a restart (old validation before the crash, new validation at
replay) are not modeled; the model has a single code version. The
`updates == nil` guard added to row 1 is unreachable from `updateState`
(`execution.go:615`) and is not modeled separately.

## V1-5. Proposed invariants (update)

| Invariant | Type | Scenario | Location |
|---|---|---|---|
| `VEReachedImmutable` | Safety | U4 | `Update.tla` |
| `VEChangeOnlyToFuture` | Safety | U5 | `Update.tla` |
| `EnableFromDisabledNotRejected` | No-halt (safety form) | U1 | `Update.tla` |
| `UnchangedVENotRejected` | No-halt (safety form) | U2, U7 | `Update.tla` |
| `InstalledParamsBasicValid` | Structural | U5 | `base.tla` |
| `ValidationInputStable` | Structural | all | `base.tla` |

Kept V0 invariants: `TypeOK`, `PersistedHeightRelationships`,
`SuccessfulApplyAdvancesExactlyOne`, `RejectedUpdateDoesNotInstall`,
`ParameterUpdateReflected`, `NormalPhaseIsSynchronized`,
`RecoveryNormalOnlySupported` (decisions in `spec/invariant-evidence.json`).

## V1-6. Findings pending verification

### Model-checkable
| ID | Description | Property | Scenario |
|---|---|---|---|
| V1-MC-1 | Can a contract-compliant unchanged VEH update be rejected (permanent halt)? | `UnchangedVENotRejected` | U2, U7 |
| V1-MC-2 | Can enabling from 0 to a future height still be rejected? | `EnableFromDisabledNotRejected` | U1 |
| V1-MC-3 | Can an accepted update move/disable a reached VEH or set a past one? | `VEReachedImmutable`, `VEChangeOnlyToFuture` | U4, U5 |
| V1-MC-4 | Does replay after crash re-validate consistently? | all update properties | U6 |

### Code-review-only
| ID | Description |
|---|---|
| V1-CR-1 | `ValidateUpdate` accepts unchanged re-sends in rows 3 and 9 but rejects them in row 6: the same "no change" input is treated differently depending on `h` (code-path inconsistency). Covered by V1-MC-1. |
| V1-CR-2 | Row 2 (`U < 0`) is unreachable from `updateState` because `nextParams.ValidateBasic()` runs first (`execution.go:617-620`). No consequence. |

---

# V0 baseline brief (retained; superseded where V1 sections apply)


## 1. System Overview

- **System**: supplied exact-old CometBFT tree; Go; 5,027 lines in the binding source-map files.
- **Category**: Category A (distributed/message-passing). CometBFT, the ABCI application, block store, and state store cross distinct synchronous and durable boundaries and may report different heights after a crash (`scope.md`; `internal/state/execution.go:253-299`).
- **Modeled protocol**: execution, persistence, and startup replay for a decided block, with consensus-parameter updates returned by `FinalizeBlock`.
- **Architectural choice**: the block, latest `FinalizeBlockResponse`, application state, and CometBFT state are persisted in a fixed order rather than one transaction (`internal/consensus/state.go:1781-1827`; `internal/state/execution.go:253-299`).
- **Concurrency/atomicity**: ABCI calls are synchronous at this boundary, but process crash may occur between block-store save, response save, application `Commit`, and state-store save (`spec/abci/abci++_app_requirements.md:271-299,899-950`).
- **Threat boundary**: crash/restart and application/state/store height skew only. Byzantine voting, transaction contents, evidence gossip, and cryptography are excluded by `scope.md`.
- **Evidence policy**: code-only exact-old analysis. Archaeology, history, issues, upstream material, and post-old behavior were not consulted.

## 2. Scenarios

### Scenario 1: Parameter update validation and installation

**Mechanism**: `FinalizeBlock` may return a complete or partial consensus-parameter update; the candidate is applied to a copy, checked by `ValidateBasic` and `ValidateUpdate`, and installed only if both checks succeed.

**Evidence**:
- `types/params.go:143-205` enforces the basic parameter domain.
- `types/params.go:208-229` enforces old-tree vote-extension update rules.
- `types/params.go:256-286` copies the existing parameter record and replaces each non-nil subrecord in full.
- `internal/state/execution.go:611-631` applies, validates, and records a successful change for height `H+1`; error returns preserve the input state.

**Affected code paths**: `ConsensusParams.Update`, `ConsensusParams.ValidateBasic`, `ConsensusParams.ValidateUpdate`, `updateState`, `BlockExecutor.ApplyBlock`.

**Suggested modeling approach**:
- Variables: `activeParam`, `persistedParam`, `pendingParam`, `lastParamChange`, `validationOutcome`.
- Actions: `FinalizeBlock`, `SaveFinalizeBlockResponse`, `UpdateStateAccepted`, `UpdateStateRejected`.
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

## 3. Modeling Recommendations

### 3.1 Model

| What | Why | How |
|---|---|---|
| Symbolic complete consensus-parameter identity | Scenario 1 requires equality, replacement, validation, and persistence but not arithmetic over every field | finite `Params`, `ValidParams`, and fingerprints in implementation traces |
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

### 6.3 Code-Review-Only

| ID | Description | Suggested action |
|---|---|---|
| V0-CR-1 | `ExecCommitBlock` intentionally bypasses historical CometBFT state mutation because old state is unavailable (`internal/consensus/replay.go:449-455`) | preserve as an explicit abstraction boundary, not a defect claim |

## 7. Reference Pointers

- Full analysis report: `analysis-report.md`
- Binding scope: `/work/scope.md`
- Core sources: `types/params.go`, `internal/state/execution.go`, `internal/state/state.go`, `internal/state/store.go`, `internal/consensus/replay.go`, `internal/consensus/state.go`, `node/node.go`, `node/setup.go`, `proxy/app_conn.go`, `proto/cometbft/abci/v1/types.proto`, `spec/abci/abci++_app_requirements.md`
- No historical or external references were used.
