# Rebased case-010 trace harness

One command (bounded: each Maven/JUnit scenario under `timeout 15m`):

    /work/current/.specula-output/harness/run.sh

It verifies the artifact HEAD (`b16ba71`, commit "update"), resets `zookeeper-server/src`, applies the V0 patch and the update probes, then runs:

| Scenario | Test | Trace |
|---|---|---|
| election-ordered (prior) | `SpeculaTraceScenarioTest#testElectionAndOrderedMutations` | `traces/election-ordered-new.ndjson` |
| restart-catchup (prior) | `SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup` | `traces/restart-catchup-new.ndjson` |
| diff-sync-after-snap (update, from the diff) | `QuorumPeerMainTest#testDiffSyncAfterSnap` | `traces/diff-sync-after-snap-new.ndjson` |
| snap-complete (update-focused) | `SpeculaTraceScenarioTest#testForcedSnapSyncCompletes` | `traces/snap-complete-new.ndjson` |

Old-implementation control: `harness/run-old-control.sh` -> `traces/diff-sync-after-snap-oldcontrol.ndjson`.

Trace validation (state below `/dev/shm/specula-e2e-case-010/`, removed after each run):

    cd /work/current/.specula-output/spec
    ./run_trace.sh ../traces/<trace>.ndjson <name> [Trace.cfg|TraceUpdate-new.cfg] [Trace|TraceUpdate]
