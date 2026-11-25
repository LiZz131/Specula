# Instrumentation specification (incremental update revision)

Source: artifact commit `2efbdfc` (`update`), rebased from the exact-old
prior patch. Paths are relative to
`zookeeper-server/src/main/java/org/apache/zookeeper/server/`. The rebased
patch is `../harness/patches/instrumentation.patch`; `../harness/run.sh` applies
it to a fresh archive of the artifact HEAD.

## 1. Trace event schema

Each NDJSON line: `tag="trace"`, `scenario`, process-local `seq`, real
`timeMillis`/`timeNanos`, Java `thread{id,name}`, and `event`:

| Field | Source | TLA+ projection (`Trace.tla`) |
|---|---|---|
| `name` | probe name | selects the wrapper (`TraceNext`) |
| `node` | `QuorumPeer.getId()` / `ZooKeeperServer.getServerId()` | `Node` |
| `zxid`, `txnEpoch`, `txnCounter` | probe zxid | `TxnEntry == [id, epoch, ctr]` / `EvZxid` |
| `state.acceptedEpoch/currentEpoch/role/phase/syncMode` | `QuorumPeer` getters (`-1`/`unknown` for server-only probes) | `ValidateCommonPostState` |
| `aux.zkState` | `ZooKeeperServer.state` of the role instance (`speculaStateName`) | `zkState[Node]` (`ZkMap`) |
| `aux.pending` / `aux.committed` | `Learner.syncWithLeader` `packetsNotCommitted.size()` / `packetsCommitted.size()` | `Len(pending'[Node])` / `Len(syncCommits'[Node])` |
| `aux.peer` | sid whose NEWLEADER ACK the leader counted/rejected | `nlAcks[Node]` |
| `aux.logEpoch/logCounter` | `FileTxnSnapLog.getLastLoggedZxid()` (txn-log tail on disk) | `LastZ(durable'[Node])` lower bound check |

`aux` is present on every record (`-1`/`none`/`unknown` when not captured).

## 2. Action-to-code mapping

Prior probes (unchanged unless noted):

| Spec action / effect | Location and trigger | Event |
|---|---|---|
| election role decision | `quorum/FastLeaderElection.setPeerState`, after assignment | `ElectionWon` |
| public role (tree zxid) | `quorum/QuorumPeer.setPeerState`, after assignment; zxid = `getLastLoggedZxid()` = DataTree position | `PeerRoleChanged` |
| public phase (tree zxid) | `quorum/QuorumPeer.setZabState` | `PhaseChanged` |
| `AcceptEpoch` | `QuorumPeer.setAcceptedEpoch` after file write | `AcceptedEpochPersisted` |
| `LearnerNewLeaderPersist` / `FinishDiscovery` | `QuorumPeer.setCurrentEpoch` after file write | `CurrentEpochPersisted` |
| registration | `quorum/Learner.registerWithLeader` after ACKEPOCH | `FollowerRegistered` |
| `SyncWithLeader` mode / `LearnerNewLeaderStartup` (NONE) | `QuorumPeer.setSyncMode` | `SyncModeChanged` |
| `SyncWithLeader` directive | `Learner.syncWithLeader` after mode handling | `SyncSelected`, `SnapshotInstalled` |
| `LearnerLogPendingOne`, `LearnerUptodateLogOne`, `ReceiveProposal` | `quorum/FollowerZooKeeperServer.logRequest` after `pendingTxns.add` | `ProposalQueued` |
| `AppendOne` | `SyncRequestProcessor.run` after append | `TxnAppended` |
| `FsyncOne` | `SyncRequestProcessor.flush` after `ZKDatabase.commit` | `TxnDurable` |
| `LearnerUptodateCommitOne`, `ReceiveCommit` | `FollowerZooKeeperServer.commit` after commit-processor enqueue | `CommitDelivered` |
| `ApplyOne` | `ZooKeeperServer.processTxn(Request)` after DB apply | `TxnApplied` |
| UPTODATE serving (rebased) | `Learner.syncWithLeader` after `zk.startServing()` (was after `zk.startup()`) | `BroadcastReady` |

New update-window probes (densified around the changed code):

| Spec action / effect | Location and trigger | Event | Fields checked |
|---|---|---|---|
| `SyncWithLeader` buffer (producer) | `Learner.syncWithLeader` case PROPOSAL after `packetsNotCommitted.add` | `SyncProposalBuffered` | zxid = buffered entry, `aux.pending` |
| `SyncWithLeader`/`ReceiveCommit` buffer | case COMMIT after `packetsCommitted.add` | `SyncCommitBuffered` | zxid, `aux.committed` |
| `ReceiveCommit` (non-txn-log branch) | case COMMIT after `processTxn` + `remove` | `SyncCommitApplied` | zxid |
| `LearnerSendNewLeaderAck` (affected) | case NEWLEADER after `writePacket(ACK newLeaderZxid)` | `NewLeaderAckSent` | `aux.pending` (must be 0), `aux.committed`, `aux.zkState` (INITIAL) |
| `LearnerNewLeaderStartup`/`LearnerUptodateStartServing` (affected) | `ZooKeeperServer.setState` after assignment | `ZkServerState` | `aux.zkState` |
| UPTODATE receipt (affected) | case UPTODATE at entry | `UptodateReceived` | `aux.pending`, `aux.committed` |
| `ServerShutdown`, non-running (interaction) | `ZooKeeperServer.shutdown(boolean)` and `quorum/LearnerZooKeeperServer.shutdown` when `!canShutdown()` | `ZkShutdownSkipped` | tree zxid, `aux.zkState`, log tail |
| `ServerShutdown`, running | `ZooKeeperServer.shutdown(boolean)` after guard | `ZkShutdownStarted` | tree zxid, log tail |
| fast-forward | `ZooKeeperServer.shutdown(boolean)` after `fastForwardDataBase` | `ZkTreeFastForwarded` | tree zxid, log tail |
| follower drain | `LearnerZooKeeperServer.shutdown` after `syncProcessor.shutdown()` | `ZkSyncDrained` | log tail |
| leader counts ACK (consumer) | `quorum/Leader.waitForNewLeaderAck` after `addAck(sid)` | `NewLeaderAckCounted` | `aux.peer` |
| leader rejects ACK | same, zxid-mismatch branch | `NewLeaderAckRejected` | `aux.peer`, zxid |
| `LeaderStartZkServer` | `Leader.lead` after `waitForNewLeaderAck` returns, before `startZkServer` | `NewLeaderQuorum` | ack-set quorum |
| process restart (`Crash`;`Restart`) | `QuorumPeer.start` after `loadDataBase()` | `DatabaseLoaded` | tree zxid = `LastLogged`, log tail selects the restored disk prefix |

## 3. Special considerations

- Writer: synchronized open/append/close per event; no background thread; no
  new lock is taken by probes (`speculaStateName` is a volatile read).
- `Zab1_0Test` follower conversations use a scripted leader; `Trace.tla`
  seeds that fixture leader as an established epoch-1 leader and maps the
  fixture's LOOKING role to FOLLOWING for those scenarios only.
- `ZkServerState` is emitted for every ZooKeeperServer instance including
  leaders and standalone helpers inside tests; nodes outside `Server` are
  rejected by `TraceInputOK`.
- Mandatory update checks: `NewLeaderAckSent` requires the model's pending
  buffer to be empty and the server state INITIAL; every `ProposalQueued`
  between NEWLEADER and the ACK must equal the head of the buffered sync
  proposals (`LearnerLogPendingOne`).
