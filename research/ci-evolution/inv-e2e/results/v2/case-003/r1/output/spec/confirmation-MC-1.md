# MC-1 confirmation evidence

**Finding**: re-sending an unchanged, already reached `ABCI.VoteExtensionsEnableHeight`
in `FinalizeBlockResponse.ConsensusParamUpdates` is rejected by the updated
`ConsensusParams.ValidateUpdate` (row 6), so `ApplyBlock` fails and the chain halts.

- Source: model checking (`Update_full.cfg`, invariant `UnchangedVEUpdateNotRejected`,
  13-state counterexample `spec/output/mc/MC-1_Update_full_counterexample.log`).
- Revision under test: artifact commit `401753b` ("update"); control: `9dd6e50` ("baseline").
- Update attribution: introduced by the update (changed row-6 cell; the old first branch
  `params == updated → nil`, old types/params.go:212-214, was removed).

## Reachability (real interface)

| Step | Evidence |
|---|---|
| App returns `ConsensusParamUpdates` whose `Abci` equals the current reached enable height | scripted ABCI app through `proxy.NewLocalClientCreator` and the real `BlockExecutor.ApplyBlock` (`traces/ve_unchanged_after_enable.ndjson`, validated by `Trace.cfg`) |
| `updateState` → `ValidateUpdate` → row 6 error | trace `rejectRule = "r6"`; error text "vote extensions cannot be updated to a past or current height" |
| Crash/restart re-validates and fails again | `traces/replay_real_ve_unchanged_rejected.ndjson` (validated): real `Handshaker.Handshake` → real-app replay → `UpdateStateRejected` → handshake error |

## Reproduction and controls

`spec/repro/MC-1/run.sh <tree>` copies `specula_mc1_repro_test.go` into
`internal/state`, runs `go test` under a 10-minute timeout, and removes it.

Baseline tree re-creation: `mkdir -p controls/old-baseline && (cd artifact && git archive HEAD~1 | tar -x -C ../controls/old-baseline)` (removed after the run; 67 MB).

| Tree | Result | Log |
|---|---|---|
| updated `401753b` (types/params.go sha256 `ed9e08e2…`) | **FAIL** — both tests: "updating consensus params: vote extensions cannot be updated to a past or current height" | `spec/repro/MC-1/repro-updated-401753b.log` |
| baseline `9dd6e50` (types/params.go sha256 `d2333af6…`) | PASS | `spec/repro/MC-1/control-baseline-9dd6e50.log` |

Additional code observation with the same harness on both trees:
`spec/output/observe-old.log`, `spec/output/observe-new.log` (O3, O11, O12).

Consequence: `ApplyBlock` error is fatal in consensus
(`internal/consensus/state.go:1834-1836`), and restart replay re-executes the same
block with the same deterministic response (`internal/consensus/replay.go:403-415`),
so the height can never be committed; all nodes apply the same validation.

## Requirement status

Contested (see `spec/bug-report.md` "Requirement assessment"): protocol text, the
removed V0 unit test and the in-tree complete-params producer pattern support
acceptance; the updated unit test (types/params_test.go:168-169) and table comment
expect rejection. The developer-intent evidence inside the update conflicts with its
stated purpose (fixing validation-caused chain halts).

## Remedy sketch (model-only)

`spec/repro/MC-1/FixSketch.tla` + `FixSketch.cfg`: overriding `ValidateUpdateOK` to also
accept `U = E` makes every reference and update property hold over full `MCNext`
(1,572,122 distinct states, diameter 46; `spec/repro/MC-1/fix-sketch-tlc.log`), i.e.
accepting an unchanged value does not weaken any enable-height safety rule
(`VEHistoryStable`, `VEEnableMonotone`, `StartupLastCommitConsistent`,
`AcceptedVEUpdateRespectsRules`, `PermittedVEUpdateNotRejected`).
