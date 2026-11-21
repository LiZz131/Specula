# Specula incremental harness (case-002, artifact commit `update`)

Rebased from the V0 prior harness (`/work/previous/.specula-output/harness`). One command:

```sh
timeout 6000s /work/current/.specula-output/harness/run.sh
```

It copies `artifact/` (without `.git`) to `harness/work-source`, applies
`patches/instrumentation.patch` (prior patch rebased + update probes + the two update-focused
test classes), builds `zookeeper-server` (and `-am` deps) with JDK 21 under a 1800 s timeout, then
runs each scenario with `mvn ... -Dtest=<selector> test` under a 600 s timeout, writing
`traces/<scenario>.ndjson` (non-empty required) and `spec/output/harness/harness-<scenario>.log`.
Results ledger: `spec/output/harness/harness-results.ndjson`.

Scenarios (fresh on the new revision):

| Scenario | Selector | Origin | Expected test outcome |
|---|---|---|---|
| follower-snap | Zab1_0Test#testNormalFollowerRun | V0 regression | pass |
| follower-diff | Zab1_0Test#testNormalFollowerRunWithDiff | V0 regression | pass |
| quorum-startup-mutation-shutdown | QuorumPeerMainTest#testQuorum | V0 regression | pass |
| leader-abandon-restart-recovery | QuorumPeerMainTest#testEarlyLeaderAbandonment | V0 regression | pass |
| update-diff-sync-consistency | DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog | test added by the update | pass |
| update-commit-after-newleader | SpeculaSyncUpdateTest#testCommitOfForwardedProposalAfterNewLeader | U-NPE (diff-derived) | observe (fails on new code: NPE) |
| update-newleader-ack-durability | SpeculaSyncUpdateTest#testNewLeaderAckOnlyAfterDiffTxnDurable | U-DUR (diff-derived) | observe (fails: ACK before fsync) |

Environment: only JDK 21 was used (as in V0); Maven Central for build dependencies only
(`MAVEN_OPTS=-Dmaven.repo.local=/work/.cache/m2`).
