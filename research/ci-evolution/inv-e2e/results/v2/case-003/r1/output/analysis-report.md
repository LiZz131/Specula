# Exact-old code analysis report

## Scope and isolation

This report analyzes only the supplied exact-old code under `/work/source` and the binding `/work/scope.md`. The source has one neutral synthetic commit; the requested archaeology/history/issue phase was replaced by code-only structural and deep analysis. No remotes, external research, future revision, fixed revision, benchmark label, or prior answer was inspected.

Category A applies because the modeled components cross process and durable-storage boundaries. Byzantine consensus behavior is explicitly excluded even though CometBFT as a whole implements BFT consensus.

## Coverage

The seven binding source-map files were read completely: `types/params.go` (334 lines), `internal/state/execution.go` (763), `internal/state/state.go` (353), `internal/consensus/replay.go` (544), `node/node.go` (1,080), `proxy/app_conn.go` (231), and `spec/abci/abci++_app_requirements.md` (1,145). Relevant ABCI aliases/interfaces and generated/proto request-response definitions were also read. Control-flow following added `internal/state/store.go`, `internal/state/services.go`, `internal/consensus/state.go:1740-1861`, `internal/blocksync/reactor.go:490-550`, and `node/setup.go:187-203`.

The binding focused tests were read at their target functions. Test assertions were used only after confirming each behavior in production code.

## Structural map

| Component | Entry/state | Durable effect |
|---|---|---|
| Consensus finalization | `internal/consensus/state.go:1741-1861` | saves block before invoking `ApplyBlock` |
| Block execution | `internal/state/execution.go:205-315` | sequences finalization, response save, app commit, state save |
| Parameter transition | `internal/state/execution.go:585-652`; `types/params.go:143-286` | computes and validates the next-height parameter record |
| State serialization | `internal/state/state.go:40-224` | retains current params and last-change height |
| State store | `internal/state/store.go:204-243,562-601,798-870` | sync-writes state, latest response, and parameter history |
| Application boundary | `proxy/app_conn.go:18-27,103-110`; `abci/types/application.go:7-35` | synchronous `FinalizeBlock` and `Commit` |
| Startup | `node/node.go:304-361`; `node/setup.go:187-203` | runs handshake before normal node services and reloads state |
| Recovery | `internal/consensus/replay.go:240-521` | selects replay using app/store/state heights |

## Exact-old parameter behavior

`ConsensusParams.Update` begins with a value copy and replaces a subrecord only when the corresponding protobuf pointer is non-nil (`types/params.go:256-286`). A present subrecord is replaced in full, so omitted scalar fields within that subrecord take protobuf zero values. The old application contract states the same behavior (`spec/abci/abci++_app_requirements.md:779-807`).

`updateState` computes this candidate, applies `ValidateBasic`, then old-tree update-specific validation (`internal/state/execution.go:611-625`). Only after both succeed does it update the app protocol version and set `LastHeightConsensusParamsChanged = H+1` (`internal/state/execution.go:627-630`). Its returned state has `LastBlockHeight = H`, active `ConsensusParams = nextParams`, and no application hash until after `Commit` (`internal/state/execution.go:635-652`). On either validation error it returns the input state.

The symbolic model uses a fingerprint for a complete parameter record and a finite `ValidParams` relation. This preserves complete-record identity, optional update, acceptance/rejection, installation, last-change height, persistence, and replay. Arithmetic for each individual parameter field remains covered by old-tree tests rather than duplicated in TLA+.

## Atomicity and failure boundaries

The observable ordering is:

1. consensus/block sync saves block `H` (`internal/consensus/state.go:1781-1790`; `internal/blocksync/reactor.go:516-529`);
2. `ApplyBlock` validates the block and synchronously calls application `FinalizeBlock` (`internal/state/execution.go:211-234`);
3. CometBFT sync-saves the latest `FinalizeBlockResponse` (`internal/state/execution.go:253-256`; `internal/state/store.go:562-601`);
4. parameter/validator response data is validated and an in-memory next state is constructed (`internal/state/execution.go:260-282,585-652`);
5. application `Commit` persists app state (`internal/state/execution.go:284-288,370-418` and the contract at `spec/abci/abci++_app_requirements.md:271-299`);
6. CometBFT saves the state and parameter history in a sync database batch (`internal/state/execution.go:295-299`; `internal/state/store.go:204-243,848-870`).

A crash loses only the staged/in-memory CometBFT values in the abstraction. The block, last response, application committed height, and saved CometBFT state survive according to which calls returned. No arbitrary disk corruption, message loss, or independent store reordering is introduced.

## Recovery decision table

Let `B` be block-store height, `A` application height reported by `Info`, and `S` saved CometBFT state height.

| Preconditions | Exact-old path | State mutation |
|---|---|---|
| `B = 0` | compare app hash with state; return | no replay |
| `B = S`, `A < B` | `replayBlocks(..., mutateState=false)` using `ExecCommitBlock` | app only |
| `B = S`, `A = B` | assert hash and return | none |
| `B = S+1`, `A < S` | app-only replay through `S`, then `replayBlock` for `B` | final block only |
| `B = S+1`, `A = S` | real-app `replayBlock` for `B` | yes |
| `B = S+1`, `A = B` | load saved response, use mock app, `replayBlock` for `B` | CometBFT state only |

The guards are `internal/consensus/replay.go:358-438`. The app-only and final-block implementations are `internal/consensus/replay.go:441-521`. Unsupported conditions include `A>B`, `S>B`, `B>S+1`, and app height too far below a pruned block-store base (`internal/consensus/replay.go:358-383`).

## Error-path classification

An invalid block or failed `FinalizeBlock` returns before response persistence. A response-save error returns before candidate validation. A parameter validation error occurs after the response can be durable but before application `Commit`; it returns the old `State` value (`internal/state/execution.go:253-282`). A `Commit` failure leaves the block and response durable but state unsaved. A state-save failure leaves both the application and response at `H` while state remains at `H-1`, which is the mock-replay case.

These are code-derived state classes, not incident claims. The V0 asks whether the bounded abstraction maintains the neutral properties across all such cuts.

## Instrumentation plan resulting from analysis

The writable copy emits one NDJSON event at each modeled boundary: `BlockStored`, `ApplyBlockStart`, `FinalizeBlock`, `SaveFinalizeBlockResponse`, `UpdateStateAccepted`/`UpdateStateRejected`, `CommitApp`, `SaveState`, `HandshakeStart`, `ReplayAppBlock`, `ReplayStateBlockStart`, and `HandshakeComplete`. Every event records the three durable heights, volatile state height, active/persisted parameter fingerprints, last-change heights, saved response metadata, replay mode, phase, and validation result.

No event is synthesized by a standalone model. Apply traces run actual `BlockExecutor.ApplyBlock`; recovery traces run actual `Handshaker.Handshake` and replay functions against the old test infrastructure.

## Analysis outcome

No known incident was sought or asserted. The code-only analysis yielded three verification scenarios and no directly confirmed implementation defect. Bounded TLC and trace replay results are recorded separately; any environmental or state-space limits are reported as limited coverage rather than proof.

---

# Incremental update analysis (case-003 `update` commit)

## Exact inputs

| Item | Identity |
|---|---|
| Old source | `/work/old-source/` = artifact commit `9dd6e50` ("baseline"); `types/params.go`, `types/params_test.go` |
| New source | `/work/new-source/` = artifact commit `401753b` ("update"); same two files plus `.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md` |
| Prior suite | `/work/previous/.specula-output/` (V0, exact-old; no unresolved findings; LIMITED_COVERAGE) |
| Diff scope | only `ConsensusParams.ValidateUpdate` (types/params.go:208-262) and its unit test changed; no caller, store, replay, or consensus file changed |

`git diff 9dd6e50 401753b -- types/params.go` equals `diff old-source new-source`; the
changelog entry is the only non-code addition. No history, issue, advisory, or
external material was consulted (the changelog link was not followed).

## Changed behavior (code reading, both revisions)

The single caller is `updateState` (internal/state/execution.go:614-631):
`nextParams = Update(...)`, then `nextParams.ValidateBasic()`, then
`state.ConsensusParams.ValidateUpdate(updates, header.Height)`; an error makes
`ApplyBlock` fail before application `Commit` (execution.go:279-282), which
consensus treats as fatal (internal/consensus/state.go:1834-1836). Because
`ValidateBasic` runs first and rejects a negative enable height
(types/params.go:188-190), and installed params always passed it, the reachable
domain is E = current enable height >= 0, U = proposed height (any int), h = block
height >= 1. Projection of every branch onto (E, U, h):

| Cell | Old (9dd6e50) | New (401753b) | New row |
|---|---|---|---|
| Abci nil | accept | accept | 1 |
| U < 0 | reject (ValidateBasic) | reject (ValidateBasic) | basic (row 2 unreachable via updateState) |
| E = 0, U = 0 | accept (equal) | accept | 3 |
| E = 0, 0 < U <= h | reject | reject | 6 |
| **E = 0, U > h** | **reject** ("cannot be modified once the initial height has occurred") | **accept** | 7 |
| 0 < E <= h, U = 0 | reject | reject | 4 |
| **0 < E <= h, U = E** | **accept** (first branch: equal) | **reject** ("cannot be updated to a past or current height") | 6 |
| 0 < E <= h, 0 < U <= h, U != E | reject | reject | 6 |
| 0 < E <= h, U > h | reject | reject | 8 |
| **E > h, U = 0** | **reject** ("cannot be disabled once enabled") | **accept** | 5 |
| E > h, 0 < U <= h | reject | reject | 6 |
| E > h, U > h (incl. U = E) | accept | accept | 9 |

`updated == nil` (row 1's new nil check) is unreachable from `updateState`, which
only calls ValidateUpdate for a non-nil update.

Three cells flip. They are directly visible in the modeled `UpdateStateAccepted`
/ `UpdateStateRejected` enablement, and V0's fixed `ValidParams` could not express
any of them (V0 validity was independent of height and current params). Code
observation on both revisions (`spec/output/observe-old.log`,
`spec/output/observe-new.log`, scenarios O1-O13) confirms the table through the
real `ApplyBlock` path.

## Decision: `MODEL_CHANGE_REQUIRED`

The update changes the enablement of modeled actions (accept/reject of a
parameter update) and the correctness requirements around the enable height.
Representation chosen (Chapter 2): parameter record `[rest, ve]`, update record
`[present, rest, abciPresent, abci]`, explicit `ValidateUpdateRow` following the
new branch order, `rejectRule`, and a durable per-height enable-height history
`veHist` for the unchanged consumers. Category A, granularity, durable
boundaries, crash windows and the replay matrix are unchanged.

## Interactions of the changed action with unchanged code

| Path | Code | Model | Evidence |
|---|---|---|---|
| producer → changed → durable | app `FinalizeBlock` → response saved (execution.go:252-256) → `updateState` | FinalizeBlock → SaveFinalizeBlockResponse → UpdateState* | traces `ve_*` |
| changed → consumer (save-time) | extended-commit decision uses the enable height in effect (consensus/state.go:1786) | `SaveBlock` appends `veHist` | `VEHistoryStable`, canary `ve_enabled_block` |
| changed → consumer (later) | restart `reconstructLastCommit` (consensus/state.go:589-600), block-sync serving (blocksync/reactor.go:219) use the *current* enable height for past heights | `VEHistoryStable`, `StartupLastCommitConsistent` | MC: no violation |
| changed → crash → recovery | mock replay re-validates the saved update; real replay re-executes and re-validates (replay.go:403-433) | SelectMockReplay/SelectRealReplay → UpdateState* | traces `replay_mock_ve_update`, `replay_real_ve_update` |
| rejected → crash → recovery | a rejected update is re-executed on restart and rejected again; handshake fails (replay.go:266-270) | AbortRejectedApply → BeginHandshake → SelectRealReplay → UpdateStateRejected | trace `replay_real_ve_unchanged_rejected` |
| app-only catch-up | `ExecCommitBlock` never validates params (replay.go:441-489) | ReplayAppBlock (omitted from focus, EnvUpdate + discharge) | `Update_discharge.cfg` |

The new code keeps `VoteExtensionsEnabled(m)` for every already-decided height m
invariant across later parameter changes (row 6 forbids U <= h; rows 4/8 freeze a
reached height), so the save-time and later consumer decisions agree. This is
checked by `VEHistoryStable` over all campaigns with no violation.

## Update-attributable candidate (MC-1)

Row 6 now also rejects an Abci subrecord that repeats the current, already
reached enable height (U = E, 0 < E <= h). The old revision accepted exactly that
input (first branch `params == updated`; removed V0 test "no error when
unchanged", /work/old-source/types/params_test.go:196-204). The protocol text says
the application must not *change* the value once non-zero
(spec/abci/abci++_app_requirements.md:776-777), that each non-empty field is
applied in full (:785-786), and that CometBFT uses a non-nil update (:803); the
in-tree producer pattern `cp.ToProto()` (always includes Abci) is used as a
per-block update by `TestConsensusParamsChangesSaveLoad`
(internal/state/state_test.go:1044). The updated unit test instead expects an
error for "current: 100, 100 -> 100" and "current: 300, 100 -> 100"
(types/params_test.go:168-169), and :776 says the height "Must always be set to a
future height". The requirement for this cell is therefore contested; the
property `UnchangedVEUpdateNotRejected` was not weakened toward the
implementation, its counterexample is recorded as MC-1, and the conflict is stated
in `spec/bug-report.md`. Consequence on the real code: `ApplyBlock` fails, the
node halts, and every restart re-executes and rejects the same block
(`traces/replay_real_ve_unchanged_rejected.ndjson`); since validation is
deterministic, all nodes halt at that height.

## Exclusions retained

Unchanged from V0 (Byzantine behavior, transactions, validator updates,
pruning, InitChain parameter validation, state sync). InitChain may set the enable
height without `ValidateUpdate` (replay.go:346-347); this path is unchanged by the
update and stays outside the model.
