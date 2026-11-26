# Specular trace harness (rebased for update 2efbdfc)

`run.sh` copies the updated artifact (`../artifact`, commits `baseline` →
`update`) to `work-source/`, applies `patches/instrumentation.patch`, builds
`zookeeper-server` (and its reactor dependencies) with `-DskipTests`, and runs
the selected JUnit scenarios, each under an outer `timeout` (build 1800 s,
scenario 400 s). Every scenario must write a fresh nonempty NDJSON trace to
`../traces/<scenario>.ndjson`; Maven logs go to `../spec/output/harness-<scenario>.log`
and one summary line per run to `../spec/output/harness-summary.log`.

Scenarios (V0 regression set + one update scenario from the visible diff):

| scenario | test | purpose |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | SNAP sync, NEWLEADER, proposal/commit after NEWLEADER |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | DIFF sync with a buffered proposal logged at NEWLEADER (U1) |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | real election, client writes, shutdown |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | leader abandonment, restart, recovery, SNAP |
| diff-sync-uncommitted-log | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` (added by the update) | uncommitted leader txn transferred by DIFF, NEWLEADER ACK quorum, learner failure at UPTODATE, re-election (U1-U3) |

Commands used in this run:

```sh
# full rebuild from the artifact + all scenarios
timeout 3000s /work/current/.specular-output/harness/run.sh
# reuse the already patched/built work-source (what produced the retained traces)
SPECULAR_REUSE_WORK_SOURCE=1 timeout 3000s /work/current/.specular-output/harness/run.sh
# subset
SPECULAR_SKIP_BUILD=1 SPECULAR_SCENARIOS="follower-diff" harness/run.sh
```

Environment: OpenJDK 21.0.13, Maven 3.6.3, `MAVEN_OPTS=-Dmaven.repo.local=/work/.cache/m2`
(dependencies downloaded from Maven Central). JDK 21 is broader than the
project's preferred JDK 8/11, as in V0.
