# Harness instrumentation notes (case-003 rebase)

The V0 patch applied cleanly to the updated tree (`../spec/output/harness-rebase-check.log`);
it is archived at `patches/prior-v0/instrumentation.v0.patch`. The current
`patches/instrumentation.patch` keeps every V0 hook and trigger point and changes only:

| Change | File (instrumented copy) | Why |
|---|---|---|
| `LifecycleState` takes structured params/update, `rejectRule`, `veHist` | `internal/speculatrace/trace.go` | Trace.tla now compares `[rest, ve]`, update records, the rejection rule and the enable-height history |
| new helpers `SpeculaParam`, `SpeculaUpdate`, `SpeculaVEHistory`, `SpeculaRejectRule` | `internal/state/specula_values.go` (new, opt-in) | map implementation values to the base.tla vocabulary |
| hook arguments updated (same call sites) | `internal/state/execution.go` `ApplyBlock` hooks, `speculaLifecycleState` | emit the new fields at the V0 trigger points; `UpdateStateRejected` records `SpeculaRejectRule(err)` |
| response shadow and snapshots use the helpers | `internal/consensus/replay.go` `Handshake`, `speculaLifecycleState` | same |
| update-focused ApplyBlock scenarios | `internal/state/specula_trace_test.go` (`TestSpeculaTraceVE*`) | rows 4/5/6/7/8/9 + basic, multi-block chains |
| update × crash/recovery scenarios | `internal/consensus/specula_trace_test.go` (`TestSpeculaTraceReplay*`) | mock replay, real replay, real replay of a rejected update |

`observe/specula_observe_test.go` is a self-contained, non-asserting code
observation (no instrumentation dependency) that is copied into a tree, run, and
removed; it was run on the baseline tree (`../controls/old-baseline`, `git archive
HEAD~1`) and on the updated tree (`../spec/output/observe-{old,new}.log`).

Rebuild and rerun: `bash harness/run.sh` from `.specula-output/` (applies the
patch idempotently, then 16 scenarios, each `timeout 10m go test …`).
To adjust a field: change the helper in `specula_values.go` or the argument at the
hook, rerun `run.sh`, and regenerate the patch with
`git add -N <new files> && git diff HEAD > ../harness/patches/instrumentation.patch && git reset -q`
in `artifact/`. `clean.sh` reverses the patch.
