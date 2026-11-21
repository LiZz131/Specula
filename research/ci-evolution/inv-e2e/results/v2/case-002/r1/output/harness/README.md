# Specula harness (incremental run on the updated source)

`run.sh` applies `patches/instrumentation.patch` to
`/work/current/.specula-output/artifact` (commit `update`
2efbdfc3754df193bce05b9792297c813377cdaf), builds with Maven under a 1500 s
outer timeout, and runs each scenario under its own outer timeout, writing a
fresh NDJSON trace to `../traces/<scenario>.ndjson` and a log to
`../spec/output/update/harness-<scenario>.log`:

| Scenario | JUnit selector | Origin |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | prior regression |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | prior regression |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | prior regression |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | prior regression |
| update-diff-sync-consistency | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | added by the visible diff |
| update-observe-ack-durability | `SpeculaUpdateObservationTest#newLeaderAckPrecedesDurability` | update observation (U1) |
| update-observe-commit-after-newleader | `SpeculaUpdateObservationTest#commitOfStreamedProposalAfterNewLeader` | update observation (U3) |

The observation tests also write `<trace>.observation.json`.
`../old-control/run-old-control.sh` runs the two observation tests unmodified
on the exact-old tree extracted with `git archive baseline` (attribution control).

Environment: JDK 21 (`/usr/lib/jvm/java-21-openjdk-amd64`), Maven 3.6.3,
`MAVEN_OPTS=-Dmaven.repo.local=/work/.cache/m2`.
