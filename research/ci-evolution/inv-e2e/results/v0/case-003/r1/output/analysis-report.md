# Code analysis report — V0 (exact-old) + V1 incremental update

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

**[V1]** The V0 symbolic model used a fingerprint for a complete parameter record and a finite `ValidParams` relation (superseded, see the V1 section below). This preserves complete-record identity, optional update, acceptance/rejection, installation, last-change height, persistence, and replay. Arithmetic for each individual parameter field remains covered by old-tree tests rather than duplicated in TLA+.

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


## V1 incremental update analysis (`baseline` -> `update`)

### Inputs and identity

- Updated tree: `artifact/` commit `update` (`401753b0…`); old: commit
  `baseline` (`9dd6e508…`). Changed files: `types/params.go`,
  `types/params_test.go`, `.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md`.
- Only `ConsensusParams.ValidateUpdate` changed in production code
  (`types/params.go:208-261`). Its single production caller is `updateState`
  (`internal/state/execution.go:622`), reached from `ApplyBlock` in consensus
  (`internal/consensus/state.go:1826`), blocksync, and handshake replay
  (`internal/consensus/replay.go:504-521`). `ExecCommitBlock` (app-only replay)
  does not validate parameters.
- The prior V0 run had no unresolved errors or findings.

### Old vs new rule (projection onto the model vocabulary)

With `c` the current enable height, `u` the proposed one and `h = header.Height`
(`ValidateBasic` runs first and rejects `u < 0` in both versions):

| class | old | new |
|---|---|---|
| `Abci == nil` | accept | accept |
| `u = c` and `~Enabled(c,h)` | accept | accept |
| `u = c` and `Enabled(c,h)` (unchanged re-send after enablement) | **accept** | **reject** (row 6) |
| `c = 0, u > h` (first enablement) | **reject** | **accept** (row 7) |
| `c > h, u = 0` (cancel a future height) | **reject** | **accept** (row 5) |
| other changes | reject unless `u > h /\ c > h` | same |

Closed form of the new rule: accept iff `u >= 0 /\ ~Enabled(c,h) /\ ~Enabled(u,h)`
(`Enabled(v,h) = v /= 0 /\ v <= h`, `types/params.go:75-83`). Verified on an
exhaustive grid by `spec/analysis/validate_update_projection.py`.

### Interactions (Chapter 3)

- Producers: the application's `FinalizeBlockResponse.ConsensusParamUpdates`.
  Contract: non-empty sub-records are applied in full and unchanged values are
  re-sent (`spec/abci/abci++_app_requirements.md:779-789`); the enable height
  "must not be changed" once non-zero (`:776-777`); first enablement must be at
  a height above the current one (`:1118-1129`). `ConsensusParams.ToProto`
  always fills `Abci` (`types/params.go:320-341`); in-repo tests build updates
  from complete parameter values (`internal/state/state_test.go:1044`).
- Consumers of the installed value: `reconstructLastCommit`
  (`internal/consensus/state.go:589-597`), blocksync
  (`internal/blocksync/reactor.go:384-386`), `buildExtendedCommitInfo`
  (`internal/state/execution.go:536-543`) evaluate `VoteExtensionsEnabled(k)`
  for the previous height with the new record. The new rule keeps those answers
  stable (accepting a change only when neither value is enabled at `h`).
- Error path: any rejection makes `ApplyBlock` fail before `Commit`; consensus
  panics and halts (`state.go:1834-1836`, recovered at `:791-803`); restart
  replays through the real app (`replay.go:408-415`) and fails again. A
  rejection of a contract-legal update is therefore a deterministic chain halt.
- Mock replay (`replay.go:417-433`) re-validates the saved response with the
  same inputs; acceptance must be reproducible.

### Outcome

The updated model (`spec/base.tla` V1) and `spec/Update.tla` were validated
against 20 fresh traces and model-checked (see `validation-report.md`). One
update-introduced defect was found and reproduced: MC-1
(`spec/bug-report.md`, `spec/confirmation-MC-1.md`).
