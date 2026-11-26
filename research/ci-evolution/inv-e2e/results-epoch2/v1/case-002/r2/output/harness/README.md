# Specular incremental harness (case-002, run incr-8c80add29fe2)

Rebased from the V0 prior harness (`/work/previous/.specular-output/harness`). One command applies the
instrumentation to a fresh copy of the updated source, builds it, runs the scenarios and writes fresh traces:

```sh
timeout 2400s /work/current/.specular-output/harness/run.sh            # all scenarios
timeout 900s  /work/current/.specular-output/harness/run.sh follower-diff   # one scenario
```

* Source: `../artifact` (neutral commit `update`, 2efbdfc) copied to `../work-source`, then
  `patches/instrumentation.patch` applied (`git checkout -- . && git clean` first, so reruns are idempotent).
* Build: `mvn -B -pl zookeeper-server -am install -DskipTests -Dmaven.javadoc.skip=true -Dcheckstyle.skip -Dspotbugs.skip`
  (outer `timeout 1500s`; Maven repository `/work/.cache/m2`, online only for ordinary build dependencies).
* Each scenario: `mvn -B -pl zookeeper-server ... -Dspecular.trace.file=<trace> -Dspecular.trace.scenario=<name> -Dtest=<selector> test`
  under `timeout 300s`; traces in `../traces/fresh/`, logs and `harness-results.ndjson` in `../spec/output/incr/harness/`.

| Scenario | Selector | Origin |
|---|---|---|
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | prior |
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | prior |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | prior |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | prior |
| diff-sync-consistency | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | added by the update (visible diff) |

Only JDK 21 is installed (the manifest prefers JDK 8/11); builds and tests pass with it.

Reproduction drivers (Part 4) live in `repro/` and run against *uninstrumented* copies of a tree:
`repro/test_bug1_newleader_ack_durability.sh` (MC-1), `repro/test_bug2_commit_after_newleader.sh` (CR-1, CR-2 probe),
`repro/test_bug3_newleader_ack_order.sh` (CR-3); usage `<label> <source-tree>`.
