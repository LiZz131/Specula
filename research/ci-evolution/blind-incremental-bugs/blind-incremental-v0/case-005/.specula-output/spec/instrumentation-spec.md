# Trace instrumentation specification

## Schema and ordering

`SpeculaTrace.emit` writes one synchronized, process-wide NDJSON record per
marker and flushes it immediately:

```json
{"tag":"trace","ts":0,"event":{"name":"ServerStart","nid":"s0","peer":"","state":{"zxid":0,"epoch":0,"acceptedEpoch":0,"role":"LOOKING","mode":"NONE"}}}
```

Required fields are `tag`, monotonic observation timestamp `ts`, event `name`,
node `nid`, optional peer id `peer`, and the event state fields `zxid`, `epoch`,
`acceptedEpoch`, `role`, and `mode`. Normalization adds `modelZxid` without
removing or changing the native zxid. `Trace.tla` checks all state fields where
the source marker defines them; unavailable fields use the emitted sentinel
`-1`, and ordinary non-sync events require mode `NONE`.

## Marker-to-transition map

| Marker | Exact-old producer boundary | Trace operator |
|---|---|---|
| ServerStart / ServerCrash | `QuorumPeer.start`, `shutdown` | `TraceStart`, `TraceCrash` |
| ElectionDecision | `FastLeaderElection.lookForLeader` return paths | `TraceElection` |
| EpochSupportReceived | `Leader.getEpochToPropose` | `TraceEpochSupport` |
| AcceptedEpochMemory / AcceptedEpochPersist | leader/learner epoch selection and `QuorumPeer.setAcceptedEpoch` | `TraceAcceptedMemory`, `TraceAcceptedPersist` |
| AckEpochSent / EpochAckAccepted | learner registration and `Leader.waitForEpochAck` | `TraceAckEpochSent`, `TraceEpochAck` |
| CurrentEpochMemory / CurrentEpochPersist | discovery completion and `QuorumPeer.setCurrentEpoch` | `TraceCurrentMemory`, `TraceCurrentPersist` |
| LeaderInfoSent / NewLeaderSent | `LearnerHandler.run` protocol sends | `TraceLeaderInfo`, `TraceNewLeaderSent` |
| SyncModeSelected / SyncModeApplied | `LearnerHandler.syncFollower`, `Learner.syncWithLeader` | `TraceSyncSelected`, `TraceSyncApplied` |
| SyncProposalReceived / SyncCommitApplied | learner synchronization packet loop | `TraceSyncProposal`, `TraceSyncCommit` |
| BootstrapSnapshot | learner post-sync snapshot boundary | `TraceBootstrapSnapshot` |
| NewLeaderAckReceived | `Leader.waitForNewLeaderAck` | `TraceNewLeaderAck` |
| LeaderBroadcastReady | `Leader.lead` after NEWLEADER quorum | `TraceLeaderReady` |
| UpToDateSent / FollowerBroadcastReady | leader send and learner sync completion | `TraceUpToDate`, `TraceFollowerReady` |
| Proposal / ProposalReceived | `Leader.propose`, `Follower.processPacket` | `TraceProposal`, `TraceProposalReceived` |
| LogAppend / LogDurable | `SyncRequestProcessor.run` append/commit | `TraceAppend`, `TraceDurable` |
| AckSent / AckReceived | `SendAckRequestProcessor`, `Leader.processAck` | `TraceAckSent`, `TraceAckReceived` |
| Commit | leader commit or follower commit receipt | `TraceCommit` |
| Apply | `FinalRequestProcessor.processRequest` | `TraceApply` |

The precise changes, including `build.xml` propagation of
`specula.trace.file`, are stored in `harness/patches/instrumentation.patch`.
The two added source files are stored separately under `harness/src/` and are
copied by the idempotent `harness/apply.sh`.

## Reproduction and consumption

`harness/run.sh NAME` applies the recorded instrumentation, runs only the
neutral exact-old JUnit scenario under a 300-second outer timeout, records the
command/exit code, preserves raw bytes under `traces/original/`, and emits the
normalized `traces/NAME.ndjson`. `harness/validate-suite.sh` enumerates every
normalized retained trace. The test covers startup, election, mutation,
follower shutdown/catch-up, complete shutdown/restart, durable recovery, and a
post-recovery mutation.

