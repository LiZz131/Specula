# Harness instrumentation (rebased)

Patch: `patches/instrumentation.patch` (generated against a pristine `git archive` of the
artifact HEAD; the work tree under `build/` is not a git repository).  Writer:
`quorum/SpeculaTrace.java` — synchronized, opens/appends/closes per event, no background
thread, every record carries `aux{zkState,pending,committed,peer,logEpoch,logCounter}`.

Changed relative to the V0 patch:
- `Learner.syncWithLeader`: `BroadcastReady` re-anchored after `zk.startServing()` (old hunk
  after `zk.startup()` no longer applies); new `SyncProposalBuffered`, `SyncCommitBuffered`,
  `SyncCommitApplied`, `NewLeaderAckSent` (after `writePacket(ACK newLeaderZxid)`),
  `UptodateReceived`.
- `ZooKeeperServer.setState` and `QuorumZooKeeperServer.setState` (override without super):
  `ZkServerState`; accessors `speculaStateName/speculaTreeZxid/speculaLogZxid` (no locks).
- `ZooKeeperServer.shutdown(boolean)`: `ZkShutdownSkipped` / `ZkShutdownStarted` /
  `ZkTreeFastForwarded`; `LearnerZooKeeperServer.shutdown`: `ZkShutdownSkipped`, `ZkSyncDrained`.
- `Leader.waitForNewLeaderAck`: `NewLeaderAckCounted`, `NewLeaderAckRejected`;
  `Leader.lead`: `NewLeaderQuorum` before `startZkServer`.
- `QuorumPeer.start`: `DatabaseLoaded` after `loadDataBase` (makes in-process restarts visible).
- `FollowerZooKeeperServer.commit`: `CommitDelivered` moved *before*
  `commitProcessor.commit` (otherwise the CommitProcessor may log `TxnApplied` first).

Rebuild/rerun: edit the work tree, regenerate the patch from a pristine archive (see
`spec/changelog.md`), then `bash harness/run.sh`.  Event-to-spec mapping:
`../spec/instrumentation-spec.md`.
