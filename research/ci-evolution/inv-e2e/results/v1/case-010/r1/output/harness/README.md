# Rebased trace harness (case-010 update revision)

All paths are relative to `/work/current/.specula-output`.

- `harness/run.sh` — one command: verifies `artifact` HEAD (`b16ba71`), applies `harness/patches/instrumentation.patch` idempotently, and runs each scenario with Maven surefire under `timeout 20m`, writing `traces/<scenario>-<RUN_ID>.ndjson` (refuses to overwrite) and logs under `spec/output/harness/`.
  `SPECULA_TRACE_RUN_ID=v3e harness/run.sh` (scenarios: `election-ordered`, `restart-catchup` = prior regression; `upd-snap-exit-diff` = the update's `QuorumPeerMainTest#testDiffSyncAfterSnap`; `upd-serving-exit`; `upd-snap-complete` = prior restart scenario with `-Dzookeeper.forceSnapshotSync=true`).
- `harness/run-old-control.sh` — same probes on the exact-old revision (`artifact-old`, a detached worktree at `HEAD~1` = `baseline`, created if missing) with the update's test file copied in (`harness/patches/instrumentation-old-control.patch`); traces in `traces/old-control/`.
- `harness/repro-mc1.sh` — asserting reproduction of MC-1's mechanism on both revisions (expected: new FAIL, old PASS).
- `harness/patches/instrumentation-v0-prior.patch` — the prior run's preserved patch (applied cleanly to the new source before rebasing).

Trace validation (example):

```bash
cd spec && JSON=/work/current/.specula-output/traces/upd-snap-exit-diff-v3d.ndjson \
  timeout 10m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -workers 1 -metadir /dev/shm/specula-e2e-case-010/trace-x -config Trace.cfg Trace
```

Old-revision traces use `Trace-prior.cfg` / `Trace-prior-core.cfg` (`LearnerShutdownSemantics = "PRIOR"`). Model checking: `spec/run_tlc.sh <cfg> <module> <minutes> <workers> <label>` (state under `/dev/shm/specula-e2e-case-010/`, removed after each run; log `spec/output/<label>.log`).
