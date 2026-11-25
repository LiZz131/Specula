# Specula trace harness — incremental rebase (update revision `2efbdfc`)

Rebased from the exact-old V0 harness (`/work/previous/.specula-output/harness`). Same
strategy (Category A, single NDJSON file per scenario, synchronous opt-in probes,
`-Dspecula.trace.file`), same build/test entry points and JUnit scenarios.

One command (from `.specula-output/`):

```sh
timeout 3600s bash harness/run.sh            # all scenarios
timeout 3600s bash harness/run.sh follower-diff   # one scenario
SKIP_PREPARE=1 bash harness/run.sh ...        # reuse the built tree
```

`run.sh` archives the artifact's current commit into `harness/build/work-source`, applies
`patches/instrumentation.patch` (`git apply --check` first), builds `zookeeper-server`
(`-am`, tests skipped, 1200 s bound) and runs each scenario with a 600 s bound, writing
`traces/<scenario>.ndjson`, `spec/output/harness-<scenario>.log` and a ledger line in
`spec/output/harness-command-results.ndjson`.  JDK 21 (only JDK available).

| Scenario | JUnit selector | Origin |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | prior |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | prior |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | prior |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | prior |
| diff-sync-uptodate-failure | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | **update** (test added by the diff) |

Supplementary reproduction (not part of the regression gate): `repro/run-repro.sh new|old`
runs `repro/StaleTreeReelectionReproTest.java` on the instrumented update tree (traced) or on
the uninstrumented baseline commit `1414ebf` (control).

`trace_inventory.py` prints per-trace event counts and update-window coverage
(`spec/output/trace-inventory.json`).
