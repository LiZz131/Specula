# Specula instrumentation specification — schema v3 (updated source)

Rebased from the V0 specification (V0 text preserved in `/work/previous/.specula-output/instrumentation-spec.md`). Category A: one mutex-serialized NDJSON file per scenario; `SpeculaTrace` is dormant unless `-Dspecula.trace.file` is set. Patch: `harness/patches/instrumentation.patch` (applies to `artifact/` at `update` b16ba71). The V0 patch is kept as `harness/patches/prior-v0-instrumentation.patch`; it applied cleanly to the update (`git apply --check`), and every V0 probe is retained unchanged.

## Envelope

```json
{"tag":"trace","schemaVersion":3,"ts":<System.nanoTime>,"event":{"name":"<Action>","nid":"s<id>","state":{...},"msg":{...}}}
```

`state` always has `running`, `role`, `phase`, `syncMode`, `acceptedEpoch`, `currentEpoch` (read from `QuorumPeer` under the probe lock) and `Trace.tla` checks all six on every event.

Schema-v3 real-object fields (mandatory where listed; `Trace.tla` requires their presence and compares them):

| Field | Source | Model comparison |
|---|---|---|
| `memInit` | `QuorumPeer.getZkDb().isInitialized()` | `memInit'[s]` |
| `memLast` | `ZKDatabase.getDataTreeLastProcessedZxid()` floor-mapped to the dense id of the largest modeled txn zxid <= it (0 if none) | `LastOf(memDb'[s])` |
| `durableLast` | `max(FileTxnSnapLog.getLastLoggedZxid(), zxid of findMostRecentSnapshot())`, floor-mapped | `LastOf(durable'[s])` |

Dense ids are assigned at first observation of a modeled (`create`, `create2`, `delete`, `setData`) zxid, which is `Leader.propose`; session/other txns are invisible to the model, hence the floor mapping.

## Event map

V0 events (unchanged trigger points; see V0 table): `RestartLoadDatabase`, `GracefulShutdown`, `FinishElection`, `SetPeerState`, `SetZabState`, `PersistAcceptedEpoch`, `PersistCurrentEpoch`, `ChooseSyncMode`, `CompleteLearnerSync`, `FormNewLeaderQuorum`, `LeaderPropose`, `FollowerPendingProposal`, `QueueForSync`, `FlushTxnLog`, `RecordProposalAck`, `CommitProposal`, `FollowerCommit`, `ApplyTxn`, `BeginSnapshot`, `FinishSnapshot`.

Changed/added (update-local densification):

| Event | Code point (after patch) | Trace.tla action | Extra fields checked |
|---|---|---|---|
| `RestartLoadDatabase` | `QuorumPeer.loadDataBase` after epoch checks (process start **and** in-process reload after `zkDb.clear()`) | `RestartLoadDatabase` if the peer is not running in the model, else `ReloadDatabase` | `memInit`, `memLast`, `durableLast` |
| `ObserveReportedZxid` | `Learner.registerWithLeader` right after writing ACKEPOCH (`lastLoggedZxid` = value sent) | stutter observation; also `RecordEpochAck` while the leader is collecting | `msg.zxid = LastZxid(s)`, `memInit`, `memLast` |
| `LearnerApplySnapshot` | `Learner.syncWithLeader` SNAP branch after `setlastProcessedZxid` | `LearnerApplySnapshot` | `memInit`, `memLast` |
| `LearnerTruncateLog` | TRUNC branch after `setlastProcessedZxid` | `LearnerTruncateLog` | `memInit`, `memLast`, `durableLast` |
| `LearnerSyncPacket` | PROPOSAL case after `packetsNotCommitted.add` | `LearnerSyncPacket(s, tx)` | `msg.tx` = next leader txn |
| `LearnerSyncCommit` | COMMIT case: after `processTxn` (`inMemory=true`) or after `packetsCommitted.add` (`inMemory=false`) | `LearnerSyncCommit` | `msg.inMemory` = (mode in {SNAP,TRUNC} and before NEWLEADER), committed id, `memInit`, `memLast` |
| `LearnerSyncSnapshot` | NEWLEADER after `zk.takeSnapshot(syncSnapshot)` (generic snapshot probes suppressed for this call) | `LearnerSyncSnapshot` | `memInit`, `memLast`, `durableLast` |
| `AckNewLeader` | NEWLEADER immediately before writing ACK(newLeaderZxid) | `LearnerAckNewLeader` | — |
| `LearnerUpToDate` | after `zk.startServing()` | `LearnerUpToDate` | `memInit`, `memLast` |
| `LearnerShutdown` | `Learner.shutdown` after `zk.shutdown(full)`; the boolean is evaluated into a local first (no semantic change) | `LearnerShutdown` | `msg.fullyShutDown` = (`syncMode`==SNAP), `msg.zkWasRunning` = model `syncComplete`, `memInit`, `memLast` |
| `ApplyTxn` | unchanged point | `ApplyTxn` | `memInit`, `memLast` added |

`SetPeerState(LOOKING)` of a follower whose learner already shut down maps to `FollowerExitToLooking`; `SetZabState(ELECTION)` of a LOOKING peer maps to `EnterElectionPhase`; leader `SetZabState(SYNCHRONIZATION)` maps to `LeaderStartSyncCore`; leader `PersistAcceptedEpoch` maps to `LeaderPersistEpoch`; follower `PersistCurrentEpoch` during SYNCHRONIZATION maps to `LearnerPersistCurrentEpoch`; `ChooseSyncMode(NONE)` maps to `LearnerNewLeaderModeNone`.

## Fidelity limits

- Histories are compared through their last element (`memLast`, `durableLast`) plus the action guards that fix order (stream position, FIFO queues); full sequences are not observable from real objects without shadow bookkeeping.
- `AckNewLeader` is emitted before the socket write so that the leader's quorum event cannot precede it in the serialized file; a failed write would leave an over-approximate ack.
- Epoch ACK collection by the leader is not probed; the leader's own epoch event and `ObserveReportedZxid` stand in for it in `Trace.tla`, and the leader's `PersistCurrentEpoch`/`SetZabState` are replayed through generic or core forms without the quorum guard.
