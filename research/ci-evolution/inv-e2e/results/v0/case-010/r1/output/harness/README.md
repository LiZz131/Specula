# Runnable harness (updated source, schema v3)

```bash
SPECULA_TRACE_RUN_ID=<label> bash /work/current/.specula-output/harness/run.sh
```

Verifies `artifact` HEAD = `b16ba7105238d46b0d51e3cc5d92ce9fe16de834`, reapplies `patches/instrumentation.patch`, runs `mvn test-compile` then:

| Trace | Test | Origin |
|---|---|---|
| `traces/election-ordered-<label>.ndjson` | `SpeculaTraceScenarioTest#testElectionAndOrderedMutations` | V0 regression scenario (unchanged driver) |
| `traces/restart-catchup-<label>.ndjson` | `SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup` | V0 regression scenario (unchanged driver) |
| `traces/snap-abort-rejoin-<label>.ndjson` | `QuorumPeerMainTest#testDiffSyncAfterSnap` | test added by the update (visible diff) |

Each Maven invocation has an outer `timeout 15m`; logs go to `spec/output/harness-*-<label>.log`. The script fails unless every trace is nonempty.

Trace validation (one trace):

```bash
cd /work/current/.specula-output/spec
JSON=/work/current/.specula-output/traces/<trace>.ndjson timeout 20m java -cp /work/lib/tla2tools.jar:/work/lib/CommunityModules-deps.jar \
  tlc2.TLC -metadir /dev/shm/specula-e2e-case-010/<fresh> -config Trace.cfg -workers 1 Trace
```

`scripts/validate_trace.sh <trace-basename> <logname>` wraps this, keeps the log in `spec/output/`, and deletes the state directory.
