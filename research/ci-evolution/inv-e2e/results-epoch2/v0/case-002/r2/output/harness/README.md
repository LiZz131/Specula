# Specular harness (incremental run incr-13b3a238967b)

Rebased from the prior V0 Specula harness (same probes, writer, ID mapping and
JUnit scenarios).  `run.sh` copies `artifact/` (updated source), applies
`patches/instrumentation.patch`, builds `zookeeper-server` with JDK 11
(`/usr/lib/jvm/java-11-openjdk-amd64`, Maven repo `/work/.cache/m2`), and runs
each scenario under a 600 s outer timeout, writing `traces/<scenario>.ndjson`
and `spec/output/harness-<scenario>.log`.

| Scenario | JUnit selector | Origin |
|---|---|---|
| follower-snap | `Zab1_0Test#testNormalFollowerRun` | prior |
| follower-diff | `Zab1_0Test#testNormalFollowerRunWithDiff` | prior |
| quorum-startup-mutation-shutdown | `QuorumPeerMainTest#testQuorum` | prior |
| leader-abandon-restart-recovery | `QuorumPeerMainTest#testEarlyLeaderAbandonment` | prior |
| diff-sync-uncommitted | `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog` | update (test added by the diff) |
| diff-commit-after-newleader | `SpecularUpdateScenariosTest#testCommitAfterNewLeaderForPreNewLeaderProposal` | update (derived from the diff) |
| diff-ack-before-newleader-ack | `SpecularUpdateScenariosTest#testProposalAckBeforeNewLeaderAck` | update (derived from the diff; 1.5 s delay before the NEWLEADER ACK write) |

The two SpecularUpdateScenariosTest tests assert protocol expectations of the
unchanged leader side; a failing assertion is recorded but does not discard the
trace.  Prior traces are archived (immutable copies) in `../traces/archived-v0/`.
JDK: the prior run used JDK 21; this run uses the available JDK 11 (the
manifest's allowed version).

## Reproduction scripts

`harness/repro/test_bug*.sh` run one JUnit reproduction each on the updated tree
(`work/new-clean` = artifact 2efbdfc + test sources, no instrumentation) and on
the old tree (`work/old-src` = baseline 1414ebf) via `harness/repro.sh`.
`SPECULAR_REPRO_TREE=<tree> harness/repro.sh <label> <selector> custom` runs the
same test sources against any other ZooKeeper tree.  Logs:
`spec/output/repro-<label>-<new|old|custom>.log` and `*-surefire-output.txt`;
summary `spec/output/repro-summary.log`.
