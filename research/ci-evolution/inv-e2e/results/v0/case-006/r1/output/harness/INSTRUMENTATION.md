# Specula V1 harness (rebased from the exact-old V0 harness)

Provenance: the V0 harness (`/work/previous/.specula-output/harness`) targeted
`/work/work-source` at the V0 baseline commit. In V1:

- `apply.sh` materializes a clean copy of neutral commit `update`
  (c780d355cfeae6ee6be52c50c1f0bd7d30c6657a) from `artifact/` with
  `git archive` into `build/worktrees/instr-<rev>/` and applies
  `patches/instrumentation.patch`. The artifact tree is never modified.
- The V0 patch applied to the updated tree without drift (only `read_only.go`
  and `raft_test.go` changed). V1 adds probes `HandleReadIndexRequest`,
  `ForwardReadIndex`, `HandleReadIndexResponse`, `BroadcastHeartbeat`, state
  fields `pendingCtxs` and `readStates`, a read-context capture fix, and five
  scenarios (see `instrumentation-spec.md`). `src/` holds standalone copies of
  `specula_trace.go`, `specula_trace_test.go` and the uninstrumented probe test
  `specula_update_probe_test.go`.
- `prepare_deps.sh` builds the GOPATH overlay in `build/gopath` (protobuf
  v1.3.5, x/net v0.7.0, scheduler-only `pkg/testutil` shim). Go 1.27 is run
  with `-vet=off` (old logger printf idiom), GO111MODULE=off.

Commands (from `.specula-output/`):

    bash harness/run.sh        # fresh traces -> traces/*.ndjson, log spec/output/harness-run.log
    bash harness/validate.sh   # SANY + TLC replay of every trace -> spec/output/trace-*.log
    bash harness/controls.sh   # old/new probe controls -> spec/output/controls.log
                               # (last control is expected to FAIL on the baseline)

Adjusting instrumentation: edit the instrumented copy under
`build/worktrees/instr-<rev>/`, regenerate the patch against a clean
`git archive` copy (`git diff` in a scratch repo), copy `specula_trace*.go` to
`src/`, rerun `run.sh` then `validate.sh`. New events need a matching case in
`spec/Trace.tla` `ConsumeCurrent`; new state fields need a comparison in
`ValidateCorePost`/`ValidatePost`.
