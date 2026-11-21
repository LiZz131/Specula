# Confirmation — MC-1

- **Title**: Updated ValidateUpdate rejects an unchanged VoteExtensionsEnableHeight once vote extensions are enabled, halting the chain
- **Source**: MC (actual counterexample, `Update_full.cfg`, invariant `ContractLegalUpdateAccepted`)
- **Novelty**: NEW within the supplied evidence. The task's blindness rules prohibit issue/PR/advisory/upstream-history searches, so no tracker search was performed; the supplied sources (two neutral commits, changed-file snapshots, prior suite) contain no report of this mechanism. The changelog entry added by the update concerns a *different* halt (validation of `VoteExtensionsEnableHeight` in the old rule), which this finding's old-tree control reproduces separately.
- **Status**: **REPRODUCED** (escalation Level 0)
- **Severity**: High (deterministic, all-node chain halt; node cannot restart past the block)
- **Update attribution**: introduced by the update (old tree accepts the same input; see control).
- **Location**: `types/params.go:243-248` (row 6), `types/params.go:229-231` (row 3); consequence `internal/state/execution.go:622-625`, `internal/consensus/state.go:1834-1836`, `internal/consensus/replay.go:408-415`.
- **Source identity**: updated tree = artifact commit `update` `401753b049219c7a8c1c26d5fcc44d7922e2fbc3` (`types/params.go` sha256 `ed9e08e2…`); control = commit `baseline` `9dd6e50860f6f96fd0e05a8b961843dfc4a56bac` (`types/params.go` sha256 `d2333af6…`).

## Phase 1 — Investigation (evidence)

### Code audit

- Entry: consensus `finalizeCommit` → `BlockExecutor.ApplyBlock` (`internal/consensus/state.go:1826-1836`) → `FinalizeBlock` (ABCI, `internal/state/execution.go:219-234`) → `SaveFinalizeBlockResponse` (`:253-256`) → `updateState` (`:279`) → `ConsensusParams.Update` + `ValidateBasic` (`:616-620`) → `ValidateUpdate(abciResponse.ConsensusParamUpdates, header.Height)` (`:622-625`).
- New `ValidateUpdate` (`types/params.go:219-261`): with `c` = current, `u` = updated enable height, `h` = block height, for `u > 0` row 6 returns an error whenever `u <= h`. When vote extensions are enabled (`0 < c <= h`) and the application re-sends `u = c`, row 6 fires. Row 3 only covers `c <= 0 && u == 0`. The function's closed form (verified exhaustively, `spec/output/validate-update-projection.log`) is `accept <=> Abci == nil \/ (u >= 0 /\ ~Enabled(c,h) /\ ~Enabled(u,h))`.
- Old `ValidateUpdate` (`/work/old-source/types/params.go:208-229`) returned `nil` when `c == u` before any height check.
- Reachability: the trigger is an ordinary ABCI response — `FinalizeBlockResponse.ConsensusParamUpdates` with a non-nil `Abci` equal to the current value. The ABCI contract states non-empty sub-records are applied in full and unchanged values must be re-sent (`spec/abci/abci++_app_requirements.md:779-789`), and that the enable height "must not be changed" once non-zero (`:776-777`) — an unchanged re-send is consistent with that. `ConsensusParams.ToProto()` always fills `Abci` (`types/params.go:320-341`); the repository's own state tests build updates as `cp.ToProto()` of a complete parameter value (`internal/state/state_test.go:1044`). Enabling at genesis is documented (`spec/abci/abci++_app_requirements.md:1121-1124`) and used by `internal/test/params.go:12`.
- Safeguards examined: none. There is no caller-side normalization of `ConsensusParamUpdates` before validation; `ValidateBasic` passes; the error path in `ApplyBlock` returns before `Commit`; consensus treats any `ApplyBlock` error as fatal; the replay path re-executes the same block deterministically (mock replay is not selected because the app did not commit).

### Developer-knowledge evidence (supplied sources only)

- The update's new table (`types/params.go:208-218`) and tests (`types/params_test.go`, cases `"current: 100, 100 -> 100"` and `"current: 300, 100 -> 100"` expecting errors) show the new rule deliberately rejects an unchanged value once enabled at the `ValidateUpdate` unit level. The update also deleted the old test `"no error when unchanged"` (initial 100, update 100, height 500 → no error).
- The update's changelog (`.changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md`) describes the change as a fix for "Validation of `VoteExtensionsEnableHeight` can cause chain halt" (not researched further, per blindness rules).
- Intent is recorded as evidence only: the unit tests do not consider the system-level consequence (an `ApplyBlock` error is a chain halt), nor the application contract that invites re-sending unchanged values.

### Known-status

No pre-filter drop: the finding is MC-sourced with an actual counterexample.

## Phase 2 — Reproduction

### Level 0 — black box (real consensus node, real kvstore app)

Test: `spec/repro/test_bugMC1_unchanged_veh_halt_test.go`; runner `spec/repro/run_MC-1.sh` (exports each revision with `git archive` into a scratch directory, copies the test into `internal/consensus`, runs it, removes the scratch tree; the artifact working tree is untouched).

Trigger: single-validator node (`randStateWithAppWithHeight(1, app, 1)`, vote extensions enabled from height 1); the stock `kvstore` application, at height 2, returns `ConsensusParamUpdates{Block: {MaxBytes: default+1, MaxGas: default}, Abci: {VoteExtensionsEnableHeight: 1}}` — a Block change with the Abci sub-record re-sent unchanged. Success criterion: the chain stops committing and the node logs `CONSENSUS FAILURE`. Control scenario: vote extensions disabled at genesis, app enables them at height 4 in block 2.

Command: `spec/repro/run_MC-1.sh` (per revision: `timeout 10m go test -mod=readonly ./internal/consensus -run '^(TestSpeculaReproMC1UnchangedEnableHeight|TestSpeculaReproControlEnableFromZero)$' -count=1 -v`).

Output, updated tree (`spec/repro/output-MC-1-update.log`):

```
rev: update (commit 401753b049219c7a8c1c26d5fcc44d7922e2fbc3)
    specula_repro_mc1_test.go:113: MC-1 unchanged-after-enable: highest committed height=1 (target 4); CONSENSUS FAILURE logged=true
    specula_repro_mc1_test.go:113: MC-1 unchanged-after-enable: E[2026-11-18|18:09:01.527] CONSENSUS FAILURE!!!                         err="failed to apply block; error commit failed for application: updating consensus params: vote extensions cannot be updated to a past or current height, enable height: 1, current height 2"
    specula_repro_mc1_test.go:113: MC-1 unchanged-after-enable: OUTCOME=CHAIN_HALTED
    specula_repro_mc1_test.go:120: control enable-from-zero: highest committed height=5 (target 5); CONSENSUS FAILURE logged=false
    specula_repro_mc1_test.go:120: control enable-from-zero: OUTCOME=CHAIN_PROGRESSED
ok  	github.com/cometbft/cometbft/internal/consensus	15.055s
```

Output, baseline tree — old-version control (`spec/repro/output-MC-1-baseline.log`):

```
rev: baseline (commit 9dd6e50860f6f96fd0e05a8b961843dfc4a56bac)
    specula_repro_mc1_test.go:113: MC-1 unchanged-after-enable: highest committed height=4 (target 4); CONSENSUS FAILURE logged=false
    specula_repro_mc1_test.go:113: MC-1 unchanged-after-enable: OUTCOME=CHAIN_PROGRESSED
    specula_repro_mc1_test.go:120: control enable-from-zero: highest committed height=1 (target 5); CONSENSUS FAILURE logged=true
    specula_repro_mc1_test.go:120: control enable-from-zero: E[2026-11-18|18:09:24.893] CONSENSUS FAILURE!!!                         err="failed to apply block; error commit failed for application: updating consensus params: VoteExtensionsEnableHeight cannot be modified oncethe initial height has occurred, initial height: 0, current height 2"
    specula_repro_mc1_test.go:120: control enable-from-zero: OUTCOME=CHAIN_HALTED
ok  	github.com/cometbft/cometbft/internal/consensus	15.055s
```

Lines demonstrating the bug: the updated tree's `CONSENSUS FAILURE!!! … vote extensions cannot be updated to a past or current height, enable height: 1, current height 2` and `highest committed height=1`. Expected (correct) behavior: the unchanged re-send is accepted and the chain continues (as on the baseline tree, height 4 reached). The control shows the update does fix the old enable-from-zero halt, so the regression is introduced by the update, not pre-existing.

### Restart does not recover (instrumented harness, real code)

`harness/run.sh` scenario `TestSpeculaTraceReplayVEUnchanged` (node start handshake → block 1 with the unchanged echo → restart handshake on the durable stores), `spec/output/harness-replay-ve-unchanged-restart.log`:

```
block 1 ApplyBlock error: commit failed for application: updating consensus params: vote extensions cannot be updated to a past or current height, enable height: 1, current height 1 (production consensus panics on error, state.go:1834-1836)
restart Handshake error: error on replay: commit failed for application: updating consensus params: vote extensions cannot be updated to a past or current height, enable height: 1, current height 1
```

Its traces (`traces/replay_ve_unchanged_prefix.ndjson`, `traces/replay_ve_unchanged_restart.ndjson`) pass `Trace.tla` validation (`spec/output/trace-v1-replay_ve_unchanged_*.log`), matching the model's consequence witness `Update_reach_LegalUpdateRejectedOnReplay`.

### Match with the counterexample

Same action sequence (`SaveBlock → ApplyBlockStart → FinalizeBlock(abci = current) → SaveFinalizeBlockResponse → UpdateStateRejected("update")`), same violated property (contract-legal update rejected), same root-cause line (row 6, `types/params.go:244-248`). The U1 hunt variant (enable from 0, then re-send at the enable height) is also realized by `traces/apply_ve_unchanged_after_enable.ndjson`.

## Verdict

**REPRODUCED** — live harm (consensus failure, chain halt, unrecoverable restart) triggered through the real consensus/ABCI interfaces with a contract-consistent application response; old-tree control does not halt.

Additional argued (not reproduced) consequence of the same mechanism: a chain that accepted such re-sends under the old binary contains blocks the new binary rejects when re-executing them through `ApplyBlock` (blocksync or final-block replay), so new-binary nodes cannot sync that history.

## Recommendation

Treat `updated.Abci.VoteExtensionsEnableHeight == params.ABCI.VoteExtensionsEnableHeight` as accepted (after the nil/negative checks) before the past/current-height checks, keeping the update's acceptance of first enablement and cancellation of a not-yet-reached height; re-run `Update_full.cfg` and the harness.
