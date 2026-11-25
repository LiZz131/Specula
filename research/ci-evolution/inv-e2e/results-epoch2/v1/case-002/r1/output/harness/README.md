# Specula harness (V1, rebased onto source revision `update`)

`run.sh` is the one-command path: it copies `../artifact` (commit `update`) to
`work-source/`, applies `patches/instrumentation.patch` (V0 probes rebased +
V1 update probes + harness-only tests), builds with JDK 11
(`mvn -pl zookeeper-server -am install -DskipTests`, 2400 s outer timeout) and
runs the selected JUnit scenarios, each under an outer `timeout`, writing one
fresh NDJSON trace per scenario to `../traces/` (fault-injected reproduction
traces go to `../traces/fault-injected-repro/`). Logs:
`../spec/output/incremental/harness/`.

```sh
timeout 7200s harness/run.sh                         # prepare + build + all scenarios
SKIP_PREPARE=1 SCENARIOS="follower-diff" harness/run.sh   # reuse prepared copy
```

| Scenario | Test | Purpose |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | V0 regression (SNAP) |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | V0 regression (DIFF, NEWLEADER logging) |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | V0 regression |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | V0 regression |
| diff-sync-uptodate-failure | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | update's own test (U1/U4 path) |
| follower-diff-bulk-r1..r3 | `SpeculaNewLeaderAckOrderTest` | U1/U3: 7-txn DIFF, which ACK is first, durability at ACK |
| repro-u4-no-restart-r1..r3 | `SpeculaU4ReproTest` | MC-2 reproduction (expected test failure = reproduced) |
| control-diffsync-leaderwait-r1..r2 | `SpeculaDiffSyncControlTest` | attribution control (no fault) |
| repro-u1-stalled-log-r1..r3 | `SpeculaU1ReproTest` | MC-1 reproduction, stalled-disk fault (expected failure) |

Reproduction scenarios fail their JUnit assertion when the defect is
reproduced; `run.sh` therefore exits non-zero for them by design. Old-revision
controls were run from `old-control-source/` (`git archive` of commit
`baseline` plus the harness-only tests, no instrumentation).

JDK: 11 (`/usr/lib/jvm/java-11-openjdk-amd64`). Maven repository:
`/work/.cache/m2` (populated from Maven Central for ordinary build dependencies).
