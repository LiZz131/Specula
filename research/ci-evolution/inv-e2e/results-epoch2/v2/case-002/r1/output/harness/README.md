# Trace harness (revision `update`, case-002)

Rebased from the V0 harness (`instrumentation-V0-prior.patch`). One command:

```sh
timeout 3600s bash /work/current/.specula-output/harness/run.sh            # default scenarios
timeout 3600s bash /work/current/.specula-output/harness/run.sh follower-diff-repeat-1   # selected
```

`run.sh` resets `work-source/` (a copy of `artifact/` at commit `update`), applies
`patches/instrumentation.patch`, builds `zookeeper-server` (+deps) with an outer
1200 s timeout, runs each JUnit scenario with an outer 420-600 s timeout, and writes
`traces/<scenario>.ndjson` plus `spec/output/harness/harness-<scenario>.log` and
`run-summary.tsv`. Existing traces are moved aside (`*.superseded.<epoch>`).

| Scenario | JUnit selector | Origin |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | V0 regression |
| follower-diff (+ `follower-diff-repeat-1..3`) | `Zab1_0Test#testNormalFollowerRunWithDiff` | V0 regression; repetitions observe the ACK/fsync order |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | V0 regression |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | V0 regression |
| diff-sync-uncommitted-log | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | update scenario (test added by the update diff) |

Environment: OpenJDK 21 (only JDK present), Maven 3.6.3, dependencies downloaded
into `/work/.cache/m2` (warm-up log `spec/output/build-warmup-pristine.log`).
Observed run: `spec/output/harness-run-2.log` (all scenarios exit 0, nonempty traces).
