# Harness instrumentation notes (V1, rebased)

The V1 harness is the V0 harness rebased onto the updated source. The V0 patch
(`patches/instrumentation-v0-prior.patch`, sha256 `d9c8c96a…`) applied cleanly
to the updated tree because `internal/state/execution.go` and
`internal/consensus/replay.go` are unchanged by the update. The current patch
(`patches/instrumentation.patch`) keeps every V0 hook and only changes:

1. `internal/speculatrace/trace.go`: parameter values are emitted as
   `{body, veh}` (`ParamRecord`) and update descriptors as
   `{present, body, abciPresent, veh}` (`UpdateRecord`); new helpers
   `BodyValid` and `RejectStage` re-evaluate the real `ValidateBasic` /
   `ValidateUpdate`; `NoParam` is the descriptor `{"present": false}`.
2. `internal/state/execution.go` hooks: `FinalizeBlock` adds
   `proposedBodyValid`; `UpdateStateRejected` adds `stage` and `error`.
3. `internal/consensus/replay.go` hooks: same projection for the handshake
   snapshot and the recovered saved response.
4. Test scenarios: `internal/state/specula_trace_test.go` (V0 apply scenarios
   plus V1 `TestSpeculaTraceApplyVE*`), new
   `internal/consensus/specula_trace_test.go` (`TestSpeculaTraceReplayVEUnchanged`,
   `TestSpeculaTraceReplayMockVEEnable`, with a prefix trace for the
   pre-restart phase and an injected state-save failure wrapper).

Rebuild / rerun: `bash harness/run.sh` from `.specula-output/` (applies the
patch to `artifact/`, builds, runs 18 scenario processes writing 20 traces,
checks structure, and reverses the patch on exit; set
`SPECULA_KEEP_INSTRUMENTATION=1` to keep it applied). To change a field: edit
`speculatrace.LifecycleState`/`ParamRecord`/`UpdateRecord`, re-run, regenerate
the patch with `git add -N <new files> && git diff > harness/patches/instrumentation.patch && git reset`.
Never turn a trace write error into a production error path; never emit
`BlockStored` from a replayed `ApplyBlock`.
