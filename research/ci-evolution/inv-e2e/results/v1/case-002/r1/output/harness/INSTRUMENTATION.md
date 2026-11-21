# Harness instrumentation (rebased)

Patch: `patches/instrumentation.patch` (git diff of `artifact/` against commit
`update`, includes the new file `SpeculaTrace.java`). Rebase notes:

- Only one V0 hunk drifted: `BroadcastReady` followed `zk.startup()` in
  `Learner.syncWithLeader`; it now follows `zk.startServing()` (L:767).
- Capture-timing fixes: `CommitDelivered` before `commitProcessor.commit`
  (FollowerZooKeeperServer.commit); `NewLeaderAckSent` before the ACK write;
  `LeaderCommitted` before `commit(zxid)` in `Leader.tryToCommit`; `ZkStartup`
  before `setState` in `ZooKeeperServer.startupWithServerState`. Rule: a sender
  probe must be emitted before the effect can be observed by another thread.
- New update-local probes: `ZkStartup` (aux = INITIAL/RUNNING),
  `NewLeaderAckSent`, `UpToDateReceived`, `SyncProposalReceived`,
  `SyncCommitReceived` (aux = applied/buffered/ignored) in Learner;
  `NewLeaderAckReceived` (peer = learner) in LearnerHandler; `LeaderProposed`,
  `AckReceived` (peer), `LeaderCommitted` in Leader; `ElectionWon` now carries
  the chosen leader as `peer`; one `config` line per participant (voting members).

Writer: `SpeculaTrace.emit(event, QuorumPeer|ZooKeeperServer, zxid[, peerSid, aux])`,
synchronized, opt-in via `-Dspecula.trace.file`. To add a field, extend the
`emit(String,long,...)` line builder and `Trace.tla`'s `TraceInputOK`/wrapper.
To move a probe, edit the artifact source, then regenerate the patch with
`git -C artifact add -N <new files>; git -C artifact diff > harness/patches/instrumentation.patch`.

Event-to-action mapping: `spec/instrumentation-spec.md`.
