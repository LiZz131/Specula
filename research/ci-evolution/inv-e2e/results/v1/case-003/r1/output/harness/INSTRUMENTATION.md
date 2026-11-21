# Harness instrumentation notes (V1)

The V0 patch (opt-in `internal/speculatrace` package, hooks at the block
application and handshake/replay boundaries, two apply scenarios) applied to
the updated source without drift. V1 changed only what the updated
`ValidateUpdate` decision needs:

| Change | Where (instrumented tree) |
|---|---|
| Parameter record `{other, veh}` (`ParamRecord`), `OtherValid`, `Proposal` | `internal/speculatrace/trace.go` |
| `LifecycleState` now takes `types.ConsensusParams` and emits `activeOtherValid`, `pendingAbciPresent`, `responseAbciPresent` | `internal/speculatrace/trace.go` |
| FinalizeBlock: `abciPresent`, `proposedOtherValid`; response shadow carries Abci presence | `internal/state/execution.go` (ApplyBlock hooks) |
| UpdateStateRejected: `reason` (`basic` / `update` / `other` from the wrapped error) and `error` | `internal/state/execution.go` |
| Handshake response shadow uses `Proposal` | `internal/consensus/replay.go` |
| Update scenarios `TestSpeculaTraceVE/*`, `TestSpeculaTraceVEEnableThenEcho`, `TestSpeculaTraceVEEchoRestart` | `internal/state/specula_trace_test.go` |

Field-to-variable mapping and trigger points: `../spec/instrumentation-spec.md`.

Adjusting instrumentation: add a field to `LifecycleState` (state) or to the
`msg` map at the hook (event), add the check to `ValidatePostState` or the
wrapper in `Trace.tla`, regenerate the patch with
`git -C artifact add -N <new files> && git -C artifact diff > harness/patches/instrumentation.patch && git -C artifact reset -q`,
then rerun `bash harness/run.sh` and `spec/tools/validate_trace.sh <trace>`.

Rules kept from V0: post-action snapshots, complete parameter identity (no
sampled subfields), reset only at the real `Handshake` entry, no `BlockStored`
from a replayed `ApplyBlock`, and trace write errors never become production
errors.
