# Specula harness (incremental run, rebased from V0)

One command (from anywhere):

```sh
timeout 3300s bash /work/current/.specula-output/harness/run.sh
```

It verifies the artifact is at the neutral `update` commit, applies
`patches/instrumentation.patch` if needed, builds `zookeeper-server`
(`mvn -pl zookeeper-server -am -DskipTests install`, outer timeout 1200 s) and
runs each scenario under an outer timeout, writing `traces/<scenario>.ndjson`
and `spec/output/harness-<scenario>.log`:

| Scenario | JUnit selector | Origin |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | V0 |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | V0 |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | V0 |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | V0 |
| diff-sync-consistency | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | added by the update |
| repro-initial-state-failure | `SpeculaInitialStateFailureReproTest` (copied from `repro/`) | reproduction of MC-2 (expected to FAIL on the buggy code) |

Select scenarios with `SPECULA_SCENARIOS="a b ..."`. The default set is the
first five; the reproduction is run with
`SPECULA_SCENARIOS=repro-initial-state-failure`.

Old-version control (baseline worktree, no instrumentation, no install):
`bash repro/run-old-control.sh [TestSelector] [log-tag]`.

Environment limitation (unchanged from V0): only JDK 21 is available.
