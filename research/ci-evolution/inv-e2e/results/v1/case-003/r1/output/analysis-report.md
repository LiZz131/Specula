# Code analysis report — V1 incremental update (case 003)

This report extends the exact-old V0 analysis (retained verbatim below under
"V0 baseline analysis") for the supplied source update. Evidence is limited to
`/work/old-source`, `/work/new-source`, the two neutral synthetic commits in
`artifact/` (`9dd6e50` = baseline/old, `401753b` = update/new; `git show
9dd6e50:types/params.go` is byte-identical to `old-source/types/params.go` and
`artifact/types/params.go` to `new-source/types/params.go`), the prior suite,
and the scope file. No history, issue, advisory, upstream, or internet source
was consulted. The changelog file added by the update was read only as a
supplied source file; its link was not followed.

## 1. Exact inputs (Chapter 1 §1)

| Item | Value |
|---|---|
| Old revision | artifact commit `9dd6e50` (`baseline`), = prior V0 source |
| New revision | artifact commit `401753b` (`update`) |
| Changed files | `types/params.go` (M), `types/params_test.go` (M), `.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md` (A) |
| Changed function | `ConsensusParams.ValidateUpdate` only (`types/params.go:208-261` new; `:208-230` old) |
| Unchanged callers/consumers re-read | `updateState` (`internal/state/execution.go:585-652`, sole production caller at `:622`), `ApplyBlock` (`:211-316`), consensus `finalizeCommit` (`internal/consensus/state.go:1826-1836`, panics on error), block-sync (`internal/blocksync/reactor.go:529-533`, panics on error), handshake/replay (`internal/consensus/replay.go:241-438`), `ConsensusParams.Update` (`types/params.go:289-318`), `ValidateBasic` (`:145-205`), `ABCIParams.VoteExtensionsEnabled` (`:75-83`), `ToProto` (`:320-341`) |
| Prior suite status | V0 converged with `LIMITED_COVERAGE`, zero findings, six matched traces |

The system category stays **Category A** (single node's ABCI application,
block store and state store advancing at separate durable boundaries). The
update does not change concurrency, communication, or persistence order.

## 2. Behavior before and after the update

`updateState` applies the FinalizeBlock `ConsensusParamUpdates` to a copy,
runs `nextParams.ValidateBasic()` (`execution.go:617-620`) and then
`state.ConsensusParams.ValidateUpdate(updates, header.Height)`
(`execution.go:622-625`). Either error returns the input state; `ApplyBlock`
returns the error after the response is already durable
(`execution.go:253-256,279-282`), and both production callers panic
(`consensus/state.go:1834-1836`, `blocksync/reactor.go:530-533`). On restart
the stored block is replayed through the same `ApplyBlock`
(`replay.go:399-415` real app, `:417-433` saved-response mock app), so a
deterministic rejection recurs and the handshake fails (`replay.go:268-271`,
`node/setup.go:200`).

Let `P = state.ConsensusParams.ABCI.VoteExtensionsEnableHeight` (always
`>= 0`, because genesis and every installed update pass `ValidateBasic`,
`params.go:188-190`), `U = updates.Abci.VoteExtensionsEnableHeight`, `A` =
`updates.Abci != nil`, and `h = header.Height` (the block being finalized).

| Input class (A = true) | Old `ValidateUpdate` (`9dd6e50:types/params.go:208-230`) | New `ValidateUpdate` (`types/params.go:219-261`, row) | Projected change |
|---|---|---|---|
| `A = false` | nil | nil (row 1) | none |
| `U < 0` | rejected earlier by `ValidateBasic` | rejected earlier by `ValidateBasic` (row 2 masked) | none (reason `basic` in both) |
| `P = 0, U = 0` | nil (equal) | nil (row 3) | none |
| `P = 0, 0 < U <= h` | error | error (row 6) | none |
| `P = 0, U > h` | **error** (`P <= h` check, old `:223`) | **nil** (row 7) | reject → accept |
| `P > 0, U = 0, P <= h` | error | error (row 4) | none |
| `P > 0, U = 0, P > h` | **error** (old `:215`) | **nil** (row 5) | reject → accept |
| `P = U > 0, U <= h` | **nil** (old equality short-cut `:212-214`) | **error** (row 6) | accept → reject |
| `P = U > h` | nil | nil (row 9) | none |
| `P > 0, U > 0, U != P, U <= h` | error | error (row 6) | none |
| `P > 0, U > h, U != P, P <= h` | error | error (row 8) | none |
| `P > h, U > h, U != P` | nil | nil (row 9) | none |
| `updates == nil` | unreachable (caller guard `execution.go:615`) | nil (row 1, still unreachable from `updateState`) | none |

Error message text changed in rows 4, 6 and 8; messages are not modeled.

## 3. Disposition: `MODEL_CHANGE_REQUIRED`

Projected onto the V0 vocabulary, three input classes move between
`UpdateStateAccepted` and `UpdateStateRejected`, with different post-states
(active parameters and `lastParamChange = h+1` plus commit/save versus
rejection, abort, and deterministic replay rejection). The old and new
projected post-state sets are therefore unequal. In addition, the V0
abstraction cannot express the changed decision at all: `UpdateStateAccepted`
/`UpdateStateRejected` were guarded by membership of the resulting record in a
static `ValidParams` set, independent of the current parameters, of whether
the `Abci` sub-record was present, and of the height `h`. In V0 trace replay
`ValidParams` was even derived from the observed accepted proposals
(`previous/.specula-output/spec/Trace.cfg`, `Trace.tla:TraceValidParams`), so
the validation decision was never independently checked. This is an
implementation-backed abstraction defect that the update makes decisive; it is
repaired together with the source-driven change.

Granularity chosen: a complete parameter record becomes
`[other |-> <symbolic identity of Block/Evidence/Validator/Version>, veh |->
<integer VoteExtensionsEnableHeight>]`; FinalizeBlock additionally reports
whether `updates.Abci` is non-nil; `ValidateBasic` is `other \in ValidOthers
/\ veh >= 0`; `ValidateUpdate` is transcribed row by row from the new source.
Rejection is split into `UpdateStateRejectedBasic` (`execution.go:617-620`)
and `UpdateStateRejectedVE` (`:622-625`) because the code paths and the
checked inputs differ. Durable boundaries, crash windows, and replay cases are
unchanged and reused.

Old Scenarios whose assumptions need rechecking: Scenario 1 (validation and
installation: directly changed), Scenario 2 (rejection happens after the
response is durable: consequence changes for the newly rejected class), and
Scenario 3 (real/mock final-block replay re-runs the changed validation).
Explicit V0 exclusions (transactions, validator-set changes, Byzantine voting,
app-hash bytes, pruning internals, state sync) remain.

## 4. Update-focused analysis (Chapter 3)

Interactions traced through the explicit draft:

- **Producers of ValidateUpdate's inputs**: `SaveBlock` fixes `h`; the
  application's `FinalizeBlock` fixes `updates`, its `Abci` presence and `U`
  (`execution.go:218-234`); `P` is the in-memory receiver, equal to the
  persisted value at that point (`ValidationInputStable`).
- **Consumers of acceptance**: `CommitApp`, `SaveState` persist the new VEH and
  `LastHeightConsensusParamsChanged = h+1`; the next height's consensus reads it.
- **Consumers of rejection**: `ApplyBlock` returns the error after the response
  is durable; consensus/blocksync panic; startup replay re-runs the same
  decision (real app: `replay.go:409-415`; mock app with the saved response:
  `:417-433`). App-only replay (`ExecCommitBlock`, `:441-489`) never validates
  parameters; it is summarized by `EnvUpdate` in `Update.tla` and discharged.
- **Sibling path**: `ValidateBasic` runs first (`execution.go:617-620`) and
  masks the new row 2.
- **Same mechanism elsewhere**: `ValidateUpdate` has no other production
  caller; the InitChain path (`replay.go:303-363`, parameters at `:346-349`) applies `Update` without
  `ValidateUpdate` and is unchanged by the update.

Scenarios U1-U7 are listed in `modeling-brief.md` §V1-2. Property decisions
and their separating/keep states (constructed, then upgraded with trace states
from both revisions) are in `spec/invariant-evidence.json`.

Code-path inconsistency found during this analysis: rows 3 and 9 accept an
unchanged value, but row 6 rejects the same unchanged value once `P <= h`
(V1-CR-1). Because any rejection here is a permanent halt, this became the
model-checkable question V1-MC-1.

## 5. Outcome

- Validation: prior harness rebased (patch applied cleanly), 6 prior and 13
  update-focused fresh traces, all matched by real TLC trace validation with
  `TraceMatched`; mutation and old-code controls show that the changed decision
  and the new fields are actually checked (`validation-report.md`).
- Model checking: standard and update campaigns completed (bounded). One
  Case C finding: **MC-1** (`UnchangedVENotRejected`) — an application that
  re-sends the unchanged, already reached `VoteExtensionsEnableHeight` (for
  example by forwarding its complete parameter set) is rejected and every
  restart re-rejects the stored block (permanent halt). Reproduced on the
  updated source through `ApplyBlock` and the restart `Handshake`; the exact-old
  control accepts the same input, so the behaviour was introduced by the
  update (`spec/bug-report.md`).
- The update's intended fixes hold in the bounded model and in traces:
  enabling from 0 to a future height (row 7) and cancelling a future height
  (row 5) are accepted; reached heights cannot be disabled or moved; accepted
  changes target future heights.

---

# V0 baseline analysis (retained)


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
